param(
    [string]$Path,
    [ValidateSet("default", "temp")][string]$Mode = "default",
    [string]$Format = "png",
    [string]$Region,
    [switch]$ActiveWindow,
    [int]$WindowHandle
)

$ErrorActionPreference = "Stop"

$screenshotScript = Join-Path $env:USERPROFILE ".codex\skills\screenshot\scripts\take_screenshot.ps1"
if (-not (Test-Path -LiteralPath $screenshotScript)) {
    throw "Screenshot helper not found: $screenshotScript"
}

$invokeArgs = @(
    "-ExecutionPolicy", "Bypass",
    "-File", $screenshotScript,
    "-Mode", $Mode,
    "-Format", $Format
)

if ($Path) {
    $invokeArgs += @("-Path", $Path)
}
if ($Region) {
    $invokeArgs += @("-Region", $Region)
}
if ($ActiveWindow) {
    $invokeArgs += "-ActiveWindow"
}
if ($WindowHandle) {
    $invokeArgs += @("-WindowHandle", $WindowHandle)
}

& powershell @invokeArgs
