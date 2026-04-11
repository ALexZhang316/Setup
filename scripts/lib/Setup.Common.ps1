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

function Write-SetupFailure {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Write-Host ''
    Write-Host $Title -ForegroundColor Red
    Write-Host ("  {0}" -f $Message) -ForegroundColor Red
}

function Write-SetupWarning {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Write-Host $Message -ForegroundColor Yellow
}

function Copy-FileSnapshot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [string]$DestinationPath
    )

    if (-not (Test-Path -LiteralPath $SourcePath)) {
        throw "Missing file snapshot: $SourcePath"
    }

    Ensure-Directory -Path (Split-Path -Parent $DestinationPath)
    Copy-Item -LiteralPath $SourcePath -Destination $DestinationPath -Force
}

function Sync-DirectorySnapshot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [string]$DestinationPath
    )

    if (-not (Test-Path -LiteralPath $SourcePath)) {
        throw "Missing directory snapshot: $SourcePath"
    }

    $parentPath = Split-Path -Parent $DestinationPath
    $leafName = Split-Path -Leaf $DestinationPath
    $stagingPath = Join-Path $parentPath ("{0}.staging.{1}" -f $leafName, [guid]::NewGuid().ToString('N'))
    $backupPath = Join-Path $parentPath ("{0}.backup.{1}" -f $leafName, [guid]::NewGuid().ToString('N'))
    $hasBackup = $false

    Ensure-Directory -Path $parentPath
    Copy-Item -LiteralPath $SourcePath -Destination $stagingPath -Recurse -Force

    try {
        if (Test-Path -LiteralPath $DestinationPath) {
            Move-Item -LiteralPath $DestinationPath -Destination $backupPath
            $hasBackup = $true
        }

        Move-Item -LiteralPath $stagingPath -Destination $DestinationPath
    }
    catch {
        if (-not (Test-Path -LiteralPath $DestinationPath) -and $hasBackup -and (Test-Path -LiteralPath $backupPath)) {
            Move-Item -LiteralPath $backupPath -Destination $DestinationPath
            $hasBackup = $false
        }

        throw
    }
    finally {
        if (Test-Path -LiteralPath $stagingPath) {
            Remove-Item -LiteralPath $stagingPath -Recurse -Force
        }

        if ($hasBackup -and (Test-Path -LiteralPath $backupPath)) {
            Remove-Item -LiteralPath $backupPath -Recurse -Force
        }
    }
}

function Get-FileSha256 {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Assert-FileExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw ("缺少 {0}：{1}" -f $Label, $Path)
    }
}

function Assert-FilesMatch {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [string]$DestinationPath,

        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    Assert-FileExists -Path $SourcePath -Label ("源 {0}" -f $Label)
    Assert-FileExists -Path $DestinationPath -Label ("目标 {0}" -f $Label)

    $sourceHash = Get-FileSha256 -Path $SourcePath
    $destinationHash = Get-FileSha256 -Path $DestinationPath
    if ($sourceHash -ne $destinationHash) {
        throw ("{0} 校验失败：目标内容与源文件不一致。" -f $Label)
    }
}

function Assert-JsonFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    Assert-FileExists -Path $Path -Label $Label

    try {
        Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json | Out-Null
    }
    catch {
        throw ("{0} 不是有效 JSON：{1}" -f $Label, $Path)
    }
}

function Get-RelativePathWithinRoot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $resolvedRoot = (Resolve-Path -LiteralPath $RootPath).Path.TrimEnd('\')
    $resolvedPath = (Resolve-Path -LiteralPath $Path).Path

    if ($resolvedPath.Length -le $resolvedRoot.Length) {
        return ''
    }

    if (-not $resolvedPath.StartsWith(("{0}\" -f $resolvedRoot), [System.StringComparison]::OrdinalIgnoreCase)) {
        throw ("路径不在根目录内：{0}" -f $resolvedPath)
    }

    return $resolvedPath.Substring($resolvedRoot.Length + 1)
}

function Get-DirectorySnapshotSignature {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return @()
    }

    $entries = New-Object 'System.Collections.Generic.List[string]'
    foreach ($entry in @(Get-ChildItem -LiteralPath $Path -Force -Recurse | Sort-Object FullName)) {
        $relativePath = Get-RelativePathWithinRoot -RootPath $Path -Path $entry.FullName
        if ([string]::IsNullOrWhiteSpace($relativePath)) {
            continue
        }

        if ($entry.PSIsContainer) {
            $entries.Add(("D:{0}" -f $relativePath)) | Out-Null
            continue
        }

        $entries.Add(("F:{0}:{1}" -f $relativePath, (Get-FileSha256 -Path $entry.FullName))) | Out-Null
    }

    return $entries.ToArray()
}

function Assert-DirectorySnapshotMatch {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [string]$DestinationPath,

        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    if (-not (Test-Path -LiteralPath $SourcePath)) {
        throw ("缺少源目录 {0}：{1}" -f $Label, $SourcePath)
    }

    if (-not (Test-Path -LiteralPath $DestinationPath)) {
        throw ("缺少目标目录 {0}：{1}" -f $Label, $DestinationPath)
    }

    $sourceSignature = @(Get-DirectorySnapshotSignature -Path $SourcePath)
    $destinationSignature = @(Get-DirectorySnapshotSignature -Path $DestinationPath)

    if (($sourceSignature -join "`n") -ne ($destinationSignature -join "`n")) {
        throw ("{0} 目录快照校验失败：目标目录与源目录递归内容不一致。" -f $Label)
    }
}

function Test-CommandLineContainsPath {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$CommandLine,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($CommandLine) -or [string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }

    $resolvedPath = $Path
    if (Test-Path -LiteralPath $Path) {
        $resolvedPath = (Resolve-Path -LiteralPath $Path).Path
    }

    $normalizedCommandLine = $CommandLine.Replace('/', '\')
    $normalizedPath = $resolvedPath.Replace('/', '\')
    return ($normalizedCommandLine.IndexOf($normalizedPath, [System.StringComparison]::OrdinalIgnoreCase) -ge 0)
}

function Get-RunningProcessRecords {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ProcessNames
    )

    $normalizedNames = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($processName in @($ProcessNames | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        $trimmedName = $processName.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmedName)) {
            continue
        }

        $normalizedNames.Add($trimmedName) | Out-Null
        if ($trimmedName -like '*.exe') {
            $normalizedNames.Add($trimmedName.Substring(0, $trimmedName.Length - 4)) | Out-Null
        }
        else {
            $normalizedNames.Add(("{0}.exe" -f $trimmedName)) | Out-Null
        }
    }

    if ($normalizedNames.Count -eq 0) {
        return @()
    }

    return @(
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object { $normalizedNames.Contains($_.Name) } |
            Sort-Object Name, ProcessId
    )
}

function Assert-ProcessesStopped {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Label,

        [Parameter(Mandatory = $true)]
        [string[]]$ProcessNames
    )

    $runningProcesses = @(Get-RunningProcessRecords -ProcessNames $ProcessNames)
    if ($runningProcesses.Count -eq 0) {
        return
    }

    $processSummary = @(
        $runningProcesses |
            ForEach-Object { "{0} (PID {1})" -f $_.Name, $_.ProcessId }
    ) -join '、'

    throw ("检测到正在运行的 {0} 进程：{1}。请先完全退出相关应用后再运行本脚本。" -f $Label, $processSummary)
}

function Assert-DirectoryTopLevelMatch {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [string]$DestinationPath,

        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    Assert-DirectorySnapshotMatch -SourcePath $SourcePath -DestinationPath $DestinationPath -Label $Label
}

function Get-TopLevelDirectorySignature {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return @()
    }

    return @(Get-ChildItem -LiteralPath $Path -Force |
        Sort-Object Name |
        ForEach-Object {
            $entryType = if ($_.PSIsContainer) { 'D' } else { 'F' }
            "{0}:{1}" -f $entryType, $_.Name
        })
}

function Get-WindowsPowerShellPath {
    return (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')
}

function Invoke-PowerShellScriptStep {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,

        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,

        [hashtable]$Parameters = @{}
    )

    Write-Host ''
    Write-Host ("==> {0}" -f $Title) -ForegroundColor Cyan

    $argumentList = @(
        '-NoProfile'
        '-ExecutionPolicy'
        'Bypass'
        '-File'
        $ScriptPath
    )

    foreach ($entry in ($Parameters.GetEnumerator() | Sort-Object Name)) {
        if ($entry.Value -is [switch]) {
            if ($entry.Value.IsPresent) {
                $argumentList += "-$($entry.Key)"
            }

            continue
        }

        if ($entry.Value -is [bool]) {
            if ($entry.Value) {
                $argumentList += "-$($entry.Key)"
            }

            continue
        }

        if ($null -eq $entry.Value) {
            continue
        }

        $argumentList += "-$($entry.Key)"
        $argumentList += [string]$entry.Value
    }

    & (Get-WindowsPowerShellPath) @argumentList
    if ($LASTEXITCODE -ne 0) {
        throw ("步骤失败：{0}（退出码 {1}）" -f $Title, $LASTEXITCODE)
    }
}

function Quote-CommandArgument {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    return ('"{0}"' -f $Value.Replace('"', '""'))
}

function Test-IsAdministrator {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Ensure-ProcessElevated {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,

        [string]$RepoRoot,

        [hashtable]$AdditionalParameters = @{},

        [switch]$Elevated
    )

    if ($Elevated -or (Test-IsAdministrator)) {
        return
    }

    $argumentList = New-Object 'System.Collections.Generic.List[string]'
    $argumentList.Add('-NoProfile') | Out-Null
    $argumentList.Add('-ExecutionPolicy') | Out-Null
    $argumentList.Add('Bypass') | Out-Null
    $argumentList.Add('-File') | Out-Null
    $argumentList.Add((Quote-CommandArgument -Value $ScriptPath)) | Out-Null

    if (-not [string]::IsNullOrWhiteSpace($RepoRoot)) {
        $argumentList.Add('-RepoRoot') | Out-Null
        $argumentList.Add((Quote-CommandArgument -Value $RepoRoot)) | Out-Null
    }

    foreach ($entry in ($AdditionalParameters.GetEnumerator() | Sort-Object Name)) {
        if ($entry.Value -is [switch]) {
            if ($entry.Value.IsPresent) {
                $argumentList.Add("-$($entry.Key)") | Out-Null
            }

            continue
        }

        if ($entry.Value -is [bool]) {
            if ($entry.Value) {
                $argumentList.Add("-$($entry.Key)") | Out-Null
            }

            continue
        }

        if ($null -eq $entry.Value) {
            continue
        }

        $argumentList.Add("-$($entry.Key)") | Out-Null
        $argumentList.Add((Quote-CommandArgument -Value ([string]$entry.Value))) | Out-Null
    }

    $argumentList.Add('-Elevated') | Out-Null

    $process = Start-Process -FilePath (Get-WindowsPowerShellPath) -Verb RunAs -ArgumentList ($argumentList -join ' ') -Wait -PassThru
    exit $process.ExitCode
}

function Get-GitStatusLines {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,

        [Parameter(Mandatory = $true)]
        [string[]]$RelativePaths
    )

    $gitCmd = Get-GitCommand
    if (-not $gitCmd) {
        throw '未检测到 Git。该步骤需要 Git 来检查仓库快照状态。'
    }

    $statusOutput = & $gitCmd -C $RepoRoot status --short -- @RelativePaths
    if ($LASTEXITCODE -ne 0) {
        throw ("Git 状态检查失败：{0}" -f $RepoRoot)
    }

    return @($statusOutput | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Assert-GitPathsClean {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,

        [Parameter(Mandatory = $true)]
        [string[]]$RelativePaths,

        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    $statusLines = @(Get-GitStatusLines -RepoRoot $RepoRoot -RelativePaths $RelativePaths)
    if ($statusLines.Count -gt 0) {
        throw ("{0} 终止：仓库目标路径存在未提交改动，请先提交或清理后再试。" -f $Label)
    }
}

function Write-GitStatusSummary {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,

        [Parameter(Mandatory = $true)]
        [string[]]$RelativePaths
    )

    $statusLines = @(Get-GitStatusLines -RepoRoot $RepoRoot -RelativePaths $RelativePaths)

    if ($statusLines.Count -eq 0) {
        Write-Host '  git status -> （无变更）'
        return
    }

    Write-Host '  git status:'
    foreach ($line in $statusLines) {
        Write-Host ("    {0}" -f $line)
    }
}
