# Signal architecture map (for Deep Research)

Paste this into Gemini Deep Research as product context. Map every recommended technique to a **seam** below. Do not invent a parallel brain that bypasses engines.

**Names:** User-facing app = **Signal**. Repo / packages / internal types = **Helm**. Same product.

**Goal of this research:** Meta-level N-of-1 pattern detection: discover personal associations across multi-year multi-signal history (recovery, sleep, nutrition, training, context tags) without dumping raw history into a large LLM. Techniques must fit phone-first, battery-aware, deterministic-engine-owns-numbers design.

---

## System shape (today)

```
HealthKit / manual logs / EventKit / Watch HR
        │
        ▼
HealthKitIngest ──► GRDB (helm.sqlite)  ◄── Persistence repos
        │
        ├── ReadinessKit (ARC score + bands)
        ├── PlanKit (prescription, readiness gating, progression)
        ├── NutritionKit (adaptive TDEE, weekly budget, day demand)
        └── (MISSING) PatternKit ← research target
        │
        ▼
CoachLLM (Gemini narrates; tools query engines; clamps writes)
        │
        ▼
UI: Dashboard / Train / Nutrition / Chat / Trends / Settings
```

**Hard rule:** Engines compute numbers. LLM narrates and may propose. Engines clamp. Pattern detection must follow the same rule.

---

## Package seams (where findings plug in)

| Package | Role | Pattern relevance |
|---|---|---|
| **Core** | Shared models (`HelmDay`, `DailyMetrics`, sleep, meals, workouts) | Define typed day fields / hypothesis AST types here or in Domain |
| **Domain / ReadinessKit** | ARC multi-factor readiness (HRV, RHR, sleep, strain, …); bands depleted/balanced/primed | Outcome or exposure; already z-scores vs personal baselines |
| **Domain / PlanKit** | Session prescription, MEV→MRV, readiness ordered trim, e1RM progression | Gym outcomes; **do not** auto-mutate from patterns in v1 (confirm like reactive deload) |
| **Domain / NutritionKit** | Adaptive TDEE, macros, day demand tags (ordinary/office/training/social/party/…) | Nutrition outcomes; alcohol is first-class meal source |
| **Domain / PatternKit** (proposed) | Hypothesis grammar, generators, ContrastEngine, PatternFinding store | **Primary home for research techniques** |
| **Persistence** | GRDB repos, migrations | Persist findings; build day matrix from existing tables |
| **HealthKitIngest** | Ingest, day aggregation, briefs, coach context assembly | Trigger recompute on ingest / day rollover; feed day matrix |
| **CoachLLM** | Gemini (FM / OpenRouter reserved); tool protocol; memory profile | `pattern_query` tool; propose-then-test JSON; narrate findings only |
| **ExportKit** | Schema v2 export (legacy Gemini paste) | Offline research / eval; not runtime pattern brain |

---

## Data already available (feature space)

Logical day key: `HelmDay` (user cutoff, default 04:00). Sleep uses a separate wake-day convention in places (18:00 window in harvest/docs) - lag rules must be explicit.

| Family | Signals | Notes |
|---|---|---|
| Recovery | HRV SDNN, RHR, respiratory, wrist temp, ARC score/band, prior-day TRIMP | Strong coverage historically |
| Sleep | Asleep, REM/deep/core, WASO, efficiency | Stage samples in GRDB |
| Nutrition | kcal, protein/carbs/fat, meal buckets (breakfast…), alcohol meal source | Alcohol / breakfast tagging density still thin |
| Body | Mass, body fat % | Weight often sparse |
| Training | Sets (load, reps, RPE), sessions, e1RM, Hevy import, live HR → TRIMP | Performance outcomes |
| Context | Nutrition day demand (office etc.), calendar busy hints | Office is **manual tag**, not GPS |
| Memory | Free-text nutritionPatterns / trainingResponses | Not measured; optional confirm target for findings |

**Meta rule:** New life signal = new typed column on the day matrix. Not a new insight subsystem.

---

## What exists today that is NOT PatternKit

| Mechanism | What it does | Gap vs meta patterns |
|---|---|---|
| `ThresholdInsight` | Day-over-day z-score crossing on readiness contributors | Univariate, not cross-factor |
| `trends_query` | Single-series history (TRIMP, weight, e1RM, readiness, …) | No exposure→outcome grammar |
| Coach 14-day context | Structured rollup for narration | LLM may invent associations |
| Memory profile prose | Human/LLM text patterns | Not statistically gated |

`PLAN.md` already defers a “what precedes your bad days” correlation view. PatternKit is that view, generalized.

---

## Target meta architecture (product intent)

Not a list of alcohol/office insights. A reusable pipeline:

1. **Typed DayFeatureRow** (binary / continuous / categorical / residual).
2. **Hypothesis grammar:** `exposure(field, op) × outcome(field) × lag × optional match`.
3. **Generators** (all into one judge):
   - sparse seed priors (+ literature priors for cold start)
   - LLM propose-then-test (constrained JSON only; summaries not raw dumps)
   - budgeted typed search (never open pairwise fishing)
4. **ContrastEngine (one judge):** effect size, min N, label shuffle, FDR, tautology suppress.
5. **PatternFinding lifecycle:** emerging → stable → retired → optional user confirm into memory.
6. **Surfaces:** coach tool + findings-first context cards + optional morning brief line + inspectable Trends/Settings list.

Association language only (“tends to…”). No causal “because” until a later module earns it.

---

## Constraints Deep Research must respect

| Constraint | Implication for techniques |
|---|---|
| iPhone-first, battery-aware | Prefer classical / Bayesian N-of-1 on device; heavy TSFMs / on-device 4B+ discovery are offline-only or deferred |
| RAG over raw harvest retired | Retrieve **finding cards**, not full day dumps |
| Coach token budgets | Gemini ~48k / Apple FM ~4k class; tool-thin agent preferred |
| Engine ownership | Pattern numbers from PatternKit; LLM never invents correlations |
| Autocorrelated N-of-1 series | Methods must handle carryover, time trends, multiple testing |
| Small effects take months | Prefer anytime-valid / sequential evidence for weak effects |
| Logging density uneven | Cold-start priors matter; report min-N requirements |
| Privacy | On-device store; no analytics SDK |

---

## How to map research findings (required output shape)

For each technique you recommend, fill:

| Field | Content |
|---|---|
| Technique name | … |
| Problem it solves | generator / judge / cold-start / similar-days / residual outcomes / … |
| Signal seam | PatternKit / CoachLLM / ReadinessKit / Persistence / offline eval only |
| On-device fit | ship / soft / defer |
| False-discovery handling | how it avoids pretty lies |
| Min data needs | rough N or coverage |
| Replaces or complements | e.g. complements propose-then-test; kills open pairwise |
| Non-goal | what Signal should not do with this paper |

Prefer techniques that strengthen: **hypothesis grammar, budgeted search, propose-then-test, sequential Bayes, stratified baselines, residual outcomes given prescription, findings-first retrieval.**

Deprioritize / kill for runtime: full causal DAG discovery as v1 coach truth; end-to-end fine-tuned personal LLM on raw logs; reintroducing full-history RAG.

---

## Success for Signal

Old Signal felt smart by stuffing everything into a huge model. New Signal should feel smarter by:

**compute findings locally → retrieve a few cards → coach narrates / proposes next tests.**

Deep Research should return a shortlist of methods that make that loop scientifically sound and implementable on a single athlete’s phone.
