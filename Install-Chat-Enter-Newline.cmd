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

function Fail-Install {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Write-Host ''
    Write-Host '聊天热键安装失败。' -ForegroundColor Red
    Write-Host ("  {0}" -f $Message) -ForegroundColor Red
    exit 1
}

function Get-DesktopDirectory {
    $desktopPath = [Environment]::GetFolderPath([Environment+SpecialFolder]::DesktopDirectory)
    if ([string]::IsNullOrWhiteSpace($desktopPath)) {
        return (Join-Path $env:USERPROFILE 'Desktop')
    }

    return $desktopPath
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
        throw '未检测到 AutoHotkey v2，且系统中也没有 winget。请先手动安装 AutoHotkey v2，再重新运行本脚本。'
    }

    Write-Host '未检测到 AutoHotkey v2，开始尝试通过 winget 自动安装...'
    $arguments = @(
        'install',
        '--id', 'AutoHotkey.AutoHotkey',
        '-e',
        '--accept-package-agreements',
        '--accept-source-agreements',
        '--disable-interactivity',
        '--silent'
    )
    $process = Start-Process -FilePath $winget.Source -ArgumentList $arguments -NoNewWindow -PassThru
    if (-not $process.WaitForExit(300000)) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        throw '通过 winget 自动安装 AutoHotkey v2 超时（5 分钟）。请先手动安装 AutoHotkey v2，再重新运行本脚本。'
    }

    if ($process.ExitCode -ne 0) {
        throw ("通过 winget 安装 AutoHotkey v2 失败，退出码 {0}。请先手动安装 AutoHotkey v2，再重新运行本脚本。" -f $process.ExitCode)
    }

    $exePath = Get-AutoHotkeyExe
    if (-not $exePath) {
        throw 'AutoHotkey v2 安装完成后仍未检测到可执行文件。请先手动确认安装成功，再重新运行本脚本。'
    }

    return $exePath
}

function Resolve-SupportedApps {
    $apps = @(
        [pscustomobject]@{
            DisplayName = 'Codex'
            PackageName = 'OpenAI.Codex'
            RelativePaths = @('app\Codex.exe')
            ExtraPaths = @(
                (Join-Path $env:LOCALAPPDATA 'Programs\Codex\Codex.exe'),
                $(if ($env:ProgramFiles) { Join-Path $env:ProgramFiles 'Codex\Codex.exe' }),
                $(if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} 'Codex\Codex.exe' })
            )
        },
        [pscustomobject]@{
            DisplayName = 'Claude'
            PackageName = 'Claude'
            RelativePaths = @('app\Claude.exe', 'app\claude.exe')
            ExtraPaths = @(
                (Join-Path $env:LOCALAPPDATA 'Programs\Claude\Claude.exe'),
                (Join-Path $env:LOCALAPPDATA 'Programs\Claude\claude.exe'),
                $(if ($env:ProgramFiles) { Join-Path $env:ProgramFiles 'Claude\Claude.exe' }),
                $(if ($env:ProgramFiles) { Join-Path $env:ProgramFiles 'Claude\claude.exe' }),
                $(if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} 'Claude\Claude.exe' }),
                $(if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} 'Claude\claude.exe' })
            )
        }
    )

    $resolved = @()
    foreach ($app in $apps) {
        $candidates = New-Object 'System.Collections.Generic.List[string]'
        $seen = @{}

        foreach ($pkg in @(Get-AppxPackage $app.PackageName -ErrorAction SilentlyContinue | Sort-Object Version -Descending)) {
            foreach ($relativePath in $app.RelativePaths) {
                Add-UniquePath -Seen $seen -Paths $candidates -Path (Join-Path $pkg.InstallLocation $relativePath) -RequireExists
            }
        }

        foreach ($extraPath in $app.ExtraPaths) {
            Add-UniquePath -Seen $seen -Paths $candidates -Path $extraPath -RequireExists
        }

        $exePath = $candidates | Select-Object -First 1
        if ($exePath) {
            $resolved += [pscustomobject]@{
                DisplayName = $app.DisplayName
                Path = $exePath
            }
        }
    }

    return $resolved
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

try {
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
    Stop-ExistingRemapProcess -ScriptPaths @($scriptPath, $legacyScriptPath, $legacyClaudeScriptPath)
    Remove-LegacyTask -TaskNames @('Codex Enter Newline Remap')
    $taskName = Register-RemapTask -ExecutablePath $autoHotkeyExe -ScriptPath $scriptPath
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
}
catch {
    Fail-Install -Message $_.Exception.Message
}
