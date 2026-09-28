# 拆分治理执行计划：主流平台一手资料比较

调研日：2026-09-15。范围：SonarQube、GitHub CodeQL/code scanning、JetBrains Qodana。本文只核验产品机制，不认为任何产品已实现附件全部自定义拆分规则；未安装或运行产品。官方网页通过 HTTPS 实际读取；Sonar 文档返回 403，改读官方开源服务端源码，并明确未验证项。

## 可直接用于评审的结论

1. **按新增问题拦截、存量建立基线，是可复用机制，并非需要从零发明。** Qodana 明确维护 new/unchanged/absent 诊断状态；GitHub 用 fingerprints 跨运行匹配同一问题；Sonar 内置 gate 使用新代码指标。三者的“new”定义并不相同，不能直接互换配置。
2. **不能说 Qodana 不支持 C++。** 实际读取的 Qodana 2026.2 官方资料明确包含商业 `qodana-cpp` 与社区 `qodana-clang`。C++ 专页更新日期 2026-08-25，linters 总览 2026-07-31。不能把旧版本产品认知套到当前方案。
3. **人/AI 来源保护不等于分析平台的质量豁免。** 已核验的基线、状态转移、门禁机制都围绕诊断、变更范围、严重度与授权处置。未在这些页面发现附件那种逐行创作归属保证；这只是本次已读资料中的差异，不能据此断言厂商不存在任何 AI 代码能力。
4. **同样写着 clang-tidy，不代表规则配置语义相同。** Qodana 商业 C++ 会用 `.clang-tidy` 增补自身 inspection profile，`-*` 不会关闭 profile 中已启用规则。附件的单一配置宿主需要语义映射及一致性测试，不能只比文件值。
5. **“支持 C++”与“完整覆盖当前 Windows/MSVC 构建”必须分开验收。** CodeQL manual 只分析实际构建代码；none 模式存在依赖猜测/生成代码精度限制。Qodana 本次文档明确 Docker 交付，未实际证明当前项目 Windows SDK/MSVC-only 代码可完整分析。

## 对比表

| 维度 | SonarQube（本次核验范围） | GitHub CodeQL / code scanning | Qodana 2026.2 |
|---|---|---|---|
| 主要机制 | 服务端质量门禁和问题工作流 | CodeQL 分析器 + code scanning SARIF 汇总和合并门禁 | CI 检查、SARIF 基线、质量门禁、CLion/clang-tidy 能力 |
| 增量依据 | 内置 Sonar way 使用 NEW_* 指标，具体 new-code 定义页面未成功读取 | fingerprints 保持问题身份；merge protection 可要求指定工具及告警阈值 | `baseline.sarif.json` 区分 New / Unchanged / Absent |
| 门禁粒度 | 新违规数、新覆盖率、新重复率、新热点复核率（当前源码） | 按工具、告警严重度与 security severity 配置 | 总问题数或按严重度；配 baseline 时对新问题计数 |
| 误报/风险接受 | accept / false-positive 转移有 Administer Issues 权限要求 | 本次未深入核验 dismiss 工作流，不作实现细节断言 | 本次核验 baseline 接受存量，不把它等同独立误报工作流 |
| C++ 分析 | CFamily 构建前提页面 403，本次未完成验证 | none / autobuild / manual，manual 分析实际编译范围 | 商业 cpp 有 CLion 检查含 MISRA/dataflow；社区 clang 为 clang-tidy |
| 附件仍需自建部分 | 自定义规则、作者保护记录、观测晋升与 SLA 编排 | 同左；不能把通用 SARIF 门禁当成现成拆分规则 | 同左；另外必须处理 profile 与 .clang-tidy 的语义差别 |

## 1. SonarQube：已证实的机制与证据边界

Sonar 文档入口 `https://docs.sonarsource.com/sonarqube-server/user-guide/clean-as-you-code`、quality-gates、issue reviewing、CFamily prerequisites 及 `.md` /版本路径请求均返回 HTTP 403。因此不将这些页面作为已经读到的证据，也不报告商业版本价格或 CFamily 支持矩阵。

可读取的一手替代来源：

- [SonarWayQualityGate.java，SonarSource 官方仓库](https://github.com/SonarSource/sonarqube/blob/master/server/sonar-server-common/src/main/java/org/sonar/server/qualitygate/builtin/SonarWayQualityGate.java)。实际源码：`new Condition(NEW_VIOLATIONS_KEY, GREATER_THAN, "0")`，并列 NEW_COVERAGE <80、NEW_DUPLICATED_LINES_DENSITY >3、NEW_SECURITY_HOTSPOTS_REVIEWED <100。说明该内置 gate 以新代码指标构成失败条件；不是建议附件机械照抄这些数值，也不意味着每个发布版本/商业 gate 一样。
- [DoTransitionAction.java，SonarSource 官方仓库](https://github.com/SonarSource/sonarqube/blob/master/server/sonar-webserver-webapi/src/main/java/org/sonar/server/issue/ws/DoTransitionAction.java)。源码文案：`The transitions '%s', '%s' and '%s' require the permission 'Administer Issues'.` 参数为 ACCEPT、WONT_FIX、FALSE_POSITIVE；changelog 说明 10.4 添加 ACCEPT 并弃用部分旧转移。实现调用 `transitionService.checkTransitionPermission` 并记录用户与时间上下文。可复用的是**有权限、可追溯的实例处置**，不只是全局降级规则。

以上源码来自调研时 master 分支，是可变的开发分支证据；未据此宣称具体已发布版本功能完全一致。CFamily compilation database、build-wrapper 与授权版本需在正式选型时继续查证。

## 2. GitHub CodeQL / code scanning

### 构建模式与覆盖边界

官方：[CodeQL code scanning for compiled languages](https://docs.github.com/en/code-security/how-tos/find-and-fix-code-vulnerabilities/manage-your-configuration/codeql-for-compiled-languages)。

已读取短摘录：

> For C/C++, C#, Java and Rust, CodeQL creates a database without requiring a build when you enable default setup ...

> Creating a CodeQL database without a build may produce less accurate results ...

> CodeQL will analyze whatever source code is built by your specified build steps.

`none` 便于启动，但构建脚本依赖信息无法取得、依赖猜测不准或存在构建生成代码时，结果可能较不准确。manual 能限定真实构建，也因此不能保证未被该构建包含的变体都覆盖。官方建议先用 default setup 上线，再对高风险仓库考虑 manual；这是降低接入门槛的渐进路线，不能替代附件晋升前对目标分析范围的验证。

### 问题身份与 SARIF

官方：[SARIF support for code scanning](https://docs.github.com/en/code-security/reference/code-scanning/sarif-files/sarif-support)。

> code scanning uses fingerprints to match results across various runs

> The filepath has to be consistent across the runs to enable a computation of a stable fingerprint.

`ruleId` 需跨分析一致。GitHub 使用 `partialFingerprints` 匹配逻辑相同结果；CodeQL 产出自带 fingerprint。通过 upload-sarif action 上传时缺失则尝试从源码补算；直接 REST API 上传且缺 fingerprint 可能重复。**不能据此许诺“任何文件重命名都自动匹配成功”**，文档明确稳定路径前提。附件应复用 SARIF 同时补移动/重命名测试。

参考实现：[github/codeql-action fingerprints.ts](https://github.com/github/codeql-action/blob/main/src/fingerprints.ts)；本次只确认官方文档将其作为参考链接，未审阅实现。

### 合并门禁

官方：[Set code scanning merge protection](https://docs.github.com/en/code-security/how-tos/find-and-fix-code-vulnerabilities/manage-your-configuration/set-merge-protection)。

页面明确创建 ruleset、选择 `Require code scanning results`，在 `Required tools and alert thresholds` 添加 CodeQL 等工具并设告警阈值；REST API 提供 `code_scanning` rule。因此“扫描命令成功”和“分支强制要求扫描结果”是不同层次，执行计划需要把平台 merge protection 配置作为交付件。

本次没有用该页面推导全部 missing/pending/failed 细节，也未核验每类仓库套餐权限；产品采购前需继续核实。CodeQL 的安全扫描能力不能直接等同附件的文件长度、命名和拆分规则现成覆盖率。

## 3. JetBrains Qodana 2026.2

### C++ 支持范围已正面确认

官方：[Overview of linters](https://www.jetbrains.com/help/qodana/linters.html)；[C / C++](https://www.jetbrains.com/help/qodana/clang.html)。

专页摘录：

> The C/C++ family of linters lets you analyze C and C++ projects ... CMake or provide a compile_commands.json file.

商业 `qodana-cpp`：Ultimate / Ultimate Plus，Docker，完整 CLion inspections，包括 clang-tidy、MISRA、dataflow inspections。社区 `qodana-clang`：Community，Docker，clang-tidy-based inspections。两者支持 AMD64、ARM64。可选 clang 标签为 15–18；社区实现说明默认 Clang 16，不能假设和最新系统 LLVM 版本一致。

社区默认读 `build/compile_commands.json`；商业版可按 CLion 支持的构建系统自动配置，亦支持根目录编译数据库。路径映射、容器依赖与编译参数仍需处理。本次没有进行 Windows SDK 适配实验，因此不可把 Docker 架构支持扩展成 Windows/MSVC 原生支持保证。

配置关键摘录：

> Unlike stand-alone Clang-Tidy, the -* directive does not disable inspections enabled by your Qodana profile ...

关闭 profile 规则需在 `qodana.yaml` 的 exclude 配置。此处是附件双通道一致性需要真实测试的反例。

### 基线：实例状态，而非旧计数相减

官方：[Baseline](https://www.jetbrains.com/help/qodana/baseline.html)（2026-09-01）。

> compare your current code to its baseline state and see new, unchanged, and resolved problems.

SARIF 基线属于某次分析、某 Git 分支；支持所有 linters。默认 `.qodana/baseline.sarif.json`。状态为 New / Unchanged / Absent，`--baseline-include-absent` 可输出已消失问题。**新问题不会随着扫描次数增多自动成为存量**；需要更新 baseline 才改为 unchanged。附件应同样把接受新债务和普通重扫分开。

### 门禁

官方：[Quality gate](https://www.jetbrains.com/help/qodana/quality-gate.html)（2026-08-25）。

> If you run Qodana with the quality gate and the baseline features enabled, a threshold will be calculated as the sum of new problems.

失败退出码 255；支持总量与分严重度阈值，C++ 不在覆盖率门禁支持清单中，因此不要把 Qodana 平台其他语言的 coverage gate 算作 C++ 已有能力。页面展示将 Qodana 检查加入 GitHub required status checks 才阻止合并。

## 对执行计划的可复用改进

1. 定义统一 SARIF 输出与稳定 ruleId，但为跨版本、路径移动、宏/模板实例匹配单独设计验收，不把 SARIF 格式本身当去重算法。
2. 平台负责基线、诊断展示、门禁与实例处置；只为平台缺少的拆分规则和治理政策编写扩展，避免重复建设完整质量平台。
3. 把规则“检测到”与“有权修改/必须修复”分开。用户手写保护可以约束自动修改，不需要销毁诊断事实。
4. 接入验收必须包含实际编译范围、解析失败、工具版本与配置语义；不要只检查 compilation database 文件存在。
5. 明确扫描 job、报告上传、规则判定、平台 required check 四层状态，分别保留失败/未检查与无违规的区别。
