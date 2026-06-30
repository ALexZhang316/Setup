---
name: elevated-runner
description: Install and use a Windows scheduled-task based elevated command runner for Codex. Use when a task needs administrator rights from a normal Codex shell, when access is denied and the operation is approved, or when Codex needs to queue a PowerShell command through the local elevated runner and inspect its logs.
---

# Elevated Runner

## Overview

Use this skill to install and call the local elevated runner from Codex on Windows. The runner queues a PowerShell script in `%LOCALAPPDATA%\SetupElevatedRunner\queue`, triggers the `Setup Elevated Runner` scheduled task, and writes stdout, stderr, and exit code logs under `%LOCALAPPDATA%\SetupElevatedRunner\logs`.

## Workflow

1. Try the normal shell first unless administrator rights are clearly required.
2. Before using elevation, verify the operation is appropriate for an administrator token. Ask the user before irreversible or destructive changes.
3. If the runner is missing, install it:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\elevated-runner\scripts\install.ps1"
```

4. Queue one inline PowerShell command and wait for completion:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\elevated-runner\scripts\new-job.ps1" -Command "net session" -Wait
```

5. For multi-line work, write or identify a `.ps1` script, then queue it:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\elevated-runner\scripts\new-job.ps1" -ScriptPath "C:\Path\To\script.ps1" -Wait
```

## Scripts

- `scripts\install.ps1` installs or refreshes the scheduled task and copies `runner.ps1` into `%LOCALAPPDATA%\SetupElevatedRunner`.
- `scripts\new-job.ps1` creates a queue JSON file, triggers the task, and optionally waits for the final exit code.
- `scripts\runner.ps1` runs queued scripts with the scheduled task's administrator token and records logs.

## Verification

Use a harmless command to verify elevation:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\elevated-runner\scripts\new-job.ps1" -Command "$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent()); $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)" -Wait
```

Expected stdout includes `True` and `ExitCode=0`.
