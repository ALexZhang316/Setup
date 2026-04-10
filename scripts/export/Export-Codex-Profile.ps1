param(
    [string]$RepoRoot,
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

if (-not $RepoRoot) {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}

. (Join-Path $PSScriptRoot '..\lib\Setup.Common.ps1')
. (Join-Path $PSScriptRoot '..\lib\Setup.Discovery.ps1')

try {
    $sourceRoot = Join-Path $env:USERPROFILE '.codex'
    $configSourcePath = Join-Path $sourceRoot 'config.toml'
    $agentsSourcePath = Join-Path $sourceRoot 'AGENTS.md'
    $skillsSourcePath = Join-Path $sourceRoot 'skills'

    $snapshotRoot = Join-Path $RepoRoot 'codex-profile'
    $configSnapshotPath = Join-Path $snapshotRoot 'config.toml'
    $agentsSnapshotPath = Join-Path $snapshotRoot 'AGENTS.md'
    $skillsSnapshotPath = Join-Path $snapshotRoot 'skills'
    $trackedPaths = @(
        'codex-profile\config.toml'
        'codex-profile\AGENTS.md'
        'codex-profile\skills'
    )

    Assert-FileExists -Path $configSourcePath -Label '本机 .codex\config.toml'
    Assert-FileExists -Path $agentsSourcePath -Label '本机 .codex\AGENTS.md'
    if (-not (Test-Path -LiteralPath $skillsSourcePath)) {
        throw "未找到本机 .codex\skills：$skillsSourcePath"
    }

    Assert-GitPathsClean -RepoRoot $RepoRoot -RelativePaths $trackedPaths -Label 'Codex 快照导出'

    if ($ValidateOnly) {
        Write-Host 'Codex 快照导出预检通过。'
        Write-Host ("  live source -> {0}" -f $sourceRoot)
        Write-Host ("  snapshot root -> {0}" -f $snapshotRoot)
        exit 0
    }

    Write-Host '开始导出 Codex 配置...'
    Copy-FileSnapshot -SourcePath $configSourcePath -DestinationPath $configSnapshotPath
    Copy-FileSnapshot -SourcePath $agentsSourcePath -DestinationPath $agentsSnapshotPath
    Sync-DirectorySnapshot -SourcePath $skillsSourcePath -DestinationPath $skillsSnapshotPath

    Assert-FilesMatch -SourcePath $configSourcePath -DestinationPath $configSnapshotPath -Label 'config.toml'
    Assert-FilesMatch -SourcePath $agentsSourcePath -DestinationPath $agentsSnapshotPath -Label 'AGENTS.md'
    Assert-DirectoryTopLevelMatch -SourcePath $skillsSourcePath -DestinationPath $skillsSnapshotPath -Label 'skills'

    Write-Host 'Codex 配置导出完成。'
    Write-Host ("  live source -> {0}" -f $sourceRoot)
    Write-Host ("  config.toml -> {0}" -f $configSnapshotPath)
    Write-Host ("  AGENTS.md -> {0}" -f $agentsSnapshotPath)
    Write-Host ("  skills -> {0}" -f $skillsSnapshotPath)
    Write-GitStatusSummary -RepoRoot $RepoRoot -RelativePaths $trackedPaths
}
catch {
    Write-SetupFailure -Title 'Codex 配置导出失败。' -Message $_.Exception.Message
    exit 1
}
