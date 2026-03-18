---
name: "enso-review-gate"
description: "Project-specific review and validation workflow for the Enso desktop agent in `D:\\Enso`. Use when asked to review, inspect, validate, audit, or 检定 this repo. Focus on contract drift, stop-condition coverage, permission-boundary regressions, execution-flow correctness, verification gaps, and whether the official scripts actually prove the required behavior."
---

# Enso Review Gate

Use this skill for repo reviews and acceptance checks. Review against the Enso product docs, not generic desktop-app expectations, and make findings the primary output.

## Required review workflow

1. Read the repo docs in the onboarding order:
   - `AGENTS.md`
   - `docs/current-baseline.md`
   - `docs/execution-flow.md`
   - `docs/codebase-contract.md`
2. Run:

```powershell
npm run preflight
npm run verify
```

3. Run the UI regression when the stop conditions or shell behavior matter:

```powershell
npm run test:mvp:ui
```

4. Inspect the implementation paths that most directly affect product behavior:
   - `src/main/core/execution-flow.ts`
   - `src/main/services/*.ts`
   - `src/main/ipc.ts`
   - `src/shared/types.ts`
   - `src/renderer/App.tsx`
   - `package.json`
   - `tests/`

## Review focus

- Does the app preserve the fixed three-panel shell and manual mode switching?
- Does the request path still follow planner -> executor -> verifier instead of collapsing into direct model calls?
- Are retrieval, tool use, gate checks, and verification explicit and visible?
- Are writes bounded to the workspace or converted into proposals?
- Are audits, plan, trace, verification, and pending confirmations persisted and surfaced?
- Do verification scripts actually cover the stop conditions, or only a subset?
- If code changed, were `CHANGELOG.md`, `TODO_LIMITATIONS.md`, and `docs/codebase-contract.md` updated?

## Reporting format

- Present findings first, ordered by severity.
- Include tight file and line references for each finding.
- Call out testing gaps separately when the scripts are green but do not prove a required behavior.
- If no findings remain, say so explicitly and mention residual risks or untested surfaces.
