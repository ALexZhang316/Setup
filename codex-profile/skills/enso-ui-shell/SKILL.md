---
name: "enso-ui-shell"
description: "Renderer-shell workflow for the Enso desktop agent in `D:\\Enso`. Use when changing the fixed three-panel layout, conversation rail, mode switcher, center-pane views, composer, right-rail status panels, or any UI that reflects execution state, audit, plan, trace, verification, or pending actions."
---

# Enso UI Shell

Use this skill when changing the Electron renderer shell. Preserve the product shape first: three panels, manual mode switching, visible execution state, and a center chat control surface.

## Main files

- `src/renderer/App.tsx`
- `src/renderer/index.css`
- `src/renderer/components/ui/*`
- `src/shared/bridge.ts`
- `src/shared/modes.ts`
- `src/shared/types.ts`
- `src/main/preload.ts`
- `src/main/ipc.ts`
- `tests/mvp.ui.test.cjs`

## UI invariants

- Keep the fixed three-panel structure.
- Keep default mode plus mutually exclusive optional modes.
- Do not hide plan, trace, verification, audit, or pending-action state when the backend provides them.
- Keep request submission and confirmation flows visible and legible.
- Keep the shell usable on desktop widths and avoid breaking the existing test ids unless you update tests with intent.

## Preferred workflow

1. Read `docs/ui-layout.md` and `docs/windows-product-spec.md` if the change is structural.
2. Update shared types or bridge contracts first when the UI depends on new data.
3. Update `App.tsx` with minimal churn to existing interaction paths.
4. Preserve `data-testid` hooks that the UI regression depends on.
5. Capture a screenshot or run the UI regression after meaningful shell changes.

## Verification

Always run:

```powershell
npm run test:mvp:ui
```

Also run:

```powershell
npm run verify
```

Spot-check these behaviors when relevant:
- mode switching, including return to default mode
- conversation creation, selection, rename, delete, and pin
- settings view and audit view toggles
- composer send flow
- pending confirmation flow
- right-rail rendering of plan, trace, verification, evidence, state, and audit
