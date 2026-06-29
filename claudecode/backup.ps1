param(
    [string]$RepoRoot,
    [switch]$Preview
)

$ErrorActionPreference = 'Stop'

if (-not $RepoRoot) {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
}

Import-Module (Join-Path $RepoRoot 'shared\Sync-Core.psm1') -Force

$mappings = @(
    @{ Repo = 'claudecode\profile\CLAUDE.md'; Local = (Join-Path $env:USERPROFILE '.claude\CLAUDE.md'); Type = 'file' }
    @{ Repo = 'claudecode\profile\settings.json'; Local = (Join-Path $env:USERPROFILE '.claude\settings.json'); Type = 'file' }
)

Invoke-SetupProfileSync -RepoRoot $RepoRoot -Mappings $mappings -Direction Backup -Name 'Claude Code backup' -Preview:$Preview
