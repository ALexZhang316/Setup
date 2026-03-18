---
name: "enso-doc-postflight"
description: "Mandatory documentation and postflight workflow for code changes in the Enso desktop agent repo at `D:\\Enso`. Use after any code edit to update the required repo docs, run postflight, and check that the documented contract still matches the code and tests."
---

# Enso Doc Postflight

Use this skill after code changes in `D:\Enso`. In this repo, postflight documentation is part of done, not optional cleanup.

## Required docs

Update all three after any code change:

- `CHANGELOG.md`
- `TODO_LIMITATIONS.md`
- `docs/codebase-contract.md`

Also update these when the change obviously affects them:
- `README.md`
- `AGENTS.md`
- `CLAUDE.md`
- `docs/current-baseline.md`
- `docs/execution-flow.md`

## What to write

### `CHANGELOG.md`

- Record what changed and why.
- Keep it concrete.
- Mention behavior, verification, and user-visible impact over internal trivia.

### `TODO_LIMITATIONS.md`

- Add new known limitations introduced by the change.
- Mark resolved items when the change removed a limitation.
- Do not pretend a rough edge is solved if tests or UX still leave it open.

### `docs/codebase-contract.md`

- Update runtime notes, module registry, schema, directory structure, and known issues when they changed.
- Prefer actual code over stale prose. If the doc drifted, fix the doc before handing off.

## Postflight sequence

1. Update the mandatory docs.
2. Run:

```powershell
npm run postflight
```

3. Review the diff:

```powershell
git diff --stat
git diff
```

4. Confirm the docs match the actual implementation and current tests.

## Common failure modes

- Code changed but one of the mandatory docs did not.
- `docs/codebase-contract.md` still describes an old schema or module list.
- `verify` is green but the docs claim stronger coverage than the scripts actually provide.
- Limitations were silently resolved or introduced without updating `TODO_LIMITATIONS.md`.
