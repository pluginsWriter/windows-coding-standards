# rebuild-compile-db.ps1 —— 一键重建编译数据库（MSBuild tlog → compile_commands.json）
#
# 解决的问题：MSBuild（.vcxproj）工程没有原生的 compile_commands.json（CMake 才有），
# 而 clang-tidy / DEC 工具链都需要它。本脚本把最近一次构建生成的 CL.command.1.tlog
# 转换成编译数据库，并可选做一次 clang-tidy 冒烟（验证头文件能否真正解析）。
#
# 用法（任意终端均可——脚本自动找 VS 并导入编译环境，无需 x64 Native Tools 窗口）：
#   cpp\scripts\rebuild-compile-db.cmd -Src D:\path\to\被测工程
#   （PowerShell 里也可直接: .\rebuild-compile-db.ps1 -Src D:\path\to\被测工程）
#   可选参数: -Tlog <指定tlog路径>（多工程解决方案时选具体工程）
#             -Out <输出路径>（默认 <工程>\compile_commands.json）
#             -NoSmoke（跳过 clang-tidy 冒烟）
#
# 何时重跑：在 VS / MSBuild 里重新 Build 之后重跑同一条命令即可 —— tlog 会随构建
#           自动更新，本脚本取最新的那份，输出直接覆盖旧数据库，无需手动删除。
#
# 产出（发回给维护者的东西）：
#   <工程>\compile_commands.json   编译数据库
#   <工程>\clang-tidy-smoke.log    冒烟输出（装了 LLVM 才生成；报「找不到头文件」也算有效结果）
#   <工程>\rebuild-db.log          本脚本全程输出（排障用）
#
# 退出码：0 成功 / 2 找不到工程或 tlog / 3 找不到 Python / 4 转换失败

param(
    [Parameter(Mandatory = $true)][string]$Src,
    [string]$Out = "",
    [string]$Tlog = "",
    [switch]$NoSmoke
)

$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }
$Base = $PSScriptRoot
$Utf8Nb = New-Object System.Text.UTF8Encoding($false)
$LogLines = New-Object System.Collections.Generic.List[string]

function Say([string]$m) {
    Write-Output $m
    $LogLines.Add($m)
}
function Fail([string]$m, [int]$code) {
    Say ""
    Say ("!! " + $m)
    Say ("!! 失败退出码: $code。排障请把 rebuild-db.log（若已生成）与 tlog 文件发回。")
    exit $code
}

# ---------- 0. 校验工程目录 ----------
if (-not (Test-Path -LiteralPath $Src)) {
    Fail "工程目录不存在: $Src（用法: rebuild-compile-db.cmd -Src D:\path\to\工程）" 2
}
$Src = (Resolve-Path -LiteralPath $Src).Path
if (-not $Out) { $Out = Join-Path $Src 'compile_commands.json' }
$OutDir = Split-Path -Parent $Out

Say ("== 重建编译数据库: $Src")
Say ("== 时间: " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))

# ---------- 1. 找 tlog（默认取最新构建的那份） ----------
$tlogFile = $null
if ($Tlog) {
    if (-not (Test-Path -LiteralPath $Tlog)) { Fail "指定的 tlog 不存在: $Tlog" 2 }
    $tlogFile = Get-Item -LiteralPath $Tlog
    Say ("== 使用指定 tlog: " + $tlogFile.FullName)
} else {
    $all = Get-ChildItem -LiteralPath $Src -Recurse -File -Filter 'CL.command.1.tlog' -ErrorAction SilentlyContinue
    if (-not $all -or @($all).Count -eq 0) {
        Fail "在 $Src 下没有找到 CL.command.1.tlog —— 请先在 Visual Studio / MSBuild 里对该工程执行一次生成（Build），tlog 会在中间目录产生，然后重跑本命令。" 2
    }
    $tlogFile = @($all) | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    Say ("== 找到 " + @($all).Count + " 份 tlog，取最新一份（多工程解决方案要指定别的工程时，用 -Tlog 参数）:")
    Say ("   " + $tlogFile.FullName + "  （构建时间 " + $tlogFile.LastWriteTime + "）")
}

# ---------- 2. VS 定位 + 编译环境导入（同 audit/run-audit.ps1 §1b，真机已验证：94 个变量） ----------
$vsPath = $null
try {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path -LiteralPath $vswhere) {
        $vsPath = (& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>&1 | Out-String).Trim()
    }
} catch { }

if (-not $env:INCLUDE) {
    if ($vsPath -and (Test-Path -LiteralPath $vsPath)) {
        $vcvars = Join-Path $vsPath 'VC\Auxiliary\Build\vcvars64.bat'
        if (Test-Path -LiteralPath $vcvars) {
            $envOut = & cmd.exe /c ('call "' + $vcvars + '" >nul 2>&1 && set') 2>&1 | Out-String
            $imported = 0
            foreach ($line in ($envOut -split "`r?`n")) {
                if ($line -match '^([A-Za-z0-9_()]+)=(.*)$') {
                    Set-Item -Path ('Env:' + $Matches[1]) -Value $Matches[2]
                    $imported++
                }
            }
            Say ("== MSVC 环境: 已从 vcvars64.bat 导入 $imported 个变量到本进程（INCLUDE 将烘焙进数据库）")
        } else {
            Say "!! 找到 VS 但没有 vcvars64.bat —— 数据库将不含系统头文件 /I，冒烟报找不到头文件仍属有效结果。"
        }
    } else {
        Say "!! 未探测到 VS 安装（vswhere 无结果）——数据库将不含系统头文件 /I，冒烟报找不到头文件仍属有效结果。"
    }
} else {
    Say "== INCLUDE 已在当前环境中（看起来你已在编译环境里），跳过 vcvars 导入"
}

# ---------- 3. 找 Python（py -3 / python / python3，用 --version 输出甄别商店占位假 python） ----------
$pyExe = $null
$pyPre = @()
foreach ($cand in @(@('py', '-3'), @('python'), @('python3'))) {
    $name = $cand[0]
    $pre = @()
    if ($cand.Count -gt 1) { $pre = @($cand[1]) }
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) { continue }
    $verOut = ''
    try { $verOut = (& $name @pre '--version' 2>&1 | Out-String) } catch { }
    if (($LASTEXITCODE -eq 0) -and ($verOut -match 'Python\s+\d')) {
        $pyExe = $name
        $pyPre = $pre
        Say ("== Python: " + $name + " " + ($verOut.Trim() -replace '^Python\s+', ''))
        break
    }
}
if (-not $pyExe) {
    Say "!! 没有可用的 Python（py / python / python3 均不可用或为商店占位）。"
    Fail ("两个办法任选：① 装 Python（python.org 或 Microsoft Store 均可）后重跑本命令；② 直接把 tlog 文件发回: " + $tlogFile.FullName) 3
}

# ---------- 4. 转换 ----------
$conv = Join-Path $Base 'tlog_to_compile_commands.py'
if (-not (Test-Path -LiteralPath $conv)) { Fail "转换器不存在: $conv（本脚本须与 tlog_to_compile_commands.py 同目录）" 5 }
Say ""
Say ("$ " + $pyExe + " " + ($pyPre -join ' ') + " tlog_to_compile_commands.py " + $tlogFile.FullName + " -o " + $Out)
$convOut = & $pyExe @pyPre $conv $tlogFile.FullName -o $Out 2>&1 | Out-String
Say $convOut
if (($LASTEXITCODE -ne 0) -or -not (Test-Path -LiteralPath $Out)) {
    Fail ("转换失败（exit=$LASTEXITCODE）。请把 tlog 文件本身发回: " + $tlogFile.FullName) 4
}

# ---------- 5. clang-tidy 冒烟（装了 LLVM 才做；报「找不到头文件」也是有效结果） ----------
$smokeLog = ""
if (-not $NoSmoke) {
    Say ""
    Say "===== clang-tidy 冒烟（单 TU，验证头文件可解析性） ====="
    $tidy = Get-Command clang-tidy -ErrorAction SilentlyContinue
    if (-not $tidy -and $vsPath -and (Test-Path -LiteralPath $vsPath)) {
        foreach ($sub in @('Common7\IDE\CommonExtensions\Microsoft\LLVM\bin',
                           'Common7\IDE\CommonExtensions\Microsoft\LLVM\x64\bin')) {
            $dir = Join-Path $vsPath $sub
            if (Test-Path -LiteralPath $dir) { $env:PATH = $dir + ';' + $env:PATH }
        }
        $tidy = Get-Command clang-tidy -ErrorAction SilentlyContinue
    }
    if ($tidy) {
        $db = $null
        try { $db = Get-Content -LiteralPath $Out -Raw | ConvertFrom-Json } catch { }
        $entry = $null
        if ($db) { foreach ($e in @($db)) { if ($e.file -match '\.cpp$') { $entry = $e; break } } }
        if ($entry) {
            $smokeLog = Join-Path $OutDir 'clang-tidy-smoke.log'
            $checks = '-*,clang-analyzer-core*,cppcoreguidelines-init-variables'
            Say ("$ clang-tidy -p <数据库目录> --checks=" + $checks + " " + $entry.file)
            $smoke = & $tidy.Source '-p' $OutDir ('--checks=' + $checks) $entry.file 2>&1 | Out-String
            Say $smoke
            Say ("== 冒烟退出码: $LASTEXITCODE（非 0 也常见——报「找不到头文件」同样是有效结果）；输出已存: $smokeLog")
            [System.IO.File]::WriteAllText($smokeLog, $smoke, $Utf8Nb)
        } else {
            Say "!! 数据库里读不出 .cpp 条目，跳过冒烟（数据库本身不受影响）。"
        }
    } else {
        Say "== 未找到 clang-tidy（独立 LLVM 与 VS 内置均无）——跳过冒烟，不影响数据库；发回数据库即可。"
    }
}

# ---------- 6. 落盘全程日志 + 汇总 ----------
$dbLog = Join-Path $OutDir 'rebuild-db.log'
[System.IO.File]::WriteAllText($dbLog, ($LogLines -join "`r`n"), $Utf8Nb)

Say ""
Say "===== 完成。请把以下文件发回 ====="
Say ("  1. " + $Out + "   （编译数据库）")
if ($smokeLog) { Say ("  2. " + $smokeLog + "   （冒烟输出；报找不到头文件也算有效）") }
Say ("  3. " + $dbLog + "   （本命令全程输出）")
Say ("  备用：以上任一步失败时，直接发回 tlog 文件 " + $tlogFile.FullName)
exit 0
