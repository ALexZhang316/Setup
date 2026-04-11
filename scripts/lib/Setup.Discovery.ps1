$ErrorActionPreference = 'Stop'

function Add-UniquePath {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Seen,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
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
    }
    else {
        $normalizedPath = $Path
    }

    if ($Seen.ContainsKey($normalizedPath)) {
        return
    }

    $Seen[$normalizedPath] = $true
    $Paths.Add($normalizedPath) | Out-Null
}

function Get-VersionLikeDirectoryOrder {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.DirectoryInfo[]]$Directories
    )

    $decoratedDirectories = foreach ($directory in $Directories) {
        $name = $directory.Name.Trim()
        $versionCandidate = $name.TrimStart('v', 'V')
        $numericPart = $versionCandidate
        $suffix = ''

        if ($versionCandidate -match '^([0-9]+(?:\.[0-9]+){0,3})(.*)$') {
            $numericPart = $matches[1]
            $suffix = $matches[2]
        }

        $version = $null
        $isVersion = [version]::TryParse($numericPart, [ref]$version)
        [pscustomobject]@{
            Directory = $directory
            IsVersion = if ($isVersion) { 1 } else { 0 }
            Version = if ($isVersion) { $version } else { [version]'0.0' }
            HasSuffix = if ([string]::IsNullOrWhiteSpace($suffix)) { 0 } else { 1 }
            Name = $name
        }
    }

    return @(
        $decoratedDirectories |
            Sort-Object `
                @{ Expression = { $_.IsVersion }; Descending = $true },
                @{ Expression = { $_.Version }; Descending = $true },
                @{ Expression = { $_.HasSuffix }; Descending = $false },
                @{ Expression = { $_.Name }; Descending = $true } |
            ForEach-Object { $_.Directory }
    )
}

function Get-GitCommand {
    $command = Get-Command 'git.exe', 'git' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) {
        return $command.Source
    }

    return $null
}

function Get-DesktopDirectory {
    $desktopPath = [Environment]::GetFolderPath([Environment+SpecialFolder]::DesktopDirectory)
    if ([string]::IsNullOrWhiteSpace($desktopPath)) {
        return (Join-Path $env:USERPROFILE 'Desktop')
    }

    return $desktopPath
}

function Get-CodexExecutablePath {
    $candidates = New-Object 'System.Collections.Generic.List[string]'
    $seen = @{}

    $command = Get-Command 'codex.exe', 'codex' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command -and $command.Source) {
        Add-UniquePath -Seen $seen -Paths $candidates -Path $command.Source -RequireExists
    }

    foreach ($pkg in @(Get-AppxPackage 'OpenAI.Codex' -ErrorAction SilentlyContinue | Sort-Object Version -Descending)) {
        Add-UniquePath -Seen $seen -Paths $candidates -Path (Join-Path $pkg.InstallLocation 'app\Codex.exe') -RequireExists
    }

    Add-UniquePath -Seen $seen -Paths $candidates -Path (Join-Path $env:LOCALAPPDATA 'Programs\Codex\Codex.exe') -RequireExists
    if ($env:ProgramFiles) {
        Add-UniquePath -Seen $seen -Paths $candidates -Path (Join-Path $env:ProgramFiles 'Codex\Codex.exe') -RequireExists
    }
    if (${env:ProgramFiles(x86)}) {
        Add-UniquePath -Seen $seen -Paths $candidates -Path (Join-Path ${env:ProgramFiles(x86)} 'Codex\Codex.exe') -RequireExists
    }

    return $candidates | Select-Object -First 1
}

function Get-ClaudeCliPath {
    $command = Get-Command 'claude', 'claude.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command -and $command.Source) {
        return $command.Source
    }

    $candidates = New-Object 'System.Collections.Generic.List[string]'
    $seen = @{}

    $appDataCliRoot = Join-Path $env:APPDATA 'Claude\claude-code'
    if (Test-Path -LiteralPath $appDataCliRoot) {
        foreach ($versionDir in Get-VersionLikeDirectoryOrder -Directories @(Get-ChildItem -LiteralPath $appDataCliRoot -Directory -ErrorAction SilentlyContinue)) {
            Add-UniquePath -Seen $seen -Paths $candidates -Path (Join-Path $versionDir.FullName 'claude.exe') -RequireExists
        }
    }

    $packagesRoot = Join-Path $env:LOCALAPPDATA 'Packages'
    if (Test-Path -LiteralPath $packagesRoot) {
        foreach ($packageDir in Get-ChildItem -LiteralPath $packagesRoot -Directory -ErrorAction SilentlyContinue) {
            if ($packageDir.Name -notlike 'Claude*') {
                continue
            }

            $cliRoot = Join-Path $packageDir.FullName 'LocalCache\Roaming\Claude\claude-code'
            if (-not (Test-Path -LiteralPath $cliRoot)) {
                continue
            }

            foreach ($versionDir in Get-VersionLikeDirectoryOrder -Directories @(Get-ChildItem -LiteralPath $cliRoot -Directory -ErrorAction SilentlyContinue)) {
                Add-UniquePath -Seen $seen -Paths $candidates -Path (Join-Path $versionDir.FullName 'claude.exe') -RequireExists
            }
        }
    }

    return $candidates | Select-Object -First 1
}

function Get-ClaudeDesktopRoots {
    param(
        [switch]$IncludeDefaultAppData
    )

    $roots = New-Object 'System.Collections.Generic.List[string]'
    $seen = @{}
    $appDataRoot = Join-Path $env:APPDATA 'Claude'

    if ($IncludeDefaultAppData) {
        Add-UniquePath -Seen $seen -Paths $roots -Path $appDataRoot
    }
    else {
        Add-UniquePath -Seen $seen -Paths $roots -Path $appDataRoot -RequireExists
    }

    $packagesRoot = Join-Path $env:LOCALAPPDATA 'Packages'
    if (Test-Path -LiteralPath $packagesRoot) {
        foreach ($packageDir in Get-ChildItem -LiteralPath $packagesRoot -Directory -ErrorAction SilentlyContinue) {
            if ($packageDir.Name -notlike 'Claude*') {
                continue
            }

            $candidateRoot = Join-Path $packageDir.FullName 'LocalCache\Roaming\Claude'
            Add-UniquePath -Seen $seen -Paths $roots -Path $candidateRoot -RequireExists
        }
    }

    return $roots.ToArray()
}

function Get-CanonicalClaudeDesktopRoot {
    $appDataRoot = Join-Path $env:APPDATA 'Claude'
    if (Test-Path -LiteralPath $appDataRoot) {
        return (Resolve-Path -LiteralPath $appDataRoot).Path
    }

    $packagedRoots = @(Get-ClaudeDesktopRoots | Where-Object { $_ -ne $appDataRoot } | Sort-Object)
    return $packagedRoots | Select-Object -First 1
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

    $command = Get-Command AutoHotkey64.exe, AutoHotkey.exe, AutoHotkey -ErrorAction SilentlyContinue | Select-Object -First 1
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
    $resolved = @()
    foreach ($app in @(
        [pscustomobject]@{ Id = 'codex'; DisplayName = 'Codex' },
        [pscustomobject]@{ Id = 'claude'; DisplayName = 'Claude' }
    )) {
        $exePath = Resolve-AppExecutablePath -AppId $app.Id
        if ($exePath) {
            $resolved += [pscustomobject]@{
                Id = $app.Id
                DisplayName = $app.DisplayName
                Path = $exePath
            }
        }
    }

    return $resolved
}
