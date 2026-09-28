// CLM-005 实验组：#pragma warning(push) + disable 之后【故意不写 pop】。
// 声明（预期行为）：抑制泄漏到翻译单元末尾 —— 后续所有函数的 C4100 都不再报。
#pragma warning(push)
#pragma warning(disable : 4100)
int intended(int unused) { return 1; }     // 有意抑制（预期范围内）
// 此处故意不写 pop —— 模拟 DEC 计划 T-DEC-61 说的范围泄漏陷阱
int leaked(int also_unused) { return 2; }  // 预期：也被吞掉（这就是泄漏的证据）
