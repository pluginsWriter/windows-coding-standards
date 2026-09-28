// CLM-004a 夹具：NOLINT 注释单独放在诊断行的【前一行】。
// 声明（预期行为）：这样写【不能】抑制下一行 —— 诊断仍应报出。
// 若诊断被抑制了，说明声明错误（FAIL）。
// NOLINT(readability-named-parameter)
int f(int) { return 0; }   // 诊断应出现在这一行（未具名参数）
