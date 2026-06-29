param(
    [string]$RepoRoot,
    [switch]$Preview
)

$ErrorActionPreference = 'Stop'

if (-not $RepoRoot) {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

& (Join-Path $RepoRoot 'codex\restore.ps1') -RepoRoot $RepoRoot -Preview:$Preview
& (Join-Path $RepoRoot 'claudecode\restore.ps1') -RepoRoot $RepoRoot -Preview:$Preview
