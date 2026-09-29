# audit/ —— skill 真机审计包（Windows C++）

**被测物是 skill 本身**（规范文档、自带脚本、DEC 计划的可执行声明），被审工程代码只是夹具。
目的：在 Windows 真机上收集**真实有效**的问题——每条 finding 必须过五道门，过门的才允许触发对 skill 的修改。没过门的只是候选/线索。

## 快速开始（人类）

1. 把整个 `audit/` 目录随 skill 带到 Windows 真机。
2. 执行（二选一，产出完全一致）：

```powershell
# 方式 A：Windows 原生 PowerShell / cmd（零依赖，推荐）
cd C:\path\to\windows-coding-standards\audit
run-audit.cmd -Src D:\path\to\被测C++工程
# 或 PowerShell 里直接: .\run-audit.ps1 -Src D:\path\to\被测工程
```

```bash
# 方式 B：Git Bash / WSL（bash 版）
cd /c/path/to/windows-coding-standards/audit
./run-audit.sh --src /d/path/to/被测C++工程
```

3. 直接读结果：`logs\run-<时间戳>\summary.md`

说明：要让 CLM-005/006（MSVC 声明核验）自动跑，请在「x64 Native Tools Command Prompt for VS」里执行，使 `cl.exe` 在 PATH；否则那两条记 UNTESTED，不影响其余部分。

## Agent 入口（如果你是 agent，从这里开始）

1. 读本 README（尤其「五道门」「A–F 分类」）。
2. 执行审计主入口（PowerShell 版 `run-audit.cmd -Src <被测C++工程目录>` 或 `.\run-audit.ps1 -Src <目录>`；Git Bash/WSL 下用 `./run-audit.sh --src <目录>`，产出一致），读完生成的 `summary.md`。
3. 按 `briefs/agent-brief.md` 六阶段完成机械部分未覆盖的判断工作（开场提示词在该文件顶部，可整段复制）。
4. 所有结论写入本次 run 目录的 `findings.tsv`；每条过五道门。
5. 更新 `summary.md` 的待办清单，补齐「未检查清单」。

## 自动化覆盖（run-audit.sh 一条命令完成）

| 部分 | 实体 | 产出 |
| --- | --- | --- |
| 环境指纹 | 工具探测 cmake/clang-tidy/cl/ninja/msbuild/cppcheck | `env.txt`、`cmdlog.txt` |
| macOS 遗留痕迹 | `scripts/scan-macos-traces.{sh,ps1}`（9 类模式 + include 大小写 + BOM） | `macos-trace-candidates.tsv`（候选） |
| 工具链声明核验 | `scripts/verify-toolchain-claims.{sh,ps1}` + `fixtures/` | `claims-results.tsv`（PASS/FAIL/UNTESTED+证据） |

每个脚本都有 bash 与 PowerShell 两个等价实现，同一次审计只用其中一个入口即可。

**日志纪律**：每次 run 一个 `logs/run-<时间戳>/` 目录；`cmdlog.txt` 记录每条命令原文与完整输出；任何结论必须引用该目录内的日志文件。agent 补跑的命令必须先追加 `$ 命令` 行再贴输出到 `cmdlog.txt`。

## 五道门（finding 有效性门槛，缺一不可）

1. **复现门**：同样条件下复现 ≥2 次；只出现一次的标「间歇」，不算确认。
2. **证据门**：有 `文件:行号` 或 `命令+实际输出`（在 run 目录内有落盘）。
3. **归因门**：能指到 skill 的具体工件（哪个文件哪一节/哪条规则/哪个脚本）；指不到的归「工程自身问题」或「未知」，不进 skill 修复。
4. **差异门**：写清「skill 预期 vs 实际发生」；两者一致的不是 finding。
   - ⚠️ **C 类例外**：C 类的 `expected` **不取自「skill 已有声明」**，而取自**目的层 `references/design-purpose.md`**。不加这条例外，C 类会被本门**结构性**挡下（"skill 里没有"就写不出"skill 预期"）—— 详见下节。
5. **影响门**：说明不改会发生什么（谁会在哪一步被误导）。

## A–F 分类（每条 finding 的去向）

| 类 | 含义 | 去向 |
| --- | --- | --- |
| A | skill 声明错误（文档说的与真机事实不符） | 改 skill 文档 |
| B | skill 给的命令/脚本在真机失效 | 修命令/脚本 |
| C | 覆盖缺口（真机暴露、skill 无对应条目） | 补规则/补文档 |
| D | 阈值失真（能跑但数字不合真机分布） | 喂给 E 系列实验校准 |
| E | 执行性缺口（ SHOULD 级要求实际做不到） | 降级或给可执行替代 |
| F | 环境假设破产（skill 前提在本机不成立） | 改前置说明/环境检测 |

## C 类专用口径（覆盖缺口 —— 唯一能发现「规则层缺了哪条」的通道）

**为什么必须单独给一条口径。** 五道门都是**证伪型**：门 4 要求写「skill 预期 vs 实际发生」，
而 C 类的字面意思就是「skill 里没有这条」—— 它**天然给不出**「skill 预期」，于是**结构性地过不了门 4**。
可 C 类又是**唯一**能回答「规则层缺了哪几条」的类别：A / B / D / E / F 全都在"已有声明或既有规则"的内部挑错，
只有 C 类问的是"该有而没有"。C 类被门 4 挡下，审计层就**永远报不出缺口** ——
这正是设计目的 **G5（审计层能发现规则层缺口）** 此前不成立的原因。

**因此 C 类按以下三条判（其余四门不变）：**

| 门 | 其它类别 | **C 类的专用口径** |
| --- | --- | --- |
| 差异门（门 4） | `expected` 取自「skill 已经这么说了」 | `expected` 取自**目的层 `references/design-purpose.md` 对该病灶的要求**；`actual` = 规则层**无对应条目** |
| 证据门（门 2） | 须有 `文件:行号` 或 `命令+输出` 的**直接**证据 | **允许两种形态，取其一即可**：① **计数** —— 用检索命令证明规则层**零命中**（如某病灶在缺陷目录无编号、在正文无任何一条 MUST/MUST NOT 提到它），命令与输出落盘；② **抽样** —— 给出 **≥2 个**真机实例（同一缺口的两个不同现场），证明不是孤例 |
| 归因门（门 3） | 指到 skill 具体工件 | 只有 `expected` **能在目的层找到依据**时才允许 `fix_target=skill`；**目的层也没有依据的，`fix_target=none`**（记录待议，**不得直接往规则层补条目**） |

**不算 finding 的反面**：只有"我觉得应该有"、既给不出计数也没有 ≥2 实例的，**一律不算 C 类 finding** ——
它只是线索，进「待人工复核」清单并写明缺什么证据。
（这条同时守住硬约束「**不得为满足规则而堆代码**」：没有目的层依据的"应该"不许变成规则。）

## claims 与规则层的接线（CLM-013..031，2026-09-28）

**接线前的状态**：`templates/claims-checklist.tsv` 原有 12 条，`source` 列指向的是 DEC 计划 / `research/` / 审计设计本身
—— **没有一条指向 `references/`**。也就是说，审计层与规则层之间**没有通路**：审计能核验工具链声明，却**说不到规则层缺了哪几条**。

**接线方式**：把两侧正文**附录 D**（待实测 / 验证状态清单）里的每一条论断接成一条 claim：

| 来源 | 条数 | claim 编号 |
| --- | --- | --- |
| `references/csharp-coding-standards.md` 附录 D #1..#8 | 8 | CLM-013 … CLM-020 |
| `references/cpp-coding-standards.md` 附录 D D1..D11 | 11 | CLM-021 … CLM-031 |

`source` 列一律写成 ``references/<侧>-coding-standards.md 附录 D#<编号>``。这样 finding 的 `attribution_artifact`
就能**指到附录 D 的具体条目**，C 类专用口径里的 `expected` 也有了落点 —— 这就是设计目的 **G5（审计层能发现规则层缺口）** 的落点。

> ⚠️ **平台差异：不许拿 macOS 的结论当 Windows 的结论。**
> C++ 侧 9 条已在 macOS 上实测（Apple clang 21.0.0 + `clang-format` / `clang-tidy` **21.1.6**），
> 但本审计包的**目标平台是 Windows** —— 工具版本与目标三元组都不同，**Windows 上一律重跑**并把结论写回。
> C# 侧 8 条**从未验过**（本机无 .NET SDK），全部 `untested`。

> ⚠️ **计数纪律**：claims 里 `source` 指向**某一侧**附录 D 的行数，**必须等于该侧附录 D 的实际行数**；
> claims 的 `id` 也必须连续无断号。两条都由 skill 的自检机械核对 —— 同一件事抄两处就必然漂。

## 闭环纪律

- 修复 skill 任何一处必须引用 finding ID；修后在同环境复验，`status` 改 `fixed-verified` 并留复验证据。
- 已确认的 finding 从各 run 的 `findings.tsv` 合并进 `audit/findings-master.tsv`（skill 仓库内的累计台账）。

## 文件地图

```
audit/
├── README.md                     本文件
├── run-audit.ps1 / run-audit.cmd 主入口，Windows 原生 PowerShell（cmd 启动器免 ExecutionPolicy 设置）
├── run-audit.sh                  主入口，Git Bash / WSL 用（与 ps1 产出一致）
├── findings-master.tsv           累计发现台账（确认项合并处）
├── scripts/
│   ├── scan-macos-traces.ps1 / .sh      macOS 痕迹候选扫描（双实现）
│   └── verify-toolchain-claims.ps1 / .sh 声明夹具核验（双实现）
├── fixtures/                     声明核验用最小夹具
├── briefs/agent-brief.md         agent 六阶段任务简报（含开场提示词）
├── templates/                    findings.tsv / claims-checklist.tsv 模板
└── logs/run-<时间戳>/            每次 run 的全部日志与结果（执行时生成）
```
