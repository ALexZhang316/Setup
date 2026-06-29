# new-job.ps1 - queue an administrator job and trigger Setup Elevated Runner.

param(
    [string]$ScriptPath,
    [string]$Command,
    [switch]$Wait,
    [int]$TimeoutSeconds = 300
)

$ErrorActionPreference = 'Stop'

$TaskName = 'Setup Elevated Runner'
$RunnerRoot = Join-Path $env:LOCALAPPDATA 'SetupElevatedRunner'
$QueueDir = Join-Path $RunnerRoot 'queue'
$LogsDir = Join-Path $RunnerRoot 'logs'
$DoneDir = Join-Path $RunnerRoot 'done'

if ([string]::IsNullOrWhiteSpace($ScriptPath) -eq [string]::IsNullOrWhiteSpace($Command)) {
    throw 'Specify exactly one of -ScriptPath or -Command.'
}

if (-not (Test-Path -LiteralPath $RunnerRoot)) {
    throw ('Runner root does not exist. Install it first: powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\shared\elevated-runner\install.ps1')
}

foreach ($dir in @($QueueDir, $LogsDir, $DoneDir)) {
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

function Get-JobExitCode {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    $logText = Get-Content -LiteralPath $Path -Raw
    $match = [regex]::Match($logText, '(?m)^ExitCode=(-?\d+)\s*$')
    if ($match.Success) {
        return [int]$match.Groups[1].Value
    }

    return $null
}

if ($ScriptPath) {
    $resolvedScriptPath = (Resolve-Path -LiteralPath $ScriptPath).Path
    $scriptContent = Get-Content -LiteralPath $resolvedScriptPath -Raw
    $source = $resolvedScriptPath
}
else {
    $scriptContent = $Command
    $source = 'inline-command'
}

$randomPart = [guid]::NewGuid().ToString('N').Substring(0, 8)
$jobId = '{0:yyyyMMdd-HHmmss-fff}-{1}-{2}' -f (Get-Date), $PID, $randomPart
$jobPath = Join-Path $QueueDir ($jobId + '.json')
$logPath = Join-Path $LogsDir ($jobId + '.log')
$donePath = Join-Path $DoneDir ($jobId + '.json')

$cwd = (Get-Location).ProviderPath
$userName = [Security.Principal.WindowsIdentity]::GetCurrent().Name

$job = [ordered]@{
    id = $jobId
    createdAt = (Get-Date).ToString('o')
    createdBy = $userName
    cwd = $cwd
    source = $source
    script = $scriptContent
}

$json = $job | ConvertTo-Json -Depth 5
Set-Content -LiteralPath $jobPath -Value $json -Encoding UTF8

Write-Host ('Queued job: {0}' -f $jobId)
Write-Host ('  Job: {0}' -f $jobPath)
Write-Host ('  Log: {0}' -f $logPath)
Write-Host ('  Done: {0}' -f $donePath)

$schtasks = Join-Path $env:SystemRoot 'System32\schtasks.exe'
$triggerOutput = & $schtasks /run /tn $TaskName 2>&1
$triggerExitCode = $LASTEXITCODE
$triggerOutput | ForEach-Object { Write-Host $_ }
if ($triggerExitCode -ne 0) {
    throw ('Failed to trigger scheduled task {0}. schtasks exit code: {1}' -f $TaskName, $triggerExitCode)
}

if (-not $Wait) {
    exit 0
}

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$exitCode = $null
while ((Get-Date) -lt $deadline) {
    if (Test-Path -LiteralPath $donePath) {
        $exitCode = Get-JobExitCode -Path $logPath
        if ($null -ne $exitCode) {
            break
        }
    }

    Start-Sleep -Milliseconds 500
}

if (-not (Test-Path -LiteralPath $donePath)) {
    Write-Host ('Timed out waiting for job completion after {0} seconds.' -f $TimeoutSeconds)
    Write-Host ('Log: {0}' -f $logPath)
    exit 124
}

if ($null -eq $exitCode) {
    Write-Host ('Timed out waiting for job exit code after {0} seconds.' -f $TimeoutSeconds)
    Write-Host ('Log: {0}' -f $logPath)
    exit 124
}

Write-Host ('Job completed: {0}' -f $jobId)
Write-Host ('ExitCode={0}' -f $exitCode)
Write-Host ('Log={0}' -f $logPath)
exit $exitCode
