---
name: "enso-provider-integration"
description: "Provider and configuration workflow for the Enso desktop agent in `D:\\Enso`. Use when changing provider presets, model adapter behavior, API-key storage, config schema, runtime validation, provider factory wiring, or related IPC and settings UI paths."
---

# Enso Provider Integration

Use this skill when the task touches provider selection, local config, secret persistence, or model invocation. Keep the provider layer explicit, validated, and aligned with the settings UI.

## Main files

- `src/shared/providers.ts`
- `src/shared/types.ts`
- `src/main/services/config-service.ts`
- `src/main/services/secret-service.ts`
- `src/main/services/model-adapter.ts`
- `src/main/providers/provider-factory.ts`
- `src/main/providers/types.ts`
- `src/main/providers/kimi-provider.ts`
- `src/main/ipc.ts`
- `src/renderer/App.tsx`
- `config/default.toml`
- `tests/mvp.integration.test.cjs`
- `tests/mvp.ui.test.cjs`

## Rules

- Never persist provider API keys into `config.toml`.
- Keep secrets in local secure storage only.
- Validate config by allowed values and expected types, not only by TOML parse success.
- Reject or normalize unsupported provider ids and invalid mode defaults deterministically.
- Keep the renderer settings surface aligned with the actual backend schema.
- When adding a provider, update presets, adapter wiring, config defaults, settings UI, and tests together.

## Change checklist

1. Update shared provider ids and presets.
2. Update config load/save behavior and validation.
3. Update secure key storage if the provider surface changed.
4. Update model adapter and provider factory.
5. Update IPC and settings UI if the user-editable surface changed.
6. Add regression coverage for config persistence, secret handling, and provider error mapping.

## Verification

Run:

```powershell
npm run verify
```

Also run the UI test when settings or provider UX changed:

```powershell
npm run test:mvp:ui
```

Make sure these still hold:
- config file never stores plaintext API keys
- secret storage can save, read, and clear the active provider key
- invalid provider responses map to meaningful provider errors
- changed defaults are reflected in new conversations and in the settings screen
