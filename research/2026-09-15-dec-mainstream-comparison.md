# DEC 执行计划修订四复审与主流方案对比

调研日期：2026-09-15。评审对象：原执行文档（内部文档，未随仓库分发），磁盘版本为修订四，412 行、47 个任务。原文 SHA-256：`7b027e75285790d13a369036c80365e1905b753e1546afa5cc920de17420136c`。本轮未修改原文、未执行文档中的任务。

## 结论

这份计划已由编码规则接入扩展为一套定制的质量治理系统。基线、渐进启用、配置回读、扫描健康与人工分诊符合成熟工具的方向；主要额外成本来自可信来源保护、跨通道身份迁移、逐规则实验晋升、SLA 自动降级和 AI 拆分授权。

市场上已有可复用的检测、基线和问题处置能力，但本次资料没有证明任何单个产品开箱即用地覆盖全部 DEC 拆分语义与手写保护政策。应把现成底座、定制规则、AI权限治理分别比较，不能拿一个检查器与整套47任务计划直接比功能总量。

修订四新增的 M0 提示试点是合理收敛；本轮优先建议是保留该方向，并把现成底座可做的部分从默认自研清单中拆出。条件化排序见后文，权重未由用户确认，不构成采购决策。

## 1. 证据与边界

本次实际读取 LLVM、Microsoft、GitHub、JetBrains、PVS-Studio、Cppcheck 官方页面及 SonarSource、Anthropic 官方源码/资料，共核对九个产品或机制，另检查 GitHub Code Quality 的语言边界。这里只能称作有代表性的主流工程生态样本，没有市场份额数据，不按安装量排名。

Sonar 文档站与 Claude 文档站本次返回403，分别改读其官方仓库；未读取成功的页面不作已核验来源。LLVM latest 当前是24.0.0git开发文档，Sonar master与Anthropic main均为可变分支。未安装产品、未跑实际Windows C++工程、未核价，不虚构性能、误报率、许可证成本或平台适配结论。附件两份上游正文依旧未随本次请求提供，本文不验证其规则内容；也未重新全盘检索上游文件。

一手资料细表分别见：

1. [平台取证：SonarQube、CodeQL、Qodana](research/2026-09-15-dec-platforms.md)
2. [原生工具与AI机制：clang-tidy、MSVC、Copilot、Claude](research/2026-09-15-dec-native-ai.md)
3. [基线补充：PVS-Studio、Cppcheck、SARIF](research/2026-09-15-dec-baseline-sources.md)

## 2. 九个产品或机制的同层比较

### 2.1 原生检测器与C++检测产品

| 对象 | 官方已核验的做法 | 可承担的DEC工作 | 与原计划的差异和限制 |
| --- | --- | --- | --- |
| LLVM clang-tidy | 公开检查器与参数，认知复杂度、函数规模与嵌套；编译数据库扫描，NOLINT系列抑制 | 族A部分指标、通道样本验证、原始诊断 | 不自带完整实例基线、手写归属或影子授权。认知复杂度默认25，嵌套默认none；BranchThreshold不是圈复杂度。[S1–S3] |
| MSVC /analyze | 原生构建分析、ruleset动作、SARIF、局部抑制及理由 | Windows通道、规则状态与抑制审计 | 不保证与clang-tidy指标对等；includesuppressed仍不会输出被ruleset禁用规则的诊断，必须联合有效配置审计。[S4–S5] |
| Cppcheck | C/C++缺陷分析、VS/编译数据库导入、文本/XML/源码抑制、缓存复用 | 较轻量的补充缺陷通道 | 缓存增量分析是提速，不等于只拦新增问题；未证明其现成覆盖DEC纯转发、包级指标和词数预算。[S6] |
| PVS-Studio | Windows C/C++分析、外置存量基线、诊断上下文匹配 | 基线和告警处置底座，避免源码加满抑制注释 | 已有基线但不是完整拆分规则集。文件改名、上下文和消息变化可能使告警重现，不能保证任意重命名自动识别；商业许可未核价。[S7] |

### 2.2 CI质量与诊断平台

| 对象 | 官方已核验的做法 | 可承担的DEC工作 | 与原计划的差异和限制 |
| --- | --- | --- | --- |
| SonarQube | Sonar way源码以新代码指标设gate；accepted/false-positive等转移有权限控制 | 集中质量门禁、实例处置与团队治理 | 新代码指标并不等同DEC实例基线；CFamily当前配置及具体授权版本本次未完成核验。手写保护、拆分定制与SLA编排仍需额外实现。[S8–S9] |
| GitHub CodeQL + code scanning | C/C++支持none/autobuild/manual；SARIF指纹；ruleset按工具和告警阈值要求扫描结果 | 问题身份、PR合并保护、安全检查与其他工具SARIF汇总 | CodeQL规则覆盖不能当作DEC规则覆盖；none精度受依赖/生成代码影响，manual只覆盖实际构建。PR增量报告不等于完整影响范围分析。[S10–S12] |
| JetBrains Qodana 2026.2 | 商业qodana-cpp基于CLion检查，社区qodana-clang基于clang-tidy；SARIF baseline区分New/Unchanged/Absent，gate可计新增问题 | 可复用检查、实例基线、CI门禁 | 当前确实支持C++，但Docker交付不证明Windows SDK/MSVC-only工程适配。商业版.clang-tidy的-*不关闭profile已启用项，要用qodana.yaml exclude；C++不在该页面coverage gate清单。[S13–S15] |

### 2.3 AI协作与动作约束

| 对象 | 官方已核验的做法 | 可承担的DEC工作 | 与原计划的差异和限制 |
| --- | --- | --- | --- |
| GitHub Copilot | 仓库/路径指令、AI code review；可选Copilot approvals公共预览 | “先起名再拆”、例外提示和辅助评审 | 默认评审不计必需审批，开启预览后可计入，新提交使批准失效；自然语言指令不保证执行，也不是确定性复杂度判据。AI批准不等于获准改写或合并。[S16–S17] |
| Claude Code hooks | 官方hook资料区分prompt与command hooks；command hooks支持确定性工具集成，PreToolUse可拒绝动作 | 在AI动作前后调用检查器、消费手写保护范围 | 只覆盖经过相关客户端事件的动作，外部编辑与其他客户端仍需独立验证。未确认任意历史代码来源自动恢复；当前网页细则403，不能把main上示例当所有客户端接口保证。[S18] |

**额外边界：GitHub Code Quality不等于CodeQL本体。** 官方Code Quality规则分析语言当前列C#、Go、Java、JavaScript、Python、Ruby、TypeScript，没有C++；AI分析范围可以更广。因此它可以作为分层模式参照，不能因CodeQL支持C++就列为本计划族A的直接替代品。[S19]

## 3. 原计划与这些成熟机制的六个实质区别

1. **按谁编写决定强制力，是额外策略。** 本次核验的门禁主要围绕诊断、严重度、新代码范围和授权处置；DEC另按human-protected/ai-recorded/unknown决定动作。保留用户手写不自动改写、不自动阻断的既定偏好，但要承认这会降低自动门禁覆盖；不能将未知来源记为干净，也不能声称产品自带完整来源识别。
2. **基线方向成熟，重建整套匹配器未必必要。** Qodana、PVS与GitHub均有实例身份机制。DEC应先定义行为验收，再验证现成平台的差额；SARIF仅是交换格式，既不能自动证明跨工具规则等价，也不能消除重命名和工具升级的匹配边界。
3. **默认阈值、指标定义、工程政策不是同一件事。** LLVM复杂度定义有明确出处，但默认25是实现默认值，不是本工程最优阈值。成熟工具提供规则和默认参数，团队可先试点验证。DEC为所有规则预设完整实验协议，比现成接入过程重；应将工具契约验证、阈值政策验证、自研分类器验证分开，避免机械地给确定性计数器做同一种混淆矩阵实验。
4. **第二通道应证明补充价值，而非默认追求对等。** MSVC和clang-tidy覆盖不同。DEC已经允许single-channel，但还应在账本分开“语义等价需去重”和“互补不等价保留两条”。Qodana同名clang-tidy配置的不同语义就是实际例子。
5. **SLA超时自动降整条规则，不是本次核验到的通用默认模式。** 成熟平台提供有权限的实例接受/误报处置。DEC的自动降级应说明触发依据、作用域、期限与恢复验收；未分诊只能证明响应超时，不能证明规则失效。不把此类额外编排当基本检查器接入前必须全部自研。
6. **AI影子授权是另一个可独立交付的系统。** D7可以保留，但生成建议、编辑源码、提交PR、批准PR、合并代码须分权。市场中的AI评审/审批功能不能直接作为“自主拆分无需人工”的验证证据。

## 4. 修订四的新问题与仍待澄清处

### 4.1 直接影响执行的五处

| 优先级 | 位置 | 问题与实际后果 | 建议修正 |
| --- | --- | --- | --- |
| 高 | §1.3，原文97–116行；§2 135–140行；§4第5条 | T-DEC-00a被放进“上游不落盘不可开工”清单，形成上游产出依赖上游的字面循环；又允许整个D6开工，但60/62等消费尚未冻结账本 | 区分“产出源规范”“核对源规范”“搭脚本骨架”“正式消费规则”；00a没有自依赖，D6仅无上游依赖部分可先做 |
| 高 | §6原文387行；§3.2、T-DEC-70、DoD | 样本不足时取消下限，与预登记门槛和至少30次验收冲突；维持人工虽然阻止扩权，但DoD是否完成仍不清楚 | 允许结束观察并提交报告，不等于通过授权/统计验收；状态记“样本不足，继续人工”，保留门槛 |
| 高 | T-DEC-06原文176行；P-2原文396行 | “AI为主要作者”不推出“没有可归属历史”；没有历史也不推出“手写保护覆盖率接近零”。来源记录验证覆盖、用户保护作用域、自动阻断覆盖是三种量 | 按真实记录核验，删除无数据的接近零断言。允许从新会话前向采集真实记录；历史缺失只标未知，未验收范围不开阻断 |
| 中 | M0原文145–159行；T-DEC-02/25 | “仅四前置”没有写真实工程、Windows环境/CI入口和临时工具配置来源；25若消费正式宿主又会受上游限制 | 明确四项为执行任务，环境/采样为输入前提；M0可用工具原生ID和版本化试点配置，不能宣称已映射DEC规则。区分CI报告与DEC正式验收 |
| 中 | T-DEC-00a原文169行；P-4原文398行；规则引用约定 | 00a将§5.3/§6写成“架构”章节，但原文其余处指规范的四问与例外；P-4又称00a可变“核对”，与00b拆分重复；规范/架构都用“上游§N”仍有歧义 | 引用改为“规范§N/架构§N”，00a只负责取得或产出正文，00b只负责核对；修正T-DEC-13在依赖表误列D2的问题（任务实际在D1） |

### 4.2 与主流工具对接前须补的五项

1. **确切检查器清单**：T-DEC-20的“三项检查”必须有ID、固定版本、指标公式、默认与选定参数。BranchThreshold不能算圈复杂度；E5的“有现成工具”也需指认具体检查器，不应当作已证明事实。[S1–S3]
2. **四层执行状态**：分别记录扫描job、报告上传、DEC策略判定、平台required check/merge protection；未扫描或上传失败不能用“0违规”或一个绿色提示状态代替。[S11–S12, S15]
3. **配置级抑制审计**：源码标记、有效规则集、工具参数、平台实例状态必须联合检查。MSVC ruleset关闭的规则不出现在includesuppressed日志，因此仅扫源码或SARIF都不足。[S4–S5]
4. **以行为定义基线适配边界**：明确文件移动、上下文改动、工具版本变化、已解决问题再现、配置变化的接受语义；现成平台不能满足的部分才进入自研清单。[S7, S11, S14]
5. **治理流程的收益指标**：除规则触发与误报，应观察受保护/未知/可自动判定覆盖，扫描耗时与等待、人工分诊投入、错误拆分/撤回及例外率。否则只能证明流程运转，不能证明拆分质量改善。先记录基线再定业务门槛，不凭空补数字。

## 5. 五条落地路线：条件化结构评估

`plancheck-mcp detect_project_context`成功，确认参照仓库没有C++工程和CI证据；它不能替代目标Windows工程勘察。`evaluate_proposals`返回内部错误 `Cannot read properties of undefined (reading '0')`。本次没有伪造自动评分：下面1–5分由评审者基于已读证据给出，随后交给`sensitivity_analysis`做确定性计算。

评估对象是“当前缺环境、缺上游时的首版落地路线”，不是产品总体质量。临时权重：Windows C++与拆分适配30%、增量治理复用25%、实施/维护成本30%、手写保护15%；未获用户权重确认。成本列越高越贵；其他列越高越好。所有路线保护均为3，表示可设计适用域层但均未实测，不能凭完整计划文案得更高分。

| 路线 | C++/拆分适配 | 增量治理 | 成本（高为差） | 保护 | 工具计算分 |
| --- | --- | --- | --- | --- | --- |
| 原生检查器＋薄DEC层，先M0提示 | 4 | 3 | 2 | 3 | 72 |
| SonarQube＋薄DEC层 | 3 | 4 | 3 | 3 | 65 |
| PVS-Studio＋拆分检查补充 | 3 | 4 | 4 | 3 | 59 |
| Qodana＋薄DEC层 | 2 | 4 | 3 | 3 | 59 |
| 47任务完整DEC自建 | 3 | 2 | 5 | 3 | 43 |

评分依据逐项说明：

- **原生路线**：S1–S5直接对应族A与Windows构建，适配4但没有目标工程实测故非5；S11可复用标准诊断但仍需平台/脚本，增量3；M0范围小因此成本2；保护3基于原文§0与T-DEC-06仍需实现。
- **Sonar路线**：S8–S9可复用集中gate和实例处置，增量4；CFamily、许可与Windows工程本次未验证，适配3，平台集成加定制层成本3；保护仍3。不得把源码核验算成CFamily实测。
- **PVS路线**：S7直接证明Windows C++与实例基线，但不等于全部拆分检查，因此适配3、增量4；另加拆分通道与定制层的集成维护使成本4，此项不是许可证价格估算；保护3。
- **Qodana路线**：S13–S15证明C++、baseline及gate，增量4；Windows特定依赖和容器路径尚未验证，适配保守2，不能解释成产品不支持C++；配置映射及平台接入成本3；保护3。
- **完整自建**：47任务覆盖意图明确但没有实现，适配3；实例基线与治理均拟自研，增量2；自建配置/基线/来源/SLA/授权多子系统，成本5；保护只有设计没有验收，仍3。

工具给出加权和、加权积、TOPSIS三种算法均将原生路线排首，但结论标为**脆弱**：增量治理权重从25%提高到约44.44%（相对乘1.778）时，Sonar路线领先。保护列全相同，工具在其权重达到100%时报出的另一“翻盘”只是全部打平后的排序，不是完整自建在保护上胜出的证据，因此不据此推荐。

**建议的适用条件**：

1. 当前目标是先获得真实检查反馈：采用原生检查器＋薄DEC的M0路线，依据上述72分与较小首版范围；不要把实例治理、来源追踪和AI授权全部塞进第一次报告上线。
2. 已有集中质量平台、多人协作且很看重新增问题生命周期：优先实测Sonar或现有平台适配，此时成本和权重应按现有资产重算，不能沿用本表。
3. 已有JetBrains/CLion或PVS资产：分别验证Windows真实工程与基线边界后重评；本表不能成为迁离既有平台的依据。
4. 完整自建：只在列出现成底座无法满足的具体行为，并接受长期维护责任后考虑。独特的手写保护政策可以保留，而无需连现成SARIF、基础告警生命周期也一起重建。

## 6. 下轮文档修改应如何收敛

1. 修正本报告§4.1的循环依赖和验收冲突，不新增新的顶层审批阶段。
2. 增一张“规则ID → 精确检查器 → 固定版本 → 覆盖缺口 → 处理通道”的最小映射；上游未就绪时M0先用工具ID，后续再核对规则映射。
3. 将交付明确为：M0报告；M1选定规则的增量反馈与人工处置；M2有可信适用域的自动阻断；M3窄类别AI动作授权。此为建议的里程碑划分，不修改既有任务完成状态。
4. 先验证所选平台能否承接基线、SARIF、问题状态与合并门禁，记录自研差额；用户手写/未知来源保护贯穿所有阶段。
5. 用真实Windows C++工程跑通一个族A检查器，再决定是否购买平台、做第二通道或投入纯转发自研。缺工程时不以玩具校准结果替代，仍可做检查器契约样本验证。

## 一手来源索引

- S1 [LLVM cognitive complexity](https://clang.llvm.org/extra/clang-tidy/checks/readability/function-cognitive-complexity.html)
- S2 [LLVM function size / nesting](https://clang.llvm.org/extra/clang-tidy/checks/readability/function-size.html)
- S3 [LLVM clang-tidy usage](https://clang.llvm.org/extra/clang-tidy/)
- S4 [MSVC /analyze](https://learn.microsoft.com/en-us/cpp/build/reference/analyze-code-analysis?view=msvc-170)
- S5 [MSVC warning pragma](https://learn.microsoft.com/en-us/cpp/preprocessor/warning?view=msvc-170)
- S6 [Cppcheck manual](https://cppcheck.sourceforge.io/manual.html)
- S7 [PVS-Studio baselining](https://pvs-studio.com/en/docs/manual/0032/)
- S8 [SonarSource SonarWayQualityGate.java](https://github.com/SonarSource/sonarqube/blob/master/server/sonar-server-common/src/main/java/org/sonar/server/qualitygate/builtin/SonarWayQualityGate.java)
- S9 [SonarSource DoTransitionAction.java](https://github.com/SonarSource/sonarqube/blob/master/server/sonar-webserver-webapi/src/main/java/org/sonar/server/issue/ws/DoTransitionAction.java)
- S10 [CodeQL compiled languages](https://docs.github.com/en/code-security/how-tos/find-and-fix-code-vulnerabilities/manage-your-configuration/codeql-for-compiled-languages)
- S11 [GitHub SARIF support](https://docs.github.com/en/code-security/reference/code-scanning/sarif-files/sarif-support)
- S12 [GitHub code scanning merge protection](https://docs.github.com/en/code-security/how-tos/find-and-fix-code-vulnerabilities/manage-your-configuration/set-merge-protection)
- S13 [Qodana C/C++](https://www.jetbrains.com/help/qodana/clang.html)
- S14 [Qodana baseline](https://www.jetbrains.com/help/qodana/baseline.html)
- S15 [Qodana quality gate](https://www.jetbrains.com/help/qodana/quality-gate.html)
- S16 [Copilot repository instructions](https://docs.github.com/en/copilot/how-tos/configure-custom-instructions/add-repository-instructions)
- S17 [Copilot code review and approvals](https://docs.github.com/en/copilot/concepts/agents/code-review)
- S18 [Anthropic official hook-development skill](https://raw.githubusercontent.com/anthropics/claude-code/main/plugins/plugin-dev/skills/hook-development/SKILL.md)
- S19 [GitHub Code Quality](https://docs.github.com/en/code-security/concepts/code-quality/code-quality)
