# Install-Chat-Enter-Newline.ps1 — 安装聊天窗口键盘映射
# Enter = 换行，Ctrl+Enter = 发送（仅在 Codex / Claude 窗口生效）
# 需要管理员权限（计划任务以最高权限运行），脚本会自动请求提权

param(
    [string]$RepoRoot,
    [switch]$Elevated
)

$ErrorActionPreference = 'Stop'

if (-not $RepoRoot) {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
}

# ---------- 提权 ----------

function Test-IsAdmin {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdmin)) {
    $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $elevateArgs = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -RepoRoot "{1}" -Elevated' -f $PSCommandPath, $RepoRoot
    try {
        $proc = Start-Process -FilePath $psExe -Verb RunAs -ArgumentList $elevateArgs -Wait -PassThru
        exit $proc.ExitCode
    } catch {
        Write-Host 'UAC 提权被拒绝或失败。此脚本需要管理员权限。' -ForegroundColor Red
        exit 1
    }
}

# ---------- 查找 AutoHotkey v2 ----------

function Find-AutoHotkey {
    $candidates = @(
        'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe',
        'C:\Program Files\AutoHotkey\v2\AutoHotkey.exe',
        'C:\Program Files (x86)\AutoHotkey\v2\AutoHotkey64.exe',
        'C:\Program Files (x86)\AutoHotkey\v2\AutoHotkey.exe'
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { return $c }
    }
    $cmd = Get-Command AutoHotkey64.exe, AutoHotkey.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }
    return $null
}

function Ensure-AutoHotkey {
    $exe = Find-AutoHotkey
    if ($exe) { return $exe }

    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) {
        throw '未检测到 AutoHotkey v2，且系统中没有 winget。请先手动安装 AutoHotkey v2。'
    }

    Write-Host '未检测到 AutoHotkey v2，通过 winget 自动安装...'
    $proc = Start-Process -FilePath $winget.Source -ArgumentList @(
        'install', '--id', 'AutoHotkey.AutoHotkey', '-e',
        '--accept-package-agreements', '--accept-source-agreements',
        '--disable-interactivity', '--silent'
    ) -NoNewWindow -PassThru

    if (-not $proc.WaitForExit(300000)) {
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        throw 'winget 安装 AutoHotkey 超时（5 分钟）。'
    }
    if ($proc.ExitCode -ne 0) {
        throw ("winget 安装失败，退出码 {0}。" -f $proc.ExitCode)
    }

    $exe = Find-AutoHotkey
    if (-not $exe) { throw '安装完成但仍找不到 AutoHotkey v2 可执行文件。' }
    return $exe
}

# ---------- AHK 脚本内容 ----------

$ahkContent = @'
#Requires AutoHotkey v2.0
#SingleInstance Force

#HotIf WinActive("ahk_exe Codex.exe") || WinActive("ahk_exe Claude.exe")

$Enter::
{
    SendInput "+{Enter}"
}

$^Enter::
{
    Hotkey "$Enter", "Off"
    try {
        SendInput "{Enter}"
    }
    finally {
        Hotkey "$Enter", "On"
    }
}

$NumpadEnter::
{
    SendInput "+{Enter}"
}

$^NumpadEnter::
{
    Hotkey "$NumpadEnter", "Off"
    try {
        SendInput "{Enter}"
    }
    finally {
        Hotkey "$NumpadEnter", "On"
    }
}

#HotIf
'@

# ---------- 主流程 ----------

try {
    $remapRoot  = Join-Path $env:LOCALAPPDATA 'DesktopAIKeyRemap'
    $scriptPath = Join-Path $remapRoot 'ChatEnterNewline.ahk'
    $taskName   = 'Desktop AI Enter Newline Remap'

    Write-Host '检查前置条件...'
    $ahkExe = Ensure-AutoHotkey
    Write-Host ("  AutoHotkey -> {0}" -f $ahkExe)

    # 写入 AHK 脚本
    if (-not (Test-Path $remapRoot)) { New-Item -ItemType Directory -Path $remapRoot -Force | Out-Null }
    Set-Content -LiteralPath $scriptPath -Value $ahkContent -Encoding UTF8
    Write-Host ("  脚本 -> {0}" -f $scriptPath)

    # 停止已有的 AHK 进程（如果有）
    Get-Process -Name AutoHotkey*, AutoHotkey64* -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and $_.CommandLine -like "*ChatEnterNewline*" } |
        Stop-Process -Force -ErrorAction SilentlyContinue

    # 清理旧版计划任务
    foreach ($old in @('Codex Enter Newline Remap')) {
        $t = Get-ScheduledTask -TaskName $old -ErrorAction SilentlyContinue
        if ($t) { Unregister-ScheduledTask -TaskName $old -Confirm:$false }
    }

    # 注册计划任务（开机自启）
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $action    = New-ScheduledTaskAction -Execute $ahkExe -Argument ('"{0}"' -f $scriptPath)
    $trigger   = New-ScheduledTaskTrigger -AtLogOn -User $currentUser
    $principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Highest
    $settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null

    # 立即启动
    Start-Process -FilePath $ahkExe -ArgumentList ('"{0}"' -f $scriptPath)

    Write-Host ''
    Write-Host '聊天热键安装完成。'
    Write-Host '  Enter -> 换行'
    Write-Host '  Ctrl+Enter -> 发送'
    Write-Host ("  任务 -> {0}" -f $taskName)
}
catch {
    Write-Host ''
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
