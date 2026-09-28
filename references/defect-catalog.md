# C#/.NET 缺陷目录与检测方法

> 版本：v0.1.1（首稿 + 严重性表述更正）· 2026-09-14 · 配套 `csharp-coding-standards.md`
> **本文件的用途**：把「代码不规范」拆成可逐类排查的清单，每类给出检测方式、整改动作与典型样本。
> 标 `[待实测]` 的条目尚未在装有 .NET SDK 的机器上验证，见正文附录 D。

---

## 怎么用

排查面**不要停留在「格式 + 命名」两项**。Swift 侧的教训是：只在命名/分号/花括号上打转，会漏掉体量、复杂度、魔法值、设计建模等更贵的问题。按下面的三档逐类过一遍，每类给出数字，再决定整改优先级。

## 分档依据

| 档 | 含义 | 处理方式 |
|---|---|---|
| **一档：机器可检出** | 有内置分析器或格式化器覆盖 | 进 CI，给出数字，机械修复 |
| **二档：可 grep / 可定量** | 没有专门规则，但能用模式匹配或脚本统计 | 人工确认后整改，必要时自建检查脚本 |
| **三档：纯人工评审** | 只能靠人判断 | 进评审清单，不计入 CI 门槛 |

---

## 一档：机器可检出

| # | 缺陷 | 规则 / 配置 | 整改动作 | 典型样本 |
|---|---|---|---|---|
| 1 | 格式不合规（大括号、空格、换行、行尾空白） | `IDE0055`；`csharp_prefer_braces`、`csharp_new_line_before_open_brace` | `dotnet format` | `if (x) return;`（该换行的没换） |
| 2 | 命名不合规 | `IDE1006` + `.editorconfig` 的 `dotnet_naming_rule/symbols/style` | 按正文 §3.4/3.5 改 | `private string connStr;`（应 `_connectionString`） |
| 3 | 未使用的 `using` | `IDE0005` | 删除 | 文件顶部残留 `using System.Linq;` 而全文未用 |
| 4 | 文件头缺失 / 不规范 | `IDE0073` + `file_header_template` | 补文件头模板 | 新文件缺版权/许可头 |
| 5 | 公开 API 缺文档注释 | `CS1591`（需 `GenerateDocumentationFile=true`） | 补 XML 注释 | `public void Refund(...)` 无 `<summary>` |
| 6 | 可空性错误 | `CS8600`–`CS8629` 系列（如 `CS8602` 解引用可能为 null） | 加判空或修正可空标注 | `order.Customer.Name` 而 `Customer` 可空 |
| 7 | 吞异常 | `CA1031` | 只捕获能处理的异常类型 | `catch (Exception) { }` |
| 8 | 未释放 `IDisposable` | `CA2000` | 改 `using` | `var fs = new FileStream(...);` 无 `using` |
| 9 | 公开字段 | `CA1051` | 改为属性 | `public string Name;` |
| 10 | 属性返回数组 | `CA1819` | 返回 `IReadOnlyList<T>` | `public byte[] Data { get; }` |
| 11 | public 标识符含下划线 | `CA1707` | 改命名 | `public void Do_Work()` |
| 12 | 常量数组作为实参（每次都分配） | `CA1861` | 改 `static readonly` | `Check(new[] { 1, 2, 3 })` |
| 13 | 不安全随机数 / SQL 注入 | `CA5394`、`CA2100` | 换 `RandomNumberGenerator` / 参数化查询 | `new Random()` 用于生成令牌 |
| 14 | 成员之间缺分隔空行 | **无 Roslyn 内置规则**；StyleCop `SA1516` | 补空行 | 两个相邻 `void Foo() { }` 紧贴 |
| 15 | 冗余抑制（`#pragma` / `SuppressMessage` 已无必要） | `IDE0079` | 删除 | 抑制的规则其实早已不触发 |

**采集基线**：

```bash
dotnet build -warnaserror 2>&1 | grep -oE '\b(CA|IDE|CS|SA)[0-9]{4}\b' | sort | uniq -c | sort -rn
dotnet format --verify-no-changes            # 只读：有未格式化文件则退出码非 0
```

`[待实测]` `CA1502`（圈复杂度）默认未必启用，启用方式与阈值配置键名须实测；`dotnet format --verify-no-changes` 是否覆盖命名类规则也须实测（若只覆盖格式，则命名必须靠 `IDE1006` 出现在构建输出里）。

---

## 二档：可 grep / 可定量

这些**没有专门规则**，但能用模式匹配定量。命令里刻意用 `grep -E` 而非 `\|`（BSD grep 不支持 BRE 交替，会静默退化成搜字面量）。

| # | 缺陷 | 检测命令（在工程根执行） | 整改动作 |
|---|---|---|---|
| 16 | `async void`（事件处理器除外） | `grep -rnE '\basync +void\b' --include='*.cs' .` | 改 `async Task` |
| 17 | 同步阻塞异步 | `grep -rnE '\.(Result|Wait)\(\)|GetAwaiter\(\)\.GetResult\(\)' --include='*.cs' .` | 全链路改 async/await |
| 18 | null-forgiving 滥用 | `grep -rnE '[A-Za-z0-9_)\]]!' --include='*.cs' .`（需排除 `!=`） | 逐个确认并加注释说明理由 |
| 19 | 一行多条语句 | `grep -rnE ';[^;/]*;' --include='*.cs' .`（`for(...)` 会误报，需人工过滤） | 拆行 |
| 20 | 空 catch / 空 finally | `grep -rnEA1 'catch' --include='*.cs' . \| grep -E '^\s*\{\s*\}\s*$'` | 补处理或删除 |
| 21 | 测试中的 `Thread.Sleep` | `grep -rnE 'Thread\.Sleep' --include='*.cs' .` | 改 `await Task.Delay` 或轮询断言 |
| 22 | `TODO` / `FIXME` / `HACK` 堆积 | `grep -rnE '(TODO|FIXME|HACK)' --include='*.cs' . \| wc -l` | 分类：能做的建任务，做不了的删除 |
| 23 | 魔法字符串/数字候选 | `grep -rnE '"([^"]{2,})"' --include='*.cs' .` 后按出现次数排序 | 出现 ≥ 2 次的提取常量 |
| 24 | `Console.WriteLine` 残留在生产代码 | `grep -rnE 'Console\.(Write|Read)Line' --include='*.cs' src/` | 换日志框架或删除 |

---

## 三档：纯人工评审

| # | 缺陷 | 判据 |
|---|---|---|
| 25 | **命名读不懂** | 遮住定义只看调用点，陌生人能否说出这行在做什么（正文 §3.1）。只针对三类：生僻词、自造缩写与单字母、对象/返回值无从判断 |
| 26 | 函数过长 / 类型过大 | 无内置规则。函数 > 60 行、类型 > 300 行须说明理由 |
| 27 | 参数过多 | 无内置规则。> 6 个须说明理由；布尔参数优先改具名实参或拆分 |
| 28 | 布尔参数的可读性 | 调用点出现裸 `true`/`false` 即改具名实参 |
| 29 | 元组泛滥 | 公开 API 返回 > 2 元素必须定义具名类型 |
| 30 | 数据建模失当 | 用 `string` 承载枚举语义、用 `dynamic`/`object` 逃避类型、DTO 与领域模型混用 |
| 31 | 注释复述代码而非说明契约 | 注释应说明「为什么」与「什么条件下会抛异常」，不写 `// 给 count 加一` |
| 32 | 职责划分 | 单个类型承担多个变化原因；`XxxManager` 成为杂物间 |

---

## 排查顺序建议

1. **先采基线，不改代码**。同时跑一档的 `dotnet build -warnaserror` 与 `dotnet format --verify-no-changes`，得到「N 处 / M 文件」。
2. **确认配置真的生效**。这一步不能省：若配置静默失效，基线会是假的「0 违规」。验证方法见「已知漏检与陷阱」第 2 条。
3. **一次只开一档规则**（先正确性 + 安全，再性能 + 可靠性，最后样式），每开一档跑一次基线 —— 否则数字混在一起无法归因。
4. **格式类机械修复与逻辑改动分两个提交**（正文 §8）。
5. **命名 / 设计 / 注释类走评审**，不塞进自动修复流程，也不与格式提交混合。

---

## 已知漏检与陷阱

不写清楚这些，就会把「工具没报」误当成「代码没问题」。

1. **`dotnet format` 只修它支持自动修的部分。** 命名、文档、魔法值、设计约束它不碰。跑过一次不等于达标 —— 必须明确告知还剩什么。
2. **配置静默失效（最危险）。** `.editorconfig` 不在 `root = true` 的层级链上 → 不生效；`AnalysisLevel` / `EnableNETAnalyzers` 未开 → 规则不参与；**选项式** severity（`xxx = value:severity`）在 .NET 8 及更早**构建时不被编译器识别**，只有 IDE 报（构建期强制**必须**用规则 ID 式 `dotnet_diagnostic.<ID>.severity`，且 `EnforceCodeStyleInBuild=true`）；而该开关不为 `true` 时，**命令行构建默认完全不做 IDExxxx 分析**。**这些失效的表现都是「报 0 违规」** —— 与 Swift 侧 `.swiftlint.yml` 的 `included` 指向不存在目录时报 0 违规是同一类失效。验证方法：往代码里**故意塞一处已知违规**，看检查器是否报出来；不报就是配置无效，基线不可信。
3. **两套工具重叠会双报。** 引入 StyleCop 后，`SA1xxx` 与 `IDE0055` 会同时报同一处格式问题。必须同时提交「关闭清单」。
4. **`IDE0005` 在构建期是否上报，取决于 `GenerateDocumentationFile`。** `[待实测]` 没有输出不等于没有未使用的 using。
5. **成员之间缺空行这类规则，工具链默认查不出。** 不做「故意塞违规」的验证，就会长期漏检。
6. **`grep` 的正则误报要有预期。** 上表第 19 项的 `for (...)`、第 18 项的 `!=` 都会误报，数字只能当候选量而非结论。
7. **只看退出码会骗人。** `dotnet format` 的成功退出不代表合规（要用 `--verify-no-changes`）；这一点与 Swift 侧「补丁写入被静默拦下却返回 0」同源 —— **核验副作用，不核验退出码**。
