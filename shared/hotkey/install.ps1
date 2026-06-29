# install.ps1 - install chat-window keyboard remapping.
# Enter = newline, Ctrl+Enter = send. Applies to Codex and Claude Code windows.
# Requires administrator rights because the scheduled task runs elevated.

param(
    [string]$RepoRoot
)

$ErrorActionPreference = 'Stop'

if (-not $RepoRoot) {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}

function Test-IsAdmin {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdmin)) {
    $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $elevateArgs = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -RepoRoot "{1}"' -f $PSCommandPath, $RepoRoot
    try {
        $proc = Start-Process -FilePath $psExe -Verb RunAs -ArgumentList $elevateArgs -Wait -PassThru
        exit $proc.ExitCode
    }
    catch {
        Write-Host 'UAC elevation was cancelled or failed. Administrator rights are required.' -ForegroundColor Red
        exit 1
    }
}

function Find-AutoHotkey {
    $candidates = @(
        'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe',
        'C:\Program Files\AutoHotkey\v2\AutoHotkey.exe',
        'C:\Program Files (x86)\AutoHotkey\v2\AutoHotkey64.exe',
        'C:\Program Files (x86)\AutoHotkey\v2\AutoHotkey.exe'
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    $command = Get-Command AutoHotkey64.exe, AutoHotkey.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) {
        return $command.Source
    }

    return $null
}

function Ensure-AutoHotkey {
    $exe = Find-AutoHotkey
    if ($exe) {
        return $exe
    }

    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) {
        throw 'AutoHotkey v2 was not found, and winget is not available. Install AutoHotkey v2 manually.'
    }

    Write-Host 'AutoHotkey v2 was not found. Installing with winget...'
    $proc = Start-Process -FilePath $winget.Source -ArgumentList @(
        'install', '--id', 'AutoHotkey.AutoHotkey', '-e',
        '--accept-package-agreements', '--accept-source-agreements',
        '--disable-interactivity', '--silent'
    ) -NoNewWindow -PassThru

    if (-not $proc.WaitForExit(300000)) {
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        throw 'winget AutoHotkey install timed out after 5 minutes.'
    }
    if ($proc.ExitCode -ne 0) {
        throw ('winget AutoHotkey install failed with exit code {0}.' -f $proc.ExitCode)
    }

    $exe = Find-AutoHotkey
    if (-not $exe) {
        throw 'AutoHotkey install completed, but no AutoHotkey v2 executable was found.'
    }

    return $exe
}

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

try {
    $remapRoot = Join-Path $env:LOCALAPPDATA 'DesktopAIKeyRemap'
    $scriptPath = Join-Path $remapRoot 'ChatEnterNewline.ahk'
    $taskName = 'Desktop AI Enter Newline Remap'

    Write-Host 'Checking prerequisites...'
    $ahkExe = Ensure-AutoHotkey
    Write-Host ('  AutoHotkey -> {0}' -f $ahkExe)

    if (-not (Test-Path -LiteralPath $remapRoot)) {
        New-Item -ItemType Directory -Path $remapRoot -Force | Out-Null
    }
    Set-Content -LiteralPath $scriptPath -Value $ahkContent -Encoding UTF8
    Write-Host ('  Script -> {0}' -f $scriptPath)

    Get-Process -Name AutoHotkey*, AutoHotkey64* -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and $_.CommandLine -like '*ChatEnterNewline*' } |
        Stop-Process -Force -ErrorAction SilentlyContinue

    foreach ($oldTaskName in @('Codex Enter Newline Remap')) {
        $oldTask = Get-ScheduledTask -TaskName $oldTaskName -ErrorAction SilentlyContinue
        if ($oldTask) {
            Unregister-ScheduledTask -TaskName $oldTaskName -Confirm:$false
        }
    }

    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $action = New-ScheduledTaskAction -Execute $ahkExe -Argument ('"{0}"' -f $scriptPath)
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $currentUser
    $principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null

    Start-Process -FilePath $ahkExe -ArgumentList ('"{0}"' -f $scriptPath)

    Write-Host ''
    Write-Host 'Chat hotkey install complete.'
    Write-Host '  Enter -> newline'
    Write-Host '  Ctrl+Enter -> send'
    Write-Host ('  Task -> {0}' -f $taskName)
}
catch {
    Write-Host ''
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
