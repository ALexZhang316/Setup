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
    @{ Repo = 'codex\profile\AGENTS.md'; Local = (Join-Path $env:USERPROFILE '.codex\AGENTS.md'); Type = 'file' }
    @{ Repo = 'codex\profile\config.toml'; Local = (Join-Path $env:USERPROFILE '.codex\config.toml'); Type = 'file' }
    @{ Repo = 'codex\profile\skills'; Local = (Join-Path $env:USERPROFILE '.codex\skills'); Type = 'dir' }
)

Invoke-SetupProfileSync -RepoRoot $RepoRoot -Mappings $mappings -Direction Restore -Name 'Codex restore' -Preview:$Preview
