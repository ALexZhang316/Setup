@echo off
setlocal
set "SELF=%~f0"
set "TMPPS=%TEMP%\Install-Claude-Code-Profile-%RANDOM%%RANDOM%.ps1"

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

$repoRoot = Split-Path -Parent $env:SELF
$settingsSourcePath = Join-Path $repoRoot 'claude-code-profile\settings.json'
$claudeRoot = Join-Path $env:USERPROFILE '.claude'
$settingsTargetPath = Join-Path $claudeRoot 'settings.json'

if (-not (Test-Path -LiteralPath $settingsSourcePath)) {
    throw "未找到配置快照：$settingsSourcePath"
}

Ensure-Directory -Path $claudeRoot

Copy-Item -LiteralPath $settingsSourcePath -Destination $settingsTargetPath -Force

Write-Host 'Claude Code 配置快照已恢复完成。'
Write-Host ("settings.json -> {0}" -f $settingsTargetPath)
