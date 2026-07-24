# Helm build progress

Shared status board for every build agent. Invocation: Cameron says `build M#.#` only. Rules: `PLAN.md` + `.cursor/rules/helm-build-agent.mdc`.

**Agents auto-commit every section. Cameron only tests at DT gates (DT1 to DT6). Never ask Cameron to commit or review.**

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
| M0.8 Second layout skin (optional) | done | 2026-07-23 | fa22d78 | Data sheet skin selectable in Settings; HelmScreenStack + skinAccentStripe; StatChip ruled treatment; previews per skin. State-field/Blueprint reserved. |
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
| M4.2 GeminiProvider + keys | done | 2026-07-23 | e8523bc | GeminiProvider (AI Studio SSE + structured output with prompt/schema versions), Keychain via APIKeyStore, Settings Coach screen (provider picker + key entry), GeminiStream signpost, fixture contract tests. Live smoke is DT3. |
| M4.3 MemoryProfile | done | 2026-07-23 | 0081741 | MemoryProfile value type + stablePrefixText(); v4 migration; MemoryProfileStore; Settings Coach Memory editor. 3 persistence + 3 CoachLLM tests pass. |
| M4.4 Context builder (pure) | done | 2026-07-23 | 0b9c2d0 | ContextBuilder + CoachContextDays + EvidenceIndex + CoachPrompt; stable prefix ordering, oldest-day-first trimming, follow-up skips health days. 6 CoachLLM tests pass. |
| M4.5 Chat UI + chat persistence | done | 2026-07-23 | 5707237 | v7 chat_message migration; ChatStore; CoachContextAssembler; ChatController + streaming UI; mock provider in DEBUG; tab-disappear cancel. |
| M4.6 "Show your working" sheet (tap-to-explain) | done | 2026-07-23 | ca901eb | ExplainableMetric + ExplainSheet + StatChip in DesignSystem; snapshot tests for readiness/prescription/nutrition; Dashboard wiring; chat hand-off via ChatController. |
| M5.1 PlanKit mesocycle core (pure) | done | 2026-07-21 | cb28104 | PlanKit target in Domain package. MesocycleState, MEV→MRV ramp, deload/reset, landmark seed+refine, Epley progression, weekly hard-set ledger. 13 tests. |
| M5.2 Planned-vs-actual calendar + drift policy | done | 2026-07-23 | 4d00c27 | PlanKit drift policy + ACWR guard; v5 plan schema (planned_workout, plan_mesocycle_state); PlanRepository. 6 drift scenario tests + 2 repo tests. |
| M5.3 Prescription + readiness gating + clamps | done | 2026-07-23 | 230df19 | PlanKit prescription(for:givenReadiness:profile:history:), readiness gating, apply(adjustment:excluding:) with clamps. 7 new tests. |
| M5.4 Exercise seed schema + import | done | 2026-07-23 | 6140951 | free-exercise-db.json (loggy/Signal catalog) + exercises.json manifest (placeholder:true, seedVersion 1). ExerciseSeedImporter with loggy muscle/mode/alias mapping, Hevy staples, picker curation. v6 app_metadata migration. First-launch import; idempotent re-import on version bump. 4 seed tests pass. |
| M5.5 Evidence-driven selection + citations | done | 2026-07-23 | b4699be | ExerciseSelectionEngine scores effectiveness/stretch/SFR + equipment; rationale + citationIDs on PrescribedExercise; 6 selection tests. |
| M5.6 Phase/goal setup + Dashboard prescription card | done | 2026-07-23 | 3576f5a | Training Plan settings (phase/goal/emphasis + experience, v8 migration); PlanPrescriptionEngine with PrescriptionCompute signpost; Dashboard today's session card; phase change re-plans. |
| M6.1 Prescription-driven Train screen | done | 2026-07-23 | 5a24028 | startFromPrescription bridge; auto-start today's plan on Train open; PrescriptionRow targets + PREV inline; manual/template fallback intact. |
| M6.2 In-session coach | done | 2026-07-23 | 2c4423f | askCoachInSession + InSessionCoachService; PlanKit apply bridge; exclude list + undo; coach_recommendation logging; AdjustmentBanner + AskCoachBar on Train; coach-adjust haptic. |
| M6.3 Morning brief on open | done | 2026-07-23 | 2c4423f | Generate-on-open brief with engine snapshot + coach narration; BriefCard on Dashboard; daily_brief v9 persistence; fingerprint cache skips regen unless inputs change. Interim NutritionTargetComposer until M9.1. |
| M6.4 Onboarding assembly | done | 2026-07-23 | c28c464 | First-run flow: HealthKit presence check, notifications, Gemini key, training plan, backfill progress, Shortcuts pointer. Launch gate via AppRootView; Setup section in Settings for re-entry. HealthKitDataPresenceChecker + 2 tests. |
| M7.1 GenerateBriefIntent (locked-phone aware) | done | 2026-07-23 | 31fda8f |
| M7.2 Notification triggers + Shortcuts guide | done | 2026-07-23 | 3325983 | Pre/post notification planners + snapshot tests; pre-workout scheduler from session-window heuristic; post-workout on finish; threshold insights in-app (silent); Proactive Notifications guide + onboarding copy update. |
| M8.1 Watch workout session | done | 2026-07-23 | c8f045d | HKWorkoutSession + HKLiveWorkoutBuilder on Watch; activity picker; live HR/zones; Edwards zones in Core; state machine unit tests; WorkoutSessionLifecycle + LiveWorkoutBuilderTeardown signposts (Watch category). Error(7) teardown order enforced. Watch-authoritative; no WCSession for workout state. |
| M8.2 Phone observation + readiness complication | done | 2026-07-23 | acb0ffe | Phone HKWorkout observer feeds Edwards TRIMP into next-day prior_day_trimp; throttled readiness push via WCSession application context; complication shows ARC score + brief deep link; Watch Brief tab; opportunistic live HR from Watch (5s throttle). Fixture tests for workout TRIMP + complication payload. |
| M9.1 NutritionKit engine (pure) | done | 2026-07-23 | 7a676ad | Adaptive TDEE + macro targets + macro gap. Replaces NutritionTargetComposer in brief and Dashboard (empty trend until M9.2 persistence). |
| M9.2 Nutrition screen + Dashboard card | done | 2026-07-23 | dd249e8 | NutritionService + NutritionEngine; persisted TDEE trend; targets vs actual + alcohol gap on Dashboard and Nutrition screen; day-type resolver (training/rest/deload). |
| M9.3 Photo-to-macro | done | 2026-07-23 | 987ab04 |
| M9.4 USDA reference bundle + NutritionLookup | done | 2026-07-24 | 6e97c46 | USDA SR subset bundle; NutritionLookup + MacroAggregator; MealLineItem in Core; lookup fixture tests pass. |
| M9.5 Grounded photo pipeline | done | 2026-07-24 | 6e97c46 | meal_decomposition.v1; MealVisionProviding; GroundedPhotoMacroEstimator; fixture pipeline tests (no live API). |
| M9.6 OpenRouter vision + confirm sheet v2 | done | 2026-07-24 | 6e97c46 | OpenRouterMealVisionProvider + MealVisionRouter; confirm sheet v2 line items + on-device recompute; PhotoMealLocalStore; Settings photo model picker. PrescriptionAutoStartStore fix for relaunch auto-start. |
| M9.7 LiDAR portion assist (optional) | deferred | | | Post-DT5; depth-assisted portion hints. |
| M10.1 Trends charts | done | 2026-07-23 | 2745fd6 | Five chart cards on Trends tab with paginated repository queries, ArcGauge for volume/energy, state-ramp line charts, fixture previews. |
| M10.2 Sources / Methodology screen | done | 2026-07-23 | 612b1c3 | Bundled placeholder methodology seed; Sources screen with topic browser + citations; equipment/selection-bias preferences persist to MemoryProfile and re-plan prescription. |
| M11.1 Schema-v2 export + Share Extension | done | 2026-07-23 | 8184f95 | ExportKit byte-compatible schema-v2 JSON; Settings export/copy/share; HelmShare extension imports via app group. |
| M11.2 Sharing via Coacher (later, optional) | done | 2026-07-23 | 67b47aa | CoachKeyService client + HelmDeviceIdentity + OpenRouterKeyProvisioner (Release auto-provision); Settings retry UI; reuses Coacher worker; shared-secret-in-binary documented. Also aligned GeminiModel with existing 3.5 test expectation (pre-existing mismatch on HEAD). |
| M12.1 Motion and transition pass | done | 2026-07-24 | 9cb87c5 | HelmNumericRoll, skeleton shimmer, staggered appear, matched-card detail; adopted on Dashboard/Train/Trends/Nutrition; set/PR/adjustment motion paired with haptics; Reduce Motion unit tests. |
| M12.2 Layout rhythm and density audit | done | 2026-07-24 | eed20f6 | HelmHairlineRule, HelmLayout tokens, helmScreenPadding, StatChip contributor grid, ruled list rows, LayoutRhythmTests |
| M12.3 Data-viz refinement | done | 2026-07-24 | 9238343 | HelmSparkline, HelmChartScrub, LandmarkVolumeBar; muscle volume bar card; Dashboard sparklines; scrub + insufficient-data states. |
| M12.4 Finish pass: states, iconography, consistency | done | 2026-07-24 | 456fd6d | HelmScreenState, HelmIcon, pressable styles; screen empty/loading/error previews; ICONOGRAPHY.md; copy and dash pass. |
| M12.5 Signature moments | done | 2026-07-24 | 3540be2 | Arc bloom, PR burst, workout finish summary, onboarding welcome/backfill/payoff reveal; Reduce Motion + gate tests.
| M12.6 DeviationBand component | done | 2026-07-24 | fff7c53 | DeviationBand bar/inline layouts, helmNumericRoll on value, previews for in/below/above-band and cold-start. |
| M12.7 Recovery detail view | not started | | | |
| M12.8 Progression / plan-model view | not started | | | Absorbs M13.1/M13.2 plan-visibility intent |
| M12.9 Muscle-volume promotion and recency | not started | | | |

## Device Test Gates

Run by Cameron, not build agents. See "Device Test Gates" in PLAN.md for the full checklist per gate.

| Gate | Status | Date | Notes / issues filed |
|---|---|---|---|
| DT1 (after M2.2): foundation + ingest + readiness | done | 2026-07-22 | HealthKit connected after relaunch, dashboard polish, Watch round-trip complete, ARC/battery/diagnostics pass. Design re-check (haptics + reveal) pending M0.7 + M2.3. |
| DT2 (after M3.6 + F-DESIGN-M3): the logger, in the gym | done | 2026-07-23 | Logger works on device: workout log, rest timer, numpad, paste import, history/templates/PRs. Rest-done haptic while suspended + set-logged/PR-hit feel verified. |
| DT3 (after M6.4): the loop replaces Gemini (go-live gate) | done | 2026-07-23 | Go-live verified on device: grounded chat, prescription Train, in-session coach swaps, morning brief, onboarding. F-DT3.1–3.7 landed. Manual Gemini workflow retired. |
| DT4 (after M8.2): proactivity + Watch | on hold | 2026-07-23 | Overnight battery pass (`helm-diagnostics-2026-07-23T15-41-35Z`; no `HealthKitObserverFetch` / `BackfillChunk` churn in export). Watch + rest of checklist paused: corp network blocks Watch deploy; resume off-network. Build `60a85e7`. |
| DT5 (after M11.1): nutrition, analytics, full regression | not started | | |
| DT6 (after M12.5 and M0.8): the polish gate | not started | | | Motion feel, skins, states, DeviationBand on device |

## Fix sections

| ID | Status | Date | Notes |
|---|---|---|---|
| F-DT1.1 HealthKit launch bootstrap + status UI | done | 2026-07-22 | Ingest metadata persistence, HealthKitBootstrap.start(), upgraded HealthKitStatusView, tests. |
| F-DT1.2 Watch companion install path | done | 2026-07-22 | DT1 Watch install note in PLAN.md; signing already inherited from project base. |
| F-DT1.3 Dashboard visual polish | done | 2026-07-22 | Greeting, band badge/stripe, contributor bars, secondary Ask Coach button. Superseded visually by M2.3 once M0.7 lands. |
| F-DESIGN-M3 Logger UI + haptics catch-up | done | 2026-07-23 | fa58558 | DesignSystem HelmNumpad + SetRow; WorkoutHapticPolicy/Coordinator; HelmNotificationDelegate; Train re-skin per DESIGN-SYSTEM.md + HAPTICS.md. |
| F-DT3.1 Onboarding permission-aware UI | done | 2026-07-23 | bea71fc | HealthKit connected state + refresh; notifications enabled/denied UI. |
| F-DT3.2 Training plan onboarding UX | done | 2026-07-23 | bea71fc | Weekly rate calculator; Set up later; Form layout; Continue saves if dirty. |
| F-DT3.3 Chat + coach reliability | done | 2026-07-23 | bea71fc | LocalizedError; chat error bubble; empty stream failure; JSON sanitizer. |
| F-DT3.4 AskCoachBar layout polish | done | 2026-07-23 | bea71fc | Fixed indicator frame; loading-only spinner. |
| F-DT3.5 Shortcuts honest UX | done | 2026-07-23 | bea71fc | Coming-soon copy; Morning Brief Automation guide in Settings. |
| F-DT3.6 Haptics catch-up | done | 2026-07-23 | bea71fc | sessionFinished on workout finish when no PR. |
| F-DT5.1 OpenRouter photo 404 | done | 2026-07-24 | 3c65441 | OpenRouter prompt-only JSON; error body surfaced; Gemini fallback in MealVisionRouter. |
| F-DT5.2 Coach OpenRouter picker | done | 2026-07-24 | 3c65441 | Removed OpenRouter from coach provider picker; note that OpenRouter is for photo meals. |
| F-DT5.3 Nutrition tab + Dashboard trends | done | 2026-07-24 | 3c65441 | Nutrition tab; DashboardTrendsSection; AppTabRouter. |
| F-DT5.4 Settings polish | done | 2026-07-24 | 3c65441 | Plain list styling; merged notifications guide; layout preview Card. |
| F-DT5.5 App icon | done | 2026-07-24 | 3c65441 | Treatment C arc icon in iPhone + Watch asset catalogs. |
| F-DT5.6 Nutrition transparency | done | 2026-07-24 | 3c65441 | Explain on calorie row; floor/TDEE contributors; zero TDEE treated as nil. |
| F-DT5.7 Export UI rebrand | done | 2026-07-24 | 3c65441 | Export health data copy; bioharvest wire unchanged. |
| F-DT5.8 Diagnostics refresh | done | 2026-07-24 | 3c65441 | Category filter, stack traces, share-extension OSLog in export. |
| F-DT5.9 Train sets + picker | done | 2026-07-24 | 3c65441 | Manual +/- sets; recent exercises + muscle filters in picker. |
| F-DT5.10 Watch companion | done | 2026-07-24 | 3c65441 | Phone-led companion payload; WatchCompanionView; HR auto-start. |
| F-DT5.11 Coach-editable settings | done | 2026-07-24 | 3c65441 | settings_adjustment.v1 JSON apply from chat; re-plans prescription. |
| M13.1 Planned workout UI | deferred | | | Plan-visibility absorbed by M12.8; calendar scope remains |
| M13.2 Drift policy UI | deferred | | | Mesocycle visibility absorbed by M12.8; drift indicators remain |
| M13.3 EventKit hints | deferred | | | Post-DT5 |
