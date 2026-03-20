@echo off
setlocal
set "SELF=%~f0"
set "TMPPS=%TEMP%\Install-Codex-Profile-%RANDOM%%RANDOM%.ps1"

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$content = Get-Content -LiteralPath '%SELF%' -Raw; " ^
  "$marker = ':__POWERSHELL_PAYLOAD__'; " ^
  "$index = $content.LastIndexOf($marker); " ^
  "if ($index -lt 0) { throw 'Marker not found.' }; " ^
  "$script = $content.Substring($index + $marker.Length).TrimStart([char]13, [char]10); " ^
  "$utf8NoBom = New-Object System.Text.UTF8Encoding($false); " ^
  "[System.IO.File]::WriteAllText('%TMPPS%', $script, $utf8NoBom)"
if errorlevel 1 goto :prepare_fail

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%TMPPS%" "%SELF%"
set "EXIT_CODE=%ERRORLEVEL%"

del /q "%TMPPS%" >nul 2>nul

if not "%EXIT_CODE%"=="0" (
    echo.
    echo Install failed with exit code %EXIT_CODE%.
    pause
)

exit /b %EXIT_CODE%

:prepare_fail
echo Failed to prepare installer payload.
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

$selfPath = $args[0]
if (-not $selfPath) {
    throw 'Installer path argument missing.'
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
    throw "Missing config snapshot: $configSourcePath"
}

if (-not (Test-Path -LiteralPath $agentsSourcePath)) {
    throw "Missing global instructions snapshot: $agentsSourcePath"
}

if (-not (Test-Path -LiteralPath $skillsSourcePath)) {
    throw "Missing skills snapshot: $skillsSourcePath"
}

Ensure-Directory -Path $codexRoot

Copy-Item -LiteralPath $configSourcePath -Destination $configTargetPath -Force
Copy-Item -LiteralPath $agentsSourcePath -Destination $agentsTargetPath -Force

if (Test-Path -LiteralPath $skillsTargetPath) {
    Remove-Item -LiteralPath $skillsTargetPath -Recurse -Force
}

Copy-Item -LiteralPath $skillsSourcePath -Destination $skillsTargetPath -Recurse -Force

Write-Host 'Codex profile restored.'
Write-Host ("config.toml -> {0}" -f $configTargetPath)
Write-Host ("AGENTS.md -> {0}" -f $agentsTargetPath)
Write-Host ("skills -> {0}" -f $skillsTargetPath)
