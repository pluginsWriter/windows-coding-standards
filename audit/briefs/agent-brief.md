# Agent 审计任务简报 —— skill 真机验证（Windows C++）

> 被测物是 **skill**（规范文档、自带脚本、DEC 计划的可执行声明）。被审工程代码只是夹具。
> 你的产出不是"这段代码哪里烂"，而是"**skill 的哪条声明在真机上不成立 / 哪里没覆盖**"。
> 开工前先读 `../README.md`（五道门、A–F 分类、闭环纪律）。

## 0. 开场提示词（整段复制给执行 agent）

```text
角色：你在 Windows 真机上验证一个编码规范 skill 的有效性。被测物是 skill，不是被审代码。

第一步：进入 audit/ 目录，执行审计主入口——PowerShell 环境: .\run-audit.ps1 -Src <被测C++工程目录>（或 run-audit.cmd -Src <目录>）；Git Bash/WSL 环境: ./run-audit.sh --src <被测C++工程目录>——读完生成的 logs/run-*/summary.md。
第二步：按 briefs/agent-brief.md 的六阶段，完成其中机械部分未覆盖的判断工作。
第三步：所有结论写入该 run 目录的 findings.tsv；每条必须过五道门。

证据纪律：
1. 每条结论必须引用本次 run 目录内的日志文件；自己补跑的命令，先在 cmdlog.txt 追加一行「$ 命令原文」再贴完整输出。
2. 确认级结论必须复现两次；只出现一次的标「间歇」。
3. 编译期事实 / 运行期事实 / 静态推断 分开标注，不许混写。
4. 没运行过的部分只能写「未检查」，禁止写成「正常/通过」。
5. 禁止评价性总结（如"整体良好"）；只输出逐条事实与推断。

禁令：
- 不修改被测工程源码（扫描与构建只读/独立目录）。
- grep 候选不是结论：候选 → 分诊 → 过五道门 → 才算 finding。
- 未过门的 finding 不得用于建议修改 skill。

开始前先用三句话说明你打算怎么验证，再动手。
```

## 1. 六个阶段

| 阶段 | 内容 | 自动化程度 | 你的产出 |
| --- | --- | --- | --- |
| 0 环境指纹 | 工具版本、生成器矩阵 | run-audit.sh 已做 | 核对 env.txt；补 MSVC 具体版本 / vcvars 环境 / 缺失工具的处置决定（缺工具→哪些 claim 被迫 UNTESTED，逐一列在未检查清单） |
| 1 skill 自检 | 跑 skill 自带的 verify/一致性脚本 | 手动 | 结果进 findings（A 类优先：脚本自己都跑不过=声明错误） |
| 2 声明核对 | claims-checklist.tsv 逐条 | 部分（夹具自动） | 复核 claims-results.tsv 的证据后回填 checklist；UNTESTED 条目逐条人工验证，或明确写"不可测原因" |
| 3 工作流实走 | 按 skill 的工作流对被测工程走一遍 | 手动 | 每步记录「skill 预期 vs 实际发生」；走不通的步骤进 findings（B/E 类） |
| 4 规则触发 | 已知违规样本喂给 skill 的机器规则 | 手动 | 每条规则记录「拦得住/拦不住」；拦不住=负向验证失败（B 类）；skill 有规则但真机无工具=D 类线索→CLM-009 |
| 5 缺口收集 | 真实工程暴露 skill 未覆盖的问题 | 候选已扫 | 分诊 macos-trace-candidates.tsv；真缺口进 findings（C 类） |

阶段顺序建议 0→1→2→3→4→5，但阶段 5 的分诊可与 3 并行（扫描结果独立于工作流）。

## 2. 五道门（见 ../README.md，此处为操作口径）

- 复现门：repro_count ≥2。
- 证据门：evidence 列必须指到本次 run 目录的具体文件（必要时附行号）；`文件:行号` 或 `命令+输出` 二选一起码。
- 归因门：attribution_artifact 列写 skill 具体工件（如「DEC计划 T-DEC-26」「skill README §x」）；写不出的，fix_target 只能是 project 或 none。
- 差异门：expected 与 actual 两列必须都填且确实不同；"skill 说会拦、实际也拦了"不是 finding。
  - **C 类例外（覆盖缺口）**：C 类的 `expected` 取自**目的层 `../references/design-purpose.md`**，**不取自「skill 已有声明」**；
    `actual` 写「规则层无对应条目」并附检索命令与输出。**目的层也没有依据 ⇒ `fix_target=none`（记录待议，不得补规则）。**
    不加这条例外，C 类会被门 4 结构性挡下 —— 详见 `../README.md` 的「C 类专用口径」。
- 影响门：impact 列写"不改会发生什么"（谁在哪一步被误导）。

## 3. A–F 分类与 fix_target 对应

| category | 含义 | fix_target 允许值 |
| --- | --- | --- |
| A | skill 声明错误 | skill（指明文件+章节） |
| B | skill 命令/脚本真机失效 | skill（脚本/命令） |
| C | 覆盖缺口 | skill（新增条目，**仅当目的层有依据**）或 none（目的层也无依据 → 记录待议） |
| D | 阈值失真 | skill（E 系列实验，不可直接改数） |
| E | 执行性缺口 | skill（降级 SHOULD / 给替代） |
| F | 环境假设破产 | skill（前置说明/环境检测）或 project（环境要补装） |

工程自身问题（归因不到 skill）：category 留 C 但 fix_target=project，单独成行不混入 skill 修复。

**C 类的两条操作纪律**（与 A/B/D/E/F 不同，别照抄其它类的填法）：

1. **C 类的 `expected` 只能来自目的层** `../references/design-purpose.md`（哪一条目标、哪个病灶），
   **不许写成「这条规范应该有」** —— 那是"我觉得"，不是依据。目的层里找不到 ⇒ `fix_target=none`。
2. **证据允许「计数 + 抽样」两种形态，取其一**：计数 = 检索命令证明规则层零命中（命令与输出落盘）；
   抽样 = ≥2 个真机实例。**两者都给不出 ⇒ 不算 finding**，只进「待人工复核」清单。

## 4. findings.tsv 字段速查

`id`(F-001 递增) · `stage`(0–5) · `category`(A–F) · `attribution_artifact`(skill 具体工件或"无") · `expected` · `actual` · `evidence` · `repro_command` · `repro_count` · `confidence`(compile|runtime|infer) · `fix_target`(skill|project|none) · `status`(open|confirmed|false-positive|attributed-elsewhere|fixed-verified|intermittent) · `impact` · `notes`

## 5. 候选分诊流程（阶段5）

对 `macos-trace-candidates.tsv` 每条候选：

1. **去噪**：按 §6 误报源表先排除明显误报（排除的计数留档，不逐条进 findings）。
2. **定性**：看上下文判断是活代码 / 死分支 / 纯注释线索；`#ifdef __APPLE__` 分支在 Windows 下的可达性属静态推断，confidence 标 infer。
3. **成案**：确属 macOS 遗留且 skill 应管而没管的 → C 类 finding（归因门：skill 缺哪条；`expected` 按「C 类专用口径」取自目的层，不是"我觉得应该有"）；skill 有规则但没拦住的 → B 类。
4. **保守原则**：拿不准的不进 findings，进「待人工复核」清单并写明缺什么证据。

## 6. 已知误报源（分诊参考）

> 2026-09-24 真机批次（run-20260924-151058）后：扫描器已修复两类 apple_symbols 系统性误报并默认排除第三方/构建目录（见 findings-master F-001/F-003/F-004）。旧运行目录里的 apple_symbols 候选按误报处理，不必逐条分诊。

| 类别 | 已知误报 | 判别方法 |
| --- | --- | --- |
| apple_symbols | `uint8_t`/`std::uint16_t` 等全小写类型（曾因 PS 大小写不敏感整批误报，F-001） | 修复后不会再出现；旧目录遇到直接按误报丢弃 |
| apple_symbols | `UINT`/`UINT_MAX`/`UINT32` 等 Windows 全大写类型（F-003） | 同上：真 Apple 符号第二字母必为小写（NSString/CGRect），全大写后缀必是误报 |
| apple_symbols | `CFG_xxx`、`UIxxx` 等普通宏撞 NS/CF/CG/UI 前缀 | 看语境：是否 Apple 头文件/类型系统 |
| apple_symbols | 第三方跨平台库自带 dispatch_ 封装 | 看 include 来源 |
| apple_guards | 合法的跨平台分支（两边都有实现） | 看分支体内是否真有 Windows 实现 |
| posix_api | pthread 的 Windows 兼容层（如 winpthreads） | 看 include 与链接目标 |
| comment_traces | 注释里正常提及 macOS 的跨平台说明 | 只扫 TODO/FIXME 已降噪，仍需人工看 |
| utf8_bom | BOM 在 MSVC 下是保护而非问题 | 与 /utf-8 编译选项一起判断 |
| include_case_mismatch | 生成目录/构建产物里的路径 | 只看源码目录内的 include |
| （全部） | third_party/external/vendor/build 等目录内容 | 扫描器已默认排除（清单见脚本头部 EXD/ExcludeRe）；如需扫第三方，改脚本参数后重扫 |

## 7. 收口检查单（每阶段结束自检）

- [ ] 所有写入 findings 的条目五道门字段齐全？
- [ ] 有没有把"没查"写成"通过"？（逐条 status 复核）
- [ ] 未检查清单是否更新（含：缺工具导致的 UNTESTED、时间不够没跑的、权限不足的）？
- [ ] summary.md 待办清单是否勾完/更新？
- [ ] 确认项是否已合并进 audit/findings-master.tsv？
