# DEC C++ 工具首版

本目录实现执行计划的 **M0 提示扫描工具**和只读诊断对比。Python 3.10+，依赖 PyYAML；扫描使用固定版本的 clang-tidy。源码不会自动格式化、修复或重命名。现有根目录 C# 规范入口不变。

## 已实现的能力

1. 严格验证配置、重复键、未知参数和工具版本；从唯一试点配置生成 clang-tidy 配置，并回读实际生效项。
2. 对照显式文件清单验证编译数据库，拒绝漏项和同文件多配置混用；每个翻译单元独立记录成功、错误与超时。
3. 保存原始命令、stdout/stderr、结构化诊断、参数与输入指纹；扫描前后检查已声明源码和输入文件未变。
4. `compare` 按诊断指纹报告新增、消失、未变、认知复杂度恶化/改善与歧义；不自动更新基线，不因总数不变吞掉新增。
5. `.vcxproj` 只读清点、Windows 调用脚本和三平台契约 CI 文件。

这不是完整 DEC 规范实现。上游 19+4 条尚未核验，因此配置只使用工具原生 ID，尚未实现正式规则账本、来源鉴别、生产阻断、SLA 驱动或 AI 授权。`mode` 只接受 `advisory`，不能通过把配置改成 blocking 获得未经验证的阻断能力。

## 安装与本机运行

在本目录执行：

```sh
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements-tools.txt
.venv/bin/python -m dec doctor --tool .venv/bin/clang-tidy
DEC_CLANG_TIDY="$PWD/.venv/bin/clang-tidy" .venv/bin/python -m unittest discover -s tests -v
.venv/bin/python scripts/run_contract_scan.py --output reports/my-contract-run --tool .venv/bin/clang-tidy
```

输出目录必须不存在，避免覆盖旧证据。以上 C++ 文件是契约样本，**不是工程校准数据**。缺 clang-tidy 时真实工具测试会明确 skip；只有 `doctor` 成功且测试无 skip，才能声称完成工具集成测试。

Windows 对应安装与验证：

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements-tools.txt
$env:DEC_CLANG_TIDY = (Resolve-Path .\.venv\Scripts\clang-tidy.exe).Path
.\.venv\Scripts\python.exe -m dec doctor --tool $env:DEC_CLANG_TIDY
.\.venv\Scripts\python.exe -m unittest discover -s tests -v
```

## pilot-cpp 接入

用户指认的源码目录为 `~/src/pilot-cpp`。只读清点结果位于 `execution/pilot-cpp-inventory.json`，草拟扫描清单位于 `config/pilot-cpp-manifest.json`。

工程声明 MSVC v143、Windows SDK 10.0；4 个 ClCompile 项及 Win32/x64/ARM64 的 Debug/Release 配置，部分配置明确 C++17。存在 Windows SDK、WMI、SetupAPI、WinRT 等依赖。**没有从 vcxproj 猜测编译数据库**：项目 imports、条件和继承属性必须以实际 Windows 构建为准，manifest 需和选定配置的实际编译项核对。

在该 Windows 工程的开发者环境内，提供同配置下的真实 `compile_commands.json`。本首版消费已有数据库，尚不实现 MSBuild 数据库捕获；VS 工程文件本身不是编译数据库。不要为让扫描通过而去掉 Windows 依赖或编造 include/define。

```powershell
# 在 cpp 目录执行；三个路径变量替换为 Windows 上的实际位置。
$SourceRoot = 'D:\src\pilot-cpp'
$Database = 'D:\analysis\pilot-cpp-x64-debug\compile_commands.json'
$Report = 'D:\analysis\pilot-cpp-m0-run-001'
.\scripts\Invoke-M0Scan.ps1 -SourceRoot $SourceRoot -CompilationDatabase $Database `
  -OutputDirectory $Report -Python .\.venv\Scripts\python.exe `
  -ClangTidy .\.venv\Scripts\clang-tidy.exe
```

路径仅是调用格式示例，不代表这些 Windows 路径已经存在。每个配置独立提供数据库和报告，不把六个配置混进一次扫描。PowerShell 脚本已编写，Windows 实际执行仍待验证。

macOS/Linux 的相同入口：

```sh
.venv/bin/python -m dec scan --source-root /actual/source/root \
  --database /actual/build/compile_commands.json \
  --manifest config/pilot-cpp-manifest.json --policy config/m0-policy.yaml \
  --tool .venv/bin/clang-tidy --output reports/actual-run-001
```

manifest 的 `translation_units` 定义本次“应查”范围；`inputs` 列入头文件、项目文件及其他需要防漂移的本地输入。清单中的路径相对于源码根目录；不存在或越界的路径报错。系统头文件不作为诊断报告范围。**清单不是自动发现的依赖闭包**：未声明的外部 SDK/头文件、环境变量和编译响应文件变化没有完整哈希保护，首版不应作为生产合并门禁。

## 输出与退出码

每次生成 `report.json`、`summary.md`、生成配置、数据库副本、逐 TU 有效配置回读和原始分析输出。`revision` 当前是已声明输入的内容快照，不冒充 Git 提交；实际工程提交另见接入记录。

| 状态 | 含义 | 退出码 |
| --- | --- | --- |
| `checked` + `advisory` | 清单范围已扫描；普通诊断只提示 | 0 |
| `partial` / `not-checked` + `incomplete` | 工具、配置、解析、超时或输入完整性失败 | 2 |

本地扫描器不会上传报告：`upload_status` 始终诚实记录为 `not-attempted`。`.github/workflows/dec-contracts.yml` 是**工具契约测试**的 CI，上传步骤失败会使 job 失败；当前仓库尚未在远程运行该工作流。实际 pilot-cpp 的报告上传、CI check 和 M0 端到端验收仍须接入其平台，不得因本地返回 0 宣称生产 M0 已达成。

## 诊断对比

```sh
.venv/bin/python -m dec compare --baseline reports/run-001/report.json \
  --current reports/run-002/report.json --output reports/comparison-001.json
```

比较要求同一源码根目录、检测指纹和完整扫描结果；配置变化拒绝比较并提示需要迁移。路径/上下文指纹属于保守匹配：改名或上下文改变可能显示旧项消失、新项出现，不保证任意重构后自动识别身份。重复 TU 观察可聚合，冲突实例保留为 ambiguous。只对识别出的认知复杂度数值比较恶化方向；未实现其他指标的通用恶化算法。

本工具不修改旧报告、不会自动把新问题收为存量，也尚未实现已整改项退出基线、低水位历史管理或基线迁移工作流。因此 `compare` 是只读分析辅助，不等于 T-DEC-44 全部验收，更不能直接作为生产阻断依据。

## 任务与验证边界

见 `execution/implementation-status.md`。原执行计划的上游核验、校准、晋升、来源判定与授权任务保持未完成；不使用合成样本填补真实工程实验。
