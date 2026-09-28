# scan-macos-traces.ps1 —— macOS 遗留痕迹机械扫描（候选生成器，不是结论生成器）
# 与 scan-macos-traces.sh 等价的 Windows 原生 PowerShell 版。
#
# 用法:   .\scan-macos-traces.ps1 -Src <源码目录> -OutPath <输出.tsv>
# 输出:   TSV 四列：类别 / 文件 / 行号 / 匹配内容；每一行都是"候选"，
#         必须经 agent 分诊（五道门）后才能进 findings.tsv。
# 原则:   只读不改任何源码；CRLF 仅计数（Windows 上 CRLF 是常态，不算发现）。

param(
    [Parameter(Mandatory = $true)][string]$Src,
    [Parameter(Mandatory = $true)][string]$OutPath
)

$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }

if (-not (Test-Path -LiteralPath $Src)) {
    Write-Error "错误: 源码目录不存在: $Src"
    exit 2
}
$Src = (Resolve-Path -LiteralPath $Src).Path
$Utf8Nb = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($OutPath, "", $Utf8Nb)

$CodeExts = @('.h', '.hpp', '.cc', '.cpp', '.cxx', '.c', '.inl', '.m', '.mm', '.inc', '.cmake')
# 默认排除目录：第三方库/构建产物/IDE 元数据（真机实测 third_party 占候选 27%，纯噪声）。
# 目录名大小写不敏感匹配路径中的独立段。
$ExcludeRe = '[\\/](third_party|3rdparty|thirdparty|external|vendor|deps|build|_build|out|bin|obj|\.git|\.vs|x64|Debug|Release|node_modules)[\\/]'
$files = Get-ChildItem -LiteralPath $Src -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object {
        ($CodeExts -contains $_.Extension.ToLower() -or $_.Name -ieq 'CMakeLists.txt') -and
        ($_.FullName -notmatch $ExcludeRe)
    }

function Add-Row([string]$Cat, [string]$File, [string]$Line, [string]$Text) {
    $t = ($Text -replace "`t", " ").TrimEnd()
    [System.IO.File]::AppendAllText($OutPath, "$Cat`t$File`t$Line`t$t`n", $Utf8Nb)
}

# 类别 → 正则（.NET 语法；\s 替代 [[:space:]]）
# 注意：Select-String 必须显式 -CaseSensitive——PS 默认大小写不敏感，真机上曾把
#       uint8_t/uint16_t 全部误判为 UI 前缀符号（1138 条误报，见 findings-master F-001）。
# apple_symbols 要求前缀后紧跟「大写+小写」（CamelCase 第二字母小写），
# 借此排除 UINT/UINT_MAX/UINT32 等 Windows/C 全大写类型（见 F-003）。
$Categories = [ordered]@{
    objc_syntax    = '@(implementation|interface|end|selector|property|synchronized)[^A-Za-z]|objc_msgSend|#import\s*[<"]'
    apple_symbols  = '\b(NS|CF|CG|UI)[A-Z][a-z][A-Za-z0-9_]*|dispatch_(async|sync|after|once|get_main|main_queue)|\bCF(Release|Retain|StringCreate)\b|\bNSBundle\b'
    apple_headers  = '<(Foundation|AppKit|UIKit|Cocoa|IOKit|CoreFoundation|CoreGraphics|CoreData|CoreAnimation|CoreAudio|CoreImage|dispatch)/'
    apple_guards   = '#(el)?if(def|ndef)?.*__APPLE__|#(el)?if.*TARGET_OS_|#(el)?if.*TARGET_CPU_ARM'
    posix_api      = '\bpthread_[a-z_]+|\bsem_(wait|post|trywait|init|destroy)\b|\bclock_gettime\b|\bmach_absolute_time\b|\bkqueue\b|\bfork\s*\('
    posix_paths    = '"/usr/|"/Library/|"/System/|"/var/|~/Library|/Contents/MacOS|\.framework["/ ]|\.app/|\.plist["/ ]|\.icns["/ ]|\.dylib\b|\.dsym\b'
    build_residue  = 'xcodeproj|xcworkspace|codesign\s|XCTest|\.xib["/ ]|\.storyboard["/ ]|xcode-select'
    comment_traces = '(TODO|FIXME|HACK|XXX)[^"]*([Mm]ac([Oo][Ss])?[ :]|darwin|Darwin|OS[ ]?X)'
}

foreach ($kv in $Categories.GetEnumerator()) {
    $hits = $files | Select-String -Pattern $kv.Value -CaseSensitive -ErrorAction SilentlyContinue
    foreach ($h in $hits) {
        Add-Row $kv.Key $h.Path ([string]$h.LineNumber) $h.Line
    }
}

# ---- include 大小写不匹配 ----
# 原理：以「不区分大小写」方式找到实际文件后，与「区分大小写」的期望名做字符串比对。
# 这样在大小写不敏感文件系统（Windows NTFS / macOS APFS 默认）上也能发现拼写不一致——
# 这类 include 在 Windows 上能编过，到了大小写敏感环境（Linux CI / 他人 clone）直接编译失败。
$incRe = '^\s*#\s*include\s*"([^"]+)"'
foreach ($h in ($files | Select-String -Pattern $incRe -CaseSensitive -ErrorAction SilentlyContinue)) {
    $inc = $h.Matches[0].Groups[1].Value
    if ($inc -match '^(/|[A-Za-z]:[\\/])') { continue }     # 绝对路径 / 带盘符，跳过
    $dirPart  = Split-Path $inc -Parent
    $baseName = Split-Path $inc -Leaf
    $fileDir  = Split-Path $h.Path -Parent
    foreach ($base in @($fileDir, $Src)) {
        if ($dirPart) { $tdir = [System.IO.Path]::GetFullPath((Join-Path $base $dirPart)) }
        else { $tdir = [System.IO.Path]::GetFullPath($base) }
        if (-not (Test-Path -LiteralPath $tdir)) { continue }
        $found = Get-ChildItem -LiteralPath $tdir -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ieq $baseName } | Select-Object -First 1
        if ($found -and ($found.Name -cne $baseName)) {
            Add-Row 'include_case_mismatch' $h.Path ([string]$h.LineNumber) ($inc + "（磁盘实际拼写: " + $found.FullName + "）")
            break
        }
    }
}

# ---- ObjC 源文件本身 ----
foreach ($f in ($files | Where-Object { $_.Extension -ieq '.m' -or $_.Extension -ieq '.mm' })) {
    Add-Row 'objc_file' $f.FullName '0' 'ObjC 源文件残留'
}

# ---- UTF-8 BOM（信息项：MSVC 无 /utf-8 时 BOM 反而保护中文注释；无 BOM+中文才是风险） ----
foreach ($f in ($files | Where-Object { @('.cpp', '.hpp', '.h', '.cc', '.cxx') -contains $_.Extension.ToLower() })) {
    try {
        $fs = [System.IO.File]::OpenRead($f.FullName)
        $b = New-Object byte[] 3
        $n = $fs.Read($b, 0, 3)
        $fs.Close()
        if ($n -eq 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) {
            Add-Row 'utf8_bom' $f.FullName '0' '文件头带 UTF-8 BOM'
        }
    } catch { }
}

# ---- CRLF 计数（信息项） ----
$crlfCount = 0
foreach ($f in ($files | Where-Object { @('.cpp', '.h', '.hpp') -contains $_.Extension.ToLower() })) {
    try {
        $raw = [System.IO.File]::ReadAllText($f.FullName)
        if ($raw -match "`r") { $crlfCount++ }
    } catch { }
}

# ---- 汇总（stdout；agent 直接可读） ----
$rows = @([System.IO.File]::ReadAllLines($OutPath) | Where-Object { $_ -match '\S' })
$total = $rows.Count
Write-Output "== 扫描完成: $Src"
Write-Output "== 已默认排除目录: third_party / build / .git 等第三方与构建目录（清单见脚本头部 ExcludeRe）"
Write-Output "== 候选总数: $total（候选 != 发现，需过五道门分诊）"
Write-Output "== CRLF 文件计数（信息项，Windows 上属常态）: $crlfCount"
if ($total -gt 0) {
    Write-Output "== 分类计数:"
    $rows | ForEach-Object { ($_ -split "`t")[0] } | Group-Object | Sort-Object Count -Descending |
        ForEach-Object { Write-Output ("   {0,-6} {1}" -f $_.Count, $_.Name) }
}
if ($total -gt 3000) {
    Write-Output "!! 候选超过 3000 行，噪声可能偏大：建议收窄源码范围或分目录重扫"
}
exit 0
