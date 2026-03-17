#Requires -RunAsAdministrator
# ============================================================
# Claude Code 一键配置脚本
# 用途：换设备时快速恢复 Claude Code 个人配置
# 包含：全局最高权限 | 管理员快捷方式 | 回车键改为换行
# ============================================================

$ErrorActionPreference = 'Stop'
$claudeDir = "$env:USERPROFILE\.claude"
$launcherDir = "$env:LOCALAPPDATA\ClaudeLauncher"
$launcherPath = Join-Path $launcherDir 'Launch-Claude.ps1'
$iconPath = Join-Path $launcherDir 'Claude.ico'

function Write-ShortcutIcon {
    param(
        [string]$ExecutablePath,
        [string]$IconPath
    )

    try {
        Add-Type -AssemblyName System.Drawing

        $iconDir = Split-Path $IconPath -Parent
        if (-not (Test-Path $iconDir)) {
            New-Item -ItemType Directory -Path $iconDir -Force | Out-Null
        }

        $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($ExecutablePath)
        if (-not $icon) {
            Write-Warning "无法从 $ExecutablePath 提取图标，将回退到 Claude.exe 图标路径。"
            return $false
        }

        try {
            $stream = [System.IO.File]::Open(
                $IconPath,
                [System.IO.FileMode]::Create,
                [System.IO.FileAccess]::Write
            )

            try {
                $icon.Save($stream)
            } finally {
                $stream.Dispose()
            }
        } finally {
            $icon.Dispose()
        }

        return $true
    } catch {
        Write-Warning "写入本地图标失败：$($_.Exception.Message)。将回退到 Claude.exe 图标路径。"
        return $false
    }
}

# 确保 .claude 目录存在
if (-not (Test-Path $claudeDir)) {
    New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null
}

# ---- 1. 全局最高权限 ----
Write-Host "[1/3] 配置全局最高权限..." -ForegroundColor Cyan

$settings = @'
{
  "permissions": {
    "allow": [
      "*"
    ],
    "deny": []
  }
}
'@
Set-Content -Path "$claudeDir\settings.json" -Value $settings -Encoding UTF8
Write-Host "      已写入 $claudeDir\settings.json" -ForegroundColor Green

# ---- 2. 创建管理员快捷方式 ----
Write-Host "[2/3] 创建管理员快捷方式..." -ForegroundColor Cyan

# 创建启动脚本
if (-not (Test-Path $launcherDir)) {
    New-Item -ItemType Directory -Path $launcherDir -Force | Out-Null
}

$launchScript = @'
Add-Type -AssemblyName PresentationFramework

$package = Get-AppxPackage Claude |
    Sort-Object Version -Descending |
    Select-Object -First 1

if (-not $package) {
    [System.Windows.MessageBox]::Show(
        'Claude is not installed.',
        'Claude Launcher',
        'OK',
        'Error'
    ) | Out-Null
    exit 1
}

$candidates = @(
    (Join-Path $package.InstallLocation 'app\Claude.exe'),
    (Join-Path $package.InstallLocation 'app\claude.exe')
) | Where-Object { Test-Path $_ }

if (-not $candidates) {
    [System.Windows.MessageBox]::Show(
        'The Claude executable was not found.',
        'Claude Launcher',
        'OK',
        'Error'
    ) | Out-Null
    exit 1
}

$exePath = $candidates[0]
Start-Process -FilePath $exePath -WorkingDirectory (Split-Path $exePath) -Verb RunAs
exit 0
'@
Set-Content -Path $launcherPath -Value $launchScript -Encoding UTF8

# 创建快捷方式
$lnkPath = "$env:USERPROFILE\Desktop\Claude.lnk"
$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut($lnkPath)
$Shortcut.TargetPath = "powershell.exe"
$Shortcut.Arguments = '-WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f $launcherPath
$Shortcut.Description = "Claude (以管理员身份运行)"

# 尝试设置图标为本地缓存图标，失败时回退到 Claude.exe
$package = Get-AppxPackage Claude | Sort-Object Version -Descending | Select-Object -First 1
if ($package) {
    $iconCandidates = @(
        (Join-Path $package.InstallLocation 'app\Claude.exe'),
        (Join-Path $package.InstallLocation 'app\claude.exe')
    ) | Where-Object { Test-Path $_ }

    if ($iconCandidates.Count -gt 0) {
        $exeIcon = $iconCandidates[0]
        $iconCached = Write-ShortcutIcon -ExecutablePath $exeIcon -IconPath $iconPath

        if ($iconCached -and (Test-Path $iconPath)) {
            $Shortcut.IconLocation = "$iconPath,0"
        } else {
            $Shortcut.IconLocation = "$exeIcon,0"
        }
    } else {
        Write-Warning '未找到 Claude.exe，快捷方式图标将保持系统默认值。'
    }
} else {
    Write-Warning '未找到 Claude 安装包，快捷方式图标将保持系统默认值。'
}
$Shortcut.Save()

# 设置"以管理员身份运行"标志 (字节 0x15, 位 5)
$bytes = [System.IO.File]::ReadAllBytes($lnkPath)
$bytes[0x15] = $bytes[0x15] -bor 0x20
[System.IO.File]::WriteAllBytes($lnkPath, $bytes)

Write-Host "      已创建 $lnkPath (管理员模式)" -ForegroundColor Green

# ---- 3. 回车键改为换行 ----
Write-Host "[3/3] 配置回车键为换行..." -ForegroundColor Cyan

$keybindings = @'
{
  "$schema": "https://www.schemastore.org/claude-code-keybindings.json",
  "$docs": "https://code.claude.com/docs/en/keybindings",
  "bindings": [
    {
      "context": "Chat",
      "bindings": {
        "enter": "chat:newline",
        "ctrl+enter": "chat:submit"
      }
    }
  ]
}
'@
Set-Content -Path "$claudeDir\keybindings.json" -Value $keybindings -Encoding UTF8
Write-Host "      已写入 $claudeDir\keybindings.json" -ForegroundColor Green

# ---- 完成 ----
Write-Host ""
Write-Host "============================================" -ForegroundColor Yellow
Write-Host " 全部配置完成！" -ForegroundColor Yellow
Write-Host " - 全局权限: 所有工具自动批准" -ForegroundColor White
Write-Host " - 快捷方式: 桌面 Claude.lnk (管理员)" -ForegroundColor White
Write-Host " - 按键绑定: Enter=换行, Ctrl+Enter=发送" -ForegroundColor White
Write-Host "============================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "Launcher script: $launcherPath"
if (Test-Path $iconPath) {
    Write-Host "Shortcut icon: $iconPath"
}
