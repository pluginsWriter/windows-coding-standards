#!/usr/bin/env bash
# =============================================================================
# windows-coding-standards —— 内部一致性自检（纯静态，不调用 dotnet）
# =============================================================================
# 为什么需要它：SKILL.md、规范正文、缺陷目录、assets 配置模板之间存在多处
# **同一事实的副本**（缩进、行尾、case 缩进、命名前缀、三档类数、待实测条数、版本号）。
# 手抄副本必然漂移 —— 这正是 Swift 版当年 `drain` 事件与 703 处漏检的根因。
#
# 纪律：**期望值一律从单一权威来源推导**（阈值取自 assets 模板、条数取自正文表格行数），
#       不在本脚本里写第二份硬编码 —— 硬编码只会制造下一个漂移源。
#
# 用法:
#   bash scripts/verify_consistency.sh            # 不一致记 FAIL
#   bash scripts/verify_consistency.sh --strict   # 已声明的待决项也记 FAIL
#
# 退出码: 0 通过 / 1 有 FAIL / 2 用法错误 / 3 关键文件缺失
#
# 注意：本脚本只做静态核对，不验证任何 .NET 工具的实际行为。
#       本机（macOS）没有 .NET SDK，故「跑一次看行为」这条路在此不可用。
# 字符处理纪律：本脚本一律用 `grep -E`，不用 BRE 的 `\|` —— BSD grep 不支持它，
#       会静默退化成搜字面量、无输出，极易误判成「文件里没有」。
# =============================================================================

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SKILL_DIR=$(cd "$SCRIPT_DIR/.." && pwd)

STRICT=0
[ "${1:-}" = "--strict" ] && STRICT=1

SKILL_MD="$SKILL_DIR/SKILL.md"
MAIN="$SKILL_DIR/references/csharp-coding-standards.md"
CATALOG="$SKILL_DIR/references/defect-catalog.md"
EC="$SKILL_DIR/assets/editorconfig"
PROPS="$SKILL_DIR/assets/Directory.Build.props"
STYLECOP="$SKILL_DIR/assets/stylecop.json"

FAIL=0
WARN=0

pass() { printf '  PASS  %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }
warn() { printf '  WARN  %s\n' "$1"; WARN=$((WARN + 1)); }
hdr()  { printf '\n[%s] %s\n' "$1" "$2"; }

# 取一个文件里某个自定义键的值（`key = value` 形式，忽略注释行）
ec_value() { grep -E "^$2 *=" "$1" | head -1 | sed 's/^[^=]*=[[:space:]]*//' | sed 's/[[:space:]]*$//'; }

# 数某个 Markdown 二级标题段落里的 `| <数字> |` 表格行数
count_rows_in_section() {
  awk -v want="$2" '
    /^## / { sec = ($0 ~ want) ? 1 : 0; next }
    sec && /^\| [0-9]+ \|/ { n++ }
    END { print n + 0 }
  ' "$1"
}

for f in "$SKILL_MD" "$MAIN" "$CATALOG" "$EC" "$PROPS" "$STYLECOP"; do
  if [ ! -f "$f" ]; then
    printf 'FATAL: 关键文件缺失: %s\n' "$f" >&2
    exit 3
  fi
done

printf '=== windows-coding-standards 一致性自检 ===\n'
printf 'skill 目录: %s\n' "$SKILL_DIR"

# ---------------------------------------------------------------------------
hdr 1 "frontmatter 与目录名一致（.agents / WorkBuddy 等发现机制的前提）"
NAME_IN_FM=$(grep -E '^name:' "$SKILL_MD" | head -1 | sed 's/^name:[[:space:]]*//')
DIR_NAME=$(basename "$SKILL_DIR")
if [ "$NAME_IN_FM" = "$DIR_NAME" ]; then
  pass "frontmatter name == 目录名（$DIR_NAME）"
else
  fail "frontmatter name '$NAME_IN_FM' != 目录名 '$DIR_NAME'"
fi
if grep -qE '^agent_created: true$' "$SKILL_MD"; then
  pass "agent_created: true 已声明"
else
  warn "缺少 agent_created: true（模型自建 skill 的标识）"
fi

# ---------------------------------------------------------------------------
hdr 2 "SKILL.md 里引用的资产路径必须真实存在（防悬空引用）"
MISSING_REF=0
for rel in $(grep -oE '`(assets|scripts|references)/[A-Za-z0-9._/-]+`' "$SKILL_MD" | tr -d '`' | sort -u); do
  if [ ! -e "$SKILL_DIR/$rel" ]; then
    fail "SKILL.md 引用了不存在的路径: $rel"
    MISSING_REF=1
  fi
done
[ "$MISSING_REF" -eq 0 ] && pass "全部资产引用均存在"

# ---------------------------------------------------------------------------
hdr 3 "版权边界：本版不得内置官方来源快照（正文 §7.4）"
if [ -d "$SKILL_DIR/references/official" ]; then
  OFFICIAL_COUNT=$(find "$SKILL_DIR/references/official" -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
  if [ "$OFFICIAL_COUNT" -gt 0 ]; then
    fail "出现了 $OFFICIAL_COUNT 个官方来源快照 —— C#/.NET 侧权威是书与 Learn 页面，不可整篇内置（正文 §7.4）"
  else
    pass "references/official 目录为空壳，无快照"
  fi
else
  pass "未内置官方来源快照（符合正文 §7.4）"
fi

# ---------------------------------------------------------------------------
hdr 4 "缩进与行尾：模板与正文取值一致（正文 §4.3）"
TPL_INDENT=$(ec_value "$EC" 'indent_size')
TPL_STYLE=$(ec_value "$EC" 'indent_style')
DOC_INDENT=$(grep -oE 'indent_size = [0-9]+' "$MAIN" | head -1 | sed 's/.*= *//')
DOC_STYLE=$(grep -oE 'indent_style = [a-z]+' "$MAIN" | head -1 | sed 's/.*= *//')
if [ -n "$DOC_INDENT" ] && [ "$TPL_INDENT" = "$DOC_INDENT" ]; then
  pass "indent_size 一致（$TPL_INDENT）"
elif [ -z "$DOC_INDENT" ]; then
  warn "正文里推导不出 indent_size，无法比对"
else
  fail "indent_size 不一致：模板=$TPL_INDENT 正文=$DOC_INDENT"
fi
if [ -n "$DOC_STYLE" ] && [ "$TPL_STYLE" = "$DOC_STYLE" ]; then
  pass "indent_style 一致（$TPL_STYLE）"
elif [ -z "$DOC_STYLE" ]; then
  warn "正文里推导不出 indent_style，无法比对"
else
  fail "indent_style 不一致：模板=$TPL_STYLE 正文=$DOC_STYLE"
fi

if [ -n "$(ec_value "$EC" 'end_of_line')" ]; then
  pass "end_of_line 已显式写死（正文 §4.3 要求不得留空默认）"
else
  fail "模板里 end_of_line 为空 —— 正文 §4.3 要求必须显式指定"
fi

# ---------------------------------------------------------------------------
hdr 5 "case 缩进：模板与正文一致，且不得与 Swift 侧取值混用（正文 §4.3）"
TPL_CASE=$(ec_value "$EC" 'csharp_indent_switch_labels')
DOC_CASE=$(grep -oE 'csharp_indent_switch_labels = [a-z]+' "$MAIN" | head -1 | sed 's/.*= *//')
if [ -n "$DOC_CASE" ] && [ "$TPL_CASE" = "$DOC_CASE" ]; then
  pass "csharp_indent_switch_labels 一致（$TPL_CASE）"
else
  fail "csharp_indent_switch_labels 不一致：模板=${TPL_CASE:-<空>} 正文=${DOC_CASE:-<推导不出>}"
fi

# ---------------------------------------------------------------------------
hdr 6 "行长：正文若已定值则必须与模板一致，未定值记 WARN（正文 §4.4 待实测）"
TPL_LINE=$(ec_value "$EC" 'max_line_length')
DOC_LINE=$(grep -oE 'max_line_length = [0-9]+|行长上限为 [0-9]+|行长 [0-9]+ 列' "$MAIN" | head -1 | grep -oE '[0-9]+')
if [ -n "$DOC_LINE" ]; then
  if [ "$TPL_LINE" = "$DOC_LINE" ]; then
    pass "行长一致（$TPL_LINE）"
  else
    fail "行长不一致：模板=$TPL_LINE 正文=$DOC_LINE"
  fi
else
  warn "正文未给出行长数值，模板单方面取 $TPL_LINE —— 该值目前只是 SHOULD，不得写成 MUST（附录 D 第 2 条未销项前）"
fi

# ---------------------------------------------------------------------------
hdr 7 "命名前缀：模板的 required_prefix 必须覆盖正文 §3.4 声明的两项"
DOC_INSTANCE=$(grep -oE '`_camelCase`' "$MAIN" | head -1 | tr -d '`')
DOC_STATIC=$(grep -oE '`s_camelCase`' "$MAIN" | head -1 | tr -d '`')
PREFIX_INSTANCE=$(printf '%s' "$DOC_INSTANCE" | sed 's/camelCase$//')
PREFIX_STATIC=$(printf '%s' "$DOC_STATIC" | sed 's/camelCase$//')
TPL_PREFIXES=$(grep -E '^dotnet_naming_style\..*\.required_prefix *=' "$EC" | sed 's/.*=[[:space:]]*//' | sort -u | tr '\n' ' ')
if [ -z "$PREFIX_INSTANCE" ] || [ -z "$PREFIX_STATIC" ]; then
  warn "正文 §3.4 里推导不出私有字段前缀，无法比对"
else
  ok=1
  for p in "$PREFIX_INSTANCE" "$PREFIX_STATIC"; do
    printf '%s' "$TPL_PREFIXES" | grep -qE "(^| )$(printf '%s' "$p" | sed 's/[].[*^$/\\]/\\&/g')( |$)" || ok=0
  done
  if [ "$ok" -eq 1 ]; then
    pass "私有实例 / 静态字段前缀与正文一致（$PREFIX_INSTANCE / $PREFIX_STATIC）"
  else
    fail "模板缺少正文声明的私有字段前缀（应为 $PREFIX_INSTANCE / $PREFIX_STATIC，实为: $TPL_PREFIXES）"
  fi
fi

# ---------------------------------------------------------------------------
hdr 8 "severity 语法：模板不得出现「选项式 severity」（正文 §7.2）"
OPT_SEV=$(grep -nE '^[a-zA-Z_]+ *= *[a-zA-Z_]+:(error|warning|suggestion|silent|none)([[:space:]]|$)' "$EC" || true)
if [ -z "$OPT_SEV" ]; then
  pass "无选项式 severity（构建期强制一律走规则 ID 式）"
else
  fail "发现选项式 severity —— .NET 8 及更早构建时不生效，须改为 dotnet_diagnostic.<ID>.severity:"
  printf '%s\n' "$OPT_SEV" | sed 's/^/        /'
fi

BAD_SEV=$(grep -E '^dotnet_diagnostic\.[A-Za-z0-9]+\.severity *=' "$EC" \
  | sed 's/.*=[[:space:]]*//' | grep -vE '^(none|silent|suggestion|warning|error)$' || true)
if [ -z "$BAD_SEV" ]; then
  pass "severity 取值均在合法集合内"
else
  fail "非法的 severity 取值: $(printf '%s' "$BAD_SEV" | tr '\n' ' ')"
fi

# ---------------------------------------------------------------------------
hdr 9 "枚举类事实：SKILL.md 声明的类数 / 条数必须等于正文表格实际行数"
read -r C1 C2 C3 <<EOF
$(awk '
  /^## / { sec = ($0 ~ /一档/) ? 1 : (($0 ~ /二档/) ? 2 : (($0 ~ /三档/) ? 3 : 0)); next }
  sec && /^\| [0-9]+ \|/ { if (sec==1) a++; else if (sec==2) b++; else if (sec==3) c++ }
  END { print a+0, b+0, c+0 }
' "$CATALOG")
EOF
DECL=$(grep -oE '（[0-9]+ 类）' "$SKILL_MD" | grep -oE '[0-9]+' | tr '\n' ' ' | sed 's/ *$//')
DECL1=$(printf '%s' "$DECL" | awk '{print $1}')
DECL2=$(printf '%s' "$DECL" | awk '{print $2}')
DECL3=$(printf '%s' "$DECL" | awk '{print $3}')
if [ -z "$DECL1" ]; then
  warn "SKILL.md 里推导不出三档类数声明，无法比对"
else
  [ "$DECL1" = "$C1" ] && pass "一档类数一致（$C1）" || fail "一档类数不一致：SKILL.md=$DECL1 缺陷目录实际=$C1"
  [ "$DECL2" = "$C2" ] && pass "二档类数一致（$C2）" || fail "二档类数不一致：SKILL.md=$DECL2 缺陷目录实际=$C2"
  [ "$DECL3" = "$C3" ] && pass "三档类数一致（$C3）" || fail "三档类数不一致：SKILL.md=$DECL3 缺陷目录实际=$C3"
fi

D_ROWS=$(count_rows_in_section "$MAIN" '附录 D')
D_DECL=$(grep -oE '附录 D\*\*（[0-9]+ 条）|附录 D（[0-9]+ 条）' "$SKILL_MD" | grep -oE '[0-9]+' | head -1)
if [ -z "$D_DECL" ]; then
  warn "SKILL.md 里推导不出待实测条数，无法比对"
elif [ "$D_DECL" = "$D_ROWS" ]; then
  pass "待实测条数一致（$D_ROWS）"
else
  fail "待实测条数不一致：SKILL.md=$D_DECL 正文附录 D 实际=$D_ROWS 行"
fi

# ---------------------------------------------------------------------------
hdr 10 "版本号：四处必须一致（正文头部 / 正文变更记录末行 / 缺陷目录头部 / SKILL.md）"
V_HEAD=$(grep -oE '^> 版本：v[0-9]+(\.[0-9]+)*' "$MAIN" | head -1 | grep -oE 'v[0-9].*')
V_LAST=$(grep -oE '^\| v[0-9]+(\.[0-9]+)* \|' "$MAIN" | tail -1 | grep -oE 'v[0-9].*[0-9]')
V_CAT=$(grep -oE '^> 版本：v[0-9]+(\.[0-9]+)*' "$CATALOG" | head -1 | grep -oE 'v[0-9].*')
V_SKILL=$(grep -oE 'v[0-9]+\.[0-9]+(\.[0-9]+)*' "$SKILL_MD" | head -1)
if [ -z "$V_HEAD" ] || [ -z "$V_LAST" ] || [ -z "$V_CAT" ] || [ -z "$V_SKILL" ]; then
  warn "有版本号推导不出来：正文头部=${V_HEAD:-?} 变更记录=${V_LAST:-?} 缺陷目录=${V_CAT:-?} SKILL.md=${V_SKILL:-?}"
else
  if [ "$V_HEAD" = "$V_LAST" ] && [ "$V_HEAD" = "$V_CAT" ] && [ "$V_HEAD" = "$V_SKILL" ]; then
    pass "四处版本号一致（$V_HEAD）"
  else
    fail "版本号不一致：正文头部=$V_HEAD 变更记录=$V_LAST 缺陷目录=$V_CAT SKILL.md=$V_SKILL"
  fi
fi

# ---------------------------------------------------------------------------
hdr 11 "已声明的待决项（--strict 下降为 FAIL）"
PENDING=0

# JS 侧 stylecop.json 的占位符必须被填掉才能启用 SA1633
if grep -q 'TODO 填写' "$STYLECOP"; then
  warn "stylecop.json 的 companyName / copyrightText 仍是占位符（仅在引入 StyleCop 前需填）"
  PENDING=$((PENDING + 1))
fi

# 模板里保留的 [待实测] 说明必须与正文附录 D 对得上
EC_PENDING=$(grep -c '\[待实测\]' "$EC" || true)
if [ "$EC_PENDING" -gt 0 ]; then
  warn "assets/editorconfig 内有 $EC_PENDING 处 [待实测] 标记 —— 销项后须同步清理，勿让标记与结论长期并存"
  PENDING=$((PENDING + 1))
fi

if [ "$PENDING" -eq 0 ]; then
  pass "无未决项"
fi

# ---------------------------------------------------------------------------
printf '\n=== 结果：FAIL %d / WARN %d ===\n' "$FAIL" "$WARN"
if [ "$FAIL" -gt 0 ]; then
  printf '结论：不一致（须修正后再集成）\n'
  exit 1
fi
if [ "$STRICT" -eq 1 ] && [ "$WARN" -gt 0 ]; then
  printf '结论：--strict 下待决项也算不通过\n'
  exit 1
fi
printf '结论：一致性通过\n'
exit 0
