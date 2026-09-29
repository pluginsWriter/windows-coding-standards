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
# 目的层：本仓库此前**从未把设计目的完整写下过**，而"没有目的就没有缺口"——
# 它不在 SHARED_JUDGMENT 里的话，第 15 节不会核对"两侧是否都还在用它"，
# 于是它可以被某一侧静默弃用而没人发现（与本文件存在的理由同源）。
DESIGN_PURPOSE="$SKILL_DIR/references/design-purpose.md"
# 接入与整改流程（2026-09-29 E12 落地为判据层）：进 SHARED_JUDGMENT 后，
# 第 15 节同样核对「SKILL.md 列出 + 两侧正文共同引用 + 自带版本行」——
# 不进去的话它可以被某一侧静默弃用而没人发现（与目的层同源的理由）。
PLAYBOOK="$SKILL_DIR/references/remediation-playbook.md"
SHARED_JUDGMENT="$DESIGN_PURPOSE $GRANULARITY $CHANGE_DISC $PLAYBOOK"

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

# ---------- 附录 D 的「已销 / 未销」两段（E3，2026-09-28）----------
# 动因：标题自称「验证状态与待实测清单」，就必须有人核对**状态**这一维。
# 两段的**段标题自带条数**（`### 已销（9 条…）`），而**正文别处不许再抄一遍** ——
# 抄出来的副本必然漂（本项目已栽过：计划书写"节号已排到 15"而脚本当时已是 18 节）。
# 所以这里的判据是「段标题的数字 == 段内实际行数」，外加「两段之和 == D 行总数」。
#
# ⚠️ 数「子段内的行」不能用 count_rows_in_section —— 它只在 `## ` 上重置。
# 而 `## ` 的正则**不匹配** `### x`（`^##` 后要求一个空格，`###` 的第三位是 `#`），
# 所以 `###` 子标题既不会误重置、也必须自己台阶式跟踪。下面这个函数就是干这个的。
#
# ⚠️ **awk 的变量名不能取内建函数名**：这里原先把子段模式叫 `sub`，而 `sub` 是 awk 内建函数
#    ⇒ awk 把 `cur ~ sub` 里的 `sub` 当函数引用解析，直接 `syntax error ... cur ~ sub >>> && <<<`，
#    函数**静默返回空串**，下游三处断言全部误报。凡内建名（sub / gsub / match / index /
#    length / split / sprintf …）一律不得作变量名。
count_rows_in_subsection() {   # $1=文件 $2=## 节名片段 $3=### 子段名片段 $4=行 pattern
  awk -v want="$2" -v subsec="$3" -v pat="$4" '
    /^## /  { sec = ($0 ~ want) ? 1 : 0; cur = ""; next }
    /^### / { if (sec) cur = $0; next }
    sec && cur ~ subsec && $0 ~ pat { n++ }
    END { print n + 0 }
  ' "$1"
}

# 同一子段内的行按**首列编号**列出（空格分隔、已排序）—— 供「点名清单」类比对使用
list_ids_in_subsection() {     # $1=文件 $2=## 节名片段 $3=### 子段名片段
  awk -v want="$2" -v subsec="$3" '
    /^## /  { sec = ($0 ~ want) ? 1 : 0; cur = ""; next }
    /^### / { if (sec) cur = $0; next }
    sec && cur ~ subsec && /^[|]/ {
      n = split($0, a, "|")
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", a[2])
      if (a[2] ~ /^[A-Za-z]+-?[0-9]+$/) print a[2]
    }
  ' "$1" | sort | tr '\n' ' '
}

PD_DONE=$(count_rows_in_subsection "$CPP_MAIN" '附录 D' '^### 已销' '^[|] D[0-9]+ [|]')
PD_UNDONE=$(count_rows_in_subsection "$CPP_MAIN" '附录 D' '^### 未销' '^[|] D[0-9]+ [|]')
PD_DONE_DECL=$(grep -oE '^### 已销（[0-9]+ 条' "$CPP_MAIN" | grep -oE '[0-9]+' | head -1)
PD_UNDONE_DECL=$(grep -oE '^### 未销（[0-9]+ 条' "$CPP_MAIN" | grep -oE '[0-9]+' | head -1)

if [ -z "$PD_DONE_DECL" ] || [ -z "$PD_UNDONE_DECL" ]; then
  fail "C++ 附录 D 缺「### 已销（N 条…）」/「### 未销（N 条…）」段标题 —— 状态维度没有可核对的声明"
else
  [ "$PD_DONE_DECL" = "$PD_DONE" ] \
    && pass "C++ 附录 D「已销」段：标题数字与实际行数一致（${PD_DONE}）" \
    || fail "C++ 附录 D「已销」段数字不一致：段标题写 ${PD_DONE_DECL} 条，段内实际 ${PD_DONE} 行"
  [ "$PD_UNDONE_DECL" = "$PD_UNDONE" ] \
    && pass "C++ 附录 D「未销」段：标题数字与实际行数一致（${PD_UNDONE}）" \
    || fail "C++ 附录 D「未销」段数字不一致：段标题写 ${PD_UNDONE_DECL} 条，段内实际 ${PD_UNDONE} 行"
  if [ $((PD_DONE + PD_UNDONE)) -eq "$PD_ROWS" ]; then
    pass "C++ 附录 D 两段之和 == D 行总数（${PD_DONE} + ${PD_UNDONE} = ${PD_ROWS}）"
  else
    fail "C++ 附录 D 分段漏行：已销 ${PD_DONE} + 未销 ${PD_UNDONE} ≠ D 行总数 ${PD_ROWS}（有行没被归段）"
  fi
fi

# 同一事实在 README 里也声明了一次 —— 跨文件核对，否则它就是下一个漂移点
RM_DONE_DECL=$(grep -oE '待实测\*\*已销 [0-9]+ 条|待实测已销 [0-9]+ 条' "$README" | grep -oE '[0-9]+' | head -1)
if [ -z "$RM_DONE_DECL" ]; then
  warn "README 里推导不出「已销 N 条」的声明，无法与 C++ 附录 D 比对"
elif [ "$RM_DONE_DECL" = "$PD_DONE" ]; then
  pass "README 的「已销 ${RM_DONE_DECL} 条」与 C++ 附录 D 一致"
else
  fail "README 与 C++ 附录 D 的已销条数不一致：README=${RM_DONE_DECL}，附录 D 实际=${PD_DONE}"
fi

# README 点名的「只剩 D8 / D10」也必须与实际未销段一致（点名少了 = 漏报，多了 = 谎报）
# 两侧都归一到「排序 + 空格分隔」再比 —— 比的是集合，不是书写顺序。
RM_UNDONE_IDS=$(grep -oE '只剩[^。]*' "$README" | grep -oE 'D[0-9]+' | sort | tr '\n' ' ')
PD_UNDONE_IDS=$(list_ids_in_subsection "$CPP_MAIN" '附录 D' '^### 未销')
if [ -z "$RM_UNDONE_IDS" ]; then
  warn "README 里推导不出「只剩 D…」的点名，无法与未销段比对"
elif [ "$RM_UNDONE_IDS" = "$PD_UNDONE_IDS" ]; then
  pass "README 点名的未销条目与实际一致（${PD_UNDONE_IDS% }）"
else
  fail "README 点名的未销条目与实际不一致：README=「${RM_UNDONE_IDS% }」实际=「${PD_UNDONE_IDS% }」"
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
hdr 19 "语言判定：SKILL.md / README 的「后缀 → 走哪一套」表必须与探测器逐项一致"
# 起因（2026-09-28，用户明示）：语言判定必须**内联进"写这一个文件"的动作**，不能是"先跑一次"的独立步骤
# —— 所以「看后缀就知道走哪一套」的那张表是判定的**唯一依据**，不是说明书。
# 它与 scripts/detect_language.sh 的 CS_EXT / NATIVE_EXT 一旦漂移，后果是
# **"按表判成 C++、按脚本判成 C#"** —— 最难被发现的一类不一致（两侧都"看着对"）。
# 期望值从脚本推导，不写第二份硬编码。判据的抽取只认**表格行**，
# 故散文里出现的 `*.csproj` / `*.vcxproj`（工程级强标记，不是源码后缀）不会混进来。
if [ -f "$DETECT" ]; then
  DET_SUF=$(mktemp "${TMPDIR:-/tmp}/wcs-detsuf-XXXXXX")
  grep -E '^(CS_EXT|NATIVE_EXT)=' "$DETECT" | grep -oE '\*\.[A-Za-z+]+' | sort -u > "$DET_SUF"
  for pair in "SKILL.md:$SKILL_MD" "README.md:$README"; do
    name=${pair%%:*}; file=${pair#*:}
    TBL_SUF=$(mktemp "${TMPDIR:-/tmp}/wcs-tblsuf-XXXXXX")
    grep -E '^\|[[:space:]]*`\*\.[A-Za-z0-9+]' "$file" 2>/dev/null \
      | grep -oE '\*\.[A-Za-z0-9+]+' | sort -u > "$TBL_SUF"
    if [ ! -s "$TBL_SUF" ]; then
      fail "$name 里找不到「后缀 → 走哪一套」表 —— 语言判定又退化成\"必须先跑一遍命令\""
    else
      SUF_MISS=$(comm -23 "$DET_SUF" "$TBL_SUF" | tr '\n' ' ')
      SUF_EXTRA=$(comm -13 "$DET_SUF" "$TBL_SUF" | tr '\n' ' ')
      if [ -z "$SUF_MISS" ] && [ -z "$SUF_EXTRA" ]; then
        pass "$name 的后缀表与探测器逐项一致（$(wc -l < "$DET_SUF" | tr -d ' ') 个后缀）"
      else
        [ -n "$SUF_MISS" ] && fail "$name 的后缀表漏了探测器认下的后缀：${SUF_MISS}—— 这些文件会被判错侧"
        [ -n "$SUF_EXTRA" ] && fail "$name 的后缀表多出探测器不认的后缀：${SUF_EXTRA}—— 看似分流，实由默认值兜底"
      fi
    fi
    rm -f "$TBL_SUF"
  done
  rm -f "$DET_SUF"
fi

# ---------------------------------------------------------------------------
hdr 20 "G1 病灶索引表：两侧各一张、前两列逐行一致，第四列的归属都指得到东西"
# 起因（2026-09-28，D-2 落槌后）：设计目的 G1 的「机器可查那一半」必须真的机械化 ——
# 否则那张表只是第二份"写下来但没人守"的文件（本工程已吃过这个亏：目的层此前从未被完整写下）。
# 三条断言：
#   ① 两侧都能识别出病灶表，且**行数相同**（病灶类目跨语言共享，不该只有一侧少一类）。
#   ② 前两列（病灶名 + 特征形态）**逐行相同** —— 那是「病」本身；第三、四列**必须分侧**
#      （工具 / 编号体系 / 注释载体都不同），故不参与逐行比对。
#   ③ 第四列每行都要**指得到东西**：一个能在该侧目录里检索到的编号 / 一份判据文件的节 /
#      或明写「本侧不治」（显式出口，仿第 16 节的「反例」约定）。**留空格 = FAIL**。
# 期望值一律从两份文件互相推导，不写第二份硬编码（行数、类名都不硬写）。
lesion_rows() {   # $1=side main file → 每行输出「病灶名 \t 特征形态 \t 第四列」
  awk '
    /^\|/ && index($0, "病灶") && index($0, "机器能否拦住") { t = 1; next }
    t && /^\|/ {
      n = split($0, a, "|")
      for (i = 2; i <= n - 1; i++) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", a[i]) }
      # ⚠️ 必须跳过 Markdown 的分隔行（`|---|---|`）—— 不跳会被当成一行"病灶"，
      #    于是"行数""归属"两处同时误报（2026-09-28 实测：报出 7 行、且剩一行第四列为 `---`）。
      if (a[2] ~ /^-+$/) { next }
      print a[2] "\t" a[3] "\t" a[n-1]
      next
    }
    t { exit }
  ' "$1"
}

# 第四列的归属是否指得到东西。两侧用同一套检查：C++ 行里不会出现 `#nn`，反之亦然。
lesion_owner_check() {   # $1=表文件（TSV） $2=侧名
  local bad="" nm feat own x num hit
  while IFS=$'\t' read -r nm feat own; do
    [ -z "$nm" ] && continue
    printf '%s' "$own" | grep -qE '本侧不治|本规范不治' && continue
    hit=0
    for x in $(printf '%s' "$own" | grep -oE 'CPP-[0-9]+' || true); do
      grep -qE "^[|] ${x} [|]" "$CPP_CATALOG" || bad="${bad}        ${nm} → ${x} 在 C++ 缺陷目录里检索不到\n"
      hit=1
    done
    for x in $(printf '%s' "$own" | grep -oE '#[0-9]+' || true); do
      num=${x#\#}
      grep -qE "^[|] ${num} [|]" "$CATALOG" || bad="${bad}        ${nm} → ${x} 在 C#/.NET 缺陷目录里检索不到\n"
      hit=1
    done
    printf '%s' "$own" | grep -qE '(design-granularity|change-discipline|design-purpose)\.md' && hit=1
    [ "$hit" -eq 0 ] && bad="${bad}        ${nm} → 第四列既无编号、也无判据文件引用，且未写「本侧不治」\n"
  done < "$1"
  if [ -z "$bad" ]; then
    pass "${2} 病灶表：每一行的归属都指得到东西（$(wc -l < "$1" | tr -d ' ') 行）"
  else
    fail "${2} 病灶表有行的归属指不到东西 —— 那就是「表里有、条文里没有」的空格："
    printf '%b' "$bad"
  fi
}

LESION_CPP=$(mktemp "${TMPDIR:-/tmp}/wcs-lesion-cpp-XXXXXX")
LESION_CS=$(mktemp "${TMPDIR:-/tmp}/wcs-lesion-cs-XXXXXX")
lesion_rows "$CPP_MAIN" > "$LESION_CPP"
lesion_rows "$MAIN" > "$LESION_CS"
if [ ! -s "$LESION_CPP" ] || [ ! -s "$LESION_CS" ]; then
  fail "病灶索引表缺失或表头不可识别（表头行须同时含「病灶」与「机器能否拦住」）—— G1 的机器可查那一半又空了"
else
  N_CPP=$(wc -l < "$LESION_CPP" | tr -d ' ')
  N_CS=$(wc -l < "$LESION_CS" | tr -d ' ')
  if [ "$N_CPP" = "$N_CS" ]; then
    pass "两侧病灶表行数一致（${N_CPP} 行）"
  else
    fail "两侧病灶表行数不一致：C++ ${N_CPP} 行 / C#/.NET ${N_CS} 行 —— 类目跨语言共享，不该只有一侧少"
  fi
  cut -f1,2 "$LESION_CPP" > "$LESION_CPP.n"
  cut -f1,2 "$LESION_CS" > "$LESION_CS.n"
  LDIFF=$(diff "$LESION_CPP.n" "$LESION_CS.n" 2>&1 | head -12 || true)
  if [ -z "$LDIFF" ]; then
    pass "两侧的「病灶 / 特征形态」两列逐行一致（只有第三、四列分侧）"
  else
    fail "两侧病灶表的「病灶 / 特征形态」不一致 —— 这两列是「病」本身，必须共享："
    printf '%s\n' "$LDIFF" | sed 's/^/        /'
  fi
  lesion_owner_check "$LESION_CPP" "C++"
  lesion_owner_check "$LESION_CS" "C#/.NET"
fi
rm -f "$LESION_CPP" "$LESION_CS" "$LESION_CPP.n" "$LESION_CS.n"

# ---------------------------------------------------------------------------
hdr 21 "体量阈值：取值只有一处（模板），正文 / 摘要 / 判据层不得复制数值"
# 起因（2026-09-28，D-1 落槌）：实测认知复杂度的阈值 `25` **就是 clang-tidy 的出厂默认值**
# —— 本工程从未选择过它。这暴露出两件事：① 取值的副本散在正文 / 判据层 / 摘要里，
# 谁也说不清哪份是准的；② 一个"抄来的默认值"被标成了 MUST。
# 本节只治①；② 由正文 §2 的元规则（MUST 必须「可检查 **且** 有依据」）承载。
# 四条断言，全部可复核：
#   A. 模板必须**恰好**声明那 5 个体量键（每键出现 1 次）：少一个 = 该检查静默不生效；多一处 = 有了第二份取值。
#   B. 除模板外，交付面不得把阈值写成「键名 = 数值」／「键名: 数值」的赋值式。
#   C. C++ 正文 §5.4 的**表行**内不得出现数字（表只回答「等级 / 依据 / 由谁检查」）。
#      ⚠️ 比对前必须**剥掉 `§x.y` 交叉引用** —— 那是小节号不是阈值；不剥就会把说明文字本身报成违规
#         （本脚本第 14 / 16 / 17 / 19 节都栽在"扫到自己讲解该坑的那段文字"上，这是第 5 次）。
#   D. C# 正文 §5.3 的体量表**带数值**，故必须显式声明"本侧没有配置载体" ——
#      否则它就成了第二份没人声明、也没人核对的来源。
THR_BAD=""
for k in readability-function-size.LineThreshold \
         readability-function-size.ParameterThreshold \
         readability-function-size.NestingThreshold \
         readability-function-size.BranchThreshold \
         readability-function-cognitive-complexity.Threshold; do
  n=$(grep -cF -- "$k" "$CLANG_TIDY" || true)
  [ "$n" = "1" ] || THR_BAD="${THR_BAD}        ${k} 在模板里出现 ${n} 次（必须恰好 1 次）\n"
done
if [ -z "$THR_BAD" ]; then
  pass "assets/clang-tidy 是 5 个体量阈值键的唯一声明处（各 1 次）"
else
  fail "体量阈值键在模板里的声明数不对（少一处 = 静默不生效；多一处 = 第二份取值）："
  printf '%b' "$THR_BAD"
fi

THR_DUPE=$(grep -nE '(LineThreshold|ParameterThreshold|NestingThreshold|BranchThreshold|cognitive-complexity\.Threshold)[[:space:]]*[:=][[:space:]]*"?[0-9]' \
  "$SKILL_MD" "$README" "$CPP_MAIN" "$CPP_CATALOG" "$CPP_NAMING" \
  "$GRANULARITY" "$CHANGE_DISC" "$DESIGN_PURPOSE" 2>/dev/null || true)
if [ -z "$THR_DUPE" ]; then
  pass "正文 / 摘要 / 判据层里没有「阈值键名 = 数值」的赋值式副本"
else
  fail "阈值取值出现在模板之外 —— 取值只能有一份（正文 §1.1）："
  printf '%s\n' "$THR_DUPE" | sed 's/^/        /'
fi

SEC54=$(awk '/^### 5\.4/{s=1;next} s&&/^### /{s=0} s' "$CPP_MAIN" \
        | sed -E 's/§[0-9]+(\.[0-9]+)*//g' | grep -nE '^\|.*[0-9]' || true)
if [ -z "$SEC54" ]; then
  pass "C++ 正文 §5.4 的表内无裸数值（表只回答「等级 / 依据 / 由谁检查」）"
else
  fail "C++ 正文 §5.4 的表行里又出现了数值 —— 取值只能写在 assets/clang-tidy："
  printf '%s\n' "$SEC54" | sed 's/^/        /'
fi

SEC53=$(awk '/^### 5\.3/{s=1;next} s&&/^### /{s=0} s' "$MAIN")
if printf '%s' "$SEC53" | grep -qE '^\|.*[0-9]'; then
  if printf '%s' "$SEC53" | grep -q '没有配置载体'; then
    pass "C# 正文 §5.3 带数值且已声明「本侧没有配置载体」（它是该侧四项的唯一出处）"
  else
    fail "C# 正文 §5.3 的表带数值，却没声明该侧没有配置载体 —— 那会变成一份没人声明的第二来源"
  fi
else
  warn "C# 正文 §5.3 的体量表已不再写数值 —— 请确认这四项的取值另有出处并已登记"
fi

# ---------------------------------------------------------------------------
hdr 22 "引用可解析：正文里的 §X.Y 必须指得到真实标题（E2，2026-09-28）"
#
# 动因：两侧正文与跨语言判据文件之间到处用 §X.Y 互引，**从来没有一处被核对过**。
# 标题一改名，引用就变成「看起来指得到、其实指空」—— 与 §7.3 反复强调的假绿同形。
#
# 【归属规则】一个 §X.Y 指向哪个文件，看**同一行内、它前面最后一次出现的 `xxx.md`**，
# 但**只有**当 `.md` 与 `§` 之间只剩空格 / `*` / 反引号时才算「紧跟」；列表项
# （`§1.4 / §5.6`）继承前一项的归属。
# 反例（两侧头部「配套文件清单」里真实存在，试跑时正是被它骗了一次）：
#     `design-granularity.md` —— …（臃肿 / 过度拆分，§5.4 与 §6.3 引用它）
# 这里的 §5.4 / §6.3 说的是**本文件**的小节（"本文件在哪几节引用了它"），不是那个文件的小节。
# 若按「最后一个 .md」无条件归属，本文件的引用会被整批误判成跨文件引用。
#
# ⚠️ **判据要比计划里那版更严。** 计划原拟 `grep -qE "^#{2,4} ${ref}([^0-9]|$)"`，
#    而该模式会让 `§3` **命中 `### 3.1`**（`3` 之后是 `.`，而 `.` 属于 `[^0-9]`）
#    ⇒ 它**过不了计划自己写的负向测试**（"只写前缀 §3 而正文只有 `### 3.1` 必须 FAIL"）。
#    本节的判据**不走「前缀 + 边界字符」**，而是把标题编号抽成一个**集合**再精确相等：
#        `## 3. 格式` → `3`      `### 3.1 取值` → `3.1`
#    `§3` 与 `3.1` 在集合里**天然不相等**，前缀混同从根上不成立。
#    实测：只含 `### 3.1` 的夹具里，`§3` **不**命中（计划那版会命中 = 假绿），`§3.1` 命中。

# 抽出文件里的全部 §X.Y 引用并判定归属。
# 输出三列：目标文件 <TAB> 引用号 <TAB> 本行点到的 .md（逗号分隔，可为空）
sec_refs_of() {
  awk -v self="$2" '
    {
      line = $0
      md_n = 0; mdlist = ""
      p = line; off = 0
      while (match(p, /[A-Za-z0-9_.-]+\.md/)) {
        md_n++
        md_e[md_n]  = off + RSTART + RLENGTH - 1
        md_nm[md_n] = substr(p, RSTART, RLENGTH)
        mdlist = (mdlist == "" ? md_nm[md_n] : mdlist "," md_nm[md_n])
        off += RSTART + RLENGTH - 1
        p = substr(p, RSTART + RLENGTH)
      }
      pos = 0; prev_target = self; prev_end = 0
      while (1) {
        if (!match(substr(line, pos + 1), /§[0-9]+(\.[0-9]+)*/)) break
        mstart = pos + RSTART; mlen = RLENGTH
        matched = substr(line, mstart, mlen)
        ref = "?"
        # ⚠️ 不能写 substr(matched, 2)：`§` 在 UTF-8 里是 **2 字节**，
        #    在 LC_ALL=C 下按字节切片会从字符中间切开，ref 直接变成空串。
        #    对匹配段再取一次 ASCII 的数字/句点即可。
        if (match(matched, /[0-9]+(\.[0-9]+)*/)) ref = substr(matched, RSTART, RLENGTH)
        tgt = ""
        for (k = 1; k <= md_n; k++)
          if (md_e[k] < mstart) {
            gap = substr(line, md_e[k] + 1, mstart - md_e[k] - 1)
            if (gap ~ /^[ \t*`]*$/) tgt = md_nm[k]
          }
        if (tgt == "" && prev_end > 0) {
          g2 = substr(line, prev_end + 1, mstart - prev_end - 1)
          if (g2 ~ /^[ \t]*[\/、][ \t]*\**[ \t]*$/) tgt = prev_target
        }
        if (tgt == "") tgt = self
        key = tgt SUBSEP ref
        if (!(key in seen)) { seen[key] = 1; printf "%s\t%s\t%s\n", tgt, ref, mdlist }
        prev_target = tgt; prev_end = mstart + mlen - 1
        pos = mstart + mlen - 1
      }
    }
  ' "$1"
}

# 取一份文件里所有小节标题的**编号集合**（空格分隔）：
#   `## 3. 格式` → `3`；`### 3.1 基础风格` → `3.1`；`#### 1.4.1 x` → `1.4.1`
# `[.]?` 吃掉 `## N. ` 的那个句点，再统一剥掉行首 `#` 与尾随句点。
sec_ids_of() {
  grep -oE '^#{2,4} [0-9]+(\.[0-9]+)*[.]?' "$1" | sed -E 's/^#+ //; s/[.]$//' | tr '\n' ' '
}

# ⚠️ 各文件的编号集合**只读一次**：56 处引用若每处都起一个 grep，实测 ~5 秒；
#    而 §18 会把本脚本**再整体跑一遍**，这份开销直接翻倍。
SEC_IDS_CS=$(sec_ids_of "$MAIN")
SEC_IDS_CPP=$(sec_ids_of "$CPP_MAIN")
SEC_IDS_NAMING=$(sec_ids_of "$CPP_NAMING")
SEC_IDS_GRAN=$(sec_ids_of "$GRANULARITY")
SEC_IDS_CHANGE=$(sec_ids_of "$CHANGE_DISC")
SEC_IDS_PURPOSE=$(sec_ids_of "$DESIGN_PURPOSE")

sec_ids_for() {   # $1=目标文件名 → 该文件的小节编号集合
  case "$1" in
    csharp-coding-standards.md)  printf '%s' "$SEC_IDS_CS" ;;
    cpp-coding-standards.md)     printf '%s' "$SEC_IDS_CPP" ;;
    cpp-naming-antipatterns.md)  printf '%s' "$SEC_IDS_NAMING" ;;
    design-granularity.md)       printf '%s' "$SEC_IDS_GRAN" ;;
    change-discipline.md)        printf '%s' "$SEC_IDS_CHANGE" ;;
    design-purpose.md)           printf '%s' "$SEC_IDS_PURPOSE" ;;
    *)                           sec_ids_of "$SKILL_DIR/references/$1" ;;
  esac
}

sec_in() { case " $1 " in *" $2 "*) return 0 ;; esac; return 1; }   # $1=集合 $2=编号

SEC_TOTAL=0
SEC_BAD=""
SEC_AMB=""
for sec_pair in "$MAIN:csharp-coding-standards.md" "$CPP_MAIN:cpp-coding-standards.md"; do
  sec_file=${sec_pair%%:*}
  sec_self=${sec_pair##*:}
  while IFS="$(printf '\t')" read -r sec_tgt sec_ref sec_mds; do
    [ -z "$sec_ref" ] && continue
    SEC_TOTAL=$((SEC_TOTAL + 1))
    if [ "$sec_tgt" = "$sec_self" ]; then sec_tf="$sec_file"; else sec_tf="$SKILL_DIR/references/$sec_tgt"; fi
    if [ ! -f "$sec_tf" ]; then
      SEC_BAD="${SEC_BAD}        §${sec_ref} 归属到 ${sec_tgt}，但该文件不存在（${sec_self}）\n"
      continue
    fi
    sec_in "$(sec_ids_for "$sec_tgt")" "$sec_ref" && continue
    # 目标里没有：再看同一行点到的**其它** .md 里有没有 ——
    # 有的话只是「归属没写明」，不该判死（判死会变成误报，见上面 design-granularity 那条反例）。
    sec_alt=""
    sec_oldifs=$IFS; IFS=,
    for sec_c in $sec_mds; do
      [ "$sec_c" = "$sec_tgt" ] && continue
      [ -f "$SKILL_DIR/references/$sec_c" ] || continue
      sec_in "$(sec_ids_for "$sec_c")" "$sec_ref" && sec_alt="${sec_alt}${sec_alt:+ }${sec_c}"
    done
    IFS=$sec_oldifs
    if [ -n "$sec_alt" ]; then
      SEC_AMB="${SEC_AMB}        §${sec_ref}：${sec_tgt} 里没有，但同一行的 ${sec_alt} 里有 —— 归属没写明，锚点改名时会静默漂\n"
    else
      SEC_BAD="${SEC_BAD}        §${sec_ref} → ${sec_tgt} 里没有这个标题（${sec_self} 的引用指空了）\n"
    fi
  done <<EOF
$(sec_refs_of "$sec_file" "$sec_self")
EOF
done

if [ -n "$SEC_BAD" ]; then
  fail "有 §X.Y 引用指不到任何标题（共扫过 ${SEC_TOTAL} 处引用）："
  printf '%b' "$SEC_BAD"
else
  pass "两侧正文的 §X.Y 引用全部可解析（共扫过 ${SEC_TOTAL} 处引用）"
fi
if [ -n "$SEC_AMB" ]; then
  warn "有 §X.Y 引用的归属没写明（不判死，但建议补上文件名）："
  printf '%b' "$SEC_AMB"
fi

# ---------------------------------------------------------------------------
hdr 23 "审计层与规则层的通路（E6 / E7，2026-09-28）"
# 动因：五道门全是**证伪型**，门 4 要求 finding 填「skill 预期 vs 实际发生」，
# 而 C 类（覆盖缺口）的字面意思就是"skill 里没有这条" ⇒ 它天然填不出 expected，
# **被门 4 结构性挡下**。可 C 类又是唯一能回答"规则层缺了哪几条"的类别
# （A/B/D/E/F 都在"已有声明或既有规则"内部挑错）。于是设计目的 **G5**（审计层能发现
# 规则层缺口）此前根本不成立 —— 不是没做，是**结构上没有通路**。
# 本节机械守住两件落地：
#   ① C 类口径必须写到，且必须把 expected 的来源钉在**目的层**文件上（否则又变成"我觉得应该有"）；
#   ② claims 必须接上两侧正文附录 D：**逐侧条数对得上** + 编号不断号 + 每行字段数一致。

AUDIT_README="$SKILL_DIR/audit/README.md"
AUDIT_BRIEF="$SKILL_DIR/audit/briefs/agent-brief.md"
CLAIMS="$SKILL_DIR/audit/templates/claims-checklist.tsv"

# ---------- ① C 类专用口径 ----------
for aud_pair in "$AUDIT_README:audit/README.md" "$AUDIT_BRIEF:audit/briefs/agent-brief.md"; do
  aud_f=${aud_pair%%:*}
  aud_n=${aud_pair##*:}
  if [ ! -f "$aud_f" ]; then
    fail "${aud_n} 不存在 —— 审计层的 C 类口径无处安放"
    continue
  fi
  if ! grep -q 'C 类' "$aud_f"; then
    fail "${aud_n} 里推导不出「C 类」专用口径 —— 覆盖缺口会被差异门结构性挡下（G5 失守）"
  elif ! grep -q 'design-purpose\.md' "$aud_f"; then
    fail "${aud_n} 写了 C 类口径，但没把 expected 的来源指向目的层 design-purpose.md"
  else
    pass "${aud_n} 有 C 类专用口径，且 expected 的来源指向目的层"
  fi
done

# ---------- ② claims 接线两侧附录 D ----------
if [ ! -f "$CLAIMS" ]; then
  fail "audit/templates/claims-checklist.tsv 不存在 —— E7 的接线没有落点"
else
  CS_D=$(count_rows_in_section "$MAIN"     '附录 D' '^[|] [0-9]+ [|]')
  CPP_D=$(count_rows_in_section "$CPP_MAIN" '附录 D' '^[|] D[0-9]+ [|]')
  CL_CS=$(awk -F'\t' 'NR > 1 && $3 ~ /csharp-coding-standards\.md 附录 D/ { n++ } END { print n + 0 }' "$CLAIMS")
  CL_CPP=$(awk -F'\t' 'NR > 1 && $3 ~ /cpp-coding-standards\.md 附录 D/ { n++ } END { print n + 0 }' "$CLAIMS")
  [ "$CS_D" = "$CL_CS" ] \
    && pass "claims 接入 C# 附录 D 的条数与正文一致（${CS_D}）" \
    || fail "claims 接入 C# 附录 D 的条数不一致：正文 ${CS_D} 条，claims 里 ${CL_CS} 条"
  [ "$CPP_D" = "$CL_CPP" ] \
    && pass "claims 接入 C++ 附录 D 的条数与正文一致（${CPP_D}）" \
    || fail "claims 接入 C++ 附录 D 的条数不一致：正文 ${CPP_D} 条，claims 里 ${CL_CPP} 条"

  # README 也把这两个数抄了一份 —— 跨文件核对，否则它就是下一个漂移点。
  # （与第 9 节核对 README 的「已销 N 条」同一处理：同一事实写两处，就必须有人比对。）
  CL_TOTAL=$(awk -F'\t' 'NR > 1 && NF > 1 { n++ } END { print n + 0 }' "$CLAIMS")
  RM_CL_TOTAL=$(grep -oE '共 [0-9]+ 条断言' "$README" | grep -oE '[0-9]+' | head -1)
  RM_CL_D=$(grep -oE '其中 \*\*[0-9]+ 条直接接在两侧正文附录 D 上' "$README" | grep -oE '[0-9]+' | head -1)
  if [ -z "$RM_CL_TOTAL" ] || [ -z "$RM_CL_D" ]; then
    warn "README 里推导不出 claims 的条数声明（共 N 条 / 其中 N 条接附录 D），无法比对"
  else
    [ "$RM_CL_TOTAL" = "$CL_TOTAL" ] \
      && pass "README 声明的 claims 总数与实际一致（${CL_TOTAL}）" \
      || fail "README 与 claims 的总数不一致：README=${RM_CL_TOTAL}，实际=${CL_TOTAL}"
    [ "$RM_CL_D" = "$((CS_D + CPP_D))" ] \
      && pass "README 声明的「接附录 D」条数与两侧之和一致（$((CS_D + CPP_D))）" \
      || fail "README 与两侧附录 D 之和不一致：README=${RM_CL_D}，实际=$((CS_D + CPP_D))"
  fi

  # 每行字段数必须一致（8 列）—— 追加时若用了空格而非制表符，整份 TSV 会静默散架
  CL_BADF=$(awk -F'\t' 'NR > 1 && NF > 1 && NF != 8 { print NR }' "$CLAIMS" | head -3 | tr '\n' ' ')
  if [ -z "$CL_BADF" ]; then
    pass "claims 每行字段数一致（8 列）"
  else
    fail "claims 有行的字段数不为 8（行号：${CL_BADF% }）—— 追加时误用了空格而非制表符"
  fi

  # 编号连续无断号（与 C++ 缺陷编号同一条纪律：漏改号或删条目必留坑）
  read -r CL_N CL_MAX <<EOF
$(awk -F'\t' 'NR > 1 && $1 ~ /^CLM-[0-9]+$/ { n = substr($1, 5) + 0; if (n > max) max = n; c++ } END { print c + 0, max + 0 }' "$CLAIMS")
EOF
  if [ -n "$CL_MAX" ] && [ "$CL_N" = "$CL_MAX" ]; then
    pass "claims 编号连续（CLM-001…CLM-$(printf '%03d' "$CL_MAX")，无断号）"
  else
    fail "claims 编号不连续：最大编号 ${CL_MAX}，条目数 ${CL_N} —— 有断号或重复"
  fi
fi

# ---------------------------------------------------------------------------
hdr 24 "C++ 侧工具脚本的契约（退出码 / 参数 / 空范围必须非零）"
# 起因（2026-09-29，E5）：C++ 侧此前**没有**安装与采基线脚本，全靠手抄接入计划 §4.2 的命令。
# 而 §4.2 那几行里，一半的失效形态是「命令在跑、退出码也在变、实际一个文件都没查」
# （空清单 / 缺工具 / 缺编译数据库）。所以这两个脚本的**契约**必须被机械核对，
# 而不是"写完看一眼"——与 §18 对自检脚本本身做的是同一件事。
B_SCRIPT="$SCRIPT_DIR/bootstrap_cpp_style.sh"
L_SCRIPT="$SCRIPT_DIR/baseline_cpp_style.sh"

# A. 存在性 + 语法
for sf in "$B_SCRIPT" "$L_SCRIPT"; do
  if [ ! -f "$sf" ]; then
    fail "C++ 侧脚本缺失：$(basename "$sf") —— 手抄 §4.2 的命令会立刻复活"
    continue
  fi
  if bash -n "$sf" 2>/dev/null; then
    pass "C++ 侧脚本存在且语法通过：$(basename "$sf")"
  else
    fail "C++ 侧脚本语法错误：$(basename "$sf")"
  fi
done

# B. 头部声明的退出码与实际必须互为子集（同 §18 A，口径一致）
for sf in "$B_SCRIPT" "$L_SCRIPT"; do
  [ -f "$sf" ] || continue
  sbn=$(basename "$sf")
  DECL=$(sed -n 's/^# 退出码:[^0-9]*//p' "$sf" | grep -oE '[0-9]+' | sort -u)
  ACT=$(grep -oE '^[[:space:]]*exit[[:space:]]+[0-9]+' "$sf" | grep -oE '[0-9]+' | sort -u)
  if [ -z "$DECL" ]; then
    fail "${sbn} 头部找不到「# 退出码:」声明行 —— 契约无从核对"
  else
    MIS=""
    for c in $DECL; do printf '%s\n' "$ACT" | grep -qx -- "$c" || MIS="${MIS}${c} "; done
    if [ -z "$MIS" ]; then
      pass "${sbn} 声明的退出码（$(printf '%s' "$DECL" | tr '\n' ' ' | sed 's/ $//')）都有对应 exit"
    else
      fail "${sbn} 声明了但脚本里不可能出现的退出码：${MIS}—— 调用方无法依赖"
    fi
    UND=""
    for c in $ACT; do printf '%s\n' "$DECL" | grep -qx -- "$c" || UND="${UND}${c} "; done
    if [ -n "$UND" ]; then
      fail "${sbn} 有未在头部声明的退出码：${UND}—— 要么补进声明，要么删掉该 exit"
    fi
  fi
done

# C. 真功能：未知参数必须被拒（exit 2），不得静默退化成"看起来成功了"
for sf in "$B_SCRIPT" "$L_SCRIPT"; do
  [ -f "$sf" ] || continue
  bash "$sf" "$SKILL_DIR" --__wcs_bogus_flag__ >/dev/null 2>&1
  BOGUS_RC=$?
  if [ "$BOGUS_RC" -eq 2 ]; then
    pass "$(basename "$sf") 拒绝未知参数（exit 2）"
  else
    fail "$(basename "$sf") 未知参数返回 ${BOGUS_RC}（应为 2）—— 拼错的选项会静默退化"
  fi
done

# D. **空范围必须非零退出** —— 这是防"假基线"的承重墙。
#    接入计划 §4.2 的原话：「分母写 0 比不写分母更坏：它看起来是已核对过的」。
#    这条刻意安排在**工具检测之前**（先判范围再判环境），所以在没装 clang 的机器上也成立。
if [ -f "$L_SCRIPT" ]; then
  EMPTY_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t wcs)
  if [ -n "$EMPTY_DIR" ] && [ -d "$EMPTY_DIR" ]; then
    bash "$L_SCRIPT" "$EMPTY_DIR" >/dev/null 2>&1
    EMPTY_RC=$?
    if [ "$EMPTY_RC" -eq 4 ]; then
      pass "baseline 脚本对**空范围**非零退出（exit 4）—— 不会把「没扫到」报成「0 违规」"
    else
      fail "baseline 脚本对空范围返回 ${EMPTY_RC}（应为 4）—— 空清单会被读成「干净」"
    fi
    rm -rf "$EMPTY_DIR"
  else
    warn "无法创建临时空目录，跳过「空范围必须非零」这条检查"
  fi
fi

# E. 两个脚本必须列进 SKILL.md —— 交付了却不入口，等于没交付
for sbn in bootstrap_cpp_style.sh baseline_cpp_style.sh; do
  if grep -qF "$sbn" "$SKILL_MD"; then
    pass "SKILL.md 已列出 ${sbn}"
  else
    fail "SKILL.md 未列出 ${sbn} —— C++ 侧脚本不入口，用户仍会手抄 §4.2"
  fi
done

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
