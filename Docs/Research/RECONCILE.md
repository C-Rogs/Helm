# Research reconcile - training engine spine

> Locked product decisions from Gemini Deep Research (`0`–`3` in `Docs/Research/`) plus owner choices (2026-08-05).
> Implementation follows this file over raw research when they conflict.

## Goal

Replace 1-exercise-per-muscle prescriptions with a **Movement Pattern Session Composer (MPSC)** so sessions match PT-realistic density while PlanKit still owns weekly MEV→MRV maths.

## Locked defaults

| Topic | Decision |
|---|---|
| Default template | **PPL** (Upper/Lower + Full Body reserved in settings enum; slot tables later) |
| Default duration | **60 minutes** |
| Normal Pull @ ≥45 min | **≥3 pattern slots**, **≥3 exercises**; @ 60 min **≥4 exercises** including vertical pull, horizontal pull, elbow flexion |
| 2-exercise session | **Defect** unless 30 min **or** deload **or** readiness **depleted** **or** constraints wipe ≥50% slots |
| Max hard sets / exercise (composer) | **4** |
| Synergy ledger (v1.2) | **1.0 / 0.5 / 0.25** with **50%** weekly synergist cap |
| Mid-block experience / V_base | Structural rules immediate; landmark reseed **next block**; optional non-destructive remaining-target rescale (v1.2) |
| Same-day readiness | **Automatic** ordered trim (cap RPE → trim isolation → trim compound @ MEV floor → technique → rest suggest) |
| Full-week reactive deload | **Propose + user confirm** |
| ARC mapping | Use Helm bands: `depleted` / `balanced` / `primed` (no parallel float thresholds in engine) |
| Emphasis | Structured tags later; free text stays coach/memory until EmphasisProfile ships |
| Methodology essays | **Never** mutate engine; typed settings only |
| Coach | Narrate + clamped proposals; engine source of truth |

## Build phases

| Phase | Scope | Status |
|---|---|---|
| **v1.1** | MPSC for PPL; duration budget; program template enum | done (`74c2e25`) |
| **v1.2** | Set allocation floors; fractional synergist ledger; progression-by-lift; V_base | done (`206c6fb`, follow-up `0f3e198`) |
| **v1.3** | Readiness precedence; drift harden; deload ≥ MEV; reactive deload confirm | done (`8c48696`) |
| **v2** | EmphasisProfile UI; UL/FB slot tables; methodology→knob map; Thread 4 nutrition | pending |

## Acceptance (v1.1)

- Pull + 60 min + non-depleted + non-deload → ≥4 exercises; includes vertical + horizontal + elbow-flexion slots when catalog allows.
- Pull + 45 min + same → ≥3 exercises with ≥2 pull patterns.
- Equipment filter still respected.
- Changing duration re-plans incomplete days; does not rewrite completed history.
- Program template setting persists; non-PPL templates fall back to PPL slots until their tables ship.

## Acceptance (v1.2–v1.3)

- Normal session: filled slots use role floors (primary ≥3, secondary/isolation ≥2); drop optional slots before emitting 1-set rows.
- Synergist volume caps at 50% of weekly muscle target.
- Depleted readiness: ordered trim via SessionAutoregulator (not global volume wipe).
- Deload weekly target ≥ MEV.
- Reactive full-week deload requires user confirm.

- Weekly ledger `totals` remain raw direct+synergist; synergist cap applies when computing prescription remaining.
- `ScheduledVolumeForecast` stays a Trends heuristic (per-muscle ceil split), not a full MPSC replay.

## Literature review (2026-08-06) - deliberate departures from the raw threads

External meta-analyses were checked against the constants in threads `2` and `3`. Where the
published evidence and the raw threads disagree, the engine follows the evidence and this
table records why. Constants live in `PlanKit/HardSetPolicy.swift`.

| Thread said | Evidence says | Engine does |
|---|---|---|
| Hard set requires RIR ≤ 4, else zero credit | Robinson et al. 2024 (*Sports Med*): hypertrophy rises continuously as RIR falls, a negative linear slope with no threshold. Refalo et al. 2023: no advantage for failure over non-failure | Graded `proximityCredit`: full credit to RIR 2, tapering 0.9 / 0.8 / 0.5, zero from RIR 6 (the thread's own warmup row) |
| Hard set requires 5-30 reps, else zero credit | Volume dose-response holds across loads; heavy and very light work still grow muscle, just less per set | 0.5 credit outside the band rather than 0 |
| Load band 30-85% 1RM, outside is not a hard set | No evidence for an upper bound. The 85% figure in the thread is descriptive of typical hypertrophy work, not a cutoff | Floor only at 30%. The rep band already discounts near-maximal work |
| Indirect sets count 0.5 | Pelland et al. 2025 (*Sports Med*): of `total` / `fractional` / `direct` counting, **fractional (0.5)** best predicted both hypertrophy and strength across 67 studies | Unchanged, now with direct citation |
| Per-muscle session cap: hard knee at 10 sets, then 0.5 decay | Remmert et al. 2025: point of undetectable outcome superiority ≈ **11 fractional sets per session**, with returns diminishing progressively below it and a markedly flatter slope above | `SessionSaturation` piecewise curve (free to 6, taper over 8, floor 0.25). Applied to the session total so it is order-independent and cannot be dodged by splitting across two exercises |
| Weekly hard cap ~20 sets | Pelland et al. 2025: slope stays positive with 100% posterior probability; diminishing returns, not a wall | No hard stimulus cap. The ceiling is **fatigue** against MRV, which is what MRV always meant |
| ACWR zones gate prescriptions | Impellizzeri et al. 2020, 2021: mathematically coupled, fails to normalise, "neither ACWR nor AL contain useful information for predicting injury". Explicit call to dismiss it | Ratio still computed and displayed. Its ability to downgrade a shift into a **skip** is behind a flag, default off. Deleting real training on a spurious signal is a real cost for no benefit |
| Readiness drives volume | Two RCTs on HRV-guided resistance training (young men 2019, older women 2024) found no benefit over fixed scheduling | Kept, but ordered trim stays cheapest-first (cap RPE before cutting sets) and bands get hysteresis so they stop oscillating |
| Rest-pause / drop sets are fractional | Coleman et al. 2022, Sødal et al. 2023, and the 2026 drop-set meta all find parity with straight sets at equated volume; advanced systems pool to g=0.05 for hypertrophy | 0.5 fractional credit retained. Rest-pause mini-sets aggregate to a single 0.5 no matter how many are logged |

Two structural consequences:

- **Stimulus and fatigue are separate ledgers.** MEV and the weekly target read stimulus;
  MRV reads fatigue. A heavy single now correctly costs more recovery than it returns in
  growth, which a single conflated "set count" cannot express.
- **Reference 1RM is never self-referential.** Load is graded against a rolling best from
  strictly earlier sessions, decayed after 14 days (`exp(-0.005/day)`), and Epley is capped
  at 12 reps. Grading a set against a reference that includes itself made every PR read as
  exactly 100% of 1RM.

## Sources

- `Docs/Research/0.rtf` … `3.rtf` (raw)
- `Docs/Research/extracted/*.txt`
- `Docs/drafts/session-composer-research.md` (Prompt 0 digest)
- Pelland et al. (2025) *The Resistance Training Dose Response*, Sports Medicine
- Remmert et al. (2025) *Is There Too Much of a Good Thing?*, SportRxiv 537
- Robinson et al. (2024) *Proximity to Failure Dose-Response*, Sports Medicine
- Refalo et al. (2023) *Influence of Proximity-to-Failure on Hypertrophy*, Sports Medicine
- Impellizzeri et al. (2020, 2021) ACWR critiques, Sports Medicine / JAT
