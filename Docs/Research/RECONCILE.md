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

| Phase | Scope |
|---|---|
| **v1.1 (this ship)** | MPSC for PPL; duration budget setting; program template enum (PPL live; UL/FB stub); prescription uses slots; acceptance tests for Pull density |
| **v1.2** | Fractional hard-set matrix + synergist cap; progression-by-lift; V_base seeding |
| **v1.3** | Readiness precedence table; drift matrix; deload ≥ MEV floor + confirm UX |
| **v2** | EmphasisProfile UI; UL/FB slot tables; methodology→knob map; Thread 4 nutrition depth |

## ARC band map (from research floats)

| Research-ish signal | Helm `ReadinessBand` |
|---|---|
| Very low / “ARC &lt; 0.40” thin-session exception | `.depleted` |
| Normal training | `.balanced` |
| High / green-light | `.primed` |

## Acceptance (v1.1)

- Pull + 60 min + non-depleted + non-deload → ≥4 exercises; includes vertical + horizontal + elbow-flexion slots when catalog allows.
- Pull + 45 min + same → ≥3 exercises with ≥2 pull patterns.
- Equipment filter still respected.
- Changing duration re-plans incomplete days; does not rewrite completed history.
- Program template setting persists; non-PPL templates fall back to PPL slots until their tables ship.

## Sources

- `Docs/Research/0.rtf` … `3.rtf` (raw)
- `Docs/Research/extracted/*.txt`
- `Docs/drafts/session-composer-research.md` (Prompt 0 digest)
