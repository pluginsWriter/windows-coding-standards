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
