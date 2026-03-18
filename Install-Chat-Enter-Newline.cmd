@echo off
setlocal
set "SELF=%~f0"
set "TMPPS=%TEMP%\Install-Chat-Enter-Newline-%RANDOM%%RANDOM%.ps1"

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$content = Get-Content -LiteralPath $env:SELF -Raw; $marker = ':__POWERSHELL_PAYLOAD__'; $index = $content.LastIndexOf($marker); if ($index -lt 0) { throw 'Marker not found.' }; $script = $content.Substring($index + $marker.Length).TrimStart([char]13, [char]10); $utf8NoBom = New-Object System.Text.UTF8Encoding($false); [System.IO.File]::WriteAllText($env:TMPPS, $script, $utf8NoBom)"
if errorlevel 1 goto :prepare_fail

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$isAdmin = (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator); exit ([int](-not $isAdmin))"
if errorlevel 1 goto :elevate

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%TMPPS%"
set "EXIT_CODE=%ERRORLEVEL%"
goto :cleanup

:elevate
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$argList = '-NoProfile -ExecutionPolicy Bypass -File ""' + $env:TMPPS + '""'; $process = Start-Process -FilePath powershell.exe -Verb RunAs -ArgumentList $argList -Wait -PassThru; exit $process.ExitCode"
set "EXIT_CODE=%ERRORLEVEL%"

:cleanup
del /q "%TMPPS%" >nul 2>nul

if not "%EXIT_CODE%"=="0" (
    echo.
    echo Install failed with exit code %EXIT_CODE%.
    pause
)

exit /b %EXIT_CODE%

:prepare_fail
echo Failed to prepare the installer.
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

function Get-AutoHotkeyExe {
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

    $command = Get-Command AutoHotkey64.exe, AutoHotkey.exe, AutoHotkey -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if ($command) {
        return $command.Source
    }

    return $null
}

function Ensure-AutoHotkey {
    $exePath = Get-AutoHotkeyExe
    if ($exePath) {
        return $exePath
    }

    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) {
        throw 'winget.exe was not found, so AutoHotkey cannot be installed automatically.'
    }

    Write-Host 'Installing AutoHotkey...'
    & $winget.Source install --id AutoHotkey.AutoHotkey -e --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        throw "AutoHotkey installation failed with exit code $LASTEXITCODE."
    }

    $exePath = Get-AutoHotkeyExe
    if (-not $exePath) {
        throw 'AutoHotkey was installed, but the executable was not found afterward.'
    }

    return $exePath
}

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
                $path -and $path.Length -gt 0 -and $proc.CommandLine.Contains($path)
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

$remapRoot = Join-Path $env:LOCALAPPDATA 'DesktopAIKeyRemap'
$scriptPath = Join-Path $remapRoot 'ChatEnterNewline.ahk'
$legacyScriptPath = Join-Path $env:LOCALAPPDATA 'CodexKeyRemap\CodexEnterNewline.ahk'
$legacyClaudeScriptPath = Join-Path $env:USERPROFILE 'Desktop\ClaudeEnterSwap.ahk'

Ensure-Directory -Path $remapRoot
$autoHotkeyExe = Ensure-AutoHotkey
Write-RemapScript -Path $scriptPath
Stop-ExistingRemapProcess -ScriptPaths @($scriptPath, $legacyScriptPath, $legacyClaudeScriptPath)
Remove-LegacyTask -TaskNames @('Codex Enter Newline Remap')
$taskName = Register-RemapTask -ExecutablePath $autoHotkeyExe -ScriptPath $scriptPath
Start-RemapProcess -ExecutablePath $autoHotkeyExe -ScriptPath $scriptPath
Start-Sleep -Seconds 2

$process = Get-CimInstance Win32_Process |
    Where-Object { $_.Name -match '^AutoHotkey' -and $_.CommandLine -and $_.CommandLine.Contains($scriptPath) } |
    Select-Object -First 1

if (-not $process) {
    throw 'The remap process did not start successfully.'
}

Write-Host 'Ready: Enter -> newline, Ctrl+Enter -> send in Codex and Claude.'
Write-Host ("Task: {0}" -f $taskName)
Write-Host ("Script: {0}" -f $scriptPath)
