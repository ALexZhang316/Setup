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

$repoRoot = Split-Path -Parent $env:SELF
$profileDir = Join-Path $repoRoot 'claude-code-profile'
$claudeRoot = Join-Path $env:USERPROFILE '.claude'
$claudeDesktopRoot = Join-Path $env:APPDATA 'Claude'

if (-not (Test-Path -LiteralPath $profileDir)) {
    throw "未找到配置快照目录：$profileDir"
}

# ══════════════════════════════════════════════════════════════
#  1. CLAUDE.md — 恢复全局协作协议
# ══════════════════════════════════════════════════════════════
Write-Host ''
Write-Host '── CLAUDE.md ─────────────────────────────────────'
$claudeMdSrc = Join-Path $profileDir 'CLAUDE.md'
$claudeMdDst = Join-Path $claudeRoot 'CLAUDE.md'
Ensure-Directory -Path $claudeRoot
if (Test-Path -LiteralPath $claudeMdSrc) {
    Copy-Item -LiteralPath $claudeMdSrc -Destination $claudeMdDst -Force
    Write-Host ("  CLAUDE.md -> {0}" -f $claudeMdDst)
} else {
    Write-Host '  [跳过] 未找到 CLAUDE.md' -ForegroundColor Yellow
}

# ══════════════════════════════════════════════════════════════
#  2. Settings — 恢复 settings.json（权限 + 插件启用列表）
# ══════════════════════════════════════════════════════════════
Write-Host ''
Write-Host '── Settings ──────────────────────────────────────'
$settingsSrc = Join-Path $profileDir 'settings.json'
$settingsDst = Join-Path $claudeRoot 'settings.json'
Ensure-Directory -Path $claudeRoot
Copy-Item -LiteralPath $settingsSrc -Destination $settingsDst -Force
Write-Host ("  settings.json -> {0}" -f $settingsDst)

# ══════════════════════════════════════════════════════════════
#  3. Plugins — 通过 CLI 实际安装每个插件（下载到缓存）
# ══════════════════════════════════════════════════════════════
Write-Host ''
Write-Host '── Plugins ───────────────────────────────────────'

# 从 settings.json 读取启用的插件列表
$settings = Get-Content -LiteralPath $settingsSrc -Raw | ConvertFrom-Json
$plugins = @()
if ($settings.enabledPlugins) {
    $plugins = $settings.enabledPlugins.PSObject.Properties.Name
}

# 检查 claude CLI 是否可用
$claudeCmd = Get-Command 'claude' -ErrorAction SilentlyContinue
if (-not $claudeCmd) {
    Write-Host '  [跳过] 未找到 claude CLI，无法自动安装插件。' -ForegroundColor Yellow
    Write-Host '  请安装 Claude Code 后手动执行：' -ForegroundColor Yellow
    foreach ($p in $plugins) {
        Write-Host ("    claude plugin install {0}" -f $p)
    }
} else {
    $pluginsFailed = @()
    foreach ($p in $plugins) {
        Write-Host ("  正在安装 {0} ..." -f $p) -NoNewline
        try {
            & $claudeCmd.Source plugin install $p --scope user 2>&1 | Out-Null
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
}

# ══════════════════════════════════════════════════════════════
#  4. Extensions — Claude Desktop 偏好 + 扩展安装提示
# ══════════════════════════════════════════════════════════════
Write-Host ''
Write-Host '── Extensions ────────────────────────────────────'

$desktopSrcDir = Join-Path $profileDir 'claude-desktop'
if (Test-Path -LiteralPath $desktopSrcDir) {
    # 3a. Claude Desktop 偏好设置
    foreach ($targetRoot in @($claudeDesktopRoot, (Join-Path $env:LOCALAPPDATA 'Packages\Claude_pzs8sxrjxfjjc\LocalCache\Roaming\Claude'))) {
        if (-not (Test-Path -LiteralPath $targetRoot)) { continue }
        $cfgSrc = Join-Path $desktopSrcDir 'claude_desktop_config.json'
        if (Test-Path -LiteralPath $cfgSrc) {
            # 保留目标文件中的 oauth:tokenCache 等敏感字段
            $cfgDst = Join-Path $targetRoot 'claude_desktop_config.json'
            $srcObj = Get-Content -LiteralPath $cfgSrc -Raw | ConvertFrom-Json
            if (Test-Path -LiteralPath $cfgDst) {
                $dstObj = Get-Content -LiteralPath $cfgDst -Raw | ConvertFrom-Json
                # 只覆盖 preferences 部分，保留其他已有字段
                $dstObj.preferences = $srcObj.preferences
                $dstObj | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $cfgDst -Encoding UTF8
            } else {
                Copy-Item -LiteralPath $cfgSrc -Destination $cfgDst -Force
            }
            Write-Host ("  claude_desktop_config.json -> {0}" -f $cfgDst)
        }
    }

    # 3b. Per-extension settings (enabled/disabled)
    $extSettingsSrcDir = Join-Path $desktopSrcDir 'extension-settings'
    if (Test-Path -LiteralPath $extSettingsSrcDir) {
        $extSettingsDstDir = Join-Path $claudeDesktopRoot 'Claude Extensions Settings'
        Ensure-Directory -Path $extSettingsDstDir
        $files = Get-ChildItem -LiteralPath $extSettingsSrcDir -Filter '*.json'
        foreach ($f in $files) {
            Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $extSettingsDstDir $f.Name) -Force
            Write-Host ("  {0} -> {1}" -f $f.Name, $extSettingsDstDir)
        }
    }

    # 3c. 读取扩展注册表，提示手动安装
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

        # 检查哪些扩展缺少二进制文件
        $extDir = Join-Path $claudeDesktopRoot 'Claude Extensions'
        $missing = @()
        foreach ($ext in $extNames) {
            $extPath = Join-Path $extDir $ext.Id
            if (-not (Test-Path -LiteralPath $extPath)) {
                $missing += $ext
            }
        }

        if ($missing.Count -gt 0) {
            Write-Host ''
            Write-Host '  以下 Desktop 扩展需要在 Claude Desktop 中手动安装：' -ForegroundColor Yellow
            Write-Host '  (打开 Claude Desktop -> Settings -> Extensions -> 搜索安装)' -ForegroundColor Yellow
            Write-Host ''
            foreach ($ext in $missing) {
                Write-Host ("    - {0} v{1} ({2})" -f $ext.DisplayName, $ext.Version, $ext.Id)
            }
        } else {
            Write-Host '  所有 Desktop 扩展已就绪。'
        }
    }
}

# ══════════════════════════════════════════════════════════════
#  完成
# ══════════════════════════════════════════════════════════════
Write-Host ''
Write-Host '══════════════════════════════════════════════════'
Write-Host ' Claude Code Profile 恢复完成！'
Write-Host '  - CLAUDE.md:  已恢复（全局协作协议）'
Write-Host '  - Settings:   已恢复（权限 + marketplace）'
Write-Host '  - Plugins:    已通过 CLI 安装（或已列出手动命令）'
Write-Host '  - Extensions: 偏好已恢复（缺失扩展已列出）'
Write-Host '══════════════════════════════════════════════════'
