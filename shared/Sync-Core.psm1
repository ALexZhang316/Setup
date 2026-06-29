$ErrorActionPreference = 'Stop'

function Assert-SetupUserProfile {
    if ([string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
        throw 'USERPROFILE is empty. Cannot resolve local profile paths.'
    }
}

function Resolve-SetupRoot {
    param([string]$RepoRoot)

    if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
        throw 'RepoRoot is required.'
    }
    if (-not (Test-Path -LiteralPath $RepoRoot)) {
        throw ('Repository root does not exist: {0}' -f $RepoRoot)
    }

    return (Resolve-Path -LiteralPath $RepoRoot).Path
}

function Sync-SetupDirectory {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )

    $parent = Split-Path -Parent $Destination
    $name = Split-Path -Leaf $Destination
    $staging = Join-Path $parent ('.sync-staging-' + $name)
    $backup = Join-Path $parent ('.sync-backup-' + $name)

    if (Test-Path -LiteralPath $staging) {
        Remove-Item -LiteralPath $staging -Recurse -Force
    }

    Copy-Item -LiteralPath $Source -Destination $staging -Recurse -Force
    if (-not (Test-Path -LiteralPath $staging)) {
        throw ('Failed to create staging directory: {0}' -f $staging)
    }

    $destinationExists = Test-Path -LiteralPath $Destination
    $renamed = $false
    if ($destinationExists) {
        if (Test-Path -LiteralPath $backup) {
            Remove-Item -LiteralPath $backup -Recurse -Force
        }

        try {
            Rename-Item -LiteralPath $Destination -NewName ('.sync-backup-' + $name)
            $renamed = $true
        }
        catch {
            Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
            throw ('Destination directory is busy or cannot be renamed: {0}. {1}' -f $Destination, $_.Exception.Message)
        }
    }

    if ($renamed) {
        try {
            Rename-Item -LiteralPath $staging -NewName $name
        }
        catch {
            if (Test-Path -LiteralPath $backup) {
                Rename-Item -LiteralPath $backup -NewName $name -ErrorAction SilentlyContinue
            }
            throw ('Directory replacement failed and rollback was attempted: {0}' -f $_.Exception.Message)
        }

        if (Test-Path -LiteralPath $backup) {
            Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    else {
        Rename-Item -LiteralPath $staging -NewName $name
    }

    if (Test-Path -LiteralPath $staging) {
        Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Sync-SetupItem {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination,
        [Parameter(Mandatory)][ValidateSet('file', 'dir')][string]$Type,
        [switch]$Preview
    )

    if (-not (Test-Path -LiteralPath $Source)) {
        Write-Host ('[skip] Missing source: {0}' -f $Source) -ForegroundColor Yellow
        return $false
    }

    if ($Preview) {
        Write-Host ('[preview] {0} -> {1}' -f $Source, $Destination)
        return $true
    }

    $parent = Split-Path -Parent $Destination
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    if ($Type -eq 'dir') {
        Sync-SetupDirectory -Source $Source -Destination $Destination
    }
    else {
        Copy-Item -LiteralPath $Source -Destination $Destination -Force
    }

    Write-Host ('[done] {0} -> {1}' -f $Source, $Destination)
    return $true
}

function Get-SetupGitDirty {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string[]]$RepoPaths
    )

    $git = Get-Command git -ErrorAction SilentlyContinue
    if (-not $git) {
        return @()
    }

    $dirty = @()
    foreach ($path in $RepoPaths) {
        $lines = & git -C $RepoRoot status --short -- $path 2>$null
        if ($lines) {
            $dirty += $lines
        }
    }
    return $dirty
}

function Assert-SetupCleanTargets {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][object[]]$Mappings
    )

    $repoPaths = @($Mappings | ForEach-Object { $_.Repo })
    $dirtyLines = Get-SetupGitDirty -RepoRoot $RepoRoot -RepoPaths $repoPaths
    if ($dirtyLines.Count -eq 0) {
        return
    }

    Write-Host 'Repository target paths have uncommitted changes:' -ForegroundColor Red
    foreach ($line in $dirtyLines) {
        Write-Host ('  {0}' -f $line) -ForegroundColor Red
    }
    throw 'Commit or clear those changes before exporting local configuration.'
}

function Invoke-SetupProfileSync {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][object[]]$Mappings,
        [Parameter(Mandatory)][ValidateSet('Restore', 'Backup')][string]$Direction,
        [Parameter(Mandatory)][string]$Name,
        [switch]$Preview
    )

    Assert-SetupUserProfile
    $RepoRoot = Resolve-SetupRoot -RepoRoot $RepoRoot

    if ($Direction -eq 'Backup' -and -not $Preview) {
        Assert-SetupCleanTargets -RepoRoot $RepoRoot -Mappings $Mappings
    }

    $ok = 0
    $skipped = 0

    foreach ($mapping in $Mappings) {
        if ($Direction -eq 'Restore') {
            $source = Join-Path $RepoRoot $mapping.Repo
            $destination = $mapping.Local
        }
        else {
            $source = $mapping.Local
            $destination = Join-Path $RepoRoot $mapping.Repo
        }

        $synced = Sync-SetupItem -Source $source -Destination $destination -Type $mapping.Type -Preview:$Preview
        if ($synced) {
            $ok++
        }
        else {
            $skipped++
        }
    }

    $mode = if ($Preview) { 'preview complete' } else { 'complete' }
    if ($skipped -gt 0) {
        Write-Host ('{0} {1}: {2} item(s), {3} skipped.' -f $Name, $mode, $ok, $skipped) -ForegroundColor Yellow
    }
    else {
        Write-Host ('{0} {1}: {2} item(s).' -f $Name, $mode, $ok)
    }
}

Export-ModuleMember -Function Assert-SetupUserProfile, Resolve-SetupRoot, Sync-SetupDirectory, Sync-SetupItem, Get-SetupGitDirty, Assert-SetupCleanTargets, Invoke-SetupProfileSync
