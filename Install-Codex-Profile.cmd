@echo off
setlocal
set "SELF=%~f0"
set "TMPPS=%TEMP%\Install-Codex-Profile-%RANDOM%%RANDOM%.ps1"

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$content = Get-Content -LiteralPath $env:SELF -Raw; " ^
  "$marker = ':__POWERSHELL_PAYLOAD__'; " ^
  "$index = $content.LastIndexOf($marker); " ^
  "if ($index -lt 0) { throw 'Marker not found.' }; " ^
  "$script = $content.Substring($index + $marker.Length).TrimStart([char]13, [char]10); " ^
  "$utf8NoBom = New-Object System.Text.UTF8Encoding($false); " ^
  "[System.IO.File]::WriteAllText($env:TMPPS, $script, $utf8NoBom)"
if errorlevel 1 goto :prepare_fail

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%TMPPS%" "%SELF%"
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

:__POWERSHELL_PAYLOAD__
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

function Get-CodexExecutablePath {
    $candidates = New-Object 'System.Collections.Generic.List[string]'
    $seen = @{}

    $command = Get-Command 'codex.exe', 'codex' -ErrorAction SilentlyContinue |
        Select-Object -First 1
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

function Fail-Install {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Write-Host ''
    Write-Host 'Codex 配置安装失败。' -ForegroundColor Red
    Write-Host ("  {0}" -f $Message) -ForegroundColor Red
    exit 1
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

try {
    $selfPath = $args[0]
    if (-not $selfPath) {
        throw '安装脚本缺少启动参数。请直接运行 .cmd 文件，不要单独运行内部临时 .ps1。'
    }

    $repoRoot = Split-Path -Parent $selfPath
    $profileRoot = Join-Path $repoRoot 'codex-profile'
    $configSourcePath = Join-Path $profileRoot 'config.toml'
    $agentsSourcePath = Join-Path $profileRoot 'AGENTS.md'
    $skillsSourcePath = Join-Path $profileRoot 'skills'
    $codexRoot = Join-Path $env:USERPROFILE '.codex'
    $configTargetPath = Join-Path $codexRoot 'config.toml'
    $agentsTargetPath = Join-Path $codexRoot 'AGENTS.md'
    $skillsTargetPath = Join-Path $codexRoot 'skills'

    if (-not (Test-Path -LiteralPath $configSourcePath)) {
        throw "未找到仓库内的 Codex 配置快照：$configSourcePath"
    }

    if (-not (Test-Path -LiteralPath $agentsSourcePath)) {
        throw "未找到仓库内的 Codex 全局指令文件：$agentsSourcePath"
    }

    if (-not (Test-Path -LiteralPath $skillsSourcePath)) {
        throw "未找到仓库内的 Codex skills 快照：$skillsSourcePath"
    }

    Write-Host '开始检查前置条件...'
    $codexExe = Get-CodexExecutablePath
    if (-not $codexExe) {
        throw '未检测到 Codex 可执行文件。请先安装 Codex，并至少启动一次后完全退出，再运行本脚本。'
    }
    Write-Host ("  Codex -> {0}" -f $codexExe)

    Ensure-Directory -Path $codexRoot

    Copy-Item -LiteralPath $configSourcePath -Destination $configTargetPath -Force
    Copy-Item -LiteralPath $agentsSourcePath -Destination $agentsTargetPath -Force
    Sync-DirectorySnapshot -SourcePath $skillsSourcePath -DestinationPath $skillsTargetPath

    Write-Host ''
    Write-Host 'Codex 配置恢复完成。'
    Write-Host ("  config.toml -> {0}" -f $configTargetPath)
    Write-Host ("  AGENTS.md -> {0}" -f $agentsTargetPath)
    Write-Host ("  skills -> {0}" -f $skillsTargetPath)
    Write-Host '  如果 Codex 当前正在运行，请完全退出后重新打开。'
}
catch {
    Fail-Install -Message $_.Exception.Message
}
