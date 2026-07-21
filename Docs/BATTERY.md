# Battery measurement method

Battery is a hard constraint on Helm (locked decision), not a vibe check. This doc is the repeatable procedure so "battery is fine" is a measured claim, not an impression. Written at M0.6, before any HealthKit observer, live workout session, or LLM call exists to regress it, so the very first baseline is close to a clean-app floor.

---

## Instruments energy log baseline

Captured once at M0.6 (near-empty app: tab shell, no observers registered yet) and again after every Device Test Gate (DT1 to DT5), so drift is visible gate over gate, not discovered at the end.

**Procedure**:
1. Physical iPhone, unplugged, battery above 50%, background app refresh and other apps left in their normal state (don't artificially quiet the phone; the test should reflect real usage).
2. Xcode → Open Developer Tool → Instruments → **Energy Log** template, attach to the Helm build under test.
3. Run for a fixed 15-minute window doing nothing (phone locked, screen off) to get an idle floor, then a second 15-minute window with the app foregrounded and idle on Dashboard, then (once the relevant feature exists) a 15-minute window exercising the feature under test (e.g. a logged workout for the DT2 baseline, live chat for DT3).
4. Record: average energy impact level (Instruments' Low/Medium/High/Very High banding), CPU time, and any flagged "unusually high" categories (networking, location, GPS is unused so should read zero, background tasks).
5. Save the trace file (`.trace`) alongside the written numbers; don't rely on memory of what the graph looked like.

**Where results go**: append a dated entry to the table below, one row per gate.

| Date | Build / commit | Scenario | Idle energy impact | Active energy impact | Notes |
|---|---|---|---|---|---|
| | | M0.6 baseline (empty shell) | | | |
| | | DT1 (ingest + readiness) | | | |
| | | DT2 (logger, in the gym) | | | |
| | | DT3 (go-live, chat + prescription) | | | |
| | | DT4 (proactivity + Watch, overnight) | | | |
| | | DT5 (nutrition + full regression) | | | |

---

## Repeatable overnight test

Purpose: catch background churn that a 15-minute foreground trace won't show, principally observer re-registration storms, background-delivery misfires, or a Watch complication updating more often than intended.

**Procedure**:
1. Charge to 100%, unplug, note the time.
2. Leave the phone locked overnight (8 hours minimum), Wi-Fi and Bluetooth on as normal, Watch paired and worn or on its charger per the variant being tested (see below).
3. In the morning, check Settings → Battery → Battery usage by app for Helm's overnight percentage, and pull a diagnostics export (per `Docs/DIAGNOSTICS.md`) before doing anything else, so the OSLog extract still covers the overnight window.
4. Grep the OSLog extract for the signpost names in `Docs/DIAGNOSTICS.md`'s catalog that should be silent overnight (`HealthKitObserverFetch`, `BackfillChunk`). Any repeated firing overnight with no corresponding real HealthKit write is churn, not legitimate work, and is a bug to file, not an accepted cost.
5. Repeat with two Watch variants once M8 lands: complication on the active watch face, and complication removed, to isolate the complication's contribution from the base app's.

**Baseline expectation**: overnight battery usage for Helm should be in the same range as a comparable single recovery-tracking app (Whoop/Oura-class), not distinguishable as an outlier in Battery usage by app. There is no fixed percentage target locked yet; the first overnight run at DT1 sets the working baseline, and every later DT gate's overnight run is compared against it, not against an arbitrary number invented here.

| Date | Build / commit | Watch variant | Overnight % (Settings) | Anomalous signpost firing? | Notes |
|---|---|---|---|---|---|
| | | DT1 (no Watch features yet) | | | |
| | | DT4, complication on | | | |
| | | DT4, complication off | | | |
| | | DT5 regression | | | |

---

## Signpost names to grep for observer churn

From `Docs/DIAGNOSTICS.md`'s signpost catalog, the ones relevant to background/overnight battery review:

- `HealthKitObserverFetch`: should fire only when HealthKit actually has new samples to deliver, not on a timer. Repeated firing with empty results overnight indicates a misconfigured `enableBackgroundDelivery` frequency or an observer re-registering itself in a loop.
- `BackfillChunk`: should never fire overnight after the initial onboarding backfill completes. Any recurrence means backfill is re-triggering, which is a bug.
- `WorkoutSessionLifecycle` / `LiveWorkoutBuilderTeardown` (once M8 lands): should only appear during an actual worn workout, never overnight with the Watch idle.

If Instruments' energy log flags a category as unusually high, cross-reference the timestamp against the OSLog extract for the nearest signpost to identify which subsystem caused it, rather than guessing from the category name alone.
