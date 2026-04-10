param(
    [string]$RepoRoot,
    [switch]$Elevated
)

$ErrorActionPreference = 'Stop'

if (-not $RepoRoot) {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}

. (Join-Path $PSScriptRoot '..\lib\Setup.Common.ps1')
. (Join-Path $PSScriptRoot '..\lib\Setup.Discovery.ps1')

function Write-RemapScript {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $content = @'
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

    Set-Content -LiteralPath $Path -Value $content -Encoding UTF8
}

function Stop-ExistingRemapProcess {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ScriptPaths
    )

    Get-CimInstance Win32_Process |
        Where-Object {
            $proc = $_
            $proc.Name -match '^AutoHotkey' -and
            $proc.CommandLine -and
            ($ScriptPaths | Where-Object {
                $path = $_
                $path -and $proc.CommandLine.Contains($path)
            })
        } |
        ForEach-Object {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        }
}

function Remove-LegacyTask {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$TaskNames
    )

    foreach ($taskName in $TaskNames) {
        $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if ($task) {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        }
    }
}

function Register-RemapTask {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ExecutablePath,

        [Parameter(Mandatory = $true)]
        [string]$ScriptPath
    )

    $taskName = 'Desktop AI Enter Newline Remap'
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $action = New-ScheduledTaskAction -Execute $ExecutablePath -Argument ('"{0}"' -f $ScriptPath)
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $currentUser
    $principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew

    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
    return $taskName
}

function Start-RemapProcess {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ExecutablePath,

        [Parameter(Mandatory = $true)]
        [string]$ScriptPath
    )

    Start-Process -FilePath $ExecutablePath -ArgumentList ('"{0}"' -f $ScriptPath) | Out-Null
}

try {
    Ensure-ProcessElevated -ScriptPath $PSCommandPath -RepoRoot $RepoRoot -Elevated:$Elevated

    $remapRoot = Join-Path $env:LOCALAPPDATA 'DesktopAIKeyRemap'
    $scriptPath = Join-Path $remapRoot 'ChatEnterNewline.ahk'
    $legacyScriptPath = Join-Path $env:LOCALAPPDATA 'CodexKeyRemap\CodexEnterNewline.ahk'
    $legacyClaudeScriptPath = Join-Path (Get-DesktopDirectory) 'ClaudeEnterSwap.ahk'

    Write-Host '开始检查前置条件...'
    $supportedApps = @(Resolve-SupportedApps)
    if ($supportedApps.Count -eq 0) {
        throw '未检测到 Codex 或 Claude 的可执行文件。请先安装至少一个目标应用，并至少启动一次后完全退出，再运行本脚本。'
    }

    foreach ($app in $supportedApps) {
        Write-Host ("  {0} -> {1}" -f $app.DisplayName, $app.Path)
    }

    Ensure-Directory -Path $remapRoot
    $autoHotkeyExe = Ensure-AutoHotkey
    Write-Host ("  AutoHotkey -> {0}" -f $autoHotkeyExe)

    Write-RemapScript -Path $scriptPath
    Assert-FileExists -Path $scriptPath -Label '聊天热键脚本'

    Stop-ExistingRemapProcess -ScriptPaths @($scriptPath, $legacyScriptPath, $legacyClaudeScriptPath)
    Remove-LegacyTask -TaskNames @('Codex Enter Newline Remap')

    $taskName = Register-RemapTask -ExecutablePath $autoHotkeyExe -ScriptPath $scriptPath
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if (-not $task) {
        throw ("计划任务创建失败：{0}" -f $taskName)
    }

    Start-RemapProcess -ExecutablePath $autoHotkeyExe -ScriptPath $scriptPath
    Start-Sleep -Seconds 2

    $process = Get-CimInstance Win32_Process |
        Where-Object { $_.Name -match '^AutoHotkey' -and $_.CommandLine -and $_.CommandLine.Contains($scriptPath) } |
        Select-Object -First 1

    if (-not $process) {
        throw '热键脚本进程未能成功启动。请先确认 AutoHotkey v2 可以正常运行，再重新执行本脚本。'
    }

    Write-Host '聊天热键安装完成。'
    Write-Host '  Enter -> 换行'
    Write-Host '  Ctrl+Enter -> 发送'
    Write-Host ("  Task -> {0}" -f $taskName)
    Write-Host ("  Script -> {0}" -f $scriptPath)
    Write-Host '  验证 -> 计划任务、AHK 脚本、活动进程均已存在'
}
catch {
    Write-SetupFailure -Title '聊天热键安装失败。' -Message $_.Exception.Message
    exit 1
}
