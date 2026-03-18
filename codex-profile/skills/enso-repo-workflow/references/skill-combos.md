# Enso Skill Combos

Use this file to select the minimal effective skill set for work in `D:\Enso`.
Start with the smallest combination that covers the task.
Do not load all Enso skills by default.

## Core Enso skills

- `enso-repo-workflow`
  Use for almost any substantive code change in this repo.
- `enso-execution-kernel`
  Use for execution flow, retrieval, tools, gates, verification, persistence, and right-rail execution state.
- `enso-review-gate`
  Use for review, audit, 检定, acceptance checks, and contract drift checks.
- `enso-provider-integration`
  Use for provider presets, config validation, secret storage, model adapter wiring, and settings UI related to providers.
- `enso-ui-shell`
  Use for three-panel renderer work, mode switching, composer flow, and right-rail rendering.
- `enso-doc-postflight`
  Use after code changes to update required docs and enforce postflight completeness.

## Existing generic skills worth combining

- `playwright`
  Use for automated UI verification, browser/Electron flow checks, screenshots, and reproducing renderer bugs.
- `playwright-interactive`
  Use for iterative live UI debugging when a persistent browser/Electron session is helpful.
- `gh-fix-ci`
  Use for GitHub Actions failure investigation and repair planning.
- `gh-address-comments`
  Use for addressing PR review comments on the active branch.
- `screenshot`
  Use only when an OS-level screenshot is specifically needed.

## Recommended combinations

### General feature work

- `enso-repo-workflow`
- `enso-doc-postflight`

### Execution-flow work

Use for:
- `src/main/core/execution-flow.ts`
- retrieval decision logic
- typed tools
- gating and confirmation flow
- verification behavior
- state or audit persistence

Recommended skills:
- `enso-execution-kernel`
- `enso-repo-workflow`
- `enso-doc-postflight`

Add:
- `enso-ui-shell` if right-rail rendering changes
- `playwright` if shell behavior or confirmation UX changed

### Provider and config work

Use for:
- `ConfigService`
- `SecretService`
- `ModelAdapter`
- provider factory or provider implementations
- provider-related settings UI

Recommended skills:
- `enso-provider-integration`
- `enso-repo-workflow`
- `enso-doc-postflight`

Add:
- `enso-ui-shell` if settings UI changed
- `playwright` if provider UX or settings persistence needs UI verification

### UI shell work

Use for:
- three-panel layout
- mode switcher
- conversation rail
- center-pane views
- composer
- right-rail state panels

Recommended skills:
- `enso-ui-shell`
- `enso-doc-postflight`

Add:
- `enso-repo-workflow` when the change is broader than renderer-only
- `playwright` for regression coverage
- `playwright-interactive` for live iterative debugging

### Review or acceptance checks

Use for:
- code review
- project audit
- 检定
- stop-condition checks
- contract drift checks

Recommended skills:
- `enso-review-gate`

Add:
- `playwright` when UI or stop conditions matter
- `gh-fix-ci` if the review target is a failing PR

### PR review comment handling

Recommended skills:
- `gh-address-comments`
- the Enso domain skill that matches the comment

Examples:
- execution-flow comments -> `enso-execution-kernel`
- settings/provider comments -> `enso-provider-integration`
- UI comments -> `enso-ui-shell`

### CI failure investigation

Recommended skills:
- `gh-fix-ci`
- one matching Enso domain skill

Examples:
- runtime or state-chain failures -> `enso-execution-kernel`
- provider/config failures -> `enso-provider-integration`
- renderer/test failures -> `enso-ui-shell`

## Minimal selection rules

- Do not combine all Enso skills for one task.
- Prefer 2-3 skills for most work.
- Add `enso-doc-postflight` whenever code changes are expected.
- Add `playwright` only when UI behavior, shell layout, or stop conditions need proof.
- Add GitHub skills only when the task is tied to PR comments or CI.

## Quick mapping

- Implement a normal repo change:
  - `enso-repo-workflow` + `enso-doc-postflight`
- Change `ExecutionFlow`:
  - `enso-execution-kernel` + `enso-doc-postflight`
- Change settings and API key handling:
  - `enso-provider-integration` + `enso-ui-shell` + `enso-doc-postflight`
- Change three-panel UI:
  - `enso-ui-shell` + `playwright` + `enso-doc-postflight`
- Review the repo:
  - `enso-review-gate` + `playwright`
- Fix CI:
  - `gh-fix-ci` + the relevant Enso domain skill
