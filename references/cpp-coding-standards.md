# C++ 编码规范（Windows 平台）

> 版本：v0.1.4（**销掉附录 D 的 9 条待实测** + 修掉两份模板的 3 个真实缺陷，**规则阈值未变**）· 2026-09-28
> （跳号说明：本次改动本应记为 v0.1.3，但 C#/.NET 侧当前正是 v0.1.3 —— 自检第 10 节要求两侧版本号可区分，故取 v0.1.4。**C++ 侧从未有过 v0.1.3**。）
> **本文件只服务 C++。** C#/.NET 侧见 `references/csharp-coding-standards.md`。
> 两套规则**互不套用** —— 隔离纪律见 §1.4，相反取值清单见 §5.6。
>
> **C++ 侧的配套文件**（各司其职，不要互相替代）：
> - `references/cpp-defect-catalog.md` —— 缺陷目录（`CPP-xx` 编号）
> - `references/cpp-naming-antipatterns.md` —— 命名反模式词典（§4.6 可接受词表的唯一权威）
> - `references/design-granularity.md` —— **跨语言**的粒度判据（臃肿 / 过度拆分，§5.4 与 §6.3 引用它）
> - `references/change-discipline.md` —— **跨语言**的变更纪律（整改不改行为 / 不为规范堆代码，§3.4 与 §9 引用它）
> - `assets/clang-format` / `assets/clang-tidy` —— 格式与检查配置模板（取值的唯一权威）

---

## 0. 问题定义：C++ 的病与 C#/.NET 恰好相反

C#/.NET 侧的病是「**规则太多、选不出来、噪音淹没信号**」，所以那边的规范作用是**收敛选择**。
C++ 侧的病不是太多，是**没有一个东西在管**：

| | C#/.NET | C++ |
|---|---|---|
| 最高权威 | Framework Design Guidelines（书）+ C# 语言规范 | **C++ Core Guidelines（免费官方文档，但明确不是标准）** |
| 该权威管不管命名 / 格式 | FDG 管命名与 API 设计 | **不管**（自述 "less concerned with … naming conventions and indentation style"） |
| 命名风格 | 单一（PascalCase，`dotnet_naming_rule` 可机器强制） | **社区无统一风格**：Google 蛇形 / Microsoft 帕斯卡 / LLVM 小驼峰 |
| 可执行规则的默认状态 | Roslyn 默认集较大 | **clang-tidy 默认集极小 —— 不显式开簇，几乎查不出东西** |
| 主要风险 | 配了不生效（假基线） | **没配 → 默认集太小 → 跑绿了什么都没证明**（假绿） |

因此本规范的工作是**拼装 + 落点**：把散在四层的规则（语言与运行时 / 领域合规 / 平台与界面 / 跨语言底座）拼成一份可执行的清单，并为每条指明**它由哪个工具、哪条命令负责**。

### 三条必须先知道的事实（均已取证，来源见附录 B）

**一、C++ Core Guidelines 不是标准，但它是本侧唯一可整篇引用的权威。**

它由 isocpp（Standard C++ Foundation）托管，Bjarne Stroustrup 与 Herb Sutter 主编，贡献方包括 CERN、Microsoft、Morgan Stanley 等。但它的 FAQ.6 白纸黑字：

> Have these guidelines been approved by the ISO C++ standards committee? … **No. These guidelines are outside the standard.**

同时它的许可声明是 **MIT-style**，明确允许 "Copying, use, modification, and creation of derivative works"。

> ⚠️ **这一条与 C# 侧相反，别把纪律搬错。** C# 侧的主要权威是**受版权保护的书**（《Framework Design Guidelines》），只能做条目索引、不得整篇复制（见那边 §7.4）。C++ 侧则可以**合法内置快照并做逐字比对**。两侧的「引文校验能不能做」结论不同，原因在此。

**二、Core Guidelines 自己声明不管命名与格式。**

原文：*"We are less concerned with low-level issues, such as naming conventions and indentation style."*

→ **C++ 侧的命名与格式没有权威文本可引。** 它们只能落到配置载体上：命名 → `.clang-tidy` 的 `readability-identifier-naming`；格式 → `.clang-format`。**没有配置，这两项在本侧等于没有规范。**

**三、C++ 社区没有统一的命名风格，且最权威的那份文档与 Windows 惯例冲突。**

- Google 风格：类型 `PascalCase`、函数与变量 `snake_case`、成员 `snake_case_`
- Microsoft 风格：类型 `PascalCase`、函数 `PascalCase`、成员 `m_camelCase`
- LLVM 风格：类型 `PascalCase`、函数与变量 `camelBack`
- **Core Guidelines `NL.10` 明确写着 "Avoid CamelCase"** —— 与 Microsoft 惯例直接冲突

→ 本侧**不存在「照官方写」这条路径**。命名必须由项目**显式选定一条路线并机器化**（§4）。

---

## 1. 权威依据与分层

### 1.1 第一层：可执行权威（唯一权威，机器执行）

`.clang-format` + `.clang-tidy` 是**唯一权威配置载体**。

规范正文里出现的任何取值（缩进宽度、列宽、命名大小写、前缀后缀、启用哪些检查），若在配置里也存在，**以配置为准，且只能有一份**。正文不写第二份副本 —— 这是本工程在 Swift 侧踩过漂移之后立的规矩（见 §7.2）。

### 1.2 第二层：文本权威（人读，用于判断与争议裁决）

| 用途 | 依据 | 可引用程度 |
|---|---|---|
| 语言与设计语义、资源管理、并发 | **C++ Core Guidelines**（isocpp） | **可整篇引用**（MIT-style），但须标注"非 ISO 标准" |
| 语言本身的语义（不是风格） | ISO C++ 标准（各版次） | 可引用，须标版次 |
| 格式与命名的实际来源 | 各企业风格指南：Google / LLVM / Microsoft / Chromium / Mozilla / WebKit | 只作**取向依据**，不逐条引用 |
| C 风格不安全构造 | **SEI CERT C++**（免费，按类别组织） | 可引用 |
| 安全关键域 | **MISRA C++:2023** / JSF AV C++ / HIC++ | 只**索引**，正文按需引用条目号 |
| 平台与工具链 | Microsoft Learn（MSVC、Windows 驱动、WHCP） | 可引用 |

**引用纪律**：引用官方原文必须标注来源与版次；企业风格指南只作取向说明、不逐字引用（各家的许可不同，逐字引用成本高、收益低）。

### 1.3 第三层：工具权威（执行者）

`clang-format`（格式） / `clang-tidy`（检查） / 编译器警告（`clang-cl`、MSVC `/W4` + `/analyze`） / CodeQL（驱动认证） 。

**分工必须清晰且不得重叠** —— 同一件事有两个执行者，就会出现"两边都报、修了一边另一边还在报"的噪音（见 §7.3）。

### 1.4 与 C#/.NET 侧的隔离（本规范最硬的边界纪律）

**两侧的规则、取值、工具、缺陷编号一律独立。** 这不是风格偏好，是因为两侧在下列每一项上都**不同或相反**：

| 维度 | C++ 侧 | C#/.NET 侧 |
|---|---|---|
| 配置文件 | `.clang-format` / `.clang-tidy` | `.editorconfig` / `Directory.Build.props` / `stylecop.json` |
| 格式化器 | `clang-format` | `dotnet format` |
| 检查器 | `clang-tidy`（`-*` 再逐簇开） | Roslyn analyzers（`CAxxxx` / `IDExxxx`） |
| 命名权威 | `.clang-tidy` 的 `readability-identifier-naming` | `.editorconfig` 的 `dotnet_naming_rule` + `IDE1006` |
| 命名风格 | **项目自决**（三条主流路线） | 单一：PascalCase 体系 |
| `case` 缩进 | `.clang-format` 的 `IndentCaseLabels` | `csharp_indent_switch_labels = false` |
| 注释语法 | Doxygen（`@brief` / `///` / `/*! */`） | XML（`<summary>` / `<param>`） |
| 编译期强制 | `-Werror` / `/WX` | `TreatWarningsAsErrors` + `EnforceCodeStyleInBuild` |
| 缺陷编号 | `CPP-xx`（见 `cpp-defect-catalog.md`） | `#xx`（见 `csharp-defect-catalog.md`） |

**硬规矩：**

1. **不得把一侧的判据、阈值、文件名、检查 ID 搬到另一侧。** 两个文件名字都带语言前缀，就是为了让误用无法通过"看起来像"发生。
2. **交付某一侧的工作时，只读该侧的正文与配置。** 混读两侧的常见后果是：给 C++ 提 `IDE1006`、给 C# 提 `readability-identifier-naming`；或把 `case` 缩进按另一侧设。
3. **唯一允许共享的是跨语言底座** —— `.editorconfig` 的 `[*]` 段（charset / 缩进宽度 / 行尾 / 去尾随空白 / 末行换行）。它是唯一一处"两侧必须一致"的地方，且它的权威来源是 EditorConfig 本身，不属任何一侧。`[*.{cs,csx}]` 段**只属 C# 侧**。
4. 判不清本次该走哪一侧时，跑 `scripts/detect_language.sh`（见 `SKILL.md`），**不要凭印象选一套**。

---

## 2. 强制等级与「可检查性」原则（元规则）

| 等级 | 含义 | 要求 |
|---|---|---|
| **MUST** | 必须遵守 | **必须给出检测命令**，且能在 CI 中判定通过 / 不通过 |
| **SHOULD** | 应当遵守 | 允许例外，但例外须在评审中说明；须注明「可 grep 定量」或「须人工评审」 |
| **MAY** | 可自由选择 | 不做检查 |

**核心判据：约束力 ≈ 可检查性。**

- 给不出检测命令的条目**不得标 MUST**，只能降 SHOULD 并注明「须人工评审」。
- **「跑过工具」不等于达标。** `clang-tidy` 只报它被启用且实现了的检查；跑过一次不代表命名、设计、注释问题已清零。交付时必须明确列出「还剩什么、为什么」。
- **本项目对「实测」的标注纪律**：本机的实测结论会明确写"已实测"并给出环境与命令；凡未经本机验证的论断一律标 `[待实测]`，汇总在附录 D。**标了 `[待实测]` 的条目在销项之前不得当作结论使用。**

> **本机的实测环境**（附录 D 里区分"已实测 / 待实测"的依据）：
> **本机的实测环境**（附录 D 里区分"已实测 / 待实测"的依据）：
> macOS，`clang++` Apple clang 21.0.0；`clang-format` / `clang-tidy` = **21.1.6**（PyPI 轮子）。
> **本机没有** `cmake` / `dotnet` / `doxygen` / MSVC `cl` / Windows SDK。
> ⇒ **编译器警告类与格式化器 / tidy 的行为类均已实测**；仍待实测的只剩需要 Windows 工具链
> 或文档核对的那几条（D7 / D8 / D10）。**换工具大版本后必须重跑附录 D。**

---

## 3. 格式：唯一权威是 `.clang-format`

### 3.1 基础风格必须显式选一个（MUST）

`clang-format` 的 `BasedOnStyle` 只有**七个合法值**（LLVM 官方文档列举，来源见附录 B）：

| 值 | 对应的风格指南 |
|---|---|
| `LLVM` | LLVM coding standards |
| `Google` | Google C++ Style Guide |
| `Chromium` | Chromium style guide |
| `Mozilla` | Mozilla style guide |
| `WebKit` | WebKit style guide |
| `Microsoft` | **Microsoft style guide（MSVC / EditorConfig 风格参考）** |
| `GNU` | GNU coding standards |

**本规范选 `Microsoft`**，理由三条：

1. 平台内一致性：Win32 / WDK / COM / MSVC 文档与模板全是帕斯卡风格，与本侧目标平台一致；
2. 混合工程成本：C++ 与 C# 共存的工程里，两套大括号与命名风格一致，评审时的认知切换成本最低；
3. 官方预设可直接用：`BasedOnStyle: Microsoft` 是 clang-format 的一等公民，不需要自造风格（自造风格的维护成本与升级风险都更高）。

> **但基础风格不够。** 预设只覆盖它自己定义的选项，且预设取值随 clang-format 版本演进。因此模板里的关键取值（缩进宽度、列宽、`IndentCaseLabels`）**必须显式写出**，不依赖预设默认 —— 否则升级 clang-format 就会静默改变格式。

### 3.2 取值纪律：跨语言项与语言特有项分开

| 类别 | 取值 | 权威来源 |
|---|---|---|
| **跨语言项**（缩进宽度、行尾、去尾随空白、末行换行、charset） | 与 C# 侧**一致** | `.editorconfig` 的 `[*]` 段 —— **唯一允许两侧共享的地方** |
| **C++ 特有项**（大括号位置、`IndentCaseLabels`、指针 / 引用对齐、`ColumnLimit` 断行策略） | 由 `.clang-format` 单独决定 | `.clang-format` —— **不得从 C# 侧的 `.editorconfig` 推导** |

把跨语言项与特有项分开登记，是为了让"哪一处必须一致、哪一处必须独立"变成可查的事实，而不是靠记忆。

### 3.3 必须改的格式项（MUST，已实测可检出）

以下四类是**无争议的不规范**（与 Swift / C# 侧同源）：

1. 一行多条语句（`;` 连接）
2. 块内压行（`if (x) { a(); b(); }` 挤在一行）
3. 关键字与花括号之间缺空格 / 该换行的大括号没换行
4. **成员（函数 / 类型 / 数据成员）之间缺分隔空行**

检测命令（`clang-format` 会报前 3 类与第 4 类）：

```bash
# 只读检查：非 0 退出即有未格式化文件
clang-format --dry-run --Werror $(git ls-files '*.cpp' '*.h' '*.hpp' '*.cc')
```

**第 4 类（成员间空行）的额外说明**：`clang-format` 通过 `SeparateDefinitionBlocks`（旧名 `EmptyLineBeforeAccessModifier` 相关项）控制，**未配置时不会强制**。因此模板里必须显式设置；若某工程决定不设，则第 4 类降为 SHOULD + 人工评审，**不得标 MUST**（这正是 Swift 侧"MUST 但无检查器 → 703 处违反"的同型教训）。

### 3.4 人工排版与工具排版同等有效

- **`clang-format -i` 不是提交前必做动作。** 钩子与 CI 只做 `--dry-run --Werror` **检查**，**禁止自动改写源码**。
- 手工断行 / 对齐必须被保留：`.clang-format` 的 `ReflowComments: false`、`AllowShortFunctionsOnASingleLine` 等不要设成激进值。
- 局部豁免用 clang-format 的原生指令（**这是 C++ 侧的载体，与 C# 侧的 `#pragma` 或 `.editorconfig` 段不同**）：

  ```cpp
  // clang-format off
  int    aligned_matrix[3][3] = { {1, 0, 0}, {0, 1, 0}, {0, 0, 1} };
  // clang-format on
  ```

- 大规模格式化**必须先获准**，且单独提交（见 §9）。
- ⚠️ **`#include` 重排是本侧唯一「格式化就会动语义」的动作。** `SortIncludes` / `IncludeBlocks` 未显式写死时，取值随预设与 clang-format 版本漂移 —— 同一份配置在不同机器上会产出不同结果，而"格式提交"承诺的是无行为变更。
  模板已取**保守值**（不自动重排 include）并把这两个开关**显式写死**。改动它们等于改行为，须按 `change-discipline.md` §1.2 归入 B 类并单独提交。

---

## 4. 命名：没有权威文本，必须自决 + 机器化

### 4.1 判据（唯一判据，不满足则改）

**遮住定义、只看调用点，陌生人能否说出这行在做什么。** 判据与语言无关，C++ 侧沿用同一条。

### 4.2 必须先选一条路线（MUST，工程级决定）

C++ 没有统一命名风格。主流三条路线：

| 路线 | 类型 | 函数 | 成员变量 | 典型使用者 |
|---|---|---|---|---|
| **Microsoft**（本规范默认） | `PascalCase` | `PascalCase` | `m_camelCase` | MSVC / Win32 / WDK / COM |
| Google | `PascalCase` | `snake_case` | `snake_case_` | 开源与大量 Linux 项目 |
| LLVM | `PascalCase` | `camelBack` | `PascalCase` | Clang / LLVM 及邻近生态 |

**本规范选 Microsoft 路线**，理由与 §3.1 同源（平台一致 + 混合工程成本）。

> ⚠️ **必须知道这一条与 Core Guidelines 冲突。** Core Guidelines `NL.10` 明确写着 *"Avoid CamelCase"*。我们仍选驼峰，理由是：`NL.10` **没有工具强制执行**（clang-tidy 无对应检查），而 Windows 生态的既有惯例与实际工程权重更高。
>
> **这是一个显式取舍，不是遗漏。** 若某工程决定改走 Google 或 LLVM 路线，只改 `.clang-tidy` 的 `readability-identifier-naming` 配置即可，**正文其余部分不受影响** —— 这正是把命名权交给配置载体、而不是写给正文的原因。

### 4.3 唯一权威是配置，不是本文件

命名的**唯一权威**是 `.clang-tidy` 里 `readability-identifier-naming` 的 `CheckOptions`。

本文件只声明**取向**（Microsoft 路线）与**判据**（§4.1），**不列出精确的 case / prefix / suffix 取值** —— 那些只在 `assets/clang-tidy` 模板里写一份。

`readability-identifier-naming` 的能力（已由 LLVM 官方文档确认，来源见附录 B）：

- **casing 取值**：`lower_case` / `UPPER_CASE` / `camelBack` / `CamelCase` / `camel_Snake_Back` / `Camel_Snake_Case` / `aNy_CasE` / `Leading_upper_snake_case`
- **几十类标识符**分别配置，各有 `Case` / `Prefix` / `Suffix` / `IgnoredRegexp` 四个选项，例如：
  `ClassCase` / `StructCase` / `EnumCase` / `EnumConstantCase` / `UnionCase` / `TypeAliasCase` / `TypedefCase` /
  `FunctionCase` / `MethodCase` / `PrivateMethodCase` / `PublicMethodCase` / `VirtualMethodCase` /
  `MemberCase` / `PrivateMemberCase` / `ProtectedMemberCase` / `PublicMemberCase` /
  `StaticConstantCase` / `GlobalConstantCase` / `ConstexprVariableCase` / `LocalVariableCase` / `ParameterCase` /
  `TemplateParameterCase` / `NamespaceCase` / `MacroDefinitionCase` / `IncludeGuardCase` …
- 另有 `DefaultCase` / `DefaultPrefix` / `DefaultSuffix` / `DefaultIgnoredRegexp` 作兜底，以及 `HungarianPrefix`（**本规范一律设为 `Off`**，见 §4.5）。
- **空配置 = 该检查等于关闭**（官方原文：*"The check only enforces style on kinds of identifiers which have been configured, so an empty config effectively disables it."*）

> **这是 C++ 侧最容易被误判成"已经检查过"的一处。** `readability-identifier-naming` 出现在 `.clang-tidy` 的 `Checks` 列表里**什么都不做** —— 它必须配 `CheckOptions`。只启检查不配选项，等于没查。

### 4.4 检测命令

```bash
# 需要 compile_commands.json（CMake: -DCMAKE_EXPORT_COMPILE_COMMANDS=ON）
clang-tidy -checks='-*,readability-identifier-naming' src/*.cpp
```

### 4.5 三类「真缺陷」（与 C# 侧同源，但载体不同）

| 类别 | 例子 | 本侧处理 |
|---|---|---|
| 生僻英文词 | `reify`、`thunk`、`amortize` | 人工评审（无工具） |
| 自造缩写与单字母 | `aniDur`、`sz`、`l`、`r`、`w` | 部分可机器化（`readability-identifier-length`，**默认关闭**） |
| 对象或返回值无从判断 | `handle`、`data`、`process()` 无宾语 | 人工评审 |

**匈牙利前缀一律禁止**：`strName` / `pFoo` / `bBusy` / `g_nWheels`。Core Guidelines `NL.5`（"Don't encode type information in names"）支持这一条。→ `readability-identifier-naming` 的 `HungarianPrefix` 保持 `Off`。

### 4.6 明确可以接受（不得要求重命名）

与 C# 侧同源：**常用词与高频缩写明确可以接受**，不得因"不眼熟"要求重命名。典型误报：

- `normalize`、`perform`、`enumerate` —— 常用词
- `buf`、`ptr`、`impl`、`cfg`、`ctx`、`len`、`idx`、`argc`、`iter` —— **C++ 生态高频缩写**
- 循环下标 `i` / `j` / `k`、模板参数 `T` —— **Core Guidelines `NL.7` 明确支持**：名字长度约与作用域长度成正比
- `m_` / `g_` 前缀 —— **不是缺陷**，它编码的是**作用域**（成员 / 全局）而非类型，是 §4.2 路线的一部分

> **可接受词表的唯一权威是 `cpp-naming-antipatterns.md` §0，不是 C# 侧的表。**
> 两侧的词表**必须独立** —— C# 侧的表里没有 `buf` / `ptr` / `impl` / `argc` 这些 C++ 生态缩写，拿它来筛 C++ 命名会漏掉大量正当写法（并反之误判）。
>
> **反例警告**：把常用词当缺陷，会制造大量无意义重命名与 diff 噪音。这一条在 Swift 侧付过代价。

**反模式清单与七条自检测试见 `cpp-naming-antipatterns.md`** —— 那是"什么样的名字必须改"的唯一权威，本文件只声明取向。

---

## 5. 语言与设计约束

### 5.1 编译期可强制（MUST，**本机已实测**）

以下条目由编译器警告覆盖，**已在本机用 Apple clang 21.0.0 实测**（夹具与结果见 §5.5）：

| # | 约束 | 检测开关 | 实测结论 |
|---|---|---|---|
| 1 | 多态基类必须有虚析构 | `-Wnon-virtual-dtor` | ✅ 报出 |
| 2 | 禁止 C 风格转换 | `-Wold-style-cast` | ✅ 报出 |
| 3 | 禁止变量遮蔽 | `-Wshadow` | ✅ 报出 |
| 4 | 禁止隐式窄化转换 | `-Wconversion` | ✅ 报出（但见下方警告） |
| 5 | 函数外多余分号 | `-Wextra-semi` | ✅ 报出 |
| 6 | 未使用变量 | `-Wall -Wextra` | ✅ 报出 |

**两条实测得出的重要边界（容易误判，必须记住）：**

1. **`-Wconversion` 会被显式 C 风格转换"绕过"。**
   实测：`int a = x;`（`x` 为 `double`）→ 报 `-Wfloat-conversion`；`int b = (int)x;` → **不报**。
   → 所以「禁止 C 风格转换」（`-Wold-style-cast`）与「禁止隐式窄化」（`-Wconversion`）**必须同时开**，只开一个会留缺口。
2. **`-Wall -Wextra` 不包含下列警告。** 实测基线只报了 `unused variable`，加严格集后才报出非虚析构、C 风格转换、变量遮蔽。
   → **只用 `-Wall -Wextra` 就宣称"检查过了"，是本侧最典型的假绿。**

强制命令（**推荐集**）：

```bash
clang++ -std=c++20 -Wall -Wextra -Wconversion -Wshadow -Wold-style-cast \
        -Wnon-virtual-dtor -Wextra-semi -Wpedantic -Werror
```

- **`-Werror` 必须开**，否则警告只是噪音。已实测：加 `-Werror` 后警告使编译失败（exit 1）。
- **标准版本必须显式指定**（已实测本机支持 `c++17` / `c++20` / `c++23`），不要依赖编译器默认 —— MSVC 与 clang-cl 的默认值不同。
- MSVC / clang-cl 侧的对应物是 `/W4` + `/WX`；**两套开关不是同一组**，不要互抄（见 §5.6）。

**静态分析**（本机已实测可用）：

```bash
clang++ --analyze -Xanalyzer -analyzer-output=text src/foo.cpp
```

实测能查出内存泄漏（`unix.Malloc`：*Potential leak of memory pointed to by 'p'*）。

### 5.2 只能靠 clang-tidy 查的（编译器不管）

以下条目**已实测确认 clang 编译器不报**，必须由 clang-tidy 覆盖：

| 约束 | clang-tidy 检查 | 备注 |
|---|---|---|
| 禁止非 const 全局变量 | `cppcoreguidelines-avoid-non-const-global-variables` | 实测 `int g_counter = 0;` 无任何编译器警告 |
| 无作用域枚举改 `enum class` | `modernize-use-enum-class` / `cppcoreguidelines-*` | 实测 `enum Color {...}` 无警告 |
| 禁止 `reinterpret_cast` / `const_cast` | `cppcoreguidelines-pro-type-reinterpret-cast`、`-pro-type-const-cast` | |
| 禁止 C 风格数组 | `cppcoreguidelines-avoid-c-arrays` | **误报率较高**，视工程取舍 |
| 禁止魔法数字 | `readability-magic-numbers` | 与 C# 侧同源问题，但阈值须在配置里定 |
| 函数体量 / 认知复杂度 | `readability-function-size`、`readability-function-cognitive-complexity` | 见 §5.4 |
| 必须 `override` / `final` | `modernize-use-override` | |
| 使用 `nullptr` 替代 `NULL` / `0` | `modernize-use-nullptr` | |
| 参数按值 / 按 `const&` 传递 | `performance-unnecessary-value-param` | 有误报，须显式禁个例 |
| 隐式 bool 转换 | `readability-implicit-bool-conversion` | **默认关闭**，开了噪音大 |

**启用策略见 §7.3** —— 这一节的检查**默认不启用**，必须显式开簇。

### 5.3 SHOULD（须人工评审或定量）

- 优先 `constexpr` / `const`，可变性应是例外（Core Guidelines `P.10`、`Con.*`）
- 优先值语义与 RAII，避免裸 `new` / `delete`（`R.*`、`C.10`）
- 优先返回结构体而非输出参数（`F.20`、`F.21`）
- 单参数构造函数标 `explicit`（`C.46`）
- 纯函数优先（`F.8`）
- 头文件必须有 include guard 或 `#pragma once`，且全工程统一选一种
- 命名空间别名与 `using` 的作用域尽量小；**头文件里禁止 `using namespace`**

### 5.4 体量上限（MUST 部分 / SHOULD 部分必须分清）

| 项 | 阈值 | 可检查性 |
|---|---|---|
| 认知复杂度 | 25 | **机器可查**：`readability-function-cognitive-complexity`（**默认关闭**，须显式开） |
| 函数行数 | 60 | `readability-function-size` 的 `LineThreshold`（**默认关闭**） |
| 参数个数 | 6 | `readability-function-size` 的 `ParameterThreshold` |
| 嵌套深度 | 3 | `readability-function-size` 的 `NestingThreshold` |
| 类型行数 | 300 | **无工具** → SHOULD + 人工评审 |

**阈值只写在 `.clang-tidy` 模板里**，本表是"哪一项由谁检查"的索引，数值以模板为准。

> #### ⚠️ 超过阈值 ≠ 必须拆（**本规范最容易被执行错的一处**）
>
> **体量上限是"提示需要检查"，不是"必须拆"。** 触发后必须过一遍 `design-granularity.md` §3.2 的提问清单：
>
> - **能说出独立的变化原因** → 按该原因拆，并把原因写进提交信息；
> - **说不出** → **不拆**，改为在类型 / 函数头部写明职责与不变式（§6.3）。
>
> 为把行数压到阈值以下而机械切割，只会把"难以理解的大段"变成"难以理解的多段"。
>
> **「拆解过细」与「臃肿」是同一个病的两个方向，判据与检测见 `design-granularity.md`** —— 那份文件同时给出拆分的正当理由（§3.3）、禁止拆的信号（§3.4）、以及碎片化的候选筛选命令（§6.1）。**本侧没有内置规则能报"拆得太碎"**，它只能靠那份判据 + 人工评审。

### 5.5 领域规则：只引条目，不重写

C++ Core Guidelines 的定位是索引，不是抄写。按需引用条目号：

| 主题 | 条目 |
|---|---|
| 接口设计 | `I.1`–`I.27` |
| 函数（单一职责、参数传递、返回值） | `F.1`–`F.60` |
| 类与继承（虚析构、`explicit`、切片） | `C.35`、`C.46`、`C.67`、`C.128` |
| 资源管理（RAII、所有权） | `R.1`–`R.13` |
| 错误处理 | `E.1`–`E.31` |
| 常量与不可变性 | `Con.1`–`Con.4` |
| 并发 | `CP.1`–`CP.44` |
| 名字与布局 | `NL.1`–`NL.26` |

**注意 `NL` 节的定位**：它是"建议"，且与工具无强制对应。`NL.4`（一致缩进）、`NL.8`（一致命名风格）、`NL.20`（一行一条语句）、`NL.21`（一次声明一个名字）与 §3.3 的必须改项重合；`NL.10`（Avoid CamelCase）**已被本规范显式推翻**（§4.2）。

### 5.6 **与 C#/.NET 侧相反的取值（隔离清单）**

凡下列条目，**两侧禁止互抄**：

| 项 | C++ 侧 | C#/.NET 侧 |
|---|---|---|
| `case` 缩进 | `.clang-format` 的 `IndentCaseLabels`（Microsoft 预设下缩进） | `csharp_indent_switch_labels = false`（**不缩进**） |
| 成员变量命名 | `m_camelCase` | `_camelCase` |
| 静态字段 | 无固定前缀（按 §4.2 路线） | `s_camelCase` |
| 接口命名 | 无 `I` 前缀惯例 | `I` + PascalCase |
| 文档注释 | Doxygen（`@brief` / `@param`） | XML（`<summary>` / `<param>`） |
| 编译警告开关 | `-Wall -Wextra -Wconversion …` / `/W4` | `AnalysisLevel` + `TreatWarningsAsErrors` |
| 格式化器 | `clang-format` | `dotnet format` |
| 检查 ID 前缀 | `bugprone-` / `cppcoreguidelines-` / `readability-` / `performance-` / `modernize-` / `cert-` | `CAxxxx` / `IDExxxx` / `SAxxxx` |
| 工厂方法 | 无统一惯例（标准库惯例 `make_unique` / `make_shared`） | `Create` |
| 非空断言 / 可空性 | 无语言级可空性（靠 `gsl::not_null` 等） | `<Nullable>enable</Nullable>` |
| 一次性资源释放 | RAII（析构函数） | `IDisposable` + `using` |

---

## 6. 注释与文档

### 6.1 注释判据（Core Guidelines `NL.1`–`NL.3`）

- **`NL.1`**：不要在注释里说代码已经说清楚的事 → **同义复述是缺陷**（同 C# 侧）。
- **`NL.2`**：在注释里陈述**意图**。
- **`NL.3`**：注释要精炼；注释会过期，代码不会。

应用到 C++ 侧的两条具体判据：

1. **注释该说明"为什么"，不说明"是什么"。** 说明约束、所有权、线程安全、单位、前置条件 —— 这些代码表达不了。
2. **注释掉的代码必须删除**（版本控制里已有历史）。这是一条可 grep 的定量项：

   ```bash
   # 连续 3 行以上的注释代码块（候选，须人工确认）
   grep -rnE '^\s*//\s*(if|for|while|return|std::|[A-Za-z_]+\(.*\);)' --include='*.cpp' --include='*.h' . | head
   ```

### 6.2 文档注释载体：Doxygen（**与 C# 侧的 XML 完全不同**）

| | C++ 侧 | C# 侧 |
|---|---|---|
| 语法 | Doxygen：`/** @brief … */` / `/// @param` / `/*! … */` | XML：`/// <summary>` / `<param>` |
| 强制手段 | 无编译器级开关（`-Wdocumentation` 只查**格式一致性**，不查缺失） | `CS1591` + `GenerateDocumentationFile` |

```cpp
/// @brief 计算给定温度下的饱和蒸汽压。
/// @param temperatureC 摄氏度；必须 >= -273.15。
/// @return 饱和蒸汽压，单位 kPa。
/// @note 非线程安全。
double SaturatedVaporPressure(double temperatureC);
```

**关键事实（已实测，见附录 D 的 D7）**：C++ **没有**与 C# `CS1591` 对等的"公开成员必须有文档"的编译器开关。
实测夹具三例：注释完好 → 0 报；`@param` 名写错 → 报 `parameter 'wrongName' not found in the function declaration`；
**完全没有注释的函数 → 0 报**。⇒ `-Wdocumentation` 只管**已写注释的格式**，**不管注释缺失**。

→ 因此「每个公开成员必须有文档」在本侧**只能是 SHOULD + 人工评审**，除非引入额外工具（如 `doxygen` 的 `WARN_IF_UNDOCUMENTED`，见附录 D）。**不得标 MUST** —— 标了也没有执行者，正是 Swift 侧 703 处漏检的同型错误。

### 6.3 类型级设计意图（SHOULD，人工评审）

**这段针对的是"这个类为什么这样拆、和谁协作"这类无法从成员签名推出的信息。**

> 判据与理由见 `design-granularity.md` §5。**拆解本身会增加读者的认知负担，唯一补偿办法就是把设计意图写下来** —— 成员级注释再齐全，也回答不了"为什么有这个类、它和旁边那个类的区别是什么"。

要求（与 C# 侧同源，载体不同）：每个对外类型在其声明处（头文件）有一段说明，回答：

1. 这个类型**为何存在**（它负责的单一职责是什么）
2. 它**与谁协作**（依赖谁、被谁使用、生命周期由谁持有）
3. 它**不负责什么**（边界，防止职责蔓延）

```cpp
/// @brief 管理设备句柄的 RAII 包装。
///
/// 职责：持有 HANDLE 并在析构时关闭；提供原始的句柄访问。
/// 协作：由 DeviceSession 独占持有，不跨线程共享。
/// 不负责：不做句柄有效性校验，也不重试失败的操作 —— 那是 DeviceSession 的职责。
class DeviceHandle { /* … */ };
```

**为什么这条重要**：成员级文档再齐全，也回答不了"为什么有这个类"。设计逻辑难懂的根因在这里，不在注释数量。

---

## 7. 工具链与四道闸门

### 7.1 闸门（C++ 版）

| 闸门 | 机制 | 命令 | 本机可跑 |
|---|---|---|---|
| **编辑期** | 编辑器按 `.editorconfig` / `.clang-format` 即时格式化 | 编辑器行为，无命令 | — |
| **构建期** | 编译器警告即错误 | `clang++ … -Werror`（§5.1） | ✅ **已实测** |
| **静态分析期** | clang-tidy + Clang Static Analyzer | `clang-tidy` / `clang++ --analyze` | ⚠️ analyzer ✅ / tidy ✗（无该工具） |
| **格式期** | 只读检查，不改源码 | `clang-format --dry-run --Werror` | ✓ 已实测（21.1.6：未格式化 exit 1 / 已格式化 exit 0） |

**原则：能压在编译期的，不依赖钩子。** 与 C# 侧的 `EnforceCodeStyleInBuild` + `TreatWarningsAsErrors` 同源 —— 让"跑不过就提交不了"发生在构建阶段，而不是靠人记得跑脚本。

**CI 必跑**：

```bash
# 1) 构建期闸门
clang++ -std=c++20 -Wall -Wextra -Wconversion -Wshadow -Wold-style-cast \
        -Wnon-virtual-dtor -Wextra-semi -Wpedantic -Werror  <目标>

# 2) 格式期闸门（只读）
clang-format --dry-run --Werror $(git ls-files '*.cpp' '*.h')

# 3) 静态分析
clang-tidy -p build/ $(git ls-files '*.cpp')
```

### 7.2 配置联动（改一处就要查其余）

| 事实 | 出现位置 | 纪律 |
|---|---|---|
| 缩进宽度 / 行尾 / charset | `.editorconfig` 的 `[*]` 段 + `.clang-format` | **必须一致**；`[*]` 段是权威 |
| C++ 格式取值 | `.clang-format`（唯一） | 正文不复制 |
| 命名 case / prefix / suffix | `.clang-tidy` 的 `CheckOptions`（唯一） | 正文不复制 |
| 启用的检查簇与禁用清单 | `.clang-tidy` 的 `Checks`（唯一） | 正文不复制 |
| 体量阈值 | `.clang-tidy` 的 `CheckOptions` | 正文只列"谁检查"，不列数值 |

**同一份事实只允许有一个出处**，其余位置一律引用。

### 7.3 clang-tidy 的启用策略：默认集太小是最大陷阱

**事实（已实测，见附录 D 的 D4）**：`clang-tidy` 的默认检查集**远小于**按簇全开时的规模 ——
出厂默认启用 **134** 条，本模板的簇配置启用 **432** 条，差额全落在
`cppcoreguidelines-*` / `misc-*` / `modernize-*` / `performance-*` / `readability-*`
这些**必须显式声明才会启用**的簇上。不显式声明 `Checks`，跑绿**证明不了什么**。

**流行做法（业界大面积采用，模式一致）**：先 `-*` 关掉全部，再逐簇打开，然后**逐个禁用误报项**。形如：

```yaml
Checks: >
  -*,
  bugprone-*,
  cppcoreguidelines-*,
  cert-*,
  performance-*,
  modernize-*,
  readability-*,
  -cppcoreguidelines-avoid-magic-numbers,   # 误报高，按工程取舍
  -readability-magic-numbers,
  -cppcoreguidelines-owning-memory,          # 与既有代码风格冲突
  -modernize-use-trailing-return-type        # 团队取舍
```

**这就是 C++ 侧的「收敛选择」** —— 与 C# 侧"在数百条 CA/IDE 规则里选"是同一个动作，只是这边的默认集更小、所以更容易漏。

**本规范的启用策略（三档推进，与 §9 迁移一致）：**

| 档 | 检查簇 | 强度 |
|---|---|---|
| 一档：正确性与安全 | `bugprone-*`、`clang-analyzer-*`、`cert-*`、`cppcoreguidelines-*`（限内存与所有权） | 进 CI，`WarningsAsErrors` |
| 二档：现代写法与性能 | `modernize-*`、`performance-*` | 进 CI，警告级 |
| 三档：可读性与风格 | `readability-*`、`llvm-*`（如采用 LLVM 风格） | 初期 `suggestion`，稳定后再升 |

**禁用清单必须落盘在 `.clang-tidy` 里并写明理由**，不得只在 CI 脚本里用命令行临时排除 —— 否则配置漂移无法审计。

### 7.4 来源快照的版权边界（**与 C# 侧相反**）

| | C#/.NET 侧 | C++ 侧 |
|---|---|---|
| 主要权威的载体 | 书（《Framework Design Guidelines》）+ Learn 各页 | **C++ Core Guidelines，MIT-style 许可的公开文档** |
| 能否内置快照 | **不能**（版权） | **能**（许可明确允许 copy / modify / derivative works） |
| 能否做逐字引文校验 | 不能，只能降到"条目存在性 + 链接可达性" | **能** |

**因此 C++ 侧将来可以做 C# 侧做不到的事**：内置 Core Guidelines 快照 + 逐字引文校验脚本。

> ⚠️ 但**这件事必须先把边界写死再动手**：内置快照须保留原许可声明与出处；企业风格指南（Google / LLVM / Microsoft / Chromium / Mozilla / WebKit）的许可是**各自独立**的，不随 Core Guidelines 一起获得授权，**不得一并快照**。

---

## 8. 领域合规（可选层：安全关键域才启用）

### 8.1 安全关键域的标准选择

| 标准 | 行业 | 形态 | 规则量 |
|---|---|---|---|
| **MISRA C++:2023** | 汽车（ISO 26262）、工业（IEC 61508） | 付费 PDF | 175+ 规则 |
| **SEI CERT C++** | 航空、国防、政府 | **免费**、按类别（STR / INT / MEM …） | 90+ 规则 |
| JSF AV C++ | 老一代 DO-178C 航空 | 免费 PDF | 220+ 规则 |
| HIC++ 4.0 | 高完整性 | clang-tidy 有 `hicpp-*` 簇 | — |

**一条必须说准的版本事实（常见误用）**：**`MISRA C++:2023` 已吸收并取代 `AUTOSAR C++14`。**

2019 年 1 月 MISRA 与 AUTOSAR 宣布合并，2023 年 10 月发布的 MISRA C++:2023 整合了 AUTOSAR C++14 的规则。许多工具仍以 "AUTOSAR C++14" 作为**兼容别名**暴露检查集 —— **新项目应引 MISRA，而不是 AUTOSAR C++14**。

**工具覆盖的现实**：clang-tidy 的 `misra-*` / `cert-*` / `autosar-*` / `cppcoreguidelines-*` 都是**部分实现**，须与标准全文核对；商业工具（Helix QAC / Coverity / Parasoft / PVS-Studio / LDRA / Axivion）覆盖更全。

**偏离程序（deviation procedure）是合规的一部分**：MISRA 要求每个偏离或每类偏离都**获得签核**，并在项目结束时出具合规报告。**"我们规则没全过但发了"不算合规。**

### 8.2 Windows 驱动：WHCP 的 CodeQL + DVL（**流程强制，非零违规强制**）

驱动侧是**认证级要求**，与普通应用的"我们内部有规范"不同：

- **WHCP 强制跑 CodeQL，并产出 DVL（Driver Verification Log）**。DVL 不含源码，只汇总静态分析结果。
- CodeQL 的查询集分三档：

  | 套件 | 含义 | 对认证的影响 |
  |---|---|---|
  | `recommended.qls` | 面向常见驱动与 C/C++ 缺陷的宽集 | 建议默认跑（26H1 起与 `mustrun` 相同） |
  | `mustrun.qls` | **必须运行**的检查 | **失败不会**让 Static Tools Logo test 失败（可能有误报）；但**没有结果的 DVL 会失败** |
  | `mustfix.qls` | 报告**必须修复**问题的子集 | **失败会让 Static Tools Logo test 失败** |

> ⚠️ **别把这条写成"必须零告警"。** 正确的口径是：**`mustfix` 必须通过；`mustrun` 必须跑出结果（不要求全部通过）**。写错会让团队把大量误报当成阻塞项，或反过来忽略 mustfix。

- **CodeQL CLI 版本与要认证的 Windows 版本有对应矩阵**（WHCP_21H2 / 22H2 / 24H2 / 25H2 / 26H1 各对应不同的 CLI 与 pack 版本）。跑错组合会导致 DVL 不被接受 —— **版本矩阵必须查当次文档，不得凭记忆**（来源见附录 B）。
- 历史上驱动的 VS Code Analysis 与 SDV 均有变动/退役（`[待实测]`，见附录 D）；**DVL 仍要求汇总 Code Analysis 与 SDV 的日志的说法在新旧文档间不一致**，实操以当前 WDK 版的《Creating a driver verification log》为准。

---

## 9. 迁移纪律

> **判据不在本节，在 `change-discipline.md`**（跨语言共享）。本节只写 C++ 侧的**流程与顺序**。
> 那两条硬约束是：**整改不得改变原有行为**（接入之前）、**不得为满足规则而增加代码**（接入之后）。

- **格式迁移是无行为变更的提交。** 不新增测试，但每次提交后必须跑受影响的测试与构建。
- **重命名与接口调整是有行为边界影响的变更。** 重命名公开 API **先写 ADR**，再做完整回归。
- **严禁把格式修改与逻辑修改放进同一个提交。**
- **改之前先给每处改动定级**（`change-discipline.md` §1.2 的 A / B / C），并按级决定"能否批量、要不要测试、要不要先告知用户"。
  C++ 侧最容易踩的三处：加 `explicit`（调用方的隐式转换不再编译）、加虚析构（**ABI 变更**）、加 `noexcept`（改变 `terminate` 行为与容器的 move 选择）。
- ⚠️ **`clang-format` 重排 `#include` 是唯一会动语义的格式化动作** —— 宏定义顺序、自包含性、PCH 交互都受它影响。
  模板已取保守值（不自动重排）并把 `SortIncludes` / `IncludeBlocks` 显式写死；**改这两个开关等于改行为，须单独提交**（`change-discipline.md` §1.4.1）。
- **存量工程不要一次全开检查。** 按 §7.3 的三档推进：先正确性与安全，现代写法与性能次之，可读性最后，且样式类初期限定 `suggestion`。
- **禁止为提高通过率而放宽检查。** 放宽必须写进本文件附录 C 的变更记录。
- **不得为消除 clang-tidy / 编译器的警告而加代码。** 典型反例：给 `switch` 补 `default:` 掩盖"漏了 case"的警告、成片加 `// NOLINT`。
  判据见 `change-discipline.md` §2.1：**新增的每一行必须被某条规则指名要求。**
- **禁止「顺手清理」**：死代码分支、未使用参数、"多余"的防御性检查、注释掉的旧实现 —— 它们可能是刻意的（ABI 占位、平台桩、上游接口占位）。清理属 C 类，须单独提交。
- **交付的三件东西**（`change-discipline.md` §1.7）：**前后数字** + **剩余清单（还有哪些没改、为什么）** + **可复现命令**；每处改动挂一个 `CPP-nn` 编号，挂不上的说明本来就不该改。
- 引入 `.clang-format` 到既有工程的顺序：**先只读采基线（数出会改多少文件）→ 单独一次全仓格式化提交 → 再开钩子/CI 检查**。反序做会让格式 diff 与逻辑变更混在一起，评审失效。
- 大范围整改前留**回滚点**（干净分支或 tag）。

---

## 附录 A：提交前自检清单（C++ 侧）

1. 本次改动的文件**全部**是 C/C++ 吗？有 `.cs` 混进来就说明该分两次交付（两侧规则不同）。
2. `clang++ … -Werror` 干净（用 §5.1 的推荐集，不是只有 `-Wall -Wextra`）。
3. `clang-format --dry-run --Werror` 无输出。
4. `clang-tidy` 用的是工程自己的 `.clang-tidy`（**确认 `Checks` 不是空、`CheckOptions` 不是空的**）。
5. 改过的类型有 §6.3 的类型级说明（若该类型是对外接口）。
6. 注释**没有复述代码**（§6.1）。
7. **主动确认检查器真的在工作**：故意留一处已知违规，看它是否报出来。不报 = 配置无效，本次结论作废。
8. 交付说明里列出**还剩什么、为什么**（未启用的检查簇、误报豁免、人工评审项）。
9. 每处改动定过级（A / B / C）吗？C 类的单独提交与回归测试在哪？（`change-discipline.md` §1.2）
10. 本次净增行数是多少？显著为正的话，逐条对过 `change-discipline.md` §2.2 吗？（`git diff --numstat`）

## 附录 B：来源入口（取证日期 2026-09-28）

| 主题 | 来源 |
|---|---|
| C++ Core Guidelines（正文、FAQ、许可） | `github.com/isocpp/CppCoreGuidelines` · `isocpp.github.io/cppcoreguidelines/cppcoreguidelines`<br>关键条目：FAQ.6（不是 ISO 标准）、许可声明（MIT-style）、`NL.1`–`NL.26` |
| Core Guidelines 章节与规则编号体系 | 同上；`In` / `P` / `I` / `F` / `C` / `Enum` / `R` / `ES` / `Per` / `CP` / `E` / `Con` / `T` / `CPL` / `SF` / `SL` + 支撑节 `A` / `NR` / `RF` / `Pro` / `GSL` / `NL` |
| `clang-format` 的 `BasedOnStyle` 七个合法值 | LLVM《Clang-Format Style Options》 |
| `clang-tidy` 检查簇全表 | LLVM《Clang-Tidy》checks 索引 |
| `readability-identifier-naming` 的 case/prefix/suffix 与"空配置即关闭" | LLVM《clang-tidy - readability-identifier-naming》 |
| MISRA C++:2023 取代 AUTOSAR C++14 | MISRA 与 AUTOSAR 2019 合并公告；MISRA C++:2023（2023-10） |
| WHCP 的 CodeQL 三套件与 DVL | Microsoft Learn《CodeQL Queries and Suites for Windows Driver Testing》、《How to create a driver verification log》 |

## 附录 C：变更记录

| 版本 | 日期 | 变更 |
|---|---|---|
| v0.1.0 | 2026-09-28 | 首稿。建立权威分层、格式与命名的配置载体、编译期约束（本机实测）、clang-tidy 启用策略、领域合规层，以及 §1.4 / §5.6 的隔离清单。 |
| v0.1.1 | 2026-09-28 | **阈值未变**：① 新增跨语言配套文件引用 `change-discipline.md`，§9 迁移纪律由"只写流程"改为"流程 + 判据指针"，并补 C++ 侧三处最易踩的行为变更（`explicit` / 虚析构 ABI / `noexcept`）、"不得为消警告加代码"、"禁止顺手清理"与交付三件东西；② §3.4 补 `#include` 重排是唯一有语义风险的格式化动作，模板已把 `SortIncludes` / `IncludeBlocks` 显式写死；③ 附录 A 补两条清单（改动定级、净增行数）；④ 附录 D 新增 D11。 |
| v0.1.2 | 2026-09-28 | **阈值未变**：修 D11 的复验命令 —— 原写成 `grep -E 'SortIncludes[|]IncludeBlocks'`，在 ERE 里 `[|]` 是字符类不是交替，该命令**永远零命中且 exit 1**（已实测），属"以输出为空冒充核对过"的假绿。改为 `grep -e SortIncludes -e IncludeBlocks`（避开 Markdown 表格单元里的竖线转义问题），并就地加反例说明。同类写法已由 `scripts/verify_consistency.sh` 第 16 节机械拦截。 |
| v0.1.4 | 2026-09-28 | **规则与阈值均未变，销项与修缺陷**（本应记 v0.1.3，为与 C#/.NET 侧当前版本区分而取 v0.1.4）：把 `clang-format` / `clang-tidy` 补到 **21.1.6**（PyPI 轮子，三平台齐全）后逐条实测，**附录 D 的 11 条里 9 条已销**（D1–D6、D7、D9、D11；只剩 D8 需 Doxygen、D10 需查文档）。**过程中查出并修掉两份模板的 3 个真实缺陷**：① `assets/clang-format` 误用 `.editorconfig` 的键名 `EndOfLine`（clang-format 正确键是 `LineEnding`）→ 后果是 clang-format **报 unknown key 并拒绝读整个文件**，模板里一条都不生效；② `assets/clang-tidy` 的 `Checks` 写成折叠块标量 `>`，其中 `#` 不是注释而是内容 → 注释被粘进紧随的禁用项，**14 条禁用里废掉 10 条**，改为 YAML 列表后逐条生效；③ `HeaderGuardCase` 与全局 `HungarianPrefix` 两个键名在 21.1.6 **不存在**（会被静默忽略）。另补结论：`-Wdocumentation` 已实测只管注释格式不管缺失；`clang-tidy` 的 PyPI 构建**不含 misra 检查**（§8 的 MISRA 合规不能靠它机械化）。自检新增**第 17 节**：静态拦上述两类模板陷阱，并在有工具时**做真验证**（无工具则记 WARN，不记 PASS）；同日晚再补**第 18 节**（自检脚本自身的契约：退出码可达性、参数拒绝、自述节数一致 —— 不涉规则取值，故本版本号不变）。 |

## 附录 D：待实测清单（在有 `clang-format` / `clang-tidy` 的机器上逐条验证并把结论写回正文）

> **本机的实测边界**（2026-09-28 更新）：`clang++` = Apple clang 21.0.0；
> **`clang-format` 与 `clang-tidy` 已补齐**（PyPI 轮子，固定 **21.1.6**，与 `.clang-format` /
> `.clang-tidy` 模板编写时对齐）；仍**没有** `cmake` / `dotnet` / `doxygen` / MSVC `cl` / Windows SDK。
>
> ⚠️ **工具的取用方式本身是个知识点**：`clang-format` 与 `clang-tidy` 都有 PyPI 轮子，
> 且 **win_amd64 / macosx / manylinux 三平台齐全** —— 所以"验证 clang 工具的行为"**不需要**
> 先装一整份 LLVM，也不需要一台特定平台的机器。装上后**必须记录版本号**：
> 下面的结论只对 **21.1.6** 成立，换大版本要重跑。

**已实测 · 编译器警告类（Apple clang 21.0.0）**

| # | 结论 | 复验命令 |
|---|---|---|
| 1 | `-Wnon-virtual-dtor` / `-Wold-style-cast` / `-Wshadow` / `-Wconversion` / `-Wextra-semi` 均生效 | §5.5 夹具 + §5.1 命令 |
| 2 | `-Wall -Wextra` **不含**上述多数警告 | 同上，对比开 / 不开严格集 |
| 3 | 显式 C 风格转换**绕过** `-Wconversion` | `int b = (int)x;`（`x` 为 `double`）编译无警告 |
| 4 | 非 const 全局变量、无作用域枚举**无编译器警告** | 同上夹具 |
| 5 | `-Werror` 使警告变硬失败（exit 1） | 同上 |
| 6 | `clang++ --analyze` 可用，能报内存泄漏 | `clang++ --analyze -Xanalyzer -analyzer-output=text leak.cpp` |
| 7 | 本机支持 `-std=c++17/20/23` | `clang++ -std=c++XX -fsyntax-only -x c++ /dev/null` |

**已实测 · 格式化器与 tidy（clang-format / clang-tidy 21.1.6）**

| # | 结论（**这四条直接改了模板的内容**） |
|---|---|
| 1 | **`EndOfLine` 不是 clang-format 的键**（正确名是 `LineEnding`）。写错会让 clang-format 报 `unknown key` 并**拒绝读取整个 `.clang-format`**（exit 1）—— 模板里**一条配置都不生效**。原 `assets/clang-format` 被判为不可读，已修。 |
| 2 | `Checks` 写成折叠块标量（`Checks: >`）时，**`#` 不是注释而是内容** → 写在禁用项前的注释会被粘进该禁用项，使**那条禁用静默失效**。原 `assets/clang-tidy` 的 14 条禁用里**废掉 10 条**；改成 YAML 列表后 14 条逐条生效（对照实验：`--list-checks` 下 14/14 确认未启用）。 |
| 3 | `CheckOptions` 的两个键名在 21.1.6 **不存在**（`HeaderGuardCase`、全局 `HungarianPrefix`），会被**静默忽略**。include guard 由 `MacroDefinitionCase` 一并管（实测 `#ifndef bad_guard_h` 报宏定义命名违规）；`*HungarianPrefix` 是 26 个按种类的键，默认已是 `Off`。 |
| 4 | 命名规则**确实会报**（实测：函数 / 局部变量 / 类 / 私有成员四处违规全部报出）⇒ §4 的"自决并机械化"路线在工具层是成立的。 |

**待实测**

| # | 待验论断 | 状态 | 验证命令 / 结论 |
|---|---|---|---|
| D1 | `BasedOnStyle: Microsoft` 的实际预设取值 | **已实测** | 21.1.6：`IndentWidth=4` / `ColumnLimit=120` / `IndentCaseLabels=false` / `BreakBeforeBraces=`**`Custom`** / `PointerAlignment=Right` / `AccessModifierOffset=-2` / `AllowShortFunctionsOnASingleLine=None`。⇒ 模板在 `BreakBeforeBraces`（取 `Allman`）、`AccessModifierOffset`（取 `-4`）、`IndentCaseLabels`（取 `true`）三处**偏离预设**，已在模板内注明 |
| D2 | `clang-format --dry-run --Werror` 在未格式化文件上是否非 0 退出 | **已实测** | 是。未格式化文件 `exit=1`，同一文件格式化后 `exit=0` |
| D3 | `SeparateDefinitionBlocks` 是否强制成员间空行 | **已实测** | 21.1.6 下 `Always` 生效：两个紧贴的成员函数之间被插入空行，`private:` 之前也加了。**不需要降级为人工评审** |
| D4 | `clang-tidy` 默认检查集的精确边界 | **已实测** | 出厂默认启用 **134** 条；本模板的簇配置启用 **432** 条。差别全在 `cppcoreguidelines-*` / `misc-*` / `modernize-*` / `performance-*` / `readability-*` 这些**必须显式开**的簇上 ⇒ "不写真证明不了什么"成立 |
| D5 | `readability-identifier-naming` 空 `CheckOptions` 时是否真的不报 | **已实测** | 是，**0 条**（同一夹具在本模板配置下报 **4 条**）。⇒ 这条检查"启用了但没配 = 完全没查" |
| D6 | `readability-function-size` / `-cognitive-complexity` 的阈值键名与默认值 | **已实测** | 键名全部被接受。**关键发现：`LineThreshold` / `ParameterThreshold` / `NestingThreshold` / `BranchThreshold` 的出厂默认都是 `none`** —— 即不设阈值该检查**什么都不做**（只有 `StatementThreshold` 默认 800）。`-cognitive-complexity.Threshold` 默认 `25` |
| D7 | `-Wdocumentation` 是否只查格式、不查缺失 | **已实测** | **成立**。夹具三例：注释完好的函数 0 报；`@param` 名写错的函数报 `parameter 'wrongName' not found in the function declaration`（并给出 `did you mean 'a'`）；**完全没有注释的函数也 0 报** ⇒ 它**只管已写注释的格式，不管注释缺失**。结论：公开成员的文档要求无法靠编译器强制执行，只能靠评审 + 工具（D8） |
| D8 | Doxygen 的 `WARN_IF_UNDOCUMENTED` 能否作为强制手段 | **待实测** | 本机无 `doxygen`；须在装了 Doxygen 的机器上做最小 Doxyfile 试验 |
| D9 | `clang-tidy` 的 `misra-*` 簇覆盖多少条 MISRA C++:2023 | **已实测（结论是"没有"）** | PyPI 轮子的 21.1.6 **完全不含 misra 检查**：`--list-checks --checks='-*'` 里搜 `misra` 命中 **0**，`--checks='-*,misra-cpp2023-*'` 直接报 `Error: no checks enabled.` ⇒ §8 的 MISRA 合规**不可能**靠这个构建的 clang-tidy 机械化，必须换商业检查器或纯人工评审 |
| D10 | WHCP 当前是否仍要求汇总 Code Analysis / SDV 日志 | **待实测** | 属文档核对，非工具行为 —— 查当前 WDK 版的《Creating a driver verification log》 |
| D11 | `SortIncludes` / `IncludeBlocks` 的实际生效值 | **已实测** | 均被接受且**确实生效**：乱序 include 原样保留；同一夹具改成 `CaseSensitive` + `Regroup` 后立刻重排（对照实验）。另：21.x 里 `SortIncludes` 已是**嵌套结构**（`Enabled` / `IgnoreCase`），标量 `Never` 仍被接受并映射为 `Enabled: false` —— 正是"跨大版本语义变过"的实证 |

> ⚠️ **反例**：D11 的复验命令不要写成 `grep -E 'SortIncludes[|]IncludeBlocks'`。在 ERE 里 `[|]` 是**字符类**（只匹配一个字面竖线字符），**不是交替运算符**。写成那样等于要求输入里出现字面 `SortIncludes|IncludeBlocks`，**永远零命中且 exit 1** —— 它会以"核对过了、输出为空"的外观返回，与 §5.1 / §7.3 反复强调的假绿同一形态。
> 本表原先就是坏的（自检第 16 节现已机械拦这类写法）。竖线要表示交替就写 `A|B`；要匹配字面竖线才写 `[|]`。
> 在 Markdown 表格单元里同时出现竖线时，别用 `\|` 转义去凑（不同渲染器对代码段里的 `\|` 处理不一致，转发给别人可能又变成坏的）——改用 `grep -e A -e B`，彻底避开这个字符。
