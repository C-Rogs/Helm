# Programming Specification for Helm’s Adaptive Training Engine

> Source: Gemini Deep Research (2026-08-04). Saved from research chat for product decisions.
> Status: raw research - not yet an accepted PLAN section. Decisions below may diverge from this text.

---

## 1. Executive Summary

The fundamental architectural flaw in Helm’s legacy training engine stems from an oversimplified volume allocation model within the PrescriptionEngine. While weekly hard-set calculations managed by PlanKit accurately compute volume landmarks such as Minimum Effective Volume (MEV) and Maximum Recoverable Volume (MRV), collapsing a muscle group’s total weekly volume into a single selected exercise per session creates severely compromised training programs.

For example, when a Pull session prescribes eight weekly sets of back work and six weekly sets of bicep work across two weekly exposures, the legacy engine assigns four sets to a single back exercise (e.g., Lat Pulldown) and three sets to a single bicep movement (e.g., Standing Barbell Curl).

This approach breaks down in real-world personal training environments due to four major physiological and biomechanical factors:

1. **Intra-Session Stimulus Decay** - Concentrating four to six consecutive hard sets onto a single movement vector produces acute localized fatigue that dramatically degrades the stimulus-to-fatigue ratio (SFR) of subsequent sets.
2. **Anatomical and Sub-Division Neglect** - Complex skeletal muscle structures (latissimus dorsi, trapezius, deltoids) require varied movement vectors (vertical pulling, horizontal rowing, isolation) for comprehensive development.
3. **Connective Tissue Micro-Trauma** - Repeatedly loading a single joint angle under high volume increases cumulative mechanical stress versus distributing volume across complementary patterns.
4. **Session Density and Time Constraints** - Single-exercise set dumping fails professional PT session standards.

**Recommendation:** Transition from a Muscle-First Set Allocator to a dual-layer **Movement Pattern Session Composer (MPSC)** coupled with a **Dynamic Volume Allocation & Autoregulation System (DVAAS)**. Weekly hard-set targets from PlanKit map across mandatory movement pattern slots structured by session duration budgets, equipment constraints, and selection preferences.

| Architectural Dimension | Legacy Implementation | Recommended Architecture (v2.0) |
|---|---|---|
| Session Generation Model | Single exercise per target muscle | Multi-slot Movement Pattern Session Composer (MPSC) |
| Volume Allocation Logic | Weekly sets ÷ remaining sessions | Pattern-based priority allocation constrained by time budgets |
| Experience Seeding Prior | Static scalars (0.85× / 1.0× / 1.1×) | Individualized Historical Baseline (V_base) bounded by empirical priors |
| Synergist Set Accounting | Ignored or unconstrained | Explicit dual-tier (1.0 direct / 0.5 synergist) |
| Autoregulation Hierarchy | Undefined drop sequence | Rigid 5-tier precedence (RIR → Load → Accessory → Pattern Slot → MV) |
| LLM Engine Boundary | Unclamped text proposals | Deterministic state machine with clamped structured JSON |

## 2. Settings Taxonomy & Information Architecture

| Setting Domain | Data Type | Deterministic Engine Ownership | Re-Plan Scope | UI |
|---|---|---|---|---|
| Program Parameters | Enumerated structs | SessionSplitPlanner, MPSC | Full mesocycle re-compile | Top-level program settings |
| Methodology Preferences | Scalars & enums | PrescriptionEngine, PlanKit | Re-slot microcycle exercises/targets | Preference selectors |
| Operational Constraints | Bitmasks & lists | PrescriptionEngine | Runtime candidate filtering | Body map & equipment checklist |
| User Experience Prior | Floating baseline (V_base) | PlanKit | Seeds new-block set budgets | Onboarding assessment |
| Educational Library | Immutable content | None (LLM context only) | Zero engine effect | Knowledge tab & citations |

### Program Parameters
Primary split (PPL, Upper_Lower, Full_Body), microcycle frequency (3–6 days), target session duration (30 / 45 / 60 / 75+ min). Changes force full mesocycle re-compile.

### Methodology Preferences
Selection bias (Stretch_Focused, SFR_Optimized, Compound_Heavy), proximity-to-failure policy, progression scheme, volume aggressiveness (0.8×–1.2×).

### Operational Constraints
Equipment bitmask; joint/pain constraints (functional flags, not diagnoses).

### User Experience Prior
Replace static experience scalars with V_base from reported weekly hard sets (prior 8 weeks), clamped.

### Educational Library
Read-only physiology docs for coach citations; no direct engine mutation.

## 3. Session Composer Specification

### Pattern slots by split

**Push:** Horizontal Press, Overhead Press; Lengthened Fly/Dip; Triceps (lateral/medial + long head), Lateral Delt  
**Pull:** Vertical Pull, Horizontal Row; Straight-Arm / Lat Isolation; Supinated Biceps, Neutral/Pronated Biceps, Rear Delt  
**Legs:** Knee Extension Compound, Hip Extension Hinge; Unilateral Knee Extension; Knee Flexion, Calf, Abs/Adductor  
**Upper / Lower / Full Body:** as specified in research tables

### Duration budget matrix

| Duration | Max Slots | Total Sets | Max Sets/Slot | Pattern mix |
|---|---|---|---|---|
| 30 min | 2–3 | 6–9 | 3 | 1 primary, 1 secondary, 1 isolation optional |
| 45 min | 3–4 | 10–14 | 4 | 2 primary, 1 secondary, 1 isolation |
| 60 min | 4–5 | 14–18 | 4 | 2 primary, 1 secondary, 2 isolations |
| 75+ min | 5–7 | 18–24 | 4 | 2 primary, 2 secondary, 3 isolations |

### Two-exercise session = Defect unless
- Time budget = 30 min, or
- Readiness depressed (report uses ARC &lt; 0.40 -  **map to Helm ARC bands**), or
- Deload phase, or
- Acute joint constraint excludes ≥50% candidate patterns

### Synergy accounting
- Direct 1.0 to primary movers
- Synergist 0.5
- Stabilizer 0.0 for hypertrophy (fatigue log only)

### DeterministicSessionComposer algorithm
See research §3 algorithm (pattern slots → filter constraints → daily muscle targets → rank/select → allocate sets → deduct direct + synergy credits).

## 4. Volume & Experience Model

Critique of linear experience scalars; prefer:

```
V_start = Clamp(V_reported_historical_average, 8, 15)
```

Mid-program experience/V_base changes apply **only at next mesocycle block**, not mid-block.

Refinement matrix: soreness (1–4) × performance (1–4) → ΔV and deload triggers.  
Special populations: masters (≥45), layoff returnees, chronic low ARC.  
MRV soft (0.90×) / hard (1.00×); overreaching alarm.

## 5. Autoregulation & Deload Policy

Tiered ARC response: raise RIR → cut load → trim isolations → drop pattern slot → truncate to MV.  
MEV floor protection if &lt; MEV for 2 consecutive weeks.  
Scheduled + reactive deloads (with user confirmation recommended for reactive).

## 6. Constraints & Safety

Pain → prohibited patterns + substitutions. Non-diagnostic language. Care referral thresholds. Rehab slots excluded from MRV. Asymmetry: coach proposal preferred over auto 1.5×.

## 7. LLM Coach Contract

Engine owns maths; coach narrates and proposes clamped JSON. Emphasis → structured ProposalPayload → PlanKit validate → user confirm.

## 8. Migration Path

1. **v1.1** -  Session composer (MPSC) into PrescriptionEngine  
2. **v1.2** -  V_base volume seeding  
3. **v2.0** -  Full constraints, science extensions, hardened LLM boundary  

## 9. Evidence Appendix

Volume dose-response (Grade A); individualized baseline (Grade B); lengthened ROM (Grade B); energy availability (Grade A consensus). Cut phase: lower MRV 15–25%.

## 10. Open Decisions (research defaults)

1. Synergy credit 0.5 -  **recommend A**  
2. Rigid duration cutoff -  **recommend A**  
3. Reactive deload needs user confirm -  **recommend B**  
4. Asymmetry via coach proposal -  **recommend B**

## 11. Acceptance Tests

AC-101 through AC-106 and property tests as in research (pattern diversity floor, pull ≥3 @ ≥45 min, MEV floor, MRV hard cap, equipment invariance, deterministic re-plan).
