param(
    [string]$RepoRoot
)

$ErrorActionPreference = 'Stop'

if (-not $RepoRoot) {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}

. (Join-Path $PSScriptRoot '..\lib\Setup.Common.ps1')
. (Join-Path $PSScriptRoot '..\lib\Setup.Discovery.ps1')

function Assert-Throws {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,

        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    $threw = $false
    try {
        & $ScriptBlock
    }
    catch {
        $threw = $true
    }

    if (-not $threw) {
        throw ("期望抛出异常但没有发生：{0}" -f $Label)
    }
}

$tempRoot = Join-Path $env:TEMP ("setup-check-{0}" -f [guid]::NewGuid().ToString('N'))
Ensure-Directory -Path $tempRoot

$originalAppData = $env:APPDATA
$originalLocalAppData = $env:LOCALAPPDATA
$originalProgramFiles = $env:ProgramFiles
$originalProgramFilesX86 = ${env:ProgramFiles(x86)}

try {
    Write-Host '开始执行 Setup 自检...'

    $hashSource = Join-Path $tempRoot 'hash-source.txt'
    $hashTarget = Join-Path $tempRoot 'hash-target.txt'
    Set-Content -LiteralPath $hashSource -Value 'same-content' -Encoding UTF8
    Set-Content -LiteralPath $hashTarget -Value 'same-content' -Encoding UTF8
    Assert-FilesMatch -SourcePath $hashSource -DestinationPath $hashTarget -Label 'hash-equality'

    Set-Content -LiteralPath $hashTarget -Value 'different-content' -Encoding UTF8
    Assert-Throws -Label 'hash-difference' -ScriptBlock {
        Assert-FilesMatch -SourcePath $hashSource -DestinationPath $hashTarget -Label 'hash-equality'
    }

    $dirSource = Join-Path $tempRoot 'dir-source'
    $dirTarget = Join-Path $tempRoot 'dir-target'
    Ensure-Directory -Path (Join-Path $dirSource 'nested')
    Set-Content -LiteralPath (Join-Path $dirSource 'file.txt') -Value 'source' -Encoding UTF8
    Sync-DirectorySnapshot -SourcePath $dirSource -DestinationPath $dirTarget
    Assert-DirectoryTopLevelMatch -SourcePath $dirSource -DestinationPath $dirTarget -Label 'dir-sync'

    Set-Content -LiteralPath (Join-Path $dirTarget 'extra.txt') -Value 'extra' -Encoding UTF8
    Assert-Throws -Label 'dir-mismatch' -ScriptBlock {
        Assert-DirectoryTopLevelMatch -SourcePath $dirSource -DestinationPath $dirTarget -Label 'dir-sync'
    }

    $gitRepo = Join-Path $tempRoot 'git-repo'
    Ensure-Directory -Path $gitRepo
    $gitCmd = Get-GitCommand
    if (-not $gitCmd) {
        throw '自检失败：未检测到 Git。'
    }

    & $gitCmd @('-C', $gitRepo, 'init') | Out-Null
    & $gitCmd @('-C', $gitRepo, 'config', 'user.email', 'setup-check@example.com') | Out-Null
    & $gitCmd @('-C', $gitRepo, 'config', 'user.name', 'Setup Check') | Out-Null
    Ensure-Directory -Path (Join-Path $gitRepo 'codex-profile')
    Set-Content -LiteralPath (Join-Path $gitRepo 'codex-profile\config.toml') -Value 'value = 1' -Encoding UTF8
    & $gitCmd @('-C', $gitRepo, 'add', '.') | Out-Null
    & $gitCmd @('-C', $gitRepo, 'commit', '-m', 'init') | Out-Null
    Set-Content -LiteralPath (Join-Path $gitRepo 'codex-profile\config.toml') -Value 'value = 2' -Encoding UTF8
    Assert-Throws -Label 'git-dirty-check' -ScriptBlock {
        Assert-GitPathsClean -RepoRoot $gitRepo -RelativePaths @('codex-profile\config.toml') -Label 'Git clean check'
    }

    $fakeAppData = Join-Path $tempRoot 'AppData\Roaming'
    $fakeLocalAppData = Join-Path $tempRoot 'AppData\Local'
    Ensure-Directory -Path $fakeAppData
    Ensure-Directory -Path $fakeLocalAppData
    $env:APPDATA = $fakeAppData
    $env:LOCALAPPDATA = $fakeLocalAppData
    $env:ProgramFiles = Join-Path $tempRoot 'Program Files'
    ${env:ProgramFiles(x86)} = Join-Path $tempRoot 'Program Files (x86)'

    Ensure-Directory -Path (Join-Path $env:APPDATA 'Claude')
    Ensure-Directory -Path (Join-Path $env:LOCALAPPDATA 'Packages\Claude.Test\LocalCache\Roaming\Claude')
    $canonicalDesktopRoot = Get-CanonicalClaudeDesktopRoot
    $expectedDesktopRoot = Join-Path $env:APPDATA 'Claude'
    if ($canonicalDesktopRoot -ne $expectedDesktopRoot) {
        throw 'Claude Desktop 根目录优先级校验失败。'
    }

    Remove-Item -LiteralPath $expectedDesktopRoot -Recurse -Force
    $fallbackDesktopRoot = Get-CanonicalClaudeDesktopRoot
    if ($fallbackDesktopRoot -notlike '*Packages\Claude.Test\LocalCache\Roaming\Claude') {
        throw 'Claude Desktop packaged root 回退校验失败。'
    }

    Write-Host 'Setup 自检通过。'
}
finally {
    $env:APPDATA = $originalAppData
    $env:LOCALAPPDATA = $originalLocalAppData
    $env:ProgramFiles = $originalProgramFiles
    ${env:ProgramFiles(x86)} = $originalProgramFilesX86

    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
