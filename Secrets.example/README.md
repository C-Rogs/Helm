# Local API keys (bundled into Debug and Release)

Helm never commits real keys. For local development and TestFlight archives from this Mac:

1. Copy this folder to `Secrets/` at the repo root (sibling of `Helm.xcodeproj` / `project.yml`), **or** run `./scripts/sync-secrets-from-coach.sh` to copy keys from the Coach app's `Secrets/` folder.
2. Rename `gemini.key.example` to `gemini.key` (and optionally `openrouter.key.example`, `spotify-client-id.key.example`, `linear.key.example`).
3. Paste your API keys as a single line in each `*.key` file (no quotes).
4. Build. Launch copies `Secrets/` into the app bundle and loads each `*.key` file into Keychain (`AfterFirstUnlockThisDeviceOnly`).

Gemini is the coach. OpenRouter stays the photo-meal fallback when Gemini is missing or Auto cannot use it. `linear.key` is the CamLab personal API key used by in-app TestFlight feedback. None of these values are shown in the UI.

For Spotify session timelines, register a Spotify Developer app and set redirect URI `helm://spotify-callback`, then add the client ID to `spotify-client-id.key`.

If `Secrets/` is missing, the app keeps running and Diagnostics records a clear warning instead of crashing.

## TestFlight OpenRouter provisioning (M11.2, optional)

Release builds can also auto-request a capped, free-models-only OpenRouter key from the personal Coacher Cloudflare Worker (`Coacher/coach-key-service`) when that worker is configured. Friends still get the bundled `openrouter.key` as fallback without that worker.
