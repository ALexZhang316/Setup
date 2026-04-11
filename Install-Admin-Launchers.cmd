@echo off
setlocal
for %%I in ("%~dp0.") do set "REPO_ROOT=%%~fI"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%REPO_ROOT%\tools\Install-Admin-Launchers.ps1" -RepoRoot "%REPO_ROOT%"
set "EXIT_CODE=%ERRORLEVEL%"
if not "%EXIT_CODE%"=="0" (
    echo.
    echo Failed with exit code %EXIT_CODE%.
    pause
)
exit /b %EXIT_CODE%
