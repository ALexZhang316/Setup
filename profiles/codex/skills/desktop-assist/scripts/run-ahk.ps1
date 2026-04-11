param(
    [string]$Script = "$env:USERPROFILE\.codex\skills\desktop-assist\scripts\ahk\desktop-hotkeys.ahk",
    [string[]]$Args
)

$ErrorActionPreference = "Stop"

$runtime = "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
if (-not (Test-Path -LiteralPath $runtime)) {
    throw "AutoHotkey runtime not found: $runtime"
}

if (-not (Test-Path -LiteralPath $Script)) {
    throw "AutoHotkey script not found: $Script"
}

& $runtime $Script @Args
