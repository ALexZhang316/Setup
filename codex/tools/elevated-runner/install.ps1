# install.ps1 - install a scheduled-task based elevated command runner.

param(
    [string]$RepoRoot
)

$ErrorActionPreference = 'Stop'

if (-not $RepoRoot) {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
}
else {
    $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
}

$TaskName = 'Codex Elevated Runner'
$RunnerRoot = Join-Path $env:LOCALAPPDATA 'CodexElevatedRunner'
$QueueDir = Join-Path $RunnerRoot 'queue'
$RunningDir = Join-Path $RunnerRoot 'running'
$LogsDir = Join-Path $RunnerRoot 'logs'
$DoneDir = Join-Path $RunnerRoot 'done'
$InstalledRunnerPath = Join-Path $RunnerRoot 'runner.ps1'
$TriggerCmdPath = Join-Path $RunnerRoot 'Run-Elevated-Runner.cmd'
$LegacyRunnerPaths = @(
    (Join-Path $RunnerRoot 'Elevated-Runner.ps1')
)

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

function Ensure-Directory {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

foreach ($dir in @($RunnerRoot, $QueueDir, $RunningDir, $LogsDir, $DoneDir)) {
    Ensure-Directory -Path $dir
}

foreach ($legacyRunnerPath in $LegacyRunnerPaths) {
    if (Test-Path -LiteralPath $legacyRunnerPath) {
        Remove-Item -LiteralPath $legacyRunnerPath -Force
    }
}

$sourceRunnerPath = Join-Path $RepoRoot 'codex\tools\elevated-runner\runner.ps1'
if (-not (Test-Path -LiteralPath $sourceRunnerPath)) {
    throw ('Runner script not found: {0}' -f $sourceRunnerPath)
}

Copy-Item -LiteralPath $sourceRunnerPath -Destination $InstalledRunnerPath -Force

$triggerContent = @"
@echo off
schtasks.exe /run /tn "$TaskName"
exit /b %ERRORLEVEL%
"@
Set-Content -LiteralPath $TriggerCmdPath -Value $triggerContent -Encoding ASCII

$psTaskExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$taskArgs = '-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $InstalledRunnerPath
$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name

$action = New-ScheduledTaskAction -Execute $psTaskExe -Argument $taskArgs
$principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances Queue
Register-ScheduledTask -TaskName $TaskName -Action $action -Principal $principal -Settings $settings -Force | Out-Null

$registeredTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop

Write-Host 'Codex elevated runner installed.'
Write-Host ('  TaskName: {0}' -f $TaskName)
Write-Host ('  TaskState: {0}' -f $registeredTask.State)
Write-Host ('  RunnerRoot: {0}' -f $RunnerRoot)
Write-Host ('  QueueDir: {0}' -f $QueueDir)
Write-Host ('  LogsDir: {0}' -f $LogsDir)
Write-Host ('  DoneDir: {0}' -f $DoneDir)
Write-Host ('  RunnerScript: {0}' -f $InstalledRunnerPath)
Write-Host ('  TriggerCmd: {0}' -f $TriggerCmdPath)
Write-Host ''
Write-Host 'Usage from a medium-token Codex shell:'
Write-Host ('  schtasks.exe /run /tn "{0}"' -f $TaskName)
Write-Host '  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\codex\tools\elevated-runner\new-job.ps1 -Command "net session" -Wait'
