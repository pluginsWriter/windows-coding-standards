#!/usr/bin/env bash
# run-audit.sh —— skill 真机审计主入口（Windows C++ 环境）
#
# 被测物是 skill 本身（规范文档/脚本/DEC 计划的可执行声明），被测工程只是夹具。
#
# 用法:
#   ./run-audit.sh --src <被测C++工程目录> [--logs <日志根目录>]
#   （建议在 VS Native Tools 命令行里启动 Git Bash，使 cl.exe 可见，CLM-005/006 才能自动跑）
#
# 产出（执行后直接读结果，无需人工翻原始日志）:
#   logs/run-<时间戳>/
#     cmdlog.txt                    每条命令原文+完整输出（证据链）
#     env.txt                       环境指纹（工具版本/路径）
#     macos-trace-candidates.tsv    macOS 遗留痕迹候选（分诊前，不是结论）
#     scan-summary.txt              扫描分类计数
#     claims-results.tsv            声明核验结果（PASS/FAIL/UNTESTED+证据文件）
#     claims-checklist.tsv          本次运行的声明清单副本（待 agent 回填）
#     findings.tsv                  发现台账（含五道门字段，agent 填写）
#     summary.md                    机械结果汇总 + agent 待办清单 ← 先读这个

set -uo pipefail

BASE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

SRC=""
LOGROOT="$BASE/logs"
while [ $# -gt 0 ]; do
  case "$1" in
    --src)  SRC="$2";  shift 2 ;;
    --logs) LOGROOT="$2"; shift 2 ;;
    *) echo "未知参数: $1（用法: ./run-audit.sh --src <被测C++工程目录> [--logs <目录>]）" >&2; exit 2 ;;
  esac
done
if [ -z "$SRC" ] || [ ! -d "$SRC" ]; then
  echo "用法: ./run-audit.sh --src <被测C++工程目录> [--logs <目录>]" >&2
  exit 2
fi
SRC=$(cd "$SRC" && pwd -P)

TS=$(date +%Y%m%d-%H%M%S)
RUN="$LOGROOT/run-$TS"
mkdir -p "$RUN" || exit 2
CMDLOG="$RUN/cmdlog.txt"; : > "$CMDLOG"

log()  { printf '\n===== %s\n' "$*" >> "$CMDLOG"; }
run()  { printf '\n$ %s\n' "$*" | tee -a "$CMDLOG"; "$@" 2>&1 | tee -a "$CMDLOG"; true; }

# ---------- 1. 环境指纹（阶段0） ----------
{
  echo "时间: $(date '+%F %T')"
  echo "被测源码: $SRC"
  echo "shell: $BASH_VERSION"
  echo "MSYSTEM: ${MSYSTEM:-（非 Git Bash）}"
} > "$RUN/env.txt"

run uname -a | tee -a "$RUN/env.txt"
command -v systeminfo >/dev/null 2>&1 && systeminfo 2>/dev/null | head -40 >> "$RUN/env.txt"

# ---------- 1b. VS 内置工具探测（真机常见：装了 VS 但不在 PATH；见 findings-master F-005） ----------
# 与 run-audit.ps1 的 1b 对应。bash 侧只前插 VS 自带的 cmake/ninja/clang-tidy/msbuild；
# cl 所需的 INCLUDE/LIB 完整环境请从 VS Native Tools 命令行启动 Git Bash（见文件头提示），
# 或改用 PowerShell 入口（run-audit.ps1 会完整导入 vcvars64.bat）。
VSWHERE="/c/Program Files (x86)/Microsoft Visual Studio/Installer/vswhere.exe"
if [ -x "$VSWHERE" ]; then
  VSPATH=$("$VSWHERE" -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>/dev/null | tr -d '\r')
  if [ -n "$VSPATH" ]; then
    if command -v cygpath >/dev/null 2>&1; then
      VSPATH_U=$(cygpath -u "$VSPATH")
    else
      VSPATH_U=$(printf '%s' "$VSPATH" | sed -e 's|\\|/|g' -e 's|^\([A-Za-z]\):|/\L\1|')
    fi
    for sub in \
      "Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin" \
      "Common7/IDE/CommonExtensions/Microsoft/CMake/Ninja" \
      "Common7/IDE/CommonExtensions/Microsoft/LLVM/bin" \
      "Common7/IDE/CommonExtensions/Microsoft/LLVM/x64/bin" \
      "MSBuild/Current/Bin"; do
      [ -d "$VSPATH_U/$sub" ] && PATH="$VSPATH_U/$sub:$PATH"
    done
    export PATH
    echo "vswhere => $VSPATH" >> "$RUN/env.txt"
    echo "VS installation => ${VSPATH_U}（已前插其内置 CMake/Ninja/LLVM/MSBuild 到 PATH；cl 仍需 Native Tools 环境）" >> "$RUN/env.txt"
  else
    echo "vswhere => 有 exe 但无 VC 工作负载结果（未装 C++ 桌面开发组件？）" >> "$RUN/env.txt"
  fi
else
  echo "vswhere => 未找到（未装 VS 或非标准安装；工具探测按当前 PATH 为准）" >> "$RUN/env.txt"
fi

for t in cmake clang-tidy clang-cl cl ninja msbuild cppcheck git; do
  if command -v "$t" >/dev/null 2>&1; then
    echo "tool $t => $(command -v "$t")" >> "$RUN/env.txt"
    case "$t" in
      cmake)      run cmake --version ;;
      clang-tidy) run clang-tidy --version ;;
      ninja)      run ninja --version ;;
      cppcheck)   run cppcheck --version ;;
      git)        run git --version ;;
      cl)         run cl //nologo 2>/dev/null || run cl /nologo ;;
    esac
    { echo "--- $t 版本 ---"; grep -A2 "\$ $t" "$CMDLOG" | tail -3; } >> "$RUN/env.txt" 2>/dev/null
  else
    echo "tool $t => 缺失" >> "$RUN/env.txt"
  fi
done
cp "$RUN/env.txt" "$CMDLOG.env" 2>/dev/null || true

# ---------- 2. 初始化台账 ----------
[ -f "$BASE/templates/findings.tsv" ]        && cp "$BASE/templates/findings.tsv" "$RUN/findings.tsv"
[ -f "$BASE/templates/claims-checklist.tsv" ] && cp "$BASE/templates/claims-checklist.tsv" "$RUN/claims-checklist.tsv"

# ---------- 3. macOS 遗留痕迹扫描（阶段5候选） ----------
log "macOS 遗留痕迹扫描"
bash "$BASE/scripts/scan-macos-traces.sh" "$SRC" "$RUN/macos-trace-candidates.tsv" 2>&1 \
  | tee "$RUN/scan-summary.txt" | tee -a "$CMDLOG"

# ---------- 4. 工具链声明核验（阶段2自动化部分） ----------
log "工具链声明核验（夹具）"
bash "$BASE/scripts/verify-toolchain-claims.sh" "$RUN" 2>&1 | tee -a "$CMDLOG"

# ---------- 5. 汇总（直接可读结果） ----------
SUM="$RUN/summary.md"
{
  echo "# 审计机械报告 run-$TS"
  echo
  echo "- 被测源码: \`$SRC\`"
  echo "- 生成时间: $(date '+%F %T')"
  echo "- 环境指纹: 见 env.txt；命令证据链: 见 cmdlog.txt"
  echo
  echo "## 1. 声明核验结果（自动化部分，详见 claims-results.tsv）"
  echo
  echo "| id | 结果 | 证据 | 说明 |"
  echo "| --- | --- | --- | --- |"
  if [ -f "$RUN/claims-results.tsv" ]; then
    awk -F'\t' 'NF>=4 && $1!="id" {printf "| %s | %s | %s | %s |\n", $1, $2, $3, $4}' "$RUN/claims-results.tsv"
  else
    echo "| （无） | | | |"
  fi
  echo
  echo "> PASS/FAIL 也只是机械判定：agent 须复核证据文件后，把结果回填 claims-checklist.tsv。"
  echo
  echo "## 2. macOS 遗留痕迹候选（分诊前，不是结论）"
  echo
  if [ -s "$RUN/macos-trace-candidates.tsv" ]; then
    echo "| 计数 | 类别 |"
    echo "| --- | --- |"
    cut -f1 "$RUN/macos-trace-candidates.tsv" | sort | uniq -c | awk '{printf "| %s | %s |\n", $1, $2}'
    echo
    echo "共 $(wc -l < "$RUN/macos-trace-candidates.tsv" | tr -d ' ') 条候选 → 分诊流程见 briefs/agent-brief.md §5；已知误报源见 §6。"
  else
    echo "（无候选。注意：候选为零 ≠ 干净，只等于本次模式集未命中。）"
  fi
  echo
  echo "## 3. Agent 待办（按 briefs/agent-brief.md 六阶段执行）"
  echo
  echo "- [ ] 阶段0 补漏：核对 env.txt，补 MSVC 具体版本 / vcvars 环境 / 缺失工具的处置决定"
  echo "- [ ] 阶段1 skill 自检：跑 skill 自带 verify 类脚本，结果进 findings.tsv（A 类优先）"
  echo "- [ ] 阶段2 人工部分：复核 claims-results.tsv 证据，回填 claims-checklist.tsv；UNTESTED 条目逐条验证或明确标注不可测原因"
  echo "- [ ] 阶段3 工作流实走：按 skill 工作流走一遍被测工程，每步记录 skill预期 vs 实际发生"
  echo "- [ ] 阶段4 规则触发：对 skill 每条机器规则喂已知违规样本，记录 拦得住/拦不住"
  echo "- [ ] 阶段5 候选分诊：macos-trace-candidates.tsv → 过五道门 → findings.tsv"
  echo "- [ ] 收口：检查 findings.tsv 每条 repro_count≥2、归因列指向 skill 具体工件、A–F 分类齐全；补齐未检查清单"
  echo
  echo "## 4. 证据纪律（对 agent 生效）"
  echo
  echo "- 每条结论必须引用本目录内日志文件；自己补跑的命令一律追加到 cmdlog.txt（先写 \`$ 命令\` 再贴输出）。"
  echo "- 确认级结论必须复现两次；只出现一次的标\"间歇\"。"
  echo "- 编译期事实 / 运行期事实 / 静态推断 分开标注；没运行过的只能写\"未检查\"。"
} > "$SUM"

echo
echo "== 完成。结果目录: $RUN"
echo "== 先读: $SUM"
