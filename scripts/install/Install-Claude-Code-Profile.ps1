param(
    [string]$RepoRoot
)

$ErrorActionPreference = 'Stop'

if (-not $RepoRoot) {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}

. (Join-Path $PSScriptRoot '..\lib\Setup.Common.ps1')
. (Join-Path $PSScriptRoot '..\lib\Setup.Discovery.ps1')

function Get-PluginListValidationResult {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ClaudeCmd,

        [Parameter(Mandatory = $true)]
        [string[]]$ExpectedPlugins
    )

    $output = & $ClaudeCmd plugin list --json 2>$null
    if ($LASTEXITCODE -ne 0) {
        return [pscustomobject]@{
            Verified = $false
            Missing = @()
            Reason = 'plugin list --json 不可用'
        }
    }

    $jsonText = ($output -join "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($jsonText)) {
        return [pscustomobject]@{
            Verified = $false
            Missing = @()
            Reason = 'plugin list --json 输出为空'
        }
    }

    try {
        $parsed = $jsonText | ConvertFrom-Json
        $serialized = $parsed | ConvertTo-Json -Depth 100
        $missing = @()
        foreach ($pluginId in $ExpectedPlugins) {
            if ($serialized -notmatch [regex]::Escape($pluginId)) {
                $missing += $pluginId
            }
        }

        return [pscustomobject]@{
            Verified = $true
            Missing = $missing
            Reason = $null
        }
    }
    catch {
        return [pscustomobject]@{
            Verified = $false
            Missing = @()
            Reason = 'plugin list --json 输出不可解析'
        }
    }
}

function Assert-ClaudeDesktopPreferencesMatch {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [string]$DestinationPath
    )

    $sourcePreferences = (Get-Content -LiteralPath $SourcePath -Raw | ConvertFrom-Json).preferences
    $destinationPreferences = (Get-Content -LiteralPath $DestinationPath -Raw | ConvertFrom-Json).preferences
    $sourceJson = $sourcePreferences | ConvertTo-Json -Depth 100
    $destinationJson = $destinationPreferences | ConvertTo-Json -Depth 100

    if ($sourceJson -ne $destinationJson) {
        throw 'Claude Desktop 偏好校验失败：目标 preferences 与快照不一致。'
    }
}

try {
    $profileDir = Join-Path $RepoRoot 'claude-code-profile'
    $claudeRoot = Join-Path $env:USERPROFILE '.claude'
    $claudeMdSrc = Join-Path $profileDir 'CLAUDE.md'
    $settingsSrc = Join-Path $profileDir 'settings.json'
    $desktopSrcDir = Join-Path $profileDir 'claude-desktop'

    if (-not (Test-Path -LiteralPath $profileDir)) {
        throw "未找到仓库内的 Claude 配置快照目录：$profileDir"
    }

    Assert-FileExists -Path $claudeMdSrc -Label '仓库内的 CLAUDE.md'
    Assert-FileExists -Path $settingsSrc -Label '仓库内的 settings.json'
    Assert-JsonFile -Path $settingsSrc -Label 'settings.json'

    Write-Host '开始检查前置条件...'

    $settings = Get-Content -LiteralPath $settingsSrc -Raw | ConvertFrom-Json
    $plugins = @()
    if ($settings.enabledPlugins) {
        $plugins = @($settings.enabledPlugins.PSObject.Properties.Name | Sort-Object)
    }

    $claudeCmd = Get-ClaudeCliPath
    if (-not $claudeCmd) {
        throw '未检测到 Claude Code CLI。请先安装 Claude Code，并至少启动一次后完全退出，再运行本脚本。'
    }

    Write-Host ("  Claude Code CLI -> {0}" -f $claudeCmd)

    if ($plugins.Count -gt 0) {
        $gitCmd = Get-GitCommand
        if (-not $gitCmd) {
            throw '未检测到 Git。Claude Code 插件安装依赖 Git，请先安装 Git，并重新打开终端后再运行本脚本。'
        }

        Write-Host ("  Git -> {0}" -f $gitCmd)
    }

    $claudeDesktopRoots = @()
    if (Test-Path -LiteralPath $desktopSrcDir) {
        $claudeDesktopRoots = @(Get-ClaudeDesktopRoots)
        if ($claudeDesktopRoots.Count -eq 0) {
            throw '未检测到 Claude Desktop 数据目录。请先安装并启动一次 Claude Desktop，然后完全退出后再运行本脚本。'
        }

        foreach ($desktopRoot in $claudeDesktopRoots) {
            Write-Host ("  Claude Desktop -> {0}" -f $desktopRoot)
        }
    }

    Write-Host ''
    Write-Host '── CLAUDE.md ─────────────────────────────────────'
    $claudeMdDst = Join-Path $claudeRoot 'CLAUDE.md'
    Ensure-Directory -Path $claudeRoot
    Copy-FileSnapshot -SourcePath $claudeMdSrc -DestinationPath $claudeMdDst
    Assert-FilesMatch -SourcePath $claudeMdSrc -DestinationPath $claudeMdDst -Label 'CLAUDE.md'
    Write-Host ("  CLAUDE.md -> {0}" -f $claudeMdDst)

    Write-Host ''
    Write-Host '── Settings ──────────────────────────────────────'
    $settingsDst = Join-Path $claudeRoot 'settings.json'
    Copy-FileSnapshot -SourcePath $settingsSrc -DestinationPath $settingsDst
    Assert-FilesMatch -SourcePath $settingsSrc -DestinationPath $settingsDst -Label 'settings.json'
    Assert-JsonFile -Path $settingsDst -Label 'settings.json'
    Write-Host ("  settings.json -> {0}" -f $settingsDst)

    Write-Host ''
    Write-Host '── Plugins ───────────────────────────────────────'
    Write-Host ("  claude cli -> {0}" -f $claudeCmd)

    $pluginInstallFailures = @()
    foreach ($pluginId in $plugins) {
        Write-Host ("  正在安装 {0} ..." -f $pluginId) -NoNewline
        try {
            & $claudeCmd plugin install $pluginId --scope user 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Host ' OK' -ForegroundColor Green
            }
            else {
                Write-Host (" 失败 (exit {0})" -f $LASTEXITCODE) -ForegroundColor Red
                $pluginInstallFailures += $pluginId
            }
        }
        catch {
            Write-Host (" 失败 ({0})" -f $_.Exception.Message) -ForegroundColor Red
            $pluginInstallFailures += $pluginId
        }
    }

    if ($pluginInstallFailures.Count -gt 0) {
        throw ("以下插件安装失败：{0}" -f ($pluginInstallFailures -join '、'))
    }

    if ($plugins.Count -gt 0) {
        $pluginValidation = Get-PluginListValidationResult -ClaudeCmd $claudeCmd -ExpectedPlugins $plugins
        if ($pluginValidation.Verified) {
            if ($pluginValidation.Missing.Count -gt 0) {
                throw ("插件列表校验失败，缺少：{0}" -f ($pluginValidation.Missing -join '、'))
            }

            Write-Host '  插件列表校验 -> OK'
        }
        else {
            Write-SetupWarning ("  插件状态未做独立列举验证（{0}）。" -f $pluginValidation.Reason)
        }
    }

    Write-Host ''
    Write-Host '── Extensions ────────────────────────────────────'

    $desktopWarnings = New-Object 'System.Collections.Generic.List[string]'
    if (Test-Path -LiteralPath $desktopSrcDir) {
        $cfgSrc = Join-Path $desktopSrcDir 'claude_desktop_config.json'
        $extSettingsSrcDir = Join-Path $desktopSrcDir 'extension-settings'
        $extSrc = Join-Path $desktopSrcDir 'extensions-installations.json'

        if (Test-Path -LiteralPath $cfgSrc) {
            Assert-JsonFile -Path $cfgSrc -Label 'claude_desktop_config.json'
        }

        if (Test-Path -LiteralPath $extSrc) {
            Assert-JsonFile -Path $extSrc -Label 'extensions-installations.json'
        }

        foreach ($targetRoot in $claudeDesktopRoots) {
            if (Test-Path -LiteralPath $cfgSrc) {
                $cfgDst = Join-Path $targetRoot 'claude_desktop_config.json'
                if (Test-Path -LiteralPath $cfgDst) {
                    $srcObj = Get-Content -LiteralPath $cfgSrc -Raw | ConvertFrom-Json
                    $dstObj = Get-Content -LiteralPath $cfgDst -Raw | ConvertFrom-Json
                    $dstObj.preferences = $srcObj.preferences
                    $dstObj | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $cfgDst -Encoding UTF8
                }
                else {
                    Copy-FileSnapshot -SourcePath $cfgSrc -DestinationPath $cfgDst
                }

                Assert-JsonFile -Path $cfgDst -Label '目标 claude_desktop_config.json'
                Assert-ClaudeDesktopPreferencesMatch -SourcePath $cfgSrc -DestinationPath $cfgDst
                Write-Host ("  claude_desktop_config.json -> {0}" -f $cfgDst)
            }
        }

        if (Test-Path -LiteralPath $extSettingsSrcDir) {
            foreach ($targetRoot in $claudeDesktopRoots) {
                $extSettingsDstDir = Join-Path $targetRoot 'Claude Extensions Settings'
                Sync-DirectorySnapshot -SourcePath $extSettingsSrcDir -DestinationPath $extSettingsDstDir
                Assert-DirectoryTopLevelMatch -SourcePath $extSettingsSrcDir -DestinationPath $extSettingsDstDir -Label 'Claude Extensions Settings'
                Write-Host ("  extension settings -> {0}" -f $extSettingsDstDir)
            }
        }

        if (Test-Path -LiteralPath $extSrc) {
            $extData = Get-Content -LiteralPath $extSrc -Raw | ConvertFrom-Json
            $extNames = @()
            if ($extData.extensions) {
                $extData.extensions.PSObject.Properties | ForEach-Object {
                    $ext = $_.Value
                    $extNames += [PSCustomObject]@{
                        Id = $ext.id
                        DisplayName = $ext.manifest.display_name
                        Version = $ext.version
                    }
                }
            }

            foreach ($desktopRoot in $claudeDesktopRoots) {
                $extDir = Join-Path $desktopRoot 'Claude Extensions'
                $allowedExtensionIds = @($extNames | ForEach-Object { $_.Id })
                $removedExtensions = @()
                if (Test-Path -LiteralPath $extDir) {
                    foreach ($directory in Get-ChildItem -LiteralPath $extDir -Directory) {
                        if ($allowedExtensionIds -contains $directory.Name) {
                            continue
                        }

                        Remove-Item -LiteralPath $directory.FullName -Recurse -Force
                        $removedExtensions += $directory.Name
                    }
                }

                foreach ($removedExtension in $removedExtensions) {
                    Write-Host ("  removed stale extension -> {0} ({1})" -f $removedExtension, $desktopRoot)
                }

                $missing = @()
                foreach ($ext in $extNames) {
                    $extPath = Join-Path $extDir $ext.Id
                    if (-not (Test-Path -LiteralPath $extPath)) {
                        $missing += $ext
                    }
                }

                if ($missing.Count -gt 0) {
                    $desktopWarnings.Add(("以下 Desktop 扩展仍需手动安装：{0}" -f $desktopRoot)) | Out-Null
                    Write-Host ''
                    Write-SetupWarning ("  以下 Desktop 扩展需要在 Claude Desktop 中手动安装：{0}" -f $desktopRoot)
                    Write-SetupWarning '  (打开 Claude Desktop -> Settings -> Extensions -> 搜索安装)'
                    Write-Host ''
                    foreach ($ext in $missing) {
                        Write-SetupWarning ("    - {0} v{1} ({2})" -f $ext.DisplayName, $ext.Version, $ext.Id)
                    }
                }
                else {
                    Write-Host ("  所有 Desktop 扩展已就绪。({0})" -f $desktopRoot)
                }
            }
        }
    }

    Write-Host ''
    Write-Host '══════════════════════════════════════════════════'
    Write-Host ' Claude Code Profile 恢复完成！'
    Write-Host '  - CLAUDE.md:  已恢复并校验'
    Write-Host '  - Settings:   已恢复并校验'
    Write-Host '  - Plugins:    已安装；严格失败项会中断'
    Write-Host '  - Extensions: 偏好已恢复；缺失 GUI 扩展仅保留 warning'
    Write-Host '  - Restart:    若 Claude / Claude Desktop 正在运行，请完全退出后重新打开'
    if ($desktopWarnings.Count -gt 0) {
        Write-Host ("  - Warning:    {0}" -f $desktopWarnings.Count)
    }
    Write-Host '══════════════════════════════════════════════════'
}
catch {
    Write-SetupFailure -Title 'Claude 配置安装失败。' -Message $_.Exception.Message
    exit 1
}
