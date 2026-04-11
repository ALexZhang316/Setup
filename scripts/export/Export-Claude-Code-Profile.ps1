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

function Sync-DirectoryFromOptionalSource {
    param(
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [string]$DestinationPath
    )

    if (Test-Path -LiteralPath $SourcePath) {
        Sync-DirectorySnapshot -SourcePath $SourcePath -DestinationPath $DestinationPath
        return [pscustomobject]@{
            ValidationSourcePath = $SourcePath
            CleanupPath = $null
        }
    }

    $temporaryRoot = Join-Path $env:TEMP ("Setup-EmptyDir-{0}" -f [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null
    Sync-DirectorySnapshot -SourcePath $temporaryRoot -DestinationPath $DestinationPath

    return [pscustomobject]@{
        ValidationSourcePath = $temporaryRoot
        CleanupPath = $temporaryRoot
    }
}

try {
    $sourceRoot = Join-Path $env:USERPROFILE '.claude'
    $claudeMdSourcePath = Join-Path $sourceRoot 'CLAUDE.md'
    $settingsSourcePath = Join-Path $sourceRoot 'settings.json'

    $snapshotRoot = Join-Path $RepoRoot 'claude-code-profile'
    $claudeMdSnapshotPath = Join-Path $snapshotRoot 'CLAUDE.md'
    $settingsSnapshotPath = Join-Path $snapshotRoot 'settings.json'
    $desktopSnapshotRoot = Join-Path $snapshotRoot 'claude-desktop'
    $desktopConfigSnapshotPath = Join-Path $desktopSnapshotRoot 'claude_desktop_config.json'
    $desktopInstallationsSnapshotPath = Join-Path $desktopSnapshotRoot 'extensions-installations.json'
    $desktopSettingsSnapshotPath = Join-Path $desktopSnapshotRoot 'extension-settings'

    $trackedPaths = @(
        'claude-code-profile\CLAUDE.md'
        'claude-code-profile\settings.json'
        'claude-code-profile\claude-desktop'
    )

    Assert-FileExists -Path $claudeMdSourcePath -Label '本机 .claude\CLAUDE.md'
    Assert-FileExists -Path $settingsSourcePath -Label '本机 .claude\settings.json'
    Assert-JsonFile -Path $settingsSourcePath -Label '.claude\settings.json'
    Assert-GitPathsClean -RepoRoot $RepoRoot -RelativePaths $trackedPaths -Label 'Claude 快照导出'

    $desktopSourceRoot = Get-CanonicalClaudeDesktopRoot
    $existingDesktopSnapshot = Test-Path -LiteralPath $desktopSnapshotRoot
    if (-not $desktopSourceRoot -and $existingDesktopSnapshot) {
        throw '仓库已有 Claude Desktop 快照，但本机未检测到 Claude Desktop 数据目录。请先安装并启动一次 Claude Desktop，或先清理仓库中的旧 Desktop 快照。'
    }

    $desktopConfigSourcePath = $null
    $desktopInstallationsSourcePath = $null
    $desktopSettingsSourcePath = $null
    if ($desktopSourceRoot) {
        $desktopConfigSourcePath = Join-Path $desktopSourceRoot 'claude_desktop_config.json'
        $desktopInstallationsSourcePath = Join-Path $desktopSourceRoot 'extensions-installations.json'
        $desktopSettingsSourcePath = Join-Path $desktopSourceRoot 'Claude Extensions Settings'

        Assert-FileExists -Path $desktopConfigSourcePath -Label 'Claude Desktop 配置文件'
        Assert-FileExists -Path $desktopInstallationsSourcePath -Label 'Claude Desktop 扩展安装清单'
        Assert-JsonFile -Path $desktopConfigSourcePath -Label 'claude_desktop_config.json'
        Assert-JsonFile -Path $desktopInstallationsSourcePath -Label 'extensions-installations.json'
    }

    if ($ValidateOnly) {
        Write-Host 'Claude 快照导出预检通过。'
        Write-Host ("  live source -> {0}" -f $sourceRoot)
        if ($desktopSourceRoot) {
            Write-Host ("  desktop source -> {0}" -f $desktopSourceRoot)
        }
        else {
            Write-Host '  desktop source -> 未检测到，本次仅导出 Claude Code 配置'
        }

        Write-Host ("  snapshot root -> {0}" -f $snapshotRoot)
        exit 0
    }

    Write-Host '开始导出 Claude 配置...'
    Copy-FileSnapshot -SourcePath $claudeMdSourcePath -DestinationPath $claudeMdSnapshotPath
    Copy-FileSnapshot -SourcePath $settingsSourcePath -DestinationPath $settingsSnapshotPath

    Assert-FilesMatch -SourcePath $claudeMdSourcePath -DestinationPath $claudeMdSnapshotPath -Label 'CLAUDE.md'
    Assert-FilesMatch -SourcePath $settingsSourcePath -DestinationPath $settingsSnapshotPath -Label 'settings.json'
    Assert-JsonFile -Path $settingsSnapshotPath -Label 'settings.json'

    if ($desktopSourceRoot) {
        Ensure-Directory -Path $desktopSnapshotRoot
        Copy-FileSnapshot -SourcePath $desktopConfigSourcePath -DestinationPath $desktopConfigSnapshotPath
        Copy-FileSnapshot -SourcePath $desktopInstallationsSourcePath -DestinationPath $desktopInstallationsSnapshotPath
        $settingsSyncResult = Sync-DirectoryFromOptionalSource -SourcePath $desktopSettingsSourcePath -DestinationPath $desktopSettingsSnapshotPath

        Assert-FilesMatch -SourcePath $desktopConfigSourcePath -DestinationPath $desktopConfigSnapshotPath -Label 'claude_desktop_config.json'
        Assert-FilesMatch -SourcePath $desktopInstallationsSourcePath -DestinationPath $desktopInstallationsSnapshotPath -Label 'extensions-installations.json'
        Assert-JsonFile -Path $desktopConfigSnapshotPath -Label 'claude_desktop_config.json'
        Assert-JsonFile -Path $desktopInstallationsSnapshotPath -Label 'extensions-installations.json'
        Assert-DirectorySnapshotMatch -SourcePath $settingsSyncResult.ValidationSourcePath -DestinationPath $desktopSettingsSnapshotPath -Label 'extension-settings'

        if ($settingsSyncResult.CleanupPath -and (Test-Path -LiteralPath $settingsSyncResult.CleanupPath)) {
            Remove-Item -LiteralPath $settingsSyncResult.CleanupPath -Recurse -Force
        }
    }

    Write-Host 'Claude 配置导出完成。'
    Write-Host ("  live source -> {0}" -f $sourceRoot)
    Write-Host ("  CLAUDE.md -> {0}" -f $claudeMdSnapshotPath)
    Write-Host ("  settings.json -> {0}" -f $settingsSnapshotPath)
    if ($desktopSourceRoot) {
        Write-Host ("  desktop source -> {0}" -f $desktopSourceRoot)
        Write-Host ("  claude_desktop_config.json -> {0}" -f $desktopConfigSnapshotPath)
        Write-Host ("  extensions-installations.json -> {0}" -f $desktopInstallationsSnapshotPath)
        Write-Host ("  extension-settings -> {0}" -f $desktopSettingsSnapshotPath)
    }
    else {
        Write-Host '  desktop source -> 未检测到，本次未更新 Claude Desktop 快照'
    }

    Write-GitStatusSummary -RepoRoot $RepoRoot -RelativePaths $trackedPaths
}
catch {
    Write-SetupFailure -Title 'Claude 配置导出失败。' -Message $_.Exception.Message
    exit 1
}
