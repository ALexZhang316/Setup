param(
    [string]$Workspace = "$env:USERPROFILE\.codex\playwright-desktop-assist",
    [switch]$SkipBrowserInstall
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    throw "npm is required to prepare the Playwright workspace."
}

New-Item -ItemType Directory -Force -Path $Workspace | Out-Null
Push-Location $Workspace
try {
    if (-not (Test-Path -LiteralPath (Join-Path $Workspace "package.json"))) {
        npm init -y | Out-Null
    }

    npm install playwright | Out-Null

    if (-not $SkipBrowserInstall) {
        npx playwright install chromium | Out-Null
    }

    node -e "import('playwright').then(() => console.log('playwright import ok')).catch((error) => { console.error(error); process.exit(1); })"
} finally {
    Pop-Location
}
