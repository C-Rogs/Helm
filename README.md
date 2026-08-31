# Helm

iPhone training coach. HealthKit lands in a local GRDB store. Deterministic engines set today's session, calories, and readiness. Gemini narrates and can swap an exercise; the engines clamp the change. The Watch companion runs a real `HKWorkoutSession`, so heart rate actually feeds training load.

Personal app. iOS 26 and watchOS 26. No App Store page. Friends TestFlight is archived from this Mac.

This repo is the product. bioharvest, Coach, Signal, loggy, and BodyBattery taught the loop. Helm does not import those codebases.

## What you do with it

Tabs: Dashboard, Train, Nutrition, Chat, Settings.

1. Grant Health on first launch. Ingest is observer-driven. It does not poll.
2. Open Train. Today's prescription is already a workout: engine target and last time inline.
3. Log the set. Watch is live HR for that activity type. Finish writes an `HKWorkout`.
4. Chat is for "why this volume", the methodology library, or "machine taken, swap the dip."
5. Settings holds the editable memory profile the model reads every turn, export, and opt-in iCloud Drive sync.

HealthKit is unreadable while the phone is locked. Morning briefs fire on first unlock, or on open. A 7am Shortcut on a locked phone cannot harvest.

## Precedent

The old loop was bioharvest JSON, paste into Gemini, type Hevy text and calories, and hope the thread remembered the mesocycle. The human was the integration layer.

Whoop and Oura see recovery and not sets. Fitbod, Renaissance Periodization, and Hevy see sets and not HRV. MacroFactor does adaptive TDEE in its own silo. Helm is one phone for those three, for one athlete.

## Building blocks

- Packages: `Core`, `Domain` (ReadinessKit, PlanKit, NutritionKit), `Persistence` (GRDB, append-only migrations), `HealthKitIngest` (actor, anchored queries, source-bundle filter so Helm does not re-ingest its own Health writes), `CoachLLM` (Gemini; OpenRouter and Foundation Models reserved on the same protocol), `DesignSystem`, `ExportKit`.
- Day boundary is a user cutoff (default 04:00), not the end of a sleep sample. Apple Health splits nights; a 4am bedtime would otherwise land on the wrong day.
- iCloud device backup of `helm.sqlite` is off. Restore is HealthKit re-ingest plus optional iCloud Drive profile and 90-day training history. Manual export lives in Settings.
- Schema v2 JSON from bioharvest still imports. Copy-to-Gemini remains as a fallback.
- No analytics SDKs. Diagnostics is a zip on the share sheet.
- XcodeGen owns the project file. Keys live in gitignored `Secrets/` (see `Secrets.example/`). Launch copies them into Keychain (`AfterFirstUnlockThisDeviceOnly`).

```bash
brew install xcodegen   # once
xcodegen generate
open Helm.xcodeproj
```

Build the **Helm** scheme onto a physical iPhone. Simulator HealthKit is not a useful test.

## What this skips

Paid tiers, Garmin, on-device Foundation Models in v1, RAG (retired from Signal for battery). Coacher's capped OpenRouter minting is wired as a later friends path; TestFlight currently ships a bundled key as fallback.
