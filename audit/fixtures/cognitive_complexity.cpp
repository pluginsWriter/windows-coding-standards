// CLM-003 夹具：认知复杂度样本
// 目标：超过 readability-function-cognitive-complexity 默认阈值 25，触发诊断。
// 若在真机上未触发：先加深嵌套重试；仍不触发则检查名不可用，按 FAIL 处理并人工复核。
int deep(int a, int b, int c) {
  int r = 0;
  if (a > 0) {                    // +1
    if (b > 0) {                  // +2
      if (c > 0) {                // +3
        if (a > b) {              // +4
          if (b > c) {            // +5
            if (a > c) {          // +6
              r += 1;             // 小计 21
            }
          }
        }
      }
    }
  }
  if (a < 0) {                    // +1
    if (b < 0) {                  // +2
      if (c < 0) {                // +3
        r -= 1;                   // 小计 6
      }
    }
  }
  for (int i = 0; i < a; ++i) {   // +1
    if (i % 2 == 0) {             // +2
      r += i;                     // 小计 3
    }
  }
  while (r > 100) {               // +1
    r /= 2;
  }
  return r;                       // 预期合计 31
}
