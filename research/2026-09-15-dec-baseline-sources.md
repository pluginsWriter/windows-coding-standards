# DEC 市场对比补充取证：Cppcheck、PVS-Studio 与 SARIF

核验日期：2026-09-15。仅依据本次成功读取的官方页面，不是安装运行结果。执行文档未修改。

## PVS-Studio：已有实例基线，不需要改源码

来源：[Baselining analysis results](https://pvs-studio.com/en/docs/manual/0032/)，页面日期 2026-08-10。

官方说明已有大量存量告警时，可以先在新增代码上使用分析器，以后再处理存量；也可以在不修改源码的情况下抑制误报。支持 C/C++ 等语言，提供 Windows Visual Studio 集成。

关键原文：

> This mode doesn't require modification of the project's source files.

> line shift, will not lead to the re-emergence of these messages.

匹配字段为：前一行、当前行、后一行的哈希，文件名（区分大小写），诊断 ID，标准化消息。移动这三行或改变空格通常保留抑制；修改附近内容、文件名、诊断 ID 或消息可能使告警重现。

对 DEC 的意义：T-DEC-44 的实例身份方向有成熟先例，不能声称属于全新机制；同时，成熟产品也有明确边界，不承诺任意重命名后都完美追踪。应先试用所选平台的基线语义，验证差额，再决定自研范围。产品基线不等于天然满足 DEC 的全部整改退出、跨工具合并或来源保护要求。

## Cppcheck：轻量 C/C++ 检查、项目导入与抑制

来源：[Cppcheck manual](https://cppcheck.sourceforge.io/manual.html)。

官方定位：检测 C/C++ 未定义行为和危险构造，努力减少误报，但明确不保证发现所有缺陷。可导入 Visual Studio 项目或 `compile_commands.json`，也允许手工配置分析范围。

官方支持 `--suppressions-list`、XML suppressions（可含 id/fileName/lineNumber/symbolName）及源码内抑制。`--cppcheck-build-dir` 保存分析信息，复查时复用未改变文件的结果。

对 DEC 的意义：这是成本较低的补充检测器，不是完整拆分治理平台。缓存导致的增量分析是性能优化，不等于基线上的“只阻断新增诊断”。不能因工具支持 C++ 就断言内置纯转发、god module 或命名词数预算等 DEC 项。

## GitHub SARIF：跨次扫描的诊断指纹

来源：[SARIF support for code scanning](https://docs.github.com/en/code-security/reference/code-scanning/sarif-files/sarif-support)。请求旧地址自动跳转至该现行地址。

官方使用 `partialFingerprints` 匹配不同扫描的同一问题；要求 ruleId 稳定、文件路径一致。CodeQL 产生的 SARIF 已含指纹；`upload-sarif` 在缺指纹时尝试从源码补齐，而直接通过 API 上传缺指纹结果可能出现重复告警。

关键原文：

> code scanning uses fingerprints to match results across various runs

> The filepath has to be consistent across the runs to enable a computation of a stable fingerprint.

对 DEC 的意义：优先采用标准诊断格式及平台匹配机制，但 SARIF 不是万能去重器；它不自动解决不同检查器规则等价性、作者来源判定，也不保证任意文件改名无影响。

## 取证边界

以上为成功读取的一手文档。未测 Windows 真实工程、执行时长、误报率、许可证采购条件或 DEC 全规则覆盖。PVS 另一次对 `/en/docs/manual/0040/` 的访问未取到可支撑本报告的增量结论，故未据此引用。
