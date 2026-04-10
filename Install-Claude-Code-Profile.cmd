@echo off
setlocal
set "SELF=%~f0"
set "TMPPS=%TEMP%\Install-Claude-Code-Profile-%RANDOM%%RANDOM%.ps1"

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$content = Get-Content -LiteralPath $env:SELF -Raw -Encoding UTF8; $marker = ':__POWERSHELL_PAYLOAD__'; $index = $content.LastIndexOf($marker); if ($index -lt 0) { throw 'Marker not found.' }; $script = $content.Substring($index + $marker.Length).TrimStart([char]13, [char]10); $utf8NoBom = New-Object System.Text.UTF8Encoding($false); [System.IO.File]::WriteAllText($env:TMPPS, $script, $utf8NoBom)"
if errorlevel 1 goto :prepare_fail

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%TMPPS%"
set "EXIT_CODE=%ERRORLEVEL%"

del /q "%TMPPS%" >nul 2>nul

if not "%EXIT_CODE%"=="0" (
    echo.
    echo 安装失败，退出码 %EXIT_CODE%。
    pause
)

exit /b %EXIT_CODE%

:prepare_fail
echo 安装脚本准备失败。
pause
exit /b 1

:__POWERSHELL_PAYLOAD__
$ErrorActionPreference = 'Stop'

function Ensure-Directory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Fail-Install {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Write-Host ''
    Write-Host 'Claude 配置安装失败。' -ForegroundColor Red
    Write-Host ("  {0}" -f $Message) -ForegroundColor Red
    exit 1
}

function Sync-DirectorySnapshot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [string]$DestinationPath
    )

    if (-not (Test-Path -LiteralPath $SourcePath)) {
        throw "Missing directory snapshot: $SourcePath"
    }

    $parentPath = Split-Path -Parent $DestinationPath
    $leafName = Split-Path -Leaf $DestinationPath
    $stagingPath = Join-Path $parentPath ("{0}.staging.{1}" -f $leafName, [guid]::NewGuid().ToString('N'))
    $backupPath = Join-Path $parentPath ("{0}.backup.{1}" -f $leafName, [guid]::NewGuid().ToString('N'))
    $hasBackup = $false

    Ensure-Directory -Path $parentPath
    Copy-Item -LiteralPath $SourcePath -Destination $stagingPath -Recurse -Force

    try {
        if (Test-Path -LiteralPath $DestinationPath) {
            Move-Item -LiteralPath $DestinationPath -Destination $backupPath
            $hasBackup = $true
        }

        Move-Item -LiteralPath $stagingPath -Destination $DestinationPath
    }
    catch {
        if (-not (Test-Path -LiteralPath $DestinationPath) -and $hasBackup -and (Test-Path -LiteralPath $backupPath)) {
            Move-Item -LiteralPath $backupPath -Destination $DestinationPath
            $hasBackup = $false
        }

        throw
    }
    finally {
        if (Test-Path -LiteralPath $stagingPath) {
            Remove-Item -LiteralPath $stagingPath -Recurse -Force
        }

        if ($hasBackup -and (Test-Path -LiteralPath $backupPath)) {
            Remove-Item -LiteralPath $backupPath -Recurse -Force
        }
    }
}

function Remove-StaleDirectories {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath,

        [Parameter(Mandatory = $true)]
        [string[]]$AllowedNames
    )

    if (-not (Test-Path -LiteralPath $RootPath)) {
        return @()
    }

    $removed = @()
    foreach ($directory in Get-ChildItem -LiteralPath $RootPath -Directory) {
        if ($AllowedNames -contains $directory.Name) {
            continue
        }

        Remove-Item -LiteralPath $directory.FullName -Recurse -Force
        $removed += $directory.Name
    }

    return $removed
}

function Add-UniquePath {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Seen,

        [Parameter(Mandatory = $true)]
        [System.Collections.Generic.List[string]]$Paths,

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [switch]$RequireExists
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return
    }

    if ($RequireExists -and -not (Test-Path -LiteralPath $Path)) {
        return
    }

    if (Test-Path -LiteralPath $Path) {
        $normalizedPath = (Resolve-Path -LiteralPath $Path).Path
    } else {
        $normalizedPath = $Path
    }

    if ($Seen.ContainsKey($normalizedPath)) {
        return
    }

    $Seen[$normalizedPath] = $true
    $Paths.Add($normalizedPath) | Out-Null
}

function Get-ClaudeDesktopRoots {
    param(
        [switch]$IncludeDefaultAppData
    )

    $roots = New-Object 'System.Collections.Generic.List[string]'
    $seen = @{}
    $appDataRoot = Join-Path $env:APPDATA 'Claude'

    if ($IncludeDefaultAppData) {
        Add-UniquePath -Seen $seen -Paths $roots -Path $appDataRoot
    } else {
        Add-UniquePath -Seen $seen -Paths $roots -Path $appDataRoot -RequireExists
    }

    $packagesRoot = Join-Path $env:LOCALAPPDATA 'Packages'
    if (Test-Path -LiteralPath $packagesRoot) {
        foreach ($packageDir in Get-ChildItem -LiteralPath $packagesRoot -Directory -ErrorAction SilentlyContinue) {
            if ($packageDir.Name -notlike 'Claude*') {
                continue
            }

            $candidateRoot = Join-Path $packageDir.FullName 'LocalCache\Roaming\Claude'
            Add-UniquePath -Seen $seen -Paths $roots -Path $candidateRoot -RequireExists
        }
    }

    return $roots.ToArray()
}

function Get-ClaudeCliPath {
    $command = Get-Command 'claude', 'claude.exe' -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if ($command -and $command.Source) {
        return $command.Source
    }

    $candidates = New-Object 'System.Collections.Generic.List[string]'
    $seen = @{}

    $appDataCliRoot = Join-Path $env:APPDATA 'Claude\claude-code'
    if (Test-Path -LiteralPath $appDataCliRoot) {
        foreach ($versionDir in Get-ChildItem -LiteralPath $appDataCliRoot -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending) {
            Add-UniquePath -Seen $seen -Paths $candidates -Path (Join-Path $versionDir.FullName 'claude.exe') -RequireExists
        }
    }

    $packagesRoot = Join-Path $env:LOCALAPPDATA 'Packages'
    if (Test-Path -LiteralPath $packagesRoot) {
        foreach ($packageDir in Get-ChildItem -LiteralPath $packagesRoot -Directory -ErrorAction SilentlyContinue) {
            if ($packageDir.Name -notlike 'Claude*') {
                continue
            }

            $cliRoot = Join-Path $packageDir.FullName 'LocalCache\Roaming\Claude\claude-code'
            if (-not (Test-Path -LiteralPath $cliRoot)) {
                continue
            }

            foreach ($versionDir in Get-ChildItem -LiteralPath $cliRoot -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending) {
                Add-UniquePath -Seen $seen -Paths $candidates -Path (Join-Path $versionDir.FullName 'claude.exe') -RequireExists
            }
        }
    }

    return $candidates | Select-Object -First 1
}

try {
    $repoRoot = Split-Path -Parent $env:SELF
    $profileDir = Join-Path $repoRoot 'claude-code-profile'
    $claudeRoot = Join-Path $env:USERPROFILE '.claude'

    if (-not (Test-Path -LiteralPath $profileDir)) {
        throw "未找到仓库内的 Claude 配置快照目录：$profileDir"
    }

    $claudeMdSrc = Join-Path $profileDir 'CLAUDE.md'
    $settingsSrc = Join-Path $profileDir 'settings.json'
    $desktopSrcDir = Join-Path $profileDir 'claude-desktop'

    if (-not (Test-Path -LiteralPath $claudeMdSrc)) {
        throw "未找到仓库内的 CLAUDE.md：$claudeMdSrc"
    }

    if (-not (Test-Path -LiteralPath $settingsSrc)) {
        throw "未找到仓库内的 settings.json：$settingsSrc"
    }

    Write-Host '开始检查前置条件...'

    $settings = Get-Content -LiteralPath $settingsSrc -Raw | ConvertFrom-Json
    $plugins = @()
    if ($settings.enabledPlugins) {
        $plugins = $settings.enabledPlugins.PSObject.Properties.Name
    }

    $claudeCmd = Get-ClaudeCliPath
    if (-not $claudeCmd) {
        throw '未检测到 Claude Code CLI。请先安装 Claude Code，并至少启动一次后完全退出，再运行本脚本。'
    }
    Write-Host ("  Claude Code CLI -> {0}" -f $claudeCmd)

    if ($plugins.Count -gt 0) {
        $gitCmd = Get-Command 'git.exe', 'git' -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $gitCmd) {
            throw '未检测到 Git。Claude Code 插件安装依赖 Git，请先安装 Git，并重新打开终端后再运行本脚本。'
        }
        Write-Host ("  Git -> {0}" -f $gitCmd.Source)
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
    Copy-Item -LiteralPath $claudeMdSrc -Destination $claudeMdDst -Force
    Write-Host ("  CLAUDE.md -> {0}" -f $claudeMdDst)

    Write-Host ''
    Write-Host '── Settings ──────────────────────────────────────'
    $settingsDst = Join-Path $claudeRoot 'settings.json'
    Ensure-Directory -Path $claudeRoot
    Copy-Item -LiteralPath $settingsSrc -Destination $settingsDst -Force
    Write-Host ("  settings.json -> {0}" -f $settingsDst)

    Write-Host ''
    Write-Host '── Plugins ───────────────────────────────────────'
    Write-Host ("  claude cli -> {0}" -f $claudeCmd)

    $pluginsFailed = @()
    foreach ($p in $plugins) {
        Write-Host ("  正在安装 {0} ..." -f $p) -NoNewline
        try {
            & $claudeCmd plugin install $p --scope user 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Host ' OK' -ForegroundColor Green
            } else {
                Write-Host (" 失败 (exit {0})" -f $LASTEXITCODE) -ForegroundColor Red
                $pluginsFailed += $p
            }
        } catch {
            Write-Host (" 失败 ({0})" -f $_.Exception.Message) -ForegroundColor Red
            $pluginsFailed += $p
        }
    }
    if ($pluginsFailed.Count -gt 0) {
        Write-Host ''
        Write-Host '  以下插件安装失败，请手动安装：' -ForegroundColor Yellow
        foreach ($p in $pluginsFailed) {
            Write-Host ("    claude plugin install {0}" -f $p)
        }
    }

    Write-Host ''
    Write-Host '── Extensions ────────────────────────────────────'

    if (Test-Path -LiteralPath $desktopSrcDir) {
        foreach ($targetRoot in $claudeDesktopRoots) {
            $cfgSrc = Join-Path $desktopSrcDir 'claude_desktop_config.json'
            if (Test-Path -LiteralPath $cfgSrc) {
                $cfgDst = Join-Path $targetRoot 'claude_desktop_config.json'
                $srcObj = Get-Content -LiteralPath $cfgSrc -Raw | ConvertFrom-Json
                if (Test-Path -LiteralPath $cfgDst) {
                    $dstObj = Get-Content -LiteralPath $cfgDst -Raw | ConvertFrom-Json
                    $dstObj.preferences = $srcObj.preferences
                    $dstObj | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $cfgDst -Encoding UTF8
                } else {
                    Copy-Item -LiteralPath $cfgSrc -Destination $cfgDst -Force
                }
                Write-Host ("  claude_desktop_config.json -> {0}" -f $cfgDst)
            }
        }

        $extSettingsSrcDir = Join-Path $desktopSrcDir 'extension-settings'
        if (Test-Path -LiteralPath $extSettingsSrcDir) {
            foreach ($targetRoot in $claudeDesktopRoots) {
                $extSettingsDstDir = Join-Path $targetRoot 'Claude Extensions Settings'
                Sync-DirectorySnapshot -SourcePath $extSettingsSrcDir -DestinationPath $extSettingsDstDir
                Write-Host ("  extension settings -> {0}" -f $extSettingsDstDir)
            }
        }

        $extSrc = Join-Path $desktopSrcDir 'extensions-installations.json'
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
                $removedExtensions = Remove-StaleDirectories -RootPath $extDir -AllowedNames $allowedExtensionIds

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
                    Write-Host ''
                    Write-Host ("  以下 Desktop 扩展需要在 Claude Desktop 中手动安装：{0}" -f $desktopRoot) -ForegroundColor Yellow
                    Write-Host '  (打开 Claude Desktop -> Settings -> Extensions -> 搜索安装)' -ForegroundColor Yellow
                    Write-Host ''
                    foreach ($ext in $missing) {
                        Write-Host ("    - {0} v{1} ({2})" -f $ext.DisplayName, $ext.Version, $ext.Id)
                    }
                } else {
                    Write-Host ("  所有 Desktop 扩展已就绪。({0})" -f $desktopRoot)
                }
            }
        }
    }

    Write-Host ''
    Write-Host '══════════════════════════════════════════════════'
    Write-Host ' Claude Code Profile 恢复完成！'
    Write-Host '  - CLAUDE.md:  已恢复（全局协作协议）'
    Write-Host '  - Settings:   已恢复（权限 + marketplace）'
    Write-Host '  - Plugins:    已通过 CLI 安装（或已列出手动命令）'
    Write-Host '  - Extensions: 偏好已恢复（缺失扩展已列出）'
    Write-Host '  - Restart:    若 Claude / Claude Desktop 正在运行，请完全退出后重新打开'
    Write-Host '══════════════════════════════════════════════════'
}
catch {
    Fail-Install -Message $_.Exception.Message
}
