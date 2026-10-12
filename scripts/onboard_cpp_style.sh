#!/usr/bin/env bash
# =============================================================================
# windows-coding-standards —— C++ 侧一键接入编排层（**薄壳**）
# =============================================================================
# 用法:
#   bash scripts/onboard_cpp_style.sh <工程目录>                    # 首次接入全链
#   bash scripts/onboard_cpp_style.sh <工程目录> --update          # 配置升级后的重新替换（带备份与复验）
#   bash scripts/onboard_cpp_style.sh <工程目录> --skip-baseline   # 只做到配置就位（显式跳过基线段）
#
# 编排的段（每段调用既有脚本，**不复制其逻辑**）:
#   1) bootstrap_cpp_style.sh --check            工具链 + 配置现状（缺工具 / 无源文件即停）
#   2) 配置就位: 默认 --fix（只新增不覆盖）；--update 则备份 → 替换 → dump-config 复验
#   3) bootstrap_cpp_style.sh --check --probe    探针复验（配置真的生效吗）
#   4) 编译数据库: 已有则跳过；有 CMakeLists.txt 则 cmake -DCMAKE_EXPORT_COMPILE_COMMANDS=ON；
#      .vcxproj / .sln 工程 → 只打印 MSBuild 断链提示（该路线已裁决「暂不定」，本脚本不替用户选）
#   5) baseline_cpp_style.sh                     可信基线（--skip-baseline 显式跳过）
#
# 退出码: 0 成功 / 2 用法错误 / 6 配置替换或探针复验失败
#   透传说明（**不属于上面那行声明**，机械核对只认「# 退出码:」行）:
#   步骤 1/2/3/5 的失败码**原样透传自被调脚本** —— 3 缺 clang-format 或 clang-tidy /
#   4 工程里无 C++ 源（bootstrap）、5 缺编译数据库或基线失败（baseline）。
#   调用方按「非零即失败」处理即可，不要对透传码做分支。
#
# 设计纪律:
#   · **薄壳**: 本脚本只编排顺序与失败传播；工具检测、配置安装、探针、基线全部调用
#     既有脚本 —— 同一逻辑实现两份必然漂移（本仓硬规矩），本脚本不做第二份实现。
#   · **probe 未命中 = 失败**: bootstrap 的 probe 段是「检测 + 报告」语义、恒 exit 0，
#     `[未报]` 行是它向调用方报告「配置未生效」的**输出契约**；本脚本据此判失败。
#     ⚠️ 改 bootstrap 里那两行 `[未报]` 文案，必须同步本脚本的 grep（第 3 段）。
#   · **--update 显式发起、带时间戳备份、替换后核验副作用**（cmp），绝不静默覆盖；
#     dump-config 校验不过即失败并指回备份路径（历史上模板曾被静默整份拒绝读取）。
#   · **MSBuild 断链不隐瞒**: 无数据库时 baseline 必然非零退出 —— 那是已裁决的断链状态，
#     不是本脚本坏了；本脚本把责任写进提示，而不是伪造一个「成功」。
#
# ⚠️ 本脚本**尚未在 Windows（Git Bash）实跑过**；已列入 Windows 验证工单（轨 A 追加项）。
# =============================================================================

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SKILL_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
ASSETS="$SKILL_DIR/assets"
BOOTSTRAP="$SCRIPT_DIR/bootstrap_cpp_style.sh"
BASELINE="$SCRIPT_DIR/baseline_cpp_style.sh"

PROJECT=""
DO_UPDATE=0
SKIP_BASELINE=0
for arg in "$@"; do
  case "$arg" in
    --update)       DO_UPDATE=1 ;;
    --skip-baseline) SKIP_BASELINE=1 ;;
    -*) printf '未知选项: %s\n' "$arg" >&2; exit 2 ;;
    *)  if [ -z "$PROJECT" ]; then PROJECT="$arg"; else printf '多余的参数: %s\n' "$arg" >&2; exit 2; fi ;;
  esac
done

if [ -z "$PROJECT" ]; then
  printf '用法: bash %s <工程目录> [--update] [--skip-baseline]\n' "$0" >&2
  exit 2
fi
if [ ! -d "$PROJECT" ]; then
  printf '错误: 目录不存在: %s\n' "$PROJECT" >&2
  exit 2
fi
PROJECT=$(cd "$PROJECT" && pwd)

hdr() { printf '\n=== [%s] %s ===\n' "$1" "$2"; }

printf '=== windows-coding-standards C++ 一键接入（编排层）===\n'
printf '工程目录: %s\n' "$PROJECT"
printf '模式: %s%s\n' \
  "$([ "$DO_UPDATE" -eq 1 ] && printf 'update（重新替换，带备份）' || printf '首次安装（只新增不覆盖）')" \
  "$([ "$SKIP_BASELINE" -eq 1 ] && printf ' + 跳过基线')"

# ---------------------------------------------------------------------------
hdr 1 "步骤 1/5 工具链与配置现状（bootstrap --check）"
bash "$BOOTSTRAP" "$PROJECT" --check
RC=$?
if [ "$RC" -ne 0 ]; then
  printf '\n错误: 步骤 1 未通过（exit %s）—— 后续步骤不会执行。\n' "$RC" >&2
  exit "$RC"
fi

# ---------------------------------------------------------------------------
hdr 2 "步骤 2/5 配置就位"
if [ "$DO_UPDATE" -eq 1 ]; then
  # --update：显式替换。备份 → 替换 → 核验副作用。只动两份 clang 配置；
  # .editorconfig 依旧不在任何脚本安装范围内（两侧共享，见 bootstrap 头部纪律）。
  TS=$(date +%Y%m%d-%H%M%S)
  for pair in "clang-format:.clang-format" "clang-tidy:.clang-tidy"; do
    src="${pair%%:*}"
    dst="${pair##*:}"
    dst_path="$PROJECT/$dst"
    if [ ! -f "$dst_path" ]; then
      printf '  %s 不存在 → 直接安装（等同 --fix）\n' "$dst"
      cp "$ASSETS/$src" "$dst_path" || { printf '  错误: 复制失败 %s\n' "$dst_path" >&2; exit 6; }
    else
      if cmp -s "$dst_path" "$ASSETS/$src"; then
        printf '  %s 与 skill 当前版一致 → 跳过\n' "$dst"
        continue
      fi
      DIFF_N=$(diff "$dst_path" "$ASSETS/$src" 2>/dev/null | grep -cE '^[<>]' || true)
      BAK="$dst_path.bak.$TS"
      cp "$dst_path" "$BAK" || { printf '  错误: 备份失败 %s\n' "$BAK" >&2; exit 6; }
      printf '  %s 与 skill 当前版有差异（%s 行）→ 已备份到 %s，现在替换\n' "$dst" "$DIFF_N" "$BAK"
      cp "$ASSETS/$src" "$dst_path" || { printf '  错误: 复制失败 %s\n' "$dst_path" >&2; exit 6; }
    fi
    # 核验副作用，不核验 cp 的退出码
    if ! cmp -s "$dst_path" "$ASSETS/$src"; then
      printf '  错误: %s 替换后与模板不一致（写入被拦？）\n' "$dst" >&2
      exit 6
    fi
  done
  # 让工具把模板真读一遍 —— 整份被拒绝读取是最危险的失效模式（v0.1.4 实测过）
  CF_ERR=$(cd "$PROJECT" && LC_ALL=C clang-format -style=file -dump-config 2>&1 >/dev/null || true)
  if [ -n "$CF_ERR" ]; then
    printf '错误: 替换后的 .clang-format 被工具拒绝读取 —— 本文件里一条配置都不生效：\n' >&2
    printf '%s\n' "$CF_ERR" | sed 's/^/    /' >&2
    printf '回滚: cp "%s/.clang-format.bak.%s" "%s/.clang-format"\n' "$PROJECT" "$TS" "$PROJECT" >&2
    exit 6
  fi
  printf '  .clang-format 能被干净读取（stderr 为空）\n'
else
  bash "$BOOTSTRAP" "$PROJECT" --fix
  RC=$?
  if [ "$RC" -ne 0 ]; then
    printf '\n错误: 配置安装失败（exit %s）。\n' "$RC" >&2
    exit "$RC"
  fi
fi

# ---------------------------------------------------------------------------
hdr 3 "步骤 3/5 探针复验（配置真的生效吗）"
# bootstrap 的 probe 段恒 exit 0（检测+报告语义）；「配置未生效」靠输出里的
# `[未报]` 行报告 —— 那是它对调用方的输出契约（见本文件头部纪律）。
PROBE_OUT=$(bash "$BOOTSTRAP" "$PROJECT" --check --probe 2>&1)
RC=$?
printf '%s\n' "$PROBE_OUT"
if [ "$RC" -ne 0 ]; then
  printf '\n错误: 探针阶段未通过（exit %s）。\n' "$RC" >&2
  exit "$RC"
fi
if printf '%s' "$PROBE_OUT" | grep -qF '[未报]'; then
  printf '\n错误: 探针有未命中项（上方 [未报] 行）—— 配置没有真正生效，拒绝继续。\n' >&2
  printf '  修复前不要采基线：那样采到的 0 违规是假的。\n' >&2
  exit 6
fi
if printf '%s' "$PROBE_OUT" | grep -qF '跳过' && ! printf '%s' "$PROBE_OUT" | grep -qF '[命中]'; then
  printf '  ⚠️ 本次探针被跳过（探针文件已存在？）—— 复验没有真正执行，请人工确认。\n' >&2
fi

# ---------------------------------------------------------------------------
hdr 4 "步骤 4/5 编译数据库（clang-tidy 依赖）"
CDB="$PROJECT/build/compile_commands.json"
if [ -f "$CDB" ]; then
  printf '  已存在: %s → 跳过生成\n' "$CDB"
elif [ -f "$PROJECT/CMakeLists.txt" ]; then
  if command -v cmake >/dev/null 2>&1; then
    printf '  检测到 CMakeLists.txt → cmake 生成编译数据库 ...\n'
    cmake -S "$PROJECT" -B "$PROJECT/build" -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
    RC=$?
    if [ "$RC" -ne 0 ] || [ ! -f "$CDB" ]; then
      printf '错误: cmake 未产出 %s（exit %s）—— 核验副作用，不核验退出码。\n' "$CDB" "$RC" >&2
      exit 6
    fi
  else
    printf '错误: 检测到 CMakeLists.txt 但 PATH 里没有 cmake，且无现成编译数据库。\n' >&2
    printf '  安装 cmake 后重跑，或先自行生成 %s。\n' "$CDB" >&2
    exit 6
  fi
elif ls "$PROJECT"/*.vcxproj >/dev/null 2>&1 || [ -n "$(find "$PROJECT" -maxdepth 1 -name '*.sln' -print -quit 2>/dev/null)" ]; then
  printf '  ⚠️ MSVC / .sln 工程：MSBuild 的 VS 生成器**不产出** compile_commands.json。\n'
  printf '     该路线已裁决「暂不定」—— 本脚本不替你选，三条替代路见接入计划 §5.3 与 remediation-playbook.md。\n'
  printf '     继续执行基线段：它将因缺编译数据库**非零退出** —— 那是诚实失败，不是脚本坏了。\n'
else
  printf '  提示: 非 CMake 且非 MSVC 工程 —— 需自行提供 %s 后重跑。\n' "$CDB"
fi

# ---------------------------------------------------------------------------
hdr 5 "步骤 5/5 可信基线"
if [ "$SKIP_BASELINE" -eq 1 ]; then
  printf '  已显式跳过（--skip-baseline）。\n'
  printf '  ⚠️ 本次没有基线数字 —— 不得把「没测」当成「0 违规」使用。\n'
else
  bash "$BASELINE" "$PROJECT"
  RC=$?
  if [ "$RC" -ne 0 ]; then
    printf '\n错误: 基线未产出（exit %s）—— 见上方 baseline 的输出。\n' "$RC" >&2
    exit "$RC"
  fi
fi

# ---------------------------------------------------------------------------
hdr 6 "完成"
printf '  后续日常检查（改完代码后，对改动文件跑对应侧命令）:\n'
printf '    clang-format --dry-run --Werror <改动的文件>\n'
printf '    clang-tidy -p "%s/build" <改动的文件>\n' "$PROJECT"
printf '  重采基线: bash "%s" "%s"\n' "$BASELINE" "$PROJECT"
exit 0
