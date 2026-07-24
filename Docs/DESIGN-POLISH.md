# Helm design polish and league push

> Advisory requirements doc plus drop-in plan, in the same stance as `Docs/DESIGN-REPORT.md`: it assesses, then proposes plan-format sections the architect can paste into `PLAN.md` with matching `PROGRESS.md` rows. It does not edit the plan itself.
>
> Normative companions unchanged: `Docs/DESIGN-SYSTEM.md` (tokens, Arc, type, motion, components) and `Docs/HAPTICS.md`. This doc adds no new tokens or identity; it raises rendered execution to a shipped-product bar.
>
> Standing rules carry: OLED-black base, one accent, state ramp reserved for state, no em dashes in copy, zero hard-coded colors outside the token file, Reduce Motion and haptics-off honored, engine layer untouched.

---

## 1. Why this exists

A competitor, StrongSplit (shipping, App Store, £3.99/mo, recovery + strength + nutrition in one app), reads as visually sleeker than Helm today. That is not a concept gap. Helm's design system is more differentiated than StrongSplit's generic dark theme: the Arc, the grotesk-plus-mono voice, the state ramp, the haptic language. The gap is **execution and finish**. Every Helm screen was built by a separate agent pass against the spec, so rendered spacing, motion, chart styling, and state coverage drift even where the tokens are correct. StrongSplit wins on the last 15 percent: fluid motion, consistent density, refined data-viz, and finished empty/loading states.

Direction confirmed with Cameron:
- **Diagnosis**: all four axes pull the eye. Motion and transitions, density and spacing, charts and data-viz, overall finish.
- **Identity**: keep and refine the instrument thesis. Additionally activate a second `HelmSkin` layout (the reserved `M0.8`) so a sleeker, denser look is switchable.
- **Ambition**: polish pass on shipped screens plus investment in a few signature moments.

The objective is a build agent can look at any Helm screen and it reads as *one disciplined product*, not a series of prompts, and the standout moments feel premium.

---

## 2. The sleek bar (measurable, so agents know when done)

A screen or component is "in the league" when all hold:

1. **No magic numbers.** Every space, radius, and duration is a `Docs/DESIGN-SYSTEM.md` token (spacing 4/8/12/16/22/32, gutter 22, card gap 12, radius 16 to 20, motion `quick`/`standard`/`settle`/`reveal`). SwiftLint-adjacent grep audit: no raw `.padding(13)`, no ad-hoc `Color(...)`, no inline `.animation(.easeInOut(duration: 0.3))`.
2. **Engine numbers transition, never snap.** Every readout uses `contentTransition(.numericText())` over mono tabular figures, so a readiness, e1RM, volume, or target value change rolls in place with no width jump.
3. **Every screen has three non-happy states.** Empty (no data yet), loading (skeleton, not blank), and error (typed-error copy at the UI edge) are all designed and previewed, not left as a spinner or a crash-to-blank.
4. **Both palettes, largest Dynamic Type.** Every component ships SwiftUI previews in dark and light and at the largest accessibility text size without clipping or column jump.
5. **Motion has a Reduce Motion twin.** Each transition collapses to a `quick` cross-fade under Reduce Motion, unit-tested via the existing capability abstraction.
6. **One primary number per card.** Hierarchy is carried by the type scale (`heroNumber` / `bigNumber` / `number`), not by nesting cards inside cards. Secondary metrics are `StatChip`s on a hairline row.

Feel (spring weights, haptic-motion sync, whether the reveal lands) is a Device Test Gate item (DT6), not agent-verifiable. Everything above is.

---

## 3. Requirements by axis

### A. Motion and transitions

Today `HelmMotion` tokens exist but screens largely use default or no transitions. Requirements:

- **Navigation continuity.** Card-to-detail uses matched-geometry where a card *becomes* a screen: Dashboard prescription card into Train, an exercise row into its history, a Trends card into its expanded chart. Sheets use `standard`; the numpad and pickers rise from the bottom third.
- **Numeric roll.** All engine readouts adopt `contentTransition(.numericText())`. The readiness score, e1RM, weekly volume, energy balance, and set targets animate value changes.
- **List choreography.** Set completion settles on the `settle` spring paired with the set-logged haptic; adding a set slides in; removing collapses; PR rows get a one-shot accent bloom.
- **Load choreography.** Cards resolve from a hairline skeleton shimmer, never pop from blank. Content staggers in top-to-bottom over `standard`.
- **Restraint guardrails.** No parallax for decoration, no bouncing, no second easing vocabulary. Motion serves reading then confirmation (DESIGN-SYSTEM section 6). StrongSplit's own reviewers flag overload; Helm's edge is calm.

### B. Density, spacing, layout rhythm

- **Vertical rhythm audit** across Dashboard, Train, Trends, Nutrition, Settings: one card gap value, one internal padding value, one eyebrow-to-content gap. Fix every drift to the spacing scale.
- **De-nest.** Remove card-inside-card. Where a group needs separation inside a card, use a hairline rule, not a nested surface. This is the visual instinct behind the reserved `dataSheet` skin and it reads cleaner immediately.
- **Column alignment.** Numbers right-aligned in tabular columns, labels left, arc centers optically aligned across a row of cards. Units one step smaller, `fgMuted`, trailing the number.
- **Hero-then-reference layout.** Top third is the hero read (score, today's headline), lower two thirds is denser reference data. Dashboard resolves the whole day in one scroll without crowding.

### C. Charts and data-viz

StrongSplit's most-praised feature is per-body-part bar charts. Helm already has the better idea (volume against MEV to MRV landmarks); it needs the better execution.

- **One chart language.** Every chart renders through `HelmChartStyle`: state-ramp colors only, mono tabular axis labels, hairline gridlines, no legends-as-clutter, no chart junk.
- **Signature chart: per-muscle volume vs landmarks.** Horizontal bars per muscle with MEV and MRV marked as bands; bar color by state (under MEV compromised, in range ready, at MRV primed, over MRV depleted). This beats a raw volume bar because it shows the *target*, which is the whole point of the engine. Make it the best-looking surface in the app.
- **Dashboard sparklines.** Inline 7-day sparklines on the readiness and weight cards for at-a-glance trend without a tab change.
- **Interactive scrub.** Drag to scrub any time-series with a mono value callout and a light haptic tick at each sample.
- **Honest empty charts.** Insufficient data shows "building baseline N/4" or "log 2 more sessions", never an empty axis.

### D. Overall finish

- **State coverage.** Empty, loading, and error designed for every screen (see the sleek bar). Empty states carry a faint Arc or the arc-trace motif and one line of useful copy, not a shrug.
- **Iconography discipline.** One SF Symbols weight and optical size per context; the arc-plus-trace motif reused for tab and section marks. No mixed icon families.
- **Surface discipline audit.** Radius 16 to 20 everywhere, 1px hairline, at most one restrained shadow token (or none). Every tappable surface has a pressed and, where relevant, active state.
- **Eyebrow consistency.** `monoTag` section eyebrows on every screen, same tracking and case.
- **Copy pass.** Terse, numbers-first, instrument voice, no filler, no em dashes, consistent capitalisation of `READY` / `PREV` / `TARGET` style labels.

### E. Signature moments (the premium investment)

Four moments carry disproportionate perceived quality. Elevate, do not merely wire:

1. **Readiness reveal** (built: `ArcRevealGauge`, `DailyRevealGate`). Add a subtle state-tint bloom behind the arc as it strokes, contributors staggering in over the final 0.3s, haptic swell cresting on land. Once per day, first Dashboard appearance. This is the app's hello.
2. **PR celebration** (built: `PersonalRecordsCelebrationView`). A state-colored arc burst and the PR-hit haptic, restraint over confetti: a memorable instrument moment, once per detected PR.
3. **Workout finish summary.** A dedicated post-session moment: total volume, sets logged, TRIMP contribution, and an animated preview of how the added volume moved each muscle toward its weekly landmark, plus a one-line "tomorrow's readiness impact" teaser. Turns finishing into a payoff.
4. **Onboarding sequence** (assembled: `M6.4`). The Arc draws itself on the welcome; the 6-month backfill renders as an Arc filling to completion; the first readiness reveal is the payoff at the end. First run should feel authored.

### F. Second layout skin (activate the reserved M0.8)

The `HelmSkin` seam already exists (`instrument` shipped; `dataSheet`, `stateField`, `blueprint` reserved). Ship a second skin so a sleeker look is switchable in Settings.

- **Recommendation: ship `dataSheet` as the second skin.** Borderless, hairline-ruled, denser. It directly answers the density axis and is the cleanest, most "instrument" of the three. Reserve `stateField` (full-bleed state hero, the loud marketing look) and `blueprint` for later.
- The switch is a Settings control persisted alongside `HelmTheme`. Tokens, Arc, type, motion, and haptics are shared; only the `SkinnedContainer` treatments differ.

### G. Data visibility and reference bands (the transparency theme)

Prompted by the StrongSplit gallery. Nearly every number in that app sits inside its own personal reference range with a plain-language verdict: HRV `45.3 ms` drawn as a marker inside the band `44.3 to 49.3 ms` tagged `GOOD`; recovery `81/100` against a `70 to 90` target band over 10 days; per-muscle sets ranked with days since trained; the full progression scheme (rep range, RPE cap, increment) with a tick-off level ladder. It is not better science. It is the same numbers shown against a baseline so the reasoning is legible. That legibility is most of what reads as sleek and intelligent.

Helm already computes richer versions of all of it and shows less. Verified against the engines:

- `ReadinessKit` exposes `Baseline.mean` and `robustSigma` (the band), `ReadinessScore.band`, `hrvBand`, and per-contributor z-scores. The Dashboard renders an abstract unitless z-score bar, not the real value in its real-unit band.
- `PlanKit` holds the mesocycle state (MEV to MRV position, deload schedule), Epley e1RM, and RIR-autoregulated progression. The app surfaces only today's prescription, never the model or the user's position in it.
- `MuscleVolumeArcGridCard` already shows per-muscle weekly hard sets against MEV/MRV landmarks, which is better science than a raw set count, but it is buried in Trends and lacks the recency (days since trained) dimension.

So this is a surfacing deficit, not an algorithm one. The reframe: **transparency plus interpretation, not one instead of the other.** Their card shows `HRV 45.3 ms GOOD` and stops. Helm shows the same band bar and then the coach reads it: "HRV is suppressed against your 14-day baseline, likely the late night, so I trimmed the top two sets and capped RPE at 8." The band earns trust in the number; the coach turns the number into a changed plan. Show the data *because* it makes the adjustment believable.

Requirements:
- **One reference-band atom.** A `DeviationBand` component: a value marker inside a personal-range band, real units, state-coloured, optional verdict tag. It is the atom the whole look is built from, and the engines already feed it. It replaces the abstract z-bar and is reused by readiness contributors, nutrition targets, sleep, and body composition.
- **Consolidate recovery.** One recovery detail view: score against its target band, history with the band overlaid, each contributor as a `DeviationBand`, and the coach's one-line read. Pulls together what is currently split across the Dashboard card, the Trends history chart, and the tap-away explain sheet.
- **Make the plan model visible.** A progression / plan-model view surfacing the mesocycle position, the progression scheme, and a per-lift level ladder with e1RM. This is the largest genuine visibility gap and overlaps the deferred M13.1/M13.2.
- **Promote muscle volume.** Add days-since-trained/recovery to the muscle-volume gauge and lift the per-muscle board out of Trends onto Train/Dashboard, keeping the landmark bands.

---

## 4. Drop-in plan sections (paste into PLAN.md, add PROGRESS.md rows)

New band **M12 Design polish and league push**, plus activation of the reserved **M0.8**. All sections are UI-layer and DesignSystem-layer only; no engine, schema, or migration changes. All acceptance is agent-verifiable (build under Swift 6 complete concurrency with zero warnings, SwiftLint clean, previews, unit tests where noted); device *feel* is DT6.

Suggested order: M12.2 (rhythm) first so later sections lay out on a fixed grid, then M12.1 (motion), M12.3 (data-viz), and M12.6 (the `DeviationBand` atom) in parallel, then M12.4 (finish), M12.5 (signature moments), and the transparency views M12.7 to M12.9 (which consume M12.6), with M0.8 last since it must cover the polished screens.

The transparency band (M12.6 to M12.9) reprioritises the deferred M13.1 (planned workout UI) and M13.2 (drift policy UI): M12.8 pulls their plan-visibility intent forward. Treat M13.1/M13.2 as absorbed by M12.8 rather than built separately, or trim them to what M12.8 does not cover.

### M12.1 Motion and transition pass
- **Track**: A (UI / DesignSystem). **Depends on**: M0.7, and the shipped screens (M2.3, M3.3 to M3.5, M6.3, M9.2, M10.1).
- **Goal**: every screen transition and every engine readout moves per DESIGN-SYSTEM section 6, calmly and consistently.
- **Scope**: add a small set of reusable motion modifiers in DesignSystem (numeric-roll wrapper, skeleton shimmer, staggered-appear, matched-geometry card-to-detail helper); adopt them on Dashboard, Train, Trends, Nutrition; wire `contentTransition(.numericText())` on all engine numbers; pair set-completion/PR/adjustment motion with their existing haptics. No new motion tokens.
- **Acceptance**: grep shows no ad-hoc `.animation(...)` durations outside tokens; every engine readout uses the numeric-roll wrapper; skeleton and staggered-appear have previews; Reduce Motion collapses each to a `quick` cross-fade (unit-tested via the capability abstraction); SwiftLint clean.

### M12.2 Layout rhythm and density audit
- **Track**: A. **Depends on**: M0.7 and shipped screens.
- **Goal**: one spacing rhythm and one hierarchy discipline across the app; no card-in-card.
- **Scope**: audit and fix Dashboard, Train, Trends, Nutrition, Settings to the spacing scale; de-nest surfaces (hairline rules replace nested cards); enforce one-primary-number-per-card with `StatChip` rows for secondaries; column alignment and unit treatment per DESIGN-SYSTEM section 2 and 5.
- **Acceptance**: grep shows no raw spacing literals outside the scale in the audited views; no nested `Card` within `Card`; previews in both palettes and at the largest Dynamic Type size show no clipping or column jump; SwiftLint clean.

### M12.3 Data-viz refinement
- **Track**: A. **Depends on**: M12.2, M10.1 (Trends), M2.2/M9.1 (data).
- **Goal**: one chart language, a signature per-muscle-vs-landmark chart, Dashboard sparklines, interactive scrub.
- **Scope**: route every Trends card and any inline chart through `HelmChartStyle` (state-ramp only, mono tabular axes, hairline gridlines); rebuild the per-muscle volume card as horizontal bars with MEV/MRV bands and state coloring; add 7-day sparklines to the readiness and weight Dashboard cards; add drag-to-scrub with a mono callout and a light haptic tick; honest insufficient-data states on every chart.
- **Acceptance**: all charts consume `HelmChartStyle` and design-system primitives only (no arbitrary colors); the per-muscle card renders under, in-range, at, and over-MRV states in previews; sparkline and scrub have previews and a Reduce Motion path; insufficient-data states previewed; SwiftLint clean.

### M12.4 Finish pass: states, iconography, consistency
- **Track**: A. **Depends on**: M12.2.
- **Goal**: shipped-product finish on the last 15 percent.
- **Scope**: design empty, loading (skeleton), and error states for every screen; iconography audit to one weight/size per context with the arc-trace motif on tab and section marks; surface-discipline audit (radius, hairline, pressed/active states on every tappable surface); `monoTag` eyebrow consistency; a copy pass for terseness and label consistency.
- **Acceptance**: every screen has previewed empty/loading/error states; a documented icon set with consistent weights; grep shows pressed/active states on interactive surfaces; no em dashes in any in-app string; SwiftLint clean.

### M12.5 Signature moments
- **Track**: A / coach-UI. **Depends on**: M12.1, M2.3 (reveal), M3.5 (PR), M6.4 (onboarding).
- **Goal**: make the reveal, PR, workout finish, and onboarding feel premium and memorable.
- **Scope**: elevate the readiness reveal (state-tint bloom, contributor stagger, haptic swell already present); elevate PR celebration (arc burst, once per PR); build the workout-finish summary moment (volume, sets, TRIMP, animated landmark movement, tomorrow-readiness teaser); author the onboarding sequence (self-drawing Arc, backfill-as-filling-Arc, first reveal as payoff).
- **Acceptance**: each moment has previews across its states; reveal and PR fire once per day / once per PR (unit-tested via the existing gates and detection query); finish summary renders from fixture session data; all four honor Reduce Motion; SwiftLint clean. Feel is DT6.

### M12.6 DeviationBand component (the reference-band atom)
- **Track**: A (DesignSystem). **Depends on**: M0.7.
- **Goal**: one reusable component that plots a value inside its personal reference range, the atom the transparency theme is built from.
- **Scope**: a `DeviationBand` view in DesignSystem taking a current value, a band (lower/upper, typically `mean ± robustSigma` or a target range), units, a `HelmState` for colour, and an optional verdict tag (`GOOD` / label). Marker inside a hairline band track, mono tabular value, unit one step smaller in `fgMuted`, state colour on the marker and tag. A horizontal `bar` layout (contributor rows) and a compact inline layout. No engine change; the values are supplied by the wiring layer.
- **Acceptance**: previews for in-band, below-band, above-band, and cold-start (no band yet) in both palettes and at the largest Dynamic Type; state never encoded by colour alone (value and tag always present); numeric-roll on value change; SwiftLint clean; zero hard-coded colours.

### M12.7 Recovery detail view
- **Track**: A / readiness-UI. **Depends on**: M12.6, M2.2/M2.3, M10.1 (history), and benefits from M4.5 (coach) for the narration line.
- **Goal**: one screen that consolidates the scattered recovery pieces and reads the way StrongSplit's recovery screen does, plus the coach's interpretation.
- **Scope**: score against its target band; readiness history with the band overlaid (reuse the Trends history query, restyled through `HelmChartStyle`); each contributor (HRV, resting HR, sleep) as a `DeviationBand` in real units, reconstructed from the stored daily metric plus the persisted `readiness_baseline_state` (`mean`, `robustSigma`); the coach's one-line read at the top, degrading to the engine contributor summary when the coach is offline; an "Ask coach about this" hand-off. Reachable from the Dashboard readiness card.
- **Acceptance**: renders from fixture readiness + baseline data for good/compromised/cold-start states; contributor bands show real units and the personal range; offline path shows engine summary with the coach hand-off disabled; snapshot tests per state; no engine change (pure wiring over existing repositories); SwiftLint clean.

### M12.8 Progression / plan-model view (absorbs deferred M13.1/M13.2)
- **Track**: plan-UI. **Depends on**: M12.2, PlanKit (M5.x), M3.5 (PR/e1RM queries).
- **Goal**: make the plan model and the user's position in it visible, not just today's prescription.
- **Scope**: surface the current mesocycle position (block, week, MEV to MRV ramp state, scheduled deload) from `PlanKit` mesocycle state; the active progression scheme (rep range, RPE cap, sets-per-session, load increment); and a per-lift level ladder with estimated 1RM and per-step deltas from the logged history. Read-only visibility in v1 (editing stays in Settings/plan config); this is the plan-visibility intent of the deferred M13.1/M13.2 pulled forward. Reachable from the Dashboard prescription card and Train.
- **Acceptance**: renders from fixture mesocycle state and logged history for mid-meso, deload-week, and cold-start; the level ladder marks completed steps from real queries (not stored as truth); no engine or schema change; SwiftLint clean. Update the deferred M13.1/M13.2 rows to note they are absorbed here.

### M12.9 Muscle-volume promotion and recency
- **Track**: A / plan-UI. **Depends on**: M12.2, M10.1, PlanKit weekly hard-set ledger.
- **Goal**: lift the landmark-aware per-muscle volume board out of Trends into a first-class surface, with the recency dimension StrongSplit shows.
- **Scope**: extend `MuscleVolumeGauge` with days-since-trained per muscle (from the ledger/last-session query); a ranked per-muscle board (sets vs MEV/MRV landmark band, state colour, days since trained), promoted onto Train and summarised on the Dashboard; keep the existing `ArcGauge` grid available in Trends. Landmark bands stay; do not regress to raw counts.
- **Acceptance**: board renders under-MEV, in-range, at-MRV, and over-MRV states with recency from fixtures; the Dashboard summary and the Train board share one view model; previews in both palettes; no engine change beyond the additive recency field on the view model; SwiftLint clean.

### M0.8 Second layout skin (activate reserved): ship `dataSheet`
- **Track**: A. **Depends on**: M0.7 and the M12 polished screens (so the second skin covers finished compositions).
- **Goal**: a second switchable `HelmSkin` layout family, borderless and hairline-ruled, denser than `instrument`.
- **Scope**: implement `dataSheet` treatments for every `SkinnedContainer` site and the Dashboard/Train/Trends compositions; a Settings control to switch skin live, persisted alongside `HelmTheme`; reserve `stateField` and `blueprint` still behind the seam.
- **Acceptance**: switching skin re-renders every screen with no layout breakage in simulator, in both palettes and at the largest Dynamic Type; no color or layout constant outside DesignSystem; previews per skin. Feel and perf on device at DT6.

---

## 5. Device Test Gate addition

### DT6 (after M12.5 and M0.8): the polish gate
- Every named haptic still syncs to its motion on a real iPhone; the readiness reveal, PR burst, and workout-finish summary land as premium moments.
- Skeleton-to-content and matched-geometry transitions feel fluid at 120Hz, no dropped frames on device.
- Both skins switch live with no flash or layout break, in dark and light.
- Empty/loading/error states verified on device with real (and absent) data.
- Largest Dynamic Type pass on Dashboard and the set row.
- `DeviationBand` reads correctly against real HealthKit-derived baselines on device (right units, band the right width, verdict matches the engine); the recovery detail view, progression view, and muscle-volume board reconcile with the engine numbers.

---

## 6. What not to do

- No new identity. No second accent, no gradients-for-decoration, no new type family, no new motion easing vocabulary. The instrument thesis stands; this is execution.
- No engine, schema, or migration changes. Every section is UI-layer and DesignSystem-layer.
- Do not chase StrongSplit's density. Their reviewers call it overload; Helm's edge is a calm instrument that has already decided the day. Add finish, not features-as-chrome.
- Do not gate build agents on device feel. Feel is DT6; presence, tokens, previews, and Reduce-Motion paths are agent-verifiable.
- Do not rewrite shipped `PROGRESS.md` rows. M12 and M0.8 are new/activated sections, appended, per the append-only rule.
