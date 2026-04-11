param(
    [string]$RepoRoot
)

$ErrorActionPreference = 'Stop'

if (-not $RepoRoot) {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}

. (Join-Path $PSScriptRoot '..\lib\Setup.Common.ps1')
. (Join-Path $PSScriptRoot '..\lib\Setup.Discovery.ps1')

try {
    $profileRoot = Join-Path $RepoRoot 'codex-profile'
    $configSourcePath = Join-Path $profileRoot 'config.toml'
    $agentsSourcePath = Join-Path $profileRoot 'AGENTS.md'
    $skillsSourcePath = Join-Path $profileRoot 'skills'

    $codexRoot = Join-Path $env:USERPROFILE '.codex'
    $configTargetPath = Join-Path $codexRoot 'config.toml'
    $agentsTargetPath = Join-Path $codexRoot 'AGENTS.md'
    $skillsTargetPath = Join-Path $codexRoot 'skills'

    Assert-FileExists -Path $configSourcePath -Label '仓库内的 Codex 配置快照'
    Assert-FileExists -Path $agentsSourcePath -Label '仓库内的 Codex 全局指令文件'
    if (-not (Test-Path -LiteralPath $skillsSourcePath)) {
        throw "未找到仓库内的 Codex skills 快照：$skillsSourcePath"
    }

    Write-Host '开始检查前置条件...'
    $codexExe = Get-CodexExecutablePath
    if (-not $codexExe) {
        throw '未检测到 Codex 可执行文件。请先安装 Codex，并至少启动一次后完全退出，再运行本脚本。'
    }

    Write-Host ("  Codex -> {0}" -f $codexExe)
    Assert-ProcessesStopped -Label 'Codex' -ProcessNames @('Codex.exe', 'codex.exe')

    Ensure-Directory -Path $codexRoot
    Copy-FileSnapshot -SourcePath $configSourcePath -DestinationPath $configTargetPath
    Copy-FileSnapshot -SourcePath $agentsSourcePath -DestinationPath $agentsTargetPath
    Sync-DirectorySnapshot -SourcePath $skillsSourcePath -DestinationPath $skillsTargetPath

    Assert-FilesMatch -SourcePath $configSourcePath -DestinationPath $configTargetPath -Label 'config.toml'
    Assert-FilesMatch -SourcePath $agentsSourcePath -DestinationPath $agentsTargetPath -Label 'AGENTS.md'
    Assert-DirectorySnapshotMatch -SourcePath $skillsSourcePath -DestinationPath $skillsTargetPath -Label 'skills'

    Write-Host ''
    Write-Host 'Codex 配置恢复完成。'
    Write-Host ("  config.toml -> {0}" -f $configTargetPath)
    Write-Host ("  AGENTS.md -> {0}" -f $agentsTargetPath)
    Write-Host ("  skills -> {0}" -f $skillsTargetPath)
    Write-Host '  验证 -> 文件与目录快照一致'
    Write-Host '  如果 Codex 当前正在运行，请完全退出后重新打开。'
}
catch {
    Write-SetupFailure -Title 'Codex 配置安装失败。' -Message $_.Exception.Message
    exit 1
}
