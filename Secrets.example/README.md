# Local API keys (Debug bootstrap)

Helm never commits real keys. For local development:

1. Copy this folder to `Secrets/` at the repo root (sibling of `Helm.xcodeproj` / `project.yml`), **or** run `./scripts/sync-secrets-from-coach.sh` to copy keys from the Coach app's `Secrets/` folder.
2. Rename `gemini.key.example` to `gemini.key` (and optionally `openrouter.key.example` to `openrouter.key`).
3. Paste your API keys as a single line in each `*.key` file (no quotes).
4. Build and run the **Debug** configuration on your device or simulator.

On launch, Debug builds copy `Secrets/` into the app bundle and load each `*.key` file into Keychain (`AfterFirstUnlockThisDeviceOnly`). Release builds omit the bootstrap entirely.

Settings and onboarding screens prefill saved keys from Keychain, matching Coach.

If `Secrets/` is missing, the app keeps running and Diagnostics records a clear warning instead of crashing.

## TestFlight OpenRouter provisioning (M11.2)

Release builds can auto-request a capped, free-models-only OpenRouter key from the personal Coacher Cloudflare Worker (`Coacher/coach-key-service`). Before distributing to friends:

1. Deploy the worker and set `CoachKeyServiceConfig.baseURLString` + `appSharedSecret` in `Packages/CoachLLM/Sources/CoachLLM/CoachKeyServiceConfig.swift`.
2. The shared secret is embedded in the Release binary. That is acceptable for a capped friends circle; rotate `APP_SHARED_SECRET` on the worker if the binary leaks. Do not ship this to the public App Store.

Debug builds skip auto-provision and continue to load `openrouter.key` from `Secrets/` when present.
