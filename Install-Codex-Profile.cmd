@echo off
setlocal
set "SELF=%~f0"
set "TMPPS=%TEMP%\Install-Codex-Profile-%RANDOM%%RANDOM%.ps1"

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$content = Get-Content -LiteralPath $env:SELF -Raw; $marker = ':__POWERSHELL_PAYLOAD__'; $index = $content.LastIndexOf($marker); if ($index -lt 0) { throw 'Marker not found.' }; $script = $content.Substring($index + $marker.Length).TrimStart([char]13, [char]10); $utf8NoBom = New-Object System.Text.UTF8Encoding($false); [System.IO.File]::WriteAllText($env:TMPPS, $script, $utf8NoBom)"
if errorlevel 1 goto :prepare_fail

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%TMPPS%"
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

function Test-CodexRunning {
    $process = Get-Process -Name 'Codex' -ErrorAction SilentlyContinue |
        Select-Object -First 1

    return $null -ne $process
}

$repoRoot = Split-Path -Parent $env:SELF
$profileRoot = Join-Path $repoRoot 'codex-profile'
$configSourcePath = Join-Path $profileRoot 'config.toml'
$skillsSourcePath = Join-Path $profileRoot 'skills'
$codexRoot = Join-Path $env:USERPROFILE '.codex'
$configTargetPath = Join-Path $codexRoot 'config.toml'
$skillsTargetPath = Join-Path $codexRoot 'skills'

if (-not (Test-Path -LiteralPath $configSourcePath)) {
    throw "未找到配置快照：$configSourcePath"
}

if (-not (Test-Path -LiteralPath $skillsSourcePath)) {
    throw "未找到技能快照：$skillsSourcePath"
}

if (Test-CodexRunning) {
    throw '检测到 Codex 正在运行，请先关闭 Codex 再执行此脚本。'
}

Ensure-Directory -Path $codexRoot

Copy-Item -LiteralPath $configSourcePath -Destination $configTargetPath -Force

if (Test-Path -LiteralPath $skillsTargetPath) {
    Remove-Item -LiteralPath $skillsTargetPath -Recurse -Force
}

Copy-Item -LiteralPath $skillsSourcePath -Destination $skillsTargetPath -Recurse -Force

Write-Host 'Codex 配置快照已恢复完成。'
Write-Host ("config.toml -> {0}" -f $configTargetPath)
Write-Host ("skills -> {0}" -f $skillsTargetPath)
