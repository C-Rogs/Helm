# Plan: Helm (unified adaptive health coach, clean-slate iOS build)

> Clean-slate build. "Helm" is the confirmed name, a new app and not an extension of the lab's coach/Coacher projects. This is the single source of truth for separate Cursor build agents. **Cameron only says which section to build** (e.g. `build M3.2` or `build F-DT1.1`). The agent reads this file and `.cursor/rules/helm-build-agent.mdc`; no extra instructions are required. Every section is self-contained: goal, scope, interfaces to expose, dependencies, and acceptance criteria the agent can verify itself (build + tests + lint). Cameron does not review or test between sections; he only runs Device Test Gates (DT1 to DT7). Agents must `git commit` every finished section without asking permission. On-device verification is batched into those gates, not per-section.

## Invocation (for Cameron)

Say only:

```
build M3.2
```

or `build F-DT1.1` for a fix section. The agent loads this plan and the Helm build-agent rule, then executes the section end to end including commit and `PROGRESS.md` update. You test on device only when a DT gate's milestones are complete.

## Build agent contract (read this first, every time)

### Cameron's role vs yours

| Cameron | Build agent |
|---|---|
| Runs DT1 to DT7 on a physical device when a gate's milestones are done | Builds one plan section per session |
| Files fix sections (F-DT#.#) when a gate fails | Implements fix sections like any other section |
| Does **not** review diffs, run the app, or approve commits between sections | Commits and updates `PROGRESS.md` before ending the turn |
| Does **not** answer "should I commit?" | **Always commits.** No prompt, no confirmation, no waiting |

If your section passes agent-verifiable acceptance (build, tests, lint), commit and exit. Cameron will test at the next DT gate, not now.

1. **Scope discipline.** Build exactly the section named. Do not start the next section, do not refactor other sections' files except where an interface change is explicitly part of your section. If the section turns out to be materially bigger than described, stop and report instead of half-building.
2. **Sizing.** Each section is sized for one focused agent pass: one pure engine, one package layer, or one screen plus its wiring. If you cannot hold the whole section's file set in mind, you are doing too much.
3. **Read before writing.** Read the plan header (Locked decisions, Platform constraints, Engineering standards, the relevant engine spec) plus your section. Read every interface your section consumes in the actual code, not from memory of this document.
4. **Verification split.** Your acceptance list is agent-verifiable: the project builds under Swift 6 complete concurrency with zero warnings, SwiftLint is clean, all unit/snapshot/property tests pass, and any listed simulator-checkable behaviour works. Items requiring a physical iPhone, a physical Watch, real HealthKit data, live Gemini, or overnight battery runs are listed under the Device Test Gates and are NOT yours to verify. Never claim a device behaviour works. **Do not ask Cameron to run the app, preview a screen, or sanity-check your work; he tests only at DT gates.**
5. **Migrations are append-only.** Any section that adds tables appends a new numbered GRDB migration. Never edit a shipped migration. The migrate-up-from-every-prior-schema test must keep passing.
6. **Fixtures over live services.** LLM work is built and tested against recorded fixtures. Never call live Gemini from tests. Never log request URLs (the key travels as a query parameter).
7. **Seed content placeholders.** Exercise/evidence/methodology content is authored by Cameron. Build against the defined schema with a small clearly-marked placeholder sample (`"placeholder": true`). Never invent citations.
8. **Check `PROGRESS.md` before starting; only mark `done` after a commit lands.** Before building, read dependency rows and confirm each has a commit SHA (blank Commit = not landed). When finished, append your row with status `done`, today's date, and `git rev-parse --short HEAD`. Never edit another section's row.
9. **Auto-commit. Never ask Cameron.** Finishing a section always includes `git add` + `git commit` on your machine before you report back. **Forbidden:** "Would you like me to commit?", "Should I create a commit?", "Ready for you to review before I commit", ending the turn with uncommitted files, or asking Cameron to commit. One section = one clean commit (two commits max if code and `PROGRESS.md` must split; see Commit discipline). Never use `--no-verify`; fix hook failures and recommit. Your final message includes the commit SHA and a clean `git status`.
10. **Write it like a human engineer shipped it, not like an agent generated it.** See "Read like a human wrote it" below. This is a standing requirement on every section, not a separate cleanup pass.
11. **Instrument against the frozen contract, don't invent your own.** Read `Docs/DIAGNOSTICS.md` before writing any `OSLog`/signpost/error-capture code. Use your package's assigned category, emit the exact signpost name from the catalog if your section owns one, and route unhandled errors through the ring buffer per its contract. A section is not done until it satisfies that doc's Instrumentation gate.
12. **UI sections read the design specs.** Before any screen or DesignSystem work, read `Docs/DESIGN-SYSTEM.md` and `Docs/HAPTICS.md` (normative from M0.7). Open `Docs/Helm-Design-Proposal.dc.html` for visual reference. Re-skins of shipped sections (M0.4, M2.2, M3.3-M3.5) are append-only follow-ups (M0.7, M2.3, F-DESIGN-M3), not edits to done `PROGRESS.md` rows.

---

## Progress tracking (`PROGRESS.md`)

`PROGRESS.md`, in this same folder, is the shared status board every agent reads and appends to. `PLAN.md` stays a stable spec that nothing writes back into; `PROGRESS.md` is the mutable log of what actually happened. It exists so:

- an agent about to build M6.1 can confirm M5.5 is actually done (not just assumed from the plan) and see the exact commit it landed in;
- deviations from spec surface once, in one place, instead of getting rediscovered by every downstream section;
- Cameron can glance at one file to see what is built, in progress, or blocked, without reconstructing it from git log across dozens of commits.

**Format**: one row per section in the status table, appended (never edited) when the section is picked up and again when it's finished. Each finished row is:

```
| M#.# | Status | Date | Commit | Notes / deviations |
```

- **Status**: `not started` / `in progress (agent: <name/session>)` / `done` / `blocked (<reason>)`.
- **Commit**: the short SHA the section landed in. **Required for `done`.** Empty Commit = not landed; downstream agents must stop.
- **Notes / deviations**: anything a downstream section needs to know that isn't obvious from the code: an interface that changed shape, a scope cut, a test that had to be skipped and why, a follow-up filed. Leave blank if none. This field is the one agents actually need to read before starting dependent work; keep it honest, not padded.

**Definition of done (all required):**
1. Agent-verifiable acceptance passes (build, tests, lint).
2. Every file for this section is committed (no `??` or `M` left for your paths).
3. At least one commit with subject `[M#.#] …` (or `[F-DT#.#] …` for fix sections).
4. `PROGRESS.md` updated with commit SHA in the same commit or the immediate next one.
5. `git status` clean. Agent reported SHA + status in handoff. **No commit prompt to Cameron.**

If a section is abandoned or redone, add a new row rather than rewriting history; the log should read chronologically.

---

## Commit discipline

**Commits are automatic and mandatory.** Cameron does not test between sections and does not approve commits. If you built it and tests pass, commit it yourself before ending the turn.

### Mandatory close-out (every section, no exceptions)

1. `git status`: stage every path your section touched (`git add …`).
2. Run acceptance tests (`swift test`, `xcodebuild` as required): all green.
3. Stage `PROGRESS.md` with status `done` and date, but leave the Commit column as `TBD` for now.
4. `git commit -m "[M#.#] …"` (see format below).
5. `git rev-parse --short HEAD`: write that SHA into your `PROGRESS.md` row, then `git add PROGRESS.md && git commit --amend --no-edit` so the section lands as **one** commit with the correct SHA. Never add a second commit just to record the SHA.
6. `git status`: must be clean. Report SHA + status. **Do not ask Cameron whether to commit.**

### Rules

- One commit per finished section (or a short logical chain within it), never a commit spanning two sections.
- Message format: `[M#.#] <imperative summary>` for the subject, e.g. `[M3.2] Add active-session store with rest-timer projection`. Fix sections use `[F-DT#.#] …`. Body explains *why* only where non-obvious; no restating the diff.
- Reference the plan section, not "as requested" or conversational framing.
- Do not commit failing tests, commented-out code, or scaffolding left over from getting something to compile.
- Update `PROGRESS.md` in the same commit that finishes the section (amend after you know the SHA).
- Never commit messages like "Record commit SHA in PROGRESS"; that is a smell. Use amend instead.
- Never squash or rewrite history across sections.
- Parallel agents each commit their own section independently before exiting.
- **Never** end a turn with uncommitted section work. **Never** ask Cameron to commit, review, or test before you commit.

---

## Read like a human wrote it, not like an agent generated it

This app should read as if one disciplined iOS engineer wrote it end to end, not as a series of independently prompted patches. Concretely:

- **No AI tells.** No comments explaining what the code obviously does, no "Note: this was implemented per the plan" or "Added for M4.2" references, no apologetic comments, no leftover TODO scaffolding from getting something to compile. A comment only earns its place by explaining a non-obvious *why* (see Engineering standards).
- **One naming and structure convention throughout.** Swift API Design Guidelines followed consistently: same file layout per type (properties, init, public API, private helpers), same acronym casing, same extension-grouping style, regardless of which section or agent built it. SwiftLint enforces the mechanical part; agents are responsible for the judgment part (naming, structure) it can't catch.
- **No redundant abstractions bolted on per-section.** Before adding a new protocol, helper, or wrapper type, check whether an equivalent already exists from an earlier section (grep first). Reuse or extend it rather than duplicating a shape under a new name.
- **Commit history reads like real engineering, not a changelog of prompts.** Message format above; no commits like "fix build", "wip", "address feedback"; squash those into the section's real commit before it's considered done.
- **No dead code.** If a section supersedes something from an earlier one (rare, since dependencies are unidirectional), delete the old code in the same commit rather than leaving it unreferenced.
- **Docs and doc-comments are terse and purposeful**, matching Apple's own style, not verbose LLM-style prose. A doc-comment on a public API says what it does and any non-obvious constraint; it does not narrate the implementation.

---

## Parallel build tracks

Sections in different tracks below have no file overlap and can be built by separate agents at the same time, as long as each track's own internal ordering (left to right) is respected. Cross-track parallelism is safe for code; the one shared hazard is **`project.yml` and any GRDB migration file**, both of which are append-only, shared, single files. See the note after the tracks.

- **Wave 0 (must land first, serially)**: M0.1 then M0.2. Everything else depends on these.
- **Wave 1, parallel tracks off M0.1/M0.2**:
  - Track A (diagnostics/UI shell): M0.3 then M0.4 then M0.5 then M0.6 then **M0.7** (mostly serial, small)
  - Track B (persistence): M1.1
  - Track C (pure engines, no persistence dependency at all): M2.1 (ReadinessKit), M4.1 (CoachLLM protocol), M5.1 (PlanKit mesocycle core). These three can run **simultaneously with each other and with Track B**, since they only need `Core`.
- **Wave 2, once M1.1 lands**: Track B continues as M1.2 and M1.3 **in parallel** (both depend only on M1.1 + M0.3); separately, Track D (logger) starts: M3.1, which only needs M1.1, runs in parallel with M1.2/M1.3.
- **Wave 3**: M1.4 (needs M1.3); M3.2 then M3.3 then M3.5 and M3.6 (both off M3.1, can run parallel to each other); M4.2 (needs M4.1 + M0.6) and M4.3 (needs M1.1, parallel to M4.2); M5.2 (needs M5.1 + M3.1).
- **Design wave (current)**: **M0.7** (Track A, after M0.6) unlocks **M2.3** (readiness re-skin; append-only follow-up to shipped M2.2) and **F-DESIGN-M3** (logger haptics/UI catch-up for M3.3-M3.5, which shipped before M0.7). **M4.6** follows M2.2 and benefits from M4.5 when present. M0.8 (second layout skin) is reserved, not default v1.
- From here the tree fans generally follow the section numbering (M2.2 needs M2.1+M1.4+M0.4; M2.3 needs M0.7+M2.2; M4.4 needs M4.3+M2.1; M5.3 needs M5.2+M2.1; M6.2 needs M0.7 for provenance UI, etc). Check each section's stated "Depends on" line before assuming something can run in parallel with something else. When in doubt, run serially; the cost of a wrong parallel assumption (a merge conflict or a section built against stale interfaces) is worse than the time saved.

**Shared-file hazard.** `project.yml` (XcodeGen), `Packages/*/Package.swift`, and GRDB migration files are append-only shared files. Serialize edits or use branches; **commit** before the next parallel agent starts. Never let two uncoordinated agents merge conflicting migration numbers.

**Parallel commit rule.** Parallelism does not waive auto-commit. Each agent commits its section before exiting. Downstream agents verify dependency SHAs in `PROGRESS.md`, not uncommitted sibling work.

---

## Context: why this is being built

Today Cameron runs a manual coaching loop in Gemini: export HealthKit via **bioharvest** (schema-v2 JSON), paste it into Gemini with Hevy workout text, typed calories, and typed life context (WFH, party, "I feel sick"), and Gemini prescribes sessions, nutrition, and recovery against baselines it only remembers because they sit in one chat thread.

Three problems: Cameron is the integration layer (manual export and paste every time), it is reactive (only answers the last prompt), and it has no durable memory (baselines and programme die with the thread).

The lab proved the pieces separately: **bioharvest** (HealthKit harvest), **coach** (multi-LLM chat), **BodyBattery** (the ARC readiness algorithm), **loggy** (a Hevy-grade GRDB logger schema), **Signal** (the health-brain predecessor coach is built from, the RAG approach retired), **Coacher** (a Cloudflare Worker that mints capped keys). These are **reference and lessons only**. The new app is built clean, reusing a lab design only where it is genuinely the best design.

**Outcome:** one iPhone app plus a functional Watch companion that is a **closed-loop adaptive prescription engine**, not a persona chatbot. Metrics arrive automatically, deterministic engines compute the numbers (readiness, training volume and progression, calorie and macro targets), the prescription lands in the logger as a ready-to-go, evidence-based workout, and an LLM narrates it, grounds it in sports-science research, and adapts it live for context the sensors cannot see. It proactively opens the day with an already-adjusted plan. Personal app, no monetisation, optional TestFlight-for-friends later.

---

## Product paradigm

The plan is the product. It adapts continuously as metrics arrive and as Cameron progresses. There is no coaching "voice" whose job is encouragement; the fact that recovery is low has already changed today's prescribed session and calorie target before he looks. Chat exists to ask "why", to learn the methodology, and to negotiate changes. Science is a pillar: prescriptions cite current evidence on what most effectively trains each muscle and how to periodise.

---

## Locked decisions

| Area | Decision |
|---|---|
| Build stance | Clean-slate, highest engineering tier. Lab is reference for proven algorithms, schema design, and lessons. Do not import lab code unless it is the optimal design re-implemented cleanly. |
| Numbers | Deterministic engines compute readiness, training volume/progression, calorie/macro targets. The LLM adjusts engine output for context it cannot sense (hungover, tweaked shoulder, machine taken) by swap/reorder/reshuffle. The engine stays source of truth for the maths and **clamps every LLM-proposed adjustment to safe bounds**. |
| Prescription surfacing | Today's prescription appears in the logger as a ready-to-go workout. Each exercise shows the engine's prescribed target and the previous performance inline (Hevy style). |
| Intra-workout coach | Live in-session coach can reorder exercises, swap an exercise, and adjust remaining sets, applied structurally to the active session and logged as a recommendation, with clean undo. |
| Science / evidence | Exercise selection and periodisation are evidence-driven. The LLM grounds prescriptions in curated research and cites it. A Sources / Methodology area lets Cameron learn, see citations, and negotiate methodology and preferences. Evidence is grounding, not medical advice; keep the "coaching, not diagnosis" boundary. |
| Plan horizon | The app silently runs a managed mesocycle (RP-style MEV to MRV ramp with scheduled deload) and always points to the optimal route. Heavy readiness-driven adaptation. **Missed-workout and schedule-drift handling is core logic, not an edge case** (see PlanKit). |
| Goal model | Primary phase (cut / maintain / gain) + rate + target, plus a training emphasis (for example V-taper: shoulders and back). Changing phase re-plans everything. |
| Nutrition | **Helm-native food logging is source of truth** (search, barcode, templates, photo, quick-add, alcohol); GRDB holds rich meal detail; **Apple Health write-through** for dietary aggregates with source-bundle filtering (no re-ingest loop). Adaptive-TDEE engine on top. Brief MFP overlap during transition uses dedup policy (M14.8). Full spec: `Docs/NUTRITION-LOGGING-SPEC.md`. Photo-to-macro shipped M9.3–M9.6. |
| Training text import | Hevy "import" is a copy-paste of the day's workout text, parsed into structured sets. Not an API or CSV integration. Superseded once the built-in logger is primary. |
| Memory | Editable rolling profile the LLM reads every turn and Cameron can inspect and correct in Settings (baselines, mesocycle position, phase, preferences, standing constraints, what has worked). Ordered as a stable prefix so Gemini implicit caching applies. |
| Proactivity | Fully local. A Shortcuts automation fires an on-device App Intent (harvest + compute + Gemini + local notification). **Triggered on alarm-off / first unlock, not a fixed clock time** (HealthKit is unreadable while locked; see below). Generate-on-open fallback guarantees it is never missed. No server, no push service. |
| Proactive pushes | Morning readiness brief, pre-workout prime, post-workout post-mortem. Threshold insights surface in-app but stay silent. |
| Offline | Engines always render the numbers with no LLM. Gemini narrates and adjusts online. **v1 offline behaviour: coach unavailable, logger and numbers fully functional.** On-device narration (Apple Foundation Models) is **removed from v1 but designed for**: the provider protocol and per-provider budgets stay in place so a FoundationModelsProvider drops in later with no rearchitecting. |
| Watch | iPhone is the brain. Watch = ARC readiness complication + **live HR during an active workout, structured as a real workout**. The Watch runs an `HKWorkoutSession` of the correct activity type (run, strength, etc.), saving an `HKWorkout` with HR samples to HealthKit, so training load (Edwards TRIMP) and therefore readiness gating are fed correctly, the same way a Hevy or Apple Workout session logs. In v1. A walking skeleton is built and verified early; features land at M8. |
| Analytics | Focused decision-driving charts first (trend weight vs target, readiness history, per-muscle volume vs landmarks, e1RM progression, energy balance), expanding later. |
| Keys / devices | iPhone only. Own keys in Keychain now; pushed to the dev device via a Debug bootstrap. Provider layer + device identity designed so the existing **Coacher Cloudflare Worker** (capped free-model key minting) drops in later for TestFlight friends. |
| Data safety | The GRDB store is the system of record for training data. Manual export (DB + logs) via share sheet from M1; iCloud backup inclusion decided explicitly; restore semantics defined (HealthKit anchors reset on restore). |
| Privacy vs battery | Privacy is a low concern (data already goes to Gemini). Battery is a hard constraint, **with a measurement method** (Instruments energy log baseline + repeatable overnight test). |
| Telemetry | None. No analytics SDKs. |
| Dev diagnostics | Deep structured logging from M0, one-tap export off the phone (AirDrop/share sheet). For app performance and functional debugging, the real risk in agent-built code. |
| Backwards compatibility | The schema-v2 JSON export and copy-to-Gemini path remain intact as a built-in fallback (built at M11.1). |

---

## Platform constraints the build agents must design around

1. **HealthKit is unreadable while the phone is locked.** HealthKit data is Protected Unless Open; read access is relinquished about 10 minutes after lock and returns on next unlock. A fixed-time Shortcuts automation on a locked phone cannot harvest. Proactive briefs trigger on alarm-off / first unlock, check `isProtectedDataAvailable` at intent start, and fall back to generate-on-open. bioharvest never handled this; the new intent must.
2. **HealthKit background delivery must be explicitly enabled.** Observer-driven ingest requires `enableBackgroundDelivery(for:frequency:)` per sample type plus the HealthKit background-delivery entitlement and capability; without it, observers only fire while the app is foregrounded. Frequency budgets are type-appropriate (immediate for workouts, hourly is fine for dietary energy).
3. **Foundation Models context is 4096 tokens total** (instructions + prompt + response), with `contextSize` / `tokenCount(for:)` for budgeting. Relevant only when the later on-device narration provider is added; when built, handle `.exceededContextWindowSize` as a typed error and give it its own trimmed context budget.
4. **Gemini caching:** rely on implicit caching (default-on for 2.5 models, ~90% discount on shared prefixes, ~1 to 2k min prefix). Order the stable prefix (system prompt + profile + baselines + evidence index) first. Do not build explicit cache management (32k min + storage cost, wrong shape). The API key travels as a URL query parameter on the AI Studio endpoint; never log request URLs. Token estimate = chars / 3.5.
5. **Live-workout HealthKit teardown:** Signal's documented blank-screen bug was `HKLiveWorkoutBuilder` Error(7) plus a UIKit keyboard teardown during a live workout, not memory pressure. The Watch workout session (M8) and the custom numpad (M3.3) must handle this cleanly.

---

## Competitive gap we exploit

No shipping product closes the loop across recovery, strength, and nutrition with LLM reasoning. Recovery apps (Whoop, Oura, Bevel, Ultrahuman) have chat and readiness but are blind to sets/reps/RPE and do no real hypertrophy programming or adaptive nutrition. Strength engines (Fitbod, RP, Hevy) do rigorous progression but are closed rules-boxes with no chat; RP autoregulates off soreness only, never HRV/sleep. MacroFactor nails adaptive TDEE but is siloed. Our move: readiness-gated autoregulation spanning domains, evidence-cited exercise selection, and an LLM that narrates and negotiates. Single-user removes the constraints that force incumbents into closed, conservative formulas.

Ideas deliberately adopted: personal rolling baselines not population norms; recovery drives a daily target; adaptive TDEE from trend weight; MEV to MRV mesocycle with deloads and RIR autoregulation plus evidence-based movement selection; inspectable editable memory; auto-filled previous performance and low-friction capture; sleep-window-only HRV with artefact filtering; a "what precedes your bad days" correlation view later.

---

## Architecture (clean, from scratch)

One iPhone app plus Watch, built as modular Swift packages with a strict dependency direction. Pure engines depend only on `Core` value types, never on persistence, HealthKit, or network, so they are trivially testable and deterministic. **No on-device embedding or RAG** (retired from Signal for complexity and battery reasons; Gemini's window plus trimmed structured context plus the editable profile replaces it).

### Package graph (aim for ~5 packages, not ~10)

Micro-packages per feature make AI agents duplicate types instead of hunting imports. Consolidate:

```
App (iPhone)   WatchApp   WidgetsLiveActivity   ShareExtension   AppIntents
      \___________\____________\_________________\_______________/
                                │ composition root (DI)
   ┌───────────────┬───────────────┬───────────────┬───────────────┐
 DesignSystem     Domain          Persistence     HealthKitIngest   CoachLLM
                (pure engines)     (GRDB)          (actor)          (Gemini)
   └───────────────┴───────────────┴───────────────┴─────────────── Core + Diagnostics
```

- **Core**: Sendable value types (metrics, sets, prescriptions, phase/goal, evidence records), units, a testable `Clock`/`Calendar` abstraction, error types, and the single canonical "day boundary" function (see Time standard: a user-defined cutoff, not sleep-sample end). No I/O.
- **Diagnostics**: OSLog subsystem/categories, in-memory ring buffer, export service (share sheet / AirDrop), and a **local silent error log**: any unhandled error thrown by an engine or ingest path writes its type, context, and stack trace to the ring buffer (never crashing, never phoning home) so a silent HealthKit-parse failure in agent-built code is recoverable on export. Used by every layer.
- **Domain** (pure): the three engines as targets or folders under one package: **ReadinessKit**, **PlanKit**, **NutritionKit**. Value inputs, value outputs, zero I/O.
- **Persistence**: GRDB store with versioned migrations, value-type records, repositories, `DatabasePool`. Derived values (previous performance, e1RM, weekly volume) are computed via queries, not stored as truth.
- **HealthKitIngest**: an actor wrapping HealthKit read + write, observer-driven (no polling, background delivery enabled per type), bounded/chunked backfill, anchored queries with locally stored cursors, idempotent on sample UUIDs, **source-bundle-ID filtering so the app never re-ingests its own writes**, and anchored-query deletion handling for MFP edits/deletes.
- **CoachLLM**: LLM provider protocol (`availability`, `prewarm`, streaming `respond`, `resetThread`) with per-provider token budgets. Gemini provider is the v1 backend; OpenRouter sits behind the same protocol (disabled until minting exists); **a FoundationModelsProvider is not built in v1 but the protocol, registry, and budget map reserve its slot**. Context builder with oldest-day-first trimming, memory-profile injection ordered for implicit caching, structured-output parsing for in-session adjustments and photo-macro extraction, and **failure policy** (rate limit, timeout, offline mid-rest-timer → engine-only fallback).
- **DesignSystem**: the instrument UI layer in one package (no separate haptics or Arc packages). Normative specs: `Docs/DESIGN-SYSTEM.md` (tokens, `HelmTheme`/`HelmSkin`, `ArcGauge`, type, motion, components, thumb-reach) and `Docs/HAPTICS.md` (`HapticEngine`, twelve named patterns). M0.4 shipped a minimal token shell; **M0.7** elevates it to the full system. `ArcGauge` and `HapticEngine` live here. Visual reference: `Docs/Helm-Design-Proposal.dc.html` (browser only, not shipping code). No em dashes in copy.

### Daily compute pipeline

```
HealthKit (live, observer) ─┐
Logger sessions / pasted text ─┼─► Persistence ─► ReadinessKit ─┐
Helm food log (GRDB + HK) ─────┘                 PlanKit ───────┼─► numeric prescription (ready-to-go workout + targets)
photo-vision meals ────────────────────────────► NutritionKit ─┘        │
(MFP overlap: dedup during transition) ──────────────────────────────────┘
                                                                        ▼
              editable memory profile + baselines + evidence ─► CoachLLM (Gemini)
                                                                        │
                          narration + evidence citations + live adjustments (swap/reorder, clamped)
                                                                        ▼
                                        Dashboard cards + notification + Train screen + chat
```

The numeric prescription renders with no LLM (offline-safe). The LLM narrates, cites methodology, and applies adjustments requested in chat, flagged as context, or made live in a workout, all clamped by the engine.

---

## Engineering standards (inherited by every section)

- **Language/runtime**: Swift 6, strict concurrency = complete. Everything `Sendable`. Stateful I/O behind `actor`s (HealthKitIngest, Persistence, network clients). UI and view models `@MainActor`. State via the `@Observable` macro, never `ObservableObject`. Structured concurrency only; honour `Task.checkCancellation()` in every streaming/long loop. Do not sprinkle `@MainActor` to silence the compiler in ways that change semantics.
- **UI**: SwiftUI, iOS 26+. UIKit only where a system control is wrong for the job (notably a custom numeric keypad via `UIViewRepresentable` to avoid the live-workout keyboard teardown bug documented in Signal).
- **Architecture**: protocol-oriented with a single composition root for DI. No ambient singletons except a justified registry. Pure engines take value inputs and return value outputs, zero I/O. Repositories mediate Persistence and Core. Services behind protocols so engines and view models are testable with fakes.
- **Persistence**: GRDB, versioned migrations (migrate-up from every prior schema tested), value records, `FetchableRecord`/`PersistableRecord`. No business logic in views. Compute derived data via queries, do not persist it as truth. `DatabasePool` for concurrent reads.
- **Logging/diagnostics**: `OSLog` shared subsystem + per-module categories; a `Diagnostics` ring buffer capturing signposts and errors; one-tap export to a file via the share sheet. No `print()`. Instrument key flows with `os_signpost`.
- **Errors**: typed per-domain errors, `async throws`, mapped to friendly copy at the UI edge. Never crash on missing data; honour HealthKit nil semantics (missing is not zero; emit explicit null, keep keys present, as bioharvest does).
- **Time**: exactly one canonical "day" rule in one Core function. **Use a user-defined end-of-day cutoff (default 04:00 local), not the end of a sleep sample.** Apple Health fragments sleep into multiple samples and late nights (a 04:00 bedtime after a party) would otherwise mis-attribute Friday's recovery or Sunday's early-hours intake to the wrong day. Everything (readiness window, intake day, training day) keys off this single cutoff. Tested across DST transitions, travel, split sleep, and a night that crosses the cutoff.
- **Performance/battery budget**: observer-driven HealthKit, never polling; live HR only during an active workout, stopped on finish; Live Activities end promptly; complication updates throttled; heavy work gated on foreground stability with defined stop conditions (Signal's documented lesson); background work bounded and idempotent; lazy queries and pagination for history; no MLX/embedding models. Battery is an acceptance criterion, verified with signposts, an Instruments energy baseline, and a repeatable overnight test.
- **Project/config**: XcodeGen is the single source of truth for targets and package wiring. SwiftLint enforced (line length, no force unwrap, no `print`). A Debug-only key bootstrap loads gitignored `Secrets/` keys into Keychain (`AfterFirstUnlockThisDeviceOnly`); stripped from Release.
- **Testing posture (deliberately lean but targeted)**: three engines get real suites (below). Contract tests with recorded fixtures for LLM structured-output parsing. Everything else lands in the Device Test Gate checklists. No separate testing milestones.

### Where real tests live (the correctness spend)
1. **ReadinessKit baselines**: golden-file tests against exported real HealthKit data plus synthetic series, covering missing days, DST, travel, cold start. Guard unit correctness (SDNN not RMSSD, ms not s, kJ vs kcal).
2. **PlanKit mesocycle core**: property tests (volume never exceeds MRV, monotone progression within a meso, deload invariants) plus scenario tests for missed and reordered sessions.
3. **Persistence ingest + migrations**: fixture-driven anchored-query merge/dedup, source filtering, migrate-up-from-every-prior-schema.

---

## Visual design system (normative for all UI work)

**Thesis: an instrument, not an app.** Numbers are the hero; consistency of read, restraint, and feedback earns trust. Pure engines are never re-skinned; all visual work is DesignSystem + screen wiring.

**Normative specs (read before any UI section):**
- `Docs/DESIGN-SYSTEM.md`: color (dark + light profiles), `HelmTheme` + `HelmSkin` seam, `SkinnedContainer`, Space Grotesk + JetBrains Mono, `ArcGauge`, motion tokens, set-row/numpad/provenance components, thumb-reach rules.
- `Docs/HAPTICS.md`: `HapticEngine`, twelve named patterns in four groups, Core Haptics + `UIFeedbackGenerator` fallback, Settings toggle, Reduce Motion respect.
- `Docs/DESIGN-REPORT.md`: assessment and rationale (advisory context for architects).
- `Docs/Helm-Design-Proposal.dc.html`: visual reference artifact (open in browser; not shipping code).

**Package rule:** `ArcGauge`, `HapticEngine`, and all skin/token primitives live in the existing **`DesignSystem` package**. Do not add haptics or Arc micro-packages (~5 packages rule stands).

**Shipped-section rule:** M0.4 (tokens shell) and M2.2 (readiness wiring + first card) are **done**; do not rewrite their `PROGRESS.md` rows. Visual upgrades land as **append-only follow-ups**: M0.7 (system) and M2.3 (readiness re-skin). M3.3-M3.5 shipped before M0.7; their design threads are specified in those section definitions and implemented in **F-DESIGN-M3** after M0.7.

**Skin posture (v1):** ship one layout skin (`instrument`, card baseline) via `HelmSkin`; palette switch (dark / light / auto) ships fully. Data-sheet, State-field, and Blueprint layouts stay reserved behind the seam (optional M0.8, deferred by default). Mirrors the reserved-provider-slot pattern in CoachLLM.

**What not to do:** no second accent color, no decorative gradients, no device haptic verification in build agents (feel is DT; engine presence/safety is agent-verifiable), no em dashes in in-app copy.

---

## The engines

### ReadinessKit (re-implement ARC from the BodyBattery spec)
ARC-Readiness morning score from sleep-window SDNN HRV (HealthKit does not expose RMSSD), resting HR, sleep composite, optional respiratory rate / wrist temperature / prior-day Edwards TRIMP. Personal EWMA baselines (14-day half-life) with MAD-based robust spread and z-scores; weights approximately HRV 0.42, RHR 0.18, sleep 0.22, remainder to optionals with proportional redistribution when absent; logistic squash centring an all-at-baseline day near 58, not 50. Honest cold-start: nil under 4 valid nights ("building baseline N/4"), provisional 4 to 13 (pulled toward the anchor), full at 14+. Seed baselines from HealthKit backfill so day-1 is not blank for two weeks. The ARC spec is v0.1 design status with an acknowledged ~29% MAPE vs chest strap, valid for within-person deltas only; surface confidence labels, make no clinical claims. This score gates PlanKit and NutritionKit.

### PlanKit (the core differentiator, new)
- **Mesocycle**: 4 to 6 week blocks per muscle, weekly hard-set targets ramping MEV toward MRV, scheduled deload, then reset. Landmarks seeded from experience and refined from logged tolerance (RIR, soreness flags, performance).
- **Planned vs actual calendar + drift policy**: the data model separates the planned mesocycle from actual logged sessions. An explicit, tested policy handles a session 0, 2, or 5 days late or done out of order (shift / skip / restructure). Specified before build.
- **Progression**: per-lift estimated 1RM (Epley) from logged sets, working-weight and rep-target progression, per-muscle weekly hard-set accounting.
- **Readiness gating**: morning ARC scales today's prescribed volume/intensity. Under-recovered trims sets and caps RPE; peaking green-lights the top. Acute:chronic workload ratio guards spikes.
- **Evidence-driven selection**: an exercise-science model rates movements per target muscle (effectiveness, stretch-position bias, stimulus-to-fatigue, equipment). PlanKit picks movements to satisfy the muscle's weekly target, respecting equipment and constraints, and attaches rationale + citations for the coach to surface.
- **Prescription output**: a structured, ready-to-go session (exercises, ordered, target sets/reps/load/RPE), consumed by the Train screen. Plus an override API: flagged context or in-workout requests produce structured adjustments (swap via canonical-exercise + muscle map, reorder, drop/move), each **clamped to safe bounds** before applying. The swap request carries an **exclude list** of already-unavailable movements so the coach never re-proposes a machine that is also taken; the engine returns the next best evidence-appropriate movement not on the list.

### NutritionKit (new)
Adaptive TDEE by reconciling smoothed trend weight against logged intake (MacroFactor-style), updating weekly. Calorie target = expenditure minus phase deficit/surplus; protein per kg bodyweight; carbs/fat periodised (higher on hard days, tighter on rest/deload). Reads logged intake from GRDB meals + HealthKit dietary aggregates (write-through from Helm logging; external sources during MFP transition with dedup).

**Food reference data**: on-device **CoFID** (UK Composition of Foods, full bundle, OGL) for generic search; **Open Food Facts** API for UK branded barcode + text search with local product cache. USDA subset from M9.4 is **replaced by CoFID in M14.1**. Resolution chain: recents → CoFID → OFF → custom food. Offline: CoFID + cache only; pending import queue for branded misses.

**Macro-gap / alcohol handling**: explicit alcohol entries (M14.4) carry kcal toward TDEE; `MacroGapCalculator` attributes remaining untracked kcal (gap = total kcal minus reconstructed-macro kcal minus explicit alcohol) and must **not** distort carb/fat periodisation. Quick-add kcal-only entries count toward TDEE. Gap is a first-class field the coach can narrate.

### CoachLLM (new, clean provider layer)
Provider protocol with a registry owning one instance per backend and a local-inference gate reserved for a future on-device model. Gemini (48k budget) is the v1 backend; OpenRouter behind the same protocol for later; the FoundationModelsProvider slot is reserved (4k budget in the map) but not built in v1. Context builder trims oldest days first, skips re-sending health context on follow-up turns. Memory profile prepended every turn, ordered as a stable prefix for implicit caching. Structured output for in-session adjustments and photo-macro extraction, **with a prompt-version and output-schema-version stamped on every stored artefact** so old chat history stays parseable. Failure policy: rate limit / timeout / offline mid-rest-timer degrade cleanly to engine-only. System prompt terse, numbers-first, instructional, evidence-citing, no filler.

---

## Evidence and methodology (the science pillar)

- A local **methodology library**: evidence-based notes on movement selection per muscle, rep ranges, effective reps, stretch-mediated hypertrophy, volume landmarks, deload logic, autoregulation. **Curated and authored by Cameron; build agents only wire it, never invent citations.** Shipped as bundled seed data (JSON or SQLite) with provenance and a versioned update path.
- The coach **cites** when it prescribes, with a source reference from the curated library.
- A **Sources / Methodology screen** where Cameron browses the reasoning behind his current programme, reads citations, and negotiates preferences, which updates the memory profile and re-plans. v1 can render this as bundled markdown rather than a bespoke UI.
- Evidence is grounding, not medical advice. Keep the "coaching, not diagnosis" boundary.

---

## Exercise + evidence seed data (must exist before M5.5; schema + parser built at M5.4)

`Resources/ExerciseSeed/exercises.json`: a curated canonical exercise list with aliases, muscle taxonomy, exercise mode, and per-exercise evidence ratings + citations. **JSON in the app bundle, parsed into GRDB on first launch** (not a binary SQLite blob): it diffs cleanly in git and Cursor agents handle JSON schema updates far better than a binary. Authored by Cameron. Reuse loggy's `exercise` / `exercise_alias` canonicalisation shape. Versioned with a `seedVersion`; on version bump the parser re-imports/updates rows idempotently. This is content work, not engine work. Until Cameron's content lands, agents ship a small placeholder sample marked `"placeholder": true` so parsing and selection are buildable and testable.

---

## UX and flow

- **Dashboard (home)**: today's ARC readiness (with confidence label), the generated brief, the prescribed session summary (with any adjustment), and nutrition targets, as cards. Prominent Ask Coach into chat. Everything shown is something an engine acts on. Built incrementally: readiness card at M2.2, prescription card at M5.6, brief at M6.3, nutrition card at M9.2.
- **Train (logger, prescription-driven)**: opens today's prescribed workout ready to go. Each exercise row shows the prescribed target and the previous performance inline, plus input fields with the custom numpad. Checkmark to complete a set, auto rest timer (timestamp-projected, survives backgrounding), finish, editable history, templates, PRs. An in-workout Ask Coach applies live structural changes (reorder, swap when a machine is taken, adjust remaining sets) with undo. Paste-a-workout parses unstructured text into sets.
- **Chat**: persistent, memory-backed, one tap away. For why, learning methodology, negotiating changes. Chat history persists in GRDB (its own migration, M4.5) with prompt/schema versions stamped.
- **Nutrition**: targets vs actual for the day (targets-first layout); native food logging via multi-action FAB (search, barcode, photo, quick-add, alcohol); four meal buckets (breakfast/lunch/dinner/snacks); saved templates, recents, copy meal; editable confirm sheet shared across photo and manual paths. Spec: `Docs/NUTRITION-LOGGING-SPEC.md`.
- **Trends**: focused chart set first.
- **Sources / Methodology**: the science area above.
- **Settings**: all configuration (keys, providers, phase/goal/emphasis, notification triggers, editable memory profile, units, Watch, export/paste fallback, data export/backup, diagnostics export, Advanced).
- **Onboarding**: per-type HealthKit authorisation (read denials are invisible by design, so verify presence of data not the grant), notification permission, Gemini key entry into Keychain, Shortcuts installation for briefs, initial phase/goal, and a bounded backfill to seed baselines. Pieces are built with their features; M6.4 assembles them into one first-run flow.
- **Watch**: readiness complication tapping to the brief; live HR during an active workout, logged as a proper `HKWorkout`.

---

## Backwards compatibility, data safety, dev diagnostics

- **Backwards compat**: keep a byte-compatible schema-v2 JSON export and the copy-to-Gemini action, plus the Share-Extension import, as a permanent fallback (M11.1).
- **Data safety (from M1)**: manual export of the GRDB store + OSLog bundle via share sheet. Decide iCloud backup inclusion explicitly (default is included unless excluded). Define restore-on-new-device semantics, including that HealthKit anchors reset on restore and a re-backfill runs.
- **Dev diagnostics (from M0)**: a diagnostics screen listing recent structured logs and signposts, a global log ring buffer, and an Export action that writes a log bundle and opens the share sheet for AirDrop. For catching performance and functional regressions in agent-built code, not for validating metric accuracy.

---

## Build sections (each sized for one Composer pass)

Ordered by dependency. Each section lists Goal, Scope, Interfaces, Depends on, and agent-verifiable Acceptance. Device-only verification lives in the Device Test Gates below. The manual Gemini workflow is functionally replaced at the end of M6.

### M0 Foundation

#### M0.1 Repo, XcodeGen, app shell
- **Goal**: buildable skeleton with standards enforced from commit one.
- **Scope**: git repo, `project.yml` (App target, empty local packages `Core`, `Diagnostics`, `DesignSystem`, `Persistence`, `HealthKitIngest`, `Domain`, `CoachLLM` pre-declared so later agents never fight XcodeGen), SwiftLint config, Swift 6 complete concurrency, a minimal five-tab shell (Dashboard, Train, Chat, Trends, Settings) with placeholder views.
- **Depends on**: nothing.
- **Acceptance**: `xcodegen` + build clean with zero warnings; SwiftLint clean; app runs in simulator to the tab shell.

#### M0.2 Core package
- **Goal**: the shared vocabulary every later section imports.
- **Scope**: Sendable value types (daily metrics, body comp, sleep, workout/set, prescription, phase/goal, evidence record), units (explicit kcal/kJ, kg/lb, ms), typed base errors, testable `Clock`/`Calendar` abstraction, the single canonical day-boundary function (04:00 default cutoff, user-configurable).
- **Interfaces**: `HelmDay.day(for:cutoff:calendar:)`; `Clock` protocol; unit types.
- **Depends on**: M0.1.
- **Acceptance**: day-boundary unit tests pass across DST transitions, timezone travel, split sleep, and a night crossing the cutoff; no I/O imports anywhere in the package.

#### M0.3 Diagnostics package + screen
- **Goal**: structured logging and export before any feature code exists.
- **Scope**: implement `Docs/DIAGNOSTICS.md` exactly: the fixed subsystem/category taxonomy, the ring buffer (500-entry cap, actor-isolated, silent error capture with type + context + stack), `LogExportService` producing the specified zip schema (`manifest.json`, `ring_buffer.json`, `oslog_extract.txt`, chat/photo content excluded by default), a Settings-hosted diagnostics screen listing recent entries with an Export button.
- **Interfaces**: `DiagnosticsLog`, `LogExportService`, `os_signpost` helpers per the signpost catalog.
- **Depends on**: M0.2.
- **Acceptance**: a test log line appears on the diagnostics screen in simulator; export produces a zip matching the documented schema via the share sheet; ring buffer capped and thread-safe under strict concurrency; a deliberately thrown test error is captured to the ring buffer, not crashed.

#### M0.4 DesignSystem
- **Goal**: theme and reusable components so screens never invent styling.
- **Scope**: OLED-black theme tokens (colour, typography, spacing), card, gauge, stat row, primary/secondary buttons, chart style primitives; apply the theme to the M0.1 tab shell. No em dashes in any copy.
- **Interfaces**: theme tokens; `Card`, `Gauge`, `StatRow` components.
- **Depends on**: M0.1.
- **Acceptance**: tab shell renders themed in simulator; components have SwiftUI previews; zero hard-coded colours outside the token file.
- **Note**: shipped as minimal shell. Full instrument system is **M0.7** (append-only; do not edit this section's `PROGRESS.md` row).

#### M0.5 Watch walking skeleton
- **Goal**: prove the Watch pipeline early so M8 is features, not plumbing.
- **Scope**: WatchApp target in XcodeGen, one value round-tripped via `WCSession` application context, a stub complication, shared `Core` import on the Watch.
- **Depends on**: M0.1, M0.2.
- **Acceptance**: both targets build clean; the round-trip and complication are simulator-verifiable stubs; device verification deferred to DT1.

#### M0.6 Debug key bootstrap
- **Goal**: keys on the dev device without ever committing them. Battery measurement method is already frozen in `Docs/BATTERY.md`; this section is the bootstrap implementation only.
- **Scope**: gitignored `Secrets/` template, Debug-only bootstrap loading keys into Keychain (`AfterFirstUnlockThisDeviceOnly`), compiled out of Release.
- **Depends on**: M0.1.
- **Acceptance**: Release build contains no bootstrap symbols; missing `Secrets/` degrades with a clear diagnostic, not a crash. Record the `Docs/BATTERY.md` M0.6 baseline row (empty-shell Instruments energy log) once this section's build is on a physical device, at DT1.

#### M0.7 DesignSystem v2 (Arc, type, color, motion, haptic engine)
- **Goal**: turn the M0.4 base into a full instrument system so no screen agent invents styling, motion, or feedback.
- **Scope** (implement `Docs/DESIGN-SYSTEM.md` and `Docs/HAPTICS.md` exactly; all in the `DesignSystem` package):
  - Elevate tokens to the design-system spec as **two palette profiles (dark primary + light)**, switched by system appearance: warm-black and warm-paper surface ladders, foreground ladders, acid-lime accent (darkened for AA on light), the four-stop readiness state ramp, radius and spacing scale. Zero hard-coded colors outside the token file (M0.4 rule carries forward).
  - `HelmTheme` environment (palette: dark / light / auto, default system; explicit override in Settings) and `HelmSkin` environment (layout family). `SkinnedContainer` primitive: shared components render through it so the skin chooses Card vs ruled block vs full-bleed field vs graticule block. **v1 wires the `instrument` (card) skin only**; other layout families reserved for M0.8.
  - Register Space Grotesk and JetBrains Mono; `HelmType` scale with tabular monospaced figures on every engine number style.
  - `ArcGauge`: 270° sweep, configurable value/track/state color, optional center readout, reveal animation. Signature view for readiness, volume, energy balance.
  - Motion tokens per design-system section 6, including named readiness-reveal timeline; honor Reduce Motion.
  - `HapticEngine`: Core Haptics patterns for all twelve named events, `UIFeedbackGenerator` fallback, Settings toggle, AHAP assets bundled. Wire **selection** haptic at tab bar and segmented controls (M0.4 shell shipped without this; lands here).
- **Interfaces**: `HelmTheme`, `HelmSkin`, `SkinnedContainer`, `HelmType`, `ArcGauge`, `HapticEngine`, motion tokens.
- **Depends on**: M0.4, M0.3.
- **Acceptance**: tokens centralized; SwiftUI previews for `ArcGauge` in every state and cold-start; `HapticEngine` compiles, resolves each named pattern, no-ops safely without CHHapticEngine (unit-tested via capability abstraction); Reduce Motion path unit-tested; selection haptic wired on tab bar; SwiftLint clean; zero hard-coded colors outside token file. Real haptic *feel* is DT1 (design re-check after M2.3).

#### M0.8 Second layout skin (optional, reserved)
- **Goal**: a second full `HelmSkin` layout family selectable at runtime (in-app layout switcher).
- **Scope**: second skin treatments for every `SkinnedContainer` site and Dashboard/Train/Trends compositions; Settings control to switch skin live; persist choice.
- **Depends on**: M0.7, and whichever screens the second skin must cover.
- **Status**: **build only if Cameron wants an in-app layout switcher in v1.** Default: defer; M0.7 seam makes deferring cheap.
- **Acceptance**: switching skin re-renders every screen with no layout breakage in simulator, in both palettes; no color or layout constant outside DesignSystem; previews per skin. Feel/perf on device at next DT gate.

### M1 Data layer

#### M1.1 Persistence: health schema + repositories
- **Goal**: the GRDB store for health metrics.
- **Scope**: `Persistence` package: `DatabasePool`, migrator, migration v1 (daily metrics, body comp, sleep, nutrition days + meals), value records, repositories, in-memory test support.
- **Interfaces**: repositories for daily metrics, body comp, sleep, nutrition.
- **Depends on**: M0.2.
- **Acceptance**: migrate-up from empty passes; the migrate-up-from-every-prior-schema test harness exists and passes; repositories round-trip value records in-memory.

#### M1.2 DB export + data safety
- **Goal**: the manual backup path, from day one.
- **Scope**: DB export (checkpointed copy) + OSLog bundle via share sheet from Settings; explicit iCloud backup inclusion decision implemented; restore semantics documented (HealthKit anchors reset on restore, re-backfill runs).
- **Depends on**: M1.1, M0.3.
- **Acceptance**: export produces a valid openable SQLite file in simulator; restore behaviour documented in `Docs/DATA-SAFETY.md`.

#### M1.3 HealthKitIngest actor (live reads)
- **Goal**: live, observer-driven HealthKit ingest.
- **Scope**: `HealthKitIngest` actor: per-type authorisation requests, anchored queries with persisted cursors, `HKObserverQuery` + `enableBackgroundDelivery` per type (HRV SDNN, RHR, sleep, respiratory rate, wrist temperature, active energy, dietary energy + macros, body mass, workouts), sample-UUID idempotency, source-bundle-ID filtering (never re-ingest own writes), deletion handling for MFP edits, writes into M1.1 repositories, entitlements in XcodeGen.
- **Interfaces**: async snapshots and `AsyncStream`s per metric family; ingest status reporting. Emits the `HealthKitObserverFetch` signpost per `Docs/DIAGNOSTICS.md`, scoped per HKSampleType.
- **Depends on**: M1.1, M0.3.
- **Acceptance**: builds with entitlements; ingest logic covered by fixture-driven tests (merge/dedup, source filtering, deletion); simulator run requests authorisation and ingests seeded simulator Health data; `HealthKitObserverFetch` signpost visible in an Instruments trace. Live-device behaviour is DT1.

#### M1.4 Bounded backfill + debug data browser
- **Goal**: seed 6 months of history without wrecking first launch.
- **Scope**: chunked, resumable, off-launch-path backfill (6-month window) with progress reporting and memory bounds; baseline-seeding hook for ReadinessKit; a Debug-only data browser screen listing stored days per metric.
- **Interfaces**: `BackfillService.run(window:)` with progress; day-listing queries. Emits the `BackfillChunk` signpost per `Docs/DIAGNOSTICS.md`, scoped per chunk index.
- **Depends on**: M1.3.
- **Acceptance**: backfill runs off the main path (verified via the `BackfillChunk` signpost in Instruments, not print-debugging), is idempotent on re-run, chunk sizes bounded; browser lists ingested days.

### M2 Readiness

#### M2.1 ReadinessKit engine (pure)
- **Goal**: the ARC score, correct and tested.
- **Scope**: `Domain/ReadinessKit` exactly per the engine spec above: EWMA baselines (14-day half-life), MAD spread, z-scores, weight redistribution, logistic squash (~58 centre), honest cold-start (nil <4 nights, provisional 4 to 13, full 14+), Edwards TRIMP contribution, confidence labels. Pure: value inputs, value outputs.
- **Interfaces**: `readiness(for:) -> ReadinessScore?` with contributor breakdown + confidence; baseline state value type; `seedBaselines(from:)`.
- **Depends on**: M0.2.
- **Acceptance**: golden-file tests against exported real HealthKit data plus synthetic series pass, covering missing days, DST, travel, cold start; unit-correctness guards (SDNN not RMSSD, ms not s, kJ vs kcal).

#### M2.2 Readiness wiring + Dashboard card
- **Goal**: readiness on screen from real stored data.
- **Scope**: wire ReadinessKit to repositories, baseline seeding from the M1.4 backfill, a daily compute trigger on ingest, and the Dashboard readiness card (gauge + contributors + confidence label, "building baseline N/4" state).
- **Interfaces**: `ReadinessService` (observed by Dashboard); persisted daily scores (migration). `ReadinessService` emits the `ReadinessCompute` signpost per `Docs/DIAGNOSTICS.md` around each call into the pure `ReadinessKit.readiness(for:)` (the engine itself stays zero-I/O per the engineering standards, so the signpost lives in the wiring layer, not the engine).
- **Depends on**: M2.1, M1.4, M0.4.
- **Acceptance**: with fixture data in the store, the card renders score, contributors, and cold-start states correctly in simulator; recompute triggers on new ingest; `ReadinessCompute` signpost visible in Instruments.
- **Note**: shipped at M0.4-era visuals. Visual upgrade is **M2.3** (append-only; do not edit this section's `PROGRESS.md` row).

#### M2.3 Readiness card re-skin + reveal (append-only follow-up to M2.2)
- **Goal**: bring the shipped readiness card up to the Arc + reveal + signature-haptic spec without touching M2.2's engine wiring.
- **Scope**: replace the M2.2 gauge with `ArcGauge` from M0.7; add readiness-reveal motion timeline and **readiness-reveal** haptic, fired once per day on first Dashboard appearance (not on every recompute); state color drives arc and label; confidence and cold-start per `Docs/DESIGN-SYSTEM.md`.
- **Interfaces**: consumes `ArcGauge`, `HapticEngine`, motion tokens; "seen today" flag keyed off `HelmDay`.
- **Depends on**: M0.7, M2.2.
- **Acceptance**: card renders all readiness states and cold-start via `ArcGauge` in simulator; reveal plays once per day (unit-tested via day-boundary abstraction + seen-today flag); Reduce Motion collapses reveal to cross-fade; recompute does not re-trigger reveal. Haptic feel verified at DT1 design re-check.

### M3 Logger (manual, no prescription, no LLM)

#### M3.1 Logger persistence
- **Goal**: the loggy-grade schema, re-derived cleanly.
- **Scope**: migration v-next: sessions, blocks/supersets, sets (weight, reps, RPE/RIR, completed-at), canonical exercise + alias tables, templates, PRs (including `best_estimated_1rm` as a PR metric), exercise-history snapshot, rest-timer state as projections, and a reserved `coach_recommendation` table. Repositories plus the two key queries: previous performance per exercise, e1RM (Epley).
- **Interfaces**: session/set/template/PR repositories; `previousPerformance(exercise:)`; `estimatedOneRM(exercise:)`.
- **Depends on**: M1.1.
- **Acceptance**: migration chain passes; query correctness covered by fixture tests (previous performance picks the right prior set, e1RM matches hand-computed values).

#### M3.2 Active session engine
- **Goal**: session state machine, independent of UI.
- **Scope**: active-session store (`@Observable`, persisted continuously so a killed app recovers mid-workout), `logSet`, `completeSet`, add/remove exercise, rest-timer as a timestamp projection (no running timer state), finish/discard.
- **Interfaces**: `ActiveSessionStore`; `RestTimer` projection.
- **Depends on**: M3.1.
- **Acceptance**: unit tests: kill-and-recover restores exact state; rest projection correct across simulated backgrounding; finish writes a complete session.

#### M3.3 Train screen + custom numpad
- **Goal**: the Hevy-style logging UI.
- **Scope**: Train tab: exercise rows (previous performance auto-filled inline), set rows with weight/reps/RPE inputs via a custom numeric keypad (`UIViewRepresentable`, avoiding the system-keyboard live-workout teardown bug), checkmark completion, rest-timer display, exercise picker off the canonical exercise table, finish flow. **Design:** adopt `Docs/DESIGN-SYSTEM.md` set-row and numpad specs when M0.7 is available; fire **set-logged** haptic on set completion and **selection** haptic on numpad keys (requires `HapticEngine` from M0.7). Thumb-reach: numpad and primary actions in bottom third.
- **Depends on**: M3.2, M0.4 (M0.7 for design-spec compliance; see F-DESIGN-M3 if shipped pre-M0.7).
- **Acceptance**: a full workout logs end-to-end in simulator; previous performance auto-fills; numpad never invokes the system keyboard; SwiftUI previews for every row type; haptic calls present at set-completion and numpad-key sites (grep-level), no haptic on an already-completed row.

#### M3.4 Rest-timer alerts, Live Activity, HealthKit write
- **Goal**: the session survives backgrounding and looks native.
- **Scope**: on entering background, schedule a `UNUserNotification` at the exact end-of-rest timestamp (audible/haptic), cancel on foreground return; workout Live Activity (elapsed, current exercise, rest countdown) ending promptly on finish; on finish, write an `HKWorkout` via HealthKitIngest (source-filtered so it is never re-ingested). Emits the `WorkoutSessionLifecycle` signpost per `Docs/DIAGNOSTICS.md` (begin on session start, event on pause/resume, end on finish/discard). **Design:** fire **rest-done** haptic; ensure scheduled-notification path carries the same pattern for suspended delivery (see F-DESIGN-M3 if shipped pre-M0.7).
- **Depends on**: M3.3, M1.3.
- **Acceptance**: notification scheduling/cancellation logic unit-tested; Live Activity starts/ends in simulator; workout write path covered by the source-filter test; `WorkoutSessionLifecycle` signpost spans the full session in an Instruments trace. Suspended-app alert firing and rest-done haptic while suspended are DT2.

#### M3.5 History, templates, PRs
- **Goal**: the logger is a complete product on its own.
- **Scope**: session history list + detail (editable after finish), template create/start, PR detection + display (weight, reps, e1RM), paginated queries. **Design:** fire **PR-hit** haptic on a qualifying record, once per record (see F-DESIGN-M3 if shipped pre-M0.7).
- **Depends on**: M3.3.
- **Acceptance**: history edits persist; starting from a template pre-fills; PRs computed via queries (not stored as truth) and shown after a qualifying session in simulator; PR haptic fires exactly once per detected PR (unit-tested via detection query).

#### M3.6 Paste-a-workout parser
- **Goal**: Hevy text import so historical training data exists before PlanKit.
- **Scope**: parser from pasted Hevy-format day text to structured sets (exercise resolution via alias table, unresolved names prompt to map + save a new alias), import preview UI, fixture suite of real pasted texts.
- **Interfaces**: `WorkoutTextParser.parse(_:) -> ParsedWorkout`.
- **Depends on**: M3.1.
- **Acceptance**: fixture texts (clean, messy, partial) parse correctly; unknown exercises route through the mapping prompt; imported sessions appear in history.

#### F-DESIGN-M3 Logger UI + haptics catch-up (M3.3-M3.5 shipped pre-M0.7)
- **Goal**: implement the design threads specified in M3.3, M3.4, and M3.5 after those sections shipped without `HapticEngine` or full design-system components.
- **Scope**: re-skin Train set rows and numpad per `Docs/DESIGN-SYSTEM.md`; wire **set-logged** and **selection** (numpad) haptics; wire **rest-done** on foreground and notification paths; wire **PR-hit** once per qualifying PR; thumb-reach layout pass on Train. No engine or schema changes.
- **Depends on**: M0.7, M3.3, M3.4, M3.5.
- **Acceptance**: grep-level haptic calls at all sites listed in M3.3-M3.5 design threads; set-row/numpad match design-system spec in previews; PR and rest haptic unit tests pass; no haptic on already-completed set row. Suspended rest-done feel is DT2.

### M4 Coach plumbing

#### M4.1 Provider protocol + registry
- **Goal**: the LLM abstraction everything else codes against.
- **Scope**: `CoachLLM` package: provider protocol (`availability`, `prewarm`, streaming `respond`, `resetThread`), registry owning one instance per backend, per-provider token budget map (Gemini 48k; FoundationModels slot reserved at 4k, returns unavailable in v1; OpenRouter slot disabled), chars/3.5 estimator, typed failure policy (rate limit, timeout, offline → engine-only state), fixture-based test harness.
- **Depends on**: M0.2.
- **Acceptance**: a `MockProvider` exercises the full protocol in tests; failure policy maps every error to a typed degraded state; adding a provider requires no protocol change (compile-checked by the reserved slots).

#### M4.2 GeminiProvider + keys
- **Goal**: real Gemini behind the protocol.
- **Scope**: GeminiProvider (AI Studio endpoint, streaming SSE, structured output with schema + prompt version stamped on every artefact, key as query parameter, **request URLs never logged** per `Docs/DIAGNOSTICS.md`'s redaction rules), Keychain key management, Settings screen for key entry/provider selection, recorded-fixture contract tests for streaming and structured-output decode. Emits the `GeminiStream` signpost per the catalog, scoped per request UUID.
- **Depends on**: M4.1, M0.6.
- **Acceptance**: recorded fixtures decode (streamed chunks reassemble, structured outputs parse, schema-version mismatch handled as typed error); grep-level check that no logging call, signpost annotation, or ring-buffer context can receive a request URL; `GeminiStream` signpost spans a fixture-driven request in a test trace. Live smoke test is DT3.

#### M4.3 MemoryProfile
- **Goal**: the durable, inspectable coach memory.
- **Scope**: `MemoryProfile` value type (baselines summary, mesocycle position, phase, preferences, standing constraints, what has worked), persisted (migration), serialised deterministically as a stable prefix block for implicit caching, plus the Settings editor screen.
- **Interfaces**: `MemoryProfileStore`; `stablePrefixText()`.
- **Depends on**: M1.1.
- **Acceptance**: round-trip persistence tests; serialisation is byte-stable for identical content (snapshot test); editor edits persist in simulator.

#### M4.4 Context builder (pure)
- **Goal**: the payload assembler, snapshot-tested.
- **Scope**: pure builder assembling system prompt + memory profile + baselines + evidence index (stable prefix first) then recent days, trimming oldest-first to budget; skips re-sending health context on follow-up turns; token estimation.
- **Interfaces**: `ContextBuilder.build(profile:days:budget:turn:) -> Prompt`.
- **Depends on**: M4.3, M2.1.
- **Acceptance**: snapshot tests over fixed inputs; prefix ordering byte-stable across calls; trimming drops oldest days first and never splits the prefix.

#### M4.5 Chat UI + chat persistence
- **Goal**: streaming chat grounded in real data.
- **Scope**: Chat tab: streaming rendering, cancellation on tab-disappear, degraded offline state, chat-history persistence (migration; messages stamped with prompt/schema versions), wiring through the composition root (repositories + readiness + memory profile → context builder → provider).
- **Depends on**: M4.2, M4.4, M2.2.
- **Acceptance**: chat works end-to-end against the mock provider in simulator with real stored fixture data in context; history persists across relaunch; offline state renders cleanly. Live grounded chat is DT3.

#### M4.6 "Show your working" sheet (tap-to-explain)
- **Goal**: one consistent affordance to interrogate any engine number ("why 61?", "why minus two sets?").
- **Scope**: reusable explain sheet taking a number, contributor breakdown, and optional citation reference; long-press or info affordance on any engine readout; **Ask coach about this** hand-off seeding a chat turn (disabled offline); **selection** haptic on open. Degrades to engine-only contributors when coach unavailable.
- **Interfaces**: `ExplainSheet` (or equivalent), `ExplainableMetric` input model, optional chat hand-off.
- **Depends on**: M2.2, M0.7. Benefits from M4.5 (chat) and M10.2 (methodology) when present.
- **Acceptance**: sheet renders from fixture inputs for readiness, prescription volume, and a nutrition target; offline shows engine contributors with coach hand-off disabled; snapshot tests per input type.

### M5 Planning

#### M5.1 PlanKit mesocycle core (pure)
- **Goal**: the mesocycle maths, property-tested.
- **Scope**: `Domain/PlanKit`: mesocycle blocks (4 to 6 weeks per muscle), weekly hard-set targets ramping MEV→MRV, scheduled deload + reset, landmark seeding + refinement from logged tolerance (RIR, soreness, performance), per-muscle weekly hard-set accounting, progression (e1RM, working weight, rep targets).
- **Interfaces**: `MesocycleState`; `progression(for:history:)`.
- **Depends on**: M0.2.
- **Acceptance**: property tests pass: volume never exceeds MRV, monotone progression within a meso, deload invariants hold.

#### M5.2 Planned-vs-actual calendar + drift policy
- **Goal**: schedule drift as core logic.
- **Scope**: data model separating planned mesocycle from actual logged sessions (migration for plan state); the explicit drift policy (session 0/2/5 days late, out of order → shift/skip/restructure), written as a short spec section in code comments before implementation; scenario tests.
- **Interfaces**: `resolveDrift(planned:actual:) -> PlanAdjustment`.
- **Depends on**: M5.1, M3.1.
- **Acceptance**: scenario tests for each drift case pass and encode the written policy; acute:chronic workload ratio guard covered.

#### M5.3 Prescription + readiness gating + clamps
- **Goal**: the daily numeric prescription.
- **Scope**: `prescription(for:givenReadiness:profile:history:) -> PrescribedSession` (ordered exercises, target sets/reps/load/RPE); readiness gating (low ARC trims volume and caps RPE, high green-lights); the adjustment API `apply(adjustment:excluding:)` with safe-bound clamping and the exclude list contract (a swap never returns an excluded movement).
- **Depends on**: M5.2, M2.1.
- **Acceptance**: unit tests: low-readiness prescriptions are strictly lighter; clamps reject out-of-bounds adjustments; exclude list honoured across repeated swaps; changing phase re-plans.

#### M5.4 Exercise seed schema + import
- **Goal**: the seed pipeline, buildable before Cameron's content lands.
- **Scope**: `Resources/ExerciseSeed/exercises.json` schema (canonical exercises, aliases, muscle taxonomy, mode, evidence ratings + citations, `seedVersion`), first-launch parse into GRDB, idempotent re-import on version bump, a placeholder sample marked `"placeholder": true`. Never invent citations.
- **Depends on**: M3.1.
- **Acceptance**: import + re-import idempotency tests pass; placeholder sample round-trips; version bump updates rows without duplicates.

#### M5.5 Evidence-driven selection + citations
- **Goal**: prescriptions pick the right movements and say why.
- **Scope**: selection model rating movements per target muscle (effectiveness, stretch-position bias, stimulus-to-fatigue, equipment/constraints), satisfying weekly targets; rationale + citation attachment on each prescribed exercise, consumed later by the coach.
- **Depends on**: M5.4, M5.3.
- **Acceptance**: with seed fixtures, selection satisfies weekly muscle targets under equipment constraints; every selected movement carries rationale + citation references; excluded/unavailable movements never selected.

#### M5.6 Phase/goal setup + Dashboard prescription card
- **Goal**: the plan is visible and configurable.
- **Scope**: phase/goal/emphasis model in Settings (and reused later by onboarding), persisted; changing phase triggers re-planning; Dashboard card summarising today's prescribed session. The wiring layer that calls the pure `PlanKit.prescription(for:givenReadiness:profile:history:)` emits the `PrescriptionCompute` signpost per `Docs/DIAGNOSTICS.md` (the engine itself stays zero-I/O).
- **Depends on**: M5.3, M2.2.
- **Acceptance**: phase change visibly re-plans in simulator with fixture history; card renders the prescribed session summary; `PrescriptionCompute` signpost visible in Instruments around each compute call.

### M6 Closing the loop

#### M6.1 Prescription-driven Train screen
- **Goal**: today's plan opens ready to go.
- **Scope**: Train opens today's `PrescribedSession` as the active workout; each exercise row shows the engine's target and previous performance inline; deviations from target logged as-is; falls back to manual/template start when no prescription exists.
- **Depends on**: M5.5, M3.3.
- **Acceptance**: with fixture prescription + history, the session opens pre-populated with targets and previous values in simulator; manual fallback intact.

#### M6.2 In-session coach
- **Goal**: live structural adjustments with undo.
- **Scope**: `askCoachInSession` returning structured reorder/swap/adjust (via the M4.2 structured-output path), applied through `apply(adjustment:excluding:)` to the active session, exclude list accumulating across repeated swaps in one session, clean undo stack, every applied adjustment written to `coach_recommendation`. **Design:** every applied adjustment renders in the shared **provenance** treatment from `Docs/DESIGN-SYSTEM.md` (labeled, reversible diff banner on Train); fires **coach-adjust** haptic on apply (undo restores cleanly).
- **Depends on**: M6.1, M4.5, M5.3, M0.7.
- **Acceptance**: with fixture structured outputs: swap/reorder/adjust apply and undo cleanly; a second "also taken" swap returns a different movement; recommendations logged; adjustment banner matches provenance component; coach-adjust haptic fires on apply. Live in-gym behaviour is DT3.

#### M6.3 Morning brief on open
- **Goal**: the app opens with the day already decided; the manual Gemini loop is now replaced.
- **Scope**: generate-on-open brief: readiness + prescription + nutrition targets composed by the engines, narrated by the coach (with citations) when online, engine-only card when offline; rendered as the Dashboard brief card; brief persisted per day (no regeneration spam).
- **Depends on**: M6.1, M4.5, M2.2.
- **Acceptance**: opening the app with fixture data renders the brief; offline renders the engine-only version; the brief regenerates only when inputs change.

#### M6.4 Onboarding assembly
- **Goal**: one coherent first-run flow from the pieces already built.
- **Scope**: sequence: per-type HealthKit authorisation (verify presence of data, not the grant, since read denials are invisible), notification permission, Gemini key entry, initial phase/goal, bounded backfill with progress, pointer to the Shortcuts guide (guide itself lands at M7.2).
- **Depends on**: M6.3, M1.4, M4.2, M5.6.
- **Acceptance**: fresh-install simulator run walks the full flow and lands on a working Dashboard; every step skippable and re-enterable from Settings.

### M7 Proactivity

#### M7.1 GenerateBriefIntent (locked-phone aware)
- **Goal**: the brief fires from Shortcuts without the app open.
- **Scope**: `AppIntents` target: `GenerateBriefIntent` (check `isProtectedDataAvailable` first, harvest + compute + narrate + local notification; if locked, record the miss and let generate-on-open catch it), bounded runtime, full diagnostics logging. Emits the `BriefIntentRun` signpost per `Docs/DIAGNOSTICS.md`, scoped per invocation.
- **Depends on**: M6.3.
- **Acceptance**: intent runs in simulator and produces the notification; locked-state code path unit-tested via the protected-data check abstraction; `BriefIntentRun` signpost spans the full invocation. Real alarm-off trigger is DT4.

#### M7.2 Notification triggers + Shortcuts guide
- **Goal**: the three pushes plus setup.
- **Scope**: notification content builders (morning brief, pre-workout prime, post-workout post-mortem), trigger logic (pre: ahead of the planned session window; post: on workout finish), threshold insights surfacing in-app but silent, and a Settings screen guiding Shortcuts automation setup (alarm-off / first-unlock).
- **Depends on**: M7.1, M6.1.
- **Acceptance**: content builders snapshot-tested; post-workout notification fires on finish in simulator; guide screen complete.

### M8 Watch features

#### M8.1 Watch workout session
- **Goal**: live HR as a proper workout, Watch-authoritative.
- **Scope**: on the M0.5 skeleton: activity-type picker, `HKWorkoutSession` + `HKLiveWorkoutBuilder` (careful teardown per the documented Error(7) lesson), live HR/zones during the session only, saving an `HKWorkout` of the correct type with HR samples on finish. Start/stop is Watch-authoritative; no WCSession dependency for state. Emits `WorkoutSessionLifecycle` (Watch side) and `LiveWorkoutBuilderTeardown` per `Docs/DIAGNOSTICS.md`, both scoped per session.
- **Depends on**: M0.5, M1.3.
- **Acceptance**: Watch target builds; session state machine unit-tested (start/pause/end/teardown paths); simulator session saves a workout; both signposts visible in a Watch Instruments trace spanning a simulated session. Real HR + battery is DT4.

#### M8.2 Phone observation + readiness complication
- **Goal**: the phone learns from HealthKit, not messages; readiness on the wrist.
- **Scope**: phone-side `HKObserverQuery`/anchored query on the workout type detects Watch sessions (WCSession used only for opportunistic low-latency HR display, never as source of truth); finished workouts feed Edwards TRIMP into readiness; the complication shows today's readiness (pushed via application context, throttled) and taps through to the brief.
- **Depends on**: M8.1, M2.2.
- **Acceptance**: fixture-driven test: an observed `HKWorkout` updates training load and next-day readiness inputs; complication renders in the Watch simulator gallery. End-to-end wrist flow is DT4.

### M9 Nutrition

#### M9.1 NutritionKit engine (pure)
- **Goal**: adaptive targets, tested.
- **Scope**: `Domain/NutritionKit` per the engine spec: adaptive TDEE from smoothed trend weight vs logged intake (weekly update), calorie target from phase, protein per kg, carb/fat periodisation by day type, and the macro-gap/alcohol field (gap = kcal minus reconstructed-macro kcal, surfaced separately, never distorting periodisation).
- **Interfaces**: `targets(for:phase:trend:) -> MacroTargets` (including the gap field).
- **Depends on**: M0.2.
- **Acceptance**: unit tests: TDEE converges on synthetic series; targets shift correctly across phases and day types; alcohol-day fixtures do not distort carb/fat splits.

#### M9.2 Nutrition screen + Dashboard card
- **Goal**: targets vs actual, visible daily.
- **Scope**: Nutrition screen (targets vs HealthKit actuals for the day, weekly TDEE trend), Dashboard nutrition card, wiring NutritionKit to repositories and the readiness/plan day-type signal.
- **Depends on**: M9.1, M2.2.
- **Acceptance**: with fixture intake data, targets vs actual render correctly, including the alcohol-gap presentation.

#### M9.3 Photo-to-macro
- **Goal**: the MFP-premium gap, natively.
- **Scope**: photo capture/pick, Gemini-vision extraction via the M4.2 structured-output path (`estimateMacros(image:) -> MealEstimate`), editable confirm sheet, write-through to HealthKit as a meal (source-filtered against re-ingest), failure/offline handling.
- **Depends on**: M9.2, M4.2, M1.3.
- **Acceptance**: fixture images decode to editable estimates; confirmed meals write through the HealthKit path and the dedup test proves no re-ingest. Real-food accuracy is DT5.

#### M9.4 USDA reference bundle + NutritionLookup
- **Goal**: deterministic macro math from identified foods.
- **Scope**: `NutritionKit` package additions: bundle USDA FoodData Central SR Legacy subset (~1,500–2,500 athlete-relevant foods) as compressed JSON in `NutritionKit/Resources/`; `NutritionFoodRecord` (fdc_id, description, per-100g kcal/P/C/F); `NutritionLookup` with normalized string match + synonym table; `MacroAggregator.sum(lineItems:) -> MealEstimate` (totals + confidence = min item confidence). Extend `MealEstimate` + `MealLineItem` in Core.
- **Depends on**: M9.3.
- **Acceptance**: lookup resolves ≥90% of a 20-item fixture list; aggregator tests pass; no network; bundle < 5 MB.
- **Note**: USDA bundle **superseded by full UK CoFID in M14.1**; interfaces (`NutritionLookup`, `NutritionFoodRecord`, `MacroAggregator`) remain.

#### M9.5 Grounded photo pipeline
- **Goal**: replace direct macro hallucination with decompose → lookup → sum.
- **Scope**: `meal_decomposition.v1` schema + prompt versions in CoachLLM; `MealVisionProviding` protocol; `GeminiMealVisionProvider` (stronger free vision model pin, not Flash-Lite); `GroundedPhotoMacroEstimator` (vision → lookup each item + implicitFats → aggregate → `MealEstimate` with `lineItems`); unresolved items use conservative generic fallback with `.low` confidence. Deprecate direct `GeminiProvider.estimateMacros` production path; redirect `PhotoMacroEstimator` to grounded estimator. Fixture tests for full pipeline (recorded decomposition JSON → lookup → totals).
- **Depends on**: M9.4, M4.2.
- **Acceptance**: fixture images produce line items + totals; no live API in tests; `meal_estimate.v1` HealthKit write path unchanged.

#### M9.6 OpenRouter vision + confirm sheet v2
- **Goal**: free OpenRouter path for TestFlight; user can see and edit ingredients.
- **Scope**: `OpenRouterMealVisionProvider` (OpenAI-compatible `/api/v1/chat/completions`, `response_format: json_schema`, base64 image; never log URLs); `MealVisionRouter` (OpenRouter key → `google/gemma-3-27b-it:free`, else Gemini key → `gemini-2.5-flash`); wire in `NutritionBootstrap`. `PhotoMealConfirmSheet` v2: expandable line-item rows (name, grams, item kcal); totals read-only derived from edits; editing grams recomputes via `MacroAggregator` on-device. `PhotoMealLocalStore` persists line items for audit. Optional Settings "Photo model" row (Auto / Gemini / OpenRouter) behind Advanced.
- **Depends on**: M9.5, M11.2.
- **Acceptance**: router selects backend from Keychain; confirm sheet edits grams and recomputes totals; OpenRouter fixture tests pass; build + lint clean.

#### M9.7 LiDAR portion assist (optional, post-DT5)
- **Goal**: portion accuracy without extra API calls.
- **Scope**: on Pro iPhones, attach depth metadata or scale factor from `AVDepthData` / ARKit to vision prompt context; or multiply gram estimates by depth-derived volume ratio.
- **Depends on**: M9.6, DT5 photo accuracy feedback.
- **Acceptance**: DT5 subset shows improved gram estimates vs RGB-only on same meals.
- **Status**: done (agent-verifiable pipeline + unit tests; device gram improvement verified at next photo soak).

### M14 Native food logging

Full spec: `Docs/NUTRITION-LOGGING-SPEC.md`. Replaces MFP on phone. GRDB rich detail + HealthKit write-through. CoFID on-device + Open Food Facts online.

#### M14.1 CoFID bundle replaces USDA
- **Goal**: UK food reference data on-device for search and photo grounding.
- **Scope**: Download full McCance & Widdowson CoFID 2021 dataset; convert to `NutritionKit/Resources/cofid_foods.json`; remove USDA bundle; update `NutritionLookup` + tests + `GroundedPhotoMacroEstimator` to resolve against CoFID; OGL attribution string in Sources/Methodology. Keep `NutritionFoodRecord` shape (food code in `fdcId` column or rename with migration note in code comments only).
- **Depends on**: M9.4, M9.5.
- **Acceptance**: lookup resolves ≥90% of a 20-item UK fixture list; photo pipeline fixture tests pass with CoFID; bundle builds; no network; SwiftLint clean; migrate-up tests still pass.

#### M14.2 Food log persistence (GRDB v10)
- **Goal**: schema for rich meals, line items, templates, cache, offline queue.
- **Scope**: `v10_food_logging` migration: `meal.bucket`, `meal_line_item`, `food_product_cache`, `food_portion_preference`, `meal_template` + `meal_template_item`, `pending_food_import`, `food_log_recent`; Core models (`MealBucket`, `FoodProductRef`, `MealLineItemRecord`, `FoodPortionPreference`, `MealTemplate`, `PendingFoodImport`); extend `MealRecord.Source`; repositories in Persistence; `SchemaVersion.latest = 10`.
- **Depends on**: M14.1, M1.1.
- **Acceptance**: migrate-up from v9; round-trip CRUD fixture tests for meals, line items, templates; no force unwraps.

#### M14.3 Food resolver + Open Food Facts client
- **Goal**: branded UK lookup chain with local cache.
- **Scope**: `OpenFoodFactsClient` in HealthKitIngest (or new `FoodIngest` target if needed, prefer HealthKitIngest to stay within package budget): barcode GET + text search per OFF API guide; `FoodResolver` actor: recents → CoFID → OFF → custom; `food_product_cache` writes; offline detection + `NetworkGate` for OFF calls; no API key; user-agent header per OFF requirements; never log full URLs with query params in production logs.
- **Depends on**: M14.2.
- **Acceptance**: fixture tests with recorded OFF JSON (no live network in CI); resolver chain unit tests; cache hit skips network.

#### M14.4 ManualMealService + HK write-through
- **Goal**: log food without photo; quick-add and alcohol.
- **Scope**: `ManualMealService` parallel to `PhotoMealService`: search pick → portion → bucket → GRDB persist + `MealHealthKitWriter`; quick-add kcal-only (`MealRecord.Source.quickAdd`); explicit alcohol entry type with drink presets; extend `HelmHealthKitMetadata.meal_source` values; `NutritionActualResolver` prefers GRDB meal sums; quick-add kcal counts toward TDEE in `NutritionTrendBuilder`.
- **Depends on**: M14.3, M9.2.
- **Acceptance**: fixture meal logs to GRDB + fake HK writer; TDEE test includes quick-add kcal; alcohol entry reduces macro gap correctly; dedup test: own HK writes not re-ingested.

#### M14.5 Search + barcode UI + MealLineItemEditor
- **Goal**: add food from Nutrition tab.
- **Scope**: Extract shared `MealLineItemEditor` from `PhotoMealConfirmSheet` (photo path adopts it); `FoodSearchView` (CoFID local + OFF remote results, offline banner); `BarcodeScannerView` (AVFoundation); add-food flow with smart portion step (packaged = last serving, produce = grams); wire to `ManualMealService`.
- **Depends on**: M14.4, M0.7.
- **Acceptance**: previews for search, scanner, editor; search resolves fixture foods; barcode fixture flow logs meal; photo confirm still works via shared editor; SwiftLint clean.

#### M14.6 Nutrition tab meal buckets + multi-action FAB
- **Goal**: log-first meal list below targets card.
- **Scope**: `NutritionView` keeps targets-first `NutritionDaySummaryCard` hero; below: four bucket sections with today's `MealRecord` + line item summaries; multi-action FAB (search / barcode / photo / quick-add / alcohol); `FoodLogTipStore` one-time tip (not onboarding step); empty states per bucket per DESIGN-SYSTEM.
- **Depends on**: M14.5, F-DT5.3.
- **Acceptance**: previews per bucket state; FAB presents all actions; logged meal appears in correct bucket without relaunch; haptics on log success (`HapticEngine` confirm pattern).

#### M14.7 Recents, portion memory, templates, copy meal
- **Goal**: repeat logging in ≤3 taps.
- **Scope**: `food_portion_preference` read/write on log; recents strip on search; `MealTemplate` CRUD + "log template" (1-tap with confirm); copy single bucket to today; copy yesterday's meals to today; template save from bucket header.
- **Depends on**: M14.6.
- **Acceptance**: fixture: log yogurt twice → second log defaults to "1 pot"; template logs 7-item breakfast in one action; copy meal duplicates line items to target day; unit tests for portion preference round-trip.

#### M14.8 Edit/delete history + HK sync + MFP dedup
- **Goal**: retroactive edits; safe MFP overlap.
- **Scope**: Edit past meal (any day): update GRDB line items + re-write HK samples (delete-by-meal_id + save); delete meal removes GRDB + HK; `DietarySourceMerger` in HealthKitIngest: Settings toggle `Helm only | Merge external`; merge mode dedups overlapping external HK entries (±15 min, ±10% kcal → prefer Helm); edit propagates to `nutrition_day` aggregates.
- **Depends on**: M14.7, M1.3.
- **Acceptance**: fixture edit changes totals; delete removes HK samples in fake store; merger tests: Helm+MFP duplicate → single count; migrate-up passes.

#### M14.9 Offline pending import queue
- **Goal**: log at work without network; enrich later.
- **Scope**: Offline banner on search when OFF unreachable; barcode/search miss while offline → `PendingFoodImport` row + provisional meal OR block with photo suggestion; on reconnect background task resolves queue via OFF; user notification optional (local only); retroactive edit of resolved imports.
- **Depends on**: M14.8.
- **Acceptance**: fixture offline log creates pending row; simulated reconnect resolves to cached product; CoFID search works airplane-mode in simulator; build clean.

### M10 Analytics and methodology

#### M10.1 Trends charts
- **Goal**: the focused decision-driving set.
- **Scope**: Trends tab: trend weight vs target, readiness history, per-muscle weekly volume vs landmarks, e1RM progression per lift, energy balance. Lazy/paginated queries; DesignSystem chart primitives. **Design:** per-muscle volume-vs-landmark and energy balance use `ArcGauge`; charts use the four-stop state ramp only (no arbitrary colors).
- **Depends on**: M2.2, M5.6, M9.2, M0.7.
- **Acceptance**: all five charts render from fixture data; queries paginated (no full-table loads); previews per chart; volume and energy charts consume `ArcGauge` and state-ramp colors only.

#### M10.2 Sources / Methodology screen
- **Goal**: the science area.
- **Scope**: methodology browser (bundled markdown acceptable for v1) with citations from the seed library; preference negotiation flows that update the MemoryProfile and trigger a re-plan.
- **Depends on**: M5.5, M4.3.
- **Acceptance**: methodology renders with citations; changing a preference updates the profile and visibly re-plans in simulator.

### M11 Compatibility and sharing

#### M11.1 Schema-v2 export + Share Extension (backwards compat)
- **Goal**: the permanent manual fallback.
- **Scope**: byte-compatible schema-v2 JSON export (18:00 to 18:00 sleep window, explicit-null semantics, keys always present, matching bioharvest), copy-to-Gemini action, Share-Extension import target.
- **Depends on**: M1.3.
- **Acceptance**: exported JSON byte-matches a bioharvest golden file for the same fixture inputs; Share Extension builds and imports a payload in simulator.

#### M11.2 Sharing via Coacher (later, optional)
- **Goal**: capped free-model key minting for TestFlight friends, reusing the existing Coacher Cloudflare Worker (or cut entirely; friends build from source).
- **Depends on**: M4.1.
- **Acceptance**: a device provisions a capped free-models-only key without an account. Note the shared-secret-in-binary caveat (friends-only, not App Store).

---

## Device Test Gates (batched physical testing; not for build agents)

Device testing is slow, so it is consolidated into six gates. **This is the only point Cameron tests the app.** Build agents never block on gates, never ask Cameron to run the app mid-section, and never wait for his approval before committing. Cameron runs each gate as one sitting when the listed milestones are done; failures are filed back as targeted fix sections (F-DT#.#), which agents implement and **commit** like any other section.

### DT1 after M2.2: foundation + ingest + readiness (first device install)
- HealthKit authorisation flow on a real iPhone; real data (including MFP calories) ingests live with no manual export and persists across relaunch.
- Background delivery: log a meal in MFP with Helm backgrounded; it arrives without opening the app (or on next open via anchored catch-up).
- 6-month backfill completes off the launch path with no memory spike (Instruments) and is idempotent on re-run.
- The app never re-ingests its own writes (write a test sample, confirm no echo).
- Readiness renders with real data: contributors, confidence, honest cold-start (or seeded baselines from backfill).
- Diagnostics export lands on the Mac via AirDrop; Watch skeleton installs, round-trips a value, and shows the stub complication.
- Record the Instruments energy baseline per `Docs/BATTERY.md`.

**Design re-check (after M2.3; run before or as part of next DT session once M0.7 + M2.3 land):**
- Each named haptic in `Docs/HAPTICS.md` *feels* correct on a real iPhone (CHHapticEngine present).
- Readiness reveal plays once per day on first Dashboard open and feels like the signature moment; recompute does not replay it.
- Reduce Motion collapses reveal to cross-fade; Settings haptics-off toggle honored.

**Watch install (debug builds):** Run the Helm scheme from Xcode with your **iPhone** selected (not the Watch). The Watch app embeds in the iPhone build and auto-installs to the paired Watch within ~60 seconds. Do not install from the Watch app's Available Apps list: that path fails for developer builds with "could not install at this time". If the Watch app is missing after an iPhone install, open Window → Devices and Simulators, select the paired Watch, confirm Helm appears under installed apps, then Run again from Xcode.

### DT1 fix sections (filed 2026-07-22)

Targeted fixes filed from Cameron's first DT1 session. Build agents implement these before Cameron re-runs the DT1 checklist.

#### F-DT1.1 - HealthKit launch bootstrap + truthful status UI

- **Depends on:** M1.3, M1.4, M2.2
- **Goal:** After relaunch, HealthKit screen shows connected state and last-known sync info without re-tapping Request Access; observers restart automatically.
- **Scope:** Persist ingest metadata alongside anchors; `HealthKitBootstrap.start()` on launch; upgrade HealthKit status UI with Connection row, last loaded time, stored-day count; tests for metadata round-trip and bootstrap path.
- **Acceptance:** Build + tests pass; simulator authorize-once → kill → relaunch shows connected + last sync without button tap.

#### F-DT1.2 - Watch companion install path

- **Depends on:** M0.5
- **Goal:** Reliable Watch install during DT1; clear doc when user tries Watch App Store path.
- **Scope:** Verify embed chain and signing on watch targets; DT1 troubleshooting note (above).
- **Acceptance:** Run from Xcode to iPhone → Helm on Watch within ~60s; Watch Sync round-trip; stub complication visible.

#### F-DT1.3 - Dashboard visual polish

- **Depends on:** M0.4, M2.2
- **Goal:** BodyBattery-inspired hero layout: band colour, contributor bars, greeting. Not a DT1 blocker.
- **Scope:** Greeting header, band badge + accent stripe, contributor progress bars, secondary Ask Coach button.
- **Acceptance:** Dashboard renders all readiness states with improved visual hierarchy; no behaviour change to readiness math.

### DT3 fix sections (filed 2026-07-23)

Targeted fixes from Cameron's DT3 session.

#### F-DT3.1 - Onboarding permission-aware UI

- **Depends on:** M6.4, F-DT1.1
- **Goal:** HealthKit and notification onboarding steps hide redundant connect buttons when already authorized.
- **Scope:** Gate HealthKit step on `HealthKitIngestStatus.connectionState`; show connected status + refresh; notifications show enabled state or Settings deep link when denied.
- **Acceptance:** Re-entry from Settings Setup shows correct states; build + tests pass.

#### F-DT3.2 - Training plan onboarding UX

- **Depends on:** M5.6, M6.4
- **Goal:** Step 4 usable when weekly kg rate unknown.
- **Scope:** Weekly rate calculator sheet; "Set up later" skip; Form layout fix; Continue saves if dirty.
- **Acceptance:** Calculator unit test; empty weekly rate allowed; onboarding skip path works.

#### F-DT3.3 - Chat + in-session coach reliability

- **Depends on:** M4.5, M6.2
- **Goal:** Coach failures surface readable errors; chat never silently drops a turn.
- **Scope:** `LocalizedError` on coach errors; chat error banner + inline bubble; empty-stream failure; JSON sanitizer; structured-output decode diagnostics.
- **Acceptance:** CoachLLM tests pass; chat failure shows user-visible message; no cryptic "error 1".

#### F-DT3.4 - AskCoachBar layout polish

- **Depends on:** M6.2, M0.7
- **Goal:** Pulse indicator stays anchored during loading.
- **Scope:** Fixed indicator frame; hide pulse when loading; loading-only ProgressView.
- **Acceptance:** DesignSystem previews for idle + loading; build clean.

#### F-DT3.5 - Shortcuts honest UX (until M7.1)

- **Depends on:** M6.4
- **Goal:** Stop promising Shortcuts actions that do not exist yet.
- **Scope:** Onboarding + Settings placeholder guide for morning brief automation; no fake Helm action copy.
- **Acceptance:** Grep shows no "Helm brief action" claim; guide renders in Settings.

#### F-DT3.6 - Haptics catch-up

- **Depends on:** F-DESIGN-M3
- **Goal:** Wire `sessionFinished` on workout finish; rest count-in path verified.
- **Scope:** `sessionFinished` on finish (PR still wins); rest timer hook unchanged but verified.
- **Acceptance:** Rest haptic policy tests pass; finish path calls sessionFinished when no PR.

### DT2 after M3.6 (+ F-DESIGN-M3): the logger, in the gym
- A full real workout logs cleanly; previous performance auto-fills; the numpad never blanks the screen (the Signal teardown bug).
- Rest timer: background the app mid-rest and lock the phone; the end-of-rest alert fires while suspended; returning early cancels it and the projection is correct.
- **Rest-done haptic fires while the app is suspended** (via the scheduled notification path), not only in-foreground.
- Set-logged and numpad selection haptics feel correct one-handed mid-set.
- PR-hit haptic fires once on a qualifying record.
- Live Activity shows on the Lock Screen and ends promptly on finish; the finished workout appears in Apple Health and is not re-ingested.
- Paste a real Hevy day; it parses, unknown exercises map, the session lands in history. Templates, history edits, and PR detection behave.

### DT3 after M6.4: the loop replaces Gemini (go-live gate)
- Live Gemini: chat answers grounded in real health + training data; memory profile edits take effect next turn; airplane mode degrades cleanly everywhere (chat, brief, mid-rest-timer).
- Today's real prescription opens in Train with targets + previous inline; low-readiness day visibly trims the session; phase change re-plans.
- In the gym: "machine taken" swap and reorder apply live and undo cleanly; a second swap for an also-taken machine returns a fresh alternative; recommendations are logged.
- Morning brief renders on open with citations; fresh-install onboarding runs end to end on a wiped device.
- **Exit criterion: the manual Gemini workflow is retired.**

### DT4 after M8.2: proactivity + Watch
- Real alarm-off / first-unlock Shortcuts automation fires the morning brief notification; a locked-phone run degrades gracefully and generate-on-open catches it; pre- and post-workout pushes fire on the right real triggers.
- Watch: start a real workout on the wrist; live HR streams only during the session; the phone detects the workout via HealthKit observation even with WCSession dead (test with phone out of range); the saved `HKWorkout` has the correct activity type and its training load appears in next-day readiness.
- Complication shows today's readiness and taps to the brief; updates are throttled.
- The repeatable overnight battery test passes against the DT1 baseline (signposts reviewed for observer churn).

### DT5 after M11.1: nutrition, analytics, full regression
- Photograph plate, packaged, and mixed meals: confirm sheet shows ingredient breakdown (not one blob); totals change when grams are edited (on-device recompute); same meal re-photographed within ~±25% kcal (consumer-grade bar).
- Confirmed meals appear in Apple Health and are not double-counted; weekly targets self-correct against real trend weight; an alcohol evening surfaces as gap, not a carb overshoot.
- All five Trends charts render from real history at acceptable scroll performance; methodology negotiation re-plans.
- Backwards compat: schema-v2 export byte-checks against bioharvest for the same day; copy-to-Gemini works; Share Extension imports.
- Full regression sweep of DT2/DT3 flows plus a final battery check.

### DT5 fix sections (filed 2026-07-24)

Targeted fixes from Cameron's DT5 session.

#### F-DT5.1 - OpenRouter photo 404

- **Depends on:** M9.6
- **Goal:** Photo meal upload works with OpenRouter key.
- **Scope:** OpenRouter model slug fix; prompt-only JSON fallback (drop strict json_schema for Gemma); surface error body in HTTP client; MealVisionRouter auto-fallback to Gemini when both keys present.
- **Acceptance:** CoachLLM fixture tests pass; OpenRouter failure falls back to Gemini when configured.

#### F-DT5.2 - Coach OpenRouter picker confusion

- **Depends on:** M11.2
- **Goal:** Coach settings do not promise OpenRouter chat when only meal vision is wired.
- **Scope:** Remove OpenRouter from coach Provider picker; keep Photo meal vision picker + TestFlight key section; explanatory note.
- **Acceptance:** Selecting coach provider never shows "reserved for later release" for OpenRouter; build clean.

#### F-DT5.3 - Nutrition tab + Trends on Dashboard

- **Depends on:** M9.2, M10.1
- **Goal:** Nutrition is a root tab; trend charts live on Dashboard.
- **Scope:** Add Nutrition tab; remove Trends tab; embed trend section on Dashboard; wire TrendsBootstrap from Dashboard.
- **Acceptance:** Build + previews; Nutrition one tap; Dashboard shows trend charts.

#### F-DT5.4 - Settings polish

- **Depends on:** M0.7, M0.8
- **Goal:** Settings matches canvas; data-sheet skin visible; one notifications entry.
- **Scope:** List plain style + row backgrounds; remove nested helmTheme; merge Shortcuts + Proactive Notifications; skin preview Card; audit skin bypasses.
- **Acceptance:** Settings visually matches Dashboard; layout picker visible on Settings; single notifications guide entry.

#### F-DT5.5 - App icon from design spec

- **Depends on:** M0.1
- **Goal:** Replace black placeholder icon on iPhone + Watch.
- **Scope:** Treatment C icon (arc + data trace) per DESIGN-SYSTEM.md in both asset catalogs.
- **Acceptance:** Icon visible on device after reinstall; not solid black.

#### F-DT5.6 - Nutrition transparency + glyph fix

- **Depends on:** M4.6, M9.2
- **Goal:** Calorie target explainable; info glyph does not overlap day-type tag.
- **Scope:** Move explainable to calorie row; extend nutrition contributors (TDEE, floor, phase); treat zero TDEE as nil; header spacing fix.
- **Acceptance:** Explain sheet shows floor/TDEE contributors; glyph does not overlap tag.

#### F-DT5.7 - Export UI rebrand

- **Depends on:** M11.1
- **Goal:** Settings copy says Helm export; JSON wire format unchanged (bioharvest-compatible).
- **Scope:** SchemaV2ExportView + Settings row labels only.
- **Acceptance:** No "schema v2" in user-facing copy; golden export test unchanged.

#### F-DT5.8 - Diagnostics refresh

- **Depends on:** M0.3
- **Goal:** Diagnostics useful for DT5 regression.
- **Scope:** Stack trace + category filter + buffer count in UI; widen OSLog extract; capture() at PhotoMeal, Prescription, Nutrition silent failures; doc Watch limitation.
- **Acceptance:** Diagnostics tests pass; export includes share subsystem.

#### F-DT5.9 - Train set count + exercise picker

- **Depends on:** M3.3, M5.4
- **Goal:** Manual +/- sets; picker recents and filters.
- **Scope:** addSet/removeSet on ActiveSessionStore; +/- in ExerciseSectionView; listRecentlyUsed + filter chips in ExercisePickerView.
- **Acceptance:** Persistence tests; picker shows recent section.

#### F-DT5.10 - Watch phone-led companion

- **Depends on:** M8.2, M6.1
- **Goal:** Phone Train start opens Watch companion with live HR + exercise/set mirror.
- **Scope:** WatchWorkoutCompanionPayload; TrainSessionController pushes state; Watch defaults to companion; demote standalone workout start; phone HR chip.
- **Acceptance:** Build passes; companion payload round-trip tests.

#### F-DT5.11 - Coach-editable settings (phase A)

- **Depends on:** M4.5, M5.6, M9.1
- **Goal:** Coach adjusts training plan settings via chat.
- **Scope:** settings_adjustment.v1 schema; ChatController applies phase/goal/rate mutations; triggers re-plan.
- **Acceptance:** Fixture decodes adjustment; plan persists after coach turn.

### M12 Design polish and league push

UI-layer and DesignSystem-layer only; no engine, schema, or migration changes. All acceptance is agent-verifiable (build under Swift 6 complete concurrency with zero warnings, SwiftLint clean, previews, unit tests where noted); device *feel* is DT6.

Suggested order: M12.2 (rhythm) first so later sections lay out on a fixed grid, then M12.1 (motion), M12.3 (data-viz), and M12.6 (the `DeviationBand` atom) in parallel, then M12.4 (finish), M12.5 (signature moments), and the transparency views M12.7 to M12.9 (which consume M12.6). The transparency band (M12.6 to M12.9) reprioritises deferred M13.1/M13.2: M12.8 pulls their plan-visibility intent forward.

#### M12.1 Motion and transition pass

- **Track**: A (UI / DesignSystem). **Depends on**: M0.7, and the shipped screens (M2.3, M3.3 to M3.5, M6.3, M9.2, M10.1).
- **Goal**: every screen transition and every engine readout moves per DESIGN-SYSTEM section 6, calmly and consistently.
- **Scope**: add a small set of reusable motion modifiers in DesignSystem (numeric-roll wrapper, skeleton shimmer, staggered-appear, matched-geometry card-to-detail helper); adopt them on Dashboard, Train, Trends, Nutrition; wire `contentTransition(.numericText())` on all engine numbers; pair set-completion/PR/adjustment motion with their existing haptics. No new motion tokens.
- **Acceptance**: grep shows no ad-hoc `.animation(...)` durations outside tokens; every engine readout uses the numeric-roll wrapper; skeleton and staggered-appear have previews; Reduce Motion collapses each to a `quick` cross-fade (unit-tested via the capability abstraction); SwiftLint clean.

#### M12.2 Layout rhythm and density audit

- **Track**: A. **Depends on**: M0.7 and shipped screens.
- **Goal**: one spacing rhythm and one hierarchy discipline across the app; no card-in-card.
- **Scope**: audit and fix Dashboard, Train, Trends, Nutrition, Settings to the spacing scale; de-nest surfaces (hairline rules replace nested cards); enforce one-primary-number-per-card with `StatChip` rows for secondaries; column alignment and unit treatment per DESIGN-SYSTEM section 2 and 5.
- **Acceptance**: grep shows no raw spacing literals outside the scale in the audited views; no nested `Card` within `Card`; previews in both palettes and at the largest Dynamic Type size show no clipping or column jump; SwiftLint clean.

#### M12.3 Data-viz refinement

- **Track**: A. **Depends on**: M12.2, M10.1 (Trends), M2.2/M9.1 (data).
- **Goal**: one chart language, a signature per-muscle-vs-landmark chart, Dashboard sparklines, interactive scrub.
- **Scope**: route every Trends card and any inline chart through `HelmChartStyle` (state-ramp only, mono tabular axes, hairline gridlines); rebuild the per-muscle volume card as horizontal bars with MEV/MRV bands and state coloring; add 7-day sparklines to the readiness and weight Dashboard cards; add drag-to-scrub with a mono callout and a light haptic tick; honest insufficient-data states on every chart.
- **Acceptance**: all charts consume `HelmChartStyle` and design-system primitives only (no arbitrary colors); the per-muscle card renders under, in-range, at, and over-MRV states in previews; sparkline and scrub have previews and a Reduce Motion path; insufficient-data states previewed; SwiftLint clean.

#### M12.4 Finish pass: states, iconography, consistency

- **Track**: A. **Depends on**: M12.2.
- **Goal**: shipped-product finish on the last 15 percent.
- **Scope**: design empty, loading (skeleton), and error states for every screen; iconography audit to one weight/size per context with the arc-trace motif on tab and section marks; surface-discipline audit (radius, hairline, pressed/active states on every tappable surface); `monoTag` eyebrow consistency; a copy pass for terseness and label consistency.
- **Acceptance**: every screen has previewed empty/loading/error states; a documented icon set with consistent weights; grep shows pressed/active states on interactive surfaces; no em dashes in any in-app string; SwiftLint clean.

#### M12.5 Signature moments

- **Track**: A / coach-UI. **Depends on**: M12.1, M2.3 (reveal), M3.5 (PR), M6.4 (onboarding).
- **Goal**: make the reveal, PR, workout finish, and onboarding feel premium and memorable.
- **Scope**: elevate the readiness reveal (state-tint bloom, contributor stagger, haptic swell already present); elevate PR celebration (arc burst, once per PR); build the workout-finish summary moment (volume, sets, TRIMP, animated landmark movement, tomorrow-readiness teaser); author the onboarding sequence (self-drawing Arc, backfill-as-filling-Arc, first reveal as payoff).
- **Acceptance**: each moment has previews across its states; reveal and PR fire once per day / once per PR (unit-tested via the existing gates and detection query); finish summary renders from fixture session data; all four honor Reduce Motion; SwiftLint clean. Feel is DT6.

#### M12.6 DeviationBand component (the reference-band atom)

- **Track**: A (DesignSystem). **Depends on**: M0.7.
- **Goal**: one reusable component that plots a value inside its personal reference range, the atom the transparency theme is built from.
- **Scope**: a `DeviationBand` view in DesignSystem taking a current value, a band (lower/upper, typically `mean ± robustSigma` or a target range), units, a `HelmState` for colour, and an optional verdict tag (`GOOD` / label). Marker inside a hairline band track, mono tabular value, unit one step smaller in `fgMuted`, state colour on the marker and tag. A horizontal `bar` layout (contributor rows) and a compact inline layout. No engine change; the values are supplied by the wiring layer.
- **Acceptance**: previews for in-band, below-band, above-band, and cold-start (no band yet) in both palettes and at the largest Dynamic Type; state never encoded by colour alone (value and tag always present); numeric-roll on value change; SwiftLint clean; zero hard-coded colours.

#### M12.7 Recovery detail view

- **Track**: A / readiness-UI. **Depends on**: M12.6, M2.2/M2.3, M10.1 (history), and benefits from M4.5 (coach) for the narration line.
- **Goal**: one screen that consolidates the scattered recovery pieces and reads the way StrongSplit's recovery screen does, plus the coach's interpretation.
- **Scope**: score against its target band; readiness history with the band overlaid (reuse the Trends history query, restyled through `HelmChartStyle`); each contributor (HRV, resting HR, sleep) as a `DeviationBand` in real units, reconstructed from the stored daily metric plus the persisted `readiness_baseline_state` (`mean`, `robustSigma`); the coach's one-line read at the top, degrading to the engine contributor summary when the coach is offline; an "Ask coach about this" hand-off. Reachable from the Dashboard readiness card.
- **Acceptance**: renders from fixture readiness + baseline data for good/compromised/cold-start states; contributor bands show real units and the personal range; offline path shows engine summary with the coach hand-off disabled; snapshot tests per state; no engine change (pure wiring over existing repositories); SwiftLint clean.

#### M12.8 Progression / plan-model view (absorbs deferred M13.1/M13.2 plan visibility)

- **Track**: plan-UI. **Depends on**: M12.2, PlanKit (M5.x), M3.5 (PR/e1RM queries).
- **Goal**: make the plan model and the user's position in it visible, not just today's prescription.
- **Scope**: surface the current mesocycle position (block, week, MEV to MRV ramp state, scheduled deload) from `PlanKit` mesocycle state; the active progression scheme (rep range, RPE cap, sets-per-session, load increment); and a per-lift level ladder with estimated 1RM and per-step deltas from the logged history. Read-only visibility in v1 (editing stays in Settings/plan config); this is the plan-visibility intent of the deferred M13.1/M13.2 pulled forward. Reachable from the Dashboard prescription card and Train.
- **Acceptance**: renders from fixture mesocycle state and logged history for mid-meso, deload-week, and cold-start; the level ladder marks completed steps from real queries (not stored as truth); no engine or schema change; SwiftLint clean.

#### M12.9 Muscle-volume promotion and recency

- **Track**: A / plan-UI. **Depends on**: M12.2, M10.1, PlanKit weekly hard-set ledger.
- **Goal**: lift the landmark-aware per-muscle volume board out of Trends into a first-class surface, with the recency dimension StrongSplit shows.
- **Scope**: extend `MuscleVolumeGauge` with days-since-trained per muscle (from the ledger/last-session query); a ranked per-muscle board (sets vs MEV/MRV landmark band, state colour, days since trained), promoted onto Train and summarised on the Dashboard; keep the existing `ArcGauge` grid available in Trends. Landmark bands stay; do not regress to raw counts.
- **Acceptance**: board renders under-MEV, in-range, at-MRV, and over-MRV states with recency from fixtures; the Dashboard summary and the Train board share one view model; previews in both palettes; no engine change beyond the additive recency field on the view model; SwiftLint clean.

### DT6 (after M12.5 and M0.8): the polish gate

- Every named haptic still syncs to its motion on a real iPhone; the readiness reveal, PR burst, and workout-finish summary land as premium moments.
- Skeleton-to-content and matched-geometry transitions feel fluid at 120Hz, no dropped frames on device.
- Both skins switch live with no flash or layout break, in dark and light.
- Empty/loading/error states verified on device with real (and absent) data.
- Largest Dynamic Type pass on Dashboard and the set row.
- `DeviationBand` reads correctly against real HealthKit-derived baselines on device (right units, band the right width, verdict matches the engine); the recovery detail view, progression view, and muscle-volume board reconcile with the engine numbers.

### DT7 after M14.9: native food logging (MFP deleted 7 days)

Cameron uninstalls MFP and logs all food in Helm for 7 consecutive days.

- **Repeat breakfast**: saved template logs in ≤2 taps; portion memory defaults to last serving (e.g. 1 pot).
- **Branded snacks**: barcode or type-to-find (Grenade, Arla, PhD) resolves via OFF or cache; manual custom food for misses.
- **Generic produce**: CoFID search offline at work; offline banner when OFF unavailable.
- **Leftovers dinner**: photo path still works; shared `MealLineItemEditor` for manual correction.
- **Alcohol**: explicit beer log; not misread as carb overshoot; gap field sane on mixed days.
- **History**: edit yesterday's meal; delete entry; copy Tuesday breakfast to today.
- **HealthKit**: confirmed meals in Apple Health; no double-count from Helm re-ingest; no double-count during any brief overlap testing.
- **TDEE**: weekly trend responds to logged intake including quick-add kcal.
- **Regression**: DT5 photo scenarios still pass (ingredient breakdown, gram edit recompute, ±25% kcal bar).

#### F-DT7.7 - Photo meal grounding, loading UX, and add-flow toolbars

- **Depends on:** M14.9, F-DT7.5
- **Goal:** Photo scan shows immediate loading feedback; CoFID grounding improves accuracy vs vision-only; add-food sheets use standard toolbar Cancel/Add.
- **Scope:** `PhotoMealEstimatingView` full-screen overlay with cancellable estimate tasks; CoFID plural-token matching and generic-produce fallback; per-line CoFID labels on confirm sheet; hybrid direct-vision comparison when grounding confidence is low; diagnostics audit JSON; Settings photo accuracy picker (`MealVisionPreferencesStore`); Cancel left / Add right on portion, quick-add, alcohol, and photo confirm sheets.
- **Acceptance:** Build passes; `GroundedPhotoMacroEstimatorTests` pass; overlay blocks interaction during estimate; errors clear loading state.

#### F-DT7.9 - Coach-styled meal vision loading overlay

- **Depends on:** F-DT7.7
- **Goal:** Photo analysing overlay reuses the same coach AI design vocabulary as Ask Coach; photo backdrop stays inside screen gutters.
- **Scope:** `CoachAIProgressCard` and `CoachAIPulseIndicator` in DesignSystem; `AskCoachBar` shares the pulse indicator; `PhotoMealEstimatingView` refactored to `CoachAIProgressCard` with `helmScreenPadding`, clipped photo backdrop, and coach eyebrow/surface/hairline treatment.
- **Acceptance:** Build passes; overlay uses shared coach components; card respects horizontal gutters (no bleed past screen edges).

### M13 Schedule and calendar (post-DT5)

#### M13.1 Planned workout UI

- **Depends on:** M5.2, F-DT5.10
- **Status:** Plan-visibility intent absorbed by **M12.8**. Calendar/week-ahead scope remains here if still wanted post-M12.
- **Goal:** Week-ahead schedule visible on Train.
- **Scope:** Generate planned_workout rows when prescription computes; week list on Train. *(Plan model / progression ladder → M12.8.)*
- **Acceptance:** Fixture plan renders week ahead.

#### M13.2 Drift policy UI

- **Depends on:** M13.1
- **Status:** Mesocycle position visibility absorbed by **M12.8**. Drift-on-calendar scope remains here.
- **Goal:** Skipped/moved sessions visible.
- **Scope:** Drift indicators on Train calendar list. *(Block/week/MEV→MRV ramp state → M12.8.)*
- **Acceptance:** Drift scenario tests render in UI.

#### M13.3 EventKit hints (optional)

- **Depends on:** M13.2
- **Goal:** Busy-day hints from calendar read-only.
- **Scope:** EventKit read; no write-back.
- **Acceptance:** Permission flow; busy day surfaces hint.

### DT9 post-DT7 improvement wave (F-DT9.#)

Parallel tracks after DT7. One device gate **DT9** when all sections land. Cost policy: Grok orchestrates stubs only; implementers use standard Composer 2.5 (`composer-2.5`); **never** `composer-2.5-fast`. Shared-file hazard: serialize `TrainView.swift`, Live Activity attributes, GRDB migrations, `CoachSystemPrompt.swift`.

**Locked decisions:** Watch-primary training load + phone energy backup when Watch absent; Hevy bodyweight volume rules (added kg in column, BW+added for full-BW catalog moves); local exercise resolver (no network coach API); Now Playing music capture only (analysis page deferred); no Garmin-specific code.

#### F-DT9.1 Hevy-style set input / numpad

- **Depends on:** none (Track A start)
- **Goal:** Set logging matches Hevy: grey prefilled PREV, black user/completed; tap grey opens numpad with caret; tap black select-all; no Next/Done on kg/reps; RPE slider + Done completes set; keyboard-dismiss chip + swipe-down/tap-outside dismiss.
- **Scope:** `HelmNumpad.swift`, `SetRow`, `TrainSessionController`, `SetRowView`.
- **Acceptance:** Unit tests for draft/prefill/complete colour states; build green.

#### F-DT9.2 Rest-notification cold-start crash

- **Depends on:** none (Track B start)
- **Goal:** Rest-done notification cold start continues workout without crash.
- **Scope:** `HelmNotificationDelegate`, `RestNotificationRouter`, pending session recover, Live Activity restart order; diagnostics breadcrumbs.
- **Acceptance:** Unit/integration around recover path; no force-unwrap on missing session; build green.

#### F-DT9.3 Exercise history tap + session header

- **Depends on:** F-DT9.1 if SetRow files conflict; else parallel
- **Goal:** Tap exercise name opens history sheet (PREV + e1RM); header shows elapsed + completed/total sets.
- **Scope:** `ExerciseSectionView`, history sheet, Train header.
- **Acceptance:** Fixture/snapshot for history model; header counts match session.

#### F-DT9.4 Train bottom layout + remove-exercise fix

- **Depends on:** F-DT9.1 preferred
- **Goal:** Tighter rest/coach spacing; fog higher; shorter rest banner; confirm remove actually deletes exercise.
- **Scope:** `RestTimerBanner`, Train bottom gradient, `TrainViewPresentationLayer` confirmation Binding race fix.
- **Acceptance:** Controller test: confirm remove removes exercise.

#### F-DT9.5 Rest sound + RTL progress (+ Watch haptic hook)

- **Depends on:** F-DT9.2 optional
- **Goal:** Customisable boxing-ring rest sound (default on, respect silent, headphones OK); banner progress empties right-to-left; phone drives Watch rest-end haptic message.
- **Scope:** `TrainPreferences`, sound assets, `RestTimerBanner`, WCSession rest-end message.
- **Acceptance:** Preference persistence tests; banner progress math test.

#### F-DT9.6 Watch companion auto-start + HR honesty + training load energy

- **Depends on:** none (Track B)
- **Goal:** Train start launches Watch + buzz; no Watch toast + hide HR chip; live HR when connected; phone `HKWorkout` includes energy for Apple training load.
- **Scope:** `WatchSessionCoordinator`, `SessionHeartRateChip`, `WorkoutHealthKitWriter`, `HealthKitStoreClient`.
- **Acceptance:** HR hidden when unpaired; writer tests assert non-nil energy.

#### F-DT9.7 Live Activity / Dynamic Island redesign

- **Depends on:** F-DT9.6 for HR field
- **Goal:** Hevy-like LA content, solid contrast, edge padding; Done chip completes set (no ±15); elapsed, exercise, set X/Y, target, rest, HR when live.
- **Scope:** `WorkoutActivityAttributes`, `WorkoutLiveActivityWidget`, `WorkoutLiveActivityManager`.
- **Acceptance:** Widget previews resting/working/dark; Done deep-link completes set safely.

#### F-DT9.8 In-session context, add-exercise, resolver, bounds toggle, BW logging

- **Depends on:** none (Track C start)
- **Goal:** Coach sees all logged set numbers; add catalog exercises via fuzzy resolver (recents bias); presets after add; Settings toggle disables ±10% load safety; Hevy BW volume rules.
- **Scope:** `InSessionCoachService`, `add_exercise` op, exercise resolver, `PrescriptionBounds`, paste/import note parity.
- **Acceptance:** Resolver fixture tests; context includes mass/reps/RPE; bounds toggle tested; BW volume fixtures.

#### F-DT9.9 Coach action confirmation + AI impact UX + food diary

- **Depends on:** F-DT9.8
- **Goal:** Coach mutations (workout_start, food log, adjust) discuss then confirm then apply; impactful AI progress + long haptic; food CRUD + nutrition Q&A from chat.
- **Scope:** Confirm card UI; `food_log.v1` schema; `ManualMealService`; `CoachAIProgressCard` redesign.
- **Acceptance:** Confirm required before persist; fixture decode tests.

#### F-DT9.10 Proactive in-session coaching + injury memory prompt

- **Depends on:** F-DT9.8
- **Goal:** ~25% set milestones refresh context + optional bubble; Settings toggle (default on); pain/injury via free-text memory + prompt guidance only.
- **Scope:** Milestone observer; `MemoryProfile` prompt; Settings toggle.
- **Acceptance:** Milestone fires at most 4 times per session; toggle disables bubbles.

#### F-DT9.11 Rolling 7-day muscle load + meal-card macros

- **Depends on:** none (Track D start)
- **Goal:** Muscle-group set load = rolling last 7 days; meal cards show compact P/C/F.
- **Scope:** `TrendsDataBuilder`, `MuscleVolumeBoardModel`, coach ledger window, `NutritionMealBucketSection`.
- **Acceptance:** Rolling-window unit tests; meal card preview.

#### F-DT9.12 Live-ish energy balance (constraints-aware)

- **Depends on:** none
- **Goal:** Clearer in vs out vs target given HK lag; avoid misleading tiny post-workout burned delta.
- **Scope:** `NutritionDaySummaryCard`, `NutritionEngine` freshness states.
- **Acceptance:** UI states for nil/stale/fresh active energy.

#### F-DT9.13 Workout music Now Playing capture

- **Depends on:** none
- **Goal:** Sample now-playing (title, artist, BPM, genre when available) on-device during session; GRDB storage for later analysis (deferred UI).
- **Scope:** MediaPlayer APIs; append-only migration.
- **Acceptance:** Fixture with stubbed now-playing; migration test.

#### F-DT9.14 Finish HR graph + in-chat charts

- **Depends on:** F-DT9.6 for HR samples
- **Goal:** Finish summary HR chart with set markers when HR available; coach chat renders charts on request.
- **Scope:** `WorkoutFinishSummaryView`; chat chart bubble component.
- **Acceptance:** Empty-state without HR; chart bubble snapshot.

#### F-DT9.15 Nutrition toolbar, diary strip, copy entry, templates entry

- **Depends on:** none (residual DT9 nutrition wave start)
- **Goal:** Nutrition toolbar renders (templates + refresh); week strip shows correct calendar days; meal list hides source labels; copy entry uses date/bucket picker; templates discoverable.
- **Scope:** `NutritionView`, `NutritionDiaryHeader`, `NutritionMealBucketSection`, `NutritionDayMealsStore`, `CopyMealEntrySheet`, `MealRepeatService.copyBucket` target bucket, `HelmDay.calendarDay`.
- **Acceptance:** Build green; `HelmDay.calendarDay` test; toolbar inside `NavigationStack`; copy entry sheet; templates button + MEALS row link.

#### F-DT9.16 Coach food_log persist fix

- **Depends on:** F-DT9.15
- **Goal:** Coach food_log confirm persists to GRDB even when HealthKit write fails; past-day helmDay lands on correct diary day.
- **Scope:** `ManualMealService.persist` local-first fallback, `FoodLogCommandApplier` loggedAt, `ChatController` refresh logged helmDay.
- **Acceptance:** FoodLogCommand tests for HK failure + yesterday breakfast; build green.

#### F-DT9.17 Coach meal query + copy tools

- **Depends on:** F-DT9.16
- **Goal:** Coach looks up past meals on demand via meal_query.v1; copies with meal_copy.v1 confirm; no 14-day context injection.
- **Scope:** `MealHistoryQueryService`, meal_query/meal_copy payloads, ChatController tool loop, confirm card.
- **Acceptance:** Parse + query tests; build green.

#### F-DT9.18 Train input, header, timer, coach chrome

- **Depends on:** none
- **Goal:** First-tap numpad, swipe dismiss, live HR header, rest progress bar, RPE haptic steps, remove top coach chrome, fog shrink, recover race.
- **Acceptance:** Build green; restDone on remaining zero unit test.

#### F-DT9.20 Rest bell + system font

- **Depends on:** none
- **Goal:** Rest bell plays through headphones with Silent on; Settings Font Helm/System.
- **Acceptance:** Build green.

#### F-DT9.21 Coach bulk food_log delete + LocalizedError

- **Depends on:** F-DT9.16
- **Goal:** Coach can delete all meals for a day (or bucket) without opaque "error 3"; mealNotFound/nothingToDelete show readable copy.
- **Scope:** `ManualMealError` LocalizedError; `FoodLogCommandApplier` bulk delete by helmDay (+ optional bucket); coach prompt delete rules; tests.
- **Acceptance:** FoodLogCommand tests for bulk delete + error copy; build green.

#### F-DT9.22 Numpad field-switch + slide dismiss

- **Depends on:** F-DT9.18
- **Goal:** Switching weight/reps fields works without dismissing first; numpad open/dismiss animates.
- **Scope:** Remove full-screen dismiss overlay; `withAnimation` on numpad target; bottom transition.
- **Acceptance:** Build green.

#### F-DT9.23 Empty nav + content session subheader

- **Depends on:** F-DT9.18
- **Goal:** Active session nav title empty; elapsed + sets (+ HR) as left content subheader, not toolbar principal.
- **Scope:** `TrainSessionHeaderView` in session list; clear navigationTitle when active.
- **Acceptance:** Build green.

#### F-DT9.24 Hevy rest chrome + sound picker

- **Depends on:** F-DT9.20
- **Goal:** Hevy-style rest bar (elapsed fill, big countdown, −15/+15/Skip); taller bottom fog; restDone when remaining hits 0; Settings sound ID + volume with preview.
- **Scope:** `RestTimerBanner`, Train bottom chrome/fog, `RestTimerSoundID`/`RestTimerVolumeLevel`, Settings Train sounds, `RestTimerSoundPlayer`.
- **Acceptance:** Build green.

#### F-DT9.25 Live Activity restEndsAt + Signal blue

- **Depends on:** F-DT9.7
- **Goal:** Dynamic Island/rest shows live countdown via `restEndsAt` + `Text(timerInterval:)`; Signal-blue keyline/tint.
- **Scope:** `ContentState.restEndsAt`, manager/side-effects wiring, widget compact/expanded rest + `keylineTint`.
- **Acceptance:** Build green.

#### F-DT9.26 System font coverage

- **Depends on:** F-DT9.20
- **Goal:** Settings System font covers HelmTypography aliases and UIKit numpad keys, not only SwiftUI `.helmType`.
- **Scope:** `HelmTypography` computed fonts; `HelmNumpad` UIFont respects `HelmFontPreferences`.
- **Acceptance:** Build green.

#### F-DT9.27 LA outline, boxing bell, system font follow-through

- **Depends on:** F-DT9.24, F-DT9.25, F-DT9.26
- **Goal:** Lock-screen Live Activity has no blue stroke (Island tint stays); boxing bell plays Signal RestBell caf (not chime fallback); System font applies to Train/history/dashboard via environment-driven `helmFont`/`helmType`.
- **Scope:** Widget lock-screen overlay removal; `rest_bell.caf` path + Signal asset; `HelmType.resolvedFont`, buttons/charts/numpad; Train `HelmTypography` → `helmFont`.
- **Acceptance:** Build green; bell URL resolves in unit-checkable helper or log-free play path.

### DT9 device gate (after all F-DT9.#)

Cameron runs once on device: Hevy numpad feel, rest sound/headphones, Watch start buzz + HR hide/toast, LA contrast/Done, cold-start rest notif, coach add-exercise + confirm food/start, rolling 7d volume, meal macros, finish HR graph, delete-exercise, Fitness training load smoke.

---

## Reference and lessons from the lab (informing the clean build, not imported)
- **ARC algorithm** (`BodyBattery/docs/ARC-ALGORITHM.md`, v0.1 design): the readiness spec to re-implement. EWMA + MAD z-scores, transparent weights, logistic squash centring ~58, honest cold-start, SDNN (no RMSSD in HealthKit), ~29% MAPE acknowledged, within-person deltas only.
- **Logger data model** (`loggy/Docs/04_DATABASE_SCHEMA.sql`): proven normalised schema (sessions, blocks/supersets, sets with RPE/RIR, rest-timer state + events, templates, PRs including `best_estimated_1rm` as a metric, an `exercise_history_snapshot` cache, canonical-exercise + alias, a `coach_recommendation` table). e1RM is a PR metric + snapshot column, not its own table. Re-derive cleanly.
- **Provider abstraction and budgets** (`coach/ARCHITECTURE.md`): the clean multi-LLM pattern, per-provider budgets (Gemini 48k, FM 4k), chars/3.5 estimating, oldest-day-first trimming, lazy cached markdown, battery-aware lifecycle, Keychain + Debug bootstrap. Gemini gotcha: key as URL query param, never log URLs; free-tier models only. No context-caching lesson exists there; use implicit caching via prefix ordering.
- **Harvest** (bioharvest): schema-v2 contract, 18:00 to 18:00 sleep window with overlap bucketing, explicit-null semantics (keys always present), the App Intent pattern. Gap to fix: it does not handle the locked-phone HealthKit problem; the new intent must.
- **Lessons (corrected)**: drop on-device RAG/embeddings for complexity and battery, not jetsam (Signal's blank-screen bug was `HKLiveWorkoutBuilder` Error(7) + a UIKit keyboard teardown, and jetsam was explicitly disproven). Gate heavy work on foreground stability with stop conditions; release large models on dismissal; cancel generation on tab-disappear; no 1 Hz timer-driven fetches during live workouts; custom numpad to avoid the keyboard teardown; timers as projections; bounded/chunked imports off the launch path; keep the "coaching, not diagnosis" boundary.
- **Coacher** (`Coacher/coach-key-service`): a Cloudflare Worker that mints $0-cap, free-model-allowlist OpenRouter keys per device via KV, with `MAX_DEVICES`. This already is the M11.2 minting service; reuse it rather than standing up an Oracle equivalent.
- **Visual design** (`Docs/DESIGN-SYSTEM.md`, `Docs/HAPTICS.md`, `Docs/DESIGN-REPORT.md`): instrument-not-app thesis; Arc as signature element; monospaced numeric voice; `HelmTheme`/`HelmSkin` seam; twelve-pattern haptic vocabulary. M3.3-M3.5 shipped before this system; catch up via F-DESIGN-M3.

## Kick-off decisions (resolved)
- **App name: Helm.** Kept as the real name, not a placeholder.
- **Backfill window: 6 months.** Enough for EWMA baselines to stabilise and e1RM landmarks to establish, without a slow first-launch parse.
- **Location: `Development/Helm/` at root**, with root-level SPEC.md + PLAN.md (matching coach), not under `projects/`. Formalise SPEC.md + PLAN.md before M0.
- **Visual system:** `Docs/DESIGN-SYSTEM.md` + `Docs/HAPTICS.md` are normative from M0.7 onward. One layout skin (`instrument`) + full palette switch in v1; second layout skin reserved (M0.8, deferred). `ArcGauge` + `HapticEngine` stay in DesignSystem package.
- **Still open**: whether OpenRouter/Compare stays behind Advanced for model testing (default: yes, behind Advanced).

## Mapping from the previous milestone numbering
Old M0 → M0.1 to M0.6. Old M1a → M1.1/M1.2. Old M1b → M1.3/M1.4. Old M2 → M2.1/M2.2. Old M2.5 → M3.1 to M3.6. Old M3a → M4.1/M4.2. Old M3b → M4.3/M4.4. Old M3c → M4.5. Old M4a → M5.1/M5.2. Old M4b → M5.3. Old M4c → M5.4/M5.5 (+ M5.6 new). Old M5 → M6.1 to M6.3 (+ M6.4 new). Old M6 → M7.1/M7.2. Old M7 → M8.1/M8.2. Old M8 → M9.1 to M9.3. Old M9 → M10.1/M10.2. Old M10 → M11.2. New with no old counterpart: M11.1 (backwards-compat export, previously a locked decision with no milestone), M6.4 (onboarding assembly), M5.6 and the Dashboard cards (Dashboard previously had no milestone).

**Design fold-in (2026-07-22):** M0.7 (DesignSystem v2), M0.8 (optional second layout skin, deferred), M2.3 (readiness re-skin, append-only to M2.2), M4.6 (explain sheet), F-DESIGN-M3 (logger haptics/UI catch-up for M3.3-M3.5 shipped pre-M0.7). Normative: `Docs/DESIGN-SYSTEM.md`, `Docs/HAPTICS.md`.
