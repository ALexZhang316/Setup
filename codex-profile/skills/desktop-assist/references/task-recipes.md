# Desktop Task Recipes

## Choose the right route

- Gmail, Calendar, Drive, GitHub: use the installed plugins first.
- Browser form filling, web admin panels, Electron apps: use `playwright-interactive` after `js_repl` is enabled and the Playwright workspace is prepared.
- Local documents and spreadsheets: use the `doc` and `spreadsheet` skills, not Office GUI clicks, unless the task is visual inspection only.
- Window switching, app launching, screenshots, file cleanup: use this skill's PowerShell scripts.
- Repetitive keyboard-driven actions inside Windows apps: use the bundled AutoHotkey script or add a new focused macro.

## Common tasks

### Morning setup

1. Use Calendar and Gmail plugins for the agenda and inbox triage.
2. Launch Chrome, OneNote, and Word from `launch-app.ps1`.
3. Use `focus-window.ps1` if the needed app is already open.

### Screenshot-based help

1. Capture the active app with `capture-desktop.ps1 -ActiveWindow -Mode temp`.
2. Inspect the image or hand it back to the user.
3. If the app is a browser or Electron app, switch to the browser route for deterministic control.

### Download cleanup

1. Run `sort-downloads.ps1` without `-Apply`.
2. Review the preview lines.
3. Re-run with `-Apply` only when the plan is correct.

### Office handoff

1. Launch `word`, `excel`, or `powerpoint` through the shims or `launch-app.ps1`.
2. Prefer file-level edits for content changes.
3. Use desktop focus and screenshots only when layout or on-screen behavior matters.

### Browser and Electron preparation

1. Ensure `[features] js_repl = true` in `config.toml`.
2. Run `prepare-playwright.ps1`.
3. Restart Codex so the `js_repl` tool list refreshes.
4. Use `playwright-interactive` for persistent browser or Electron work.
