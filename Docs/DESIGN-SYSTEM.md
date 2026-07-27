# Helm DesignSystem (v2)

> Normative spec for the `DesignSystem` package. Elevates the M0.4 base into a full instrument system. Every screen agent reads this before laying out a screen. Rendered reference: `Helm Design Proposal.dc.html`. Companion: `Docs/HAPTICS.md`.
>
> Standing rules carried from M0.4: OLED-black base, no em dashes in any in-app copy, zero hard-coded colors outside the token file.

## 0. Thesis

An instrument, not an app. Helm reads out the body the way a cockpit reads out an aircraft. Numbers are the hero; chrome recedes; color is a signal, not decoration. Everything on screen is something an engine acted on, and the design should make that legibility, not marketing, the feeling.

## 1. Color

Two profiles, selected automatically by the system appearance (the app follows Light/Dark, it does not offer its own switch). **Dark** is the primary: true black canvas for OLED, warm near-black surfaces (a trace of yellow, never blue-grey). **Light** is warm paper, never cold white. One brand accent in both; everything else is a semantic state ramp. Author every component against both token sets from the start; a component is not done until it reads correctly in both.

### Dark profile (primary)

| Token | Hex | oklch (approx) | Use |
|---|---|---|---|
| `canvas` | `#000000` | oklch(0 0 0) | app background, OLED true black |
| `surface` | `#111112` | oklch(0.18 0.003 100) | cards, sheets |
| `surfaceElevated` | `#1C1C19` | oklch(0.24 0.005 100) | rows, inputs, pressed cards |
| `hairline` | `rgba(255,255,255,.09)` | | 1px borders, dividers |
| `fg` | `#F4F3EE` | oklch(0.96 0.006 95) | primary text, active numerals |
| `fgSecondary` | `#A8A7A0` | oklch(0.73 0.005 95) | body, secondary labels |
| `fgMuted` | `#6B6A63` | oklch(0.52 0.006 95) | units, captions, mono tags |
| `accent` | `#C6F24E` | oklch(0.90 0.19 128) | brand, "primed", primary action, focus |

**State ramp** (readiness, volume-vs-landmark, energy balance, any good/bad signal):

| State | Hex | Readiness band |
|---|---|---|
| `depleted` | `#FF6A4D` | 0 to 39 |
| `compromised` | `#FFB648` | 40 to 54 |
| `ready` | `#D7E85A` | 55 to 74 |
| `primed` | `#C6F24E` | 75+ (equals `accent`) |

### Light profile

Warm paper, dark ink, the same accent darkened to hold AA against light. The state ramp shifts down in lightness so it stays legible on paper; hue stays constant so meaning is unchanged.

| Token | Hex | Use |
|---|---|---|
| `canvas` | `#F4F2EC` | app background, warm paper |
| `surface` | `#E9E6DC` | cards, sheets |
| `surfaceElevated` | `#FFFFFF` | rows, inputs |
| `hairline` | `rgba(0,0,0,.14)` | borders, dividers |
| `fg` | `#16150F` | primary text, active numerals |
| `fgSecondary` | `#57564D` | body, secondary labels |
| `fgMuted` | `#8A887E` | units, captions |
| `accent` | `#4F6B00` | brand, actions, focus (AA on paper) |
| `accentFill` | `#C6F24E` | accent used as a fill/highlight behind dark ink only |
| state ramp | `#C24A2E` / `#B56B00` / `#5F7A0A` / `#4F6B00` | depleted / compromised / ready / primed |

The bright acid-lime (`#C6F24E`) never carries text on light; it is a fill only, always with dark ink on top. Text-weight accent uses the darkened `#4F6B00`. In the full-bleed State-field direction the lime field is intentional and keeps its brightness in both profiles (dark ink on top).

Rules: one accent only, no second brand color. No decorative gradients; a radial vignette on the app icon and nowhere else. State colors are reserved for state. Never color body text; use the fg ladder.

## 2. Type

Two families. Space Grotesk speaks; JetBrains Mono reads out. Both OFL, bundled in-app.

- **Display / titles / UI labels / body**: Space Grotesk. Weights 400, 500, 600.
- **All numeric readout**: JetBrains Mono, `monospacedDigit` / tabular figures, weights 600, 700. Score, load, reps, RPE, kcal, e1RM, timers, percentages, dates, and the small-caps mono labels (`READY`, `PREV`, `TARGET`).

`HelmType` scale (points, Dynamic Type scales from these as the base):

| Style | Family | Size / weight | Notes |
|---|---|---|---|
| `heroNumber` | Mono | 64+ / 700 | the readiness score, one per screen |
| `bigNumber` | Mono | 26 / 700 | card metric readouts |
| `number` | Mono | 16 / 600 | set rows, inline values |
| `title` | Grotesk | 22 / 600 | screen and card titles |
| `label` | Grotesk | 17 / 600 | list primary text |
| `body` | Grotesk | 13.5 / 400 | narration, descriptions |
| `monoTag` | Mono | 10 to 11 / 500, tracking +0.16em, uppercase | section eyebrows, unit labels |

Numerals never change width between values (tabular). Units (`kg`, `%`) are `fgMuted` and one step smaller than the number they trail.

## 3. The Arc (signature element)

One shape carries the system. A 270-degree gauge that reports a value against a scale. Consumed by the readiness reveal, the MEV to MRV volume meter, the energy-balance dial, and the app icon.

Geometry (specify once, reuse everywhere):
- Sweep 270 degrees, gap 90 degrees at the bottom. Draw as a stroked circle: `strokeDasharray` value over the 270-degree arc length, rotated so the gap sits bottom-center (in SwiftUI, trim 0 to 0.75 and rotate 135 degrees; round line caps).
- Two layers: track at `hairline`, value at the state color for the metric.
- Optional center slot: `heroNumber` plus a `monoTag` state label plus an optional confidence caption.
- Stroke weight scales with radius: roughly `radius * 0.12`, capped for legibility on the Watch complication and Live Activity.

`ArcGauge` API (SwiftUI): `value: Double`, `range: ClosedRange<Double>`, `state: HelmState` (drives color), `track: Color = .hairline`, `lineWidth: CGFloat?`, and a `@ViewBuilder center` slot. A `reveal` modifier animates the value stroke from 0 on first appearance (section 6).

## 4. Components

Build these in DesignSystem so screens compose, never re-invent.

- **Card**: `surface`, radius 16 to 20, 1px `hairline`, padding 15 to 16. The universal container. Elevated/pressed state swaps to `surfaceElevated`.
- **StatChip**: small `surface` tile, `number` value over a `monoTag` label, value colored by state. Used for readiness contributors (HRV, RHR, sleep, TRIMP).
- **BriefCard**: a Card with a `monoTag` eyebrow, an optional citation chip (right-aligned, `surfaceElevated`, mono), and `body` narration. The coach's voice container.
- **PrescriptionRow**: `label` exercise name left, `number` target right (`3x8 · 30kg`). An adjusted badge (state-colored, e.g. `-2 SETS`) when the engine or coach changed it.
- **SetRow**: index (`monoTag`), weight, reps, RPE (all `number`), and a completion control. Completed rows carry an accent-tinted border; the active row a solid `fg` border with the focused field underlined in `accent`. This is the core loop surface; it must feel identical every rep.
- **Numpad**: custom numeric keypad (`UIViewRepresentable`, per the plan's live-workout teardown lesson). 3-column grid, `surfaceElevated` keys, mono glyphs, an accent primary action (`NEXT`). Selection haptic per key.
- **AdjustmentBanner (provenance)**: the single treatment for any **confirmed** plan change (readiness gating, flagged context, in-session swap/load/RPE). Accent-tinted surface, a change glyph, `from -> to` in `fg`, a reason in `body`, and an `UNDO` affordance. Shown only after the athlete confirms an in-session proposal; always logged to `coach_recommendation` on apply; pairs with coach-adjust haptic and the apply-wave overlay. Advisory coach replies (no prescription diff) stay silent: no banner, haptic, or wave.
- **AskCoachBar**: bottom-anchored, thumb-reach, a pulsing accent dot plus prompt text. Present on Dashboard and in-session. In-session opens a **chat sheet** (large detent) that stays open while coach responds; structural proposals show inline **Apply change** / **Keep plan** before anything hits the workout plan.
- **ExplainSheet ("show your working")**: takes a number, its contributor breakdown, and an optional citation; presented from a long-press or info affordance on any readout; includes an "Ask coach about this" hand-off. Selection haptic on open.

## 5. Layout and reach

- One-handed, mid-set, often not looking. Reading (score, targets, prev) lives in the top two thirds; action (ask-coach, numpad, primary buttons) in the bottom third.
- Single-scroll screens where possible; the Dashboard resolves the whole day without a tab change.
- Spacing scale: 4, 8, 12, 16, 22, 32. Screen gutter 22. Card gap 12.
- Hit targets never below 44pt (plan minimum).

## 6. Motion

Motion serves reading, then confirmation. It pairs with haptics (`Docs/HAPTICS.md`): the arc sweeps as the reveal taps, the set row settles as completion clicks.

Tokens:
- `quick` 0.18s, ease-out: selection, taps, key presses.
- `standard` 0.28s, ease-in-out: sheet and card transitions, banner in/out.
- `settle` 0.42s spring (response 0.42, damping 0.82): set-row completion, adjustment applied.
- `reveal` 0.9s: the readiness reveal only.

**Readiness reveal** (the signature moment, once per day on first Dashboard appearance):
1. Arc value strokes from 0 to score over `reveal` with ease-out.
2. The `heroNumber` counts up in lockstep (mono tabular, so no width jump).
3. State label and contributors fade+rise in over the final 0.3s.
4. The readiness-reveal haptic swells with the stroke and crests as it lands.

Reduce Motion: every animation collapses to a cross-fade at `quick`; the reveal shows the final arc and number directly with no count-up and no sweep. The haptic still fires (it is a separate channel and a separate setting).

## 7. Accessibility

- Contrast: `fg` on `canvas` and on `surface` exceeds WCAG AA; `fgMuted` is reserved for non-essential captions and units, never for the only copy of critical information.
- State is never encoded by color alone: the state ramp is always paired with a number and, where present, a `monoTag` label.
- Dynamic Type: `HelmType` styles scale; mono numerals stay tabular at every size; test the set row and Dashboard at the largest accessibility size.
- Reduce Motion and haptics-off are independent settings, both honored (sections 6 and `Docs/HAPTICS.md`).

## 8. App icon

Fitness-analysis, not nautical: the Arc reading a value against a scale. **Marque is treatment C (selected): the arc meeting a data trace** — the gauge and the readout line in one mark, warm-black radial field, `hairline` track, `accent` value arc, an `fg` trace polyline across it. Alternate is the accent-field tint (B): `accent` ground, near-black arc, for contexts that need to shout. The same arc-plus-trace scales into the tab icon, Watch complication, and Live Activity glyph. Provide both a dark-field and a light-field rendering of the icon set. Do not hand-author a wheel, helm, or compass.

## 9. Skins and theming

Appearance is driven by two independent environment values so the app can carry more than one look without duplicating logic. Everything in sections 1 through 8 except the container treatment is shared across skins.

- **`HelmTheme`** (palette): `dark` / `light` / `auto`. Defaults to `auto` (follows system appearance), with an explicit override in Settings. Selects the token set in section 1. Cheap: it is a value swap, and every component already reads tokens, never literals.
- **`HelmSkin`** (layout family): which container treatment the shared components render through. Candidates: `dataSheet` (borderless, hairline-ruled), `stateField` (full-bleed state-color hero, flat rows), `blueprint` (drafting grid, graduated dials), `instrument` (the card baseline). **v1 ships `instrument`** (chosen for readability); the rest are reserved behind the seam.

Rule: components do not hard-code their container. They render content through a `SkinnedContainer` (and, where relevant, a `SkinnedGauge`) that reads `HelmSkin` and picks the treatment. A section becomes a Card, a ruled block, a field, or a graticule block by skin, with identical content and tokens underneath. This keeps a future in-app skin switcher (report M0.8) a drop-in rather than a rewrite: adding a skin means implementing its treatments, touching no engine, token, or content code.

Both values are `@Observable` app state, persisted, and exposed through the SwiftUI environment so any view can read them without prop-drilling. The Arc, type scale, motion tokens, and haptics are identical across every skin and theme.
