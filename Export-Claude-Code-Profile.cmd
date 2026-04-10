@echo off
setlocal
set "REPO_ROOT=%~dp0"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%REPO_ROOT%scripts\export\Export-Claude-Code-Profile.ps1" -RepoRoot "%REPO_ROOT%"
set "EXIT_CODE=%ERRORLEVEL%"

if not "%EXIT_CODE%"=="0" (
    echo.
    echo 导出失败，退出码 %EXIT_CODE%。
    pause
)

exit /b %EXIT_CODE%
