# Setup

Windows AI development configuration backup and restore repository.

This repository manages only two product profiles:

- Codex
- Claude Code

## Structure

```text
codex/
  profile/                    Snapshot for %USERPROFILE%\.codex
  restore.ps1                 Restore Codex profile
  backup.ps1                  Export Codex profile
claudecode/
  profile/                    Snapshot for %USERPROFILE%\.claude
  restore.ps1                 Restore Claude Code profile
  backup.ps1                  Export Claude Code profile
scripts/
  restore-all.ps1             Restore Codex, then Claude Code
  backup-all.ps1              Export Codex, then Claude Code
shared/
  Sync-Core.psm1              Shared sync helpers
  hotkey/install.ps1          Chat hotkey installer
```

## Entrypoints

| Command | Purpose |
| --- | --- |
| `restore-all.cmd` | Restore Codex, then Claude Code |
| `backup-all.cmd` | Export Codex, then Claude Code |
| `codex\restore.cmd` | Restore only Codex |
| `codex\backup.cmd` | Export only Codex |
| `claudecode\restore.cmd` | Restore only Claude Code |
| `claudecode\backup.cmd` | Export only Claude Code |
| `hotkey.cmd` | Install Enter newline / Ctrl+Enter send remap |

All sync PowerShell scripts support `-Preview`:

```powershell
.\scripts\restore-all.ps1 -Preview
.\codex\backup.ps1 -Preview
.\claudecode\restore.ps1 -Preview
```

Preview mode prints the planned source and destination paths without writing files.

## Path Mapping

| Repository path | Local path |
| --- | --- |
| `codex\profile\AGENTS.md` | `%USERPROFILE%\.codex\AGENTS.md` |
| `codex\profile\config.toml` | `%USERPROFILE%\.codex\config.toml` |
| `codex\profile\skills\` | `%USERPROFILE%\.codex\skills\` |
| `claudecode\profile\CLAUDE.md` | `%USERPROFILE%\.claude\CLAUDE.md` |
| `claudecode\profile\settings.json` | `%USERPROFILE%\.claude\settings.json` |

## First Machine Setup

1. Install Git, Codex, and Claude Code.
2. Launch Codex and Claude Code once so their user directories exist.
3. Clone this repository to `D:\Setup`.
4. Run `restore-all.cmd`.
5. Restart Codex and Claude Code.

## Daily Sync

Export local changes:

```powershell
.\backup-all.cmd
git status --short
git add .
git commit -m "Update setup profiles"
git push
```

Restore on another machine:

```powershell
git pull
.\restore-all.cmd
```

## Hotkey

Install:

```powershell
.\hotkey.cmd
```

The remap applies to chat windows:

- `Enter` inserts a newline.
- `Ctrl+Enter` sends the message.
