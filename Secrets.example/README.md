# Local API keys (Debug bootstrap)

Helm never commits real keys. For local development:

1. Copy this folder to `Secrets/` at the repo root (sibling of `Helm.xcodeproj` / `project.yml`).
2. Rename `gemini.key.example` to `gemini.key`.
3. Paste your Gemini API key as a single line in `gemini.key` (no quotes).
4. Build and run the **Debug** configuration on your device or simulator.

On launch, Debug builds copy `Secrets/` into the app bundle and load each `*.key` file into Keychain (`AfterFirstUnlockThisDeviceOnly`). Release builds omit the bootstrap entirely.

If `Secrets/` is missing, the app keeps running and Diagnostics records a clear warning instead of crashing.
