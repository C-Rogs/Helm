# Sleep metrics

Helm sleep duration is meant to match **Apple Health → Browse → Sleep → Time Asleep** for the same wake calendar day.

## Canonical metric

| Surface | Metric | Window |
|---|---|---|
| Dashboard sleep card | Time asleep (`Xh Ym`) | 18:00 previous calendar day → 18:00 wake calendar day |
| Sleep analysis page | Time asleep + stages + recent nights | Same wake-day window; last 14 nights with data |
| ARC sleep contributor | Same time asleep | Same window |
| Coach context `sleep=` | Same time asleep | Same window |
| Recovery detail sleep band | Same time asleep | Same window |

**Time asleep** = merged sum of HealthKit asleep stages (`asleepUnspecified`, `asleepCore`, `asleepDeep`, `asleepREM`) clipped to the wake-day window. Overlapping intervals merge before summing (`SleepAggregation` / `BioharvestHealthKitMath`).

Helm does **not** show decimal hours for sleep duration in the UI. Use `SleepDurationFormatting.hoursAndMinutes(from:)`.

## Secondary metrics

| Metric | Definition |
|---|---|
| WASO / Awake | Merged `awake` stage minutes in the wake-day window |
| Deep / REM | Merged `asleepDeep` / `asleepREM` minutes |
| Sleep efficiency | `timeAsleep / timeInBed` when in-bed samples exist; otherwise `asleep / (asleep + awake)` |

In-bed (`inBed`) intervals are stored for efficiency and diagnostics but are **not** added to time asleep.

## Day attribution

Sleep is attributed to the **calendar wake day** (the day you get up), not the Helm 04:00 nutrition/training `helmDay` cutoff. `helmDay` on each stored interval still reflects sleep **onset** for storage/query; nightly totals always query by overlapping the 18:00–18:00 wake window.

## Diagnostics

Settings → **Sleep diagnostics** dumps raw HealthKit samples for last night beside Helm persisted intervals and `SleepAggregation` totals. Use it when Helm and Health disagree.
