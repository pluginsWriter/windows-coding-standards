# 当前 DEC C++ 实现与主流能力：一手证据复核

日期：2026-09-15。本文为当前源码的市场能力证据补充；不修改实现和执行计划，不代替完整代码评审或方案评分。阅读了 cpp/README.md、dec/comparison.py、diagnostics.py、runner.py、compilation.py、project.py。以下官方页面均在本轮重新 HTTP 读取，未用旧调研结论替代核验；未安装或实际运行任何商业产品，未运行目标 Windows 工程。

## 1. 最影响当前设计的事实

1. **Windows/MSBuild 编译采集已有官方实现，不应把手写 MSBuild 求值器作为默认下一步。** Sonar CFamily 官方文档本次成功访问（此前报告的 403 限制不再适用于此次这页），明确 Build Wrapper 在 Windows 上包裹 clean build，输出 compile_commands.json；MSBuild 要关闭 node reuse。它与 Sonar CFamily 版本绑定，不能据此承诺可脱离产品授权使用。[S1]
2. **SARIF 是交换结构，不是跨重构身份算法。** GitHub 明确要求稳定 ruleId、稳定路径；同一问题路径变化会关闭旧告警并创建新告警。接 SARIF 值得做，但不能声称因此解决当前三行上下文指纹、文件移动或重命名匹配。[S2]
3. **现有实现更接近“可信分析运行器”，不是完整质量平台。** 严格配置、逐 TU 覆盖、失败证据和只读输入检查值得保留；成熟平台优势在基线生命周期、问题状态、人工作业和 PR 门禁，而不仅是检测规则更多。
4. **先解决真实构建和跨 CI 可比较性，再扩大自研治理。** 当前比较要求 source_root 绝对路径相同，detection_fingerprint 又包含分析器二进制哈希和绝对化编译命令；在不同工作区、runner、工具安装之间保守拒绝是安全选择，但也限制了 PR 与主分支报告复用。应将严格原始证据指纹与明确规则的“分析语义兼容标识”分开，不能简单删除路径或工具校验。
5. **当前指标恶化属于补充能力，不能用平台“新增计数”直接替换。** comparison.py 对同身份认知复杂度数值做比较；Qodana 文档的 baseline gate 是新增问题数，不证明能阻止同一旧问题指标从 30 升到 50。[S3][S4]

## 2. 能力对比

| 方案 | 本轮已核验的可复用能力 | 当前 DEC 差距或可保留部分 | 适配边界 |
| --- | --- | --- | --- |
| clang-tidy 官方工具链 | 原生检查、结构化 export-fixes、run-clang-tidy 并行、diff 辅助脚本 [S5] | DEC 增加严格配置回读、逐 TU 证据、只读比较；没有必要重新写检测引擎 | diff 过滤不是完整新增诊断判定；官方提醒会漏掉变更间接造成且报告在未改行的问题 |
| MSVC /analyze | Windows 原生分析；SARIF、analyzedfiles、configuration、includesuppressed 输出参数 [S6] | DEC 尚只有 clang-tidy 适配；接入另一通道需要规则语义映射，不应假设同名指标对等 | 被规则集禁用的诊断不会因为 includesuppressed 出现在日志；仍需有效配置审计 |
| Sonar CFamily / SonarQube | 官方 Windows/MSBuild Build Wrapper 编译采集、真实构建约束 [S1] | 优先验证现有 capture，再决定是否需要自研；DEC 可继续消费经过验证的数据库 | Wrapper 要与对应 CFamily 匹配；本轮不据此作许可、价格或全平台功能采购承诺 |
| Qodana 2026.2 | C++ linters；SARIF 基线 New/Unchanged/Absent；新增问题质量门禁；GitHub required check 接入 [S3][S4][S7] | 避免自建基线 UI、全套问题展示；同一实例指标恶化仍需 DEC 补充验证 | C++ 为 Docker 镜像；未证明 pilot-cpp 的 Windows SDK/MSVC-only 依赖可直接在其环境运行 |
| PVS-Studio | 存量告警基线/抑制文件，Visual Studio solution/project 接入；新增告警可继续展示 [S8] | 可借用成熟实例处置机制，而不是每轮自动接受最新报告 | 本轮捕获文档入口 404，未完成捕获功能核验；不把 PVS 自身基线当 clang-tidy 告警的通用基线 |
| GitHub code scanning + SARIF / CodeQL | partialFingerprints 跨运行关联；按必需工具和阈值配置 merge protection；CodeQL none/autobuild/manual [S2][S9][S10] | DEC 缺标准 SARIF 导出、稳定分析类别及生产 check；平台可承担展示和强制合并规则 | CodeQL 安全查询不等于拆分指标；手动构建只分析实际构建范围；SARIF 不保证路径移动连续身份 |

## 3. 可执行的设计边界

建议把下面视为设计候选约束，具体主路线仍由整体方案评估确定：

- **BuildContext**：记录 repo 身份、commit/dirty snapshot、目标架构、配置、捕获器、编译器/SDK/INCLUDE 等环境、编译数据库；捕获与分析尽量在同一 Windows 环境完成。不通过 XML 静态推测代替真实 MSBuild 求值。
- **AnalyzerAdapter**：现有 clang-tidy runner 是第一实现，输出检测事实与健康状态；新增 MSVC 时保留各工具规则身份和配置，不强造规则等价关系。
- **RunEvidence 与 Finding**：保留原始命令与 stderr；统一内部诊断模型并导出 SARIF。运行状态和发布状态另存，上传失败不得伪装为扫描无违规。
- **ComparisonPolicy**：将严格证据哈希和可兼容比较条件分开；基线绑定 repo/分支/构建变体和版本化匹配策略。路径归一化必须有显式映射及碰撞测试，不能抹去配置差异。
- **PlatformAdapter**：由现成平台承担诊断展示和分支保护；DEC 仅补平台没有的认知复杂度恶化、适用范围保护等政策。未验证前保持 advisory。

首先补 Windows 真工程一次完整构建/扫描/报告发布链路。通过后再评估基线迁移、低水位/重现、原生 SARIF、第二检测通道；不要先扩展 SLA 自动降级或 AI 作者推断。

## 4. 官方证据与简短摘录

### S1：Sonar CFamily prerequisites（本轮 HTTP 200）

https://docs.sonarsource.com/sonarqube-server/analyzing-source-code/languages/c-family/prerequisites

实际读取要点：

- “At the end of your build, a compile_commands.json file should be generated…”
- “Build Wrapper must be downloaded directly from your SonarQube Server instance so that its version perfectly matches your version of the CFamily analyzer.”
- “we advise turning off this feature using the nodeReuse:False command-line option.”
- 分析应与构建环境一致；Visual Studio Developer Command Prompt 设置的 INCLUDE 等环境变量必须在分析时有效。
- Wrapper 输出包含绝对路径和环境信息；容器/跨主机使用需要额外处理。文档明确 SonarScanner CLI Docker image 不支持此 compilation-database 分析方式。

由此只能推出产品已提供成熟捕获方案，不推出其数据库对当前固定的 clang-tidy 21.1.6 开箱兼容，也不推出可无许可证脱离产品复用。接入仍需本机试验。

### S2：GitHub SARIF support（HTTP 200）

https://docs.github.com/en/code-security/reference/code-scanning/sarif-files/sarif-support

“code scanning uses fingerprints to match results across various runs”；“The filepath has to be consistent across the runs”。路径不同会创建新告警并关闭旧告警。upload-sarif 可尝试补 partialFingerprints；REST 直接上传缺指纹可能重复。

### S3：Qodana baseline（HTTP 200；页面日期 2026-09-01）

https://www.jetbrains.com/help/qodana/baseline.html

比较当前代码与 baseline，区分 new、unchanged、resolved；默认基线文件 `.qodana/baseline.sarif.json`。状态包含 New/Unchanged/Absent。新增问题不会随普通扫描自动变成存量，须更新基线。

### S4：Qodana quality gate（HTTP 200；页面日期 2026-08-25）

https://www.jetbrains.com/help/qodana/quality-gate.html

“If you run Qodana with the quality gate and the baseline features enabled, a threshold will be calculated as the sum of new problems.” 失败退出码 255；另需设置 required status checks 才阻止 GitHub 合并。未用平台其他语言覆盖率能力推断 C++ 覆盖率门禁。

### S5：clang-tidy（HTTP 200；滚动文档）

https://clang.llvm.org/extra/clang-tidy/

官方提供 run-clang-tidy 并行和 clang-tidy-diff.py。后者只报告 diff 行，官方明确这可能产生 incomplete analysis：变更引起的某些告警位置不在变更行。应将“选择分析范围”与“诊断身份增量”区分。

### S6：MSVC /analyze（HTTP 200；msvc-170 文档视图）

https://learn.microsoft.com/en-us/cpp/build/reference/analyze-code-analysis?view=msvc-170

提供 `/analyze:log:format:sarif`、`/analyze:sarif:analyzedfiles`、`/analyze:sarif:configuration` 和 `/analyze:log:includesuppressed`。规则集禁用的诊断不进入日志。配置回读/审计仍不能由诊断日志代替。

### S7：Qodana C/C++（HTTP 200；2026.2）

https://www.jetbrains.com/help/qodana/clang.html

商业 qodana-cpp（Ultimate/Ultimate Plus）与社区 qodana-clang 均支持 C++，Docker 分发；商业版本包括 CLion inspections、MISRA 和 dataflow。页面列可选 clang 15–18，当前 DEC 工具版本需单独比较。商业版 .clang-tidy 中 `-*` 不会禁用 Qodana profile 已启用检查，不能盲目复用现有严格配置判断。

### S8：PVS-Studio baseline（HTTP 200）

https://pvs-studio.com/en/docs/manual/0032/

文档说明 suppress 文件、项目与 solution 的存量抑制管理，允许不修改源码接入。它解决存量告警治理，但本轮未实测重命名/指标恶化语义，也未证明能直接用于其他分析器原始报告。尝试捕获页 `/en/docs/manual/0082/` 与手册索引 `/en/docs/manual/` 均 404，故不把捕获相关判断作为已核验结论。

### S9：GitHub merge protection（HTTP 200）

https://docs.github.com/en/code-security/how-tos/find-and-fix-code-vulnerabilities/manage-your-configuration/set-merge-protection

`Require code scanning results` 与 `Required tools and alert thresholds` 是实际平台交付项。扫描脚本 return 0 与分支规则真的要求这个扫描，是两个独立条件。仓库可用套餐和权限需接入时核验。

### S10：CodeQL compiled languages（HTTP 200）

https://docs.github.com/en/code-security/how-tos/find-and-fix-code-vulnerabilities/manage-your-configuration/codeql-for-compiled-languages

支持 none/autobuild/manual。none 可能因依赖推断和生成代码降低准确性；manual “will analyze whatever source code is built by your specified build steps”。不能用分析成功替代目标配置覆盖证明。
