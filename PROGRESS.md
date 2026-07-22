# Helm build progress

Shared status board for every build agent. Invocation: Cameron says `build M#.#` only. Rules: `PLAN.md` + `.cursor/rules/helm-build-agent.mdc`.

**Agents auto-commit every section. Cameron only tests at DT gates (DT1 to DT5). Never ask Cameron to commit or review.**

`done` requires a commit SHA. Empty Commit column = not landed.

Status values: `not started`, `in progress (agent: <name/session>)`, `done`, `blocked (<reason>)`.

## Sections

| Section | Status | Date | Commit | Notes / deviations |
|---|---|---|---|---|
| M0.1 Repo, XcodeGen, app shell | done | 2026-07-21 | 9f70b14 | Seven local packages declared in project.yml but not linked to Helm target yet; HelmWatch stub embedded for M0.5. |
| M0.2 Core package | done | 2026-07-21 | e7df993 | HelmDay.day(for:cutoff:calendar:), Clock, units, Sendable value types, 13 unit tests. Sleep attributed by onset via SleepRecord.helmDay(forStart:). |
| M0.3 Diagnostics package + screen | done | 2026-07-21 | f766be5 | DiagnosticsLog actor (500-cap ring), LogExportService zip (manifest/ring_buffer/oslog_extract), HelmCategory/Logger/Signpost helpers, Settings Diagnostics screen with Export share sheet, bootstrap test log + captured error on launch. 5 unit tests pass. |
| M0.4 DesignSystem | done | 2026-07-21 | 7109cd1 | OLED-black tokens in HelmTokens.swift; Card, Gauge, StatRow, button styles, helmChartStyle(); tab shell themed via helmTheme() + helmScreenBackground(). DesignSystem linked to Helm target. |
| M0.5 Watch walking skeleton | done | 2026-07-22 | 74ef04c | WatchSyncPayload in Core; shared WatchSessionCoordinator; phone Settings screen + Watch root UI; stub complication extension. WCSession round-trip via application context. Core package now supports watchOS. |
| M0.6 Debug key bootstrap + battery method doc | done | 2026-07-22 | 93ef388 | APIKeyStore (Keychain, AfterFirstUnlockThisDeviceOnly); Debug-only SecretsBootstrap; Secrets.example template; missing Secrets/ logs to Diagnostics without crashing. Battery method doc already landed at M0.1. |
| M0.7 DesignSystem v2 (Arc, type, motion, haptics) | done | 2026-07-23 | dbc7872 | Normative: Docs/DESIGN-SYSTEM.md + Docs/HAPTICS.md. HelmTheme/HelmSkin seam, SkinnedContainer, ArcGauge, HapticEngine in DesignSystem package. v1 instrument skin only. |
| M0.8 Second layout skin (optional) | deferred | | | Build only if in-app layout switcher wanted in v1. Default: skip; M0.7 seam reserves it. |
| M1.1 Persistence: health schema + repositories | done | 2026-07-21 | 209e784 | GRDB v1 health schema; PersistenceStore actor; repos for daily metrics, body comp, sleep, nutrition; NutritionDay + MealRecord in Core; migrate-up harness + 7 tests pass. Ephemeral temp-file pool for in-memory tests (GRDB WAL + :memory: incompatible). |
| M1.2 DB export + data safety | done | 2026-07-21 | ca0695f | Checkpointed GRDB export via SQLite backup API; Settings Data & Backup screen (database, diagnostics, full zip); iCloud included explicitly; Docs/DATA-SAFETY.md restore semantics. 9 Persistence tests pass. |
| M1.3 HealthKitIngest actor (live reads) | done | 2026-07-22 | fd8866e | HealthKitIngest actor: anchored sync, observers, background delivery, AsyncStream per family, signposts. Package wired to Core/Diagnostics/Persistence. 14 fixture tests compile; Helm.entitlements adds HealthKit + background delivery. Settings HealthKit screen for auth/sync. Workouts ingested but not persisted until logger schema (M3.1). |
| M1.4 Bounded backfill + debug data browser | done | 2026-07-22 | 509c3ac | BackfillService actor: 6-month monthly chunks, resumable cursor, BackfillChunk signpost, ReadinessKit seed hook. HealthKitStoreClient date-bounded fetch. Repository listDays + Debug DataBrowserView. Auto-backfill after HealthKit auth (utility Task). 4 new ingest tests + listDays persistence test. |
| M2.1 ReadinessKit engine (pure) | done | 2026-07-21 | f80e79e | ReadinessKit target in Domain package: ARC per BodyBattery spec (EWMA/MAD, spec weights, logistic ~58, cold-start, Edwards TRIMP, confidence). `readiness(for:)`, `seedBaselines(from:)`, `ReadinessBaselineState`. 20 tests + 3 golden fixtures. |
| M2.2 Readiness wiring + Dashboard card | done | 2026-07-22 | 509c3ac | v3 migration: readiness_daily_score + readiness_baseline_state. ReadinessRepository, ReadinessEngine + @Observable ReadinessService, ReadinessHistoryBuilder. Backfill persists baselines via engine. Dashboard ARC gauge + contributors + confidence. Ingest observer triggers recompute. ReadinessCompute signpost in wiring layer. Persistence + HealthKitIngest tests. |
| M2.3 Readiness card re-skin + reveal | done | 2026-07-23 | aa3c6a0 | ArcGauge replaces M2.2 gauge; ArcRevealGauge + DailyRevealGate; once-per-day reveal + readinessReveal haptic via ReadinessRevealStore (HelmDay keyed). Contributors fade on reveal tail. Reduce Motion skips sweep. 2 DailyRevealGate unit tests.
| M3.1 Logger persistence | done | 2026-07-22 | 509c3ac | v2 logger schema (loggy-derived): exercise/alias, sessions/blocks/sets, templates, PRs, exercise_history_snapshot, rest-timer + coach_recommendation tables. Repos: Exercise, WorkoutSession, WorkoutTemplate, PersonalRecord. Queries: previousPerformance(exercise:setIndex:), estimatedOneRM (Epley). Core logger enums + draft types. 15 Persistence tests pass (6 new logger tests + migration harness v1→v2). |
| M3.2 Active session engine | done | 2026-07-22 | cdba93d | ActiveSessionRepository + ActiveSessionEngine actor + @Observable ActiveSessionStore. RestTimer timestamp projection in Core. Kill-recover, rest backgrounding, finish/discard tests (9 new). |
| M3.3 Train screen + custom numpad | done | 2026-07-22 | 4c83f62 | Hevy-style Train tab: exercise sections, set rows, UIViewRepresentable numpad (no system keyboard), previous-performance column + tap-to-fill, rest banner, exercise picker, finish/discard. Placeholder exercise seed when table empty (until M5.4). Previews on all row types. |
| M3.4 Rest-timer alerts, Live Activity, HealthKit write | done | 2026-07-22 | 4c83f62 | Rest notifications via RestTimerNotificationPlanner + UNUserNotificationCenter; HelmWidgets Live Activity extension; WorkoutHealthKitWriter on finish (source-filtered); WorkoutSessionLifecycle signpost. |
| M3.5 History, templates, PRs | done | 2026-07-22 | 4c83f62 | Paginated history + editable detail; template create/start; query-based PersonalRecordDetector + celebration UI. |
| M3.6 Paste-a-workout parser | done | 2026-07-22 | defb7c7 | WorkoutTextParser + import resolver/service, paste + preview UI on Train, alias mapping for unknown exercises, 9 fixture tests. |
| F-DESIGN-M3 Logger UI + haptics catch-up | done | 2026-07-23 | fa58558 | DesignSystem HelmNumpad + SetRow; WorkoutHapticPolicy/Coordinator (set-logged, selection, rest-done, PR-hit); HelmNotificationDelegate for suspended rest-done; Train re-skin. 7 WorkoutHapticPolicy unit tests. |
| M4.1 Provider protocol + registry | done | 2026-07-21 | 5ecb5bc | CoachLLM package: protocol, registry with reserved FM/OpenRouter slots, token budgets, failure policy, MockProvider, fixture harness. Gemini placeholder until M4.2. |
| M4.2 GeminiProvider + keys | not started | | | |
| M4.3 MemoryProfile | not started | | | |
| M4.4 Context builder (pure) | not started | | | |
| M4.5 Chat UI + chat persistence | not started | | | |
| M4.6 "Show your working" sheet (tap-to-explain) | not started | | | Reusable explain sheet; selection haptic; offline degrades to engine contributors only. |
| M5.1 PlanKit mesocycle core (pure) | done | 2026-07-21 | cb28104 | PlanKit target in Domain package. MesocycleState, MEV→MRV ramp, deload/reset, landmark seed+refine, Epley progression, weekly hard-set ledger. 13 tests. |
| M5.2 Planned-vs-actual calendar + drift policy | not started | | | |
| M5.3 Prescription + readiness gating + clamps | not started | | | |
| M5.4 Exercise seed schema + import | not started | | | |
| M5.5 Evidence-driven selection + citations | not started | | | |
| M5.6 Phase/goal setup + Dashboard prescription card | not started | | | |
| M6.1 Prescription-driven Train screen | not started | | | |
| M6.2 In-session coach | not started | | | |
| M6.3 Morning brief on open | not started | | | |
| M6.4 Onboarding assembly | not started | | | |
| M7.1 GenerateBriefIntent (locked-phone aware) | not started | | | |
| M7.2 Notification triggers + Shortcuts guide | not started | | | |
| M8.1 Watch workout session | not started | | | |
| M8.2 Phone observation + readiness complication | not started | | | |
| M9.1 NutritionKit engine (pure) | not started | | | |
| M9.2 Nutrition screen + Dashboard card | not started | | | |
| M9.3 Photo-to-macro | not started | | | |
| M10.1 Trends charts | not started | | | |
| M10.2 Sources / Methodology screen | not started | | | |
| M11.1 Schema-v2 export + Share Extension | not started | | | |
| M11.2 Sharing via Coacher (later, optional) | not started | | | |

## Device Test Gates

Run by Cameron, not build agents. See "Device Test Gates" in PLAN.md for the full checklist per gate.

| Gate | Status | Date | Notes / issues filed |
|---|---|---|---|
| DT1 (after M2.2): foundation + ingest + readiness | done | 2026-07-22 | HealthKit connected after relaunch, dashboard polish, Watch round-trip complete, ARC/battery/diagnostics pass. Design re-check (haptics + reveal) pending M0.7 + M2.3. |
| DT2 (after M3.6 + F-DESIGN-M3): the logger, in the gym | not started | | Includes rest-done haptic while suspended, set-logged/PR-hit feel. |
| DT3 (after M6.4): the loop replaces Gemini (go-live gate) | not started | | |
| DT4 (after M8.2): proactivity + Watch | not started | | |
| DT5 (after M11.1): nutrition, analytics, full regression | not started | | |

## Fix sections

| ID | Status | Date | Notes |
|---|---|---|---|
| F-DT1.1 HealthKit launch bootstrap + status UI | done | 2026-07-22 | Ingest metadata persistence, HealthKitBootstrap.start(), upgraded HealthKitStatusView, tests. |
| F-DT1.2 Watch companion install path | done | 2026-07-22 | DT1 Watch install note in PLAN.md; signing already inherited from project base. |
| F-DT1.3 Dashboard visual polish | done | 2026-07-22 | Greeting, band badge/stripe, contributor bars, secondary Ask Coach button. Superseded visually by M2.3 once M0.7 lands. |
| F-DESIGN-M3 Logger UI + haptics catch-up | done | 2026-07-23 | fa58558 | DesignSystem HelmNumpad + SetRow; WorkoutHapticPolicy/Coordinator; HelmNotificationDelegate; Train re-skin per DESIGN-SYSTEM.md + HAPTICS.md. |
