# Helm haptic vocabulary

> Normative spec for the `HapticEngine` in the `DesignSystem` package. Haptics are a language, not decoration. In a gym, used one-handed, mid-set, often without looking, haptics are the primary confirmation channel, not polish. Companion: `Docs/DESIGN-SYSTEM.md` section 6 (motion pairs with haptics). Rendered reference: the vocabulary panel in `Helm Design Proposal.dc.html`.

## Principles

1. **A small vocabulary, grouped.** Twelve patterns in four groups (signature and reading, core loop, milestones and confirmations, guards and texture). Each maps to exactly one class of moment. Twelve is the ceiling, not a target: do not invent per-screen one-offs, and if a new moment appears, map it to an existing pattern before adding a thirteenth.
2. **Meaning is stable.** The same event feels the same everywhere and every time. The set-logged tap in particular must be byte-identical rep to rep so the hand learns to trust it without looking.
3. **Motion and haptic fire together.** The reveal sweeps as it swells; the set row settles as it clicks. Never one without the other for the events that have both.
4. **Spend celebration rarely.** Only a genuine PR gets the celebratory pattern. Everything else is confirmation, not applause.
5. **Always degradable.** CHHapticEngine when available; `UIFeedbackGenerator` fallback otherwise; silent no-op when the device cannot or the user turned it off. Never a crash, never a hard dependency.

## The vocabulary (twelve patterns, four groups)

Values below are Core Haptics `CHHapticEvent` sketches (intensity `i`, sharpness `s`, relative time in seconds). They are the design intent; the build agent tunes exact curves on-device (DT1). Each row also names its `UIFeedbackGenerator` fallback.

**Group 1 — signature and reading**

| Name | Feel | Events (i / s @ t) | Fallback |
|---|---|---|---|
| `readinessReveal` | rising swell resolving on a soft crest | continuous ramp `i 0.2->0.7`, `s 0.2->0.4` over 0.7s, then transient `i 0.9 / s 0.4 @ 0.7` | `.notificationSuccess` |
| `phaseChange` | evenly-spaced firm triple, the plan itself moved | transients `i 0.7 / s 0.5` @ 0, 0.12, 0.24 | `.notificationSuccess` |
| `thresholdInsight` | faintest single swell, ambient | continuous `i 0.15->0.3` over 0.35s | `impact(.soft)` (min intensity) |

**Group 2 — core loop**

| Name | Feel | Events (i / s @ t) | Fallback |
|---|---|---|---|
| `setLogged` | one dry, crisp transient | transient `i 0.8 / s 0.9 @ 0` | `impact(.rigid)` |
| `restCountIn` | three soft rising ticks | transients `i 0.4/0.5/0.6`, `s 0.4` @ 0, 0.3, 0.6 | `impact(.light)` x3 |
| `restDone` | urgent double pulse, felt through a gym | transient `i 1.0 / s 0.8 @ 0`, transient `i 1.0 / s 0.8 @ 0.12` | `.notificationWarning` + notification |

**Group 3 — milestones and confirmations**

| Name | Feel | Events (i / s @ t) | Fallback |
|---|---|---|---|
| `prHit` | short ascending three-tap flourish | transients `i 0.7 / s 0.5 @ 0`, `i 0.85 / s 0.6 @ 0.09`, `i 1.0 / s 0.8 @ 0.18` | `.notificationSuccess` |
| `sessionFinished` | firm transient decaying into a long settle | transient `i 0.9 / s 0.7 @ 0`, continuous `i 0.5->0` over 0.4s | `.notificationSuccess` |
| `mealConfirmed` | one soft rounded bump | transient `i 0.5 / s 0.2 @ 0` | `impact(.soft)` |

**Group 4 — guards and texture**

| Name | Feel | Events (i / s @ t) | Fallback |
|---|---|---|---|
| `coachAdjust` | two gentle bumps | transient `i 0.5 / s 0.3 @ 0`, transient `i 0.5 / s 0.3 @ 0.1` | `impact(.soft)` x2 |
| `clampRejected` | short sharp buzz, felt as resistance | transient `i 1.0 / s 1.0 @ 0`, transient `i 0.7 / s 1.0 @ 0.05` | `.notificationError` |
| `selection` | lightest tick | `UISelectionFeedbackGenerator` (no custom pattern needed) | `.selectionChanged` |

`readinessReveal` is the signature. It is the one haptic Cameron will learn to feel for each morning, so it is the most designed and the most protected: it fires once per day, paired with the reveal motion.

## Where each fires (trigger map)

| Pattern | Trigger | Milestone that wires it |
|---|---|---|
| `readinessReveal` | first Dashboard appearance of the day, with the reveal animation; not on recompute | M2.3 (re-skin of M2.2) |
| `phaseChange` | deload week begins, new mesocycle starts, or phase (cut/maintain/gain) changes | M5.6 / M5.2 |
| `thresholdInsight` | a silent insight surfaces in-app (a trend crossed a threshold); off by default | M7.2 |
| `setLogged` | a set row completes (checkmark), not on an already-complete row | M3.3 |
| `restCountIn` | final few seconds of a running rest timer, in-foreground | M3.4 |
| `restDone` | rest timer reaches zero, including while suspended (via the scheduled notification) | M3.4 |
| `prHit` | a qualifying PR is detected, exactly once per record | M3.5 |
| `sessionFinished` | a workout is finished (not discarded) | M3.2 / M3.3 |
| `mealConfirmed` | a photo-to-macro estimate is confirmed and written to Health | M9.3 |
| `coachAdjust` | an adjustment applies to the active session (swap, reorder, set change); also on the resulting undo | M6.2 |
| `clampRejected` | an adjustment or input hits a safe bound (RPE over cap, a clamp refusing an unsafe swap) | M5.3 / M6.2 |
| `selection` | tab change, segmented control, numpad key, picker selection | M0.7 (tab bar), then per-control |

## Do not

- Do not fire a haptic on scroll, on passive data arrival (background ingest), on a coach *message* (only on a plan *change*), or on navigation that is not a discrete selection.
- Do not stack two patterns in the same moment; if two events coincide, the more meaningful one wins (a set that is also a PR fires `prHit`, not `setLogged` then `prHit`).
- Do not use `restDone` intensity for anything non-urgent; it is deliberately the loudest and must stay rare enough to mean "move".

## Engine contract

`HapticEngine` lives in `DesignSystem` and is the only haptics entry point (no view calls Core Haptics or `UIFeedbackGenerator` directly).

- API surface: `play(_ pattern: HelmHaptic)`, one case per named pattern above.
- Lifecycle: lazily start `CHHapticEngine`, restart on `.stoppedHandler` / `.resetHandler`, respect `CHHapticEngine.capabilitiesForHardware().supportsHaptics`. Never hold the engine running idle.
- Settings: a single "Haptics" toggle (default on) read on every `play`. Independent of Reduce Motion (a user may want haptics with reduced motion, or the reverse).
- Low power: skip continuous patterns (`readinessReveal` swell degrades to its crest transient only) under Low Power Mode.
- Diagnostics: route engine start/stop/reset failures to the Diagnostics ring buffer per `Docs/DIAGNOSTICS.md`; never crash, never phone home.
- AHAP: bundle the custom continuous/multi-event patterns (`readinessReveal`, `phaseChange`, `restDone`, `restCountIn`, `prHit`, `sessionFinished`, `clampRejected`, `thresholdInsight`) as `.ahap` resources loaded by name; `setLogged`, `coachAdjust`, `mealConfirmed`, and `selection` may be code-built.

## Verification split

- **Agent-verifiable**: the engine compiles; each `HelmHaptic` case resolves to a pattern or fallback; `play` no-ops safely with no haptic hardware (unit-tested behind the capability abstraction); the settings toggle and Low Power path are honored; failures reach the ring buffer, never a crash.
- **Device gate (DT1)**: each pattern *feels* correct on a real iPhone; `readinessReveal` reads as the signature moment and fires once per day; `restDone` is felt with the phone pocketed. Added to the DT1 checklist.
- **Device gate (DT2)**: `restDone` fires while the app is suspended via the scheduled notification, not only in-foreground.
