---
name: "enso-repo-workflow"
description: "Repository-specific workflow for the Enso Electron desktop agent in `D:\\Enso`. Use when implementing, refactoring, or wiring features in this repo, especially when the task touches product behavior, Electron IPC, renderer layout, local persistence, config, docs, or verification flow. Enforce the repo onboarding order, the PREFLIGHT to PLAN to EXECUTE to VERIFY to POSTFLIGHT to DONE lifecycle, mandatory document updates, and stop conditions."
---

# Enso Repo Workflow

Use this skill for substantive work in `D:\Enso`. Build context from the repo documents first, preserve the execution-first product constraints, and treat verification and postflight docs as part of the implementation.

## Required startup

1. In PowerShell, switch the terminal to UTF-8 before reading docs or reviewing diffs:

```powershell
. .\scripts\enable-utf8-terminal.ps1
```

2. Read the repo docs in this order:
   - `AGENTS.md`
   - `docs/current-baseline.md`
   - `docs/execution-flow.md`
   - `docs/codebase-contract.md`
   - `docs/environment-and-github-bootstrap.md`
   - `CLAUDE.md` when the client uses it
3. Run preflight before editing unless the task is explicitly to repair preflight:

```powershell
npm run preflight
```

## Plan the task

- Check `tasks/INDEX.md` for the current backlog.
- State scope and acceptance criteria before editing. Create or update a task file only when it adds value.
- Preserve the product constraints from the docs:
  - fixed three-panel desktop shell
  - default mode plus manual optional modes
  - local-first state, workspace, and audit
  - visible plan, execution trace, and verification
  - bounded tool use and permission-gated writes
  - no automatic mode routing
  - no hidden side effects

## Change guardrails

- Prefer strengthening `planner -> executor -> verifier` over chat polish.
- Keep powerful actions as visible proposals or gated flows unless the repo docs explicitly allow execution.
- Treat `src/main/core/execution-flow.ts`, `src/main/services/`, `src/main/ipc.ts`, `src/shared/types.ts`, and `src/renderer/App.tsx` as the critical path for behavior changes.
- Keep repository text files in UTF-8 and prefer ASCII punctuation in docs when equivalent text is sufficient.
- Do not change the stack casually: Electron, React + TypeScript, Tailwind + shadcn/ui, LangChain.js as helper, better-sqlite3, SQLite, TOML.

## Skill combinations

When you need task-to-skill mapping for this repo, read `references/skill-combos.md`.
Use it to choose the minimal effective combination of Enso-specific skills plus any existing generic skill such as `playwright`, `playwright-interactive`, `gh-fix-ci`, or `gh-address-comments`.

## Verify the work

Run the normal runtime regression:

```powershell
npm run verify
```

Also run the UI regression when the task may affect any stop condition surfaced in the desktop shell:

```powershell
npm run test:mvp:ui
```

Typical triggers for the UI test:
- layout or mode switch changes
- conversation bootstrap and selection changes
- IPC wiring changes
- confirmation or workspace-write flow changes
- right-rail state, plan, trace, or audit rendering changes

## Postflight requirements

After any code change, update all three mandatory docs before reporting completion:
- `CHANGELOG.md`
- `TODO_LIMITATIONS.md`
- `docs/codebase-contract.md`

Then run:

```powershell
npm run postflight
git diff --stat
git diff
```

Treat postflight warnings as defects to address, not optional follow-ups.
