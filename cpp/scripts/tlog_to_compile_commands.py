#!/usr/bin/env python3
"""MSVC tlog → compile_commands.json（MSBuild 工程的编译数据库重建）。

背景：MSBuild（.vcxproj）工程没有原生的 compile_commands.json 导出 —— 这是 DEC M0
的 P-4 阻塞。但 FileTracker 的 CL.command.1.tlog 里每条 cl.exe 命令行完整，
可从中无损重建编译数据库，供 clang-tidy / dec 工具链消费。

输入格式（CL.command.1.tlog）：UTF-16LE 或 UTF-8（自动识别），行对结构：
    ^<源文件全路径>
    <该源文件的完整 cl 命令行>
命令行内不含程序名（MSBuild 省略了工具路径），目录以 ^ 行为准。

转换规则：
  1. 驱动固定为 clang-cl（clang tooling 据此按 MSVC 模式解析参数）；
  2. 剔除 clang-cl 不支持/与分析无关的参数：/ZI /JMC /RTC1 /Gm- /nologo /FC
     及 /Fo /Fd /Fp /Yc /Yu 输出与预编译头参数（本项目无 PCH，/Yu 未出现仍防御性剔除）；
  3. 保留 /D /I /std: /permissive- /W* /WX- /EHsc /MDd /GS /Gd /fp: /Zc: /external: 等；
  4. 若运行环境已导入 vcvars（INCLUDE 环境变量存在），默认把 INCLUDE 各目录作为
     /I 烘焙进每条记录，使产物脱离 vcvars 环境亦可被 clang tooling 使用
     （--no-env-include 关闭）；
  5. 同一源文件多次出现时保留首条（一个 tlog 目录对应一种配置）。

产物 schema 与 dec.compilation.validate_database 对齐：directory（绝对路径）/
file/arguments 三键。注意：该脚本只做文本级转换，**不在本机验证头文件可解析性**；
首次使用建议在 vcvars 环境对单个 TU 跑 clang-tidy 冒烟。

用法：
    python tlog_to_compile_commands.py <CL.command.1.tlog> -o compile_commands.json
    python tlog_to_compile_commands.py <CL.command.1.tlog> -o out.json --no-env-include
"""
from __future__ import annotations

import argparse
import json
import ntpath
import os
import re
import sys
from pathlib import Path

CC_EXT = {".c", ".cpp", ".cc", ".cxx", ".c++"}
TOKEN_RE = re.compile(r'"[^"]*"|\S+')
# 精确剔除（小写比较）：编辑续传/运行时检查/最小重建/诊断路径修饰等 clang-cl 不需要或会告警的参数
DROP_EXACT = {"/zi", "/jmc", "/rtc1", "/gm-", "/gm", "/nologo", "/fc", "/fs", "/mp"}
# 前缀剔除：输出路径与预编译头参数（/Fo".." /Fd".." /Fp".." /Yc".." /Yu".."）
# 注意 /fp:precise 是浮点模型开关必须保留，只有 /Fp 后接路径才是 PDB 参数
DROP_PREFIX = ("/fo", "/fd", "/fp\"", "/yc", "/yu", "/link")


def keep_token(tok: str) -> bool:
    low = tok.lower()
    if low in DROP_EXACT:
        return False
    if low.startswith(DROP_PREFIX):
        return False
    return True


def read_text_guess(path: Path) -> str:
    raw = path.read_bytes()
    if raw.startswith(b"\xff\xfe"):
        return raw.decode("utf-16-le", errors="replace")[1:]  # 去 BOM 字符
    if raw.startswith(b"\xef\xbb\xbf"):
        return raw.decode("utf-8-sig")
    try:
        return raw.decode("utf-16-le")
    except UnicodeDecodeError:
        return raw.decode("utf-8", errors="replace")


def pairs(lines: list[str]) -> list[tuple[str, str]]:
    """按 '^源文件 + 命令行' 行对抽取；无源文件前缀的命令行丢弃并计数。"""
    out: list[tuple[str, str]] = []
    current: str | None = None
    for line in lines:
        if line.startswith("^"):
            current = line[1:].strip()
        elif line.strip() and current:
            out.append((current, line.strip()))
            current = None
    return out


def filter_flags(command: str) -> tuple[list[str], list[str]]:
    kept: list[str] = []
    dropped: list[str] = []
    for tok in TOKEN_RE.findall(command):
        if not keep_token(tok):
            dropped.append(tok)
        else:
            kept.append(tok)
    return kept, dropped


def env_include_flags() -> list[str]:
    include = os.environ.get("INCLUDE", "")
    flags: list[str] = []
    for d in include.split(";"):
        d = d.strip()
        if d:
            flags.append('/I"' + d + '"' if " " in d else "/I" + d)
    return flags


def convert(tlog: Path, out: Path, bake_env_include: bool) -> int:
    entries: dict[str, dict] = {}
    dropped_stat: dict[str, int] = {}
    skipped_ext = 0
    inc_flags = env_include_flags() if bake_env_include else []

    for source, command in pairs(read_text_guess(tlog).splitlines()):
        if Path(source).suffix.lower() not in CC_EXT:
            skipped_ext += 1
            continue
        kept, dropped = filter_flags(command)
        # 命令行末尾自带源文件回显，去掉，避免与末尾追加的 source 重复
        kept = [t for t in kept if t.lower() != source.lower()]
        for d in dropped:
            key = d.split("=")[0].split('"')[0].lower()
            dropped_stat[key] = dropped_stat.get(key, 0) + 1
        args = ["clang-cl"]
        if inc_flags:
            existing = {t.lower() for t in kept if t.lower().startswith("/i")}
            args += [f for f in inc_flags if f.lower() not in existing]
        args += kept
        args.append(source)
        key = source.lower()
        if key in entries:
            continue
        entries[key] = {
            "directory": ntpath.dirname(source),  # 输入恒为 Windows 路径，必须用 ntpath（POSIX 上 os.path 不认反斜杠）
            "arguments": args,
            "file": source,
        }

    database = list(entries.values())
    out.write_text(json.dumps(database, ensure_ascii=False, indent=1), encoding="utf-8")

    print(f"== 源 TU 命令行: {len(pairs(read_text_guess(tlog).splitlines()))} 条")
    print(f"== 写入条目: {len(database)}（去重后；非 C/C++ 跳过 {skipped_ext} 条）")
    print(f"== 烘焙 INCLUDE 目录: {len(inc_flags)} 个" + ("（--no-env-include 已关闭）" if not bake_env_include else ""))
    if dropped_stat:
        print("== 剔除参数统计: " + ", ".join(f"{k}×{v}" for k, v in sorted(dropped_stat.items())))
    if database:
        sample = database[0]
        print("== 首条样例:")
        print("   file:", sample["file"])
        print("   args:", " ".join(sample["arguments"][:8]) + " ...")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="MSVC CL.command.1.tlog → compile_commands.json")
    ap.add_argument("tlog", type=Path, help="CL.command.1.tlog 路径")
    ap.add_argument("-o", "--output", type=Path, required=True, help="输出 compile_commands.json 路径")
    ap.add_argument("--no-env-include", action="store_true",
                    help="不把 INCLUDE 环境变量烘焙为 /I（默认烘焙，若该变量存在）")
    ns = ap.parse_args()
    if not ns.tlog.is_file():
        print(f"错误: tlog 不存在: {ns.tlog}", file=sys.stderr)
        return 2
    return convert(ns.tlog, ns.output, not ns.no_env_include)


if __name__ == "__main__":
    sys.exit(main())
