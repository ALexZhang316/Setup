Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step {
    param([string]$Message)
    Write-Host "[Codex Setup] $Message" -ForegroundColor Cyan
}

function Backup-File {
    param(
        [string]$Path,
        [string]$BackupDir,
        [string]$BackupName
    )

    if (-not (Test-Path $Path)) {
        return
    }

    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    Copy-Item $Path (Join-Path $BackupDir $BackupName) -Force
}

function Get-CodexPackage {
    Get-AppxPackage OpenAI.Codex |
        Sort-Object Version -Descending |
        Select-Object -First 1
}

function Get-CodexExecutablePath {
    param([object]$Package)

    $candidates = @(
        (Join-Path $Package.InstallLocation 'app\Codex.exe'),
        (Join-Path $Package.InstallLocation 'app\resources\codex.exe')
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    return $null
}

function Write-LauncherScript {
    param([string]$LauncherPath)

    $launcherDir = Split-Path $LauncherPath -Parent
    New-Item -ItemType Directory -Path $launcherDir -Force | Out-Null

    $launcherContent = @'
Add-Type -AssemblyName PresentationFramework

$package = Get-AppxPackage OpenAI.Codex |
    Sort-Object Version -Descending |
    Select-Object -First 1

if (-not $package) {
    [System.Windows.MessageBox]::Show(
        'Codex is not installed.',
        'Codex Launcher',
        'OK',
        'Error'
    ) | Out-Null
    exit 1
}

$candidates = @(
    (Join-Path $package.InstallLocation 'app\Codex.exe'),
    (Join-Path $package.InstallLocation 'app\resources\codex.exe')
) | Where-Object { Test-Path $_ }

if (-not $candidates) {
    [System.Windows.MessageBox]::Show(
        'The Codex executable was not found.',
        'Codex Launcher',
        'OK',
        'Error'
    ) | Out-Null
    exit 1
}

Start-Process -FilePath $candidates[0]
'@

    [System.IO.File]::WriteAllText(
        $LauncherPath,
        $launcherContent,
        [System.Text.UTF8Encoding]::new($false)
    )
}

function Write-ShortcutIcon {
    param(
        [string]$ExecutablePath,
        [string]$IconPath
    )

    try {
        Add-Type -AssemblyName System.Drawing

        $iconDir = Split-Path $IconPath -Parent
        New-Item -ItemType Directory -Path $iconDir -Force | Out-Null

        $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($ExecutablePath)
        if (-not $icon) {
            Write-Warning "Could not extract an icon from: $ExecutablePath"
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
        Write-Warning "Could not write the local Codex icon: $($_.Exception.Message)"
        return $false
    }
}

function Register-CodexAdminTask {
    param(
        [string]$TaskName,
        [string]$PowerShellPath,
        [string]$LauncherPath
    )

    $action = New-ScheduledTaskAction `
        -Execute $PowerShellPath `
        -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$LauncherPath`""
    $trigger = New-ScheduledTaskTrigger -Once -At ([datetime]'2099-01-01T00:00:00')
    $principal = New-ScheduledTaskPrincipal `
        -UserId ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name) `
        -LogonType Interactive `
        -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable

    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $action `
        -Trigger $trigger `
        -Principal $principal `
        -Settings $settings `
        -Force | Out-Null
}

function Clear-ShortcutRunAsFlag {
    param([string]$ShortcutPath)

    if (-not (Test-Path $ShortcutPath)) {
        return
    }

    $bytes = [System.IO.File]::ReadAllBytes($ShortcutPath)
    $bytes[0x15] = $bytes[0x15] -band 0xDF
    [System.IO.File]::WriteAllBytes($ShortcutPath, $bytes)
}

function Set-CodexEnterBehavior {
    param(
        [string]$StatePath,
        [string]$BackupPath,
        [bool]$CodexIsRunning
    )

    if ($CodexIsRunning) {
        return [pscustomobject]@{
            Status  = 'skipped-running'
            Message = 'Codex is currently running. Fully quit it and rerun this script to apply Enter-as-newline.'
        }
    }

    if (-not (Test-Path $StatePath)) {
        return [pscustomobject]@{
            Status  = 'missing-state'
            Message = 'Launch Codex once, then rerun this script to apply Enter-as-newline.'
        }
    }

    Backup-File -Path $StatePath -BackupDir (Split-Path $BackupPath) -BackupName (Split-Path $BackupPath -Leaf)

    try {
        $state = Get-Content $StatePath -Raw | ConvertFrom-Json
    } catch {
        return [pscustomobject]@{
            Status  = 'invalid-state'
            Message = "Could not parse the Codex state file: $($_.Exception.Message)"
        }
    }

    $atomState = $state.'electron-persisted-atom-state'
    if (-not $atomState) {
        return [pscustomobject]@{
            Status  = 'unexpected-state'
            Message = 'Could not locate electron-persisted-atom-state in the Codex state file.'
        }
    }

    $enterBehaviorProperty = $atomState.PSObject.Properties['enter-behavior']
    if ($null -eq $enterBehaviorProperty) {
        $atomState | Add-Member -NotePropertyName 'enter-behavior' -NotePropertyValue 'newline'
        $status = 'updated'
    } elseif ($atomState.'enter-behavior' -eq 'newline') {
        $status = 'already-set'
    } else {
        $atomState.'enter-behavior' = 'newline'
        $status = 'updated'
    }

    if ($status -eq 'already-set') {
        return [pscustomobject]@{
            Status  = 'already-set'
            Message = 'Enter already inserts a newline. Use Ctrl+Enter to send.'
        }
    }

    try {
        $updatedState = $state | ConvertTo-Json -Depth 100 -Compress
        [System.IO.File]::WriteAllText(
            $StatePath,
            $updatedState,
            [System.Text.UTF8Encoding]::new($false)
        )
    } catch {
        return [pscustomobject]@{
            Status  = 'write-failed'
            Message = "Could not write the updated Codex state file: $($_.Exception.Message)"
        }
    }

    return [pscustomobject]@{
        Status  = 'updated'
        Message = 'Enter now inserts a newline. Use Ctrl+Enter to send.'
    }
}

$desktopPath = [Environment]::GetFolderPath('Desktop')
$userProfile = $env:USERPROFILE
$localAppData = $env:LOCALAPPDATA
$shortcutPath = Join-Path $desktopPath 'Codex.lnk'
$shortcutBackupDir = Join-Path $localAppData 'OpenAI\CodexShortcutBackup'
$packagedConfigPath = Join-Path $PSScriptRoot 'config.toml'
$codexConfigDir = Join-Path $userProfile '.codex'
$codexConfigPath = Join-Path $codexConfigDir 'config.toml'
$codexConfigBackupPath = Join-Path $codexConfigDir 'config.toml.bak-from-setup'
$statePath = Join-Path $userProfile '.codex\.codex-global-state.json'
$stateBackupPath = Join-Path $userProfile '.codex\.codex-global-state.json.bak-enter-behavior'
$powerShellPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$schtasksPath = Join-Path $env:SystemRoot 'System32\schtasks.exe'
$launcherDir = Join-Path $localAppData 'CodexLauncher'
$launcherPath = Join-Path $launcherDir 'Launch-Codex.ps1'
$iconPath = Join-Path $launcherDir 'Codex.ico'
$taskName = 'CodexAdminLauncher'

Write-Step 'Locating the installed Codex package'
$package = Get-CodexPackage
if (-not $package) {
    throw 'Codex is not installed. Install it and launch it once, then run this script again.'
}

$codexExePath = Get-CodexExecutablePath -Package $package
if (-not $codexExePath) {
    throw "Could not find the Codex executable under: $($package.InstallLocation)"
}

$runningCodex = @(Get-Process Codex -ErrorAction SilentlyContinue)
$codexWasRunning = $runningCodex.Count -gt 0

Write-Step 'Writing the local Codex launcher'
Write-LauncherScript -LauncherPath $launcherPath

Write-Step 'Caching the Codex shortcut icon'
$shortcutIconReady = Write-ShortcutIcon -ExecutablePath $codexExePath -IconPath $iconPath

Write-Step 'Registering the Codex admin task'
Register-CodexAdminTask -TaskName $taskName -PowerShellPath $powerShellPath -LauncherPath $launcherPath

Write-Step 'Updating the desktop shortcut'
Backup-File -Path $shortcutPath -BackupDir $shortcutBackupDir -BackupName 'Codex.original.lnk'

$wshShell = New-Object -ComObject WScript.Shell
$shortcut = $wshShell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $schtasksPath
$shortcut.Arguments = '/run /tn "CodexAdminLauncher"'
$shortcut.WorkingDirectory = Split-Path $schtasksPath
if ($shortcutIconReady -and (Test-Path $iconPath)) {
    $shortcut.IconLocation = "$iconPath,0"
} else {
    $shortcut.IconLocation = "$codexExePath,0"
}
$shortcut.Description = 'Launch Codex as administrator'
$shortcut.WindowStyle = 7
$shortcut.Save()
Clear-ShortcutRunAsFlag -ShortcutPath $shortcutPath

Write-Step 'Applying the packaged Codex config'
if (-not (Test-Path $packagedConfigPath)) {
    Write-Warning "Could not find the packaged config file: $packagedConfigPath"
} else {
    New-Item -ItemType Directory -Path $codexConfigDir -Force | Out-Null
    Backup-File -Path $codexConfigPath -BackupDir $codexConfigDir -BackupName (Split-Path $codexConfigBackupPath -Leaf)
    Copy-Item $packagedConfigPath $codexConfigPath -Force
}

Write-Step 'Updating Enter behavior to newline'
if ($codexWasRunning) {
    Write-Warning 'Codex is currently running. The Enter-as-newline change will be skipped for this run.'
}

$enterBehaviorResult = Set-CodexEnterBehavior `
    -StatePath $statePath `
    -BackupPath $stateBackupPath `
    -CodexIsRunning $codexWasRunning

$shortcutBackupPath = Join-Path $shortcutBackupDir 'Codex.original.lnk'

Write-Host ''
Write-Host 'Done:'
Write-Host '- The desktop Codex shortcut now launches through the CodexAdminLauncher scheduled task.'
Write-Host '- The local launcher script has been written to %LOCALAPPDATA%\CodexLauncher\Launch-Codex.ps1.'
if (Test-Path $packagedConfigPath) {
    Write-Host '- The packaged Codex config has been copied into the user profile.'
}
switch ($enterBehaviorResult.Status) {
    'updated' {
        Write-Host "- $($enterBehaviorResult.Message)"
    }
    'already-set' {
        Write-Host "- $($enterBehaviorResult.Message)"
    }
    default {
        Write-Host "- Enter behavior was not changed. $($enterBehaviorResult.Message)"
    }
}

Write-Host ''
Write-Host "Desktop shortcut: $shortcutPath"
Write-Host "Shortcut backup: $shortcutBackupPath"
Write-Host "Scheduled task: $taskName"
Write-Host "Launcher script: $launcherPath"
if (Test-Path $iconPath) {
    Write-Host "Shortcut icon: $iconPath"
}
Write-Host "Codex config: $codexConfigPath"
if (Test-Path $codexConfigBackupPath) {
    Write-Host "Codex config backup: $codexConfigBackupPath"
}
if (Test-Path $statePath) {
    Write-Host "State file: $statePath"
    Write-Host "State backup: $stateBackupPath"
}
