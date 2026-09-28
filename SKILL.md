---
name: windows-coding-standards
description: Windows 平台（当前目标栈 C#/.NET）的默认编码规范与强制工具链（dotnet format + Roslyn analyzers + .editorconfig）。任何写、改、评审、重命名、格式化或迁移 C#/.NET 代码的工作默认遵循本规范，无需用户显式点名。核心动作不是补充规则而是「收敛选择」—— C# 侧内置 CAxxxx/IDExxxx 数百条，另有 StyleCop 与 2000+ 第三方分析器包，真正的病是选不出来、噪音淹没信号、配置静默不生效。覆盖命名（判据是「遮住定义只看调用点能否读懂」，并明确列出可接受词以免制造无意义重命名）、格式（人工排版与工具排版同等有效）、XML 文档注释、语言与设计约束（可空性 / async / IDisposable / 魔法值 / 体量上限）、32 类缺陷的三档分法与每条的可检查性披露、四道闸门与配置联动、来源快照的版权边界、分级迁移。**正文中涉及工具实际行为的论断部分尚未在装有 .NET SDK 的机器上实测**，一律以 [待实测] 标注并汇总在附录 D。触发场景与触发词清单见正文「何时使用」。
agent_created: true
compatibility: Requires the .NET SDK 6 or later (for `dotnet format`) and bash. StyleCop.Analyzers / Roslynator 为可选，只在需要「成员间空行」或「Async 后缀」这类内置查不出的规则时引入。适用于任意 SDK 风格的 .csproj / .sln 工程。本 skill 不内置官方来源快照（版权原因，见参考文献 §7.4），因此不提供逐字引文校验。
---

# Windows 编码规范（C#/.NET）

为 Windows 平台的 C#/.NET 工程提供**统一的命名、格式、注释与语言约束标准**，并配套可直接落地的强制工具链（`dotnet format` + Roslyn analyzers）。

> **本 skill 目录在下方命令里统一记为 `SKILL_DIR`。** 第一次使用前先按实际位置定义一次；将来若把它链进某个 agent 的 skill 根目录，把该路径填进来即可。
>
> ```bash
> SKILL_DIR=~/Desktop/Application/windows-coding-standards
> ```

## 默认生效（无需显式唤起）

**本规范对 C#/.NET 代码默认生效。** 用户不需要说「请按编码规范来」，也不需要在提示里带上本 skill 的名字 —— 只要这次工作涉及 C#/.NET 代码，就按本规范执行。

- **不要等被点名**：涉及 C#/.NET 代码时，先加载并应用本 skill，再动手写或改。
- **不要自行取舍风格**：用户未指定风格时一律以本规范为准。
- **写完即自检**：改动 C#/.NET 代码后按附录 A 清单自检。
- **默认不等于擅自扩大改动**：默认生效指**风格判定**默认遵循，不是默认去批量整改存量代码。大规模格式化 / 重命名仍需用户批准。

## 三条最容易搞错的事（先读这三条）

**1. 命名只针对「读不懂」，不针对「不眼熟」。**
中文开发者普遍熟悉的常用词与高频缩写**明确可以接受，不得要求重命名** —— 完整可接受词表以 `references/csharp-coding-standards.md` §3.3 为**唯一权威**，其他文件只引用、不复制。真正要改的只有三类：生僻词、自造缩写与单字母、对象或返回值无从判断。判据只有一条：**遮住定义只看调用点，陌生人能否说出这行在做什么。**

**2. `.editorconfig` 的 severity 语法有两套，写错就静默失效。**
**选项式**（`csharp_style_xxx = value:warning`）在 .NET 8 及更早**构建时不被 C#/VB 编译器识别**，只有 IDE 会报；**要在构建期强制，必须用规则 ID 式** `dotnet_diagnostic.IDE0040.severity = warning`。而且 `EnforceCodeStyleInBuild` 不为 `true` 时，**命令行构建默认完全不做 code-style（IDExxxx）分析** —— 此时 `dotnet build` 与 CI 全绿**证明不了任何事**。这与 Swift 侧「`.swiftlint.yml` 的 `included` 指向不存在目录 → 报 0 违规」是同一类**假基线**。

**3. 「跑过工具」不等于达标。**
`dotnet format` 只修它支持自动修的部分 —— 命名、文档、魔法值、设计约束它一律不碰。跑过一次就宣布合规，是本规范最想拦住的交付方式。交付时必须明确列出「还剩什么、为什么」。

## 何时使用

- 编写、修改、评审任何 C#/.NET 代码
- 用户抱怨代码不规范、命名难懂、格式混乱、注释缺失
- 需要新建或调整 `.editorconfig` / `Directory.Build.props` / `stylecop.json`
- 需要为工程建立编码规范文档，或做规范迁移
- 提交前自检、配置 CI 的代码检查步骤

**触发词**（对话中出现任一即应加载本 skill；description 已压缩，完整清单在此维护）：C# 代码规范、.NET 编码规范、C# 命名、XML 文档注释、代码风格、code style、editorconfig、dotnet format、Roslyn analyzer、StyleCop、IDE0055、CA1502、代码分析、命名不好、格式整改、规范化代码，以及 C# review / code review、重构、重命名等场景。

## 核心原则

> **Windows 是平台，不是语言，因此不存在一份「Windows 官方编码规范」。** 规则分散在四层：语言与运行时、领域合规（驱动 WHCP 认证）、平台与界面（Fluent / WinUI）、跨语言底座（EditorConfig）。

- 命名与 API 设计 → 依据 **Framework Design Guidelines**（书，**只做条目索引与引文，不可整篇复制**）
- 语言与语法 → C# 语言规范；惯例性写法 → Learn《常见 C# 代码约定》（官方自认**不是**权威列表，只作参考）
- 格式 → 以 `.editorconfig` 为**唯一权威配置载体**；正文不写第二份阈值副本
- **约束力 ≈ 可检查性**（本规范最硬的元规则）：能机器查的绝不靠「写个 MUST」；给不出检测命令的只能降 SHOULD 并注明「须人工评审」
- 人工评审聚焦三件事：**命名是否可读**、**设计是否合理**、**注释是否说明契约而非复述代码**

## 必须记住的高频规则

- **可空性必须开启**（`<Nullable>enable</Nullable>`）；禁止无理由用 null-forgiving `!`
- **禁止 `async void`**（事件处理器除外）；**禁止 `.Result` / `.Wait()` / `GetAwaiter().GetResult()`**
- **禁止空 `catch` 与吞异常**；只捕获能正确处理的异常类型
- **`IDisposable` 必须释放**（`using` 声明或 `try/finally`）
- **禁止公开字段**（`CA1051`）；**禁止魔法字符串与数字**：同一字面量出现 ≥ 2 次必须提取具名常量
- **元组最多 2 个元素**；公开 API 返回多值必须定义具名类型
- **`public` / `protected` 成员必须有 XML 文档注释**（`CS1591`）
- **常量大小写**：类型 / 方法 / 属性 / 事件 / 常量 PascalCase，私有实例字段 `_camelCase`，私有静态字段 `s_camelCase`，接口 `I` + PascalCase，类型参数 `T` + PascalCase
- **缩写大小写**：长度 > 2 的缩写只首字母大写 —— `Id` 不是 `ID`、`HttpClient` 不是 `HTTPClient`
- **禁止匈牙利式前缀与无意义后缀**：`strName`、`objMgr`、`itemInfo`
- **数值参数必须带单位**：`timeoutMilliseconds` 而非 `timeout`
- **工厂方法用 `Create`**（.NET 惯例，**不要照搬 Swift 侧的 `make`**）
- **布尔参数在调用点读不懂时改具名实参**：`CreateOrder(id, applyDiscount: true)`
- **体量上限**：圈复杂度 15 / 函数 60 行 / 类型 300 行 / 参数 6 个 —— 其中**只有复杂度有内置规则**（`CA1502`），其余三项标 SHOULD + 人工评审
- **`case` 缩进用 `csharp_indent_switch_labels = false`**（与 Swift 侧相反，勿照搬）

## 工作流

### 场景零：为什么没有「引文校验」步骤

Swift 版有一个 `verify_citations.sh`，靠内置的官方原文快照做逐字校验。**本版刻意没有这一环**：C#/.NET 侧的主要权威是**书**（《Framework Design Guidelines》）与 Microsoft Learn 各页，**不可整篇复制进 skill 分发**（详见正文 §7.4）。因此引用只到「条目索引 + 链接」为止。

将来若要补校验，只能降级为「**引用条目存在性校验 + 链接可达性检查**」，而不是逐字比对 —— 这件事必须在写脚本之前定，不能事后补。

### 场景零之二：内部一致性自检（改完 skill 后跑，纯离线）

`SKILL.md`、规范正文、缺陷目录与 `assets/` 配置模板之间存在多处**同一事实的副本**（缩进、行尾、`case` 缩进、命名约定、`Async` 后缀的等级、`[待实测]` 条数）。历史上正是这些手抄副本造成漂移。

```bash
bash "$SKILL_DIR"/scripts/verify_consistency.sh          # 不一致记 FAIL
bash "$SKILL_DIR"/scripts/verify_consistency.sh --strict # 待决项也算 FAIL
```

期望值一律**从 `assets/` 模板与正文表格推导**（阈值取自模板、条数取自表格行数），**不在脚本里写第二份硬编码** —— 硬编码只会制造下一个漂移源。

> 本机（macOS）**没有 .NET SDK**，故一致性自检只做**静态**核对（文本与配置取值），不调用 `dotnet`。

### 场景一：为工程安装规范工具链

```bash
bash "$SKILL_DIR"/scripts/bootstrap_dotnet_style.sh <工程目录> --check
```

脚本会检测 .NET SDK、安装 `.editorconfig` 与 `Directory.Build.props`、并输出违规基线。要执行修复，显式加 `--fix`（会修改源码，执行前必须先向用户确认）。未检测到 SDK 时脚本会**明确退出并报错**，不会给出假的「0 违规」。

### 场景二：写 / 改 C# 代码

1. 命名看正文 §3（拿不准查 §3.3 可接受词表 —— 那是唯一权威）。
2. 格式看正文 §4；**人工排版同样合规**（`csharp_preserve_single_line_blocks/statements` 必须在配置里显式保留）。
3. 注释看正文 §6.1（`<summary>` → `<param>` → `<returns>` → `<exception>`）。
4. 写完运行：

   ```bash
   dotnet format --verify-no-changes     # 只读；非 0 退出即有未格式化文件
   dotnet build -warnaserror             # 语义与文档注释
   ```

### 场景三：评审既有代码

1. 采集基线（**先只读，不改代码**）：

   ```bash
   dotnet build -warnaserror 2>&1 | grep -oE '\b(CA|IDE|CS|SA)[0-9]{4}\b' | sort | uniq -c | sort -rn
   dotnet format --verify-no-changes
   ```

2. **确认配置真的生效** —— 这一步不能省：往代码里**故意塞一处已知违规**，看检查器是否报出来。不报就是配置无效，基线作废。省掉这步，拿到的很可能是一份假的「0 违规」。
3. 按缺陷目录的**三档**逐类过一遍，**不要只盯「格式 + 命名」**：

   | 档 | 处理方式 |
   | --- | --- |
   | 一档：机器可检出（15 类） | 进 CI，给数字，机械修复 |
   | 二档：可 grep / 可定量（9 类） | 人工确认后整改 |
   | 三档：纯人工评审（8 类） | 进评审清单，**不计入 CI 门槛** |

4. **一次只开一档规则**（先正确性 + 安全，再性能 + 可靠性，最后样式），每开一档重采一次基线 —— 否则数字混在一起无法归因。
5. 报告时区分「格式类（可机械修复）」与「命名 / 设计 / 注释类（需评审）」。

### 场景四：为工程建立规范文档

在工程根目录创建 `CODING_STYLE.md`，**只写项目特有内容**（模块结构、错误码体系、领域术语表、目标框架、既有基线、迁移排期），并声明遵循本 skill 的通用标准。不要把通用规则复制进去 —— 复制会产生版本分裂。

### 场景五：显式要求「把代码改规范」时的完整整改

用户明确说「按规范改」「把不规范的地方改掉」时，**不能只跑一次 `dotnet format` 就交付**。

> ⚠️ 本场景的整改手册**本版尚未建立**（Swift 版里有一个同名文件，**不可照搬** —— 两侧工具链与可检查性差得远）。在它建立之前，按下列顺序做，并且**不得**把「跑过脚本」当作完成：
>
> 1. 采基线 + 确认配置生效（场景三第 1–2 步）。
> 2. 机械修复只解决格式；**命名、文档、魔法值、设计约束必须另行处理**。
> 3. 终检必须三条都干净：`dotnet format --verify-no-changes` 无输出、`dotnet build -warnaserror` 0 warning、成员间空行（若已引入 StyleCop）`SA1516` 无输出。
> 4. 如实列出剩余项与理由。**只做了格式就等于没做完。**

## 工具链要点

- **`dotnet format` 随 .NET 6+ SDK 内置**，先试它，不要无脑装第三方格式化器。
- **分工必须清晰**：`dotnet format` 管格式，Roslyn analyzers 管语义。默认**只用内置分析器**（`CAxxxx` + `IDExxxx`）。
- **引入 StyleCop 必须有配套的「关闭清单」**：它是「成员之间必须有分隔空行」（`SA1516`）与成员顺序（`SA1201`）的**唯一**机器来源 —— 正是 Swift 侧只能自写 `verify_member_spacing.sh` 的那条规则；但它同时带来约 100 条规则，且 `SA1xxx` 与 `IDE0055` 会**双报**同一处格式问题。**必须二选一。**
  - 现状提示：`StyleCop.Analyzers` 至今**没有 1.2.0 正式版**（NuGet 最新为 `1.2.0-beta.556`，2023-12-21），仓库仍在维护。网上「它已归档 / 已并入 `Microsoft.CodeAnalysis.NetAnalyzers`」的说法**不实**，采信会直接丢掉成员空行这条唯一检测源。
- **`Async` 后缀内置查不出**：`dotnet_naming_rule` 没有「异步方法」这个 symbol 组，须引第三方分析器（Roslynator `RCS1046`，**默认关闭**；AsyncFixer `ASYNC0001`；`VSTHRD200`）。未引入前该条降 SHOULD。
- **配置缺失 / 作用域为空 = 假基线，必须挡住**：脚本在缺少配置时从 `assets/` 模板生成（**只新增、绝不覆盖**已有配置）。
- **`max_line_length` 的强制性存疑**：EditorConfig 的行长主要被**编辑器**遵守，Roslyn analyzers 是否在构建期强制**尚未实测**（正文 §4.4）。在得到结论前，行长只能是 SHOULD + 评审，**不得**写成 MUST。
- **`end_of_line` 必须显式写**（模板默认 `lf`）：纯 Windows 团队可改 `crlf`，但改这一处必须**同步 `.gitattributes`**，并单独提交一次全仓行尾重排 —— 严禁与逻辑改动混在一个提交里。

## 迁移纪律

- 格式迁移是**无行为变更**的提交：不新增测试，但每次提交后必须跑受影响的测试。
- 重命名与数据建模调整是**有行为边界影响**的变更：重命名 public API **先写 ADR**，再完整回归。
- **严禁把格式修改与逻辑修改放进同一个提交。**
- **存量工程不要一次全开规则**：参照 dotnet/roslyn 的做法分三档推进（Common / Shipping / NonShipping）—— 先「正确性 + 安全」，再「性能 + 可靠性」，最后「可维护性 + 样式」，样式类初期限定 `suggestion`。
- 禁止为提高通过率而放宽阈值；放宽阈值必须写进正文附录 C 变更记录。

## 本版的状态声明（重要）

**本规范是 v0.1.1，尚未在任何真实工程上跑过一遍。** 因此：

- 正文中凡涉及**工具实际行为**的论断，一律标 `[待实测]`，并汇总在**正文附录 D**（8 条）。**这些条目在销项之前不得当作结论使用。**
- 本机是 macOS、**没有 .NET SDK**，所以「跑一次看看」这条路在本机走不通 —— 销项需要一台装了 .NET SDK 的机器。
- 已由官方文档确认、**不属于** `[待实测]` 的，目前只有：severity 两套语法的差别、命令行构建默认不做 IDExxxx 分析、`EnforceOnBuild.Never` 的存在、`Async` 后缀需第三方分析器、驱动侧 CodeQL 与 DVL 的性质。

## 参考文件

- `references/csharp-coding-standards.md` —— **完整规范**：0 问题定义 / 1 权威分层 / 2 强制等级与可检查性 / 3 命名 / 4 格式 / 5 语言与设计 / 6 文档注释与测试 / 7 四道闸门与配置联动 / 8 迁移纪律 + 附录 A 自检清单 / B 来源入口 / C 变更记录 / D 待实测清单
- `references/defect-catalog.md` —— **缺陷目录与检测方法**：32 类缺陷按「机器可检出 / 可 grep 定量 / 纯人工」三档，每类给检测命令、整改动作、典型样本，另有「已知漏检与陷阱」7 条
- `assets/editorconfig` —— `.editorconfig` 模板（安装时复制到工程根；**缩进、行尾、命名规则、severity 的唯一权威**）
- `assets/Directory.Build.props` —— MSBuild 属性模板（`AnalysisLevel` / `EnforceCodeStyleInBuild` / `TreatWarningsAsErrors` / `Nullable` / `GenerateDocumentationFile`）
- `assets/stylecop.json` —— StyleCop 配置模板（**仅在决定引入 StyleCop 时使用**）
- `scripts/bootstrap_dotnet_style.sh` —— 工具链检测与安装、基线采集（`--check` / `--fix`）
- `scripts/verify_consistency.sh` —— skill 内部一致性自检：取值从 `assets/` 模板与正文表格推导，不写第二份硬编码

**尚未建立**（不要凭空引用）：整改手册（场景五）、权威来源快照与引文校验（版权原因，见场景零）、`CODING_STYLE.md` 工程模板。
