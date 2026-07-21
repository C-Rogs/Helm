# Helm build progress

Shared status board for every build agent. See "Progress tracking" in [PLAN.md](PLAN.md) for the rules: read your dependencies' rows before starting, append your own row when done, never edit another section's row.

Status values: `not started`, `in progress (agent: <name/session>)`, `done`, `blocked (<reason>)`.

## Sections

| Section | Status | Date | Commit | Notes / deviations |
|---|---|---|---|---|
| M0.1 Repo, XcodeGen, app shell | done | 2026-07-21 | dec8301 | Seven local packages declared in project.yml but not linked to Helm target yet; HelmWatch stub embedded for M0.5. |
| M0.2 Core package | not started | | | |
| M0.3 Diagnostics package + screen | not started | | | |
| M0.4 DesignSystem | not started | | | |
| M0.5 Watch walking skeleton | not started | | | |
| M0.6 Debug key bootstrap + battery method doc | not started | | | |
| M1.1 Persistence: health schema + repositories | not started | | | |
| M1.2 DB export + data safety | not started | | | |
| M1.3 HealthKitIngest actor (live reads) | not started | | | |
| M1.4 Bounded backfill + debug data browser | not started | | | |
| M2.1 ReadinessKit engine (pure) | not started | | | |
| M2.2 Readiness wiring + Dashboard card | not started | | | |
| M3.1 Logger persistence | not started | | | |
| M3.2 Active session engine | not started | | | |
| M3.3 Train screen + custom numpad | not started | | | |
| M3.4 Rest-timer alerts, Live Activity, HealthKit write | not started | | | |
| M3.5 History, templates, PRs | not started | | | |
| M3.6 Paste-a-workout parser | not started | | | |
| M4.1 Provider protocol + registry | not started | | | |
| M4.2 GeminiProvider + keys | not started | | | |
| M4.3 MemoryProfile | not started | | | |
| M4.4 Context builder (pure) | not started | | | |
| M4.5 Chat UI + chat persistence | not started | | | |
| M5.1 PlanKit mesocycle core (pure) | not started | | | |
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
| DT1 (after M2.2): foundation + ingest + readiness | not started | | |
| DT2 (after M3.6): the logger, in the gym | not started | | |
| DT3 (after M6.4): the loop replaces Gemini (go-live gate) | not started | | |
| DT4 (after M8.2): proactivity + Watch | not started | | |
| DT5 (after M11.1): nutrition, analytics, full regression | not started | | |
