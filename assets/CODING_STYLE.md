# CODING_STYLE —— {{PROJECT_NAME}} 工程编码规范入口

> 本文件是**工程级入口**（模板复制后填空），不是规范本体。
> 规范正身是 skill **windows-coding-standards**（`SKILL.md` + 其 `references/` 下的正文与判据文件）。
> 本文件只回答三件事：本工程用哪一侧、哪些是本工程追加的补充、例外怎么登记。
> **工程只能追加补充，不能放宽通用规则。**

## 1. 本工程适用的侧

- 默认侧：**C++**（Windows 平台默认）；C#/.NET 侧仅在涉及 .NET 文件时适用。
- 语言按**本次实际涉及的文件**判定（后缀表见 skill `SKILL.md`），不由仓库整体决定。
- 两套规则互不套用 —— 给 C++ 代码跑 `dotnet format` = 已经跑错了一侧。

## 2. 判据文件（只列指针，不复制取值）

| 主题 | 权威出处 |
|---|---|
| 目的（治哪六类病） | skill `references/design-purpose.md` |
| 变更纪律（不改行为 / 不堆代码） | skill `references/change-discipline.md` |
| 粒度判据（臃肿 / 过度拆分） | skill `references/design-granularity.md` |
| 接入与整改流程 | skill `references/remediation-playbook.md` |
| C++ 正文 / 缺陷目录 | skill `references/cpp-coding-standards.md` / `cpp-defect-catalog.md` |
| C# 正文 / 缺陷目录 | skill `references/csharp-coding-standards.md` / `csharp-defect-catalog.md` |
| 配置取值（唯一权威） | skill `assets/`（`clang-format` / `clang-tidy` / `editorconfig` / `Directory.Build.props`） |

## 3. 本工程追加的补充（允许；不得与通用规则冲突）

<!-- 逐条写：补充内容 / 动因 / 提出日期。没有就删掉本节内容。 -->

- （无）

## 4. 本工程的例外登记

<!-- 例外必须写：位置 / 豁免的条款 / 理由 / 复审日期。局部豁免用工具的官方豁免语法
     （C++: // clang-format off / NOLINT；C#: #pragma warning disable / // format: off），
     并保持"最小范围"。没有就删掉本节内容。 -->

- （无）

## 5. 门禁（与 skill 正文一致；此处只放命令骨架）

```sh
# C++ 侧（格式 → 语义 → 静态）
clang-format --dry-run --Werror <files>
c++ -std=c++17 -Werror <skill 正文 §5.1 开关集> -c <files>
clang-tidy -p build/ <files>

# C# 侧
dotnet format --verify-no-changes
dotnet build -warnaserror
```

> 完整开关集与等级见 skill 两侧正文；**此处不得复制阈值数值** —— 取值一律以上表指针为准。
