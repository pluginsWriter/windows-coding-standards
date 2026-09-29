---
name: windows-coding-standards
description: Windows 平台的编码规范与工具链，覆盖 C/C++ 与 C#/.NET 两套互不套用的规则。涉及 Windows 代码的写、改、评审、格式化、重命名或迁移时加载本 skill：按本次改动的文件后缀判定走哪一套（默认 C++），再读对应的 references/cpp-coding-standards.md 或 references/csharp-coding-standards.md。触发词：C++ 代码规范、clang-tidy、clang-format、CMake、MSVC、WHCP、驱动规范、命名不好、格式整改、代码评审、C# 代码规范、.NET 编码规范、editorconfig、dotnet format、Roslyn。
agent_created: true
compatibility: 需要 bash 与 POSIX shell。C++ 侧（当前默认栈）需 clang-format 与 clang-tidy；C#/.NET 侧需 .NET SDK 6+。两侧的配置载体与检查工具完全不同，见正文「两侧的入口」。
---

# Windows 编码规范（默认 C++，兼容 C#/.NET）

为 Windows 平台工程提供**可直接落地的编码规范与工具链**。

> **默认语言栈是 C++，同时兼容 C#/.NET。** 走哪一套**不由用户声明，由本次实际涉及的文件决定** —— 见「语言判定」。
>
> **两侧规则互不套用。** 它们的配置载体、检查 ID、格式开关、命名载体、注释语法全部不同，若干处甚至相反。混用是本 skill 能造成的最严重错误。

> **`SKILL_DIR` 约定**：本 skill 目录在下方命令里统一记为 `SKILL_DIR`。第一次使用前按实际位置定义一次：
>
> ```bash
> SKILL_DIR=~/Desktop/Application/windows-coding-standards
> ```

## 设计目的（**改规范本体之前先读这一节**）

**本规范针对的主要作者不是人，而是"给 AI 下指令的人 + 执行写作的 AI"。**
它要治的是 AI 编程引入的那类病 —— 编译通过、格式也合规，**但读不懂、改不动**：
命名生涩、注释复述签名、层次过深、体量系统性偏大或偏碎、到处补防御性检查。

⇒ **重心必须放在机器查不到的那一半。** 机器规则是**底线**，不是目标 ——
把规范写成一长串机器规则，是在解决一个不存在的瓶颈。
⚠️ 这与 §「两侧的入口」里"标 MUST 必须给得出检测命令"是**两件事**：那条管**怎么标等级**（不许假装可查），
这条管**别只写可查的**（须人工评审的条款可以是最重要的条款）。两者不可互相顶替。

**五个目标与各自的达成判据（含"怎样算做到"）的唯一出处：`references/design-purpose.md`。**
判断"要不要加一条规则 / 这次改动算不算达标"时，以那份文件的尺子为准。

## 默认生效（无需显式唤起）

**本规范对 Windows 平台代码默认生效。** 用户不需要说「请按编码规范来」，也不需要带上本 skill 的名字。

- **不要等被点名**：涉及 Windows 原生代码（C/C++）或 C#/.NET 代码时，先加载本 skill 再动手。
- **不要自行取舍风格**：用户未指定风格时一律以本规范为准。
- **先判语言，再选正文**（下一节）。**判错的代价大于不判。** 这是**每写一个文件时都要做**的动作，不是另起一步。
- **默认不等于擅自扩大改动**：默认生效指**风格判定**默认遵循，不是默认去批量整改存量代码。大规模格式化 / 重命名仍需用户批准。
- **默认更不等于可以改行为**：整改存量代码时，**整改前能被观察到的，整改后必须一模一样**（判据见 `references/change-discipline.md`）。改行为必须单独提交并告知用户。
- **默认也不等于可以加代码**：规则是合格判据，不是新增清单。新增的每一行都必须被某条规则指名要求。

## 语言判定：每写一个文件之前先看它的后缀（**不是独立步骤**）

**语言由「本次实际涉及的文件」决定，不由仓库整体决定。** 一个 Windows 工程里同时有 C++ 驱动与 C# 工具是常态；此时**按文件路由**，不要整仓套一套。

⚠️ **判定要发生在写码动作里，不是另起一步先去跑个命令。** 每次**新建 / 打开 / 编辑**一个文件时，先看它的后缀：

| 后缀 | 走哪一套 | 正文 | 配置 / 工具 |
| --- | --- | --- | --- |
| `*.cs` `*.csx` | C#/.NET | `references/csharp-coding-standards.md` | `assets/editorconfig` 的 `[*.{cs,csx}]` 段 + `dotnet format` / Roslyn |
| `*.cpp` `*.cc` `*.cxx` `*.c++` `*.c` | C++ | `references/cpp-coding-standards.md` | `assets/clang-format` / `assets/clang-tidy` + 编译器警告 |
| `*.h` `*.hh` `*.hpp` `*.hxx` `*.h++` `*.ipp` `*.inl` | C++ | 同上 | 同上（C# 侧不含任何头文件后缀） |

> 这张表必须与 `scripts/detect_language.sh` 的 `CS_EXT` / `NATIVE_EXT` 两个数组**逐项相同** ——
> 它是"不看命令也能判定"的唯一依据。**改任何一侧都要同时改另一侧**（否则会出现"按表判成 C++、按脚本判成 C#"）。

**同一批改动里两种后缀都出现时**：分别按各自那一行做，**不要**用其中一套的判据去处理另一套的文件。
**检查 / 监测同样按这个判定选** —— 改到哪个文件就只对哪个文件跑对应那一侧的命令，
**不存在"先把整套检查跑一遍"的阶段**：

- 改了 `.cs` → 对该工程跑 `dotnet format --verify-no-changes` 与 `dotnet build -warnaserror`
- 改了 `.cpp` / `.h` → 对该文件跑 `clang-format --dry-run --Werror` 与 `clang-tidy -p build/`

**只有两种情形才需要跑探测器**（它是**兜底**，不是第 0 步）：

1. 本次**不涉及任何源码文件**（只改构建脚本 / 文档 / 配置）—— 后缀判不出来；
2. 需要向用户**说明工程整体构成**（`STACK=mixed` 的报告、`PRIMARY` 是哪一侧）。

```bash
PROJECT=/path/to/your/project        # 目标工程根目录（仅在上述两种情形下需要）
bash "$SKILL_DIR"/scripts/detect_language.sh "$PROJECT" src/foo.cpp src/foo.h
```

脚本回显平台级证据（后缀普查、项目标记、`.sln` 的引用内容），末三行恒为机器可读：

```
STACK=cpp | csharp | mixed | unknown
PRIMARY=cpp | csharp
CONFIDENCE=high | low
```

| `STACK` | 该读什么 |
| --- | --- |
| `cpp` | `references/cpp-coding-standards.md` + `assets/clang-format` / `assets/clang-tidy` |
| `csharp` | `references/csharp-coding-standards.md` + `assets/editorconfig` 的 `[*.{cs,csx}]` 段 |
| `mixed` | 按 `PRIMARY` 先保证默认栈，再对另一语言的文件分别套对应正文；**不要交叉套用** |
| `unknown` | 零证据，按默认取 `cpp`（`CONFIDENCE=low`），并**向用户说明这是默认值而非探测结果** |

**判定优先级**（高 → 低）：① 本次涉及文件的后缀 → ② 工程级强标记（`.csproj` / `.vcxproj` / `CMakeLists.txt` / `vcpkg.json` / `global.json`）与 `.sln` 的**引用内容** → ③ 后缀普查 → ④ 无证据取默认 `cpp`。

**两个不能当判据的共享标记**：`.sln` 与 `Directory.Build.props` 是 C# 与 C++ **共用**的 MSBuild 载体，**存在性无意义** —— 只有 `.sln` 里引用的是 `.csproj` 还是 `.vcxproj` 才能消歧。自检里有专门的反例：`bash "$SKILL_DIR"/scripts/detect_language.sh --self-test`。

## 两侧的入口（**读错就是跑错了一侧**）

### C#/.NET 侧

- 正文：`references/csharp-coding-standards.md`
- 缺陷目录（编号 `#1`–`#33`）：`references/csharp-defect-catalog.md`
- 配置模板：`assets/editorconfig`（`[*.{cs,csx}]` 段 + 跨语言 `[*]` 段）、`assets/Directory.Build.props`、`assets/stylecop.json`
- 工具：`dotnet format` + Roslyn analyzers（`CAxxxx` / `IDExxxx`）
- 命名判据与可接受词表：C# 正文 §3（**唯一权威**）

### C++ 侧

- 正文：`references/cpp-coding-standards.md`
- 缺陷目录（编号 `CPP-01`–`CPP-38`）：`references/cpp-defect-catalog.md`
- **命名反模式词典**（可接受词表的唯一权威）：`references/cpp-naming-antipatterns.md`
- 配置模板：`assets/clang-format`、`assets/clang-tidy`
- 工具：`clang-format` + `clang-tidy` + 编译器警告（`-Werror`）
- 命名判据与可接受词表：`references/cpp-naming-antipatterns.md` §0（**唯一权威**）

### 两侧共用的判据层

**「本规范要治什么、怎样算治好了」跨语言共享**，`references/design-purpose.md` 是它唯一的出处 ——
含「AI 编程」这个前提、五个目标与各自的达成判据。**改规范正文之前先读它**（本文件「设计目的」一节只写立场，不复制判据）。

**「臃肿 / 过度拆分 / 类型级设计意图」的判据跨语言共享**，`references/design-granularity.md` 是它唯一的出处。两侧正文只引用它、不复制判据 —— 但**检测命令分语言**，见该文件 §2 与 §6。

**「整改不得改行为 / 不得为规范堆代码」的判据同样跨语言共享**，`references/change-discipline.md` 是它唯一的出处。**接存量工程之前必读那一份**（见下方「显式要求『把代码改规范』时」）。

### 隔离纪律（硬规矩）

1. **不得把一侧的判据、阈值、文件名、检查 ID 搬到另一侧。** 两侧文件名都带语言前缀，就是为了让误用无法通过「看起来像」发生。
2. **交付某一侧的工作时，只读该侧的正文与配置。** 判据：**如果你想给 C++ 代码跑 `dotnet format`，你已经跑错了一侧。**
3. **唯一允许共享的取值是跨语言项**：`.editorconfig` 的 `[*]` 段（charset / 缩进宽度 / 行尾 / 去尾随空白 / 末行换行）。该段是**唯一必须两侧一致**的地方；`[*.{cs,csx}]` 段只属 C# 侧。
4. **判不清走哪一侧时跑语言判定**（上一节），不要凭印象选一套。

## 必须记住的高频规则

### C#/.NET 侧

- **可空性必须开启**（`<Nullable>enable</Nullable>`）；禁止无理由用 `!`
- **禁止 `async void`**（事件处理器除外）；**禁止 `.Result` / `.Wait()`**
- **禁止空 `catch` 与吞异常**；只捕获能正确处理的异常类型
- **`IDisposable` 必须释放**（`using` 或 `try/finally`）
- **禁止公开字段**（`CA1051`）；**禁止魔法字符串与数字**（同一字面量 ≥ 2 次必须提取具名常量）
- **元组最多 2 个元素**；公开 API 返回多值必须定义具名类型
- **`public` / `protected` 成员必须有 XML 文档注释**（`CS1591`）
- **大小写**：类型 / 方法 / 属性 / 事件 / 常量 PascalCase，私有实例字段 `_camelCase`，私有静态字段 `s_camelCase`，接口 `I` + PascalCase，类型参数 `T` + PascalCase
- **数值参数必须带单位**：`timeoutMilliseconds` 而非 `timeout`
- **工厂方法用 `Create`**（**不要照搬 Swift 侧的 `make`**）
- **体量上限**：圈复杂度 / 函数行数 / 类型行数 / 参数个数四项（**等级一律 SHOULD**）—— 其中**只有复杂度有内置规则**（`CA1502`）；这四项在 C# 侧**没有配置载体**，取值与等级的唯一出处是正文 §5.3
- **防御性检查只加在信任边界上**：外部输入（命令行 / 文件 / 网络 / 反序列化 / 第三方返回值 / `public` 入口）**必须有**校验；边界之内对已由可空标注保证的条件重复判空属缺陷（`#33`）。**每处校验都要能说出"拦的是哪个来源的哪种失效"**
- **`case` 缩进用 `csharp_indent_switch_labels = false`**（与 Swift 侧相反，勿照搬）
- **`.editorconfig` 的 severity 必须用规则 ID 式**（`dotnet_diagnostic.IDE0040.severity = warning`）；选项式在 .NET 8 及更早**构建期不生效**，且不开 `EnforceCodeStyleInBuild` 时**命令行构建默认完全不做 IDExxxx 分析** —— 此时跑绿证明不了任何事

### C++ 侧

- **编译期强制（本机已实测）**：`-Wall -Wextra -Wconversion -Wshadow -Wold-style-cast -Wnon-virtual-dtor -Wextra-semi -Wpedantic -Werror`
- ⚠️ **`-Wall -Wextra` 不包含** `-Wold-style-cast` / `-Wshadow` / `-Wnon-virtual-dtor` —— **只用 `-Wall -Wextra` 就宣称查过了，是本侧最典型的假绿**
- ⚠️ **显式 C 风格转换会绕过 `-Wconversion`**（`int b = (int)x;` 不报）—— 两个开关必须同时开
- ⚠️ **非 const 全局变量、无作用域枚举，编译器完全不查** —— 只能靠 clang-tidy
- **权限与所有权**：优先 RAII / 智能指针；禁止裸 `new` / `delete`；禁止 `reinterpret_cast`（确需则注释理由）
- **多态基类必须有虚析构**；单参数构造函数标 `explicit`
- **命名路线**：Microsoft（PascalCase + `m_` 前后缀）—— 取值只写在 `assets/clang-tidy` 里
- ⚠️ **`readability-identifier-naming` 启了但没配 `CheckOptions` = 完全没查**（官方明说空配置等于关闭）
- **禁止把类型编码进名字**：`strName` / `pFoo` / `bBusy` —— 但 **`m_` / `g_` 是作用域前缀，不是类型编码，属合规**
- **数值参数必须带单位**：`timeoutMs` / `byteCount`
- **注释用 Doxygen**（`@brief` / `@param`）—— **与 C# 侧的 XML 完全不同**
- **防御性检查只加在信任边界上**：外部输入（命令行 / 文件 / 网络 / IPC / 反序列化 / 第三方与系统 API 返回值）**必须有**校验；边界之内的重复判空属缺陷（`CPP-38`）。**对 `T&` / `std::span` 判空是死代码**；**每处校验都要能说出"拦的是哪个来源的哪种失效"**
- **体量上限**：认知复杂度（**SHOULD**，`[待工程校准]`）/ 函数行数 / 参数个数 / 嵌套深度 / 分支数 / 类型行数 —— **取值只写在 `assets/clang-tidy`**，等级与依据见正文 §5.4
- **`case` 缩进由 `.clang-format` 的 `IndentCaseLabels` 决定** —— 与 C# 侧是两个不同的开关，取值互不参考

## 工作流

### 两侧共用

**A. 每写 / 改一个文件，先看它的后缀定侧**（见「语言判定」）—— 这是**写码动作本身的第一步**，
**不是**"另起一步先探测"的独立阶段；检查 / 监测命令也按同一判定逐文件选。**B. 改完 skill 后跑内部一致性自检**：

```bash
bash "$SKILL_DIR"/scripts/verify_consistency.sh          # 不一致记 FAIL
bash "$SKILL_DIR"/scripts/verify_consistency.sh --strict # 任何 WARN 也算 FAIL（含已声明的待决项）
```

自检覆盖 24 节：路径可达性、版权边界（**两侧规则相反**：C# 侧不得内置快照，C++ 侧允许）、跨语言项一致性、两侧缺陷类数与总数、两侧版本号、两侧配置键不得互相污染、语言探测器自检、**全仓 `.sh` 的「`$VAR` + 多字节字符」回归检查**（该写法在 UTF-8 的 `LC_CTYPE` 下会因 `set -u` 直接终止，报错还是乱码）、**跨语言判据层的引用完整性**（共享文件必须被两侧都引用上 —— 一侧悄悄弃用共享判据是隔离漏洞）、**正则竖线卫生**（`[|]` 是字符类不是交替；写成 `grep -E 'A[|]B'`（反例）会永远零命中却以"输出为空"冒充"核对过了"）、**两份 C++ 配置模板的陷阱与真机验证**（静态拦「`Checks` 写成折叠块标量」与「`.clang-format` 里误用 `.editorconfig` 键名」两类会让配置**静默全失效**的写法；**若本机有 `clang-format` / `clang-tidy` 则真的读一遍模板并逐条核对键名与禁用项是否生效 —— 没有工具时记 WARN，不记 PASS**）、**自检脚本自身的契约**（头部声明的每个退出码都必须真能出现且反之亦然、未知参数必须被拒而不能静默退化、SKILL.md 自述的节数必须等于实际节数且编号连续）、**语言判定表的双向一致性**（`SKILL.md` 与 `README.md` 的「后缀 → 走哪一套」表必须与 `scripts/detect_language.sh` 的 `CS_EXT` / `NATIVE_EXT` **逐项相同** —— 那张表是"不看命令也能判定"的唯一依据，与探测器漂移就会得到"按表判成 C++、按脚本判成 C#"）、**两侧的 AI 病灶索引表**（表必须存在、**前两列逐行一致**（病灶名与特征形态是"病"本身，跨语言共享）、**第四列每行都指得到东西** —— 编号要在该侧缺陷目录里检索得到，指不出来就必须明写「本侧不治」，**不允许留空格**）、**体量阈值的取值来源唯一**（模板恰好声明那 5 个键各一次；正文 / 摘要 / 判据层不得复制数值；C++ 正文 §5.4 的表内不得出现数字；C# 侧带数值时必须声明"本侧没有配置载体"）、**待实测清单的「状态」维度**（C++ 附录 D 必须显式分成「已销 / 未销」两段，**段标题自带的条数必须等于段内实际行数**、两段之和必须等于 D 行总数；README 里"已销 N 条"与点名的剩余条目也必须与正文一致 —— 同一事实抄两处就必然漂）、**文内 / 跨文件引用的可解析性**（两侧正文里每一处 `§X.Y` 都必须指得到真实存在的标题；归属规则是"同一行内、紧跟其后的 `` `xxx.md` ``"，列表项 `§1.4 / §5.6` 继承前项；**锚定式必须能区分 `## 3. 标题` 与 `### 3.1`** —— 写成 `([^0-9]|$)` 会让 `§3` 冒充 `### 3.1`，恰是它自己那条负向测试要抓的假绿）、**审计层与规则层的通路**（两份审计文档都必须写出 **C 类专用口径** 并把 `expected` 的来源指向目的层 `design-purpose.md`；`audit/templates/claims-checklist.tsv` 接入两侧正文**附录 D** 的条数必须**逐侧对得上**、`id` 连续无断号、每行 **8 个字段**、README 抄的那两个数也要对得上 —— 少一样，审计层就退回"只能核验工具链声明、说不出规则层缺了哪几条"）、**C++ 侧工具脚本的契约**（头部声明的退出码必须都有对应 exit 且反之亦然、未知参数必须被拒、**空范围必须非零退出** —— 空清单被读成「干净」就是假基线，这条刻意排在工具检测之前，没装 clang 的机器上也成立）、**两个 C++ 脚本必须列进本文件**（交付了却不入口，用户仍会手抄命令）。期望值一律从 `assets/` 模板与正文表格推导，不写第二份硬编码。

> 自检**默认只做静态核对**（本机 macOS 无 .NET SDK、无 MSVC、无 Windows SDK）。例外只有两处：第 17 节**若 PATH 里（或 `$CLANG_FORMAT_BIN` / `$CLANG_TIDY_BIN` 指向）有 `clang-format` / `clang-tidy`，它就会真的去读那两份模板并核对键名与禁用项** —— 有工具却不跑真验证，等于把"没验"当"通过"；第 18 节会**带递归护栏与超时地把本脚本再执行一次**（喂一个坏参数），确认拼错的 `--strict` 不会假绿。C++ 侧的编译器警告类与格式化器 / tidy 行为类**均已实测**（`clang++` + 21.1.6 的 clang-format/clang-tidy），只剩 D8（需 Doxygen）与 D10（需查 WDK 文档）两条待实测。
>
> 自检脚本本身**与 locale 无关**，已在 `LC_ALL` / `LC_CTYPE` × `C` / `en_US.UTF-8` / `zh_CN.UTF-8` 下逐一跑过并全部通过 —— 含历史上必崩的那个组合（`LANG=C` + `LC_CTYPE=en_US.UTF-8`）。

### C#/.NET 侧

1. **安装配置**：`bash "$SKILL_DIR"/scripts/bootstrap_dotnet_style.sh "$PROJECT" --check`（只读）。`--fix` 会改源码，执行前必须先向用户确认。
2. **写 / 改**：命名看正文 §3（`§3.3` 是唯一权威词表）；格式看 §4（**人工排版同样合规**）；注释看 §6.1。写完跑：
   ```bash
   dotnet format --verify-no-changes     # 只读；非 0 退出即有未格式化文件
   dotnet build -warnaserror             # 语义与文档注释
   ```
3. **评审**：先采基线（只读）—— `dotnet build -warnaserror 2>&1 | grep -oE '\b(CA|IDE|CS|SA)[0-9]{4}\b' | sort | uniq -c | sort -rn`。**然后确认配置真的生效**：故意塞一处已知违规，看检查器是否报出来；不报 = 配置无效，基线作废。
4. **按缺陷目录三档逐类过**（一档 15 类机器可检出 / 二档 10 类可 grep 定量 / 三档 8 类纯人工）。**一次只开一档规则**，每开一档重采基线。

### C++ 侧

1. **安装配置**（脚本化，仍可手动复制）：
   ```bash
   bash "$SKILL_DIR"/scripts/bootstrap_cpp_style.sh "$PROJECT" --check          # 只读
   bash "$SKILL_DIR"/scripts/bootstrap_cpp_style.sh "$PROJECT" --fix            # 安装 .clang-format / .clang-tidy（只新增，不覆盖）
   bash "$SKILL_DIR"/scripts/bootstrap_cpp_style.sh "$PROJECT" --check --probe  # 探针：塞已知违规，验证配置真的生效
   # 生成 compile_commands.json（clang-tidy 依赖它；CMake 的 VS 生成器**不产出**该文件）
   cmake -S "$PROJECT" -B "$PROJECT"/build -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
   ```
   ⚠️ `.editorconfig` **不在脚本安装范围**（两侧共享、只有一份，见接入计划 §5.3）；复制后**先让工具把模板读一遍**
   （`clang-format -style=file -dump-config` 的 **stderr 必须为空**）—— 两份模板已用 21.1.6 实测过，但**换版本要重跑**；
   自检第 17 节在有工具时会自动做这件事。
2. **写 / 改**：格式由 `clang-format` 管；写完后跑 §5.1 的推荐开关集（**不是只有 `-Wall -Wextra`**）。
3. **评审**：先采基线（只读）——
   ```bash
   bash "$SKILL_DIR"/scripts/baseline_cpp_style.sh "$PROJECT"    # 清单 / 工具 / 数据库三者缺一即非零退出，不报假 0
   ```
   **`Checks` 为空 / `CheckOptions` 为空 = 命名等于没查。** 故意留一处 `int n = (int)d;` 验证是否报 `-Wold-style-cast`；不报则本次「0 违规」作废。
4. **按缺陷目录三档逐类过**（一档 20 类 / 二档 11 类 / 三档 7 类）。**三档里的「过度拆分」没有任何工具能报**，必须人工过 `design-granularity.md` §8 的评审清单。

### 显式要求「把代码改规范」时（两侧共同纪律）

**两条硬约束，判据全在 `references/change-discipline.md`：**

1. **接入之前 —— 不得改变原有行为。** 改存量不规范代码时，**整改前能被观察到的，整改后必须一模一样**。
   拿不准就按该文件 §1.2 给每处改动定级（**A 定义等价 / B 上下文相关 / C 必然改行为**）：A 类可批量，B 类必须跑测试，**C 类必须单列提交 + 告知用户 + 有回归测试**。
   ⚠️ 最容易越界的一处：把 C 类（删空 `catch`、`.Result` → `await`、加 `explicit`、加虚析构）混进「纯格式提交」。
2. **接入之后 —— 不得为满足规则而增加代码。** **新增的每一行，必须能指着一条规则说「是它要求我加的」，且删掉这行就违反那条规则。**
   规则是**合格判据**，不是**新增清单**。典型违规：复述签名的文档注释、给每个字段补属性、同义解释的 `@param`、成片 `NOLINT` / `#pragma warning disable`。
   整改天然是净删或持平 —— 净增行数显著为正时回该文件 §2.2 逐条对（`git diff --numstat`）。

**其余不能省的：**

- **不能只跑一次格式化就交付。**
- 格式化只解决格式；**命名、文档、魔法值、设计粒度它一律不碰**，而后者通常才是用户抱怨的重点。
- 终检必须加上「成员间分隔空行」（C# 侧靠 StyleCop `SA1516`，C++ 侧靠 `.clang-format` 的 `SeparateDefinitionBlocks`）—— 这一项**两个格式化器都不报**。
- **交付的三件东西**（§1.7 的完成定义，缺一不算完成）：**前后数字** + **剩余清单（还有哪些没改、为什么）** + **可复现命令**。
  另外每处改动都要能挂上一个缺陷编号或规则条目 —— 挂不上的，说明那处改动本来就不该做。**只做了格式就等于没做完。**
- **禁止「顺手清理」**（死代码、未使用参数、"多余"的防御性检查、注释掉的旧代码）—— 那属于改变行为，须单独提交。
- 超过体量上限的类型**不要机械切割** —— 先过 `design-granularity.md` §3.2 的提问清单。
- 大范围整改前留**回滚点**（干净分支或 tag）；单个提交要小到能被评审。

## 本版的状态声明

**本版尚未在任何真实工程上完整跑过一遍。** 两侧状态不同，必须分开看：

**C++ 侧：v0.1.7**（当前默认栈；本应记 v0.1.3，为与 C#/.NET 侧区分而跳号）

- **已实测**（Apple clang 21.0.0 + clang-format/clang-tidy **21.1.6**，逐条见 C++ 正文附录 D）：
  - 编译器警告类：`-Wnon-virtual-dtor` / `-Wold-style-cast` / `-Wshadow` / `-Wconversion` / `-Wextra-semi` 均生效；`-Wall -Wextra` **不含**它们；显式 C 风格转换**绕过** `-Wconversion`；非 const 全局与无作用域枚举**无警告**；`-Werror` 生效；`clang++ --analyze` 可用。
  - 格式化器 / tidy 行为类：`--dry-run --Werror` 未格式化 exit 1；`SeparateDefinitionBlocks: Always` 确实强制成员间空行；`SortIncludes: Never` 确实不重排 include（对照实验：改成 `CaseSensitive` 后立刻重排）；`clang-tidy` 出厂默认启用 134 条 / 本模板簇配置 432 条；命名规则确实会报；`readability-identifier-naming` 空 `CheckOptions` = **完全没查**。
- **销项过程中查出并修掉两份模板的 3 个真实缺陷**（v0.1.4）：① `assets/clang-format` 误用 `.editorconfig` 的 `EndOfLine`（clang-format 的键是 `LineEnding`）→ **clang-format 报 unknown key 并拒绝读整个文件**，模板里一条都不生效；② `assets/clang-tidy` 的 `Checks` 写成折叠块标量 `>`，其中 `#` 不是注释而是内容 → 注释被粘进紧随的禁用项，**14 条禁用废掉 10 条**；③ `HeaderGuardCase` / 全局 `HungarianPrefix` 两个键名在 21.1.6 **不存在**（静默忽略）。
- **仍待实测**：D8（Doxygen `WARN_IF_UNDOCUMENTED` 可否作强制手段，本机无 doxygen）、D10（WHCP 是否仍要求汇总 Code Analysis / SDV 日志，属文档核对）。
- ⚠️ **`clang-tidy` 的 PyPI 构建不含 `misra-*` 检查**（实测 `misra` 命中 0 条）⇒ §8 的 MISRA 合规**不能**靠它机械化。
- **C++ 侧的来源快照可以做**（C++ Core Guidelines 是 MIT-style 许可），但**尚未做**。
- **v0.1.7**（**E3 + E2**，规则与阈值均未变）：① 附录 D 的标题原先写「待实测清单」，而 11 条里 **9 条已销** ⇒ 标题与内容自相矛盾（G2 的最后一处失真）。改为「**验证状态与待实测清单**」，D 表拆成「**已销**（9 条，保留复验命令）/ **未销**（2 条，写明"缺什么才能销"）」两段。② 自检新增**第 22 节**：正文里每一处 `§X.Y` 都必须指得到真实标题（本侧扫过 56 处；缺了就在改名时静默指空）。
- **v0.1.6**（**D-1 / D-2 落地**）：① **认知复杂度降为 SHOULD** 并标 `[待工程校准]` —— 实测它的阈值**就是 clang-tidy 的出厂默认值 `25`**，本工程从未选择过它，也没有任何标准规定它；§2 的元规则因此**补上第二个条件**（MUST 必须「可检查 **且** 有依据」）。② §5.4 表**不再写数值**（改为「等级 / 依据 / 由谁检查」），并补登 `BranchThreshold`；阈值副本在所有文档里一并改为指针。③ §0 新增**病灶索引表**（六类 AI 病灶 → 归属）。④ 新增 **`CPP-38`「防御性检查泛滥」**：判据按**信任边界分层**，且每处校验必须能说出"拦的是哪个来源的哪种失效"。⑤ 自检新增**第 20 / 21 节**。
- v0.1.5：**规则与阈值均未变**，把跨语言目的层 `references/design-purpose.md` 接进本侧（§0 末尾加指针）——
  它显式写出「**AI 编程**」这个前提与五个目标的**达成判据**；此前该前提从未进入规范本体，两侧 §0 只写了"人类团队选不出来"。
- v0.1.1 补的是变更纪律引用与 `#include` 重排开关的显式写死（那两项此前依赖预设默认，会随 clang-format 版本漂移）；v0.1.2 修 D11 的复验命令（原写法 `grep -E 'SortIncludes[|]IncludeBlocks'`（反例）把 ERE 的**字符类**当成了**交替**，永远零命中且 exit 1）。

**C#/.NET 侧：v0.1.5**

- 凡涉及**工具实际行为**的论断标 `[待实测]`，汇总在其正文附录 D（8 条）。销项需要一台装了 .NET SDK 的机器。
- **本 skill 不内置 C# 侧官方来源快照**（版权原因：权威是书与 Learn 页面），因此不提供逐字引文校验。
- v0.1.2 补隔离声明与粒度判据引用；v0.1.3 补变更纪律引用与提交前清单。**各版均未改规则。**
- **v0.1.5**（**D-1 / D-2 落地**）：① §5.3 的表补「等级」列（四项**一律 SHOULD**）并**显式声明本侧没有配置载体**。② §0 新增**病灶索引表**。③ 新增 **`#33`「防御性检查泛滥」**：判据按**信任边界分层**。④ 自检第 20 节开始机械核对本侧病灶表。
- v0.1.4：**规则未变**，把跨语言目的层 `references/design-purpose.md` 接进本侧（§0 末尾加指针）。

**两侧共同**

- **跨语言目的层 `references/design-purpose.md`（v0.1.1）** 是「**AI 编程**」这个前提与五个目标达成判据的唯一出处；
  两侧正文 §0 都指向它，由自检第 15 节机械核对"两侧都用上了"（一侧悄悄弃用 = 静默隔离漏洞）。
- 版本号**两侧独立演进**，由自检第 10 节分别核对（含 README —— 它曾是漏网的第 5 处）。

## 参考文件

- `references/csharp-coding-standards.md` —— **C#/.NET 完整规范**：0 问题定义 / 1 权威分层 / 2 强制等级与可检查性 / 3 命名 / 4 格式 / 5 语言与设计 / 6 文档注释与测试 / 7 四道闸门与配置联动 / 8 迁移纪律 + 附录 A 自检清单 / B 来源入口 / C 变更记录 / D 待实测清单
- `references/csharp-defect-catalog.md` —— **C#/.NET 缺陷目录**：33 类（15 / 10 / 8），编号 `#1`–`#33`
- `references/cpp-coding-standards.md` —— **C++ 完整规范**：0 问题定义 / 1 权威分层与隔离 / 2 可检查性元规则 / 3 格式 / 4 命名 / 5 语言与设计 / 6 注释与文档 / 7 工具链与四道闸门 / 8 领域合规（MISRA / WHCP）/ 9 迁移纪律 + 附录 A 清单 / B 来源 / C 变更记录 / D 验证状态与待实测清单
- `references/cpp-defect-catalog.md` —— **C++ 缺陷目录**：38 类（20 / 11 / 7），编号 `CPP-01`–`CPP-38`
- `references/cpp-naming-antipatterns.md` —— **C++ 命名反模式词典**：§0 可接受词表（**唯一权威**）/ A–I 九类必改反模式 / 快速替换表 / 七条自检测试
- `references/design-purpose.md` —— **设计目的（跨语言）**：「AI 编程」这个前提、五个目标（G1 业务 / G2 元规则 / G3 定位 / G4 硬约束 / G5 机制）与**各自的达成判据**、总判据、本规范**不承诺**什么；**改规范本体之前先读**
- `references/design-granularity.md` —— **设计粒度判据（跨语言）**：臃肿与过度拆分的双向判据、拆分的正当与禁止信号、类型级设计意图要求、碎片化候选筛选命令、评审清单
- `references/change-discipline.md` —— **变更纪律判据（跨语言）**：**整改不得改变原有行为**（A/B/C 三级分类 + 两侧分侧陷阱表 + 证据阶梯）与**不得为满足规则增加代码**（唯一判据 + 常见违规清单 + 净增行数信号）；**接存量工程之前必读**
- `assets/editorconfig` —— `.editorconfig` 模板。`[*]` 段**跨语言**；`[*.{cs,csx}]` 段仅 C#。**跨语言项（缩进 / 行尾 / charset）的唯一权威**
- `assets/Directory.Build.props` —— **仅 C#/.NET**：`AnalysisLevel` / `EnforceCodeStyleInBuild` / `TreatWarningsAsErrors` / `Nullable`
- `assets/stylecop.json` —— **仅 C#/.NET**：StyleCop 配置（仅在决定引入 StyleCop 时使用）
- `assets/clang-format` —— **仅 C++**：格式唯一权威（`BasedOnStyle` + 显式覆盖）
- `assets/clang-tidy` —— **仅 C++**：检查项与命名的唯一权威（`Checks` + `CheckOptions`）
- `scripts/detect_language.sh` —— 语言判定（`--self-test` 校验探测器本身）
- `scripts/bootstrap_dotnet_style.sh` —— **仅 C#/.NET**：工具链检测与安装、基线采集（`--check` / `--fix`）
- `scripts/bootstrap_cpp_style.sh` —— **仅 C++**：工具链检测、安装 `.clang-format` / `.clang-tidy`（`--check` / `--fix`，只新增不覆盖）、配置生效探针（`--probe`）
- `scripts/baseline_cpp_style.sh` —— **仅 C++**：违规基线采集（固化接入计划 §4.2：NUL 清单 + `[ -s ]` 守卫 + 数 NUL 字节得条数；**清单为空 / 缺工具 / 缺编译数据库一律非零退出**，绝不报「0 违规」）
- `scripts/verify_consistency.sh` —— skill 内部一致性自检（双侧）

**尚未建立**（不要凭空引用，也不要拿别的文件顶替）：C++ 整改手册、C++ 侧来源快照与引文校验、`CODING_STYLE.md` 工程模板。
