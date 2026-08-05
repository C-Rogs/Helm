# Diagnostics contract

Canonical reference for how every Helm package logs, signposts, captures silent errors, and exports a debug bundle. Frozen before M0.1 so no build agent invents its own convention. M0.3 implements the mechanics described here (`DiagnosticsLog`, `LogExportService`, the diagnostics screen); every later section instruments against this contract, it does not redefine it.

No telemetry anywhere in this system. Nothing here phones home. Everything described is local-only, exported by explicit user action (share sheet / AirDrop).

---

## OSLog taxonomy

- **Subsystem** (one, fixed): `com.cameronro.helm`
- **Category per package**, fixed set, do not add new categories ad hoc; if a section genuinely needs one not listed here, add it to this table in the same commit that introduces it:

| Category | Used by |
|---|---|
| `Persistence` | GRDB store, migrations, repositories |
| `HealthKitIngest` | observer queries, anchored fetch, backfill, deletion handling |
| `ReadinessKit` | ARC compute, baseline seeding |
| `PlanKit` | mesocycle, prescription, drift resolution, adjustments |
| `NutritionKit` | TDEE, macro targets, photo-macro extraction |
| `CoachLLM` | provider calls, context building, structured-output decode |
| `Logger` | active session, sets, rest timer, Live Activity |
| `AppIntents` | `GenerateBriefIntent` and any future intents |
| `Watch` | WatchApp, workout session, complication |
| `UI` | view-level lifecycle only (tab appear/disappear, cancellation on tab-disappear); not a dumping ground for business logic |

Use `Logger(subsystem: "com.cameronro.helm", category: "<Category>")` per file/module; do not construct ad hoc subsystem strings.

---

## Signpost catalog

Named intervals for every critical path, so Instruments and the overnight battery test can find them by name without guessing. Each row is a `os_signpost(.begin/.event/.end, name: "<Name>", signpostID: ...)` pair. `signpostID` is scoped per the "Scoping" column so concurrent instances (two ingest types, two chat turns) don't collide.

| Name | Category | Scoping | Landed at |
|---|---|---|---|
| `HealthKitObserverFetch` | `HealthKitIngest` | per HKSampleType | M1.3 |
| `BackfillChunk` | `HealthKitIngest` | per chunk index | M1.4 |
| `ReadinessCompute` | `ReadinessKit` | per day | M2.1 |
| `PrescriptionCompute` | `PlanKit` | per day | M5.3 |
| `GeminiStream` | `CoachLLM` | per request (UUID) | M4.2 |
| `InSessionCoachPropose` | `CoachLLM` | per in-session turn (UUID) | in-session coach reliability |
| `BriefIntentRun` | `AppIntents` | per invocation (UUID) | M7.1 |
| `WorkoutSessionLifecycle` | `Logger` (phone side) / `Watch` (Watch side) | per session (UUID), begin at start, event at pause/resume, end at finish/discard | M3.4 (phone HK write), M8.1 (Watch session) |
| `LiveWorkoutBuilderTeardown` | `Watch` | per session (UUID) | M8.1 |

Phone AirPods HR (no Watch app) uses ring-buffer events `phone.hr.session.start` / `phone.hr.session.end` / `phone.hr.first` via `WatchCompanionDiagnosticEvent`, not a new signpost name.

A section that owns one of these rows must emit it; a section landing a new critical path not in this table adds a row here in the same commit, it does not invent an unlisted signpost name.

---

## Ring buffer contract

- **Owner**: `Diagnostics` package, one shared `actor DiagnosticsLog` (Swift 6 actor, no locks needed).
- **Capacity**: fixed-size ring, 500 entries. Oldest evicted on overflow. Not configurable at runtime; if 500 proves too small during DT gates, raise the constant and note it in `PROGRESS.md` against M0.3, don't make it dynamic.
- **Entry shape**: timestamp, category, level (`.error` for silent-failure captures, `.info`/`.debug` for manual log lines), a short message, an optional `context: [String: String]` dictionary, and for silent-error captures: the error's type name and a symbolicated (or best-effort address) stack trace.
- **What gets captured automatically**: any unhandled `Error` thrown by an engine call or an ingest path is caught at the nearest actor/service boundary, written to the ring buffer with type + context + stack, and never rethrown as a crash. This is the "silent HealthKit-parse failure in agent-built code is recoverable on export" guarantee from the top-level plan.
- **Context dictionary rules**: keep it small and typed, e.g. `["metricType": "HRV", "date": "2026-07-20"]`. Never put a raw HealthKit sample value, a full chat message, or an image in the context dictionary. This is a signal-to-noise rule as much as a privacy one: entries should stay short enough to read at a glance in the diagnostics screen.
- **Thread safety**: all writes go through the actor; no shared mutable state outside it. Callers `await log.record(...)`, never touch a buffer directly.

---

## Export bundle schema

`LogExportService` produces a single zip, presented via the share sheet (AirDrop / Files / Mail, whatever the sheet offers). Contents:

- `manifest.json`: app version + build number, GRDB migration schema version, exercise seed version, device model, OS version, export timestamp.
- `ring_buffer.json`: the current contents of the ring buffer, oldest first.
- `oslog_extract.txt`: a bounded pull from `OSLogStore` for subsystem `com.cameronro.helm`, most recent 24 hours or 5,000 entries, whichever is smaller. Includes the Share Extension process when present on the exporting device; **Watch app OSLog is not included** in a phone-initiated export (Watch is a separate process). **Watch companion wake diagnostics are relayed over WCSession** into the phone ring buffer as `Watch` category entries (`watch.handle.begin`, `watch.session.*`, etc.), so a normal Settings → Export Diagnostics bundle is enough for phone+Watch wake investigations when the Watch was reachable at least briefly.
- **Not included by default**: raw chat transcript text, meal photo images, raw HealthKit sample payloads. Chat metadata (message count, timestamps, prompt/schema version, provider error codes) may appear in the ring buffer / OSLog extract since those are typed, non-content fields; the actual message text and images are not written to either.
- If a future debugging need genuinely requires chat content in an export, that is a separate, explicit, opt-in action (not this default one-tap bundle), and would be its own small addition, not a change to this default schema.

---

## Redaction rules

- **Gemini request URLs are never logged, anywhere, full stop.** The API key travels as a URL query parameter; no `Logger` call, signpost annotation, or ring-buffer context may include a request URL. Grep for this at review time on any `CoachLLM` change.
- **No raw HealthKit values or chat content in the ring buffer or OSLog extract** (see Ring buffer contract and Export bundle schema above). This is a cleanliness rule for a personal single-user app, not a strict privacy requirement (the top-level plan already treats privacy as low concern since data goes to Gemini), but it keeps diagnostics small, fast to scan, and safe to hand to anyone without a second thought.

---

## Instrumentation gate

A section that owns a row in the signpost catalog is not "done" (per `PROGRESS.md`) until:
1. The named signpost(s) it owns are actually emitted at the begin/end (and event, where noted) points listed above.
2. Any error path it introduces that can silently fail is captured to the ring buffer per the contract above, not just logged to OSLog and forgotten.
3. It uses its assigned category from the taxonomy table, not a new one.

Sections with no row in the signpost catalog still use `OSLog` (no `print()`, per the engineering standards) with their assigned category, but don't need a named signpost interval.
