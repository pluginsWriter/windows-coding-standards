#!/usr/bin/env bash
# =============================================================================
# windows-coding-standards —— C++ 侧工具链检测与配置安装
# =============================================================================
# 用法:
#   bash scripts/bootstrap_cpp_style.sh <工程目录> --check          # 只读：检测 + 报告（默认）
#   bash scripts/bootstrap_cpp_style.sh <工程目录> --fix            # 安装 .clang-format / .clang-tidy（只新增，不覆盖）
#   bash scripts/bootstrap_cpp_style.sh <工程目录> --check --probe  # 追加「配置真的生效吗」探针
#
# 退出码: 0 成功 / 2 用法错误 / 3 缺 clang-format 或 clang-tidy / 4 工程里找不到 C++ 源文件 / 5 配置安装失败
#
# 设计纪律（与 C# 侧 `bootstrap_dotnet_style.sh` 同源）:
#   · **配置缺失 = 假基线，必须挡住。** 没有 `.clang-format` / `.clang-tidy`，
#     报出的「0 违规」只说明「工具没读配置」，不说明代码干净。
#   · **只新增、绝不覆盖** 已有配置。工程自己的 `.clang-format` 优先。
#   · **核验副作用，不核验退出码**（Swift / C# 两侧都踩过：写操作被静默拦下却返回 0）。
#   · `.editorconfig` **不在本脚本的安装范围内** —— 它是两侧唯一共享的配置（`[*]` 段），
#     只有一份、按段共享，**不得复制两份**；缺它时本脚本只报告，由工程自行补。
#
# ⚠️ 本脚本**尚未在 Windows 上实跑过**（本机 macOS、无 MSVC / MSBuild）。
#    在 MSVC 工程上首次使用时先看两件事：
#      1. clang-tidy **必须**有 compile_commands.json，而 CMake 的 VS 生成器**不产出**它
#         （三条替代路见 `2026-09-28-adoption-and-remediation-plan.md` §5.3）；
#      2. `-Wdocumentation` / `-Wconversion` 一类开关**没有被本脚本注入构建系统** ——
#         那属于 §4.1 的「必须注入工程自己的构建系统」，不在本脚本职责内。
#    首次接入请先跑 `--check --probe`，把实际行为记回正文附录 D。
# =============================================================================

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SKILL_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
ASSETS="$SKILL_DIR/assets"

PROJECT="${1:-}"
MODE="check"
PROBE=0
shift || true
for arg in "$@"; do
  case "$arg" in
    --check) MODE="check" ;;
    --fix)   MODE="fix" ;;
    --probe) PROBE=1 ;;
    *) printf '未知选项: %s\n' "$arg" >&2; exit 2 ;;
  esac
done

if [ -z "$PROJECT" ]; then
  printf '用法: bash %s <工程目录> [--check|--fix] [--probe]\n' "$0" >&2
  exit 2
fi
if [ ! -d "$PROJECT" ]; then
  printf '错误: 目录不存在: %s\n' "$PROJECT" >&2
  exit 2
fi
PROJECT=$(cd "$PROJECT" && pwd)

hdr() { printf '\n[%s] %s\n' "$1" "$2"; }

# 数 NUL 分隔清单的条数 = 数 NUL 字节数。
# ⚠️ 绝不用 `wc -l` —— 清单是 -z 的 NUL 分隔、没有换行，`wc -l` **恒为 0**。
# 这条纪律在 `.workbuddy/notes/2026-09-28-adoption-and-remediation-plan.md` §4.2 有实测记录：
# 一条专门用来防「计数器归零」的命令，自己成了「计数器归零」的新实例。
count_nul() { LC_ALL=C tr -cd '\0' < "$1" | wc -c | tr -d ' '; }

printf '=== windows-coding-standards C++ 工具链引导 ===\n'
printf '工程目录: %s\n' "$PROJECT"
printf '模式: %s%s\n' "$MODE" "$([ "$PROBE" -eq 1 ] && printf ' + probe')"

# ---------------------------------------------------------------------------
hdr 1 "检测工具链"
MISSING_TOOL=0
for t in clang-format clang-tidy; do
  if command -v "$t" >/dev/null 2>&1; then
    printf '  %s: %s\n' "$t" "$(LC_ALL=C "$t" --version 2>/dev/null | head -1)"
  else
    printf '  **缺失**: %s\n' "$t"
    MISSING_TOOL=$((MISSING_TOOL + 1))
  fi
done
if [ "$MISSING_TOOL" -gt 0 ]; then
  printf '\n错误: 缺 %s 个工具。\n' "$MISSING_TOOL" >&2
  printf '  本脚本**拒绝**在缺工具时给出任何「违规数」—— 那只会是假的 0。\n' >&2
  printf '  安装（三平台均可）: pip install clang-format clang-tidy   # PyPI 版本号形如 21.1.6\n' >&2
  printf '  LLVM 官方发行版亦可；注意有的发行版把 clang-tidy 与 clang-format 分在不同包里。\n' >&2
  exit 3
fi

# ---------------------------------------------------------------------------
hdr 2 "定位 C++ 源文件（NUL 分隔，先落盘再证明非空）"
TMPD=$(mktemp -d 2>/dev/null || mktemp -d -t wcs) || { printf '错误: 无法创建临时目录\n' >&2; exit 2; }
cleanup_tmp() { [ -n "${TMPD:-}" ] && [ -d "$TMPD" ] && rm -rf "$TMPD"; }
trap cleanup_tmp EXIT INT TERM

TU_LIST="$TMPD/tu.list"
HDR_LIST="$TMPD/hdr.list"
if git -C "$PROJECT" rev-parse --git-dir >/dev/null 2>&1; then
  git -C "$PROJECT" ls-files -z -- '*.cpp' '*.cc' '*.cxx' > "$TU_LIST"
  git -C "$PROJECT" ls-files -z -- '*.h' '*.hpp' '*.hh'   > "$HDR_LIST"
  printf '  清单来源: git ls-files（工程是 git 仓库，尊重 .gitignore）\n'
else
  (cd "$PROJECT" && LC_ALL=C find . -type f \( -name '*.cpp' -o -name '*.cc' -o -name '*.cxx' \) -print0) > "$TU_LIST"
  (cd "$PROJECT" && LC_ALL=C find . -type f \( -name '*.h' -o -name '*.hpp' -o -name '*.hh' \) -print0)   > "$HDR_LIST"
  printf '  清单来源: find（非 git 仓库 —— 会**包含**被版本控制忽略的文件）\n'
fi
TU_N=$(count_nul "$TU_LIST")
HDR_N=$(count_nul "$HDR_LIST")
if [ "$TU_N" -eq 0 ]; then
  printf '\n错误: 范围内**没有 C++ 编译单元** —— 这是**范围写错，不是"干净"**。\n' >&2
  printf '  默认只认 *.cpp / *.cc / *.cxx（头文件 %s 个）。\n' "$HDR_N" >&2
  printf '  若你的工程用别的后缀，请改本脚本的清单模式，别把「没扫到」读成「0 违规」。\n' >&2
  exit 4
fi
printf '  编译单元 %s 个 / 头文件 %s 个（分母，记进记录）\n' "$TU_N" "$HDR_N"

CDB="$PROJECT/build/compile_commands.json"
if [ -f "$CDB" ]; then
  printf '  编译数据库: %s\n' "$CDB"
else
  printf '  ⚠️ 编译数据库缺失（找的是 %s）—— clang-tidy 段将无法执行。\n' "$CDB"
  printf '     CMake 工程: cmake -S "%s" -B "%s/build" -DCMAKE_EXPORT_COMPILE_COMMANDS=ON\n' "$PROJECT" "$PROJECT"
  printf '     其它工程类型的三条替代路: 接入计划 §5.3（MSBuild 的 VS 生成器**不产出**该文件）。\n'
fi

# ---------------------------------------------------------------------------
hdr 3 "配置现状（缺哪一项就说哪一项，不给假基线）"
MISSING_CFG=0
for pair in "clang-format:.clang-format" "clang-tidy:.clang-tidy"; do
  f="${pair##*:}"
  if [ -f "$PROJECT/$f" ]; then
    printf '  已存在: %s\n' "$f"
  else
    printf '  **缺失**: %s\n' "$f"
    MISSING_CFG=$((MISSING_CFG + 1))
  fi
done
for f in .editorconfig; do
  if [ -f "$PROJECT/$f" ]; then
    printf '  已存在: %s（两侧共享，本脚本不安装）\n' "$f"
  else
    printf '  提示: %s 不存在 —— C# 侧会安装它；纯 C++ 工程也应有一份（跨语言项以它的 `[*]` 段为权威）。\n' "$f"
  fi
done

# .clang-format 被**整份拒绝读取**是这里最危险的失效模式（选项名写错 ⇒ 一条都不生效）
if [ -f "$PROJECT/.clang-format" ]; then
  CF_ERR=$(cd "$PROJECT" && LC_ALL=C clang-format -style=file -dump-config 2>&1 >/dev/null || true)
  if [ -z "$CF_ERR" ]; then
    printf '  .clang-format 能被干净读取（stderr 为空）\n'
  else
    printf '  ⚠️ .clang-format **被拒绝读取** —— 该文件里一条配置都不生效：\n'
    printf '%s\n' "$CF_ERR" | sed 's/^/        /'
  fi
fi
# .clang-tidy 的两种静默失效：Checks 折叠块标量、键名拼错（无提示）
if [ -f "$PROJECT/.clang-tidy" ]; then
  if grep -qE '^[[:space:]]*Checks[[:space:]]*:[[:space:]]*[>|]' "$PROJECT/.clang-tidy"; then
    printf '  ⚠️ .clang-tidy 的 `Checks:` 写成了折叠块标量 —— 块里的 `#` 是**内容不是注释**，\n'
    printf '     写在禁用项前的注释会把它粘成无效项，该禁用项**静默失效**。必须写成 YAML 列表。\n'
  fi
fi

if [ "$MISSING_CFG" -gt 0 ] && [ "$MODE" = "check" ]; then
  printf '\n  下一步: 加 --fix 从 skill 模板安装缺失的配置（只新增，不覆盖）。\n'
fi

# ---------------------------------------------------------------------------
hdr 4 "安装配置"
if [ "$MODE" = "fix" ]; then
  for pair in "clang-format:.clang-format" "clang-tidy:.clang-tidy"; do
    src="$ASSETS/${pair%%:*}"
    dst="$PROJECT/${pair##*:}"
    if [ ! -f "$src" ]; then
      printf '  错误: 模板缺失 %s\n' "$src" >&2
      exit 5
    fi
    if [ -f "$dst" ]; then
      printf '  跳过（已存在，绝不覆盖）: %s\n' "${pair##*:}"
    else
      cp "$src" "$dst" || { printf '  错误: 复制失败 %s\n' "$dst" >&2; exit 5; }
      # 核验副作用，不核验 cp 的退出码
      if [ -s "$dst" ]; then
        printf '  已安装: %s（%s 字节）\n' "${pair##*:}" "$(LC_ALL=C wc -c < "$dst" | tr -d ' ')"
      else
        printf '  错误: %s 复制后为空 —— 写操作被静默拦下\n' "$dst" >&2
        exit 5
      fi
    fi
  done
  printf '  注意: 复制后**先核对实际生效值再拿去用**（两个模板头部都有 `[待实测]` 说明）：\n'
  printf '        cd "%s" && clang-format -style=file -dump-config | grep -E "SortIncludes|IncludeBlocks|SeparateDefinitionBlocks"\n' "$PROJECT"
  printf '        ⚠️ 别把上面那支写成反例 `grep -E "SortIncludes[|]IncludeBlocks"` —— `[|]` 在 ERE 里是**字符类**不是交替，\n'
  printf '           那样写永远零命中且 exit 1，会以「输出为空」冒充「核对过了」（自检第 16 节拦）。\n'
else
  printf '  （--check 模式：不写任何文件）\n'
fi

# ---------------------------------------------------------------------------
hdr 5 "配置是否真的生效（--probe）"
if [ "$PROBE" -eq 1 ]; then
  PROBE_FILE="$PROJECT/.wcs-style-probe.cpp"
  if [ -e "$PROBE_FILE" ]; then
    printf '  跳过: %s 已存在，避免覆盖你的文件。\n' "$PROBE_FILE"
  else
    printf '  写入临时探针 %s（退出时自动删除）...\n' "$PROBE_FILE"
    cleanup_probe() { [ -f "$PROBE_FILE" ] && rm -f "$PROBE_FILE" && printf '  已删除探针文件。\n'; }
    trap 'cleanup_probe; cleanup_tmp' EXIT INT TERM
    cat > "$PROBE_FILE" <<'PROBE_EOF'
// 临时探针 —— 由 bootstrap_cpp_style.sh 生成，用于验证配置是否真的生效。
// 故意写坏两处，两处都对应模板里**真的配了的键**（写探针前先查模板，别凭印象）：
//   · 格式：`int  * p;` 的多余空格  → clang-format --dry-run --Werror 应 exit 1
//   · 命名：类名 `sample`（ClassCase=CamelCase）、全局量 `BadGlobal` / 成员 `BadMember`
//          （camelBack + 必须带 g_ / m_ 前缀）→ clang-tidy 应报 readability-identifier-naming
//          ⚠️ 反例：单字母成员 `p` **不**违规（它本身就是合法 camelBack）——
//             探针若这样写，「没报」会被误读成「配置没生效」。
namespace style_probe {

int BadGlobal = 0;

class sample
{
public:
    int  * BadMember;
};

}  // namespace style_probe
PROBE_EOF

    printf '\n  —— ① clang-format（验「格式配置是否生效」）——\n'
    CF_OUT=$(cd "$PROJECT" && LC_ALL=C clang-format --dry-run --Werror "$PROBE_FILE" 2>&1)
    CF_RC=$?
    if [ "$CF_RC" -ne 0 ]; then
      printf '    [命中] clang-format 报出未格式化（exit %s）—— 格式配置生效\n' "$CF_RC"
      printf '%s\n' "$CF_OUT" | head -4 | sed 's/^/        /'
    else
      printf '    [未报] clang-format exit 0 —— 探针的已知格式问题没被报出。\n'
      printf '           要么探针恰好符合当前配置，要么配置没生效。检查 .clang-format 是否被干净读取（见上节）。\n'
    fi

    printf '\n  —— ② clang-tidy（验「检查项与命名规则是否生效」）——\n'
    if [ -f "$PROJECT/.clang-tidy" ]; then
      printf '        （工程内已有 .clang-tidy —— clang-tidy 会**自动读取**它）\n'
    else
      printf '        ⚠️ 工程内**没有** .clang-tidy ⇒ 本次只验工具本身，验不了配置。\n'
    fi
    CT_OUT=$(cd "$PROJECT" && LC_ALL=C clang-tidy "$PROBE_FILE" -- -std=c++17 2>&1)
    CT_RC=$?
    if printf '%s' "$CT_OUT" | grep -qE 'readability-identifier-naming|warning:'; then
      printf '    [命中] clang-tidy 报出已知违规 —— 检查项与命名规则生效\n'
      printf '           （注意 clang-tidy **不因 warning 变非 0**，退出码 %s 不代表没报；这里看的是输出）\n' "$CT_RC"
      printf '%s\n' "$CT_OUT" | grep -E 'warning:' | head -4 | sed 's/^/        /'
    else
      printf '    [未报] clang-tidy 没有报出命名违规（exit %s）。\n' "$CT_RC"
      printf '           命名规则靠 `.clang-tidy` 的 `CheckOptions` 驱动；为空 = 完全没查（正文 §5.4）。\n'
    fi

    printf '\n  ⚠️ 本探针只验「工具 + 配置」。工程内**真实文件**不报而探针报，几乎总是作用域没覆盖到。\n'
    printf '     另：`int b = (int)d;` 一类**编译期**开关（-Wconversion 等）**不在本脚本职责内** ——\n'
    printf '     那要求把开关注入工程自己的构建系统，见接入计划 §4.1。\n'
  fi
else
  printf '  （未启用。加 --probe 可在工程里临时写一个已知违规文件，验证配置确实生效 ——\n'
  printf '   这一步是本侧唯一能证伪「假基线」的手段，建议首次接入时跑一次。）\n'
fi

# ---------------------------------------------------------------------------
hdr 6 "下一步：采数字"
printf '  本脚本只负责「检测 + 安装 + 验活」，**不产出违规数字**。采数字用同目录的脚本：\n'
printf '\n      bash "%s/baseline_cpp_style.sh" "%s"\n' "$SCRIPT_DIR" "$PROJECT"
printf '\n  为什么分开：配置缺失时采到的数字是**假基线**（工具没读配置，不等于代码干净），\n'
printf '  而 baseline 脚本会把「清单为空 / 缺工具 / 缺编译数据库」三种情况**一律判为非零退出**，\n'
printf '  不给你一个漂亮的 0。\n'

exit 0
