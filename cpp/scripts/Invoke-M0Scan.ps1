<#
.SYNOPSIS
Run a read-only advisory scan using an actual Windows compilation database.
.DESCRIPTION
Does not build pilot-cpp or synthesize SDK flags. Use a database captured from
the selected real build configuration and run inside its developer environment.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [Parameter(Mandatory = $true)][string]$CompilationDatabase,
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [string]$Manifest = (Join-Path $PSScriptRoot '..\config\pilot-cpp-manifest.json'),
    [string]$Policy = (Join-Path $PSScriptRoot '..\config\m0-policy.yaml'),
    [string]$Python = 'python',
    [string]$ClangTidy = 'clang-tidy',
    [double]$TimeoutSeconds = 120
)

$ErrorActionPreference = 'Stop'
$exitCode = 2
$originalLocation = Get-Location
try {
    # Resolve relative paths before changing to the package directory.
    $SourceRoot = (Resolve-Path -LiteralPath $SourceRoot).Path
    $CompilationDatabase = (Resolve-Path -LiteralPath $CompilationDatabase).Path
    $Manifest = (Resolve-Path -LiteralPath $Manifest).Path
    $Policy = (Resolve-Path -LiteralPath $Policy).Path
    $OutputDirectory = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)
    $Python = (Get-Command $Python -CommandType Application -ErrorAction Stop).Source
    $ClangTidy = (Get-Command $ClangTidy -CommandType Application -ErrorAction Stop).Source
    Set-Location (Join-Path $PSScriptRoot '..')
    & $Python -m dec scan --source-root $SourceRoot --database $CompilationDatabase `
        --manifest $Manifest --policy $Policy --output $OutputDirectory `
        --tool $ClangTidy --timeout $TimeoutSeconds
    $exitCode = $LASTEXITCODE
}
catch {
    [Console]::Error.WriteLine("incomplete: " + $_.Exception.Message)
}
finally {
    Set-Location $originalLocation
}
exit $exitCode
