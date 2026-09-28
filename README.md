# windows-coding-standards

Windows 平台（当前目标栈 **C#/.NET**）的编码规范 skill —— 为你的工程提供统一的命名、格式、注释与语言约束标准，
外加一套可直接落地的检查工具链（`.editorconfig` + Roslyn analyzers + `dotnet format`）。

装上之后对 C#/.NET 代码**默认生效**：不需要显式点名这个 skill，也不需要说「请按规范来」。

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

## 二、装到你的工程

```sh
PROJECT=/path/to/your/project        # 改成你的 C# 工程根目录

# 只读：检测 .NET SDK、检查配置是否齐全、采集违规基线（不写任何文件）
bash "$SKILL_DIR"/scripts/bootstrap_dotnet_style.sh "$PROJECT" --check

# 安装配置：把 .editorconfig / Directory.Build.props 复制进工程（只新增，不覆盖已有文件）
bash "$SKILL_DIR"/scripts/bootstrap_dotnet_style.sh "$PROJECT" --fix
```

脚本在检测不到 .NET SDK 时会**明确报错退出**，不会给出一个假的「0 违规」。

## 三、日常检查

```sh
dotnet format --verify-no-changes    # 格式；只读，有未格式化文件即非 0 退出
dotnet build -warnaserror            # 语义与文档注释
```

> `dotnet format` 只修它支持自动修的部分 —— 命名、文档注释、魔法值、设计约束它一律不碰。
> **「跑过工具」不等于达标**，交付时要说明还剩什么。

## 四、覆盖范围

- **命名** —— 判据只有一条：遮住定义、只看调用点，陌生人能否说出这行在做什么
- **格式** —— 人工排版与工具排版**同等有效**，不会强制用格式化器改写你的手写断行
- **注释** —— 什么该写，以及什么算「复述成员名的垃圾注释」
- **语言与设计约束** —— 可空性、`async`、`IDisposable`、魔法值、体量上限
- **缺陷目录** —— 32 类，按「机器可检出 / 可 grep 定量 / 纯人工评审」三档分开处理，每类都注明可检查性
- **迁移纪律** —— 存量工程分档推进；严禁把格式改动与逻辑改动放进同一个提交

完整规则见 [`SKILL.md`](SKILL.md)。逐条判据、检测命令与整改动作见
[`references/csharp-coding-standards.md`](references/csharp-coding-standards.md) 与
[`references/defect-catalog.md`](references/defect-catalog.md)。

## 五、接入前请知悉

- 当前为 **v0.1.1，尚未在任何真实工程上完整跑过一遍**。
- 正文中凡涉及**工具实际行为**的论断都标了 `[待实测]`，汇总在正文**附录 D**（8 条）。
  这些条目在销项之前**不要当作结论使用**；销项需要一台装了 .NET SDK 的机器。
- 本 skill **不内置**官方来源的原文快照（版权原因），因此不提供逐字引文校验。

## 六、仓库里还有什么

| 路径 | 内容 |
|---|---|
| `SKILL.md`、`references/`、`assets/`、`scripts/` | 规范本体：入口、正文、缺陷目录、配置模板、工具脚本 |
| `cpp/` | 独立的 Windows C++（clang-tidy）提示工具试点，**默认只报告、不改源码**。见 [`cpp/README.md`](cpp/README.md) |
| `audit/` | 规范自身的审计清单与测试夹具 |

## 许可

原创内容以 **MIT** 发布，见 [`LICENSE`](LICENSE)。
