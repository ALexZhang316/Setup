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
    echo 安装失败，退出码 %EXIT_CODE%。
    pause
)

exit /b %EXIT_CODE%

:prepare_fail
echo 安装脚本准备失败。
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

function Fail-Install {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Write-Host ''
    Write-Host '管理员启动器安装失败。' -ForegroundColor Red
    Write-Host ("  {0}" -f $Message) -ForegroundColor Red
    exit 1
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

function Get-DesktopDirectory {
    $desktopPath = [Environment]::GetFolderPath([Environment+SpecialFolder]::DesktopDirectory)
    if ([string]::IsNullOrWhiteSpace($desktopPath)) {
        return (Join-Path $env:USERPROFILE 'Desktop')
    }

    return $desktopPath
}

function Resolve-AppExecutablePath {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$App
    )

    $packageNames = @()
    $exeRelativePaths = @()
    $installPathCandidates = New-Object 'System.Collections.Generic.List[string]'

    switch ($App.Id) {
        'codex' {
            $packageNames = @('OpenAI.Codex')
            $exeRelativePaths = @('app\Codex.exe')
            Add-UniquePath -Seen @{} -Paths $installPathCandidates -Path (Join-Path $env:LOCALAPPDATA 'Programs\Codex\Codex.exe')
            if ($env:ProgramFiles) {
                Add-UniquePath -Seen @{} -Paths $installPathCandidates -Path (Join-Path $env:ProgramFiles 'Codex\Codex.exe')
            }
            if (${env:ProgramFiles(x86)}) {
                Add-UniquePath -Seen @{} -Paths $installPathCandidates -Path (Join-Path ${env:ProgramFiles(x86)} 'Codex\Codex.exe')
            }
        }
        'claude' {
            $packageNames = @('Claude')
            $exeRelativePaths = @('app\Claude.exe', 'app\claude.exe')
            Add-UniquePath -Seen @{} -Paths $installPathCandidates -Path (Join-Path $env:LOCALAPPDATA 'Programs\Claude\Claude.exe')
            Add-UniquePath -Seen @{} -Paths $installPathCandidates -Path (Join-Path $env:LOCALAPPDATA 'Programs\Claude\claude.exe')
            if ($env:ProgramFiles) {
                Add-UniquePath -Seen @{} -Paths $installPathCandidates -Path (Join-Path $env:ProgramFiles 'Claude\Claude.exe')
                Add-UniquePath -Seen @{} -Paths $installPathCandidates -Path (Join-Path $env:ProgramFiles 'Claude\claude.exe')
            }
            if (${env:ProgramFiles(x86)}) {
                Add-UniquePath -Seen @{} -Paths $installPathCandidates -Path (Join-Path ${env:ProgramFiles(x86)} 'Claude\Claude.exe')
                Add-UniquePath -Seen @{} -Paths $installPathCandidates -Path (Join-Path ${env:ProgramFiles(x86)} 'Claude\claude.exe')
            }
        }
        default {
            throw "Unknown app id: $($App.Id)"
        }
    }

    $candidates = New-Object 'System.Collections.Generic.List[string]'
    $seen = @{}

    foreach ($packageName in $packageNames) {
        foreach ($pkg in @(Get-AppxPackage $packageName -ErrorAction SilentlyContinue | Sort-Object Version -Descending)) {
            foreach ($relativePath in $exeRelativePaths) {
                Add-UniquePath -Seen $seen -Paths $candidates -Path (Join-Path $pkg.InstallLocation $relativePath) -RequireExists
            }
        }
    }

    foreach ($candidatePath in $installPathCandidates) {
        Add-UniquePath -Seen $seen -Paths $candidates -Path $candidatePath -RequireExists
    }

    return $candidates | Select-Object -First 1
}

function New-LauncherScript {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $content = @'
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('codex', 'claude')]
    [string]$AppId
)

$ErrorActionPreference = 'Stop'

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

function Resolve-AppExecutablePath {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('codex', 'claude')]
        [string]$AppId
    )

    $packageNames = @()
    $exeRelativePaths = @()
    $installPathCandidates = New-Object 'System.Collections.Generic.List[string]'

    switch ($AppId) {
        'codex' {
            $packageNames = @('OpenAI.Codex')
            $exeRelativePaths = @('app\Codex.exe')
            Add-UniquePath -Seen @{} -Paths $installPathCandidates -Path (Join-Path $env:LOCALAPPDATA 'Programs\Codex\Codex.exe')
            if ($env:ProgramFiles) {
                Add-UniquePath -Seen @{} -Paths $installPathCandidates -Path (Join-Path $env:ProgramFiles 'Codex\Codex.exe')
            }
            if (${env:ProgramFiles(x86)}) {
                Add-UniquePath -Seen @{} -Paths $installPathCandidates -Path (Join-Path ${env:ProgramFiles(x86)} 'Codex\Codex.exe')
            }
        }
        'claude' {
            $packageNames = @('Claude')
            $exeRelativePaths = @('app\Claude.exe', 'app\claude.exe')
            Add-UniquePath -Seen @{} -Paths $installPathCandidates -Path (Join-Path $env:LOCALAPPDATA 'Programs\Claude\Claude.exe')
            Add-UniquePath -Seen @{} -Paths $installPathCandidates -Path (Join-Path $env:LOCALAPPDATA 'Programs\Claude\claude.exe')
            if ($env:ProgramFiles) {
                Add-UniquePath -Seen @{} -Paths $installPathCandidates -Path (Join-Path $env:ProgramFiles 'Claude\Claude.exe')
                Add-UniquePath -Seen @{} -Paths $installPathCandidates -Path (Join-Path $env:ProgramFiles 'Claude\claude.exe')
            }
            if (${env:ProgramFiles(x86)}) {
                Add-UniquePath -Seen @{} -Paths $installPathCandidates -Path (Join-Path ${env:ProgramFiles(x86)} 'Claude\Claude.exe')
                Add-UniquePath -Seen @{} -Paths $installPathCandidates -Path (Join-Path ${env:ProgramFiles(x86)} 'Claude\claude.exe')
            }
        }
    }

    $candidates = New-Object 'System.Collections.Generic.List[string]'
    $seen = @{}

    foreach ($packageName in $packageNames) {
        foreach ($pkg in @(Get-AppxPackage $packageName -ErrorAction SilentlyContinue | Sort-Object Version -Descending)) {
            foreach ($relativePath in $exeRelativePaths) {
                Add-UniquePath -Seen $seen -Paths $candidates -Path (Join-Path $pkg.InstallLocation $relativePath) -RequireExists
            }
        }
    }

    foreach ($candidatePath in $installPathCandidates) {
        Add-UniquePath -Seen $seen -Paths $candidates -Path $candidatePath -RequireExists
    }

    return $candidates | Select-Object -First 1
}

$exePath = Resolve-AppExecutablePath -AppId $AppId
if (-not $exePath) {
    throw "Executable not found for app: $AppId"
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

    $exePath = Resolve-AppExecutablePath -App $App
    if (-not $exePath) {
        Write-Warning ("Skip {0}: executable not found in supported install locations." -f $App.DisplayName)
        return $false
    }

    $powershellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $taskArgs = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -AppId "{1}"' -f $LauncherScriptPath, $App.Id
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name

    $action = New-ScheduledTaskAction -Execute $powershellExe -Argument $taskArgs
    $principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew

    Register-ScheduledTask -TaskName $App.TaskName -Action $action -Principal $principal -Settings $settings -Force | Out-Null

    $shortcutPath = Join-Path (Get-DesktopDirectory) $App.ShortcutName
    $shortcutShell = New-Object -ComObject WScript.Shell
    $shortcut = $shortcutShell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = Join-Path $env:SystemRoot 'System32\schtasks.exe'
    $shortcut.Arguments = '/run /tn "{0}"' -f $App.TaskName
    $shortcut.WorkingDirectory = $env:USERPROFILE
    $shortcut.Description = $App.Description

    if (Test-Path -LiteralPath $exePath) {
        $shortcut.IconLocation = '{0},0' -f $exePath
    }

    $shortcut.Save()

    Write-Host ("Ready: {0} -> {1}" -f $App.ShortcutName, $App.TaskName)
    return $true
}

try {
    $launcherRoot = Join-Path $env:LOCALAPPDATA 'AdminAppLaunchers'
    $launcherScriptPath = Join-Path $launcherRoot 'Launch-PackagedApp.ps1'

    $apps = @(
        [pscustomobject]@{
            Id = 'codex'
            DisplayName = 'Codex'
            TaskName = 'Codex Admin Launcher'
            ShortcutName = 'Codex.lnk'
            Description = 'Start Codex with highest privileges'
        },
        [pscustomobject]@{
            Id = 'claude'
            DisplayName = 'Claude'
            TaskName = 'Claude Admin Launcher'
            ShortcutName = 'Claude Desktop.lnk'
            Description = 'Start Claude with highest privileges'
        }
    )

    Write-Host '开始检查前置条件...'
    $missingApps = @()
    foreach ($app in $apps) {
        $exePath = Resolve-AppExecutablePath -App $app
        if (-not $exePath) {
            $missingApps += $app.DisplayName
        } else {
            Write-Host ("  {0} -> {1}" -f $app.DisplayName, $exePath)
        }
    }

    if ($missingApps.Count -gt 0) {
        throw ("未检测到以下应用的可执行文件：{0}。请先安装这些应用，并至少启动一次后完全退出，再运行本脚本。" -f ($missingApps -join '、'))
    }

    Ensure-Directory -Path $launcherRoot
    New-LauncherScript -Path $launcherScriptPath

    $results = foreach ($app in $apps) {
        Register-AppLauncher -App $app -LauncherScriptPath $launcherScriptPath
    }

    $successCount = @($results | Where-Object { $_ }).Count
    Write-Host ("管理员启动器创建完成：{0}/{1}" -f $successCount, $apps.Count)

    if ($successCount -ne $apps.Count) {
        throw '部分管理员启动器未创建成功。请检查上面的输出后重试。'
    }
}
catch {
    Fail-Install -Message $_.Exception.Message
}
