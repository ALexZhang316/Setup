---
name: "enso-execution-kernel"
description: "Execution-core guidance for the Enso desktop agent in `D:\\Enso`. Use when changing or reviewing the planner-executor-verifier chain, request classification, retrieval, typed tools, workspace writes, permission gates, trace persistence, IPC runtime wiring, or the right-rail plan/trace/verification UI."
---

# Enso Execution Kernel

Use this skill when the task touches the main request pipeline or any state that the user must see in the right rail. Preserve the single-request flow from the repo docs and keep all side effects explicit, bounded, and verifiable.

## Critical files

- `src/main/core/execution-flow.ts`
- `src/main/services/config-service.ts`
- `src/main/services/knowledge-service.ts`
- `src/main/services/tool-service.ts`
- `src/main/services/workspace-service.ts`
- `src/main/services/store.ts`
- `src/main/ipc.ts`
- `src/shared/types.ts`
- `src/shared/modes.ts`
- `src/renderer/App.tsx`
- `tests/mvp.integration.test.cjs`
- `tests/mvp.ui.test.cjs`

## Runtime invariants

- Classify the request locally and never auto-switch modes.
- Keep the plan explicit and inspectable when the turn is not pure dialogue.
- Make retrieval and tool decisions explicit and bounded.
- Keep host exec, destructive actions, and workspace-external writes behind a visible gate.
- Never claim success without verification or an explicit note that verification was skipped.
- Persist enough state to reconstruct the latest plan, trace, verification result, audit summary, and pending action.
- Surface plan, trace, verification, evidence, pending action, state, and audit in the renderer when those concepts exist for the turn.

## Change sequence

1. Update shared types and persistence first when state shape changes.
2. Update the execution flow and supporting services.
3. Update IPC and preload if the renderer contract changes.
4. Update the right-rail renderer when the visible state surface changes.
5. Add or adjust regression tests for the new path.

## High-risk areas

- Keep action detection narrow enough to distinguish discussion about an action from a request to perform the action.
- Validate config values by allowed enum/type, not just by TOML parse success.
- Keep workspace writes inside the Enso workspace root and verify the artifact exists after writing.
- Fail verification explicitly when evidence or tool output is required but absent.
- Keep audit and state writes aligned so the latest user-visible state matches the persisted trace.

## Verification checklist

Run:

```powershell
npm run verify
```

Also run:

```powershell
npm run test:mvp:ui
```

Cover these scenarios when relevant:
- default mode stays distinct from optional modes
- retrieval follows config defaults and per-turn override rules
- retrieval-required turns fail verification when evidence is missing
- tool-required turns fail verification when tool output is missing
- workspace write requests become proposals, survive confirmation, then write inside the workspace
- renderer still shows plan, trace, verification, pending action, and audit clearly
