# 当前 DEC 实现评审：能力差距与后续设计

日期：2026-09-15。对象为当前 `cpp/` 源码、根目录契约 CI 和用户指定的 `pilot-cpp`，不是仅评审计划文本。本轮不修改实现、业务代码或执行计划；只写评审证据。

## 1. 现在实际完成了什么

- 本轮重新运行34项测试全部通过，无跳过；其中8项使用真实clang-tidy 21.1.6，执行环境为macOS。
- 当前提供原生clang-tidy运行、严格配置校验及回读、显式TU清单检查、原始输出和快照、只读诊断比较。
- 支持的配置选项包括认知复杂度及function-size相关选项，但默认策略只启用认知复杂度；不存在已完成的完整族A/B/D/E规则集。
- `origin` 在诊断模型中固定为unknown，mode只接受advisory，upload_status固定not-attempted；这些是明确的尚未实现范围，不能算已有归属、发布或生产门禁。
- `pilot-cpp` 仍是4个声明TU的MSVC v143/Windows SDK工程；业务工作树无改动，本轮未获得真实Windows扫描结果。
- 根目录 `.github/workflows/dec-contracts.yml` 已有三平台契约CI文件，但只扫描合成样本，不能证明pilot-cpp被接入。工具仓库尚无.git；文件已存在不等于已部署远程流水线。

源代码依据：[runner.py](cpp/dec/runner.py:36)、[policy.py](cpp/dec/policy.py:28)、[diagnostics.py](cpp/dec/diagnostics.py:49)、[CI](.github/workflows/dec-contracts.yml:33)。

## 2. 本轮隔离复现

[完整结果](research/2026-09-15-dec-current-probes.json)。其中5种情形使用临时合成源码及真实clang-tidy；路径迁移另1项单独标为报告输入模拟，不是跨平台测试。未向正式tests加入断言，也未把这些样本当真实工程校准。

| 情形 | 实际结果 | 判断 |
| --- | --- | --- |
| 只改parameter_basis说明文字 | 诊断完全一致，但compare报Baseline migration required | 检测兼容标识混入非检测元数据 |
| 新增一个无违规.cpp，并更新manifest/db | 两次扫描完整，但compare整体拒绝 | 每次加文件都需迁移，妨碍正常新增诊断治理 |
| 函数前加一行注释 | 复杂度均为6；比较为new=1、absent=1 | 三行上下文指纹对无语义修改敏感 |
| 复杂度6的函数使用默认阈值25 | checked但findings为空 | 正常阈值筛选结果，不能用于完整分布/P95校准 |
| 数据库有2个TU，manifest仍只列1个 | checked，覆盖1/1，仅报告被列出的文件 | 对局部scope符合当前契约；作为全工程门禁会漏掉新TU |
| 仅更换报告中的source_root（模拟） | compare拒绝 | 不能直接在不同checkout路径之间复用基线 |

34项测试覆盖了已有约定，不证明这些日常变更情形已经符合期望。`test_comparison.py:10`手工指定fingerprint，因此“同指纹行号改变仍未变”的测试不能证明真实扫描生成的指纹稳定。

## 3. 优先修改的设计点

### 3.1 P1：把严格运行证据与比较兼容性分开

位置：[runner.py:76](cpp/dec/runner.py:76)、[comparison.py:44](cpp/dec/comparison.py:44)。

当前 `detection_fingerprint = hash(binary + version + whole policy + all commands)`。因此说明文字、TU顺序、TU增删、工作区路径都能使全报告不可比较。拒绝不同检测口径本身合理，但这些变化并非全部需要重新接受存量。

建议保留原始哈希作为`RunEvidence`，新增明确、版本化的比较条件：`project_id`、`build_variant`、`analyzer_contract_version`、规范化后的有效规则参数。TU范围和每个TU的编译语义另存，不把新增文件当作整个检测引擎变化。原始binary hash仍保留，跨主机/工具构建是否兼容必须有明确映射或再验证，不能简单删掉检查。

源码集合新增时，新增TU完整扫描后其诊断可进入新增判定；集合移除时，区分真实源码删除和扫描遗漏，后者不得标为问题已解决。相同源码根的不同项目也不能只靠相对路径当同一项目。

### 3.2 P1：显式区分全工程scope与选定scope

位置：[compilation.py:40](cpp/dec/compilation.py:40)、[project.py:45](cpp/dec/project.py:45)。

静态manifest目前是唯一“应查”来源，数据库多出的TU被直接跳过。这适合选定范围，但不适合全工程接入后自动发现新文件。增加`scope_mode=project/selected`及明确排除原因；project模式以选定实际构建的TU集合为基准，发现数据库新增项不能静默跳过。selected模式持续显式展示“局部检查”，不提供全工程清洁结论。

不要把所有CPP文件递归扫描当作实际构建范围：条件编译、测试/生成目录和平台专用源码需要实际构建证据。

### 3.3 P1：真实Windows构建接入是独立缺口

位置：[Invoke-M0Scan.ps1:10](cpp/scripts/Invoke-M0Scan.ps1:10)、[project.py:12](cpp/dec/project.py:12)。

现有脚本消费数据库，不生产它；vcxproj清点不求值imports、条件和继承。需要在Windows开发者环境确认一个实际build_variant，完成构建捕获、扫描、报告发布。不要先手写MSBuild求值器。

本轮Sonar CFamily官方页面重新读取成功，Build Wrapper可包裹Windows/MSBuild clean build，要求`/nodeReuse:False`及构建/分析环境一致，并从对应Sonar Server取得匹配CFamily版本。应先核验产品许可、输出对固定clang-tidy版本的适配和环境可用性；这不是可无条件复制的免费独立工具承诺。若现有平台不可用，另行验证适合该真实构建的捕获器，而非伪造参数。

### 3.4 P2：诊断身份不能由整段展示文本主导

位置：[diagnostics.py:36](cpp/dec/diagnostics.py:36)。

现有指纹使用原始三行上下文及将所有数字替换后的消息；注释/空白或无关相邻行改变可能导致重报。当前文档已声明保守匹配，这是已知局限，不应冒称生产稳定身份。

建议保留`raw_message/raw_context`作为证据；由有版本的匹配规则使用稳定原生ruleId、仓库相对路径、适用的结构锚点和规范化上下文。确定匹配失败时可报告新/消失或歧义，但低置信结果不能自动扩展豁免。路径移动不应靠模糊全仓匹配直接豁免，须显式rename证据与碰撞验证。

SARIF可交换和展示指纹，不能自行解决匹配算法。GitHub官方也明确稳定路径前提；不要承诺接入SARIF即可无损跨重构追踪。

### 3.5 P2：区分指标观测、规则命中、基线状态与发布状态

位置：[diagnostics.py:42](cpp/dec/diagnostics.py:42)、[runner.py:48](cpp/dec/runner.py:48)。

现在metric从超过阈值才出现的诊断字符串提取，因此是被筛选过的数据。M0提示合理，但不能据其计算全部函数复杂度分布。未来新增`MetricObservation`应标明测量范围、缺失与零值区别；不能单把阈值调零就认为涵盖了复杂度为零的全部函数。

只读compare不是完整BaselineStore：缺持久的已解决退出、低水位、重现和迁移审批。若平台承担实例生命周期，DEC只补同实例指标恶化及用户保护政策。`PublishReceipt`应单独记录报告哈希、接收端ID/URL及上传结果；本地写出文件与远端已接收不要共用一个成功标志。

### 3.6 P2：扩展验证面，再考虑性能与大框架

现有runner逐TU串行，且每TU回读一次配置；对4TU试点不必先做分布式执行。项目扩大后再借鉴run-clang-tidy的有界并行，同时保留逐TU超时与证据。优先补真实scan→compare回归、新文件发现、说明文字变更、注释漂移、完整性失败、旧报告拒绝和发布失败；当前无第二真实检测器，不宜先搭多层通用插件框架。

## 4. 与主流功能实现的对比

| 方案 | 现成能力 | 当前实现差距 / 可保留价值 | 不能混用的概念 |
| --- | --- | --- | --- |
| clang-tidy原生工具链 | 规则、导出诊断、并行运行、diff辅助脚本 | 保留当前严格回读、逐TU证据；缺通用并行但4TU尚非瓶颈 | diff行过滤不是完整新增诊断识别 |
| MSVC /analyze | 原生Windows分析、SARIF和配置/已分析文件信息 | 尚无第二Adapter；可按实际规则覆盖补充 | 与clang-tidy不是同义双通道；includesuppressed不含ruleset关闭项 |
| Sonar CFamily / SonarQube | Windows构建捕获，以及平台侧诊断治理能力 | 可减少捕获与平台维护；当前缺真实接入 | Wrapper版本/环境有条件，需核验许可；默认质量gate不能绕过手写保护 |
| Qodana | C++检查、SARIF基线、New/Unchanged/Absent、新增问题gate | 可复用生命周期和展示，省去自研UI | 新增计数不等于同实例指标恶化；Windows SDK工程适配仍待验证 |
| PVS-Studio | C++/VS存量告警基线和处置 | 可作为已有团队工具的治理底座 | PVS自己的基线不是通用clang-tidy报告接收器 |
| GitHub SARIF/code scanning | 标准诊断展示、跨次指纹、PR merge protection | 当前缺SARIF导出、真实发布回执与工程required check | SARIF不是去重算法；CodeQL安全查询不等于拆分规则 |

官方10页本轮取证与版本限制见[市场证据](research/2026-09-15-dec-current-market-evidence.md)。本轮未实跑商业产品或Windows工程。

## 5. 三条后续路线的证据锚点

### A：补强现有运行器，保留窄职责

已有34测试、实际clang-tidy运行、read-only报告与CLI可复用；本轮probe证明了具体兼容性与scope缺口。改动集中在runner的运行上下文、compilation的scope契约、diagnostics身份与comparison兼容判断，随后通过一个独立SARIF导出函数接平台。先保留advisory，推迟完整来源、SLA和AI授权平台。Windows实测仍缺，不能承诺设计后自动具备覆盖。成本包括真实捕获接入和报告v2迁移，不能当几个字符串修补。依据源码runner.py:36/76、comparison.py:44、compilation.py:40、diagnostics.py:36及本报告§2复现。

### B：质量平台承接持续治理，DEC保留窄适配

Sonar官方证实Windows捕获，Qodana/PVS/GitHub证实各自的基线与门禁机制；这些事实在同目录市场证据文件附可访问URL。采用平台后可省长期展示、实例处置、分支保护和部分捕获工作。当前没有已购许可、现成平台实例、WindowsCI接入证据，实际成本与适配未知；默认gate需配置为不绕过用户手写不阻断约束。不能将平台支持的语言或SARIF协议当作DEC全部规则覆盖或同实例恶化治理已完成。窄适配位置是报告导出、分析类别映射和DEC自定义政策，不应搬迁现有C#规范。

### C：完整自建DEC治理系统

原计划47任务要求基线退出/迁移、来源保护、SLA、正式策略与AI影子授权；当前implementation-status.md明确这些未实现或待证据。自建可以精确表达定制政策，但并无相应实现可靠性证明，需要增加长期存储、权限、审计、兼容迁移与运行维护。实际业务当前4TU，尚未有收益数据证明需要完整质量平台。代价不能因已有约1100行含测试的原型而忽略，也不能因功能写在计划里就高估现有能力。

## 6. 建议的内部设计

保留一个小而完整的外部Interface：以项目运行配置执行scan，并以明确基线执行compare。不要让调用方每次重新拼装多个互有关联的绝对路径和隐含顺序。

建议以一个版本化`ProjectRunSpec`聚合project_id、build_variant、capture记录、scope策略与policy引用，执行时解析成本地路径。实现可继续放在现有Python包内，不引入服务部署或数据库。

内部职责分为四个Module：

1. **BuildContext**：消费实际构建证据，给出完整/选定scope、有效编译语义与输入身份；接捕获工具的Adapter，不实现泛化MSBuild求值。
2. **AnalysisRun**：现有clang-tidy实现负责检查器执行、严格回读、诊断事实和逐TU健康；返回ScanResult并保存RunEvidence。
3. **DiagnosticHistory**：判断报告兼容性、实例匹配、指标恶化与需要人工处理的歧义；数据不充分时不伪造基线一致性。
4. **Reporting**：Markdown/JSON与新增SARIF是实际存在的输出差异，可设置明确Seam；发布回执与运行事实分开。

目前只有一个实际分析器，不必先引入复杂AnalyzerAdapter继承体系；当第二个MSVC实现开始接入时，再据两个实现提取共同Interface。Module深度的目标是调用方知道更少、一次修改覆盖更多调用，而不是把每个函数拆成一个文件。

## 7. 验证顺序与退出条件

1. 固化本轮真实scan→compare复现为测试；明确selected与project scope。
2. 设计并迁移报告v2的上下文/身份兼容规则，保留旧raw证据；不能可靠迁移的旧基线明确拒绝，不静默接受现状。
3. Windows选定一个pilot-cpp真实配置，验证捕获→4TU/SDK解析→诊断报告→上传回执。目录位置不是配置身份，不省略环境信息。
4. 按实际协作平台增加SARIF输出与工程CI；先只提示。后续生产策略必须另经适用域和基线验收，不因新增出口函数而自动启用阻断。

此顺序不要求等完整上游47任务实现才修现有工具缺陷，也不把工具测试通过算成Windows工程M0已验收。

## 8. 结构化评估结果与解释

本轮重新调用plancheck进行候选比较，没有复用此前尚未实现代码时的评分。第一次返回的证据字段将多个文件用分号合并为一个位置，导致有效文件被误判不存在；该轮结果不采纳。第二次以本报告98、102、106行分别作为单一定位锚点成功核验。原始评分、理由和风险见 [评估记录](research/2026-09-15-dec-current-evaluation.json)。

权重为首版适配30%、治理可靠性30%、新增成本25%、职责集中15%。这是当前任务的默认权重，不是用户确认的采购偏好。原始分1–5，成本列越高越贵；加权与风险扣分均来自工具，不手工改分。证据覆盖100%仅指文件锚点可定位，不能理解为Windows兼容或产品选型已100%验证。

| 候选 | 适配 | 可靠性 | 成本（高为差） | 职责集中 | 加权分 | 风险扣分 | 最终分/工具等级 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| A 补强现有运行器 | 4 | 3 | 3 | 4 | 69 | 42 | 27 / 不推荐直接采用 |
| B 平台承接治理 | 2 | 2 | 4 | 4 | 46 | 51 | 0 / 不推荐直接采用 |
| C 完整自建 | 2 | 2 | 5 | 2 | 35 | 36 | 0 / 不推荐直接采用 |

**解释**：A在当前条件下相对最适合作为后续开发方向；工具明确三者均未达到推荐阈值，因此不能把相对第一说成已可上线。A的主要扣分来自已复现的身份/scope缺口、Windows未实扫、报告迁移与远程CI未验证。B/C的低分是本项目准备度和新增成本评估，不是Sonar等产品质量评分。

当前建议是优先实施A中的缺陷修复和真实接入验证，再决定是否增加B的平台适配。已有平台/许可证或多人治理需求得到确认后，应按新事实重评B；不把本轮排序当永久厂商选择。C需先证明持续治理需求和维护能力，不能以“已有原型”推导应完成全部平台自建。

本轮未改cpp实现、pilot-cpp源码或桌面计划；实现缺陷仍保留，等待明确的修复任务。
