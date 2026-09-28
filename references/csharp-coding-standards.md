# C#/.NET 编码规范（Windows 平台）

> 版本：v0.1.3（补变更纪律与提交前清单，**规则本身未变**）· 2026-09-28
> 状态：正文、缺陷目录、配置模板（`assets/editorconfig` / `Directory.Build.props` / `stylecop.json`）与检查脚本均已建立。文中标 `[待实测]` 的条目是尚未在装有 .NET SDK 的机器上验证过的论断，附录 D 汇总了验证命令。
>
> **本文件只服务 C#/.NET。** C++ 侧见 `references/cpp-coding-standards.md`。
> 两套规则**互不套用** —— 隔离纪律与相反取值清单见 `cpp-coding-standards.md` §1.4 / §5.6。
>
> **C#/.NET 侧的配套文件**（各司其职）：
> - `references/csharp-defect-catalog.md` —— 缺陷目录（`#xx` 编号）
> - `references/design-granularity.md` —— **跨语言**的粒度判据（臃肿 / 过度拆分，§5.3 引用它）
> - `references/change-discipline.md` —— **跨语言**的变更纪律（整改不改行为 / 不为规范堆代码，§8 引用它）
> - `assets/editorconfig` / `Directory.Build.props` / `stylecop.json` —— 配置模板（取值的唯一权威）

---

## 0. 问题定义：为什么不能「照抄一份官方规范」

**Windows 不是语言，是平台。它不定义编码规范。** 与 Swift 不同 —— Swift 有清晰的三件套（S1 API Design Guidelines + swift-format + SwiftLint），照它写规范是「补缺口」；而 C#/.NET 侧的情况恰好相反：

| | Swift | C#/.NET |
|---|---|---|
| 官方权威文本 | 一份（S1），明确 | 多份：Framework Design Guidelines、Learn 常见 C# 代码约定（**自认非权威**）、C# 语言规范 |
| 可执行规则数量 | 两个工具，规则数十条 | Roslyn analyzers 内置 `CAxxxx` + `IDExxxx` 数百条，另有 StyleCop 与第三方分析器（NuGet 上 2000+ 包） |
| 主要风险 | 规则太少、覆盖不到 | **规则太多、选不出来、噪音淹没信号、配置静默不生效** |

因此本规范的作用**不是补充规则，而是收敛选择**：在数百条可用规则中，明确「哪些进 MUST、哪些降 SHOULD、哪些明确关掉」，并给出每一条的检测方式。凡是本规范没选的，视为**故意不启用**，而不是遗漏。

### 与 Swift 规范的关系

沿用同一套架构原则（见 §2），但目标相反：Swift 版解决「没有」，本版解决「太多」。

---

## 1. 权威依据与分层

**第一层：可执行权威（唯一权威，机器执行）**

`.editorconfig` + `Directory.Build.props` 是**唯一权威配置载体**。规范正文里的任何阈值、词表、开关，若在配置里也存在，**以配置为准，且只能有一份**（本规范正文不写第二份副本 —— 这是 Swift 版踩过漂移后立的规矩）。

**第二层：文本权威（人读，用于判断与争议裁决）**

| 用途 | 依据 |
|---|---|
| 命名与 API 设计 | **Framework Design Guidelines**（Cwalina / Abrams）—— 受版权保护，**只做条目索引与引文，不可整篇复制** |
| 语言与语法 | C# 语言规范 |
| 惯例性写法 | Learn《常见 C# 代码约定》—— 官方文档团队自用，**页面明确声明它不是权威列表**，故本规范只把它当参考、不当依据 |
| 规则含义 | Learn：代码样式规则（IDExxxx）、质量规则（CAxxxx）各规则页 |

**第三层：工具权威（执行者）**

Roslyn analyzers（随 SDK 内置） / `dotnet format`（随 .NET 6+ SDK 内置） / 可选 StyleCop.Analyzers。

**引用纪律**：正文引用官方原文必须标注来源与版次；书籍类来源只做索引不做快照；快照的合法性逐个确认（见 §7.4）。

---

## 2. 强制等级与「可检查性」原则（本规范最硬的一条元规则）

三个等级：

| 等级 | 含义 | 要求 |
|---|---|---|
| **MUST** | 必须遵守 | **必须给出检测命令**，且能在 CI 中判定通过/不通过 |
| **SHOULD** | 应当遵守 | 允许例外，但例外须在评审中说明；须注明「可 grep 定量」或「须人工评审」 |
| **MAY** | 可自由选择 | 不做检查 |

**核心判据：约束力 ≈ 可检查性。**

- 给不出检测命令的条目，**不得标 MUST**，只能降 SHOULD 并注明「须人工评审」。
- **「跑过工具」不等于达标。** `dotnet format` 只能修它支持自动修的部分；项目里跑过一次，不代表命名、文档、设计问题已清零。交付时必须明确列出「还剩什么、为什么」。

> 这条不是理论。Swift 侧有一条「成员之间必须有空行」写在规范里、标了 MUST，工程里照样违反 703 处 —— 因为它当时没有任何检查器。加了检查器（并在 C# 侧对应 StyleCop `SA1516`）之后，它才变成一个数字。

---

## 3. 命名

### 3.1 判据（唯一判据，不满足则改）

**遮住定义只看调用点，一个没读过这段代码的人能否说出这行在做什么。** 说不出 → 改名。

### 3.2 只针对三类「真缺陷」

1. **生僻词**：`reify`、`coalesce`（作动词滥用）、`amortize`
2. **自造缩写与单字母**：`svc`、`mgr`、`cfg`、`tmp`、`l`、`r`、`w`、`n`
3. **对象或返回值无从判断**：`GetData()`、`Handle()`、`Process(item)`、返回 `object` 或裸元组

### 3.3 明确可以接受（不得要求重命名）

- 中文开发者普遍熟悉的常用词与高频缩写：`config`、`handler`、`count`、`index`、`src`、`dest`、`id`、`init`、`async`、`enum`
- 语言与框架既有词汇：`Task`、`Span`、`Span<T>` 惯用名、LINQ 方法名
- **公认缩写不算自造**：`Http`、`Url`、`Id`、`Xml`、`Json`、`Api`、`Ui`
- 反例教训：把常用词判成缺陷，会制造大量无意义重命名与 diff 噪音。

> **本节的词表是本规范内「可接受命名」的唯一权威位置。** 其他文件（含整改手册）只引用，不复制。Swift 版曾因在两处各写一份词表导致内容漂移。

### 3.4 大小写约定（MUST，可机器检出）

| 元素 | 约定 | 示例 |
|---|---|---|
| 类型、方法、属性、事件、常量 | PascalCase | `OrderService`、`MaxRetryCount` |
| 参数、局部变量、局部函数 | camelCase | `retryCount` |
| 私有实例字段 | `_camelCase` | `_connectionString` |
| 私有静态字段 | `s_camelCase` | `s_defaultOptions` |
| 接口 | `I` + PascalCase | `IPaymentGateway` |
| 类型参数 | `T` + PascalCase | `TResult` |
| 异步方法 | PascalCase + `Async` 后缀 | `LoadOrdersAsync` |

> **`Async` 后缀能机器检出，但内置规则只覆盖一半**（2026-09-14 按官方规则表更正 —— 初稿曾断言「内置覆盖不到」，**是错的**）。
>
> - `dotnet_naming_rule` 的 `required_modifiers` **允许值里包含 `async`**，所以「**带 `async` 关键字的方法必须以 `Async` 结尾**」可以用内置规则强制（三段式写法见 `assets/editorconfig`），**不需要第三方包**。
> - **覆盖不到的那一半**：返回 `Task` / `ValueTask` 但**没写 `async` 关键字**的方法匹配不到 —— 那部分才需要第三方分析器：Roslynator `RCS1046`（**默认关闭，要显式开**）、AsyncFixer `ASYNC0001`、`Microsoft.VisualStudio.Threading.Analyzers` 的 `VSTHRD200`。
> - 因此本项的处理是**拆开定级**：带 `async` 关键字的那半 → **MUST**（内置规则，可进 CI）；返回 Task 而无 `async` 的那半 → **SHOULD + 评审**。
> - 顺带：`RCS1047`「非异步方法不该以 `Async` 结尾」默认已开，与 `RCS1046` 是一对，引入时一并考虑。

### 3.5 命名规则

- **缩写大小写**：长度 > 2 的缩写只首字母大写 —— `Id` 不是 `ID`、`HttpClient` 不是 `HTTPClient`。（摘自 Framework Design Guidelines，属经典约定）
- **禁止匈牙利式前缀与无意义后缀**：`strName`、`objMgr`、`listData`、`itemInfo`、`xxxManager`（除非它真的管理 `xxx`）
- **布尔成员**用 `Is` / `Has` / `Can` / `Should` 开头（SHOULD）
- **数值参数必须带单位**：`timeoutMilliseconds` 而非 `timeout`，`byteCount` 而非 `size`（MUST，评审判定）
- **工厂方法用 `Create`**：`CreateConnection()`。注意 **不要照搬 Swift 侧的 `make` 前缀** —— .NET 惯例是 `Create`，`Make` 一般只用于非托管/转换场景
- **不加 `Get` 前缀**于属性（属性名本身是名词：`Count` 而非 `GetCount`）；方法需要动词时正常用动词
- **具名实参替代「参数标签」**：C# 没有参数标签，所以当调用点读不懂时用具名实参 —— 这是 §3.1 判据的落地方式：
  ```csharp
  // 读不懂：这两个 true 是什么？
  CreateOrder(customerId, true, true);
  // 改用具名实参
  CreateOrder(customerId, applyDiscount: true, sendConfirmation: true);
  ```
- **在 .editorconfig 中的表达方式**：`dotnet_naming_rule` + `dotnet_naming_symbols` + `dotnet_naming_style` 三段式声明，等价于 `IDE1006`。不要只写进文档而不进配置。

---

## 4. 格式

### 4.1 人工排版与工具排版同等有效

`dotnet format` / IDE 的自动格式化是合法的排版来源，**手写的换行与对齐同样是合法的**。**`dotnet format` 不是提交前必做动作**；CI 只做 `--verify-no-changes` 检查，**禁止自动改写源码**。

必须显式保留人工排版的开关（不设置就会被格式化器改写）：

```ini
csharp_preserve_single_line_blocks = true
csharp_preserve_single_line_statements = true
```

局部豁免：`#pragma warning disable IDE0055` 或 `// format: off` 形式需在实测后确定（`[待实测]`）。

### 4.2 必须改的格式项（本规范认定的「不规范」，其余一律保留）

| # | 项 | 配置项 / 规则 |
|---|---|---|
| 1 | 一行多条语句 | `csharp_preserve_single_line_statements` 相关；`IDE0055` |
| 2 | 花括号缺失或未换行 | `csharp_prefer_braces = true`、`csharp_new_line_before_open_brace = all`；`IDE0011` |
| 3 | 关键字与括号/花括号之间的空格 | `csharp_space_*` 系列；`IDE0055` |
| 4 | **成员之间缺分隔空行** | **无 Roslyn 内置规则**；对应 **StyleCop `SA1516`**（须引入 StyleCop 才可机器检出） |
| 5 | 行尾空白、文件末尾无换行 | `trim_trailing_whitespace = true`、`insert_final_newline = true`；`IDE0055` |

**第 4 项是本规范与 Swift 版最直接的同构点**：Swift 侧这条两类工具都查不出，只能自建检查器；C# 侧它**可以**被机器检出，但前提是引入 StyleCop.Analyzers。这正是「收敛选择」的一个具体决策点 —— 引入 StyleCop 会增加约 100 条规则，必须同时决定关掉哪些（见 §7.3 分工纪律）。

### 4.3 缩进与换行

- `indent_size = 4`、`indent_style = space`
- `end_of_line`：**二选一且必须写进配置** —— 纯 Windows 工程用 `crlf`；含 macOS/Linux 协作或 CI 的工程用 `lf`。不要留空默认。
- `csharp_indent_case_contents = true`、`csharp_indent_switch_labels = false`（`case` 与 `switch` 同级，**与 Swift 侧的 `indentSwitchCaseLabels = true` 相反，不要照搬**）
- `csharp_using_directive_placement`：`System` 分组置顶（`dotnet_sort_system_directives_first = true`）

### 4.4 行长上限

`[待实测]` EditorConfig 的 `max_line_length` 主要被编辑器遵守，**Roslyn analyzers 是否在 `IDE0055` / 构建期强制行长，需实测确认**。若不强制，则本项为 SHOULD + 评审，且**必须如实标注**（Swift 侧的教训：文档写了一个工具不认的选项，照文档执行直接报错）。

### 4.5 格式化的边界

- 大规模格式化（全工程重排）**必须经用户批准**，且**与逻辑改动分开提交**（见 §8）。
- 禁止为通过检查而放宽配置阈值。

---

## 5. 语言与设计约束

### 5.1 MUST

- **可空性必须开启**：`<Nullable>enable</Nullable>`。禁止无理由使用 null-forgiving `!`；确需使用时必须有注释说明为何此处不可能为 null。
- **禁止 `async void`**，事件处理器除外。
- **禁止同步阻塞异步**：`.Result`、`.Wait()`、`GetAwaiter().GetResult()`。
- **禁止空 `catch` 与吞异常**：`catch { }`、`catch (Exception) { }` 后无处理。只捕获能正确处理的异常类型。
- **`IDisposable` 必须释放**：`using` 声明或 `try/finally`。
- **禁止公开字段**：用属性（`CA1051`）。
- **禁止魔法字符串与魔法数字**：同一字面量出现 ≥ 2 次必须提取具名常量。
- **元组最多 2 个元素**，且用于内部；**公开 API 返回多值必须定义具名类型**（对应 Swift 侧的「元组最多 2 成员、关联值必须具名」）。
- **`public` / `protected` 成员必须有 XML 文档注释**（`CS1591`），说明用途、参数、返回值与抛出的异常。

### 5.2 SHOULD

- 优先不可变：`readonly`、`init`、`record`。
- 优先 `IReadOnlyList<T>` / `IEnumerable<T>` 返回，而非数组（`CA1819`）。
- 用 `Func<>` / `Action<>` 而非自定义委托类型。
- `ConfigureAwait(false)` 用于库代码。
- 布尔参数是「调用点读不懂」的常见来源 —— 优先改具名实参，其次考虑拆成两个方法或引入枚举。

### 5.3 体量上限（对照 Swift 侧，逐条说明可检查性）

| 项 | 上限 | 可检查性 |
|---|---|---|
| 圈复杂度 | 15 | `CA1502`（**默认未启用，阈值配置方式 `[待实测]`**） |
| 函数行数 | 60 | **无内置规则** → SHOULD + 人工评审 |
| 类型行数 | 300 | **无内置规则** → SHOULD + 人工评审 |
| 参数个数 | 6 | **无内置规则**（Swift 侧有 SwiftLint `function_parameter_count`；C# 侧需自定义分析器或 SonarQube `S107`）→ SHOULD + 人工 |

> 这张表本身就是对「可检查性」原则的诚实披露：**Swift 侧有工具的四项，C# 侧只有一项有工具**。本规范不为凑数把它们标成 MUST。
>
> #### ⚠️ 超过上限 ≠ 必须拆
>
> **上限是"提示需要检查"，不是"必须拆"。** 触发后必须过一遍 `design-granularity.md` §3.2 的提问清单：
>
> - **能说出独立的变化原因** → 按该原因拆，并把原因写进提交信息；
> - **说不出** → **不拆**，改为在类型头部写明职责与协作关系（§6.1）。
>
> 为把行数压到上限以下而机械切割，只会把"难以理解的大段"变成"难以理解的多段"。
>
> **「拆解过细」与「臃肿」是同一个病的两个方向，判据与检测见 `design-granularity.md`** —— 那份文件同时给出拆分的正当理由（§3.3）、禁止拆的信号（§3.4）、类型级设计意图的判据（§5）以及碎片化的候选筛选命令（§6.1）。**本侧没有任何内置规则能报"拆得太碎"**，它只能靠那份判据 + 人工评审。

---

## 6. 文档注释与测试

### 6.1 文档注释

- 开启 `<GenerateDocumentationFile>true</GenerateDocumentationFile>` + `CS1591` 作为警告 → 公开 API 缺文档可机器检出。
- 结构：`<summary>` → `<param>` → `<returns>` → `<exception>` → 需要时 `<remarks>` / `<example>`。
- 继承场景用 `<inheritdoc/>`，不要复制父类文档。
- 摘要写**契约**（做什么、什么条件下会抛异常），不写实现细节的复述。
- **中文注释、英文标识符**（沿用既有约定）。

### 6.2 测试

- 框架由工程选定（xUnit / NUnit / MSTest），不得混用。
- 断言用语义化 API（`Assert.Equal`、`Assert.Throws<T>`），禁止 `Assert.True(a == b)`。
- 禁止测试中的 `Thread.Sleep` 作为同步手段。
- 测试名说明「被测对象 + 场景 + 期望」，不写 `Test1`。

---

## 7. 工具链与四道闸门

### 7.1 闸门

| # | 闸门 | 命令 / 配置 | 说明 |
|---|---|---|---|
| 1 | 编辑期 | VS / VS Code + `.editorconfig` | `IDExxxx` 实时提示 |
| 2 | **构建期** | `EnforceCodeStyleInBuild=true` + `AnalysisLevel` + `TreatWarningsAsErrors=true` | **.NET 侧独有的硬闸门** —— 不依赖钩子，「跑不过就提交不了」直接压在编译上 |
| 3 | 格式 | `dotnet format --verify-no-changes` | 只读检查；退出码非 0 即有未格式化文件 |
| 4 | 语义 | Roslyn analyzers（`CAxxxx`），可选 StyleCop | 命名、设计、安全、性能 |

### 7.2 配置联动（必须始终一致，改一处就要查其余）

类似 Swift 的「五者必须一致」，本规范有三组联动点：

1. `.editorconfig` 的 `indent_size` / `end_of_line` / `indent_style` ↔ 编辑器与 CI 的期望
2. `.editorconfig` 中每条规则的 `dotnet_diagnostic.XXX.severity` ↔ `Directory.Build.props` 的 `AnalysisLevel` / `EnforceCodeStyleInBuild` / `TreatWarningsAsErrors`
3. `dotnet format` 在 CI 中的参数（`--severity` / `--verify-no-changes`）↔ `.editorconfig` 里实际设为 warning 及以上的规则集合

> **severity 语法有两套，写错就静默失效**（2026-09-14 按官方文档更正 —— 本行此前把两者**写反了**）：
>
> - **选项式**（`csharp_style_xxx = value:severity`）：**构建时不被 C#/VB 编译器识别**，只在 IDE 生效（.NET 9 起才在构建期生效）。
> - **规则 ID 式**：`dotnet_diagnostic.IDE0040.severity = warning` —— **要在构建期强制，必须用这一套**。
> - 并且 `EnforceCodeStyleInBuild` 不为 `true` 时，**命令行构建默认完全不做 code-style（IDExxxx）分析**。此时 `dotnet build` 与 CI 全绿**证明不了任何事**。
> - 另有 `EnforceOnBuild.Never` 的规则（`SimplifyNames`、`RemoveUnqualification`、`PreferBuiltInOrFrameworkType` 等）出于性能考虑**只在 IDE 里跑**，开关打开也压不住 —— 应列入「已知查不出」而不是标 MUST。
>
> `[待实测]` 待验证的是「**当前 SDK 上开关是否如文档所述生效**」（附录 D 第 3 条），不是语法本身。

### 7.3 工具分工纪律：禁止重叠

Swift 侧的做法是**显式禁用 SwiftLint 的全部格式规则**，避免与 swift-format 双报。C# 侧同理：

- **StyleCop `SA1xxx`（格式类）与 `IDE0055` 必须二选一**，否则同一处格式问题报两遍、噪音翻倍。
- StyleCop 与内置 `CAxxxx` 有交叠区间，引入时须逐条比对并关掉重复项。
- 本规范的立场：**默认只用内置分析器（`CAxxxx` + `IDExxxx`）+ `dotnet format`**。只有当第 4 项（成员间空行）这类内置查不出的规则成为真实痛点时，才引入 StyleCop，并同时提交一份「关闭清单」。

### 7.4 来源快照的版权边界（与 Swift 版的关键差异）

Swift 版敢内置 S1–S6 快照，是因为这些来源可分发。C#/.NET 侧**不能照抄**：

| 来源 | 可否内置快照 |
|---|---|
| Framework Design Guidelines（书） | **不可** —— 只做条目索引 + 引文 |
| Microsoft Learn 各页 | 需逐页核实许可（页脚通常标 CC BY 4.0 文档 / MIT 代码），**不可默认整篇复制** |
| dotnet/runtime、dotnet/roslyn 的配置与规范文件（MIT 仓库） | 可快照 |

**因此引文校验机制要改设计**：Swift 版的 `verify_citations.sh` 依赖「有快照可比对」；若合法快照源不足，应降级为「**引用条目存在性校验 + 链接可达性检查**」。此事必须在建立脚本之前定，不能事后补。

---

## 8. 迁移纪律

> **判据不在本节，在 `change-discipline.md`**（跨语言共享）。本节只写 C#/.NET 侧的**流程与顺序**。
> 那两条硬约束是：**整改不得改变原有行为**（接入之前）、**不得为满足规则而增加代码**（接入之后）。

- **格式迁移与逻辑迁移严禁放进同一个提交。** 格式提交无行为变更，不新增测试，但每次提交后必须跑受影响的测试。
- **重命名 public API 先写 ADR**，并对受影响的测试完整回归。
- **改之前先给每处改动定级**（`change-discipline.md` §1.2 的 A / B / C），并按级决定「能否批量、要不要测试、要不要先告知用户」。
  C#/.NET 侧最容易踩的三处：`?.` 展开成 `if (x != null)`（**属性 getter 会被调 2 次**）、`.Result` → `await`（线程与异常包装全变）、删空 `catch`（**被吞的异常开始外抛，调用方可能因此崩**）。
- **`!`（null-forgiving）是纯编译期断言，运行时零开销** —— 它属于 A 类，不是行为变更；**不要与 `?.` 混淆**，后者是 C 类。
- **禁止为通过检查放宽阈值**；确需放宽必须写进本规范的变更记录（附录 C）。
- **不得为消除分析器警告而加代码。** 典型反例：给每个字段补属性、补同义复述的 `<summary>`、成片 `#pragma warning disable`。
  判据见 `change-discipline.md` §2.1：**新增的每一行必须被某条规则指名要求。**
- **禁止「顺手清理」**：死代码分支、未使用参数、"多余"的防御性检查、注释掉的旧实现 —— 它们可能是刻意的（序列化占位、上游接口占位、调试开关）。清理属 C 类，须单独提交。
- **交付的三件东西**（`change-discipline.md` §1.7）：**前后数字** + **剩余清单（还有哪些没改、为什么）** + **可复现命令**；每处改动挂一个 `#nn` 编号，挂不上的说明本来就不该改。
- **存量工程不要一次全开规则。** 采用分档推进（dotnet/roslyn 自己的做法：Common / Shipping / NonShipping 三档配置）：先只开「正确性 + 安全」，再开「性能 + 可靠性」，最后开「可维护性 + 样式」。样式类初期限定在 suggestion。
- 大范围整改前留**回滚点**（干净分支或 tag）。
- 整改的完整流程（基线 → 机械修复 → 复检 → 待办清单 → 报告）参照同族的 Swift 规范 skill（名叫 `swift-coding-standards`）里的整改手册，**本版待建**。
  > ⚠️ 写这类引用时**不要**把那本手册的路径抄成本仓的相对路径形式（即以 references 开头的那种写法）—— 它在**另一个 skill 的内部**，写成本仓路径会被读成本地文件，也会被自检第 2 节判成悬空引用。跨 skill 引用一律**用 skill 名字**，不用路径。

---

## 附录 A：提交前自检清单

- [ ] `dotnet format --verify-no-changes` 通过
- [ ] 构建 0 warning（`TreatWarningsAsErrors=true` 生效时即自动满足）
- [ ] 成员之间有空行（若已引入 StyleCop，`SA1516` 无输出）
- [ ] 新增/修改的公开成员有 XML 文档注释
- [ ] 新增命名过一遍 §3.1 判据（遮住定义看调用点）
- [ ] 无 `!`、`.Result`、`.Wait()`、空 `catch` 的新增
- [ ] 该新增的 `!` 是否只是编译期断言（A 类），还是实际引入了短路语义变化（C 类）？
- [ ] 魔法字符串/数字已提取
- [ ] 新增的 `<summary>` 除了复述签名，还说了什么？
- [ ] 本次提交**只含格式改动**，或**只含逻辑改动**
- [ ] 每处改动定过级（A / B / C）吗？C 类的单独提交与回归测试在哪？（`change-discipline.md` §1.2）
- [ ] 本次净增行数是多少？显著为正的话，逐条对过 `change-discipline.md` §2.2 吗？（`git diff --numstat`）

## 附录 B：来源入口

- `dotnet format`：https://learn.microsoft.com/dotnet/core/tools/dotnet-format
- 代码样式规则（IDExxxx）：https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/
- 质量规则（CAxxxx）：https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/
- 代码分析配置（EditorConfig / globalconfig）：https://learn.microsoft.com/dotnet/fundamentals/code-analysis/configuration-files
- C# 格式设置选项：https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/formatting-rules
- 常见 C# 代码约定：https://learn.microsoft.com/dotnet/csharp/fundamentals/coding-style/coding-conventions
- .NET 库设计指南：https://learn.microsoft.com/dotnet/standard/design-guidelines/
- StyleCop.Analyzers：https://github.com/DotNetAnalyzers/StyleCopAnalyzers
- EditorConfig：https://editorconfig.org/

## 附录 C：变更记录

| 版本 | 日期 | 说明 |
|---|---|---|
| v0.1 | 2026-09-14 | 首稿：结构沿用 Swift 版（0–8 章 + 附录），目标由「补缺口」改为「收敛选择」。缺陷目录同期建立（文件名当时为 `defect-catalog.md`，2026-09-28 改名为 `csharp-defect-catalog.md`）。未在真实工程验证 |
| v0.1.1 | 2026-09-14 | **更正 §7.2 的 severity 表述**（原写「按规则 ID 设的 severity 构建时不生效」，方向写反）；附录 D 第 3 条改为「验证开关是否按预期生效」；补记「命令行构建默认不做 IDExxxx 分析」及「`EnforceOnBuild.Never` 的规则只在 IDE 跑」。§3.4 补记 `Async` 后缀的**可检查性拆分**（`required_modifiers` 允许值含 `async`，故带 `async` 关键字的那半内置可查、标 MUST；返回 `Task` 而无 `async` 的那半须 `RCS1046` 等第三方分析器，标 SHOULD）。同步更正缺陷目录已知漏检第 2 条 |
| v0.1.2 | 2026-09-28 | **规则未变，只补结构与边界**：① 头部补与 C++ 侧的隔离声明（两侧文件、配置载体、检查 ID、命令互不套用）；② §5.3 补「超过上限 ≠ 必须拆」并指向新增的跨语言判据 `design-granularity.md`；③ 修正头部已过时的状态陈述（原写「配置模板与检查脚本尚未建立」，实际早已建立） |
| v0.1.3 | 2026-09-28 | **规则未变**：① 新增跨语言配套文件引用 `change-discipline.md`，§8 迁移纪律由「只写流程」改为「流程 + 判据指针」，并补本侧三处最易踩的行为变更（`?.` 的 getter 调用次数、`.Result` → `await`、删空 `catch`）与「`!` 属 A 类不是行为变更」的区分；② 补「不得为消除分析器警告加代码」「禁止顺手清理」「交付三件东西」；③ 附录 A 补三条清单（`!` 的归类、文档注释的信息量、改动定级与净增行数） |

## 附录 D：待实测清单（在有 .NET SDK 的机器上逐条验证并把结论写回正文）

| # | 待验证的问题 | 建议命令 |
|---|---|---|
| 1 | `dotnet format --verify-no-changes` 是否覆盖命名类规则，还是只覆盖格式 | 造一处命名违规，跑 `dotnet format --verify-no-changes` |
| 2 | 行长是否被 `IDE0055` 强制；`max_line_length` 的实际作用 | 写一行 200 字符，跑 `dotnet format --verify-no-changes` |
| 3 | 设 `EnforceCodeStyleInBuild=true` 后，`dotnet_diagnostic.*.severity = warning` 是否**确实在构建期报出**（语法与默认关闭行为已由官方文档确认，见 §7.2；待验证的是当前 SDK 的实际开关行为，以及 `EnforceOnBuild.Never` 的**例外清单到底有哪些**） | 设 `IDE0040` 为 `warning` 后 `dotnet build`；再对 `IDE0003` 这类重复一次，看是否只在 IDE 报 |
| 4 | `IDE0005`（未使用 using）在构建期是否上报（已知它依赖 `GenerateDocumentationFile`） | 加一个无用 using，`dotnet build -warnaserror` |
| 5 | `CA1502` 的启用方式与阈值配置键名 | `dotnet_diagnostic.CA1502.severity = warning` + 调阈值 |
| 6 | StyleCop `SA1516` 与内置规则的重叠清单 | 引入 StyleCop，对同一文件跑两次，比对输出交集 |
| 7 | 局部豁免格式检查的正确写法 | `#pragma warning disable IDE0055` 与 `// format: off` 各试一次 |
| 8 | `csharp_preserve_single_line_blocks/statements` 默认值是否为 `true`（若默认已开，则「必须显式设置」的说法要修正） | 不写这两项，观察手写单行块是否被改写 |
