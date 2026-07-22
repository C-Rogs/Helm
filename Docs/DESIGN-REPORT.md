# Helm — Design report for the architect agent

> Purpose: a design assessment of Helm at its current progress (end of M3.1) and a set of concrete, plan-shaped changes to fold into `PLAN.md` / `PROGRESS.md`. This file is advisory. It does not edit the plan. The architect decides what to adopt and appends the milestones below in the plan's own format.
>
> Two normative companions live in `Docs/`:
> - `Docs/DESIGN-SYSTEM.md` — the elevated visual system (color, type, the Arc, components, motion).
> - `Docs/HAPTICS.md` — the haptic vocabulary and engine contract.
>
> A visual reference artifact, `Helm Design Proposal.dc.html`, shows the whole system rendered (theme, app icon directions, Dashboard / Train / Trends, haptic vocabulary). Open it in a browser. It is a reference, not shipping code.

---

## 1. Assessment

### The app, overall

The architecture is strong and the discipline is unusually high for an agent-built codebase: pure engines on value types, a strict dependency direction, append-only migrations, fixtures over live services, honest cold-start, and a real correctness spend concentrated where it matters (ReadinessKit, PlanKit, ingest). The product thesis is also genuinely differentiated: a closed-loop prescription engine that spans recovery, strength, and nutrition, where the plan is the product and the LLM narrates rather than performs. Nothing here needs rescuing.

The gap is not engineering. It is that a product whose entire value is *"the day is already decided, and the numbers are trustworthy"* has, so far, a design system (M0.4) sized to not embarrass the tab shell: tokens plus Card, Gauge, StatRow. That is correct for M0.4 and insufficient for the product. An instrument earns trust through consistency of read, restraint, and feedback. Right now those three are unspecified, which means every screen agent will invent them, and the app will read as a series of independently prompted patches. That is the exact failure mode the plan warns against under "Read like a human wrote it."

### UX

What is right: the single-scroll Dashboard that opens with the day resolved; prescription-driven Train instead of a blank logger; the custom numpad decision; readiness gating made visible; confidence labels shown honestly. These are the good bones.

Where it can be streamlined:

- **No shared "show your working" affordance.** The plan repeats that everything on screen is something an engine acted on, but there is no consistent way to interrogate a number. Cameron will want to ask "why 61?" and "why minus two sets?" in the same gesture, everywhere. Without one pattern, each screen invents its own, or none does.
- **Adjustments have no consistent provenance treatment.** Readiness gating, flagged-context adjustments, and in-session swaps all mutate the plan, but they are surfaced in three different places with three different vocabularies. They should read as one thing: a labeled, reversible change the coach made, always in the same visual and haptic form.
- **The five-tab structure is fine, but Nutrition and Sources are homeless.** The plan folds them into Dashboard cards and Settings-hosted markdown for v1, which is the right scope call, but the navigation to them should be decided once (card tap targets), not per-card.
- **Feedback is undesigned.** For a gym app used one-handed, mid-set, often not looking at the screen, haptics are not polish, they are the primary confirmation channel. They are currently absent from the plan.

### Design / visual

M0.4 established OLED-black. That is the right base and should stay. What is missing is a point of view: a signature element, a numeric voice, a color discipline, and a motion + haptic language. Absent those, "OLED-black" is a background color, not a design system. Section 2 proposes that point of view; `Docs/DESIGN-SYSTEM.md` specifies it.

---

## 2. Proposed direction (summary; full spec in Docs/DESIGN-SYSTEM.md)

**Thesis: an instrument, not an app.** Helm reads out the body the way a cockpit reads out an aircraft. Numbers are the hero.

- **Signature element: the Arc.** One shape carries the system. The readiness engine is literally ARC, so the arc gauge becomes the readiness reveal, the MEV to MRV volume meter, the energy-balance dial, and the app icon. It is learned once and read everywhere. This is the single most valuable thing to adopt: it converts scattered components into one recognizable language, and it is cheap because it is one well-specified SwiftUI view.
- **Type: grotesk voice, mono readout.** Space Grotesk for display and UI labels; JetBrains Mono with tabular figures for every engine number (score, load, reps, RPE, kcal, e1RM). Monospaced numerals stop columns from jumping and reinforce the instrument read. Both are OFL and embeddable.
- **Layout direction: decided — the `instrument` (card) baseline.** Cameron chose the card-stacked baseline for v1 on readability. The three alternative directions (Data-sheet, State-field, Blueprint) are shown in the reference and stay reserved behind the skin seam for a possible later switch, not built in v1. The tokens, Arc, type, motion, and haptics below are skin-independent and apply regardless.
- **Color: black, warmed, one accent, two profiles.** True black canvas for OLED dark; warm paper for light (never cold white); appearance follows the system so both must exist for every component. Acid-lime (`#C6F24E`) is the only brand accent, darkened to `#4F6B00` for AA on light. Everything else is a four-stop semantic state ramp (depleted, compromised, ready, primed) reused for readiness, volume-vs-landmark, and energy balance.
- **App icon: fitness-analysis, not nautical.** The arc reading a value against a scale. Cameron selected treatment C, the arc meeting a data trace, as the marque, with the accent-field tint (B) as the loud alternate. Rendered in the reference artifact; ship dark-field and light-field renderings.
- **Motion + haptics as a language.** Twelve named haptic patterns in four groups, each mapped to one class of moment, each firing with its motion counterpart. Specified in `Docs/HAPTICS.md`.

### UX moves worth folding in

1. **"Show your working" (tap-to-explain).** Any engine number reveals its contributors and, where relevant, its citation, in one consistent sheet. This is the honest-instrument gesture and it reuses the coach and the methodology library the plan already builds. Fires the selection haptic.
2. **One provenance treatment for every plan change.** Readiness gating, flagged-context adjustments, and in-session swaps all render as the same labeled, reversible diff (see the Train banner in the reference), always logged to `coach_recommendation`, always confirmed by the coach-adjust haptic. One vocabulary, three sources.
3. **Thumb-reach discipline.** Ask-coach bar and numpad sit in the bottom third; the reveal and reading sit up top. Codified in the design system so screen agents do not relitigate it.

---

## 2.1 On shipping multiple skins (a switchable "profile")

Can Helm ship more than one look with a switch? Yes, and the plan is already shaped for it: the M0.4 rule that no color lives outside the token file means styling is already centralized. Split the idea into two axes so the cost is clear:

- **Palette skin** (dark, light, and any accent variant): trivial. It is a swap of token *values* behind a `HelmTheme` environment value. Dark/light is already mandatory (the app follows system appearance), so an explicit override switch is nearly free and should ship in v1.
- **Layout skin** (Data-sheet vs State-field vs Blueprint vs the card baseline): tractable but not free. Each shared component and the Dashboard composition needs a rendering per skin, each maintained and device-tested. This multiplies UI surface area, which is the expensive kind of code for build agents.

**Recommended posture (mirrors the plan's reserved-provider-slot pattern):** build the *seam* now, ship one layout for v1, reserve the second.
- Introduce a `HelmSkin` environment value alongside `HelmTheme` in M0.7. Components read `HelmSkin` to choose their container treatment (a `SkinnedContainer` that renders as a Card, a ruled section, a full-bleed field, or a graticule block). Everything else (tokens, Arc, type, motion, haptics) is skin-independent and shared.
- Ship exactly one layout skin in v1: the `instrument` (card) baseline, chosen for readability. The palette switch (dark/light/auto) ships fully.
- Reserve the second layout skin behind the seam. Adding it later is a new section, not a rearchitecture, and touches only the skinned components.

This keeps v1 honest while making a "profiles" switcher a later drop-in rather than a rewrite. If Cameron wants two full layout skins in v1 for the pleasure of switching, that is a deliberate scope addition (see optional M0.8), not the default.

## 3. Fold-in plan (drop-in milestones, plan format)

These are written so the architect can paste them into `PLAN.md` and add matching `PROGRESS.md` rows. They respect the existing dependency direction and the "~5 packages, not ~10" rule: **haptics and the Arc live inside the existing `DesignSystem` package**, no new package. Two already-shipped sections (M0.4 tokens, M2.2 readiness card) get small, explicitly-scoped re-skin follow-ups rather than edits to their shipped rows, per the append-only progress rule.

### New: M0.7 DesignSystem v2 (Arc, type, color, motion, haptic engine)
- **Track**: A (UI shell / design system). **Depends on**: M0.4, M0.3.
- **Goal**: turn the M0.4 base into a full instrument system so no screen agent invents styling, motion, or feedback.
- **Scope**:
  - Elevate tokens to the `Docs/DESIGN-SYSTEM.md` spec, **as two profiles (dark primary + light), switched by system appearance**: warm-black and warm-paper surface ladders, foreground ladders, acid-lime accent (darkened for AA on light), the four-stop readiness state ramp, radius and spacing scale. Keep every color in the single token file (M0.4 acceptance carries forward: zero hard-coded colors outside it). Every component must read correctly in both profiles.
  - Introduce two environment values that drive appearance: `HelmTheme` (palette: dark / light / auto, defaulting to system appearance with an explicit override in Settings) and `HelmSkin` (layout family). Add a `SkinnedContainer` primitive that the shared components render through, so the chosen skin decides whether a section is a Card, a ruled block, a full-bleed field, or a graticule block. **v1 wires the `instrument` (card) skin only**; the seam is the point (Data-sheet / State-field / Blueprint reserved for a later M0.8). Tokens, Arc, type, motion, and haptics are skin-independent.
  - Register and wrap the two typefaces (Space Grotesk, JetBrains Mono) with a `HelmType` scale; all numeric styles use monospaced tabular figures.
  - `ArcGauge` component: 270-degree sweep, configurable value, track, and state color, with an optional center readout slot and a reveal animation. This is the signature view; readiness, volume, and energy balance all consume it.
  - Motion tokens (`Docs/DESIGN-SYSTEM.md` section 6): standard durations and curves, plus the named readiness-reveal timeline, all honoring Reduce Motion.
  - `HapticEngine` in DesignSystem per `Docs/HAPTICS.md`: Core Haptics patterns for the twelve named events (four groups), `UIFeedbackGenerator` fallback when the device or setting disallows CHHapticEngine, a Settings toggle, and Reduce-Motion / low-power respect. AHAP assets bundled.
- **Acceptance (agent-verifiable)**: tokens centralized, SwiftUI previews for `ArcGauge` in every state and cold-start; `HapticEngine` compiles, resolves each named pattern, and no-ops safely without a haptics-capable device (unit-tested via the capability abstraction); Reduce Motion path unit-tested; SwiftLint clean; zero hard-coded colors outside the token file. Real haptic *feel* is a device-gate item, added to DT1.

### New (optional, reserved): M0.8 Second layout skin
- **Depends on**: M0.7, and whichever screens the second skin must cover. **Track**: A. **Status: build only if Cameron wants an in-app layout switcher in v1.**
- **Goal**: a second full `HelmSkin` layout family selectable at runtime (the "profiles" switcher).
- **Scope**: implement a second skin's treatments for every `SkinnedContainer` site and the Dashboard/Train/Trends compositions; a Settings control to switch skin live; persistence of the choice.
- **Acceptance**: switching skin re-renders every screen with no layout breakage in simulator, in both palettes; no color or layout constant lives outside DesignSystem; previews per skin. Feel/perf on device added to DT-next. Default recommendation is to defer this and ship one skin; the M0.7 seam makes deferring cheap.

### New: M2.3 Readiness card re-skin + reveal (targeted follow-up to M2.2)
- **Depends on**: M0.7, M2.2. **Track**: A.
- **Goal**: bring the already-shipped readiness card up to the Arc + reveal + signature-haptic spec without touching M2.2's engine wiring.
- **Scope**: replace the M2.2 gauge with `ArcGauge`; add the readiness-reveal motion timeline and the readiness-reveal haptic, fired once per day on first Dashboard appearance (not on every recompute); state color drives the arc and the label; confidence and cold-start states render per spec.
- **Acceptance**: card renders all readiness states and cold-start via `ArcGauge` in simulator; reveal plays once per day (unit-tested via the day-boundary abstraction and a "seen today" flag); Reduce Motion collapses the reveal to a cross-fade; recompute does not re-trigger the reveal.

### New: M4.6 "Show your working" sheet (tap-to-explain)
- **Depends on**: M2.2, and benefits from M4.5 (chat) and M10.2 (methodology) when present; degrades to engine-only contributors when the coach is offline. **Track**: coach/UI.
- **Goal**: one consistent affordance to interrogate any engine number.
- **Scope**: a reusable explain sheet that takes a number, its contributor breakdown, and an optional citation reference, presented from a long-press or an info affordance on any readout; an "Ask coach about this" hand-off that seeds a chat turn; selection haptic on open.
- **Acceptance**: sheet renders from fixture inputs for readiness, prescription volume, and a nutrition target; offline shows engine contributors with the coach hand-off disabled; snapshot tests per input type.

### Edits threaded into existing (not-yet-built) sections
The architect should add one scope line and one acceptance line to each, rather than new sections:

- **M3.3 Train screen**: adopt the `Docs/DESIGN-SYSTEM.md` set-row and numpad specs; fire the **set-logged** haptic on set completion and the **selection** haptic on numpad keys. Acceptance: haptic calls present at the two sites (grep-level), no haptic on an already-completed row.
- **M3.4 Rest-timer / Live Activity**: fire the **rest-done** haptic, and ensure the scheduled-notification path carries the same pattern so it fires while suspended. Acceptance: the suspended path uses the notification sound/haptic, added to DT2.
- **M3.5 History / PRs**: fire the **PR-hit** haptic on a qualifying record, once per record. Acceptance: PR haptic fires exactly once per detected PR (unit-tested via the detection query).
- **M6.2 In-session coach**: every applied adjustment renders in the shared provenance treatment (labeled, reversible, logged to `coach_recommendation`) and fires the **coach-adjust** haptic. Acceptance: adjustment banner matches the design-system provenance component; haptic fires on apply and undo restores cleanly.
- **M10.1 Trends**: per-muscle volume-vs-landmark and energy balance use `ArcGauge`; charts use the state ramp, not arbitrary colors. Acceptance: charts consume design-system primitives only.
- **Global**: the **selection** haptic is wired at the tab bar and segmented controls in whichever section first introduces them (M0.4 shell is already done, so the wiring lands in M0.7 alongside the engine).

### Device Test Gate additions
- **DT1**: verify each named haptic *feels* correct on a real iPhone (CHHapticEngine present); readiness reveal plays once and feels like the signature moment; Reduce Motion and the haptics-off setting are honored.
- **DT2**: rest-done haptic fires while the app is suspended (via the scheduled notification), not only in-foreground.

---

## 4. What not to do

- Do not add a haptics or Arc package. Both live in `DesignSystem`; the plan's "~5 packages" rule stands.
- Do not re-skin engines. All of this is UI-layer and DesignSystem-layer; the pure engines and their tests are untouched.
- Do not gate build agents on device haptic verification. Feel is a DT item; the engine's *presence and safety* is agent-verifiable.
- Do not introduce a second accent or gradients-for-decoration. One accent, one state ramp, warm blacks. Restraint is the aesthetic.
- Keep the "no em dashes in copy" rule from M0.4; it extends to all in-app strings in the new components.
