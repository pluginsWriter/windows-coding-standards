#!/usr/bin/env bash
# =============================================================================
# windows-coding-standards —— 工具链安装与基线采集
# =============================================================================
# 用法:
#   bash scripts/bootstrap_dotnet_style.sh <工程目录> --check    # 只读：检测 + 报告（默认）
#   bash scripts/bootstrap_dotnet_style.sh <工程目录> --fix      # 安装配置（会写工程根，不改源码）
#   bash scripts/bootstrap_dotnet_style.sh <工程目录> --check --probe
#                                                              # 追加「配置真的生效吗」探针
#
# 退出码:
#   0 成功
#   2 用法错误
#   3 找不到 .NET SDK —— **明确失败，不产出任何基线数字**
#   4 工程目录里找不到 .sln / .csproj
#   5 配置安装失败
#
# 设计纪律（照搬 Swift 版的教训）:
#   · **配置缺失 = 假基线，必须挡住**。若目录里没有 .editorconfig / Directory.Build.props，
#     报出的「0 违规」毫无意义 —— 本脚本会先说明缺什么，而不是给你一个漂亮的 0。
#   · **只新增、绝不覆盖**已有配置。工程自己的 .editorconfig 优先。
#   · **核验副作用，不核验退出码**（Swift 侧踩过：补丁被静默拦下却返回 0）。
#
# ⚠️ 本脚本**尚未在装有 .NET SDK 的机器上实跑过**（本机是 macOS、无 SDK）。
#    首次在有 SDK 的机器上使用时，请先跑 --check --probe，把实际行为记回正文附录 D。
#    `--probe` 会在工程目录里**临时**写入并删除一个探针文件（有 trap 兜底清理）。
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

printf '=== windows-coding-standards 工具链引导 ===\n'
printf '工程目录: %s\n' "$PROJECT"
printf '模式: %s%s\n' "$MODE" "$([ "$PROBE" -eq 1 ] && printf ' + probe')"

# ---------------------------------------------------------------------------
hdr 1 "检测 .NET SDK"
if ! command -v dotnet >/dev/null 2>&1; then
  printf '\n错误: 找不到 dotnet 命令。\n' >&2
  printf '  本脚本**拒绝**在缺少 SDK 的情况下给出任何「违规数」—— 那只会是假的 0。\n' >&2
  printf '  请先安装 .NET SDK 6+：https://dotnet.microsoft.com/download\n' >&2
  exit 3
fi
SDK_VERSION=$(dotnet --version 2>/dev/null)
SDK_MAJOR=$(printf '%s' "$SDK_VERSION" | cut -d. -f1)
printf '  dotnet: %s\n' "$SDK_VERSION"
if [ "${SDK_MAJOR:-0}" -lt 6 ] 2>/dev/null; then
  printf '  警告: dotnet format 需要 .NET SDK 6 或更高（当前 %s）。\n' "$SDK_VERSION"
fi

# ---------------------------------------------------------------------------
hdr 2 "定位工程文件"
SLN=$(find "$PROJECT" -maxdepth 2 -name '*.sln' -print 2>/dev/null | head -1)
if [ -n "$SLN" ]; then
  TARGET="$SLN"
  printf '  解决方案: %s\n' "$SLN"
else
  CSPROJ=$(find "$PROJECT" -maxdepth 3 -name '*.csproj' -print 2>/dev/null | head -1)
  if [ -n "$CSPROJ" ]; then
    TARGET="$CSPROJ"
    printf '  项目: %s\n' "$CSPROJ"
    printf '  提示: 多项目工程建议在解决方案根放置 Directory.Build.props，只认解决方案级配置。\n'
  else
    printf '\n错误: 在 %s 下（深度 3 以内）找不到 .sln 或 .csproj。\n' "$PROJECT" >&2
    exit 4
  fi
fi

# ---------------------------------------------------------------------------
hdr 3 "配置现状（缺哪一项就说明哪一项，不给假基线）"
MISSING=0
for f in .editorconfig Directory.Build.props; do
  if [ -f "$PROJECT/$f" ]; then
    printf '  已存在: %s\n' "$f"
  else
    printf '  **缺失**: %s\n' "$f"
    MISSING=$((MISSING + 1))
  fi
done

if [ -f "$PROJECT/.editorconfig" ]; then
  if grep -qE '^\s*root\s*=\s*true' "$PROJECT/.editorconfig"; then
    printf '  .editorconfig 含 root = true（在层级链上，能生效）\n'
  else
    printf '  ⚠️ .editorconfig **没有 root = true**：若上层没有另一个 root，配置可能不被加载。\n'
  fi
  OPT_SEV=$(grep -nE '^[a-zA-Z_]+ *= *[a-zA-Z_]+:(error|warning|suggestion|silent|none)([[:space:]]|$)' "$PROJECT/.editorconfig" || true)
  if [ -n "$OPT_SEV" ]; then
    printf '  ⚠️ 发现「选项式 severity」—— .NET 8 及更早构建时**不生效**，须改为 dotnet_diagnostic.<ID>.severity：\n'
    printf '%s\n' "$OPT_SEV" | sed 's/^/        /'
  fi
fi

if [ "$MISSING" -gt 0 ] && [ "$MODE" = "check" ]; then
  printf '\n  下一步: 加 --fix 从 skill 模板安装缺失的配置（只新增，不覆盖）。\n'
fi

# ---------------------------------------------------------------------------
hdr 4 "安装配置"
if [ "$MODE" = "fix" ]; then
  for pair in "editorconfig:.editorconfig" "Directory.Build.props:Directory.Build.props"; do
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
      printf '  已安装: %s\n' "${pair##*:}"
    fi
  done
  printf '  注意: assets/stylecop.json **不**自动安装 —— 只有决定引入 StyleCop 时才用（正文 §7.3）。\n'
else
  printf '  （--check 模式：不写任何文件）\n'
fi

# ---------------------------------------------------------------------------
hdr 5 "配置是否真的生效（--probe）"
if [ "$PROBE" -eq 1 ]; then
  PROBE_FILE="$PROJECT/StyleProbe.cs"
  if [ -e "$PROBE_FILE" ]; then
    printf '  跳过: %s 已存在，避免覆盖你的文件。\n' "$PROBE_FILE"
  else
    printf '  写入临时探针 %s（退出时自动删除）...\n' "$PROBE_FILE"
    cleanup() { [ -f "$PROBE_FILE" ] && rm -f "$PROBE_FILE" && printf '  已删除探针文件。\n'; }
    trap cleanup EXIT INT TERM
    cat > "$PROBE_FILE" <<'PROBE_EOF'
// 临时探针 —— 由 bootstrap_dotnet_style.sh 生成，用于验证配置是否真的生效。
// 预期命中：IDE1006（私有字段应为 _camelCase）、CS1591（公开成员缺 XML 文档）、
//           IDE0011 / IDE0055（缺花括号）。
namespace StyleProbe;

internal sealed class StyleProbeSample
{
    private string BadField;

    public void Method()
    {
        if (true)
            return;
    }
}
PROBE_EOF
    PROBE_OUT=$(dotnet build "$TARGET" -warnaserror --nologo 2>&1 || true)
    HIT=0
    for id in IDE1006 CS1591 IDE0011 IDE0055; do
      if printf '%s' "$PROBE_OUT" | grep -qE "\b$id\b"; then
        printf '    [命中] %s\n' "$id"
        HIT=$((HIT + 1))
      else
        printf '    [未报] %s\n' "$id"
      fi
    done
    if [ "$HIT" -ge 2 ]; then
      printf '  判定: **配置生效**（能报出已知违规）。基线数字可信。\n'
    else
      printf '  判定: **配置未生效或未覆盖** —— 探针的已知违规没被报出来，\n'
      printf '        此时任何「0 违规」都是假基线。检查 EnforceCodeStyleInBuild 与 severity 语法。\n'
    fi
  fi
else
  printf '  （未启用。加 --probe 可在工程里临时写一个已知违规文件，验证配置确实生效 ——\n'
  printf '   这一步是本侧唯一能证伪「假基线」的手段，建议首次接入时跑一次。）\n'
fi

# ---------------------------------------------------------------------------
hdr 6 "违规基线"
BUILD_OUT=$(dotnet build "$TARGET" -warnaserror --nologo 2>&1 || true)
printf '\n  —— 按规则 ID 汇总（构建期）——\n'
printf '%s' "$BUILD_OUT" | grep -oE '\b(CA|IDE|CS|SA|RCS|SYSLIB)[0-9]{4}\b' \
  | sort | uniq -c | sort -rn | head -40 | sed 's/^/    /'
BUILD_TOTAL=$(printf '%s' "$BUILD_OUT" | grep -oE '\b(CA|IDE|CS|SA|RCS|SYSLIB)[0-9]{4}\b' | wc -l | tr -d ' ')

printf '\n  —— dotnet format --verify-no-changes（只读）——\n'
FORMAT_OUT=$(dotnet format "$TARGET" --verify-no-changes --no-restore 2>&1)
FORMAT_RC=$?
printf '%s\n' "$FORMAT_OUT" | tail -20 | sed 's/^/    /'
FORMAT_FILES=$(printf '%s' "$FORMAT_OUT" | grep -cE "violates rule|require formatting" || true)

printf '\n  —— 统计 ——\n'
printf '    构建期诊断条数: %s\n' "$BUILD_TOTAL"
printf '    format 退出码: %s（非 0 说明有未格式化文件）\n' "$FORMAT_RC"
printf '    format 涉及文件数（估算）: %s\n' "$FORMAT_FILES"

cat <<'NEXT'

  ⚠️ 关于这份基线，三件事必须同时说明，否则它会被误读：
    1. **N 处违规 ≠ 代码很糟**。规则是分档开的（正文 §8），当前只开了第一批；
       改规则档位后必须重采，否则前后数字不可比。
    2. **dotnet format 只修它支持自动修的部分**。命名、文档、魔法值、设计约束它不碰。
    3. **本基线不覆盖** 函数行数 / 类型行数 / 参数个数 —— 这三项在 C# 侧没有内置规则，
       只能人工评审（正文 §5.3）。别把「工具没报」当成「没问题」。
NEXT

exit 0
