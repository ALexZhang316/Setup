# Elevated-Runner.ps1 - execute queued jobs with an administrator token.

$ErrorActionPreference = 'Stop'

$RunnerRoot = Join-Path $env:LOCALAPPDATA 'CodexElevatedRunner'
$QueueDir = Join-Path $RunnerRoot 'queue'
$RunningDir = Join-Path $RunnerRoot 'running'
$LogsDir = Join-Path $RunnerRoot 'logs'
$DoneDir = Join-Path $RunnerRoot 'done'

function Test-IsAdmin {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Ensure-Directory {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Add-Text {
    param(
        [Parameter(Mandatory)][string]$Path,
        [AllowNull()][AllowEmptyString()][string]$Text
    )

    if ($null -eq $Text) {
        $Text = ''
    }

    Add-Content -LiteralPath $Path -Value $Text -Encoding UTF8
}

function New-GeneralLogPath {
    return (Join-Path $LogsDir ('runner-{0:yyyyMMdd-HHmmss-fff}.log' -f (Get-Date)))
}

function Write-GeneralLog {
    param([Parameter(Mandatory)][string]$Message)

    $path = New-GeneralLogPath
    Add-Text -Path $path -Text ('{0:o} {1}' -f (Get-Date), $Message)
}

function Get-SafeJobId {
    param(
        [string]$JobId,
        [Parameter(Mandatory)][string]$Fallback
    )

    if ([string]::IsNullOrWhiteSpace($JobId)) {
        $JobId = $Fallback
    }

    $safe = [regex]::Replace($JobId, '[^A-Za-z0-9_.-]', '_')
    if ([string]::IsNullOrWhiteSpace($safe)) {
        $safe = $Fallback
    }

    return $safe
}

function Move-ToDone {
    param(
        [Parameter(Mandatory)][string]$RunningPath,
        [Parameter(Mandatory)][string]$JobId
    )

    $donePath = Join-Path $DoneDir ($JobId + '.json')
    if (Test-Path -LiteralPath $donePath) {
        $donePath = Join-Path $DoneDir ('{0}-{1:yyyyMMdd-HHmmss-fff}.json' -f $JobId, (Get-Date))
    }

    Move-Item -LiteralPath $RunningPath -Destination $donePath -Force
    return $donePath
}

function Quote-Argument {
    param([Parameter(Mandatory)][string]$Value)

    return '"' + ($Value -replace '"', '\"') + '"'
}

function Invoke-JobScript {
    param(
        [Parameter(Mandatory)][string]$JobId,
        [Parameter(Mandatory)][string]$Script,
        [string]$WorkingDirectory
    )

    $scriptPath = Join-Path $RunningDir ($JobId + '.ps1')
    $stdoutPath = Join-Path $RunningDir ($JobId + '.stdout.txt')
    $stderrPath = Join-Path $RunningDir ($JobId + '.stderr.txt')

    $wrapped = @"
`$ErrorActionPreference = 'Stop'
try {
& {
$Script
}
if (`$null -ne `$global:LASTEXITCODE) {
    exit ([int]`$global:LASTEXITCODE)
}
exit 0
}
catch {
    Write-Error (`$_ | Out-String)
    exit 1
}
"@

    Set-Content -LiteralPath $scriptPath -Value $wrapped -Encoding UTF8

    $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $args = '-NoProfile -ExecutionPolicy Bypass -File {0}' -f (Quote-Argument -Value $scriptPath)

    $startInfo = @{
        FilePath = $psExe
        ArgumentList = $args
        Wait = $true
        PassThru = $true
        RedirectStandardOutput = $stdoutPath
        RedirectStandardError = $stderrPath
        WindowStyle = 'Hidden'
    }

    if ($WorkingDirectory -and (Test-Path -LiteralPath $WorkingDirectory)) {
        $startInfo.WorkingDirectory = $WorkingDirectory
    }

    $process = Start-Process @startInfo

    $stdout = ''
    $stderr = ''
    if (Test-Path -LiteralPath $stdoutPath) { $stdout = Get-Content -LiteralPath $stdoutPath -Raw }
    if (Test-Path -LiteralPath $stderrPath) { $stderr = Get-Content -LiteralPath $stderrPath -Raw }

    Remove-Item -LiteralPath $scriptPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $stdoutPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $stderrPath -Force -ErrorAction SilentlyContinue

    return [pscustomobject]@{
        ExitCode = [int]$process.ExitCode
        Stdout = $stdout
        Stderr = $stderr
    }
}

foreach ($dir in @($RunnerRoot, $QueueDir, $RunningDir, $LogsDir, $DoneDir)) {
    Ensure-Directory -Path $dir
}

if (-not (Test-IsAdmin)) {
    Write-GeneralLog 'ERROR: Elevated-Runner.ps1 is not running with an administrator token.'
    exit 1
}

$jobs = @(Get-ChildItem -LiteralPath $QueueDir -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object CreationTimeUtc, Name)
if ($jobs.Count -eq 0) {
    Write-GeneralLog 'No pending jobs.'
    exit 0
}

$overallExitCode = 0

foreach ($jobFile in $jobs) {
    $fallbackJobId = [IO.Path]::GetFileNameWithoutExtension($jobFile.Name)
    $runningPath = Join-Path $RunningDir $jobFile.Name

    if (Test-Path -LiteralPath $runningPath) {
        $runningPath = Join-Path $RunningDir ('{0}-{1:yyyyMMdd-HHmmss-fff}.json' -f $fallbackJobId, (Get-Date))
    }

    try {
        Move-Item -LiteralPath $jobFile.FullName -Destination $runningPath -ErrorAction Stop
    }
    catch {
        Write-GeneralLog ('Skipped job because it could not be locked: Path={0}; Error={1}' -f $jobFile.FullName, $_.Exception.Message)
        $overallExitCode = 1
        continue
    }

    $jobId = $fallbackJobId
    $logPath = Join-Path $LogsDir ($jobId + '.log')
    $startedAt = Get-Date
    $exitCode = 1
    $donePath = $null

    try {
        $rawJson = Get-Content -LiteralPath $runningPath -Raw
        $job = $rawJson | ConvertFrom-Json
        $jobId = Get-SafeJobId -JobId ([string]$job.id) -Fallback $fallbackJobId
        $logPath = Join-Path $LogsDir ($jobId + '.log')

        if (-not $job.script -or [string]::IsNullOrWhiteSpace([string]$job.script)) {
            throw 'Job JSON does not contain a non-empty script field.'
        }

        $identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        Add-Text -Path $logPath -Text ('JobId={0}' -f $jobId)
        Add-Text -Path $logPath -Text ('StartTime={0:o}' -f $startedAt)
        Add-Text -Path $logPath -Text ('User={0}' -f $identity)
        Add-Text -Path $logPath -Text ('IsAdmin={0}' -f (Test-IsAdmin))
        Add-Text -Path $logPath -Text ('QueueFile={0}' -f $jobFile.FullName)
        Add-Text -Path $logPath -Text ('RunningFile={0}' -f $runningPath)
        Add-Text -Path $logPath -Text ('WorkingDirectory={0}' -f ([string]$job.cwd))
        Add-Text -Path $logPath -Text 'ScriptBegin'
        Add-Text -Path $logPath -Text ([string]$job.script)
        Add-Text -Path $logPath -Text 'ScriptEnd'

        $result = Invoke-JobScript -JobId $jobId -Script ([string]$job.script) -WorkingDirectory ([string]$job.cwd)
        $exitCode = [int]$result.ExitCode

        Add-Text -Path $logPath -Text 'StdoutBegin'
        Add-Text -Path $logPath -Text ([string]$result.Stdout)
        Add-Text -Path $logPath -Text 'StdoutEnd'
        Add-Text -Path $logPath -Text 'StderrBegin'
        Add-Text -Path $logPath -Text ([string]$result.Stderr)
        Add-Text -Path $logPath -Text 'StderrEnd'
    }
    catch {
        Add-Text -Path $logPath -Text ('ERROR={0}' -f $_.Exception.ToString())
        $exitCode = 1
    }
    finally {
        $endedAt = Get-Date
        try {
            $donePath = Move-ToDone -RunningPath $runningPath -JobId $jobId
        }
        catch {
            Add-Text -Path $logPath -Text ('ERROR moving job to done: {0}' -f $_.Exception.ToString())
            $exitCode = 1
        }

        Add-Text -Path $logPath -Text ('EndTime={0:o}' -f $endedAt)
        Add-Text -Path $logPath -Text ('DurationSeconds={0:n3}' -f (($endedAt - $startedAt).TotalSeconds))
        Add-Text -Path $logPath -Text ('DoneFile={0}' -f $donePath)
        Add-Text -Path $logPath -Text ('ExitCode={0}' -f $exitCode)
    }

    if ($exitCode -ne 0) {
        $overallExitCode = $exitCode
    }
}

exit $overallExitCode
