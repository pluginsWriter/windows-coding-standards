#!/usr/bin/env bash
# =============================================================================
# windows-coding-standards —— C++ 侧违规基线采集
# =============================================================================
# 用法:
#   bash scripts/baseline_cpp_style.sh <工程目录>
#   bash scripts/baseline_cpp_style.sh <工程目录> --clang-tidy-only   # 跳过 clang-format 段
#   bash scripts/baseline_cpp_style.sh <工程目录> --clang-format-only # 跳过 clang-tidy 段
#
# 退出码: 0 成功 / 2 用法错误 / 3 缺 clang-format 或 clang-tidy / 4 范围内无 C++ 编译单元 / 5 缺编译数据库
#
# 本脚本固化 `.workbuddy/notes/2026-09-28-adoption-and-remediation-plan.md` §4.2 的六行，逐行如下 ——
# 每一行都有一个**踩过的坑**在后面，删任何一行都会退回「假基线」：
#
#   ① 清单先落盘（`git ls-files -z` 或 `find -print0`），**不用 `$(git ls-files '*.cpp')`**：
#      无匹配时参数**整体消失**，clang-format 退化成读 stdin（挂住）或空跑并退出 0；
#      带空格的路径还会被词分割拆坏。
#   ② `[ -s "$LIST" ] || exit 4` 是**承重墙**，不能删、不能只靠 `xargs -r`：
#      BSD 与 GNU 的 `xargs` 在「空输入是否执行命令」上行为**相反**。
#   ③ 条数 = **NUL 字节数**，**不用 `wc -l`**：清单是 -z 的 NUL 分隔、没有换行，`wc -l` 恒为 0。
#      （实测：真仓库 11 个文件时 `wc -l` 也显示 0。分母写 0 比不写分母更坏 —— 它看起来像已核对过。）
#   ④ 输出命令一律带 `LC_ALL=C` —— 否则文件列表的排序与其他输出随调用方 locale 变化，
#      同一工程两次运行得到的「基线」不可比。
#   ⑤ 缺工具 / 缺清单 / 缺数据库一律**非零退出**，绝不报「0 违规」。
#   ⑥ 编译数据库只覆盖**它那个配置**（Debug|x64 扫不到 Release / ARM64，也扫不到被 `#ifdef` 关掉的分支）⇒
#      基线必须注明「本数字 = 单一配置下」。
#
# ⚠️ 本脚本尚未在 Windows 上实跑过（本机 macOS）。首次使用请把实际输出与
#    「本机与 Windows 的差异」记回正文附录 D。
# =============================================================================

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

PROJECT=""
RUN_CF=1
RUN_CT=1
for arg in "$@"; do
  case "$arg" in
    --clang-tidy-only)   RUN_CF=0 ;;
    --clang-format-only) RUN_CT=0 ;;
    -*) printf '未知选项: %s\n' "$arg" >&2; exit 2 ;;
    *)
      if [ -z "$PROJECT" ]; then PROJECT="$arg"; else printf '多余的参数: %s\n' "$arg" >&2; exit 2; fi
      ;;
  esac
done

if [ -z "$PROJECT" ]; then
  printf '用法: bash %s <工程目录> [--clang-tidy-only|--clang-format-only]\n' "$0" >&2
  exit 2
fi
if [ ! -d "$PROJECT" ]; then
  printf '错误: 目录不存在: %s\n' "$PROJECT" >&2
  exit 2
fi
PROJECT=$(cd "$PROJECT" && pwd)

hdr() { printf '\n[%s] %s\n' "$1" "$2"; }

# 数 NUL 分隔清单的条数 = 数 NUL 字节数。见头部 ③。
count_nul() { LC_ALL=C tr -cd '\0' < "$1" | wc -c | tr -d ' '; }

TMPD=$(mktemp -d 2>/dev/null || mktemp -d -t wcs) || { printf '错误: 无法创建临时目录\n' >&2; exit 2; }
cleanup_tmp() { [ -n "${TMPD:-}" ] && [ -d "$TMPD" ] && rm -rf "$TMPD"; }
trap cleanup_tmp EXIT INT TERM

printf '=== windows-coding-standards C++ 违规基线 ===\n'
printf '工程目录: %s\n' "$PROJECT"

# ---------------------------------------------------------------------------
hdr 1 "文件清单（NUL 分隔，先落盘、先证明非空 —— 禁止空展开）"
TU_LIST="$TMPD/tu.list"
HDR_LIST="$TMPD/hdr.list"
if git -C "$PROJECT" rev-parse --git-dir >/dev/null 2>&1; then
  git -C "$PROJECT" ls-files -z -- '*.cpp' '*.cc' '*.cxx' > "$TU_LIST"
  git -C "$PROJECT" ls-files -z -- '*.h' '*.hpp' '*.hh'   > "$HDR_LIST"
  printf '  清单来源: git ls-files（尊重 .gitignore）\n'
else
  (cd "$PROJECT" && LC_ALL=C find . -type f \( -name '*.cpp' -o -name '*.cc' -o -name '*.cxx' \) -print0) > "$TU_LIST"
  (cd "$PROJECT" && LC_ALL=C find . -type f \( -name '*.h' -o -name '*.hpp' -o -name '*.hh' \) -print0)   > "$HDR_LIST"
  printf '  清单来源: find（非 git 仓库 —— **包含**被版本控制忽略的文件，数字会偏大）\n'
fi

# 承重墙：清单为空 ⇒ 是范围写错，不是「干净」
if [ ! -s "$TU_LIST" ]; then
  printf '\n错误: 范围内**没有 C++ 编译单元** —— 这是**范围写错，不是"干净"**。\n' >&2
  printf '  默认只认 *.cpp / *.cc / *.cxx。若工程用别的后缀，请改本脚本的清单模式，\n' >&2
  printf '  不要把这个空清单当作通过：分母为 0 的百分比是假的。\n' >&2
  exit 4
fi

TU_N=$(count_nul "$TU_LIST")
HDR_N=$(count_nul "$HDR_LIST")
printf '  编译单元 %s 个 / 头文件 %s 个（分母，记进记录）\n' "$TU_N" "$HDR_N"

# 格式检查覆盖编译单元 **与** 头文件（§4.2 两支命令）。合并成一份 NUL 清单，只跑一次。
ALL_LIST="$TMPD/all.list"
cat "$TU_LIST" "$HDR_LIST" > "$ALL_LIST" 2>/dev/null || { : > "$ALL_LIST"; cat "$TU_LIST" >> "$ALL_LIST"; cat "$HDR_LIST" >> "$ALL_LIST"; }

# ---------------------------------------------------------------------------
hdr 2 "检测工具链"
MISSING_TOOL=0
NEED=""
[ "$RUN_CF" -eq 1 ] && NEED="$NEED clang-format"
[ "$RUN_CT" -eq 1 ] && NEED="$NEED clang-tidy"
for t in $NEED; do
  if command -v "$t" >/dev/null 2>&1; then
    printf '  %s: %s\n' "$t" "$(LC_ALL=C "$t" --version 2>/dev/null | head -1)"
  else
    printf '  **缺失**: %s\n' "$t"
    MISSING_TOOL=$((MISSING_TOOL + 1))
  fi
done
if [ "$MISSING_TOOL" -gt 0 ]; then
  printf '\n错误: 缺 %s 个工具 —— **这是范围/环境问题，不是「0 违规」**。\n' "$MISSING_TOOL" >&2
  printf '  本脚本拒绝在缺工具时给出任何数字：那只会是假的 0。\n' >&2
  printf '  安装: pip install clang-format clang-tidy\n' >&2
  printf '  ⚠️ 有的打包把工具装在**非默认 PATH** 里（例如 python 的 venv/bin）—— 装完先确认 command -v 能找到。\n' >&2
  exit 3
fi

# ---------------------------------------------------------------------------
CDB=""
for cand in "$PROJECT/build/compile_commands.json" "$PROJECT/compile_commands.json"; do
  [ -f "$cand" ] && CDB="$cand" && break
done
if [ "$RUN_CT" -eq 1 ]; then
  hdr 3 "编译数据库（clang-tidy 的硬前置）"
  if [ -n "$CDB" ]; then
    printf '  已找到: %s\n' "$CDB"
  else
    printf '\n错误: 找不到 compile_commands.json —— clang-tidy **必须有**它，\n' >&2
    printf '  没有数据库时 clang-tidy 要么整体报错，要么只查语法不查语义（两种情况都表现为「0 违规」）。\n' >&2
    printf '  CMake 工程: cmake -S "%s" -B "%s/build" -DCMAKE_EXPORT_COMPILE_COMMANDS=ON\n' "$PROJECT" "$PROJECT" >&2
    printf '  ⚠️ CMake 的 **VS 生成器不产出**该文件；MSBuild 工程的三条替代路见接入计划 §5.3。\n' >&2
    printf '  只想跑格式检查: bash %s "%s" --clang-format-only\n' "$0" "$PROJECT" >&2
    exit 5
  fi
else
  hdr 3 "编译数据库（已按 --clang-format-only 跳过）"
fi

# ---------------------------------------------------------------------------
if [ "$RUN_CF" -eq 1 ]; then
  hdr 4 "clang-format --dry-run --Werror（只读；不写任何文件）"
  # ⚠️ 必须在**工程根**下跑：清单里的路径是相对工程根的（`git ls-files` 如此，`find .` 也如此）。
  #    不在工程根下跑 ⇒ 每个文件都报 `No such file or directory`，
  #    退出码非 0 却「一条真违规都没有」—— 又是一种**看起来在查、实际一个都没查**的假基线。
  CF_OUT=$(cd "$PROJECT" && xargs -0 env LC_ALL=C clang-format --dry-run --Werror < "$ALL_LIST" 2>&1)
  CF_RC=$?
  # ⚠️ 计数**不能按 `warning:` 数** —— `--Werror` 会把逐文件的提示报成 `error:`，
  #    按 `warning:` 数会恒得 0，于是「有违规」与「一条都没查」在汇总表里长得一模一样。
  #    判据改成锚在「文件:行:列:」这个形态上。
  CF_DIAG=$(printf '%s\n' "$CF_OUT" | awk '/^[^:]+:[0-9]+:[0-9]+:/{n++} END{print n+0}')
  CF_FILES=$(printf '%s\n' "$CF_OUT" | awk -F: '/^[^:]+:[0-9]+:[0-9]+:/{print $1}' | LC_ALL=C sort -u | awk 'END{print NR+0}')
  printf '  退出码: %s（非 0 = 有文件未格式化）\n' "$CF_RC"
  printf '  诊断条数: %s / 涉及文件数: %s\n' "$CF_DIAG" "$CF_FILES"
  if [ "$CF_RC" -ne 0 ]; then
    printf '  —— 前若干条（原样，无排序，locale 固定在 C）——\n'
    printf '%s\n' "$CF_OUT" | head -15 | sed 's/^/    /'
  fi
  printf '  提示: clang-format **只修**它支持自动修的部分；本脚本不写盘。\n'
else
  hdr 4 "clang-format（已按 --clang-tidy-only 跳过）"
fi

# ---------------------------------------------------------------------------
if [ "$RUN_CT" -eq 1 ]; then
  hdr 5 "clang-tidy（只读；读工程根的 .clang-tidy 与编译数据库）"
  if [ -f "$PROJECT/.clang-tidy" ]; then
    printf '  配置: %s/.clang-tidy\n' "$PROJECT"
  else
    printf '  ⚠️ 工程根**没有** .clang-tidy —— 本次跑的是工具出厂默认集，**不是本规范**。\n'
    printf '     先 bash "%s/bootstrap_cpp_style.sh" "%s" --fix 安装配置，再重采。\n' "$SCRIPT_DIR" "$PROJECT"
  fi
  # 同样必须在**工程根**下跑（理由见上节）；`-p` 用**绝对路径**避免两层 cd 叠加出错。
  CT_OUT=$(cd "$PROJECT" && xargs -0 env LC_ALL=C clang-tidy -p "$(dirname "$CDB")" --header-filter='\.(h|hpp|hh)$' < "$TU_LIST" 2>&1)
  CT_RC=$?
  # 与 clang-format 段同一口径：锚在「文件:行:列:」，不按 `warning:` 数
  CT_HITS=$(printf '%s\n' "$CT_OUT" | awk '/^[^:]+:[0-9]+:[0-9]+:/{n++} END{print n+0}')
  printf '  退出码: %s\n' "$CT_RC"
  printf '  诊断条数: %s\n' "$CT_HITS"
  printf '  —— 按检查名汇总 ——\n'
  printf '%s\n' "$CT_OUT" | grep -oE '\[[a-z0-9][a-z0-9-]*-[a-z0-9-]+\]' | LC_ALL=C sort | LC_ALL=C uniq -c | LC_ALL=C sort -rn | head -25 | sed 's/^/    /'
  if [ "$CT_HITS" -eq 0 ]; then
    printf '    （无）。**先别读成「干净」**：确认上一条配置说明 —— 若没有 .clang-tidy，或 CheckOptions 为空，\n'
    printf '    本结果只说明「没开检查」，见正文 §5.4。\n'
  fi
else
  hdr 5 "clang-tidy（已按 --clang-format-only 跳过）"
fi

# ---------------------------------------------------------------------------
hdr 6 "统计与三件必须同时说明的事"
printf '  编译单元 %s 个 / 头文件 %s 个\n' "$TU_N" "$HDR_N"
if [ "$RUN_CF" -eq 1 ]; then printf '  clang-format 退出码 %s / 诊断 %s 条 / 文件 %s 个\n' "${CF_RC:-n/a}" "${CF_DIAG:-n/a}" "${CF_FILES:-n/a}"; fi
if [ "$RUN_CT" -eq 1 ]; then printf '  clang-tidy   退出码 %s / 诊断 %s 条\n' "${CT_RC:-n/a}" "${CT_HITS:-n/a}"; fi

cat <<'NEXT'

  ⚠️ 关于这份基线，三件事必须同时说明，否则它会被误读：
    1. **N 处违规 ≠ 代码很糟**。规则是分档开的（正文 §8），当前只开了第一批；
       改规则档位后必须重采，否则前后数字不可比。
    2. **本基线只覆盖「格式」与「clang-tidy 已开的检查」**。
       编译期警告类（-Wconversion / -Wdocumentation 等）**不在此列** —— 它们要求把开关
       注入工程自己的构建系统（接入计划 §4.1），本脚本不碰构建系统。
       函数行数 / 类型行数 / 参数个数三项在 C++ 侧由 clang-tidy 的 readability-function-size
       覆盖，而本工程对**阈值**的态度是「可检查且**有依据**才标 MUST」（正文 §2）——
       取值出处见 §5.4，别把这里没报当成「没问题」。
    3. **本数字 = 单一配置下**。编译数据库只覆盖它那个配置（Debug|x64 扫不到 Release / ARM64，
       也扫不到被 #ifdef 关掉的分支）⇒ 写记录时必须带上配置名，否则不可比。
NEXT

exit 0
