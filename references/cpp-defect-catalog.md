# C++ 缺陷目录与检测方法

> 版本：v0.1.4（随正文同步版本号，**条目未变**）· 2026-09-28 · 配套 `cpp-coding-standards.md`
> **本文件只服务 C++。** C#/.NET 侧见 `csharp-defect-catalog.md`。
> **编号体系为 `CPP-xx`，与 C# 侧的 `#xx` 不通用** —— 两侧条目**不得互相引用、不得交叉套用**（见「与 C#/.NET 侧的隔离」）。

---

## 怎么用

排查面**不要停留在「格式 + 命名」两项**。按下面的三档逐类过一遍，每类给出数字，再决定整改优先级。

默认检查集在这三档里的分布极不均匀：**用 `clang-tidy` 出厂配置跑一遍，一档能查出的不到一半，二档几乎为零**。所以「跑过 clang-tidy」这句话本身不构成任何结论 —— 必须说明**用的是哪份 `.clang-tidy`**。

## 分档依据

| 档 | 含义 | 处理方式 |
|---|---|---|
| **一档：机器可检出** | 有编译器警告、clang-tidy 检查或 clang-format 覆盖 | 进 CI，给出数字，机械修复 |
| **二档：可 grep / 可定量** | 没有默认开启的规则，但能用模式匹配或脚本统计 | 人工确认后整改，必要时自建检查脚本 |
| **三档：纯人工评审** | 只能靠人判断 | 进评审清单，**不计入 CI 门槛** |

> **档位与「是否默认启用」是两件事。** 一档里的多条检查（如 `readability-function-size`、`cppcoreguidelines-avoid-non-const-global-variables`）在 clang-tidy 出厂配置下**默认关闭** —— 它们属于一档，但**必须先配置**（见 `cpp-coding-standards.md` §7.3）。

> ⚠️ **一档 ≠ 可以无脑批改。** 下表「整改动作」列里的动作，有些**必然改变行为**：
> 删空 `catch`、加 `explicit`、加虚析构（**ABI 变更**）、加 `noexcept`、调整成员声明顺序、重排 `#include`。
> 动手前按 `change-discipline.md` §1.2 给每处定级（A / B / C），C 类必须单列提交、告知用户、有回归测试。
> **"机器能查出来"和"改了不会有后果"是两件事。**

---

## 一档：机器可检出

| # | 缺陷 | 检查 / 开关 | 整改动作 | 典型样本 |
|---|---|---|---|---|
| CPP-01 | 格式不合规（大括号、空格、换行、成员间空行） | `clang-format`（`.clang-format` 唯一权威） | `clang-format -i`（须获准，且单独提交） | `if (x) { a(); b(); }` 压在一行 |
| CPP-02 | 命名不合规 | `readability-identifier-naming` + **必须配 `CheckOptions`** | 按配置的 case/prefix/suffix 改 | `int Count;`（应 `count`，若走 Microsoft 路线的局部变量规则） |
| CPP-03 | 多态基类非虚析构 | `-Wnon-virtual-dtor` ✅**已实测** | `virtual ~Base() = default;` | `struct B { virtual void Run(); ~B(){} };` |
| CPP-04 | C 风格转换 | `-Wold-style-cast` ✅**已实测** | 改 `static_cast` / `const_cast` / `reinterpret_cast` | `int n = (int)x;` |
| CPP-05 | 变量遮蔽 | `-Wshadow` ✅**已实测** | 重命名内层变量 | 内层块 `int v = 3;` 遮蔽外层参数 `v` |
| CPP-06 | 隐式窄化 / 符号转换 | `-Wconversion`（含 `-Wfloat-conversion`、`-Wsign-conversion`）✅**已实测** | 显式转换并说明理由，或改类型 | `int a = d;`（`d` 为 `double`）；`unsigned u = -1;` |
| CPP-07 | 函数外多余分号 | `-Wextra-semi` ✅**已实测** | 删除 | `void f(){};` |
| CPP-08 | 未使用变量 / 参数 | `-Wall -Wextra` ✅**已实测**；参数用 `misc-unused-parameters` | 删除，或 `[[maybe_unused]]` 并注释理由 | `int unused;` |
| CPP-09 | 内存泄漏、空指针解引用、资源未释放 | `clang-analyzer-*`（`clang --analyze` ✅**已实测可报内存泄漏**） | 改 RAII / 智能指针 | `int* p = (int*)malloc(4); *p = 1;`（未 free） |
| CPP-10 | 非 const 全局变量 | `cppcoreguidelines-avoid-non-const-global-variables` ⚠️**编译器不查，已实测** | 改为局部、`const`、或函数内静态并说明 | `int g_counter = 0;` |
| CPP-11 | 无作用域枚举 | `modernize-use-enum-class` ⚠️**编译器不查，已实测** | 改 `enum class` | `enum Color { RED, GREEN };` |
| CPP-12 | 虚函数缺 `override` / `final` | `modernize-use-override` | 补 `override` | 派生类 `void Run();`（覆写了基类虚函数） |
| CPP-13 | 用 `NULL` / `0` 当空指针 | `modernize-use-nullptr` | 改 `nullptr` | `if (p == NULL)` |
| CPP-14 | `reinterpret_cast` / `const_cast` 滥用 | `cppcoreguidelines-pro-type-reinterpret-cast`、`-pro-type-const-cast` | 重设计接口；确需则注释理由 | 把 `const T*` 强转掉 |
| CPP-15 | 变量未初始化 | `cppcoreguidelines-init-variables` | 声明处初始化 | `int n;` 之后才赋值 |
| CPP-16 | 对象切片 | `cppcoreguidelines-slicing` | 传引用 / 指针，或改设计 | `void f(Base b);` 传 `Derived` |
| CPP-17 | 移动后使用 | `bugprone-use-after-move` | 调整顺序或删除 | `f(std::move(s)); use(s);` |
| CPP-18 | 头文件里定义非 `inline` 函数/变量 | `misc-definitions-in-headers` | 移入 `.cpp` 或标 `inline` | 头文件里写 `int Foo() { … }` |
| CPP-19 | 抛异常 / 捕获异常的不当用法 | `misc-throw-by-value-catch-by-reference`、`cert-err60-cpp` | 按值抛、按 `const&` 捕 | `catch (std::exception e)` |
| CPP-20 | 危险的隐式 bool 转换 | `readability-implicit-bool-conversion` ⚠️**默认关闭** | 显式比较；确需则豁免 | `if (ptr)` / `if (i)` |

---

## 二档：可 grep / 可定量

| # | 缺陷 | 定量方式 | 整改动作 | 典型样本 |
|---|---|---|---|---|
| CPP-21 | 函数过长 | `readability-function-size`（`LineThreshold`，**默认关闭**） | 拆分；拆分须有独立变化原因（见 CPP-33） | 200 行的 `Process()` |
| CPP-22 | 函数认知复杂度过高 | `readability-function-cognitive-complexity`（阈值 25） | 提取早返回、拆分支 | 多层嵌套 `if` + 循环 |
| CPP-23 | 参数过多 | `readability-function-size` 的 `ParameterThreshold` | 引入参数对象 | 8 个参数的构造函数 |
| CPP-24 | 魔法数字 | `readability-magic-numbers`（**默认关闭**，误报高） | 提取具名常量 | `if (retries == 3)` |
| CPP-25 | 注释掉的代码块 | `grep -rnE '^\s*//\s*(if\|for\|while\|return\|[A-Za-z_]+\(.*\);)'` | 删除（版本控制里有历史） | 连续 3 行注释掉的实现 |
| CPP-26 | 裸 `new` / `delete` | `grep -rnE '\bnew\b\|\bdelete\b'` | 改 `make_unique` / `make_shared` / 容器 | `auto p = new Widget();` |
| CPP-27 | 头文件里的 `using namespace` | `grep -rn 'using namespace' --include='*.h'` | 移入 `.cpp`，或改用限定名 | 头文件顶部 `using namespace std;` |
| CPP-28 | 缺失 include guard | `grep -L '#pragma once' $(git ls-files '*.h')` | 统一加 `#pragma once` **或**传统 guard（全工程一种） | 新头文件两种都没有 |
| CPP-29 | 宏用于本可用函数/常量表达的场景 | `grep -rnE '^\s*#define\s+[A-Za-z_]+\('` | 改 `constexpr` / `inline` 函数 | `#define MAX(a,b) ((a)>(b)?(a):(b))` |
| CPP-30 | 类型行数 / 单文件类型数 | 无专用工具，脚本统计行数与类型声明数 | 按 CPP-33 判断是否该拆 | 800 行的类定义 |

> **本档的存在本身就是一条结论**：这些条目**没有默认开启的检查器**。要用它们，必须自己把阈值写进 `.clang-tidy` 的 `CheckOptions`，或自建脚本 —— 只说「我们查过了」不成立。

---

## 三档：纯人工评审

| # | 缺陷 | 判据 | 为什么机器查不出 |
|---|---|---|---|
| CPP-31 | 命名生涩难懂 | 遮住定义只看调用点，陌生人能否说出这行在做什么（只针对生僻词 / 自造缩写 / 对象无从判断） | 语义判断；工具只能查大小写与长度 |
| CPP-32 | 注释同义复述 | 删掉注释是否损失信息 | 需要理解代码语义 |
| CPP-33 | 缺类型级设计意图 | 类型声明处是否说明「为何存在 / 与谁协作 / 不负责什么」 | 无工具 |
| CPP-34 | 过度拆分 / 碎片化 | 拆分出的每个单位是否有**独立的、能说出口的变化原因** | 无工具；且**只设上限不设下限时，机器不会报"太碎"** |
| CPP-35 | 所有权与生命周期表达不清 | 资源由谁持有、何时释放、能否跨线程 —— 是否可从类型与注释推出 | 需要设计意图 |
| CPP-36 | 单位与前置条件未声明 | 参数是否带单位（`timeoutMs` / `Speed`）；前置条件是否写明 | 语义 |
| CPP-37 | 职责蔓延 | 类型的成员是否都服务于同一个单一职责 | 语义 |

---

## 与 C#/.NET 侧的隔离（**禁止交叉套用**）

排查 C++ 代码时，**不要**引用或套用下列 C# 侧的东西：

| C# 侧的东西 | 为什么不能套到 C++ |
|---|---|
| `IDE1006`、`CAxxxx`、`SAxxxx` 等检查 ID | C++ 侧的检查 ID 是 `bugprone-*` / `cppcoreguidelines-*` / `readability-*` / `performance-*` / `modernize-*` / `cert-*`，**两套 ID 空间无交集** |
| `.editorconfig` 的 `dotnet_naming_rule` | C++ 的命名权威是 `.clang-tidy` 的 `readability-identifier-naming` |
| `csharp_indent_switch_labels = false`（`case` 不缩进） | C++ 侧由 `.clang-format` 的 `IndentCaseLabels` 决定，**取值另定** |
| `_camelCase` / `s_camelCase` / `I` 前缀 | C++ 主流是 `m_camelCase`（Microsoft 路线）或 `snake_case_`（Google 路线），**无 `s_` 惯例、无 `I` 前缀** |
| XML 注释（`<summary>`） | C++ 用 Doxygen（`@brief` / `@param`） |
| `IDisposable` / `using` | C++ 用 RAII / 析构函数 / 智能指针 |
| `CS1591`（公开成员必须有文档） | C++ **无对等开关**（见 `cpp-coding-standards.md` §6.2）；本侧只能是 SHOULD + 人工评审 |
| `dotnet format` / `dotnet build -warnaserror` | C++ 侧是 `clang-format` / `clang++ -Werror` / `clang-tidy` |

**判据**：**如果你在排查 C++ 代码时打出的命令里有 `dotnet`，那你已经跑错了一侧。**

本目录的三档分类**结构**与 C# 侧同源（机器 / 可 grep / 人工），这是**方法论层的共享**；但**每一类的内容、编号、检查 ID 一律独立**。方法论共享 ≠ 条目共享。

---

## 排查顺序建议

1. **先确认配置文件存在且非空** —— `.clang-format` 与 `.clang-tidy`。缺任何一个，对应档位的结论**都不成立**。
   特别是 `.clang-tidy`：`Checks` 为空 → 什么都没查；`Checks` 有 `readability-identifier-naming` 但 `CheckOptions` 为空 → **命名仍等于没查**（官方明说"空配置实际关闭该检查"）。
2. **确认检查器真的在工作**：故意留一处已知违规（如 `int n = (int)d;`），看是否报 `-Wold-style-cast` / `-Wfloat-conversion`。不报 = 配置无效，**本次所有"0 违规"作废**。
3. 按一档 → 二档 → 三档推进，**每档给出数字**，不要混在一起。
4. 一档里**先开正确性与安全**（`bugprone-*`、`clang-analyzer-*`、`cppcoreguidelines-*` 的内存与所有权部分），再开现代写法与性能，最后开可读性。
5. 报告时区分「可机械修复」与「需评审」两类。

---

## 已知漏检与陷阱（C++ 侧）

1. **clang-tidy 默认集太小 —— 本侧最大的假绿来源。**
   出厂配置下能查出的东西很少。**不显式声明 `Checks`，跑绿不构成任何结论。** 业界通行做法是 `-*` 关全部再逐簇开（见 `cpp-coding-standards.md` §7.3）。

2. **`readability-identifier-naming` 空配置 = 关闭。**
   官方原文：*"an empty config effectively disables it."* 启了检查不配选项，是最隐蔽的一种"以为查过了"。

3. **显式 C 风格转换会绕过 `-Wconversion`（**已实测**）。**
   `int b = (int)x;` 不报窄化，`int a = x;` 才报。→ `-Wold-style-cast` 与 `-Wconversion` 必须同时开。

4. **`-Wall -Wextra` 不包含严格集（**已实测**）。**
   实测基线只报 `unused variable`；非虚析构、C 风格转换、变量遮蔽都要显式加开关才报。

5. **编译器完全不查设计约束（**已实测**）。**
   非 const 全局变量、无作用域枚举在 clang 下零警告 —— 这两条只能靠 clang-tidy。

6. **模板代码的检查覆盖差。** 未实例化的模板成员通常**不会被检查**（编译器与 clang-tidy 都如此）。模板密集的代码库，检查覆盖率会被高估。

7. **跨翻译单元的问题查不出。** `clang-tidy` 按单个 TU 分析；跨 TU 的问题（如 ODR 违反、跨文件资源泄漏）需要 CodeQL / Coverity 这类能做全程序分析的工具。

8. **`#include` 卫生需要单独工具。** 缺失 / 多余的 include 要靠 IWYU（`include-what-you-use`）或 `misc-include-cleaner` —— **本工程尚未纳入**，不要声称查过。

9. **生成代码必须豁免。** 代码生成产物（protobuf、COM 代理/存根、IDL 输出）不得进检查范围，否则数字会被无意义地放大。豁免方式须落在配置里（`HeaderFilterRegex` / 目录级 `.clang-tidy`），**不能靠"评审时忽略"**。

10. **`readability-identifier-naming` 在虚函数覆写点不上报。**
    官方说明：虚方法的命名问题在**基类处**报告（覆写点无法就地修）。同理适用于 CRTP 这类伪覆写。**这是设计如此，不是漏检** —— 别把它当 bug 报。

11. **MSVC / clang-cl 与 clang 的开关不是同一组。** `-Wall -Wextra -Wconversion` 在 MSVC 侧对应 `/W4` 等，但**并非一一对应**。同一份 `.clang-tidy` 可以共享，但**编译器开关必须分别配置**，不要互抄。
