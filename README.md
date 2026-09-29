# windows-coding-standards

Windows 平台的编码规范 skill —— 同时支持 **C/C++** 与 **C#/.NET** 两套**互不套用**的规则，各自配一套可直接落地的检查工具链。

装上之后**默认生效**：不需要显式点名这个 skill，也不需要说「请按规范来」。

走哪一套不靠你声明 —— 由**每个文件的后缀**决定，**在你写 / 改它的那一刻**就定了。混合工程按文件路由，不会整仓套一套。

> **两侧规则不得互相套用。** 它们的配置载体、检查 ID、格式开关、命名载体、注释语法全部不同，若干处甚至相反（例如 `case` 缩进、常量命名）。混用是本 skill 能造成的最严重错误 —— 详见 [`SKILL.md`](SKILL.md) 的「两侧的入口」。

## 一、安装

先把仓库取到本地（放哪都行，下面统一用 `SKILL_DIR` 指代）：

```sh
git clone https://github.com/pluginsWriter/windows-coding-standards.git
SKILL_DIR="$PWD/windows-coding-standards"
```

再把它接到你所用 agent 的 skill 目录。**用软链，不要复制目录** —— 复制出来的副本不会跟着上游更新。

```sh
mkdir -p ~/.workbuddy/skills ~/.claude/skills ~/.agents/skills

ln -sfn "$SKILL_DIR" ~/.workbuddy/skills/windows-coding-standards   # WorkBuddy
ln -sfn "$SKILL_DIR" ~/.claude/skills/windows-coding-standards      # Claude Code
ln -sfn "$SKILL_DIR" ~/.agents/skills/windows-coding-standards      # Codex / opencode
```

按你实际用的工具挑一行即可。验证是否已被发现（以 opencode 为例）：

```sh
opencode debug skill > /tmp/skills.txt 2>&1
grep windows-coding-standards /tmp/skills.txt
```

> 输出务必重定向到文件 —— 经管道（`| grep`）会因 SIGPIPE 被随机截断，同一条件连测会得到矛盾结果。

### 走哪一套（C++ 还是 C#/.NET）—— 看后缀即可，不用先跑命令

**判定发生在写码动作里**：每次新建 / 打开 / 编辑一个文件，先看它的后缀。

| 后缀 | 走哪一套 | 该跑哪个检查（只对改了的那一侧） |
| --- | --- | --- |
| `*.cs` `*.csx` | C#/.NET | `dotnet format --verify-no-changes`、`dotnet build -warnaserror` |
| `*.cpp` `*.cc` `*.cxx` `*.c++` `*.c` | C++ | `clang-format --dry-run --Werror`、`clang-tidy -p build/` |
| `*.h` `*.hh` `*.hpp` `*.hxx` `*.h++` `*.ipp` `*.inl` | C++ | 同上（C# 侧不含任何头文件后缀） |

同一批改动里两种后缀都出现时，**分别按各自那一行做**，不要用其中一套的判据去处理另一套的文件。
**不存在"先把整套检查跑一遍"的阶段。**

**只有在两种情形下才需要跑探测器**（它是兜底，不是前置步骤）：本次不涉及任何源码文件；
或需要向用户说明工程整体构成（`STACK=mixed`）。

```sh
PROJECT=/path/to/your/project        # 目标工程根目录（仅上述两种情形需要）
bash "$SKILL_DIR"/scripts/detect_language.sh "$PROJECT"

# 也可以把本次要动的文件传进去 —— 任务级证据优先于工程整体
bash "$SKILL_DIR"/scripts/detect_language.sh "$PROJECT" src/foo.cpp src/foo.h
```

末三行是机器可读的：

```
STACK=cpp | csharp | mixed | unknown
PRIMARY=cpp | csharp
CONFIDENCE=high | low
```

判据优先级：本次涉及文件的后缀 → 工程级强标记（`.csproj` / `.vcxproj` / `CMakeLists.txt` / `vcpkg.json` / `global.json`）与 `.sln` 的**引用内容** → 后缀普查 → 无证据取默认 `cpp`。

> `.sln` 与 `Directory.Build.props` 是 C# 与 C++ **共用**的 MSBuild 载体，**存在性不能作判据**，只有 `.sln` 里引用的是 `.csproj` 还是 `.vcxproj` 才能消歧。
> 想确认这个探测器本身可靠：`bash "$SKILL_DIR"/scripts/detect_language.sh --self-test`（9 项断言）。

## 二、装到你的工程

### C++ 工程

```sh
PROJECT=/path/to/your/cpp-project

# 只读：检测 clang-format / clang-tidy、检查配置是否齐全（不写任何文件）
bash "$SKILL_DIR"/scripts/bootstrap_cpp_style.sh "$PROJECT" --check

# 安装配置：把 .clang-format / .clang-tidy 复制进工程（只新增，不覆盖已有文件）
bash "$SKILL_DIR"/scripts/bootstrap_cpp_style.sh "$PROJECT" --fix

# clang-tidy 依赖编译数据库（CMake 的 VS 生成器**不产出**该文件）
cmake -S "$PROJECT" -B "$PROJECT"/build -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
```

> ⚠️ **`.vcxproj`（MSBuild）工程的编译数据库路线未定。** 上面那条 CMake 命令只适用于 CMake 工程；
> 纯 MSBuild 工程走哪条路（CMake 化 / 手拼 `cl` 参数伪造数据库 / 试点「消费已有数据库」，需一台 Windows 实机验证）
> **尚未裁决**，在此之前 `.vcxproj` 工程的 clang-tidy 检查**按断链处理**（clang-format 不受影响，它不需要数据库）。

采基线用同目录的 `baseline_cpp_style.sh`：它把文件清单（NUL 分隔）先落盘、**先证明非空**，
条数按 NUL 字节数统计（`wc -l` 对这种清单**恒为 0**）；**清单为空 / 缺工具 / 缺编译数据库一律非零退出**，
不会给出一个假的「0 违规」。

> ⚠️ 两份模板都自带版本说明与核对命令。**要点是"必须真的让工具读一遍"，不是"看一眼觉得对"**：
> `clang-format -style=file -dump-config` 的 **stderr 必须为空** —— 选项名写错会让 clang-format
> **拒绝读取整个 `.clang-format`**（exit 1），此时该文件里**一条配置都不生效**。
> 两份模板已用 clang-format / clang-tidy **21.1.6** 实测；**换大版本要重跑**。自检第 17 节会在
> 检测到这两个工具时自动做这件事（检测不到则记 WARN —— 明确表示"没验"，而不是"通过"）。

### C#/.NET 工程

```sh
PROJECT=/path/to/your/cs-project

# 只读：检测 .NET SDK、检查配置是否齐全、采集违规基线（不写任何文件）
bash "$SKILL_DIR"/scripts/bootstrap_dotnet_style.sh "$PROJECT" --check

# 安装配置：把 .editorconfig / Directory.Build.props 复制进工程（只新增，不覆盖已有文件）
bash "$SKILL_DIR"/scripts/bootstrap_dotnet_style.sh "$PROJECT" --fix
```

脚本在检测不到 .NET SDK 时会**明确报错退出**，不会给出一个假的「0 违规」。

## 三、日常检查

```sh
# C++ —— 三件事，缺一不可
clang++ -std=c++20 -Wall -Wextra -Wconversion -Wshadow -Wold-style-cast \
        -Wnon-virtual-dtor -Wextra-semi -Wpedantic -Werror
clang-format --dry-run --Werror $(git ls-files '*.cpp' '*.h')
clang-tidy -p build/ $(git ls-files '*.cpp')

# C#/.NET —— 两件事
dotnet format --verify-no-changes    # 格式；只读，有未格式化文件即非 0 退出
dotnet build -warnaserror            # 语义与文档注释
```

两侧共有的三句提醒：

- **`-Wall -Wextra` 不等于严格集。** C++ 侧实测：非虚析构、C 风格转换、变量遮蔽都不在 `-Wall -Wextra` 里，必须显式加开关。
- **`clang-tidy` 的默认检查集极小**，且 `readability-identifier-naming` **启了但没配 `CheckOptions` 等于没查**。C# 侧同理：不开 `EnforceCodeStyleInBuild`，命令行构建默认完全不做 `IDExxxx` 分析。
- **「跑过工具」不等于达标。** 格式化器只修它支持自动修的部分 —— 命名、注释、魔法值、设计粒度它一律不碰。交付时要说明还剩什么。

## 四、覆盖范围

两侧各自独立，共用同一套方法论。

| | C/C++ | C#/.NET |
|---|---|---|
| 格式 | `.clang-format`（`BasedOnStyle` 七预设之一） | `.editorconfig` + `dotnet format` |
| 检查 | `clang-tidy` + 编译器警告 | Roslyn analyzers（`CAxxxx` / `IDExxxx`） |
| 命名 | `.clang-tidy` 的 `readability-identifier-naming` | `.editorconfig` 的 `dotnet_naming_rule` + `IDE1006` |
| 注释 | Doxygen（`@brief` / `@param`） | XML（`<summary>` / `<param>`） |
| 缺陷目录 | 38 类，编号 `CPP-01`–`CPP-38` | 33 类，编号 `#1`–`#33` |

**跨语言共享的判据层**：

- **设计目的** —— **改这份规范之前先读**：[`design-purpose.md`](references/design-purpose.md)。它写明本规范针对的是 **AI 编程**这一前提（作者是「给 AI 下指令的人 + 执行写作的 AI」），要治的是**编译通过、格式也合规，但读不懂、改不动**那一类病（命名生涩、注释复述签名、层次过深、体量偏大或偏碎、到处补防御性检查），并给出五个目标各自的**达成判据**。**重心在机器查不到的那一半** —— 机器规则是底线，不是目标。
  - **两侧正文 §0 各有一张「病灶索引表」**（六类 AI 病灶 × 机器能否拦住 × 本侧由哪一条对付它），它是**从"病"找条文的入口**；由自检第 20 节机械核对（两表行数一致、前两列逐行一致、第四列每行归属可检索）。
  - **审计层与规则层之间现在有通路**（这是目标 G5 的落点）：`audit/` 的 claims 直接接在**两侧正文附录 D** 上，并给「覆盖缺口」定了**专用口径** —— C 类的 `expected` 必须取自本文件（目的层），**不许写成"我觉得应该有"**；目的层里找不到依据的，只能记 `fix_target=none`。三条都由自检第 23 节机械核对。
- **命名判据** —— 只有一条：遮住定义、只看调用点，陌生人能否说出这行在做什么。**两侧的可接受词表各自独立**（C++ 的见 [`cpp-naming-antipatterns.md`](references/cpp-naming-antipatterns.md) §0，C# 的见 C# 正文 §3.3）。
- **设计粒度** —— 臃肿与「过度拆分」是同一个病的两个方向。拆分的正当理由、禁止拆的信号、类型级设计意图要求、评审清单见 [`design-granularity.md`](references/design-granularity.md)。**没有任何检查器能报「拆得太碎」**，这一项只能人工过那份清单。
- **防御性检查的边界** —— **只加在信任边界上**（外部输入：命令行 / 文件 / 网络 / IPC / 反序列化 / 第三方与系统 API 返回值 / 公共 API 入口）。边界之内对已由类型或契约保证的条件重复校验属缺陷（C++ 见 `CPP-38`，C# 见 `#33`）；每处校验都要能说出"拦的是哪个来源的哪种失效"，说不出就删。删掉边界上的校验则属**改行为**，必须单列提交。
- **变更纪律** —— 见 [`change-discipline.md`](references/change-discipline.md)。两条硬约束，**接入前请先看这一份**：
  - **整改不得改变原有行为。** 每处改动按 A（定义等价，可批量）/ B（上下文相关，须跑测试）/ C（必然改行为，须单列提交 + 告知 + 回归）定级。**把 C 类混进「纯格式提交」是最常见的越界。**
  - **不得为满足规则而增加代码。** 新增的每一行都必须被某条规则指名要求，删掉它就违反那条规则。规则是**合格判据**，不是**新增清单**。

**格式的共同立场**：人工排版与工具排版**同等有效**；格式化器不是提交前必做动作，钩子与 CI 只做只读检查，**不自动改写源码**。

**迁移纪律**：存量工程分档推进；**严禁把格式改动与逻辑改动放进同一个提交**；大范围整改前留回滚点。

完整规则见 [`SKILL.md`](SKILL.md)。

## 五、接入前请知悉

**两侧独立演进，版本号也独立**（由 skill 内部自检分别核对）：

- **C#/.NET 侧：v0.1.5** —— 该侧凡涉及**工具实际行为**的论断都标了 `[待实测]`，汇总在其正文附录 D（8 条），销项需要一台装了 .NET SDK 的机器。
- **C++ 侧：v0.1.7** —— **编译器警告类与格式化器 / `clang-tidy` 行为类均已实测**（Apple clang 21.0.0 + clang-format/clang-tidy **21.1.6**），逐条结论写在其正文附录 D；11 条待实测**已销 9 条**，只剩 D8（需 Doxygen）与 D10（需查 WDK 文档）。（版本号本应记 v0.1.3，为与 C#/.NET 侧区分而跳号。）
  - ⚠️ **v0.1.7（E3 + E2，规则与阈值均未变）**：附录 D 原来叫「**待实测清单**」，而表里 11 条已有 9 条销项 —— **标题与内容自相矛盾**。改为「**验证状态与待实测清单**」并按**已销 / 未销**分段，段标题自带条数（由自检第 9 节核对，正文别处不另抄一份）。同时自检新增**第 22 节**：正文里每一处 `§X.Y` 必须指得到真实标题，否则锚点改名时会**静默指空**。
  - ⚠️ **v0.1.6（D-1 / D-2 落地）**：**认知复杂度降为 SHOULD** 并标 `[待工程校准]` —— 实测它的阈值**就是 `clang-tidy` 的出厂默认值**，本工程从未选择过它，也没有任何标准规定它。⇒ 元规则随之补上**第二个条件**：MUST 必须「可检查 **且** 有依据」，缺任一项降 SHOULD。另外新增 `CPP-38` / `#33`（防御性检查按信任边界分层）与**两侧 §0 的病灶索引表**，并把散在正文 / 判据层 / 摘要里的**阈值副本一律改为指针**（取值只写在 `assets/clang-tidy`）。
  - ⚠️ v0.1.5 本身**未改任何规则**：只把跨语言目的层 [`design-purpose.md`](references/design-purpose.md) 接进两侧（各自 §0 末尾加指针）。它此前**从未被写进规范本体** —— 两侧 §0 只写了"人类团队选不出来"，那是次生原因。
  - ⚠️ 销项过程中查出并修掉了两份模板的 **3 个真实缺陷**（会让配置**静默全失效**或**部分失效**）：`EndOfLine` 键名、`Checks` 折叠块标量、两个不存在的 `CheckOptions` 键。**这也说明"模板写好了"与"模板真的生效"是两件事。**
  - ⚠️ **`clang-tidy` 的 PyPI 构建不含 `misra-*` 检查**（实测命中 0 条）⇒ 领域合规里的 MISRA 部分不能靠它机械化。

其他须知：

- **本版尚未在任何真实工程上完整跑过一遍。** 首次接入请先在小范围上验证，不要直接对全仓执行整改。
- **接入存量工程前先读 [`change-discipline.md`](references/change-discipline.md)。** 整改**不得改变原有行为**，且**不得为满足规则而增加代码** —— 这两条比「把代码改整齐」重要得多。
- **两侧的版权边界相反**：C#/.NET 侧的权威是书与 Learn 页面，**不内置快照**、不提供逐字引文校验；C++ 侧的主要权威（C++ Core Guidelines）是 MIT-style 许可，**允许内置快照与逐字校验，但尚未做**。
- **不要凭「不眼熟」要求重命名。** 两侧都有明确的可接受词表，把它们当缺陷只会制造 diff 噪音。

## 六、仓库里还有什么

| 路径 | 内容 |
|---|---|
| `SKILL.md`、`references/`、`assets/`、`scripts/` | 规范本体：入口、两侧正文、缺陷目录、命名词典、粒度判据、变更纪律、配置模板、工具脚本 |
| `cpp/` | 独立的 Windows C++（clang-tidy）提示工具试点，**默认只报告、不改源码**。见 [`cpp/README.md`](cpp/README.md) |
| `audit/` | 规范自身的**真机审计包**（被测物是**规范**，不是被审代码）：五道门 + A–F 分类，另有给**覆盖缺口**专用的 **C 类口径**（`expected` 取自目的层）。`templates/claims-checklist.tsv` 共 31 条断言，其中 **19 条直接接在两侧正文附录 D 上**——这是「审计层能说出规则层缺了哪几条」的实现 |

> 别把探测器跑在本仓库自己身上 —— 它含 C++ 测试夹具，会被判成 `cpp`。那反映的是仓库内容，不是规范覆盖的语言。

## 许可

原创内容以 **MIT** 发布，见 [`LICENSE`](LICENSE)。
