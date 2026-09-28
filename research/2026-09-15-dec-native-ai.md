# DEC 执行计划：原生 C++ 检查与 AI 协作方案核验

核验日期：2026-09-15。评审对象为桌面原文修订四。本文不执行原文任务，也不修改原文。以下“官方事实”来自本次实际联网读取的一手资料；“对 DEC 的判断”是基于这些事实的分析。

## 1. 主要结论

- DEC 的“三机制：生成侧约束 + 算术门禁 + 人工检查点”能映射到现成工具组合，但它不是一个现成产品的安装指南；来源保护、实例迁移、逐规则晋升及授权评估构成额外的治理软件开发。
- clang-tidy 的现成复杂度能力足以开展提示试点；“有默认数值”不等于“存在适用于本工程的文献阈值”，且嵌套默认不开阈值。
- MSVC 应作为具有独立规则覆盖的补充通道。仅从支持规则集、SARIF 或分析能力，不能推出与 clang-tidy 复杂度规则语义对等。
- 本次所读官方资料没有建立覆盖任意编辑器、复制粘贴、混合编辑及历史提交的通用人/AI来源判定。只能说 DEC 的可信记录与保护规则需要额外实现，不能断言“所有市场产品均无来源能力”。
- Copilot code review 官方当前已记录可选 AI 审批的公共预览功能；不能继续沿用“Copilot 永远只能评论、不能批准”的旧结论。

## 2. clang-tidy：最直接的族 A 工具基础

### 官方事实

1. `readability-function-cognitive-complexity` 按 SonarSource Cognitive Complexity 规范 1.2（2017-04-19）实现，`Threshold` 默认 25。文档明确排除预处理条件与递归环完整计分，后者需要当前检查器不支持的跨翻译单元分析。[L1]
2. `readability-function-size` 可控制行数、语句数、分支控制语句数、参数、嵌套和局部变量。当前文档中 `StatementThreshold` 默认 800；`LineThreshold`、`BranchThreshold`、`NestingThreshold` 等默认 `none`。`BranchThreshold` 统计控制语句，不应直接称作圈复杂度。[L2]
3. `run-clang-tidy.py` 消费编译数据库进行项目扫描；`clang-tidy-diff.py` 是报告行过滤，实际仍分析整个文件，所以不带来对应的分析性能缩减。[L3]
4. `NOLINT` 只抑制同一行，`NOLINTNEXTLINE` 对下一行，`NOLINTBEGIN/END` 对范围；范围配对及参数必须一致，否则产生 `clang-tidy-nolint` 诊断。[L3]

### 与 DEC 的差异及建议

- 保留 `T-DEC-02` 的编译配置与覆盖验收，这比“存在 compile_commands.json”更贴合语义扫描需求。
- `T-DEC-20` 的“三项检查”应写出确切检查器 ID 和指标公式。不能把 function-size 的 BranchThreshold 充作真正的圈复杂度检查；本次未在所读检查清单找到可据以确认的独立通用圈复杂度检查器，应另行明确工具或自研来源。[L2, L4]
- §0“工具现成、有文献阈值”证据过强。默认 25 是工具默认；嵌套没有默认上限。更准确的是“部分指标有成熟检查器与公开定义，阈值仍按固定版本与工程校准”。
- 对函数级复杂度，若变化发生函数体内而诊断锚点落在未改动的声明行，纯 diff 行过滤存在漏报风险。这是基于过滤机制的推论；应采用完整受影响诊断作用域扫描与实例比较验证，不能把 diff 报告当成完整新增违规判定。[L3]
- 这些网页当前页脚为 **Clang Extra Tools 24.0.0git** 开发中资料，不应声称就是用户本地版本。必须锁定已安装工具并回读配置。

## 3. MSVC /analyze：原生构建通道与可审计输出

### 官方事实

1. `/analyze` 支持 `/analyze:ruleset`，可输出 SARIF；可记录分析文件和配置，支持 `/analyze:log:includesuppressed`。[M1]
2. **即使启用 includesuppressed，规则集禁用的诊断也不写入日志。** 所以“看不到诊断”不能反推“没有违规/豁免”。[M1]
3. `.ruleset` 可配置规则动作，模式包括 Error、Warning、Info、Hidden、None，并能包含其他规则集。[M2]
4. `#pragma warning(suppress:...)` 对下一行局部生效，`disable` 可配合 `push/pop` 管理范围。`justification` 字段从 Visual Studio 2022 17.14 引入，可在相应 SARIF 输出中保存理由；官方建议适用时优先使用 `[[gsl::suppress]]` 抑制 C++ Code Analysis 警告。[M3]

### 与 DEC 的差异及建议

- `T-DEC-13` 的“MSVC 一份语法清单”需要至少涵盖局部 suppress、push/pop、属性、规则集禁用四种实际作用域，不能只查源码里的 disable。
- `T-DEC-61` 的豁免扫描应联合有效规则集和抑制诊断；仅扫描源码或 SARIF 任一方都会遗漏部分状态。[M1–M3]
- 规则动作可做渐进启用，但规则集自身不能表达 DEC 所要求的“可信 AI 新增实例才阻断、人类保护仅提示”。这仍需上层策略执行器。
- 本次资料能证明 MSVC 的配置与输出能力，不能单凭这些页面证明某个复杂度规则“确无对等实现”。原文单通道判断应在锁定版本后给出具体规则目录、ID 搜索与样本依据。

## 4. GitHub Copilot：自然语言约束、AI评审与可选审批

### 官方事实

1. 仓库全局指令可使用 `.github/copilot-instructions.md`；路径指令使用 `.github/instructions/*.instructions.md` 与 `applyTo`，支持按 agent 排除。[G1]
2. Copilot code review 并不保证发现所有问题，也可能出错，官方要求验证反馈并辅以人工评审。[G2]
3. 当前 **Copilot approvals 为公共预览**。默认 AI 评审不计入必需审批；在相关设置开启后，可以提交满足 required-approval rule 的批准。新提交会使该批准失效，需重新请求评审。[G2]
4. 官方同时区分 Copilot AI 评审与 GitHub Code Quality 的 CodeQL 规则分析、覆盖率、可选 ruleset 合并门禁。[G2, G3]
5. **GitHub Code Quality 当前规则分析语言列有 C#、Go、Java、JavaScript、Python、Ruby、TypeScript，没有 C++。** 其 AI 分析覆盖范围可以超出这些语言。不能把 CodeQL 本身支持 C++ 推导成该产品的规则分析支持 C++。[G3]

### 与 DEC 的差异及建议

- 自然语言指令适合表达“四问”和拆分例外，不是可重复计算的复杂度检查替代品。
- D7 影子评估、误判/漏判与撤销条件，显式程度高于所读 Copilot 配置说明；是 DEC 的治理增量，但会带来样本与人工裁决成本。
- “AI审批”不等于“自动编辑授权”。DEC 必须将生成建议、写入代码、提交 PR、批准 PR、允许合并几个权限拆开；当前 D7 的“授权”若没有动作清单，容易套用错误的产品能力。
- GitHub Code Quality 可以参照其“规则扫描 + AI 解释”分层模式，但当前不能当成 C++ 族 A 的直接替代检查器。

## 5. Claude Code：事件钩子与检查器集成

### 已核实官方事实

Anthropic 官方 `anthropics/claude-code` 仓库的 hook-development 技能资料区分 prompt hooks 与 command hooks：后者用于确定性校验、外部工具集成；`PreToolUse` 可允许、拒绝、修改工具调用，`PostToolUse` 可处理结果，`Stop` 可校验完成状态。[A1]

### 与 DEC 的差异及证据限制

- 可将“AI执行时运行 clang-tidy 并反馈”接到事件钩子，避免先做通用来源推断才开始获得收益；若仍需原文的人类保护准则，则 hook 中必须消费受保护范围记录，并对最终内容执行校验。这是工程建议，不是现成产品承诺。
- 钩子只约束经过该客户端相应事件的动作；如果 Git 提交或内容修改可通过其他路径发生，仍要在 CI/服务端做独立验证。这是由事件作用域导出的判断。
- 本次 `code.claude.com/docs/en/memory`、`hooks`、对应 `.md` 及旧域名页面均返回 **403**，官方 best practices 页面也返回 403。因此不对 CLAUDE.md 当前自动加载细则、优先级或保证作新的事实断言。
- 可核实的 hook 资料为官方仓库 `main` 上技能文件（文件自标 `version: 0.1.0`），不是对当前所有客户端版本接口的完整保证；实施时仍需锁定客户端版本和验证输出格式。

## 6. 原文应优先澄清的差异

1. **指标定义与默认值**：准确列出 cognitive complexity / cyclomatic complexity / function-size / nesting 的检查器与口径，不用“复杂度”统称。
2. **来源保护的成本与边界**：只管理可信记录，不能承诺从任意历史代码恢复来源；“未知仅提示”的策略会降低自动门禁覆盖，覆盖率应成为可见运营指标。
3. **规则禁用也是配置状态**：规则集禁用不会自动作为抑制诊断出现在 SARIF，台账必须读取有效配置。
4. **权限对象明确**：AI评审、批准、写入和合并是不同动作，D7 必须标记授权到底允许哪种动作。
5. **产品及工具版本锁定**：LLVM latest 是开发文档；VS justification 有明确最低版本；Copilot审批为公共预览；GitHub Code Quality 当前没有 C++ 规则分析。

## 一手来源

- [L1: LLVM function-cognitive-complexity](https://clang.llvm.org/extra/clang-tidy/checks/readability/function-cognitive-complexity.html)
- [L2: LLVM function-size](https://clang.llvm.org/extra/clang-tidy/checks/readability/function-size.html)
- [L3: LLVM clang-tidy usage](https://clang.llvm.org/extra/clang-tidy/)
- [L4: LLVM check list](https://clang.llvm.org/extra/clang-tidy/checks/list.html)
- [M1: Microsoft /analyze](https://learn.microsoft.com/en-us/cpp/build/reference/analyze-code-analysis?view=msvc-170)
- [M2: Microsoft C++ rulesets](https://learn.microsoft.com/en-us/cpp/code-quality/using-rule-sets-to-specify-the-cpp-rules-to-run?view=msvc-170)
- [M3: Microsoft warning pragma](https://learn.microsoft.com/en-us/cpp/preprocessor/warning?view=msvc-170)
- [G1: GitHub repository instructions](https://docs.github.com/en/copilot/how-tos/configure-custom-instructions/add-repository-instructions)
- [G2: GitHub Copilot code review](https://docs.github.com/en/copilot/concepts/agents/code-review)
- [G3: GitHub Code Quality](https://docs.github.com/en/code-security/concepts/code-quality/code-quality)
- [A1: Anthropic official hook-development skill](https://raw.githubusercontent.com/anthropics/claude-code/main/plugins/plugin-dev/skills/hook-development/SKILL.md)

访问方式：Python urllib 联网读取官方 HTML 或 raw GitHub 文本。访问失败的页面只作为证据限制，不作为结论来源。网页随时间更新，本文描述本次读取内容。
