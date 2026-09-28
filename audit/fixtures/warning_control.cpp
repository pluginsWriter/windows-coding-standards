// CLM-005 对照组：无任何 pragma。/W4 下未使用参数都应报 C4100。
// 作用：证明实验组的"未报"确实是 pragma 泄漏所致，而非 /W4 没开或参数写法不触发。
int a(int unused) { return 1; }
int b(int unused_too) { return 2; }
