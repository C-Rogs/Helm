# Local API keys (Debug bootstrap)

Helm never commits real keys. For local development:

1. Copy this folder to `Secrets/` at the repo root (sibling of `Helm.xcodeproj` / `project.yml`), **or** run `./scripts/sync-secrets-from-coach.sh` to copy keys from the Coach app's `Secrets/` folder.
2. Rename `gemini.key.example` to `gemini.key` (and optionally `openrouter.key.example` to `openrouter.key`).
3. Paste your API keys as a single line in each `*.key` file (no quotes).
4. Build and run the **Debug** configuration on your device or simulator.

On launch, Debug builds copy `Secrets/` into the app bundle and load each `*.key` file into Keychain (`AfterFirstUnlockThisDeviceOnly`). Release builds omit the bootstrap entirely.

Settings and onboarding screens prefill saved keys from Keychain, matching Coach.

If `Secrets/` is missing, the app keeps running and Diagnostics records a clear warning instead of crashing.
