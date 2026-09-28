# run-audit.ps1 —— skill 真机审计主入口（Windows 原生 PowerShell 版，与 run-audit.sh 产出一致）
#
# 被测物是 skill 本身（规范文档/脚本/DEC 计划的可执行声明），被测工程只是夹具。
#
# 用法（PowerShell）:
#   .\run-audit.ps1 -Src <被测C++工程目录> [-Logs <日志根目录>]
#   （建议在「x64 Native Tools Command Prompt for VS」里跑，使 cl.exe 可见，CLM-005/006 才能自动跑）
# 若系统提示禁止运行脚本，用 cmd 启动器（已免设置，可在 cmd / 双击调用）:
#   run-audit.cmd -Src D:\path\to\project
#   或: powershell -NoProfile -ExecutionPolicy Bypass -File .\run-audit.ps1 -Src D:\path\to\project
#
# 产出（执行后直接读结果，无需人工翻原始日志）:
#   logs\run-<时间戳>\summary.md  ← 先读这个
#   其余: cmdlog.txt / env.txt / macos-trace-candidates.tsv / scan-summary.txt /
#         claims-results.tsv / claims-checklist.tsv / findings.tsv（同 bash 版）

param(
    [Parameter(Mandatory = $true)][string]$Src,
    [string]$Logs = ""
)

$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }

$Base = $PSScriptRoot
if (-not (Test-Path -LiteralPath $Src)) {
    Write-Error "用法: .\run-audit.ps1 -Src <被测C++工程目录> [-Logs <目录>]  （目录不存在: $Src）"
    exit 2
}
$Src = (Resolve-Path -LiteralPath $Src).Path
if (-not $Logs) { $Logs = Join-Path $Base 'logs' }

$TS  = Get-Date -Format 'yyyyMMdd-HHmmss'
$Run = Join-Path $Logs "run-$TS"
New-Item -ItemType Directory -Path $Run -Force | Out-Null
$CmdLog = Join-Path $Run 'cmdlog.txt'
$Utf8Nb = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($CmdLog, "", $Utf8Nb)

function Append-Log([string]$Text) {
    [System.IO.File]::AppendAllText($CmdLog, $Text + "`r`n", $Utf8Nb)
}
function Run-Tool([string]$Name, [string[]]$ArgList, [string]$ExtraLog) {
    # 运行外部工具：命令与完整输出记入 cmdlog；可选另存到 ExtraLog
    $cmdLine = "$Name " + ($ArgList -join ' ')
    Append-Log ""
    Append-Log ("$ " + $cmdLine)
    $out = & $Name @ArgList 2>&1 | Out-String
    Append-Log $out
    if ($ExtraLog) { [System.IO.File]::WriteAllText($ExtraLog, $out, $Utf8Nb) }
}

# ---------- 1. 环境指纹（阶段0） ----------
$envLines = New-Object System.Collections.Generic.List[string]
$envLines.Add("时间: " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
$envLines.Add("被测源码: $Src")
$envLines.Add("PowerShell: " + $PSVersionTable.PSVersion)
try { $envLines.Add("OS: " + [System.Environment]::OSVersion.VersionString) } catch { }
try {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $envLines.Add("Windows: " + $os.Caption + " " + $os.Version + " (Build " + $os.BuildNumber + ")")
} catch { }

# ---------- 1b. VS 内置工具探测与环境导入（真机常见：装了 VS 但不在 PATH） ----------
# 依据 vswhere 定位 VS 安装，把 VS 自带的 cmake/ninja/clang-tidy/msbuild 前置到本进程 PATH，
# 并用 vcvars64.bat 导入 MSVC 编译环境（cl.exe/INCLUDE/LIB）——使命令核验层能实际跑起来。
$vsPath = $null
try {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path -LiteralPath $vswhere) {
        Append-Log ""
        Append-Log ('$ ' + $vswhere + ' -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath')
        $vsPath = (& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>&1 | Out-String).Trim()
        Append-Log ('installationPath: ' + $vsPath)
        if ($vsPath) { $envLines.Add("VS 安装: $vsPath") }
    }
} catch { }
if ($vsPath -and (Test-Path -LiteralPath $vsPath)) {
    $bundled = @(
        @{ n = 'cmake';      p = 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin' },
        @{ n = 'ninja';      p = 'Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja' },
        @{ n = 'clang-tidy'; p = 'Common7\IDE\CommonExtensions\Microsoft\LLVM\bin' },
        @{ n = 'clang-tidy'; p = 'Common7\IDE\CommonExtensions\Microsoft\LLVM\x64\bin' },
        @{ n = 'msbuild';    p = 'MSBuild\Current\Bin' }
    )
    $env:PATH = $env:PATH
    foreach ($b in $bundled) {
        $dir = Join-Path $vsPath $b.p
        if (Test-Path -LiteralPath $dir) {
            $env:PATH = $dir + ';' + $env:PATH
            $envLines.Add("VS 内置 $($b.n) => $dir（已前置 PATH）")
        }
    }
    $vcvars = Join-Path $vsPath 'VC\Auxiliary\Build\vcvars64.bat'
    if (Test-Path -LiteralPath $vcvars) {
        try {
            Append-Log ""
            Append-Log ('$ cmd /c call "' + $vcvars + '" && set   （导入 MSVC 编译环境）')
            $envOut = & cmd.exe /c ('call "' + $vcvars + '" >nul 2>&1 && set') 2>&1 | Out-String
            $imported = 0
            foreach ($line in ($envOut -split "`r?`n")) {
                if ($line -match '^([A-Za-z0-9_()]+)=(.*)$') {
                    Set-Item -Path ('Env:' + $Matches[1]) -Value $Matches[2]
                    $imported++
                }
            }
            $envLines.Add("MSVC 环境: 已从 vcvars64.bat 导入 $imported 个变量到本进程")
        } catch {
            $envLines.Add("MSVC 环境: vcvars64.bat 导入失败 - " + $_.Exception.Message)
        }
    }
} else {
    $envLines.Add("VS 安装: 未探测到（vswhere 无结果或不可用）——cl/cmake 相关声明将保持 UNTESTED")
}

foreach ($t in @('cmake', 'clang-tidy', 'clang-cl', 'cl', 'ninja', 'msbuild', 'cppcheck', 'git')) {
    $c = Get-Command $t -ErrorAction SilentlyContinue
    if ($c) {
        $envLines.Add("tool $t => " + $c.Source)
        switch ($t) {
            'cmake'      { Run-Tool 'cmake' @('--version') '' }
            'clang-tidy' { Run-Tool 'clang-tidy' @('--version') '' }
            'ninja'      { Run-Tool 'ninja' @('--version') '' }
            'cppcheck'   { Run-Tool 'cppcheck' @('--version') '' }
            'git'        { Run-Tool 'git' @('--version') '' }
            'cl'         { Run-Tool 'cl' @('/nologo') '' }
        }
    } else {
        $envLines.Add("tool $t => 缺失")
    }
}
[System.IO.File]::WriteAllText((Join-Path $Run 'env.txt'), ($envLines -join "`r`n"), $Utf8Nb)

# ---------- 2. 初始化台账 ----------
foreach ($tpl in @('findings.tsv', 'claims-checklist.tsv')) {
    $src2 = Join-Path $Base ("templates/" + $tpl)
    if (Test-Path -LiteralPath $src2) { Copy-Item -LiteralPath $src2 -Destination (Join-Path $Run $tpl) -Force }
}

# ---------- 3. macOS 遗留痕迹扫描（阶段5候选） ----------
$candPath  = Join-Path $Run 'macos-trace-candidates.tsv'
$scanSumF  = Join-Path $Run 'scan-summary.txt'
$scanOut = & (Join-Path $Base 'scripts/scan-macos-traces.ps1') -Src $Src -OutPath $candPath 2>&1 | Out-String
Append-Log ""
Append-Log "===== macOS 遗留痕迹扫描 ====="
Append-Log $scanOut
[System.IO.File]::WriteAllText($scanSumF, $scanOut, $Utf8Nb)
Write-Host $scanOut

# ---------- 4. 工具链声明核验（阶段2自动化部分） ----------
$verifyOut = & (Join-Path $Base 'scripts/verify-toolchain-claims.ps1') -LogDir $Run 2>&1 | Out-String
Append-Log ""
Append-Log "===== 工具链声明核验（夹具） ====="
Append-Log $verifyOut

# ---------- 5. 汇总（直接可读结果） ----------
$Sum = New-Object System.Collections.Generic.List[string]
$Sum.Add("# 审计机械报告 run-$TS")
$Sum.Add("")
$Sum.Add("- 被测源码: ``$Src``")
$Sum.Add("- 生成时间: " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
$Sum.Add("- 环境指纹: 见 env.txt；命令证据链: 见 cmdlog.txt")
$Sum.Add("- 入口: PowerShell 版 run-audit.ps1")
$Sum.Add("")
$Sum.Add("## 1. 声明核验结果（自动化部分，详见 claims-results.tsv）")
$Sum.Add("")
$Sum.Add("| id | 结果 | 证据 | 说明 |")
$Sum.Add("| --- | --- | --- | --- |")
$claimsPath = Join-Path $Run 'claims-results.tsv'
if (Test-Path -LiteralPath $claimsPath) {
    $crows = [System.IO.File]::ReadAllLines($claimsPath) | Where-Object { $_ -match '\S' }
    foreach ($r in $crows) {
        $p = $r -split "`t"
        if ($p[0] -eq 'id') { continue }
        $Sum.Add("| " + $p[0] + " | " + $p[1] + " | " + $p[2] + " | " + $p[3] + " |")
    }
    if (-not $crows -or $crows.Count -eq 0) { $Sum.Add("| （无） | | | |") }
} else {
    $Sum.Add("| （无） | | | |")
}
$Sum.Add("")
$Sum.Add("> PASS/FAIL 也只是机械判定：agent 须复核证据文件后，把结果回填 claims-checklist.tsv。")
$Sum.Add("")
$Sum.Add("## 2. macOS 遗留痕迹候选（分诊前，不是结论）")
$Sum.Add("")
if ((Test-Path -LiteralPath $candPath) -and ([System.IO.File]::ReadAllLines($candPath).Count -gt 0)) {
    $Sum.Add("| 计数 | 类别 |")
    $Sum.Add("| --- | --- |")
    $cand = [System.IO.File]::ReadAllLines($candPath) | Where-Object { $_ -match '\S' }
    $cand | ForEach-Object { ($_ -split "`t")[0] } | Group-Object | Sort-Object Count -Descending |
        ForEach-Object { $Sum.Add("| " + $_.Count + " | " + $_.Name + " |") }
    $Sum.Add("")
    $Sum.Add("共 " + $cand.Count + " 条候选 → 分诊流程见 briefs/agent-brief.md §5；已知误报源见 §6。")
} else {
    $Sum.Add("（无候选。注意：候选为零 ≠ 干净，只等于本次模式集未命中。）")
}
$Sum.Add("")
$Sum.Add("## 3. Agent 待办（按 briefs/agent-brief.md 六阶段执行）")
$Sum.Add("")
$Sum.Add("- [ ] 阶段0 补漏：核对 env.txt，补 MSVC 具体版本 / vcvars 环境 / 缺失工具的处置决定")
$Sum.Add("- [ ] 阶段1 skill 自检：跑 skill 自带 verify 类脚本，结果进 findings.tsv（A 类优先）")
$Sum.Add("- [ ] 阶段2 人工部分：复核 claims-results.tsv 证据，回填 claims-checklist.tsv；UNTESTED 条目逐条验证或明确标注不可测原因")
$Sum.Add("- [ ] 阶段3 工作流实走：按 skill 工作流走一遍被测工程，每步记录 skill预期 vs 实际发生")
$Sum.Add("- [ ] 阶段4 规则触发：对 skill 每条机器规则喂已知违规样本，记录 拦得住/拦不住")
$Sum.Add("- [ ] 阶段5 候选分诊：macos-trace-candidates.tsv → 过五道门 → findings.tsv")
$Sum.Add("- [ ] 收口：检查 findings.tsv 每条 repro_count>=2、归因列指向 skill 具体工件、A-F 分类齐全；补齐未检查清单")
$Sum.Add("")
$Sum.Add("## 4. 证据纪律（对 agent 生效）")
$Sum.Add("")
$Sum.Add('- 每条结论必须引用本目录内日志文件；自己补跑的命令一律追加到 cmdlog.txt（先写「$ 命令原文」再贴完整输出）。')
$Sum.Add('- 确认级结论必须复现两次；只出现一次的标「间歇」。')
$Sum.Add('- 编译期事实 / 运行期事实 / 静态推断 分开标注；没运行过的只能写「未检查」。')
$SumPath = Join-Path $Run 'summary.md'
[System.IO.File]::WriteAllText($SumPath, ($Sum -join "`r`n"), $Utf8Nb)

Write-Host ""
Write-Host "== 完成。结果目录: $Run"
Write-Host "== 先读: $SumPath"
