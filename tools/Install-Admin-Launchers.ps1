# Install-Admin-Launchers.ps1 - create Codex and Claude admin launchers
# Creates scheduled tasks with highest privileges plus desktop shortcuts.
# Requires administrator rights and requests UAC elevation when needed.

param(
    [string]$RepoRoot
)

$ErrorActionPreference = 'Stop'

if (-not $RepoRoot) {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
}

# ---------- Elevation ----------

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

# ---------- Logging ----------

function Get-LauncherLogDirectory {
    $localAppData = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { Join-Path $env:USERPROFILE 'AppData\Local' }
    $dir = Join-Path $localAppData 'AdminAppLaunchers\logs'
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    return $dir
}

$script:InstallLogPath = Join-Path (Get-LauncherLogDirectory) ('install-{0:yyyyMMdd-HHmmss-fff}.log' -f (Get-Date))

function Write-InstallLog {
    param([Parameter(Mandatory)][string]$Message)

    $line = '{0:o} {1}' -f (Get-Date), $Message
    Add-Content -LiteralPath $script:InstallLogPath -Value $line -Encoding UTF8
}

Write-InstallLog ('Install script started. User={0}; IsAdmin={1}; RepoRoot={2}; PID={3}' -f [Security.Principal.WindowsIdentity]::GetCurrent().Name, (Test-IsAdmin), $RepoRoot, $PID)

# ---------- App executable discovery ----------

function Get-StartMenuShortcutPaths {
    param([Parameter(Mandatory)][string[]]$Names)

    $roots = @()

    if ($env:APPDATA) {
        $userPrograms = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
        if (Test-Path -LiteralPath $userPrograms) { $roots += $userPrograms }
    }

    if ($env:ProgramData) {
        $commonPrograms = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'
        if (Test-Path -LiteralPath $commonPrograms) { $roots += $commonPrograms }
    }

    foreach ($root in $roots) {
        foreach ($name in $Names) {
            Get-ChildItem -LiteralPath $root -Filter $name -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
                $_.FullName
            }
        }
    }
}

function Resolve-ShortcutExe {
    param([Parameter(Mandatory)][string]$ShortcutPath)

    try {
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($ShortcutPath)
        $target = [Environment]::ExpandEnvironmentVariables([string]$shortcut.TargetPath)
        $arguments = [string]$shortcut.Arguments

        if ([string]::IsNullOrWhiteSpace($target)) {
            Write-InstallLog ('Start menu shortcut skipped: Shortcut={0}; Reason=empty target' -f $ShortcutPath)
            return $null
        }

        $targetName = Split-Path -Leaf $target
        if ($target -like 'shell:*' -or $target -like '*AppsFolder*' -or $targetName -ieq 'explorer.exe') {
            Write-InstallLog ('Start menu broker shortcut skipped: Shortcut={0}; Target={1}; Arguments={2}' -f $ShortcutPath, $target, $arguments)
            return $null
        }

        if ([IO.Path]::GetExtension($target) -ieq '.exe' -and (Test-Path -LiteralPath $target)) {
            Write-InstallLog ('Start menu executable shortcut found: Shortcut={0}; Target={1}' -f $ShortcutPath, $target)
            return $target
        }

        Write-InstallLog ('Start menu shortcut skipped: Shortcut={0}; Target={1}; Arguments={2}; Reason=target is not an existing exe' -f $ShortcutPath, $target, $arguments)
        return $null
    }
    catch {
        Write-InstallLog ('Start menu shortcut resolve failed: Shortcut={0}; Error={1}' -f $ShortcutPath, $_.Exception.Message)
        return $null
    }
}

function Find-AppExe {
    param(
        [Parameter(Mandatory)][string]$AppName,
        [Parameter(Mandatory)][string[]]$PackagePatterns,
        [Parameter(Mandatory)][string[]]$ExeNames,
        [Parameter(Mandatory)][string[]]$StartMenuNames
    )

    foreach ($shortcut in Get-StartMenuShortcutPaths -Names $StartMenuNames) {
        $shortcutExe = Resolve-ShortcutExe -ShortcutPath $shortcut
        if ($shortcutExe) { return $shortcutExe }
    }

    foreach ($pattern in $PackagePatterns) {
        $pkg = Get-AppxPackage $pattern -ErrorAction SilentlyContinue | Sort-Object Version -Descending | Select-Object -First 1
        if ($pkg) {
            foreach ($exe in $ExeNames) {
                $path = Join-Path $pkg.InstallLocation "app\$exe"
                if (Test-Path -LiteralPath $path) { return $path }
            }
        }
    }

    $candidatePaths = @()
    if ($env:LOCALAPPDATA) {
        foreach ($exe in $ExeNames) {
            $candidatePaths += Join-Path $env:LOCALAPPDATA "Programs\$AppName\$exe"
            $candidatePaths += Join-Path $env:LOCALAPPDATA "$AppName\$exe"
        }
    }
    if ($env:ProgramFiles) {
        foreach ($exe in $ExeNames) {
            $candidatePaths += Join-Path $env:ProgramFiles "$AppName\$exe"
        }
    }
    if (${env:ProgramFiles(x86)}) {
        foreach ($exe in $ExeNames) {
            $candidatePaths += Join-Path ${env:ProgramFiles(x86)} "$AppName\$exe"
        }
    }

    foreach ($path in $candidatePaths) {
        if (Test-Path -LiteralPath $path) { return $path }
    }

    return $null
}

# ---------- Generate launcher script used by scheduled tasks ----------

function Write-LauncherScript {
    param([Parameter(Mandatory)][string]$Path)

    # This script is called by the scheduled tasks. It verifies the admin token,
    # cleans up old instances, finds the target app, and starts it.
    $content = @'
param(
    [Parameter(Mandatory)]
    [ValidateSet('codex', 'claude')]
    [string]$AppId
)

$ErrorActionPreference = 'Stop'

$apps = @{
    codex = @{
        AppName = 'Codex'
        Packages = @('OpenAI.Codex')
        Exes = @('Codex.exe')
        StartMenuNames = @('Codex.lnk', 'OpenAI Codex.lnk')
        ProcessNames = @('Codex', 'codex')
        CommandLineMarkers = @('OpenAI.Codex', '\Codex\', 'Codex.exe')
    }
    claude = @{
        AppName = 'Claude'
        Packages = @('Claude')
        Exes = @('Claude.exe', 'claude.exe')
        StartMenuNames = @('Claude.lnk', 'Claude Desktop.lnk')
        ProcessNames = @('Claude', 'claude')
        CommandLineMarkers = @('\Claude\', 'Claude.exe', 'claude.exe')
    }
}

function Get-LauncherLogDirectory {
    $localAppData = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { Join-Path $env:USERPROFILE 'AppData\Local' }
    $dir = Join-Path $localAppData 'AdminAppLaunchers\logs'
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    return $dir
}

$script:LogFile = Join-Path (Get-LauncherLogDirectory) ('{0}-{1:yyyyMMdd-HHmmss-fff}.log' -f $AppId, (Get-Date))

function Write-Log {
    param([Parameter(Mandatory)][string]$Message)

    $line = '{0:o} {1}' -f (Get-Date), $Message
    Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8
}

function Test-IsAdmin {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-StartMenuShortcutPaths {
    param([Parameter(Mandatory)][string[]]$Names)

    $roots = @()

    if ($env:APPDATA) {
        $userPrograms = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
        if (Test-Path -LiteralPath $userPrograms) { $roots += $userPrograms }
    }

    if ($env:ProgramData) {
        $commonPrograms = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'
        if (Test-Path -LiteralPath $commonPrograms) { $roots += $commonPrograms }
    }

    foreach ($root in $roots) {
        foreach ($name in $Names) {
            Get-ChildItem -LiteralPath $root -Filter $name -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
                $_.FullName
            }
        }
    }
}

function Resolve-StartMenuShortcut {
    param([Parameter(Mandatory)][string]$ShortcutPath)

    try {
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($ShortcutPath)
        $target = [Environment]::ExpandEnvironmentVariables([string]$shortcut.TargetPath)
        $arguments = [string]$shortcut.Arguments

        if ([string]::IsNullOrWhiteSpace($target)) {
            Write-Log ('Start menu shortcut skipped: Shortcut={0}; Reason=empty target' -f $ShortcutPath)
            return $null
        }

        $targetName = Split-Path -Leaf $target
        if ($target -like 'shell:*' -or $target -like '*AppsFolder*' -or $targetName -ieq 'explorer.exe') {
            Write-Log ('Start menu broker shortcut skipped: Shortcut={0}; Target={1}; Arguments={2}; Reason=broker activation is not assumed to preserve elevation' -f $ShortcutPath, $target, $arguments)
            return $null
        }

        if ([IO.Path]::GetExtension($target) -ieq '.exe' -and (Test-Path -LiteralPath $target)) {
            return [pscustomobject]@{
                Path = $target
                Mode = 'StartMenuShortcutExe'
                Detail = ('Shortcut={0}' -f $ShortcutPath)
            }
        }

        Write-Log ('Start menu shortcut skipped: Shortcut={0}; Target={1}; Arguments={2}; Reason=target is not an existing exe' -f $ShortcutPath, $target, $arguments)
        return $null
    }
    catch {
        Write-Log ('Start menu shortcut resolve failed: Shortcut={0}; Error={1}' -f $ShortcutPath, $_.Exception.Message)
        return $null
    }
}

function New-LaunchCandidate {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Mode,
        [string]$Detail = ''
    )

    [pscustomobject]@{
        Path = $Path
        Mode = $Mode
        Detail = $Detail
    }
}

function Get-LaunchCandidates {
    param([Parameter(Mandatory)][string]$AppId)

    $app = $apps[$AppId]

    foreach ($shortcut in Get-StartMenuShortcutPaths -Names $app.StartMenuNames) {
        $candidate = Resolve-StartMenuShortcut -ShortcutPath $shortcut
        if ($candidate) { $candidate }
    }

    foreach ($pattern in $app.Packages) {
        $pkg = Get-AppxPackage $pattern -ErrorAction SilentlyContinue | Sort-Object Version -Descending | Select-Object -First 1
        if ($pkg) {
            foreach ($exe in $app.Exes) {
                $path = Join-Path $pkg.InstallLocation "app\$exe"
                New-LaunchCandidate -Path $path -Mode 'AppxPackageExe' -Detail ('Package={0}; InstallLocation={1}' -f $pkg.Name, $pkg.InstallLocation)
            }
        }
    }

    $appName = $app.AppName

    if ($env:LOCALAPPDATA) {
        foreach ($exe in $app.Exes) {
            New-LaunchCandidate -Path (Join-Path $env:LOCALAPPDATA "Programs\$appName\$exe") -Mode 'LocalAppDataProgramsExe'
            New-LaunchCandidate -Path (Join-Path $env:LOCALAPPDATA "$appName\$exe") -Mode 'LocalAppDataExe'
        }
    }

    if ($env:ProgramFiles) {
        foreach ($exe in $app.Exes) {
            New-LaunchCandidate -Path (Join-Path $env:ProgramFiles "$appName\$exe") -Mode 'ProgramFilesExe'
        }
    }

    if (${env:ProgramFiles(x86)}) {
        foreach ($exe in $app.Exes) {
            New-LaunchCandidate -Path (Join-Path ${env:ProgramFiles(x86)} "$appName\$exe") -Mode 'ProgramFilesX86Exe'
        }
    }
}

function Get-PreferredLaunchCandidate {
    param([Parameter(Mandatory)][string]$AppId)

    foreach ($candidate in Get-LaunchCandidates -AppId $AppId) {
        Write-Log ('Launch candidate checked: Mode={0}; Path={1}; Detail={2}' -f $candidate.Mode, $candidate.Path, $candidate.Detail)
        if (Test-Path -LiteralPath $candidate.Path) {
            Write-Log ('Launch candidate selected: Mode={0}; Path={1}; Detail={2}' -f $candidate.Mode, $candidate.Path, $candidate.Detail)
            return $candidate
        }
    }

    return $null
}

function Test-IsProtectedProcessName {
    param([string]$Name)

    $protected = @(
        'Idle', 'System', 'Registry',
        'smss.exe', 'csrss.exe', 'wininit.exe', 'winlogon.exe',
        'services.exe', 'lsass.exe', 'svchost.exe',
        'explorer.exe', 'schtasks.exe', 'powershell.exe', 'pwsh.exe',
        'conhost.exe'
    )

    return $protected -contains $Name
}

function Add-ProcessMatch {
    param(
        [Parameter(Mandatory)][hashtable]$Matches,
        [Parameter(Mandatory)][int]$Id,
        [string]$Name,
        [string]$Source,
        [string]$CommandLine
    )

    if ($Id -eq $PID -or $Matches.ContainsKey($Id)) { return }

    $Matches[$Id] = [pscustomobject]@{
        Id = $Id
        Name = $Name
        Source = $Source
        CommandLine = $CommandLine
    }
}

function Get-MatchingAppProcesses {
    param([Parameter(Mandatory)][string]$AppId)

    $app = $apps[$AppId]
    $matches = @{}

    foreach ($proc in Get-Process -Name $app.ProcessNames -ErrorAction SilentlyContinue) {
        Add-ProcessMatch -Matches $matches -Id $proc.Id -Name $proc.ProcessName -Source 'ProcessName' -CommandLine $null
    }

    try {
        foreach ($proc in Get-CimInstance Win32_Process -ErrorAction SilentlyContinue) {
            if ($proc.ProcessId -eq $PID -or (Test-IsProtectedProcessName -Name $proc.Name)) { continue }

            $haystack = (@($proc.CommandLine, $proc.ExecutablePath, $proc.Name) | Where-Object { $_ }) -join ' '
            if ([string]::IsNullOrWhiteSpace($haystack)) { continue }

            foreach ($marker in $app.CommandLineMarkers) {
                if ($haystack.IndexOf($marker, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                    Add-ProcessMatch -Matches $matches -Id ([int]$proc.ProcessId) -Name $proc.Name -Source ('CommandLineMarker={0}' -f $marker) -CommandLine $proc.CommandLine
                    break
                }
            }
        }
    }
    catch {
        Write-Log ('Command line process scan failed: {0}' -f $_.Exception.Message)
    }

    return $matches.Values
}

function Stop-AppProcesses {
    param([Parameter(Mandatory)][string]$AppId)

    $matches = @(Get-MatchingAppProcesses -AppId $AppId)
    if (-not $matches -or $matches.Count -eq 0) {
        Write-Log ('Old process cleanup: AppId={0}; Matches=0' -f $AppId)
        return
    }

    foreach ($proc in $matches) {
        Write-Log ('Stopping old process: PID={0}; Name={1}; Source={2}; CommandLine={3}' -f $proc.Id, $proc.Name, $proc.Source, $proc.CommandLine)
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    }

    Start-Sleep -Milliseconds 800
}

try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $isAdmin = Test-IsAdmin
    Write-Log ('Launcher started. User={0}; IsAdmin={1}; AppId={2}; PID={3}' -f $identity.Name, $isAdmin, $AppId, $PID)

    if (-not $isAdmin) {
        throw 'Launch-PackagedApp.ps1 is not running with an administrator token.'
    }

    $candidate = Get-PreferredLaunchCandidate -AppId $AppId
    if (-not $candidate) {
        throw ('Cannot find executable for {0}.' -f $AppId)
    }

    Stop-AppProcesses -AppId $AppId

    Write-Log ('Starting app: AppId={0}; Mode={1}; Path={2}; Detail={3}' -f $AppId, $candidate.Mode, $candidate.Path, $candidate.Detail)
    Start-Process -FilePath $candidate.Path
    Write-Log ('Start-Process returned. AppId={0}; Mode={1}; Path={2}' -f $AppId, $candidate.Mode, $candidate.Path)
}
catch {
    Write-Log ('ERROR: {0}' -f $_.Exception.ToString())
    throw
}
'@

    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Set-Content -LiteralPath $Path -Value $content -Encoding UTF8
    Write-InstallLog ('Launcher script written: {0}' -f $Path)
}

# ---------- Register one app launcher ----------

function Register-Launcher {
    param(
        [Parameter(Mandatory)][string]$AppId,
        [Parameter(Mandatory)][string]$DisplayName,
        [Parameter(Mandatory)][string]$TaskName,
        [Parameter(Mandatory)][string]$ShortcutName,
        [Parameter(Mandatory)][string]$ExePath,
        [Parameter(Mandatory)][string]$LauncherScript
    )

    $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $taskArgs = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -AppId "{1}"' -f $LauncherScript, $AppId
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name

    try {
        $action = New-ScheduledTaskAction -Execute $psExe -Argument $taskArgs
        $principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew
        Register-ScheduledTask -TaskName $TaskName -Action $action -Principal $principal -Settings $settings -Force | Out-Null

        $registeredTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
        Write-InstallLog ('Scheduled task registered: TaskName={0}; User={1}; RunLevel=Highest; LogonType=Interactive; State={2}; Action={3} {4}' -f $TaskName, $currentUser, $registeredTask.State, $psExe, $taskArgs)
    }
    catch {
        Write-InstallLog ('Scheduled task registration failed: TaskName={0}; Error={1}' -f $TaskName, $_.Exception.ToString())
        throw
    }

    $desktopDir = [Environment]::GetFolderPath('DesktopDirectory')
    if (-not $desktopDir) { $desktopDir = Join-Path $env:USERPROFILE 'Desktop' }
    $lnkPath = Join-Path $desktopDir $ShortcutName

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($lnkPath)
    $shortcut.TargetPath = Join-Path $env:SystemRoot 'System32\schtasks.exe'
    $shortcut.Arguments = '/run /tn "{0}"' -f $TaskName
    $shortcut.WorkingDirectory = $env:USERPROFILE
    $shortcut.Description = "Start $DisplayName as administrator"
    $shortcut.IconLocation = "$ExePath,0"
    $shortcut.Save()

    Write-InstallLog ('Desktop shortcut written: AppId={0}; Path={1}; Target=schtasks.exe; Arguments={2}; Icon={3}' -f $AppId, $lnkPath, $shortcut.Arguments, $shortcut.IconLocation)
    Write-Host ("  [OK] {0}: Task={1}, Shortcut={2}" -f $DisplayName, $TaskName, $ShortcutName)
}

# ---------- Main ----------

try {
    Write-Host 'Checking apps...'
    Write-Host ("  Install log -> {0}" -f $script:InstallLogPath)

    $codexExe = Find-AppExe -AppName 'Codex' -PackagePatterns @('OpenAI.Codex') -ExeNames @('Codex.exe') -StartMenuNames @('Codex.lnk', 'OpenAI Codex.lnk')
    $claudeExe = Find-AppExe -AppName 'Claude' -PackagePatterns @('Claude') -ExeNames @('Claude.exe', 'claude.exe') -StartMenuNames @('Claude.lnk', 'Claude Desktop.lnk')

    if (-not $codexExe -and -not $claudeExe) {
        throw 'Codex or Claude was not detected. Install the app and launch it at least once first.'
    }

    $launcherScript = Join-Path $env:LOCALAPPDATA 'AdminAppLaunchers\Launch-PackagedApp.ps1'
    Write-LauncherScript -Path $launcherScript

    if ($codexExe) {
        Write-Host ("  Codex -> {0}" -f $codexExe)
        Write-InstallLog ('Codex detected: {0}' -f $codexExe)
        Register-Launcher -AppId 'codex' -DisplayName 'Codex' -TaskName 'Codex Admin Launcher' -ShortcutName 'Codex.lnk' -ExePath $codexExe -LauncherScript $launcherScript
    }

    if ($claudeExe) {
        Write-Host ("  Claude -> {0}" -f $claudeExe)
        Write-InstallLog ('Claude detected: {0}' -f $claudeExe)
        Register-Launcher -AppId 'claude' -DisplayName 'Claude' -TaskName 'Claude Admin Launcher' -ShortcutName 'Claude Desktop.lnk' -ExePath $claudeExe -LauncherScript $launcherScript
    }

    Write-Host ''
    Write-Host 'Admin launchers created.'
    Write-InstallLog 'Install script completed.'
}
catch {
    Write-InstallLog ('Install script failed: {0}' -f $_.Exception.ToString())
    Write-Host ''
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
