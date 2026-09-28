#!/usr/bin/env bash
# verify-toolchain-claims.sh —— 用最小夹具核验声明清单（claims-checklist.tsv）里可自动化的条目
#
# 用法:   verify-toolchain-claims.sh <日志目录>
# 产出:   <日志目录>/claims-results.tsv   每行: id / 结果(PASS|FAIL|UNTESTED) / 证据文件 / 说明
#         <日志目录>/clm*.log             各条目的原始工具输出（证据）
# 原则:   PASS/FAIL 是机械判定（夹具行为与声明一致/不一致）；UNTESTED 是工具缺失，
#         绝不允许把 UNTESTED 当 PASS。agent 复核证据后回填 claims-checklist.tsv。
# 提示:   CLM-005/006 需要 cl.exe 在 PATH —— 在「x64 Native Tools Command Prompt」里
#         启动 Git Bash 再跑（或先执行 vcvars64.bat 后再进 bash）。

set -uo pipefail

BASE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
FIX="$BASE/fixtures"
LOGD="${1:?用法: verify-toolchain-claims.sh <日志目录>}"
mkdir -p "$LOGD" 2>/dev/null || exit 2
OUT="$LOGD/claims-results.tsv"
: > "$OUT"

rec()  { printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$OUT"; }
have() { command -v "$1" >/dev/null 2>&1; }

# Git Bash 会把 /W4 之类误当路径转换；MSYS 环境下改用 // 前缀
if [ -n "${MSYSTEM:-}" ]; then SL='//'; else SL='/'; fi

# ---------- CLM-001 / CLM-002: 编译数据库 ----------
if have cmake; then
  vs_done=0
  for gen in "Visual Studio 17 2022" "Visual Studio 16 2019"; do
    b="$LOGD/probe-vs"; rm -rf "$b"
    if cmake -S "$FIX/mini-cmakelists" -B "$b" -G "$gen" -DCMAKE_EXPORT_COMPILE_COMMANDS=ON >"$LOGD/clm001.log" 2>&1; then
      if [ -f "$b/compile_commands.json" ]; then
        rec CLM-001 FAIL "$LOGD/clm001.log" "VS 生成器[$gen]产出了 compile_commands.json —— 与声明不符"
      else
        rec CLM-001 PASS "$LOGD/clm001.log" "VS 生成器[$gen]未产出 compile_commands.json（与声明一致）"
      fi
      vs_done=1; break
    fi
  done
  [ "$vs_done" -eq 0 ] && rec CLM-001 UNTESTED "$LOGD/clm001.log" "无可用 VS 生成器（本机未装对应 VS 或 cmake 配置失败，看日志）"

  b="$LOGD/probe-ninja"; rm -rf "$b"
  if cmake -S "$FIX/mini-cmakelists" -B "$b" -G Ninja -DCMAKE_EXPORT_COMPILE_COMMANDS=ON >"$LOGD/clm002.log" 2>&1; then
    if [ -f "$b/compile_commands.json" ]; then
      rec CLM-002 PASS "$LOGD/clm002.log" "Ninja 生成器产出 compile_commands.json（与声明一致）"
    else
      rec CLM-002 FAIL "$LOGD/clm002.log" "Ninja 配置成功却未产出 —— 与声明不符"
    fi
  else
    rec CLM-002 UNTESTED "$LOGD/clm002.log" "Ninja 生成器不可用（未装 ninja 或无编译器，看日志）"
  fi
else
  rec CLM-001 UNTESTED - "cmake 不可用"
  rec CLM-002 UNTESTED - "cmake 不可用"
fi

# ---------- CLM-003: 认知复杂度检查可触发 ----------
if have clang-tidy; then
  clang-tidy --checks='-*,readability-function-cognitive-complexity' \
    "$FIX/cognitive_complexity.cpp" -- -std=c++17 >"$LOGD/clm003.log" 2>&1
  if grep -q 'readability-function-cognitive-complexity' "$LOGD/clm003.log"; then
    rec CLM-003 PASS "$LOGD/clm003.log" "样本触发认知复杂度诊断（与声明一致）"
  else
    rec CLM-003 FAIL "$LOGD/clm003.log" "样本未触发 —— 检查名不可用或样本未过阈值，人工复核日志"
  fi
else
  rec CLM-003 UNTESTED - "clang-tidy 不可用"
fi

# ---------- CLM-004: NOLINT 落行语义（两个夹具） ----------
if have clang-tidy; then
  clang-tidy --checks='-*,readability-named-parameter' \
    "$FIX/nolint_own_line.cpp" -- -std=c++17 >"$LOGD/clm004a.log" 2>&1
  if grep -q 'readability-named-parameter' "$LOGD/clm004a.log"; then
    rec CLM-004 PASS "$LOGD/clm004a.log" "a) 单独一行 NOLINT 未抑制下一行（与声明一致）"
  else
    rec CLM-004 FAIL "$LOGD/clm004a.log" "a) 单独一行 NOLINT 抑制了下一行 —— 与声明不符"
  fi
  clang-tidy --checks='-*,readability-named-parameter' \
    "$FIX/nolint_next_line.cpp" -- -std=c++17 >"$LOGD/clm004b.log" 2>&1
  if grep -q 'readability-named-parameter' "$LOGD/clm004b.log"; then
    rec CLM-004 FAIL "$LOGD/clm004b.log" "b) NOLINTNEXTLINE 未生效 —— 与声明不符"
  else
    rec CLM-004 PASS "$LOGD/clm004b.log" "b) NOLINTNEXTLINE 正常抑制（与声明一致）"
  fi
else
  rec CLM-004 UNTESTED - "clang-tidy 不可用"
fi

# ---------- CLM-005: MSVC warning(push) 缺 pop 的范围泄漏（对照组+实验组） ----------
if have cl; then
  ( cd "$LOGD" && cl ${SL}nologo ${SL}c ${SL}W4 "$FIX/warning_control.cpp"     > clm005_control.log 2>&1
                 cl ${SL}nologo ${SL}c ${SL}W4 "$FIX/warning_push_nopop.cpp"   > clm005_push.log    2>&1 )
  ctl=0; psh=0
  grep -q 'C4100' "$LOGD/clm005_control.log" 2>/dev/null && ctl=1
  grep -q 'C4100' "$LOGD/clm005_push.log"    2>/dev/null && psh=1
  if   [ "$ctl" -eq 1 ] && [ "$psh" -eq 0 ]; then
    rec CLM-005 PASS "$LOGD/clm005_push.log" "对照组报 C4100、push无pop 组未报 —— 泄漏成立（与声明一致）"
  elif [ "$ctl" -eq 0 ]; then
    rec CLM-005 FAIL "$LOGD/clm005_control.log" "对照组也未报 C4100，夹具无效（/W4 未生效？），人工复核"
  else
    rec CLM-005 FAIL "$LOGD/clm005_push.log" "push无pop 组仍报 C4100 —— 与声明不符"
  fi
else
  rec CLM-005 UNTESTED - "cl 不在 PATH：请在 VS Native Tools 命令行里重跑（见文件头提示）"
fi

# ---------- CLM-006: MSVC /analyze 无复杂度/嵌套对等诊断 ----------
if have cl; then
  ( cd "$LOGD" && cl ${SL}nologo ${SL}c ${SL}analyze ${SL}W4 "$FIX/cognitive_complexity.cpp" > clm006.log 2>&1 )
  if grep -qiE 'complexit|nesting' "$LOGD/clm006.log"; then
    rec CLM-006 FAIL "$LOGD/clm006.log" "/analyze 报出了复杂度/嵌套类诊断 —— 与声明不符"
  else
    rec CLM-006 PASS "$LOGD/clm006.log" "/analyze 无复杂度/嵌套对等诊断（与声明一致；证据为无匹配，属排除性证据）"
  fi
else
  rec CLM-006 UNTESTED - "cl 不可用"
fi

# ---------- CLM-008: Cppcheck 可运行（抑制语义仍需人工按官方文档核） ----------
if have cppcheck; then
  cppcheck --enable=warning "$FIX/cognitive_complexity.cpp" >"$LOGD/clm008.log" 2>&1
  rec CLM-008 PASS "$LOGD/clm008.log" "cppcheck 可运行；--suppressions-list 语义仍需人工最小验证后回填"
else
  rec CLM-008 UNTESTED - "cppcheck 不可用"
fi

# ---------- 其余条目：本脚本不自动判定，留人工 ----------
rec CLM-007 UNTESTED - "人工：装 clang-cl 后对夹具跑 clang-tidy -- -x c++ --target=x86_64-pc-windows-msvc --stdlib=libc++（参数以本机为准）验证双工具链共存"
rec CLM-009 UNTESTED - "人工：嵌套深度检查的可用实现待确认（试 lizard / cppcheck / clang-tidy 各选项）；确认无实现则记 C 类缺口"
rec CLM-010 UNTESTED - "人工：clang-tidy → SARIF 最小转换验证（clang-tidy-sarif 或 IDE 输出通道）"
rec CLM-011 UNTESTED - "人工：PVS-Studio 基线抑制语义需许可产品；无产品保持 untested，不得引用为已验证"
rec CLM-012 UNTESTED - "由 scan-macos-traces.sh 的 include_case_mismatch 候选覆盖；agent 分诊后回填"

echo "== 声明核验完成: $OUT"
awk -F'\t' '{c[$2]++} END{for(k in c) printf "   %-8s %s\n", k, c[k]}' "$OUT"
exit 0
