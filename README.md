# Helm

iPhone training coach. HealthKit lands in a local GRDB store. Deterministic engines set today's session, calories, and readiness. Gemini narrates and can swap an exercise; the engines clamp the change. The Watch companion runs a real `HKWorkoutSession`, so heart rate actually feeds training load.

Personal app on iOS 26 and watchOS 26. Friends TestFlight is archived from this Mac.

bioharvest, Coach, Signal, loggy, and BodyBattery taught the loop. Helm is a new repo.

## What you do with it

Tabs: Dashboard, Train, Nutrition, Chat, Settings.

1. Grant Health on first launch. Ingest is observer-driven.
2. Open Train. Today's prescription is already a workout, with the engine target and last time inline.
3. Log the set. Watch is live HR for that activity type. Finish writes an `HKWorkout`.
4. Chat is for "why this volume", the methodology library, or "machine taken, swap the dip."
5. Settings holds the editable memory profile the model reads every turn, export, and opt-in iCloud Drive sync.

HealthKit is unreadable while the phone is locked. Morning briefs fire on first unlock, or on open. A 7am Shortcut on a locked phone cannot harvest.

## Precedent

The old loop was bioharvest JSON, paste into Gemini, type Hevy text and calories, and hope the thread remembered the mesocycle.

Whoop and Oura see recovery and not sets. Fitbod, Renaissance Periodization, and Hevy see sets and not HRV. MacroFactor does adaptive TDEE in its own silo. Helm runs those three on one phone, for one athlete.

## Building blocks

- Packages: `Core`, `Domain` (ReadinessKit, PlanKit, NutritionKit), `Persistence` (GRDB, append-only migrations), `HealthKitIngest` (actor, anchored queries, source-bundle filter so Helm skips its own Health writes), `CoachLLM` (Gemini; OpenRouter and Foundation Models reserved on the same protocol), `DesignSystem`, `ExportKit`.
- Day boundary is a user cutoff (default 04:00). Apple Health splits nights; a 4am bedtime would otherwise land on the wrong day if you keyed off the sleep sample.
- iCloud device backup of `helm.sqlite` is off. Restore is HealthKit re-ingest plus optional iCloud Drive profile and 90-day training history. Manual export lives in Settings.
- Schema v2 JSON from bioharvest still imports. Copy-to-Gemini remains as a fallback.
- No analytics SDKs. Diagnostics is a zip on the share sheet.
- `project.yml` is the XcodeGen input. Keys live in gitignored `Secrets/` (see `Secrets.example/`). Launch copies them into Keychain (`AfterFirstUnlockThisDeviceOnly`).

```bash
brew install xcodegen   # once
xcodegen generate
open Helm.xcodeproj
```

Build the Helm scheme onto a physical iPhone. Simulator HealthKit is not a useful test.

v1 skips paid tiers, Garmin, on-device Foundation Models, and RAG (retired from Signal for battery). Coacher's capped OpenRouter minting is a later friends path. TestFlight currently ships a bundled key as fallback.
