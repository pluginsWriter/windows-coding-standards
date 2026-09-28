#!/usr/bin/env bash
# =============================================================================
# windows-coding-standards —— 语言探测（C++ / C#/.NET）
# =============================================================================
# 用途：本 skill 同时支持 C++ 与 C#/.NET，但两者的规则正文、配置载体与工具链
#       完全不同。本脚本只回答一个问题：**这次该走哪一套**。
#
# 用法:
#   bash scripts/detect_language.sh <目录>                     # 工程级探测
#   bash scripts/detect_language.sh <目录> <文件> [<文件>...]  # 任务级证据优先
#   bash scripts/detect_language.sh --self-test                # 自检（校验探测器本身）
#
# 输出末三行恒为机器可读:
#   STACK=cpp|csharp|mixed|unknown
#   PRIMARY=cpp|csharp
#   CONFIDENCE=high|low
#
# 退出码: 0 正常（含 unknown）；1 自检失败；2 用法错误；3 自检无法创建临时目录
#
# 判定优先级（高 → 低）:
#   1. 任务级：本次实际改动的文件后缀 —— **这才是最终决定项**
#   2. 工程级强标记：.csproj / .vcxproj / CMakeLists.txt / vcpkg.json / global.json
#      以及 *.sln 的**内容**（它引用的是 .csproj 还是 .vcxproj）
#   3. 工程级后缀普查：.cs  vs  .cpp/.cc/.cxx/.h/.hpp/.hxx
#   4. 无任何证据 → 取默认 cpp（CONFIDENCE=low）
#
# ⚠️ 两个**不能**当判据的共享标记（C# 与 C++ 共用 MSBuild）:
#   · *.sln                  —— 两语言都用；只能读**内容**消歧，存在性无意义
#   · Directory.Build.props  —— 同上（C++ 工程也用它）
#   把共享标记当语言判据，是这个探测器最容易犯的错，自检里专门有一个反例。
#
# 纪律（沿本工程既有约定）:
#   · 输出全中文；`$VAR` 后紧跟全角标点一律写 `${VAR}`（UTF-8 下会被吞进变量名）
#   · 只用 [[:space:]]，不用 \s / \w / \b（BSD grep 不认）
#   · 只读，不写被探测目录
# =============================================================================

set -uo pipefail

DEPTH=6
PRUNE=( -name .git -o -name .svn -o -name bin -o -name obj -o -name node_modules \
        -o -name .vs -o -name packages -o -name __pycache__ -o -name .workbuddy \
        -o -name .idea -o -name .vscode -o -name 'cmake-build-*' )

# 后缀分组（-iname 模式）
CS_EXT=( '*.cs' '*.csx' )
NATIVE_EXT=( '*.cpp' '*.cc' '*.cxx' '*.c++' '*.h' '*.hh' '*.hpp' '*.hxx' '*.h++' '*.c' '*.ipp' '*.inl' )
# 强标记（存在即可作为判据）
CS_MARK=( '*.csproj' '*.fsproj' '*.vbproj' 'global.json' )
NATIVE_MARK=( '*.vcxproj' 'CMakeLists.txt' 'CMakePresets.json' 'vcpkg.json' 'conanfile.txt' 'conanfile.py' 'meson.build' )

# ---------------------------------------------------------------------------
# 计数：目录下匹配任一模式的文件数（剪掉常见产物目录）
count_match() {
  local dir="$1"; shift
  local -a pats=()
  local p
  for p in "$@"; do pats+=( -o -iname "$p" ); done
  [ "${#pats[@]}" -eq 0 ] && { printf '0'; return; }
  find "$dir" -maxdepth "$DEPTH" \( "${PRUNE[@]}" \) -prune -o \
       -type f \( "${pats[@]:1}" \) -print 2>/dev/null | wc -l | tr -d ' '
}

# 列出：目录下匹配任一模式的文件（截断，仅用于出示证据）
list_match() {
  local dir="$1"; shift
  local -a pats=()
  local p
  for p in "$@"; do pats+=( -o -iname "$p" ); done
  [ "${#pats[@]}" -eq 0 ] && return
  find "$dir" -maxdepth "$DEPTH" \( "${PRUNE[@]}" \) -prune -o \
       -type f \( "${pats[@]:1}" \) -print 2>/dev/null | sort | head -8
}

# 文件后缀归档：cs / native / other
classify_file() {
  local f="$1" base
  base=$(basename "$f")
  case "$base" in
    *.cs|*.csx) printf 'cs' ;;
    *.cpp|*.cc|*.cxx|*.c++|*.h|*.hh|*.hpp|*.hxx|*.h++|*.c|*.ipp|*.inl) printf 'native' ;;
    *.csproj|*.fsproj|*.vbproj|global.json) printf 'cs' ;;
    *.vcxproj|CMakeLists.txt|CMakePresets.json|vcpkg.json|conanfile.txt|conanfile.py|meson.build) printf 'native' ;;
    *) printf 'other' ;;
  esac
}

# .sln 内容消歧 → 回显 "<cs 计数> <native 计数>"
sln_probe() {
  local sln="$1" cs nat
  cs=$(grep -ciE '\.csproj' "$sln" 2>/dev/null); cs=${cs:-0}
  nat=$(grep -ciE '\.vcxproj' "$sln" 2>/dev/null); nat=${nat:-0}
  printf '%s %s' "$cs" "$nat"
}

# ---------------------------------------------------------------------------
# 核心：探测并回显 STACK=/PRIMARY=/CONFIDENCE=（供 --self-test 复用）
probe() {
  local dir="$1"; shift
  local -a taskfiles=( "$@" )

  local cs_task=0 nat_task=0 f kind
  local -a cs_hits=() nat_hits=()
  for f in "${taskfiles[@]:-}"; do
    [ -n "${f}" ] || continue
    kind=$(classify_file "$f")
    case "$kind" in
      cs)     cs_task=$((cs_task + 1)); cs_hits+=( "$f" ) ;;
      native) nat_task=$((nat_task + 1)); nat_hits+=( "$f" ) ;;
    esac
  done

  local cs_ext nat_ext cs_mark nat_mark sln_cs=0 sln_nat=0
  local -a slns=()
  cs_ext=$(count_match "$dir" "${CS_EXT[@]}")
  nat_ext=$(count_match "$dir" "${NATIVE_EXT[@]}")
  cs_mark=$(count_match "$dir" "${CS_MARK[@]}")
  nat_mark=$(count_match "$dir" "${NATIVE_MARK[@]}")

  if [ "${#taskfiles[@]}" -eq 0 ]; then
    printf '任务级证据: （未提供；仅做工程级探测）\n'
  else
    printf '任务级证据（本次涉及的 %s 个路径）:\n' "${#taskfiles[@]}"
    printf '  C#/.NET 命中 %s\n' "${cs_task}"
    [ "${#cs_hits[@]}" -gt 0 ] && printf '%s\n' "${cs_hits[@]}" | sed 's/^/      /'
    printf '  原生(C/C++) 命中 %s\n' "${nat_task}"
    [ "${#nat_hits[@]}" -gt 0 ] && printf '%s\n' "${nat_hits[@]}" | sed 's/^/      /'
  fi

  while IFS= read -r s; do [ -n "$s" ] && slns+=( "$s" ); done < <(list_match "$dir" '*.sln')
  local s pair
  for s in "${slns[@]:-}"; do
    [ -n "$s" ] || continue
    pair=$(sln_probe "$s")
    sln_cs=$((sln_cs + ${pair%% *}))
    sln_nat=$((sln_nat + ${pair##* }))
  done

  printf '工程级证据（深度 ≤ %s，已排除 .git/bin/obj/node_modules/.vs/packages 等）:\n' "${DEPTH}"
  printf '  C#/.NET     源码 .cs=%s  项目标记 .csproj 类=%s\n' "${cs_ext}" "${cs_mark}"
  printf '  原生(C/C++) 源码 .cpp/.h 等=%s  项目标记 .vcxproj/CMake 类=%s\n' "${nat_ext}" "${nat_mark}"
  local props_n
  props_n=$(count_match "$dir" 'Directory.Build.props' 'Directory.Build.targets')
  if [ "${#slns[@]}" -gt 0 ] || [ "${props_n}" -gt 0 ]; then
    printf '  共享标记（**存在性不可作判据**，只有 .sln 的引用内容可消歧）:\n'
    printf '      Directory.Build.props / .targets：%s 个（C# 与 C++ 共用）\n' "${props_n}"
    for s in "${slns[@]:-}"; do
      [ -n "${s}" ] || continue
      pair=$(sln_probe "$s")
      printf '      %s → 引用 .csproj %s 个 / .vcxproj %s 个\n' "${s}" "${pair%% *}" "${pair##* }"
    done
  else
    printf '  共享标记：未发现 .sln 与 Directory.Build.props / .targets\n'
  fi

  local stack confidence primary why
  if [ "$cs_task" -gt 0 ] || [ "$nat_task" -gt 0 ]; then
    confidence="high"
    if [ "$cs_task" -gt 0 ] && [ "$nat_task" -gt 0 ]; then
      stack="mixed"; primary="cpp"; why="任务级证据同时含两种语言"
    elif [ "$cs_task" -gt 0 ]; then
      stack="csharp"; primary="csharp"; why="任务级证据只含 C#/.NET 文件"
    else
      stack="cpp"; primary="cpp"; why="任务级证据只含原生(C/C++)文件"
    fi
  else
    local cs_all=$((cs_mark + sln_cs)) nat_all=$((nat_mark + sln_nat))
    if [ "$cs_all" -gt 0 ] || [ "$nat_all" -gt 0 ]; then
      confidence="high"
      if [ "$cs_all" -gt 0 ] && [ "$nat_all" -gt 0 ]; then
        stack="mixed"; primary="cpp"; why="工程级标记同时含两种语言"
      elif [ "$cs_all" -gt 0 ]; then
        stack="csharp"; primary="csharp"; why="工程级标记只含 C#/.NET"
      else
        stack="cpp"; primary="cpp"; why="工程级标记只含原生(C/C++)"
      fi
    else
      if [ "$cs_ext" -gt 0 ] && [ "$nat_ext" -gt 0 ]; then
        stack="mixed"; primary="cpp"; confidence="low"; why="仅后缀普查，两语言源码并存"
      elif [ "$cs_ext" -gt 0 ]; then
        stack="csharp"; primary="csharp"; confidence="low"; why="仅后缀普查，只见 .cs"
      elif [ "$nat_ext" -gt 0 ]; then
        stack="cpp"; primary="cpp"; confidence="low"; why="仅后缀普查，只见原生源码"
      else
        stack="unknown"; primary="cpp"; confidence="low"; why="零证据 → 取默认 cpp"
      fi
    fi
  fi

  printf '\n判定: %s （%s）\n' "${stack}" "${why}"
  if [ "${stack}" = "mixed" ]; then
    printf '  说明: 混合工程 —— **按文件路由**，不要整仓用同一套正文。\n'
  fi
  printf 'STACK=%s\nPRIMARY=%s\nCONFIDENCE=%s\n' "${stack}" "${primary}" "${confidence}"
}

# ---------------------------------------------------------------------------
# 自检：校验探测器本身（本工程规矩 —— 校验函数本身也要被校验）
self_test() {
  local base rc=0
  base=$(mktemp -d "${TMPDIR:-/tmp}/wcs-detect-XXXXXX") || return 3
  # 注意：不能用 `local base` 再在 EXIT trap 里引用 —— 函数返回后 base 已出作用域，
  # `set -u` 下 trap 会以 "base: unbound variable" 失败（实测踩过）。
  DETECT_TMP="$base"
  trap 'rm -rf "$DETECT_TMP"' EXIT

  mkdir -p "$base/cs-only/src" "$base/cpp-only/src" "$base/mixed/cs" "$base/mixed/native" \
           "$base/empty" "$base/sln-vcxproj/src" "$base/shared-marker-native/src" \
           "$base/cpp-deep/obj/trap"
  : > "$base/cs-only/App.csproj";  : > "$base/cs-only/src/Program.cs"
  : > "$base/cpp-only/App.vcxproj"; : > "$base/cpp-only/src/main.cpp"; : > "$base/cpp-only/src/main.h"
  : > "$base/mixed/cs/App.csproj"; : > "$base/mixed/cs/P.cs"
  : > "$base/mixed/native/App.vcxproj"; : > "$base/mixed/native/m.cpp"
  : > "$base/sln-vcxproj/S.sln"
  printf 'Project("{8BC9CEB8-8B4A-11D0-8D11-00A0C91BC942}") = "A", "A\\A.vcxproj", "{}"\n' > "$base/sln-vcxproj/S.sln"
  : > "$base/sln-vcxproj/src/a.cpp"
  : > "$base/shared-marker-native/Directory.Build.props"     # 共享标记，**不是** C# 判据
  : > "$base/shared-marker-native/src/main.cpp"
  : > "$base/cpp-deep/obj/trap/should-be-pruned.cpp"          # 应被 prune 掉

  check() {  # check <期望 STACK> <期望 CONFIDENCE> <目录> [任务文件...]
    local want_stack="$1" want_conf="$2" dir="$3"; shift 3
    local out got_stack got_conf
    out=$(probe "$dir" "$@" 2>&1)
    got_stack=$(printf '%s\n' "$out" | sed -n 's/^STACK=//p' | tail -1)
    got_conf=$(printf '%s\n' "$out" | sed -n 's/^CONFIDENCE=//p' | tail -1)
    if [ "$got_stack" = "$want_stack" ] && [ "$got_conf" = "$want_conf" ]; then
      printf '  PASS  %-26s → %s / %s\n' "$(basename "$dir")" "$got_stack" "$got_conf"
    else
      printf '  FAIL  %-26s → 期望 %s / %s，实得 %s / %s\n' \
        "$(basename "$dir")" "$want_stack" "$want_conf" "$got_stack" "$got_conf"
      rc=1
    fi
  }

  printf '=== detect_language.sh 自检 ===\n'
  check csharp high "$base/cs-only"
  check cpp    high "$base/cpp-only"
  check mixed  high "$base/mixed"
  check cpp    high "$base/sln-vcxproj"        # 只有 .sln，靠**内容**消歧
  # 共享标记陷阱：只有 Directory.Build.props（两语言共用）→ 不得判为 csharp。
  # 此处无项目文件，只能靠后缀普查，故 CONFIDENCE 应为 low。
  check cpp    low  "$base/shared-marker-native"
  check unknown low "$base/empty"              # 零证据 → STACK=unknown

  # 任务级优先：目录是 C#，但本次动的是 .cpp → 必须判 cpp
  local out
  out=$(probe "$base/cs-only" "$base/cpp-only/src/main.cpp" 2>&1)
  if printf '%s\n' "$out" | grep -q '^STACK=cpp$'; then
    printf '  PASS  %-26s → 任务级覆盖工程级\n' 'task-level-priority'
  else
    printf '  FAIL  %-26s → 任务级未覆盖工程级\n' 'task-level-priority'; rc=1
  fi

  # 默认值：零证据时 PRIMARY 必须是 cpp
  if probe "$base/empty" 2>&1 | grep -q '^PRIMARY=cpp$'; then
    printf '  PASS  %-26s → PRIMARY=cpp\n' 'default-primary'
  else
    printf '  FAIL  %-26s → 默认值不是 cpp\n' 'default-primary'; rc=1
  fi

  # prune 生效：obj/ 下的 .cpp 不应被计入
  local n
  n=$(count_match "$base/cpp-deep" '*.cpp')
  if [ "$n" = "0" ]; then
    printf '  PASS  %-26s → obj/ 下文件未计入\n' 'prune-effective'
  else
    printf '  FAIL  %-26s → 期望 0，实得 %s\n' 'prune-effective' "$n"; rc=1
  fi

  if [ "$rc" -eq 0 ]; then printf '\n自检结果: 全部通过\n'; else printf '\n自检结果: **有失败项**\n'; fi
  return "$rc"
}

# ---------------------------------------------------------------------------
case "${1:-}" in
  -h|--help|'')
    sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
    exit 2 ;;
  --self-test)
    self_test ;;
  *)
    DIR="$1"; shift
    if [ ! -d "$DIR" ]; then
      printf '错误: 目录不存在: %s\n' "${DIR}" >&2
      exit 2
    fi
    DIR=$(cd "$DIR" && pwd)
    printf '=== windows-coding-standards 语言探测 ===\n'
    printf '探测目录: %s\n\n' "${DIR}"
    probe "$DIR" "$@"
    ;;
esac
