@echo off
setlocal
set "SELF=%~f0"
set "TMPPS=%TEMP%\Install-Admin-Launchers-%RANDOM%%RANDOM%.ps1"

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$content = Get-Content -LiteralPath $env:SELF -Raw; $marker = ':__POWERSHELL__'; $index = $content.LastIndexOf($marker); if ($index -lt 0) { throw 'Marker not found.' }; $script = $content.Substring($index + $marker.Length).TrimStart([char]13, [char]10); $utf8NoBom = New-Object System.Text.UTF8Encoding($false); [System.IO.File]::WriteAllText($env:TMPPS, $script, $utf8NoBom)"
if errorlevel 1 goto :prepare_fail

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$isAdmin = (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator); if ($isAdmin) { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $env:TMPPS; exit $LASTEXITCODE } else { $argList = '-NoProfile -ExecutionPolicy Bypass -File ""' + $env:TMPPS + '""'; $process = Start-Process -FilePath powershell.exe -Verb RunAs -ArgumentList $argList -Wait -PassThru; exit $process.ExitCode }"
set "EXIT_CODE=%ERRORLEVEL%"
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

:__POWERSHELL__
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

function New-LauncherScript {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $content = @'
param(
    [Parameter(Mandatory = $true)]
    [string]$PackageName,

    [Parameter(Mandatory = $true)]
    [string]$ExeRelativePath
)

$ErrorActionPreference = 'Stop'

$pkg = Get-AppxPackage $PackageName |
    Sort-Object Version -Descending |
    Select-Object -First 1

if (-not $pkg) {
    throw "Package not found: $PackageName"
}

$exePath = Join-Path $pkg.InstallLocation $ExeRelativePath
if (-not (Test-Path -LiteralPath $exePath)) {
    throw "Executable not found: $exePath"
}

Start-Process -FilePath $exePath
'@

    Set-Content -LiteralPath $Path -Value $content -Encoding UTF8
}

function Register-AppLauncher {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$App,

        [Parameter(Mandatory = $true)]
        [string]$LauncherScriptPath
    )

    $pkg = Get-AppxPackage $App.PackageName |
        Sort-Object Version -Descending |
        Select-Object -First 1

    if (-not $pkg) {
        Write-Warning ("Skip {0}: package not installed." -f $App.PackageName)
        return $false
    }

    $iconPath = Join-Path $pkg.InstallLocation $App.ExeRelativePath
    $powershellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $taskArgs = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -PackageName "{1}" -ExeRelativePath "{2}"' -f $LauncherScriptPath, $App.PackageName, $App.ExeRelativePath
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name

    $action = New-ScheduledTaskAction -Execute $powershellExe -Argument $taskArgs
    $principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew

    Register-ScheduledTask -TaskName $App.TaskName -Action $action -Principal $principal -Settings $settings -Force | Out-Null

    $shortcutPath = Join-Path $env:USERPROFILE ("Desktop\{0}" -f $App.ShortcutName)
    $shortcutShell = New-Object -ComObject WScript.Shell
    $shortcut = $shortcutShell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = Join-Path $env:SystemRoot 'System32\schtasks.exe'
    $shortcut.Arguments = '/run /tn "{0}"' -f $App.TaskName
    $shortcut.WorkingDirectory = $env:USERPROFILE
    $shortcut.Description = $App.Description

    if (Test-Path -LiteralPath $iconPath) {
        $shortcut.IconLocation = '{0},0' -f $iconPath
    }

    $shortcut.Save()

    Write-Host ("Ready: {0} -> {1}" -f $App.ShortcutName, $App.TaskName)
    return $true
}

$launcherRoot = Join-Path $env:LOCALAPPDATA 'AdminAppLaunchers'
$launcherScriptPath = Join-Path $launcherRoot 'Launch-PackagedApp.ps1'

Ensure-Directory -Path $launcherRoot
New-LauncherScript -Path $launcherScriptPath

$apps = @(
    [pscustomobject]@{
        PackageName = 'OpenAI.Codex'
        ExeRelativePath = 'app\Codex.exe'
        TaskName = 'Codex Admin Launcher'
        ShortcutName = 'Codex.lnk'
        Description = 'Start Codex with highest privileges'
    },
    [pscustomobject]@{
        PackageName = 'Claude'
        ExeRelativePath = 'app\Claude.exe'
        TaskName = 'Claude Admin Launcher'
        ShortcutName = 'Claude Desktop.lnk'
        Description = 'Start Claude with highest privileges'
    }
)

$results = foreach ($app in $apps) {
    Register-AppLauncher -App $app -LauncherScriptPath $launcherScriptPath
}

$successCount = @($results | Where-Object { $_ }).Count
Write-Host ("Completed. Shortcuts updated: {0}/{1}" -f $successCount, $apps.Count)

if ($successCount -ne $apps.Count) {
    exit 1
}
