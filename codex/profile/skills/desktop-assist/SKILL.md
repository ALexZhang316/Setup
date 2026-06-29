---
name: desktop-assist
description: Windows desktop task assistance for launching common apps, managing windows, capturing screenshots, sorting local files, preparing browser automation, and routing mail, calendar, and cloud-document work through installed plugins first. Use when Codex should help with non-coding desktop workflows, repetitive office routines, browser or Electron tasks, window focus problems, download-folder cleanup, or lightweight AutoHotkey automation on Windows.
---

# Desktop Assist

Use this skill to turn ad hoc Windows desktop work into stable scripted entry points.

## Plugin-first rule

Before operating a desktop client, prefer the installed plugins for:

- Gmail
- Google Calendar
- Google Drive
- GitHub

Use desktop apps when the task is local-only, file-based, or genuinely GUI-specific.

## Quick start

Install or refresh app launchers:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\desktop-assist\scripts\install-launchers.ps1"
```

List supported launch targets:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\desktop-assist\scripts\launch-app.ps1" -List
```

List visible windows:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\desktop-assist\scripts\list-windows.ps1"
```

Focus a window by title:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\desktop-assist\scripts\focus-window.ps1" -Title "Word"
```

Capture the active window:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\desktop-assist\scripts\capture-desktop.ps1" -ActiveWindow -Mode temp
```

Preview download-folder cleanup without moving files:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\desktop-assist\scripts\sort-downloads.ps1"
```

Apply the cleanup:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\desktop-assist\scripts\sort-downloads.ps1" -Apply
```

Prepare the dedicated Playwright workspace for browser and Electron work:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\desktop-assist\scripts\prepare-playwright.ps1"
```

## Core workflow

1. Decide whether the task is better served by a plugin, local file manipulation, browser automation, or direct desktop automation.
2. Launch the app through `launch-app.ps1` or the installed command shims, not through ad hoc path hunting.
3. Use `list-windows.ps1` and `focus-window.ps1` for window discovery and activation before escalating to AutoHotkey.
4. Use `capture-desktop.ps1` or the `screenshot` skill for visual inspection.
5. For browser and Electron workflows, use `playwright-interactive` after enabling `js_repl` and restarting Codex.
6. For repetitive keyboard-driven actions, run the bundled AutoHotkey scripts through `run-ahk.ps1`.
7. For folder cleanup, preview first and apply second. Do not move files blindly.

## Resources

- `scripts/install-launchers.ps1`: creates stable user-level command shims for common desktop apps.
- `scripts/launch-app.ps1`: launches supported apps or common folders from a stable name.
- `scripts/list-windows.ps1`: enumerates visible top-level windows.
- `scripts/focus-window.ps1`: activates a window by title, process, or handle.
- `scripts/capture-desktop.ps1`: wraps the existing screenshot skill's Windows helper.
- `scripts/sort-downloads.ps1`: previews or applies file organization for Downloads or another folder.
- `scripts/prepare-playwright.ps1`: prepares a dedicated browser automation workspace with Playwright.
- `scripts/run-ahk.ps1`: runs bundled AutoHotkey scripts through the installed runtime.
- `scripts/ahk/desktop-hotkeys.ahk`: sample hotkeys for common desktop launch and folder actions.
- `references/task-recipes.md`: task patterns and when to use plugin, browser, file, or GUI routes.

## Limits

- Do not rely on pixel-perfect clicking unless there is no better stable control path.
- Do not use desktop apps for Gmail, Calendar, Drive, or GitHub when the plugin can do the job more reliably.
- Do not move or rename user files without previewing the plan first unless the user explicitly asks for direct apply.
