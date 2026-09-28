# verify-toolchain-claims.ps1 —— 用最小夹具核验声明清单里可自动化的条目
# 与 verify-toolchain-claims.sh 等价的 Windows 原生 PowerShell 版。
#
# 用法:   .\verify-toolchain-claims.ps1 -LogDir <日志目录>
# 产出:   <日志目录>\claims-results.tsv   每行: id / 结果(PASS|FAIL|UNTESTED) / 证据 / 说明
#         <日志目录>\clm*.log             各条目的原始工具输出（证据）
# 原则:   PASS/FAIL 是机械判定（夹具行为与声明一致/不一致）；UNTESTED 是工具缺失，
#         绝不允许把 UNTESTED 当 PASS。agent 复核证据后回填 claims-checklist.tsv。
# 提示:   CLM-005/006 需要 cl.exe 在 PATH —— 在「x64 Native Tools Command Prompt」里执行。

param(
    [Parameter(Mandatory = $true)][string]$LogDir
)

$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }

$Base = Split-Path $PSScriptRoot -Parent
$Fix = Join-Path $Base 'fixtures'
$FixMini = Join-Path $Fix 'mini-cmakelists'
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
$Out = Join-Path $LogDir 'claims-results.tsv'
$Utf8Nb = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($Out, "", $Utf8Nb)

function Rec([string]$Id, [string]$Res, [string]$Ev, [string]$Note) {
    [System.IO.File]::AppendAllText($Out, "$Id`t$Res`t$Ev`t$Note`n", $Utf8Nb)
}
function Have([string]$T) { [bool](Get-Command $T -ErrorAction SilentlyContinue) }
function LogOf([string]$Tool, [string[]]$ArgList, [string]$LogFile, [string]$WorkDir) {
    # 运行外部工具并把全部输出写入日志文件
    if ($WorkDir) { Push-Location $WorkDir }
    try {
        $out = & $Tool @ArgList 2>&1 | Out-String
        [System.IO.File]::WriteAllText($LogFile, $out, $Utf8Nb)
    } finally {
        if ($WorkDir) { Pop-Location }
    }
}

# ---------- CLM-001 / CLM-002: 编译数据库 ----------
if (Have 'cmake') {
    $vsDone = $false
    foreach ($gen in @('Visual Studio 17 2022', 'Visual Studio 16 2019')) {
        $b = Join-Path $LogDir 'probe-vs'
        if (Test-Path -LiteralPath $b) { Remove-Item -Recurse -Force $b -ErrorAction SilentlyContinue }
        $log = Join-Path $LogDir 'clm001.log'
        & cmake -S $FixMini -B $b -G $gen -DCMAKE_EXPORT_COMPILE_COMMANDS=ON *> $log
        if ($LASTEXITCODE -eq 0) {
            if (Test-Path -LiteralPath (Join-Path $b 'compile_commands.json')) {
                Rec 'CLM-001' 'FAIL' $log "VS 生成器[$gen]产出了 compile_commands.json —— 与声明不符"
            } else {
                Rec 'CLM-001' 'PASS' $log "VS 生成器[$gen]未产出 compile_commands.json（与声明一致）"
            }
            $vsDone = $true
            break
        }
    }
    if (-not $vsDone) {
        Rec 'CLM-001' 'UNTESTED' (Join-Path $LogDir 'clm001.log') "无可用 VS 生成器（本机未装对应 VS 或 cmake 配置失败，看日志）"
    }

    $b = Join-Path $LogDir 'probe-ninja'
    if (Test-Path -LiteralPath $b) { Remove-Item -Recurse -Force $b -ErrorAction SilentlyContinue }
    $log = Join-Path $LogDir 'clm002.log'
    & cmake -S $FixMini -B $b -G Ninja -DCMAKE_EXPORT_COMPILE_COMMANDS=ON *> $log
    if ($LASTEXITCODE -eq 0) {
        if (Test-Path -LiteralPath (Join-Path $b 'compile_commands.json')) {
            Rec 'CLM-002' 'PASS' $log "Ninja 生成器产出 compile_commands.json（与声明一致）"
        } else {
            Rec 'CLM-002' 'FAIL' $log "Ninja 配置成功却未产出 —— 与声明不符"
        }
    } else {
        Rec 'CLM-002' 'UNTESTED' $log "Ninja 生成器不可用（未装 ninja 或无编译器，看日志）"
    }
} else {
    Rec 'CLM-001' 'UNTESTED' '-' 'cmake 不可用'
    Rec 'CLM-002' 'UNTESTED' '-' 'cmake 不可用'
}

# ---------- CLM-003: 认知复杂度检查可触发 ----------
if (Have 'clang-tidy') {
    $log = Join-Path $LogDir 'clm003.log'
    LogOf 'clang-tidy' @('--checks=-*,readability-function-cognitive-complexity',
                         (Join-Path $Fix 'cognitive_complexity.cpp'), '--', '-std=c++17') $log ''
    if (Select-String -Path $log -Pattern 'readability-function-cognitive-complexity' -Quiet) {
        Rec 'CLM-003' 'PASS' $log "样本触发认知复杂度诊断（与声明一致）"
    } else {
        Rec 'CLM-003' 'FAIL' $log "样本未触发 —— 检查名不可用或样本未过阈值，人工复核日志"
    }
} else {
    Rec 'CLM-003' 'UNTESTED' '-' 'clang-tidy 不可用'
}

# ---------- CLM-004: NOLINT 落行语义（两个夹具） ----------
if (Have 'clang-tidy') {
    $logA = Join-Path $LogDir 'clm004a.log'
    LogOf 'clang-tidy' @('--checks=-*,readability-named-parameter',
                         (Join-Path $Fix 'nolint_own_line.cpp'), '--', '-std=c++17') $logA ''
    if (Select-String -Path $logA -Pattern 'readability-named-parameter' -Quiet) {
        Rec 'CLM-004' 'PASS' $logA "a) 单独一行 NOLINT 未抑制下一行（与声明一致）"
    } else {
        Rec 'CLM-004' 'FAIL' $logA "a) 单独一行 NOLINT 抑制了下一行 —— 与声明不符"
    }
    $logB = Join-Path $LogDir 'clm004b.log'
    LogOf 'clang-tidy' @('--checks=-*,readability-named-parameter',
                         (Join-Path $Fix 'nolint_next_line.cpp'), '--', '-std=c++17') $logB ''
    if (Select-String -Path $logB -Pattern 'readability-named-parameter' -Quiet) {
        Rec 'CLM-004' 'FAIL' $logB "b) NOLINTNEXTLINE 未生效 —— 与声明不符"
    } else {
        Rec 'CLM-004' 'PASS' $logB "b) NOLINTNEXTLINE 正常抑制（与声明一致）"
    }
} else {
    Rec 'CLM-004' 'UNTESTED' '-' 'clang-tidy 不可用'
}

# ---------- CLM-005: MSVC warning(push) 缺 pop 的范围泄漏（对照组+实验组） ----------
if (Have 'cl') {
    $ctlLog = Join-Path $LogDir 'clm005_control.log'
    $pshLog = Join-Path $LogDir 'clm005_push.log'
    LogOf 'cl' @('/nologo', '/c', '/W4', (Join-Path $Fix 'warning_control.cpp'))   $ctlLog $LogDir
    LogOf 'cl' @('/nologo', '/c', '/W4', (Join-Path $Fix 'warning_push_nopop.cpp')) $pshLog $LogDir
    $ctl = [bool](Select-String -Path $ctlLog -Pattern 'C4100' -Quiet)
    $psh = [bool](Select-String -Path $pshLog -Pattern 'C4100' -Quiet)
    if ($ctl -and (-not $psh)) {
        Rec 'CLM-005' 'PASS' $pshLog "对照组报 C4100、push无pop 组未报 —— 泄漏成立（与声明一致）"
    } elseif (-not $ctl) {
        Rec 'CLM-005' 'FAIL' $ctlLog "对照组也未报 C4100，夹具无效（/W4 未生效？），人工复核"
    } else {
        Rec 'CLM-005' 'FAIL' $pshLog "push无pop 组仍报 C4100 —— 与声明不符"
    }
} else {
    Rec 'CLM-005' 'UNTESTED' '-' 'cl 不在 PATH：请在 VS Native Tools 命令行里重跑（见文件头提示）'
}

# ---------- CLM-006: MSVC /analyze 无复杂度/嵌套对等诊断 ----------
if (Have 'cl') {
    $log = Join-Path $LogDir 'clm006.log'
    LogOf 'cl' @('/nologo', '/c', '/analyze', '/W4', (Join-Path $Fix 'cognitive_complexity.cpp')) $log $LogDir
    if (Select-String -Path $log -Pattern 'complexit|nesting' -Quiet) {
        Rec 'CLM-006' 'FAIL' $log "/analyze 报出了复杂度/嵌套类诊断 —— 与声明不符"
    } else {
        Rec 'CLM-006' 'PASS' $log "/analyze 无复杂度/嵌套对等诊断（与声明一致；证据为无匹配，属排除性证据）"
    }
} else {
    Rec 'CLM-006' 'UNTESTED' '-' 'cl 不可用'
}

# ---------- CLM-008: Cppcheck 可运行（抑制语义仍需人工按官方文档核） ----------
if (Have 'cppcheck') {
    $log = Join-Path $LogDir 'clm008.log'
    LogOf 'cppcheck' @('--enable=warning', (Join-Path $Fix 'cognitive_complexity.cpp')) $log ''
    Rec 'CLM-008' 'PASS' $log "cppcheck 可运行；--suppressions-list 语义仍需人工最小验证后回填"
} else {
    Rec 'CLM-008' 'UNTESTED' '-' 'cppcheck 不可用'
}

# ---------- 其余条目：本脚本不自动判定，留人工 ----------
Rec 'CLM-007' 'UNTESTED' '-' '人工：装 clang-cl 后对夹具跑 clang-tidy -- -x c++ --target=x86_64-pc-windows-msvc（参数以本机为准）验证双工具链共存'
Rec 'CLM-009' 'UNTESTED' '-' '人工：嵌套深度检查的可用实现待确认（试 lizard / cppcheck / clang-tidy 各选项）；确认无实现则记 C 类缺口'
Rec 'CLM-010' 'UNTESTED' '-' '人工：clang-tidy → SARIF 最小转换验证（clang-tidy-sarif 或 IDE 输出通道）'
Rec 'CLM-011' 'UNTESTED' '-' '人工：PVS-Studio 基线抑制语义需许可产品；无产品保持 untested，不得引用为已验证'
Rec 'CLM-012' 'UNTESTED' '-' '由扫描脚本的 include_case_mismatch 候选覆盖；agent 分诊后回填'

Write-Output "== 声明核验完成: $Out"
[System.IO.File]::ReadAllLines($Out) | ForEach-Object { ($_ -split "`t")[1] } | Group-Object |
    ForEach-Object { Write-Output ("   {0,-8} {1}" -f $_.Name, $_.Count) }
exit 0
