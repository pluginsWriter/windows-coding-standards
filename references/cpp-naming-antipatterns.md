# C++ 生涩命名反模式词典

> 版本：v0.1.0 · 2026-09-28 · 配合 `cpp-coding-standards.md` §4 使用
> **本文件只服务 C++。** C#/.NET 侧的命名判据见 `csharp-coding-standards.md` §3。
> 两侧的**可接受词表与反模式清单不同**（C++ 有类型编码、`Impl` 等独有问题，且没有 `Async` 后缀这类语言级约定）。

---

## 0. 先明确「不查什么」（**读这一节比读后面所有节都重要**）

命名判据只有一条（正文 §4.1）：

> **遮住定义，只看调用点，一个不熟悉本模块的同事能否说出这行在做什么？**

**下列写法明确可以接受，不得以「命名生涩」为由要求重命名**：

**通用常用词**：`normalize`、`reserve`、`perform`、`resolve`、`process`、`validate`、`snapshot`、`drain`、`flush`、`commit`、`rollback`、`dispatch`、`schedule`、`acquire`、`release`、`enumerate`

**C++ 生态高频缩写**：`buf`、`len`、`idx`、`cnt`、`cfg`、`ctx`、`ptr`、`ref`、`src`、`dst`、`argc`、`argv`、`elem`、`iter`、`impl`、`init`、`deinit`、`alloc`、`dealloc`、`attr`、`params`、`ret`、`err`、`fd`、`hdl`、`cb`（callback）、`pos`、`cap`（capacity）

**固定技术缩写**：`URL`、`ID`、`USB`、`HID`、`HTTP`、`JSON`、`UUID`、`API`、`ABI`、`CPU`、`GPU`、`IO`、`IRQ`、`DMA`、`DLL`、`PE`、`COM`、`RAII`

**被语言惯例豁免的短名**：
- **循环下标 `i` / `j` / `k`** —— 作用域 ≤ 3 行的循环计数器，Core Guidelines `NL.7` 明确支持（名字长度约与作用域长度成正比）
- **模板类型参数 `T`、`TValue`、`KeyT` 等** —— `NL.7` 同类情形
- **`m_` / `g_` 前缀** —— **这不是缺陷，是 §4.2 选定路线的一部分**（Microsoft 路线）。不要因为"看起来像匈牙利"就要求去掉；它标的是**作用域**（成员 / 全局），不是类型。

**为什么要单列这一节**：把常用词当缺陷，会制造大量无意义重命名与 diff 噪音，而收益为零。**规范的成本必须换来看得见的收益。** 这一条在 Swift 侧付过代价（详见那边的整改手册 §5）。

只有出现下面五类情况才需要改名。

---

## 1. 必须改的反模式

### A. 生僻词与借喻黑话（MUST NOT）

词在母领域有确切含义，借来后语义漂移，读者必须先「学会黑话」才能读代码。**C++ 侧尤其严重** —— 因为学术论文与编译原理术语大量渗入命名。

| 禁止 | 问题 | 改为 |
|---|---|---|
| `reify` | 生僻哲学词 | 具体的领域动词 |
| `thunk` | 编译原理术语，借来指「延迟执行的包装」 | `DeferredCall`、`LazyInvoker` |
| `amortize` | 会计术语 | `spreadOverTime` |
| `hydrate` | 含水隐喻 | `populate`、`fill` |
| `elide` | 生僻 | `omit`、`skip` |
| `coalesce` | 数据库术语（C++ 里偶有正当用法，如内存合并） | 若指"合并"就写 `merge` |
| `monostate` | 生造术语 | `SharedState` |
| `wibble` / `frobnicate` | 无意义占位词 | 换成真实语义 |

**判定规则**：这个词在本项目内**没有正式定义**，又不属于 C++ / 标准库 / Win32 的既有术语，就禁止使用。

### B. 自造缩写与单字母（MUST NOT）

**自造**的定义：只有作者或本团队能还原。§0 列出的行业既定缩写不在此列。

| 禁止 | 改为 |
|---|---|
| `aniDur` | `animationDuration` |
| `srtAnmating` | `startAnimating` |
| `pDevCtx` | `deviceContext`（`p` 是类型编码，见 C） |
| `wndProcHdl` | `windowProcHandle` |
| `l`、`r` | `left`、`right` |
| `w`、`h` | `width`、`height` |
| `n` | `count` / `size`（视语义） |
| `c`、`p`、`d`、`g` | 展开为完整词 |
| `tmp`（超出 3 行作用域仍叫 `tmp`） | 按实际语义命名 |

**判定规则**：`i` / `j` / `k` / `T` 以外的单字母，一律展开。

### C. 把类型信息编码进名字（MUST NOT）—— **C++ 侧特有**

Core Guidelines `NL.5` 明确禁止：*"Don't encode type information in names."*

| 禁止 | 问题 | 改为 |
|---|---|---|
| `strName` | `str` 冗余（类型已声明） | `name` |
| `bBusy` | `b` 冗余 | `isBusy` |
| `pFoo` / `lpBar` | 指针/长指针前缀 | `foo` / `bar` |
| `szLastName` | 以 null 结尾字符串前缀 | `lastName` |
| `g_nWheels` | 类型编码 + 匈牙利 | 按 §4.2 路线写（本规范用 `g_` 前缀只为标**作用域**） |
| `iVariable` | 匈牙利整数前缀 | `variable` |

**与 `m_` / `g_` 的区别（必须分清，否则会误改）**：

| 前缀 | 编码的是 | 判定 |
|---|---|---|
| `m_` / `g_` | **作用域**（成员 / 全局） | ✅ 合规，是路线的一部分 |
| `str` / `p` / `b` / `lp` / `sz` / `h` / `dw` / `w` | **类型** | ❌ 违规，必须去掉 |

**同一原则演进下的例外**：`m_` 在 30 年前也是匈牙利记法；今天它编码的是作用域而非类型，这类前缀在 Windows 生态仍被广泛接受。**判据是"是否冗余于类型"，不是"是否看起来像旧风格"。**

### D. 缺失量纲与单位（MUST NOT）

数值型名字不写单位，是跨端协作中最高频的缺陷来源。

| 禁止 | 改为 | 理由 |
|---|---|---|
| `timeout` | `timeoutMs` / `timeoutSeconds` | 毫秒还是秒？**驱动与内核代码里这个错误代价极高** |
| `size` | `byteCount` / `pixelSize` | 字节还是像素？ |
| `length` | `byteCount` / `characterCount` | 长度单位 |
| `rate` | `refreshRateHz` | 频率单位 |
| `delay` / `interval` | `retryDelayMs` / `pollIntervalMs` | 时间单位 |
| `offset`（无单位） | `byteOffset` / `elementOffset` | 偏移单位 |
| `capacity` | `capacityBytes`（若为可数元素则 `capacity` 已足够） | 视语义 |
| `temp` / `temperature` | `temperatureCelsius` | 温标 |

**判定规则**：凡是数值参数或数值字段，名字里必须出现单位或量纲。C++ 没有 Swift 的 `TimeInterval` 这类自带量纲的类型，**因此这条在本侧更必要**。

### E. 前后缀滥用（MUST NOT）

| 禁止 | 原因 | 改为 |
|---|---|---|
| `getXxx()`（非智能指针场景） | 与属性/访问器语义重复 | `xxx()` 或真实动词 |
| `setXxx()`（非对应 setter 场景） | 同上 | `xxx(value)` 或真实动词 |
| `Manager` / `Controller`（作为主 `class` 名） | 职责不可从名字推出，典型"什么都不是"的类型名 | 按实际职责命名：`ConnectionPool`、`RetryPolicy` |
| `Helper` / `Utils` / `Common` / `Misc` | 无内聚性信号，通常是杂物袋 | 按具体功能命名；杂物袋通常说明**该拆的没拆对** |
| `XxxImpl` | ⚠️ **见下方例外** | 按实现特征命名 |
| `XxxData` / `XxxInfo` / `XxxObject` | 无信息后缀，不承载任何语义 | 去掉，或写清真名 |

**`Impl` 的例外**：**Pimpl 惯用法里的 `Xxx::Impl` 是正当的**（它是该惯用法的固定构成），`NL` 无禁止、行业通行。**判据是"这个名字是否指向惯用法中确有的角色"，不是"后缀本身"**。
同理，`detail` 命名空间（标准库惯例）、`internal` 命名空间是正当的。

### F. 名词 / 形容词当函数名（MUST NOT）

读者无法区分「这是查询还是动作」。

| 禁止 | 词性 | 改为 |
|---|---|---|
| `Stored()` | 过去分词 | `IsStored()` / `GetStored()` |
| `Previews()` | 名词 | `MakePreviews()` |
| `Valid()` | 形容词 | `IsValid()` |
| `Device()` | 名词（当动作用） | `GetDevice()` / `FindDevice()` |

**判定规则**：返回 `bool` 的函数用 `Is` / `Has` / `Can` / `Should` 开头；其余动作用祈使动词。**Microsoft 路线下这两个都取 PascalCase**（与 Google 路线的 `snake_case` 不同）。

### G. 集合单复数与容器名（MUST）

- 复数名字必须是真集合：`devices`、`records`、`ids`。**Microsoft 路线下写 `Devices` / `Records`**。
- 集合的**数量**用 `Count`，不要用复数名表示数量。
- **禁止把容器类型写进名字**：`deviceList` → `Devices`、`recordArray` → `Records`、`idVector` → `Ids`。
  理由：容器类型是可变的实现细节，改名时会让名字撒谎 —— 这与 C 类（类型编码）是同一条原则。

### H. 二义性与阶段混淆（MUST NOT）

| 问题词 | 歧义 | 改为 |
|---|---|---|
| `block` | 阻塞，还是阻止？ | 阻塞用 `Wait`；阻止用 `Disable` / `Disallow` |
| `sync` | 动词还是名词？ | 动作用 `Synchronize`，`Sync` 只作名词 / 属性 |
| `close` | 同步关闭 vs 请求关闭 | `Close()`（完成后返回）／`RequestClose()`（异步请求） |
| `check` | 断言，还是校验返回值？ | 断言用 `Assert`；返回结果用 `Validate` / `TryParse` |
| `handle` | 是句柄还是"处理"动作？ | 名词用 `Handle`；动作用 `Process` |
| `buffer` | 是缓冲区还是缓冲动作？ | 动作写 `Buffer` / `Enqueue`，名词写 `buffer` |

**判定规则**：在一个作用域内，同一个词不得同时表示两种语义不同的东西。

### I. 名称过长（MUST NOT，> 60 字符）

> **过长几乎总是说明「这个类型该拆了」，而不是「需要更长的名字」。**

```cpp
// 不好：68 字符，调用点无法解析
const std::filesystem::path& configurationPersistenceApplicationSupportNotAbsoluteFilePath = ...;

// 好：先拆类型，再起短名
namespace cfg { struct PersistPath { /* ... */ }; }
```

阈值 60 与函数行数上限 60 一致，便于记忆；**超过即须先按 `design-granularity.md` 判断该不该拆类型**，而不是继续加长。

---

## 2. 快速替换对照表

| 你在写 | 类别 | 替换方向 |
|---|---|---|
| `reify` / `thunk` / `amortize` / `hydrate` / `elide` | A 生僻词 | 换成描述动作的常用词 |
| `aniDur` / `srtAnmating` / `wndProcHdl` | B 自造缩写 | 展开 |
| `l` / `r` / `w` / `h` / `n` / `c` / `p` / `d` | B 单字母 | 展开 |
| `strName` / `bBusy` / `pFoo` / `szX` / `dwX` | C 类型编码 | 去掉前缀 |
| `timeout` / `size` / `length` / `delay` / `offset` | D 缺单位 | 加单位后缀 |
| `Manager` / `Helper` / `Utils` / `Common` | E 无信息后缀 | 按具体职责命名 |
| `XxxData` / `XxxInfo` / `XxxObject` | E 无信息后缀 | 去掉 |
| `XxxImpl`（非 Pimpl） | E 后缀 | 按实现特征命名 |
| `Stored()` / `Valid()` / `Device()` | F 词性 | `IsStored()` / `IsValid()` / `GetDevice()` |
| `deviceList` / `recordArray` / `idVector` | G 容器名 | `Devices` / `Records` / `Ids` |
| `block` / `sync` / `check` / `handle` | H 歧义 | 按上表消歧 |
| 超过 60 字符的长名 | I 过长 | 拆类型 |

**不在此表内的词，默认不动。**

**合法保留（不要误改）**：`m_` / `g_` 作用域前缀、`i` / `j` / `k` 循环下标（作用域 ≤ 3 行）、`T` 模板参数、`Impl`（Pimpl 惯用法）、`detail` 命名空间、§0 的全部可接受词。

---

## 3. 自检方法

改完名字后逐条过一遍：

| # | 测试 | 问什么 |
|---|---|---|
| 1 | **调用点测试** | 遮住定义，只看调用行，能说出在做什么吗？ |
| 2 | **还原测试** | 这个名字除了作者，别人能还原出它代表什么吗？（测自造缩写） |
| 3 | **词性测试** | 函数名是祈使动词（动作）或 `Is`/`Has`/`Can`（查询）吗？ |
| 4 | **单位测试** | 每个数值参数 / 字段的名字里有单位吗？ |
| 5 | **类型冗余测试** | 名字里有没有已经由类型声明表达的信息？（`str` / `p` / `b` / `lp`） |
| 6 | **职责测试** | 这个名字是否在说「我什么都不是」（`Manager` / `Helper` / `Utils`）？ |
| 7 | **长度测试** | 超过 60 字符了吗？如果是，先考虑拆类型 |

**七条里任何一条不过，就还没有到可以提交的程度。**

> **适用范围**：本词典用于**主动命名的场景**与**新增 / 改动代码的评审**。
> 对存量代码，只有 §1 的五类（A–I 中标 MUST NOT 的部分）才进入整改范围；**§0 列出的可接受词一律不要动**。

---

## 4. 与机器检查的关系（**C++ 侧的关键差异**）

C++ 的命名**可以部分机器化**，但**机器只能查形式，查不出语义**。两侧分工必须分清：

| 能力 | 工具 | 覆盖 |
|---|---|---|
| **形式**：大小写、前缀、后缀 | `.clang-tidy` 的 `readability-identifier-naming` | ✅ §1 C/G 的一部分、大写约定 |
| **形式**：名字长度上限 | `readability-identifier-length`（**默认关闭**） | ⚠️ §1 I 可定量 |
| **语义**：生僻词、自造缩写、词性、缺单位、歧义 | **无工具** | ❌ 只能人工评审（A/B/D/F/H 全靠人） |

**三条必须记住的**：

1. **`readability-identifier-naming` 启了但没配 `CheckOptions` = 完全没查。** 官方明说空配置等于关闭该检查。
2. **机器把形式改对了，不代表名字可以读懂。** 把 `strName` 改成 `m_strName` 是形式合规、语义照旧 —— **这不叫整改**。
3. **不要为了让命名规则归零而改 §0 的词。** 那些词改动产生的 diff 噪音是纯成本。

**配置在哪**：`assets/clang-tidy` 的 `CheckOptions` 是**唯一权威**（case / prefix / suffix 的具体取值只写在那里）。本词典只声明**取向与判据**，不复制取值。
