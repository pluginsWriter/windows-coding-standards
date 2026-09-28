#!/usr/bin/env bash
# scan-macos-traces.sh —— macOS 遗留痕迹机械扫描（候选生成器，不是结论生成器）
#
# 用法:     scan-macos-traces.sh <源码目录> <输出.tsv>
# 运行环境: Windows Git Bash / WSL / macOS bash（只用 grep/awk/sed/find；bash 3.2 兼容）
# 输出:     TSV 四列：类别 / 文件 / 行号 / 匹配内容
#           每一行都是"候选"，必须经 agent 分诊（五道门）后才能进 findings.tsv。
# 原则:     只读不改任何源码；CRLF 仅计数（Windows 上 CRLF 是常态，不算发现）。

set -uo pipefail
set -f                     # 防止 include 模式里的 * 被 glob 展开
export LC_ALL=C

SRC="${1:?用法: scan-macos-traces.sh <源码目录> <输出.tsv>}"
OUT="${2:?缺少输出 TSV 路径}"
[ -d "$SRC" ] || { echo "错误: 源码目录不存在: $SRC" >&2; exit 2; }
SRC=$(cd "$SRC" && pwd -P)   # 规范为 POSIX 绝对路径，避免盘符冒号破坏 file:line 解析
: > "$OUT" 2>/dev/null || { echo "错误: 输出文件不可写: $OUT" >&2; exit 2; }

INC="--include=*.h --include=*.hpp --include=*.cc --include=*.cpp --include=*.cxx --include=*.c --include=*.inl --include=*.m --include=*.mm --include=*.inc --include=CMakeLists.txt --include=*.cmake"

# 默认排除目录：第三方库/构建产物/IDE 元数据（真机实测 third_party 占候选 27%，纯噪声）。
# GNU/BSD grep 的 --exclude-dir 按目录名匹配任意层级；find 类检查用 EXD_RE 过滤路径段。
EXD="--exclude-dir=third_party --exclude-dir=3rdparty --exclude-dir=thirdparty --exclude-dir=external --exclude-dir=vendor --exclude-dir=deps --exclude-dir=build --exclude-dir=_build --exclude-dir=out --exclude-dir=bin --exclude-dir=obj --exclude-dir=.git --exclude-dir=.vs --exclude-dir=x64 --exclude-dir=Debug --exclude-dir=Release --exclude-dir=node_modules"
EXD_RE='/(third_party|3rdparty|thirdparty|external|vendor|deps|build|_build|out|bin|obj|\.git|\.vs|x64|Debug|Release|node_modules)/'

# emit <类别>：stdin 读 grep -rIn 输出（file:line:content），拆列追加到 OUT
emit() {
  awk -v c="$1" '
    { p1 = index($0, ":"); if (!p1) next
      f = substr($0, 1, p1 - 1); rest = substr($0, p1 + 1)
      p2 = index(rest, ":"); if (!p2) next
      ln = substr(rest, 1, p2 - 1); txt = substr(rest, p2 + 1)
      if (ln ~ /^[0-9]+$/) print c "\t" f "\t" ln "\t" txt }'
}

scan() { # scan <类别> <ERE 正则>
  grep -rInE $INC $EXD "$2" "$SRC" 2>/dev/null | emit "$1" >> "$OUT"
}

# ---- 1 ObjC 语法残留 ----
scan objc_syntax   '@(implementation|interface|end|selector|property|synchronized)[^A-Za-z]|objc_msgSend|#import[[:space:]]*[<"]'

# ---- 2 Apple/Cocoa 符号 ----
# 前缀后要求「大写+小写」（CamelCase 第二字母小写），排除 UINT/UINT_MAX/UINT32 等
# Windows/C 全大写类型（真机实测见 findings-master F-003）。
scan apple_symbols '\b(NS|CF|CG|UI)[A-Z][a-z][A-Za-z0-9_]*|dispatch_(async|sync|after|once|get_main|main_queue)|\bCF(Release|Retain|StringCreate)\b|\bNSBundle\b'

# ---- 3 Apple 专有头文件（含 <Foundation/Foundation.h> 这类框架子路径） ----
scan apple_headers '<(Foundation|AppKit|UIKit|Cocoa|IOKit|CoreFoundation|CoreGraphics|CoreData|CoreAnimation|CoreAudio|CoreImage|dispatch)/'

# ---- 4 平台守卫（潜在死分支） ----
# 注：grep 按行处理，类里不需要也不应该写 \n（GNU/BSD grep 对 [^"\n] 解释不一，会静默漏检）
scan apple_guards  '#(el)?if(def|ndef)?.*__APPLE__|#(el)?if.*TARGET_OS_|#(el)?if.*TARGET_CPU_ARM'

# ---- 5 POSIX/Unix 专有 API ----
scan posix_api     '\bpthread_[a-z_]+|\bsem_(wait|post|trywait|init|destroy)\b|\bclock_gettime\b|\bmach_absolute_time\b|\bkqueue\b|\bfork[[:space:]]*\('

# ---- 6 POSIX 路径与 bundle 概念 ----
scan posix_paths   '"/usr/|"/Library/|"/System/|"/var/|~/Library|/Contents/MacOS|\.framework["/ ]|\.app/|\.plist["/ ]|\.icns["/ ]|\.dylib\b|\.dsym\b'

# ---- 7 Apple 构建/测试体系残留 ----
scan build_residue 'xcodeproj|xcworkspace|codesign[[:space:]]|XCTest|\.xib["/ ]|\.storyboard["/ ]|xcode-select'

# ---- 8 注释里的 mac 线索（低置信，只扫 TODO/FIXME/HACK/XXX 行） ----
scan comment_traces '(TODO|FIXME|HACK|XXX)[^"]*([Mm]ac([Oo][Ss])?[ :]|darwin|Darwin|OS[ ]?X)'

# ---- 9 include 大小写不匹配 ----
# 原理：以「不区分大小写」方式找到实际文件后，与「区分大小写」的期望路径做字符串比对。
# 这样在大小写不敏感文件系统（Windows NTFS / macOS APFS 默认）上也能发现拼写不一致——
# 这类 include 在 Windows 上能编过，到了大小写敏感环境（Linux CI / 他人 clone）直接编译失败。
check_include_case() {
  grep -rIn '#[[:space:]]*include[[:space:]]*"' $INC $EXD "$SRC" 2>/dev/null \
  | while IFS= read -r line; do
      f=${line%%:*}; rest=${line#*:}; ln=${rest%%:*}
      inc=$(printf '%s' "$line" | sed -n 's/.*#[[:space:]]*include[[:space:]]*"\([^"]*\)".*/\1/p')
      [ -z "$inc" ] && continue
      case "$inc" in
        /*|*:*) continue ;;            # 绝对路径 / 带盘符，跳过
      esac
      for base in "$(dirname "$f")" "$SRC"; do
        tdir=$(cd "$base/$(dirname "$inc")" 2>/dev/null && pwd -P) || continue
        bname=$(basename "$inc")
        hit=$(find "$tdir" -maxdepth 1 -iname "$bname" -print 2>/dev/null | head -1)
        if [ -n "$hit" ] && [ "$hit" != "$tdir/$bname" ]; then
          printf 'include_case_mismatch\t%s\t%s\t%s（磁盘实际拼写: %s）\n' "$f" "$ln" "$inc" "$hit"
          break
        fi
      done
    done >> "$OUT"
}
check_include_case

# ---- 10 ObjC 源文件本身 ----
find "$SRC" -type f \( -name '*.mm' -o -name '*.m' \) -print 2>/dev/null | grep -vE "$EXD_RE" \
| while IFS= read -r f; do printf 'objc_file\t%s\t0\tObjC 源文件残留\n' "$f" >> "$OUT"; done

# ---- 11 UTF-8 BOM（信息项：MSVC 无 /utf-8 时 BOM 反而保护中文注释；无 BOM+中文才是风险） ----
find "$SRC" -type f \( -name '*.cpp' -o -name '*.hpp' -o -name '*.h' -o -name '*.cc' -o -name '*.cxx' \) -print 2>/dev/null | grep -vE "$EXD_RE" \
| while IFS= read -r f; do
    sig=$(head -c 3 "$f" 2>/dev/null | od -An -tx1 | tr -d '[:space:]' | tr 'A-F' 'a-f')
    [ "$sig" = "efbbbf" ] && printf 'utf8_bom\t%s\t0\t文件头带 UTF-8 BOM\n' "$f" >> "$OUT"
  done

# ---- 汇总（stdout；agent 直接可读） ----
crlf_count=$(grep -rlI $'\r' "$SRC" $EXD --include='*.cpp' --include='*.h' --include='*.hpp' 2>/dev/null | wc -l | tr -d ' ')
total=$(wc -l < "$OUT" | tr -d ' ')
echo "== 扫描完成: $SRC"
echo "== 已默认排除目录: third_party / build / .git 等第三方与构建目录（清单见脚本头部 EXD）"
echo "== 候选总数: ${total}（候选 ≠ 发现，需过五道门分诊）"
echo "== CRLF 文件计数（信息项，Windows 上属常态）: $crlf_count"
if [ "$total" -gt 0 ]; then
  echo "== 分类计数:"
  cut -f1 "$OUT" | sort | uniq -c | sort -rn | awk '{printf "   %-6s %s\n", $1, $2}'
fi
[ "$total" -gt 3000 ] && echo "!! 候选超过 3000 行，噪声可能偏大：建议收窄源码范围或分目录重扫"
exit 0
