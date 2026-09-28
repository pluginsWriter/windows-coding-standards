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
#   bash scripts/verify_consistency.sh            # 不一致记 FAIL；WARN 只提示
#   bash scripts/verify_consistency.sh --strict   # **任何 WARN**（含已声明的待决项）也判不通过
#
# 退出码: 0 通过 / 1 有 FAIL（--strict 下 WARN 也计入）/ 2 用法错误 / 3 关键文件缺失
#
# ⚠️ 2026-09-28 修：本条注释过去写「--strict # 已声明的待决项也记 FAIL」，而实现判的是
#    `WARN > 0`（第 11 节的待决项只是 WARN 的一个子集）⇒ **注释与实现不符**。现按实现更正。
#    同时补上参数校验 —— 过去没有 `exit 2`，未知参数被**静默忽略**（`--stict` 会退化成
#    非严格模式并 exit 0，假绿），而头部却声明了「2 用法错误」。
#
# 注意：本脚本只做静态核对，不验证任何 .NET 工具的实际行为。
#       本机（macOS）没有 .NET SDK，故「跑一次看行为」这条路在此不可用。
# 字符处理纪律：本脚本一律用 `grep -E`，表示字面竖线一律写 `[|]`。
#   不要用 BRE 的 `\|` —— BSD grep 不支持它，会静默退化成搜字面量、无输出，
#   极易误判成「文件里没有」。
#   更不要在 awk 里通过 `-v` 传含 `\|` 的 pattern —— awk 的 ERE 里 `\|` 是**未定义行为**，
#   mawk 会直接报 "illegal primary in regular expression" 并中止。
# =============================================================================

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SKILL_DIR=$(cd "$SCRIPT_DIR/.." && pwd)

STRICT=0
# 递归护栏：第 18 节会以「坏参数」再调一次本脚本做真功能验证。若参数校验本身坏了，
# 子进程会跑到第 18 节又调一次自己 —— **无限递归**（2026-09-28 负向测试实测跑到被杀）。
# 故子进程带此标记，见到就整节跳过。
SELFTEST_NESTED=${WCS_SELFTEST_NESTED:-0}
if [ "$#" -gt 1 ]; then
  printf '用法：%s [--strict]（只接受 0 或 1 个参数，实收 %d 个）\n' "$(basename "$0")" "$#" >&2
  exit 2
fi
case "${1:-}" in
  "")       : ;;
  --strict) STRICT=1 ;;
  *)
    printf '用法：%s [--strict]\n' "$(basename "$0")" >&2
    printf '未知参数：%s（过去会被静默忽略 → 假绿，现记用法错误）\n' "$1" >&2
    exit 2
    ;;
esac

SKILL_MD="$SKILL_DIR/SKILL.md"
README="$SKILL_DIR/README.md"

# --- C#/.NET 侧（唯一权威：assets/ 模板 + 正文表格）-------------------------
MAIN="$SKILL_DIR/references/csharp-coding-standards.md"
CATALOG="$SKILL_DIR/references/csharp-defect-catalog.md"
EC="$SKILL_DIR/assets/editorconfig"
PROPS="$SKILL_DIR/assets/Directory.Build.props"
STYLECOP="$SKILL_DIR/assets/stylecop.json"

# --- C++ 侧（唯一权威：assets/clang-* 模板 + 正文表格）----------------------
CPP_MAIN="$SKILL_DIR/references/cpp-coding-standards.md"
CPP_CATALOG="$SKILL_DIR/references/cpp-defect-catalog.md"
CPP_NAMING="$SKILL_DIR/references/cpp-naming-antipatterns.md"
CLANG_FORMAT="$SKILL_DIR/assets/clang-format"
CLANG_TIDY="$SKILL_DIR/assets/clang-tidy"

# --- 跨语言（判据层共享，检测命令分语言）------------------------------------
GRANULARITY="$SKILL_DIR/references/design-granularity.md"
CHANGE_DISC="$SKILL_DIR/references/change-discipline.md"
SHARED_JUDGMENT="$GRANULARITY $CHANGE_DISC"

FAIL=0
WARN=0

pass() { printf '  PASS  %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }
warn() { printf '  WARN  %s\n' "$1"; WARN=$((WARN + 1)); }
hdr()  { printf '\n[%s] %s\n' "$1" "$2"; }

# 取一个文件里某个自定义键的值（`key = value` 形式，忽略注释行）
ec_value() { grep -E "^$2 *=" "$1" | head -1 | sed 's/^[^=]*=[[:space:]]*//' | sed 's/[[:space:]]*$//'; }

# 取 clang 风格配置里某个键的值（`Key: value` 形式，忽略注释行）
cl_value() { grep -E "^$2 *:" "$1" | head -1 | sed 's/^[^:]*:[[:space:]]*//' | sed 's/[[:space:]]*$//'; }

# 数某个 Markdown 二级标题段落里的表格行数（pat 为行首匹配式）
# 注意：pattern 里表示字面竖线要用 `[|]`，**不要用 `\|`** —— awk 的 ERE 里
#       `\|` 是未定义行为，mawk 会直接报 "illegal primary in regular expression"。
count_rows_in_section() {
  awk -v want="$2" -v pat="$3" '
    /^## / { sec = ($0 ~ want) ? 1 : 0; next }
    sec && $0 ~ pat { n++ }
    END { print n + 0 }
  ' "$1"
}

for f in "$SKILL_MD" "$MAIN" "$CATALOG" "$EC" "$PROPS" "$STYLECOP" \
         "$CPP_MAIN" "$CPP_CATALOG" "$CPP_NAMING" "$CLANG_FORMAT" "$CLANG_TIDY" \
         $SHARED_JUDGMENT; do
  if [ ! -f "$f" ]; then
    printf 'FATAL: 关键文件缺失: %s\n' "$f" >&2
    exit 3
  fi
done

printf '=== windows-coding-standards 一致性自检（C#/.NET + C++ 双侧）===\n'
printf 'skill 目录: %s\n' "$SKILL_DIR"

# ---------------------------------------------------------------------------
hdr 1 "frontmatter 与目录名一致（.agents / WorkBuddy 等发现机制的前提）"
NAME_IN_FM=$(grep -E '^name:' "$SKILL_MD" | head -1 | sed 's/^name:[[:space:]]*//')
DIR_NAME=$(basename "$SKILL_DIR")
if [ "$NAME_IN_FM" = "$DIR_NAME" ]; then
  pass "frontmatter name == 目录名（${DIR_NAME}）"
else
  fail "frontmatter name '$NAME_IN_FM' != 目录名 '$DIR_NAME'"
fi
if grep -qE '^agent_created: true$' "$SKILL_MD"; then
  pass "agent_created: true 已声明"
else
  warn "缺少 agent_created: true（模型自建 skill 的标识）"
fi

# ---------------------------------------------------------------------------
hdr 2 "引用的资产路径必须真实存在（防悬空引用；覆盖 SKILL.md / README / 两侧正文与目录）"
MISSING_REF=0
SRC_FILES="$SKILL_MD $README $MAIN $CATALOG $CPP_MAIN $CPP_CATALOG $CPP_NAMING $GRANULARITY $CHANGE_DISC"
# 形式一：反引号路径 `assets/xxx`
for rel in $(grep -hoE '`(assets|scripts|references)/[A-Za-z0-9._/-]+`' $SRC_FILES 2>/dev/null | tr -d '`' | sort -u); do
  if [ ! -e "$SKILL_DIR/$rel" ]; then
    fail "引用了不存在的路径（反引号形式）: $rel"
    MISSING_REF=1
  fi
done
# 形式二：Markdown 链接 [..](references/xxx.md)
for rel in $(grep -hoE '\]\((assets|scripts|references)/[A-Za-z0-9._/-]+\)' $SRC_FILES 2>/dev/null | sed 's/^](//' | sed 's/)$//' | sort -u); do
  if [ ! -e "$SKILL_DIR/$rel" ]; then
    fail "引用了不存在的路径（Markdown 链接）: $rel"
    MISSING_REF=1
  fi
done
[ "$MISSING_REF" -eq 0 ] && pass "全部资产引用均存在"

# ---------------------------------------------------------------------------
hdr 3 "版权边界：**两侧规则相反** —— C# 侧不得内置快照，C++ 侧允许（正文 §7.4 / cpp §7.4）"
# C#/.NET 侧的权威是书与 Learn 页面 → 不可整篇内置。
if [ -d "$SKILL_DIR/references/official" ]; then
  OFFICIAL_COUNT=$(find "$SKILL_DIR/references/official" -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
  if [ "$OFFICIAL_COUNT" -gt 0 ]; then
    fail "出现了 $OFFICIAL_COUNT 个官方来源快照 —— C#/.NET 侧权威是书与 Learn 页面，不可整篇内置（csharp 正文 §7.4）"
  else
    pass "references/official 目录为空壳，无快照"
  fi
else
  pass "未内置 C# 侧官方来源快照（符合 csharp 正文 §7.4）"
fi
# C++ 侧：C++ Core Guidelines 是 MIT-style 许可，允许内置快照并做逐字比对。
# 但**企业风格指南不随其授权**（各自许可独立），故只允许 cpp-core-guidelines 这一份。
if [ -d "$SKILL_DIR/references/cpp-core-guidelines" ]; then
  pass "存在 C++ Core Guidelines 快照目录（MIT-style 许可允许，见 cpp 正文 §7.4）"
  STRAY=$(find "$SKILL_DIR/references/cpp-core-guidelines" -type f -name '*.md' \
          | grep -viE 'cppcoreguidelines|core-?guidelines' | head -5)
  if [ -n "$STRAY" ]; then
    fail "快照目录内出现了疑似第三方风格指南（其许可不随 Core Guidelines 授权）:"
    printf '%s\n' "$STRAY" | sed 's/^/        /'
  fi
else
  pass "未内置 C++ 侧快照（可选：允许但不强制）"
fi

# ---------------------------------------------------------------------------
hdr 4 "缩进与行尾：模板与正文取值一致（正文 §4.3）"
TPL_INDENT=$(ec_value "$EC" 'indent_size')
TPL_STYLE=$(ec_value "$EC" 'indent_style')
DOC_INDENT=$(grep -oE 'indent_size = [0-9]+' "$MAIN" | head -1 | sed 's/.*= *//')
DOC_STYLE=$(grep -oE 'indent_style = [a-z]+' "$MAIN" | head -1 | sed 's/.*= *//')
if [ -n "$DOC_INDENT" ] && [ "$TPL_INDENT" = "$DOC_INDENT" ]; then
  pass "indent_size 一致（${TPL_INDENT}）"
elif [ -z "$DOC_INDENT" ]; then
  warn "正文里推导不出 indent_size，无法比对"
else
  fail "indent_size 不一致：模板=$TPL_INDENT 正文=$DOC_INDENT"
fi
if [ -n "$DOC_STYLE" ] && [ "$TPL_STYLE" = "$DOC_STYLE" ]; then
  pass "indent_style 一致（${TPL_STYLE}）"
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
  pass "csharp_indent_switch_labels 一致（${TPL_CASE}）"
else
  fail "csharp_indent_switch_labels 不一致：模板=${TPL_CASE:-<空>} 正文=${DOC_CASE:-<推导不出>}"
fi

# ---------------------------------------------------------------------------
hdr 6 "行长：正文若已定值则必须与模板一致，未定值记 WARN（正文 §4.4 待实测）"
TPL_LINE=$(ec_value "$EC" 'max_line_length')
DOC_LINE=$(grep -oE 'max_line_length = [0-9]+|行长上限为 [0-9]+|行长 [0-9]+ 列' "$MAIN" | head -1 | grep -oE '[0-9]+')
if [ -n "$DOC_LINE" ]; then
  if [ "$TPL_LINE" = "$DOC_LINE" ]; then
    pass "行长一致（${TPL_LINE}）"
  else
    fail "行长不一致：模板=$TPL_LINE 正文=$DOC_LINE"
  fi
  else
    warn "正文未给出行长数值，模板单方面取 $TPL_LINE —— 两条出路选一：把它写进正文（阈值就成为双方一致的事实），或明确声明「该值由模板单方面定义、正文不重复」。现状下不得把它写成 MUST"
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
    pass "私有实例 / 静态字段前缀与正文一致（$PREFIX_INSTANCE / ${PREFIX_STATIC}）"
  else
    fail "模板缺少正文声明的私有字段前缀（应为 $PREFIX_INSTANCE / ${PREFIX_STATIC}，实为: ${TPL_PREFIXES}）"
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
hdr 9 "枚举类事实：SKILL.md 声明的类数 / 条数必须等于两侧目录的实际行数（含「总数==三档之和」）"

# 从 SKILL.md 里定位某个文件名那一行，解析出「N 类（a / b / c）」的四个数字
# 参数只有一个（文件名片段），故读 $1 —— 早期版本误写成 $2，会静默匹配空式。
# 顺序要紧：**先**按「N 类（a / b / c）」筛行，**再**取第一条。
# 反过来的话会先命中正文里更早出现的「缺陷目录（编号 …）：`references/xxx-catalog.md`」
# 那一行（它含文件名但不含类数），head -1 拿到它，后面就什么都筛不出来。
# 输出**必须并成一行**：调用方用 `read -r TOTAL A B C` 接，而 bash 的 read 只吃一行，
# 四行输出会让后三个变量全是空（2026-09-28 踩过，表现为「类数推导不出来」但总数是对的）。
parse_catalog_decl() {
  grep -E "$1" "$SKILL_MD" \
    | grep -oE '[0-9]+ 类（[0-9]+ / [0-9]+ / [0-9]+）' \
    | head -1 \
    | grep -oE '[0-9]+' \
    | tr '\n' ' '
}

# 数某侧目录的三档行数（pattern 为该侧的行首编号形式）
# 用显式 if/else，**不用嵌套三元** —— 嵌套三元少一个右括号就是语法错，而且
# awk 会先处理 -v 赋值、再解析程序，所以「-v 的 pattern 也有问题」时程序里的
# 括号错会被抢先掩盖，报出来的错指向别处（2026-09-28 踩过：一个漏掉的 `)` 被
# `-v pat='^\| ...\|'` 的报错挡了两轮）。
count_tiers() {
  awk -v pat="$2" '
    /^## / {
      if      ($0 ~ /一档/) sec = 1
      else if ($0 ~ /二档/) sec = 2
      else if ($0 ~ /三档/) sec = 3
      else                  sec = 0
      next
    }
    sec && $0 ~ pat {
      if      (sec == 1) a++
      else if (sec == 2) b++
      else if (sec == 3) c++
    }
    END { print a+0, b+0, c+0 }
  ' "$1"
}

# ---------- C#/.NET 侧 ----------
read -r C1 C2 C3 <<EOF
$(count_tiers "$CATALOG" '^[|] [0-9]+ [|]')
EOF
read -r CD_TOTAL CD1 CD2 CD3 <<EOF
$(parse_catalog_decl csharp-defect-catalog)
EOF
CS_SUM=$((C1 + C2 + C3))
if [ -z "$CD_TOTAL" ]; then
  warn "SKILL.md 里推导不出 C# 缺陷目录的类数声明，无法比对"
else
  [ "$CD1" = "$C1" ] && pass "C# 一档类数一致（${C1}）" || fail "C# 一档不一致：SKILL.md=$CD1 目录实际=$C1"
  [ "$CD2" = "$C2" ] && pass "C# 二档类数一致（${C2}）" || fail "C# 二档不一致：SKILL.md=$CD2 目录实际=$C2"
  [ "$CD3" = "$C3" ] && pass "C# 三档类数一致（${C3}）" || fail "C# 三档不一致：SKILL.md=$CD3 目录实际=$C3"
  if [ "$CD_TOTAL" = "$CS_SUM" ]; then
    pass "C# 总数 == 三档之和（${CS_SUM}）"
  else
    fail "C# 总数不一致：SKILL.md 声明 ${CD_TOTAL}，三档之和为 $CS_SUM —— 改了三档忘了改总数"
  fi
fi

# ---------- C++ 侧 ----------
read -r P1 P2 P3 <<EOF
$(count_tiers "$CPP_CATALOG" '^[|] CPP-[0-9]+ [|]')
EOF
read -r PD_TOTAL PD1 PD2 PD3 <<EOF
$(parse_catalog_decl cpp-defect-catalog)
EOF
# 编号连续性：CPP-01..CPP-N 不得断号（断号 = 复制条目时漏改编号或删条目留坑）
CPP_MAX=$(grep -oE '^[|] CPP-[0-9]+ [|]' "$CPP_CATALOG" | grep -oE '[0-9]+' | sort -n | tail -1)
CPP_CNT=$(grep -oE '^[|] CPP-[0-9]+ [|]' "$CPP_CATALOG" | grep -oE '[0-9]+' | sort -n | uniq | wc -l | tr -d ' ')
CPP_SUM=$((P1 + P2 + P3))
if [ -z "$PD_TOTAL" ]; then
  warn "SKILL.md 里推导不出 C++ 缺陷目录的类数声明，无法比对"
else
  [ "$PD1" = "$P1" ] && pass "C++ 一档类数一致（${P1}）" || fail "C++ 一档不一致：SKILL.md=$PD1 目录实际=$P1"
  [ "$PD2" = "$P2" ] && pass "C++ 二档类数一致（${P2}）" || fail "C++ 二档不一致：SKILL.md=$PD2 目录实际=$P2"
  [ "$PD3" = "$P3" ] && pass "C++ 三档类数一致（${P3}）" || fail "C++ 三档不一致：SKILL.md=$PD3 目录实际=$P3"
  if [ "$PD_TOTAL" = "$CPP_SUM" ]; then
    pass "C++ 总数 == 三档之和（${CPP_SUM}）"
  else
    fail "C++ 总数不一致：SKILL.md 声明 ${PD_TOTAL}，三档之和为 $CPP_SUM"
  fi
fi
if [ -n "$CPP_MAX" ] && [ "$CPP_CNT" = "$CPP_MAX" ]; then
  pass "C++ 编号连续（CPP-01…CPP-$(printf '%02d' "$CPP_MAX")，无断号）"
else
  fail "C++ 编号不连续：最大编号 ${CPP_MAX}，实际条目数 $CPP_CNT —— 有断号或重复"
fi

# ---------- 待实测条数（两侧各一份）----------
D_ROWS=$(count_rows_in_section "$MAIN" '附录 D' '^[|] [0-9]+ [|]')
D_DECL=$(grep -oE '附录 D\*\*（[0-9]+ 条）|附录 D（[0-9]+ 条）' "$SKILL_MD" | grep -oE '[0-9]+' | head -1)
if [ -z "$D_DECL" ]; then
  warn "SKILL.md 里推导不出 C# 待实测条数，无法比对"
elif [ "$D_DECL" = "$D_ROWS" ]; then
  pass "C# 待实测条数一致（${D_ROWS}）"
else
  fail "C# 待实测条数不一致：SKILL.md=$D_DECL 正文附录 D 实际=$D_ROWS 行"
fi

PD_ROWS=$(count_rows_in_section "$CPP_MAIN" '附录 D' '^[|] D[0-9]+ [|]')
if [ "$PD_ROWS" -gt 0 ]; then
  pass "C++ 待实测条目已编号登记（$PD_ROWS 条，D 前缀）"
else
  fail "C++ 正文附录 D 里推不出待实测条目 —— 「已实测 / 待实测」的边界必须显式登记"
fi

# ---------------------------------------------------------------------------
hdr 10 "版本号：**两侧各自独立**，各侧内部必须一致（含 README —— 历史上它是漏网的第 5 处）"

# ---------- C#/.NET 侧：正文头部 / 变更记录末行 / 缺陷目录头部 / SKILL.md / README ----------
V_HEAD=$(grep -oE '^> 版本：v[0-9]+(\.[0-9]+)*' "$MAIN" | head -1 | grep -oE 'v[0-9].*')
V_LAST=$(grep -oE '^[|] v[0-9]+(\.[0-9]+)* [|]' "$MAIN" | tail -1 | grep -oE 'v[0-9].*[0-9]')
V_CAT=$(grep -oE '^> 版本：v[0-9]+(\.[0-9]+)*' "$CATALOG" | head -1 | grep -oE 'v[0-9].*')
V_SKILL_CS=$(grep -oE 'C#/\.NET 侧：v[0-9]+(\.[0-9]+)*' "$SKILL_MD" | head -1 | grep -oE 'v[0-9].*')
V_README_CS=$(grep -oE 'C#/\.NET 侧：v[0-9]+(\.[0-9]+)*' "$README" | head -1 | grep -oE 'v[0-9].*')
if [ -z "$V_HEAD" ] || [ -z "$V_LAST" ] || [ -z "$V_CAT" ] || [ -z "$V_SKILL_CS" ]; then
  warn "C# 侧有版本号推导不出来：正文头部=${V_HEAD:-?} 变更记录=${V_LAST:-?} 目录=${V_CAT:-?} SKILL.md=${V_SKILL_CS:-?}"
else
  BAD=""
  for v in "$V_LAST" "$V_CAT" "$V_SKILL_CS" "$V_README_CS"; do
    [ -n "$v" ] && [ "$v" != "$V_HEAD" ] && BAD="${BAD}${BAD:+ }$v"
  done
  if [ -z "$BAD" ]; then
    pass "C#/.NET 侧版本号全一致（${V_HEAD}，含 README）"
  else
    fail "C#/.NET 侧版本号不一致：正文头部=$V_HEAD 其余=$BAD"
  fi
fi

# ---------- C++ 侧：正文头部 / 变更记录末行 / 缺陷目录头部 / SKILL.md / README ----------
VC_HEAD=$(grep -oE '^> 版本：v[0-9]+(\.[0-9]+)*' "$CPP_MAIN" | head -1 | grep -oE 'v[0-9].*')
VC_LAST=$(grep -oE '^[|] v[0-9]+(\.[0-9]+)* [|]' "$CPP_MAIN" | tail -1 | grep -oE 'v[0-9].*[0-9]')
VC_CAT=$(grep -oE '^> 版本：v[0-9]+(\.[0-9]+)*' "$CPP_CATALOG" | head -1 | grep -oE 'v[0-9].*')
VC_SKILL=$(grep -oE 'C\+\+ 侧：v[0-9]+(\.[0-9]+)*' "$SKILL_MD" | head -1 | grep -oE 'v[0-9].*')
VC_README=$(grep -oE 'C\+\+ 侧：v[0-9]+(\.[0-9]+)*' "$README" | head -1 | grep -oE 'v[0-9].*')
if [ -z "$VC_HEAD" ] || [ -z "$VC_LAST" ] || [ -z "$VC_CAT" ] || [ -z "$VC_SKILL" ]; then
  warn "C++ 侧有版本号推导不出来：正文头部=${VC_HEAD:-?} 变更记录=${VC_LAST:-?} 目录=${VC_CAT:-?} SKILL.md=${VC_SKILL:-?}"
else
  BADC=""
  for v in "$VC_LAST" "$VC_CAT" "$VC_SKILL" "$VC_README"; do
    [ -n "$v" ] && [ "$v" != "$VC_HEAD" ] && BADC="${BADC}${BADC:+ }$v"
  done
  if [ -z "$BADC" ]; then
    pass "C++ 侧版本号全一致（${VC_HEAD}，含 README）"
  else
    fail "C++ 侧版本号不一致：正文头部=$VC_HEAD 其余=$BADC"
  fi
fi

# 两侧版本号**不得相同**是目前的事实，但不是规则 —— 同号与否只提示，不判错。
if [ -n "$V_HEAD" ] && [ "$V_HEAD" = "$VC_HEAD" ]; then
  warn "两侧版本号都是 $V_HEAD —— 两侧属独立演进，同号会让「哪侧改过」不可判；建议错开"
fi

# ---------------------------------------------------------------------------
hdr 11 "已声明的待决项（--strict 下降为 FAIL）"
PENDING=0

# C# 侧 stylecop.json 的占位符必须被填掉才能启用 SA1633
if grep -q 'TODO 填写' "$STYLECOP"; then
  warn "stylecop.json 的 companyName / copyrightText 仍是占位符（仅在引入 StyleCop 前需填）"
  PENDING=$((PENDING + 1))
fi

# C# 侧模板里保留的 [待实测] 说明必须与正文附录 D 对得上
EC_PENDING=$(grep -c '\[待实测\]' "$EC" || true)
if [ "$EC_PENDING" -gt 0 ]; then
  warn "assets/editorconfig 内有 $EC_PENDING 处 [待实测] 标记 —— 销项后须同步清理，勿让标记与结论长期并存"
  PENDING=$((PENDING + 1))
fi

# C++ 侧：两个模板的行为均未在本机验证（无 clang-format / clang-tidy）
CF_PENDING=$(grep -c '\[待实测\]' "$CLANG_FORMAT" || true)
CT_PENDING=$(grep -c '\[待实测\]' "$CLANG_TIDY" || true)
CPP_PENDING=$((CF_PENDING + CT_PENDING))
if [ "$CPP_PENDING" -gt 0 ]; then
  warn "assets/clang-format + assets/clang-tidy 内有 $CPP_PENDING 处 [待实测] 标记 —— 装上工具后须逐条销项（C++ 正文附录 D 有验证命令）"
  PENDING=$((PENDING + 1))
fi

# C++ 正文的待实测条目数必须与它自称的一致（防"标了却没登记"）
CPP_D_TAGGED=$(grep -c '\[待实测\]' "$CPP_MAIN" || true)
if [ "$CPP_D_TAGGED" -gt 0 ]; then
  pass "C++ 正文有 $CPP_D_TAGGED 处 [待实测] 标注（已登记，见其附录 D）"
fi

if [ "$PENDING" -eq 0 ]; then
  pass "无未决项"
fi

# ---------------------------------------------------------------------------
hdr 12 "语言探测器的自检（校验函数本身也要被校验）"
DETECT="$SKILL_DIR/scripts/detect_language.sh"
if [ ! -f "$DETECT" ]; then
  fail "缺少 scripts/detect_language.sh —— SKILL.md 的「语言判定」一节会变成空指令"
else
  DETECT_LOG=$(mktemp "${TMPDIR:-/tmp}/wcs-detect-selftest-XXXXXX")
  if bash "$DETECT" --self-test > "$DETECT_LOG" 2>&1; then
    pass "detect_language.sh 自检全通过"
  else
    fail "detect_language.sh 自检失败 —— 语言判定不可信，改前先修它"
    sed 's/^/      /' "$DETECT_LOG"
  fi
  rm -f "$DETECT_LOG"
fi

# ---------------------------------------------------------------------------
hdr 13 "两侧隔离：配置模板与缺陷编号不得混入对方语言（污染检测）"

# A. C#/.NET 侧模板（.editorconfig / MSBuild props / stylecop）不得含 clang 的键名。
#    这几组键名是 clang-format / clang-tidy 独有的，出现在 .editorconfig 里一定是误抄。
#    只看**键名行**，不看整行注释 —— 注释里写「本项与 .clang-format 的 X 不同」是合法的
#    交叉说明，不是污染。这里刻意只丢「整行注释」（行首非空白首个字符是 # ; / //），
#    不做行内截断 —— 行内截断会误伤含 `;` 的 MSBuild 值与含 `//` 的 URL。
strip_comment() {
  grep -nv -E '^[[:space:]]*(#|;|//|<!--)' "$@" 2>/dev/null \
    | grep -E '[^[:space:]]' || true
}
CS_LEAK=$(strip_comment "$EC" "$PROPS" "$STYLECOP" \
          | grep -E '(BasedOnStyle|IndentCaseLabels|PointerAlignment|DerivePointerAlignment|BreakBeforeBraces|SeparateDefinitionBlocks|AllowShortFunctionsOnASingleLine)' || true)
if [ -z "$CS_LEAK" ]; then
  pass "C# 侧配置模板无 clang 键名污染"
else
  fail "C# 侧模板里出现了 C++ 侧（clang）的键名 —— 两侧配置载体互不通用："
  printf '%s\n' "$CS_LEAK" | sed 's/^/        /'
fi

# B. C++ 侧模板（.clang-format / .clang-tidy）不得含 .NET 的键名前缀。
#    同 A，先剥注释：assets/clang-format 里有一处刻意写明的「与 C# 侧 XXX 是两个开关」，
#    那是隔离声明本身，不是污染 —— 早期版本没剥注释，把它误报成 FAIL 了。
CPP_LEAK=$(strip_comment "$CLANG_FORMAT" "$CLANG_TIDY" 2>/dev/null \
           | grep -E '(dotnet_|csharp_|dotnet_diagnostic)' || true)
if [ -z "$CPP_LEAK" ]; then
  pass "C++ 侧配置模板无 .NET 键名污染"
else
  fail "C++ 侧模板里出现了 C#/.NET 侧的键名前缀 —— 两侧配置载体互不通用："
  printf '%s\n' "$CPP_LEAK" | sed 's/^/        /'
fi

# C. 跨语言项必须一致：缩进宽度与行尾（这是**唯一允许两侧共享**的一类取值）
EC_INDENT=$(ec_value "$EC" 'indent_size')
CF_INDENT=$(cl_value "$CLANG_FORMAT" 'IndentWidth')
if [ -n "$EC_INDENT" ] && [ "$EC_INDENT" = "$CF_INDENT" ]; then
  pass "跨语言项「缩进宽度」两侧一致（${EC_INDENT}）"
else
  fail "跨语言项「缩进宽度」不一致：.editorconfig=$EC_INDENT vs .clang-format=$CF_INDENT —— 这是唯一必须一致的取值"
fi
EC_EOL=$(ec_value "$EC" 'end_of_line')
# ⚠️ clang-format 的键名是 `LineEnding`，**不是** `EndOfLine`。
#    `end_of_line` 是 `.editorconfig` 的键；clang-format 里写 `EndOfLine` 会让它
#    报 `error: unknown key` 并**拒绝读取整个 .clang-format**（模板里一条都不生效）。
#    本行原先就写的 `EndOfLine` —— 于是这条"跨语言一致性"检查是在拿模板里的错键
#    与它自己比对，恒真通过。这是典型的**自我印证式假绿**，已实测（clang-format 21.1.6）。
CF_EOL=$(cl_value "$CLANG_FORMAT" 'LineEnding')
EC_EOL_LC=$(printf '%s' "$EC_EOL" | tr '[:upper:]' '[:lower:]')
CF_EOL_LC=$(printf '%s' "$CF_EOL" | tr '[:upper:]' '[:lower:]')
if [ -n "$EC_EOL_LC" ] && [ "$EC_EOL_LC" = "$CF_EOL_LC" ]; then
  pass "跨语言项「行尾」两侧一致（${EC_EOL_LC}）"
else
  fail "跨语言项「行尾」不一致：.editorconfig=$EC_EOL vs .clang-format=$CF_EOL"
fi

# D. 缺陷编号不得跨侧使用（只看分档表的编号形式，不匹配正文里作为"不要套用"举例的提及）
CS_HAS_CPP=$(grep -cE '^[|] CPP-[0-9]+ [|]' "$CATALOG" || true)
CPP_HAS_CS=$(grep -cE '^[|] [0-9]+ [|]' "$CPP_CATALOG" || true)
if [ "$CS_HAS_CPP" -eq 0 ] && [ "$CPP_HAS_CS" -eq 0 ]; then
  pass "两侧缺陷编号未混用（C# 用 #nn，C++ 用 CPP-nn）"
else
  [ "$CS_HAS_CPP" -gt 0 ] && fail "C# 缺陷目录里出现了 $CS_HAS_CPP 行 CPP- 编号 —— 编号体系不能跨侧"
  [ "$CPP_HAS_CS" -gt 0 ] && fail "C++ 缺陷目录里出现了 $CPP_HAS_CS 行纯数字编号 —— 编号体系不能跨侧"
fi

# E. C++ 正文的动作命令里不得出现 dotnet（判据：给 C++ 提 .NET 的命令 = 跑错了一侧）
CPP_DOTNET=$(grep -nE '^[[:space:]]*\\\$?[[:space:]]*dotnet ' "$CPP_MAIN" "$CPP_CATALOG" 2>/dev/null || true)
if [ -z "$CPP_DOTNET" ]; then
  pass "C++ 侧文档的动作命令里无 dotnet 调用"
else
  fail "C++ 侧文档里出现了以 dotnet 开头的命令 —— 那是 C#/.NET 侧的工具："
  printf '%s\n' "$CPP_DOTNET" | sed 's/^/        /'
fi

# ---------------------------------------------------------------------------
hdr 14 '变量展开卫生：`.sh` 里 `$VAR` 后不得紧跟多字节字符（回归自检）'
# 为什么单开一节：bash 在 UTF-8 的 LC_CTYPE 下会把多字节字符的首字节吃进变量名 ——
# `$VAR（` 于是变成引用一个不存在的变量，配 `set -u` 直接终止；而**崩溃信息本身是乱码**
# （把两个字节打出来），极难归因。**判别变量是 LC_CTYPE，不是 LC_ALL**：本机默认
# LANG=C 而 LC_CTYPE=en_US.UTF-8，所以「裸跑」就会中招；LC_ALL=C 下反倒一切正常，
# 这正是当年「本机已跑通」记录失真的原因。
# 修法：写成 `${VAR}`。
#
# 判定式的三点讲究：
#   1. 必须 `LC_ALL=C` —— 否则 grep 按字符解释，`[^ -~]` 匹配不到多字节字符。
#   2. 用 `[^ -~[:cntrl:]]`（高字节）而不是 `[^ -~]`：后者把**制表符**也算进来，
#      而 `$VAR<TAB>中文` 是安全的（tab 正常终止变量名），会误报。
#   3. 排除整行注释（行首非空白第一个字符是 `#`）—— 注释不参与展开，
#      本节自己的说明文字就在注释里，不排除的话它会报自己。
#      做法是两次 grep 串联：第一次带 -n 出「行号:内容」，第二次按 `行号:#` 剔除，
#      这样行号不会因为重新编号而错位。
SH_FILES=0
SH_BAD=0
SH_REPORT=""
while IFS= read -r f; do
  SH_FILES=$((SH_FILES + 1))
  h=$(LC_ALL=C grep -nE '\$[A-Za-z_][A-Za-z0-9_]*[^ -~[:cntrl:]]' "$f" 2>/dev/null \
      | grep -vE '^[0-9]+:[[:space:]]*#' || true)
  if [ -n "$h" ]; then
    SH_BAD=$((SH_BAD + 1))
    SH_REPORT="${SH_REPORT}        ${f#"$SKILL_DIR"/}
$(printf '%s\n' "$h" | sed 's/^/          /')
"
  fi
done < <(find "$SKILL_DIR" -name '*.sh' -not -path '*/.git/*' | sort)
if [ "$SH_BAD" -eq 0 ]; then
  pass "全仓 .sh 无「\$VAR + 多字节字符」隐患（扫描 $SH_FILES 个文件）"
else
  fail "$SH_BAD 个 .sh 存在「\$VAR + 多字节字符」—— UTF-8 的 LC_CTYPE 下会因 set -u 直接终止，且报错是乱码（须写成 \${VAR}）"
  printf '%s' "$SH_REPORT"
fi

# ---------------------------------------------------------------------------
hdr 15 "跨语言判据层的引用完整性（共享文件必须被两侧都用上 —— 一侧悄悄弃用 = 隔离漏洞）"
# 为什么单开一节：`design-granularity.md` 与 `change-discipline.md` 是**两侧共用的判据层**，
# 但"共用"这件事本身没有任何机制保证 —— 完全可能出现"某侧正文改了一轮，把指向共享判据的
# 引用顺手删了"，而两侧看起来都自洽。这类退化的后果是**同一份判据只剩一侧在用**，
# 比配置污染更难发现（配置污染是显式的，引用丢失是静默的）。
#
# 三条断言：
#   (a) 每个共享判据文件都必须在 SKILL.md 里被列出 —— 否则等于藏起来了；
#   (b) 每个共享判据文件都必须同时被 C# 侧与 C++ 侧正文引用 —— 这就是"共享"的定义；
#   (c) 共享判据文件必须自带版本行（`> 版本：vX.Y.Z`）—— 它们不参与 §10 的两侧版本核对
#       （那是分侧版本），所以只能要求"有版本、改过留痕"，不能要求"与某侧一致"。
for sf in $SHARED_JUDGMENT; do
  sname=$(basename "$sf")
  # (a) 被 SKILL.md 列出
  if grep -qF "$sname" "$SKILL_MD"; then
    pass "共享判据 ${sname} 已被 SKILL.md 列出"
  else
    fail "共享判据 ${sname} 未出现在 SKILL.md 里 —— 共享文件不列进入口等于没建"
  fi
  # (b) 两侧正文都引用
  cs_hit=$(grep -cF "$sname" "$MAIN" || true)
  cpp_hit=$(grep -cF "$sname" "$CPP_MAIN" || true)
  if [ "$cs_hit" -gt 0 ] && [ "$cpp_hit" -gt 0 ]; then
    pass "共享判据 ${sname} 被两侧正文共同引用（C#/.NET ${cs_hit} 处 / C++ ${cpp_hit} 处）"
  else
    fail "共享判据 ${sname} 只被一侧引用（C#/.NET ${cs_hit} 处 / C++ ${cpp_hit} 处）—— 「共享」要求两侧都用上，否则等于该侧已弃用"
  fi
  # (c) 自带版本行
  if grep -qE '^> 版本：v[0-9]+(\.[0-9]+)*' "$sf"; then
    pass "共享判据 ${sname} 自带版本声明（$(grep -oE '^> 版本：v[0-9]+(\.[0-9]+)*' "$sf" | head -1 | grep -oE 'v[0-9].*')）"
  else
    fail "共享判据 ${sname} 缺版本声明 —— 它不参与 §10 的分侧版本核对，只能靠自带版本留痕"
  fi
done

# ---------------------------------------------------------------------------
hdr 16 '正则竖线卫生：`[|]` 不得被当作「交替」用（回归自检）'
# 为什么单开一节：`[|]` 在 ERE 里是**字符类**，只匹配一个字面竖线字符 ——
# 它**不是**交替运算符。本仓已经踩过两次（assets/clang-format 的复验命令、
# references/cpp-coding-standards.md 附录 D 的 D11），两处都把交替写成了 grep -E 'A[|]B'（反例），
# 结果要求输入里出现字面 "A|B"，**永远零命中且 exit 1**（已实测）。
# 危害不在"报不出"，而在它**以「核对过了、输出为空」的外观返回** —— 与假绿同源，
# 也正是上面第 9 节那条「0 命中不等于没问题」的同类失效。
# 判定式：`[|]` 的左右紧邻 ASCII 字母/数字/下划线 = 一定是把 `[|]` 当交替用了。
#   三种不误报的情形（均已预演验证）：
#     · 表格行首匹配 `^[|] CPP-[0-9]+ [|]` —— 左边是 `^` 或空格；
#     · 说明文字里的 `[|]`（前后是反引号或空格）—— 前后非字母数字；
#     · 本行自身的模式串 —— 里面的 `[|]` 前后是 `\`。
#
# **显式豁免标记**：要故意展示这个坏写法时，该行必须带「反例」二字。为什么必须有它 ——
#   第一版按上面的判定式扫，4 处命中**全部是误报**，且误报对象正是"讲解这个坑"的
#   说明文字（本节自己的注释、正文的 D11 警告、assets 模板的警告）。100% 误报率的
#   检查比没有更坏：它会被人关掉。故仿 `# noqa` 的做法给一个显式出口 ——
#   坏写法只有两种合法存在方式：**是该行想拦的目标**，或**该行已自标「反例」**。
#
# 扫描范围：skill 的交付面（正文 / 脚本 / assets 模板 / README），用 grep -I 跳过二进制
#   （.DS_Store 之类），避免拿它们当文本读。
#   **刻意不扫 `.workbuddy/`**：它是本地工作区（已 gitignore、**不随 skill 交付、不被执行**）。
#   把它纳入只会造成"记录这个坑本身就是违规"的摩擦 —— 而保护收益为零（那些字不会被谁照抄去跑）。
#   实测确认这条边界是必要的：纳入 `.workbuddy/` 时，本节的记录笔记与计划书的说明文字都会命中。
# 修法：要交替就写 `A|B`；在 Markdown 表格单元里为避开竖线，用 `grep -e A -e B`。
REGEX_FILES=0
REGEX_BAD=0
REGEX_REPORT=""
while IFS= read -r f; do
  REGEX_FILES=$((REGEX_FILES + 1))
  h=$(grep -nIE '[A-Za-z0-9_]\[[|]\][A-Za-z0-9_]' "$f" 2>/dev/null \
      | grep -vF '反例' || true)
  if [ -n "$h" ]; then
    REGEX_BAD=$((REGEX_BAD + 1))
    REGEX_REPORT="${REGEX_REPORT}        ${f#"$SKILL_DIR"/}
$(printf '%s\n' "$h" | sed 's/^/          /')
"
  fi
done < <(find "$SKILL_DIR" -type f -not -path '*/.git/*' -not -path '*/.workbuddy/*' | sort)
if [ "$REGEX_BAD" -eq 0 ]; then
  pass "交付面无「把 [|] 当交替用」的写法（扫描 $REGEX_FILES 个文件，不含 .workbuddy/）"
else
  fail "$REGEX_BAD 个文件把 [|] 当交替用了 —— ERE 里它是字符类，该命令会永远零命中并 exit 1（假绿，须改成 A|B 或 grep -e A -e B）"
  printf '%s' "$REGEX_REPORT"
fi

# ---------------------------------------------------------------------------
hdr 17 "C++ 配置模板：静态陷阱 + （有工具时）真机验证"

# A. 静态陷阱一：`Checks` 不得写成折叠块标量（`>` 或 `|`）。
#    已实测（clang-tidy 21.1.6）：`Checks` 是**按逗号切分的字符串**，而在折叠块标量里
#    `#` **不是注释、是内容** —— 写在某条禁用项前面的注释会被粘进那条禁用项，
#    使**该条禁用静默失效**。本模板原先 14 条禁用里有 10 条因此形同虚设。
#    判定：`Checks:` 行尾出现 `>` 或 `|`。
if grep -qE '^Checks:[[:space:]]*[>|]' "$CLANG_TIDY" 2>/dev/null; then
  fail "assets/clang-tidy 的 Checks 写成了折叠块标量 —— 注释会粘进禁用项，导致该条禁用静默失效（须改成 YAML 列表）"
else
  pass "assets/clang-tidy 的 Checks 未用折叠块标量"
fi

# B. 静态陷阱二：`.clang-format` 里不得出现 `.editorconfig` 专有键。
#    `EndOfLine` / `indent_size` / `charset` 等是 `.editorconfig` 的键名。
#    后果比"不生效"更重：clang-format 报 `error: unknown key` 并**拒绝读取整个文件**
#    （exit 1，该文件里一条配置都不生效）。已实测（clang-format 21.1.6）。
ECONLY=$(grep -nE '^[[:space:]]*(EndOfLine|indent_size|indent_style|charset|trim_trailing_whitespace|insert_final_newline)[[:space:]]*:' "$CLANG_FORMAT" 2>/dev/null || true)
if [ -z "$ECONLY" ]; then
  pass "assets/clang-format 无 .editorconfig 专有键"
else
  fail "assets/clang-format 里出现了 .editorconfig 的键名 —— clang-format 会 unknown key 并**拒绝读整个文件**："
  printf '%s\n' "$ECONLY" | sed 's/^/        /'
fi

# C. 有工具时做真验证；没工具时**明确说没验证**，绝不记 PASS。
#    工具来源：PATH，或 $CLANG_FORMAT_BIN / $CLANG_TIDY_BIN 显式指定。
#    ⚠️ 环境变量名**不能**叫 `CLANG_FORMAT` / `CLANG_TIDY` —— 那两个名字在本脚本里
#       已经被用作**模板文件路径**，会撞车成"去执行模板文件"（Permission denied）。
CF_BIN="${CLANG_FORMAT_BIN:-$(command -v clang-format 2>/dev/null || true)}"
CT_BIN="${CLANG_TIDY_BIN:-$(command -v clang-tidy 2>/dev/null || true)}"
if [ -z "$CF_BIN" ] && [ -z "$CT_BIN" ]; then
  warn "本机无 clang-format / clang-tidy —— 两份 C++ 模板**未经工具验证**（这是「没验」，不是「通过」）。装上后本节自动做真验证"
else
  TMPT=$(mktemp -d)
  printf 'int main()\n{\n    return 0;\n}\n' > "$TMPT/probe.cpp"

  # C1. clang-format：模板必须能被干净读取（stderr 必须为空）
  if [ -n "$CF_BIN" ]; then
    cp "$CLANG_FORMAT" "$TMPT/.clang-format"
    ( cd "$TMPT" && "$CF_BIN" -style=file -dump-config > "$TMPT/cf.yaml" 2> "$TMPT/cf.err" ) || true
    CFV=$("$CF_BIN" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    if [ -s "$TMPT/cf.err" ]; then
      fail "clang-format $CFV 拒绝或警告 assets/clang-format："
      sed 's/^/        /' "$TMPT/cf.err" | head -12
    else
      pass "assets/clang-format 被 clang-format $CFV 干净接受（无 unknown key / 非法值）"
    fi
  fi

  # C2. clang-tidy：模板必须能被读取，且**声明的键名与禁用项真的生效**。
  #     必须在**干净临时目录**里回读 —— 否则当前目录若恰好有 .clang-tidy 会混进来。
  if [ -n "$CT_BIN" ]; then
    cp "$CLANG_TIDY" "$TMPT/.clang-tidy"
    ( cd "$TMPT" && "$CT_BIN" --config-file="$TMPT/.clang-tidy" --dump-config probe.cpp -- -std=c++20 > "$TMPT/ct.yaml" 2> "$TMPT/ct.err" ) || true
    CTV=$("$CT_BIN" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    if [ -s "$TMPT/ct.err" ]; then
      fail "clang-tidy $CTV 对 assets/clang-tidy 报出错误/警告："
      sed 's/^/        /' "$TMPT/ct.err" | head -12
    else
      # C2a. CheckOptions 键名必须都在官方合法键表里（拼错的会被**静默忽略**）
      # 只从**真正的键声明**（`- {key: ...}`）提取，**不扫注释行** ——
      # 本模板的注释里会写"曾误以为存在 X，其实没有这个键"，扫注释会把这种
      # 说明文字本身报成违规。这个坑在本脚本第 16 节已经踩过一次。
      sed -n '/^CheckOptions:/,/^[A-Za-z]/p' "$TMPT/ct.yaml" \
        | grep -oE '^  [A-Za-z][A-Za-z0-9_.-]*:' | tr -d ' :' | sort -u > "$TMPT/knownkeys.txt"
      grep -E '^[[:space:]]*-[[:space:]]*\{[[:space:]]*key:' "$CLANG_TIDY" \
        | grep -oE '\{[[:space:]]*key:[[:space:]]*[A-Za-z0-9_.-]+' \
        | sed 's/.*key:[[:space:]]*//' | sort -u > "$TMPT/tplkeys.txt"
      UNK=$(comm -23 "$TMPT/tplkeys.txt" "$TMPT/knownkeys.txt" || true)
      if [ -z "$UNK" ]; then
        pass "assets/clang-tidy 的 CheckOptions 键名全部被 clang-tidy $CTV 认识（对照 $(wc -l < "$TMPT/knownkeys.txt" | tr -d ' ') 个合法键）"
      else
        fail "assets/clang-tidy 有键名不被 clang-tidy $CTV 认识 —— 会被**静默忽略**，配置看着像在生效其实没有："
        printf '%s\n' "$UNK" | sed 's/^/        /'
      fi
      # C2b. 声明的禁用项必须真的没被启用
      "$CT_BIN" --config-file="$TMPT/.clang-tidy" --list-checks probe.cpp -- -std=c++20 2>/dev/null \
        | sed 's/^ *//' | grep -vE '^Enabled checks:|^$' | sort -u > "$TMPT/enabled.txt"
      grep -oE '^[[:space:]]*- -[a-z][a-z0-9-]*' "$CLANG_TIDY" | sed 's/^[[:space:]]*- //' | sort -u > "$TMPT/disables.txt"
      STILL=""
      while IFS= read -r c; do
        [ -z "$c" ] && continue
        grep -qxF -- "$c" "$TMPT/enabled.txt" && STILL="${STILL}        ${c}
"
      done < "$TMPT/disables.txt"
      if [ -z "$STILL" ]; then
        pass "assets/clang-tidy 声明的 $(wc -l < "$TMPT/disables.txt" | tr -d ' ') 条禁用项逐条确认未启用"
      else
        fail "assets/clang-tidy 有禁用项**声明的与实际不符**（仍处于启用状态）："
        printf '%s' "$STILL"
      fi
    fi
  fi
  rm -rf "$TMPT"
fi

# ---------------------------------------------------------------------------
hdr 18 "自检脚本自身的契约（退出码 / 参数 / 自述节数必须与实际一致）"
if [ "$SELFTEST_NESTED" = "1" ]; then
  # 由外层第 18 节以「坏参数」探针方式调起 —— 跳过，否则参数校验一坏就无限递归。
  pass "（探针模式：跳过本节的递归调用）"
else
# 起因（2026-09-28）：头部声明了「2 用法错误」，而脚本里**从来没有 exit 2**，
# 未知参数被静默忽略 —— 把 `--strict` 敲成 `--stict` 会退化成非严格模式并 exit 0（假绿）。
# 这是「声明与实际不符」的又一实例，且恰好落在**校验器自己**身上 ⇒ 机械化。
SELF="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"

# A. 头部声明的退出码，脚本体里必须都有对应 exit（反之亦然）
DECLARED=$(sed -n 's/^# 退出码:[^0-9]*//p' "$SELF" | grep -oE '[0-9]+' | sort -u)
# 只认「行首（含缩进）的 exit N」—— 注释里的散文与字符串里的 `exit 1` 不会命中（已实测）
ACTUAL=$(grep -oE '^[[:space:]]*exit[[:space:]]+[0-9]+' "$SELF" | grep -oE '[0-9]+' | sort -u)

if [ -z "$DECLARED" ]; then
  fail "头部找不到「# 退出码:」声明行 —— 契约无从核对"
else
  MISSING=""
  for c in $DECLARED; do
    printf '%s\n' "$ACTUAL" | grep -qx -- "$c" || MISSING="${MISSING}${c} "
  done
  if [ -z "$MISSING" ]; then
    pass "头部声明的退出码（$(printf '%s' "$DECLARED" | tr '\n' ' ' | sed 's/ $//')）在脚本里都有对应 exit"
  else
    fail "头部声明了退出码但脚本里不可能出现：${MISSING}—— 声明与实际不符（本次修的就是这一类）"
  fi

  UNDOC=""
  for c in $ACTUAL; do
    printf '%s\n' "$DECLARED" | grep -qx -- "$c" || UNDOC="${UNDOC}${c} "
  done
  if [ -n "$UNDOC" ]; then
    fail "脚本体里有未在头部声明的退出码：${UNDOC}—— 调用方无法预知（要么补进声明，要么删掉该 exit）"
  fi
fi

# B. 真功能验证：未知参数必须被拒绝，不能静默退化成非严格模式
#    ⚠️ 必须带 WCS_SELFTEST_NESTED=1 递归护栏：万一参数校验坏了，子进程会跑到本节又调自己。
#    加超时兜底，避免护栏本身失效时把调用方挂死。
if command -v timeout >/dev/null 2>&1; then
  WCS_SELFTEST_NESTED=1 timeout 30 bash "$SELF" --__wcs_bogus_flag__ >/dev/null 2>&1
  BOGUS_RC=$?
else
  WCS_SELFTEST_NESTED=1 bash "$SELF" --__wcs_bogus_flag__ >/dev/null 2>&1
  BOGUS_RC=$?
fi
if [ "$BOGUS_RC" -eq 2 ]; then
  pass "未知参数被拒绝（exit 2）—— 拼错 --strict 不会假绿"
else
  fail "未知参数返回 ${BOGUS_RC}（应为 2）—— 拼错的 --strict 会静默退化成非严格模式并 exit 0"
fi

# C. SKILL.md 自述的节数 == 实际节数，且编号连续无重复
#    起因：2026-09-28 新增本节后，SKILL.md 仍写着「自检覆盖 17 节」——
#    **加了检查却没更新自述**，与「两侧版本号」「缺陷条数」同属手抄副本漂移。
SECTIONS=$(grep -oE '^hdr [0-9]+' "$SELF" | awk '{print $2}')
SEC_N=$(printf '%s\n' "$SECTIONS" | grep -c .)
SEC_CLAIM=$(grep -oE '自检覆盖 [0-9]+ 节' "$SKILL_MD" | grep -oE '[0-9]+' | head -1)
if [ -z "$SEC_CLAIM" ]; then
  fail "SKILL.md 里找不到「自检覆盖 N 节」的自述 —— 节数无从核对"
elif [ "$SEC_CLAIM" -ne "$SEC_N" ]; then
  fail "SKILL.md 自述「${SEC_CLAIM} 节」，实际 ${SEC_N} 节 —— 加了检查却没更新自述"
else
  pass "SKILL.md 自述节数与实际一致（${SEC_N} 节）"
fi

EXPECTED=$(seq 1 "$SEC_N" | tr '\n' ' ')
ACTUAL_SEQ=$(printf '%s\n' "$SECTIONS" | tr '\n' ' ')
if [ "$ACTUAL_SEQ" = "$EXPECTED" ]; then
  pass "各节编号连续且无重复（1..${SEC_N}）"
else
  fail "节编号不连续或有重复 —— 正文里「第 N 节」的交叉引用会指错"
fi
fi  # SELFTEST_NESTED

# ---------------------------------------------------------------------------
printf '\n=== 结果：FAIL %d / WARN %d ===\n' "$FAIL" "$WARN"
if [ "$FAIL" -gt 0 ]; then
  printf '结论：不一致（须修正后再集成）\n'
  exit 1
fi
if [ "$STRICT" -eq 1 ] && [ "$WARN" -gt 0 ]; then
  printf '结论：--strict 下 WARN 也记不通过（共 %d 条，见上方 WARN 行）\n' "$WARN"
  exit 1
fi
printf '结论：一致性通过\n'
exit 0
