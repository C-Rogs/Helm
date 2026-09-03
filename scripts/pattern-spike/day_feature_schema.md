# DayFeatureRow schema (research spike)

Canonical join key: **calendar `date` as `YYYY-MM-DD`** in Europe/London local day for Apple Health CSV; Helm `helm_day` string is already a logical day (`HelmDay`, 04:00 cutoff).

## Lag rules

| Feature family | Day attribution | Lag note |
|---|---|---|
| Sleep stages / asleep minutes | Wake-day / Helm sleep `helm_day` (onset-based in Helm; CSV preprocess uses local calendar day of segment) | Outcomes "after alcohol night" use **next** morning metrics vs sleep on exposure day |
| Nutrition (kcal, protein, breakfast) | HelmDay of meal / HK dietary day | Same-day contrasts unless noted |
| Alcohol flag | Day of log / HK alcoholic-beverage sample | Sleep outcome: same night; weight: **next** morning; gym: **next** training day |
| ARC / HRV / RHR | Morning-of HelmDay | Predictor for same-day gym |
| Workout / TRIMP / Hevy volume | Session start day | Prior-day TRIMP → next-day nutrition uses lag 1 |
| Day demand (office) | Override / resolved demand on HelmDay | Same-day gym contrast |

## Fields (v1 research matrix)

| Field | Type | Source |
|---|---|---|
| `date` | string | join key |
| `alcohol` | bool / count | meal `source=alcohol` or drink-name heuristic or HK `NumberOfAlcoholicBeverages` |
| `diet_energy_kcal` | float? | `daily_metrics` / HK / `nutrition_day` |
| `diet_protein_g` | float? | same |
| `breakfast_logged` | bool? | any `meal.bucket=breakfast` |
| `sleep_asleep_min` | float? | aggregated sleep stages |
| `sleep_rem_min` | float? | REM only |
| `sleep_efficiency` | float? | asleep / (asleep+awake) when both present |
| `hrv_sdnn` | float? | daily metrics / HK |
| `resting_hr` | float? | daily metrics / HK |
| `arc_score` | float? | `readiness_daily_score` |
| `arc_band` | string? | depleted/balanced/primed |
| `bodymass_kg` | float? | body composition / HK |
| `workout_minutes` | float? | HK workouts / session duration |
| `prior_day_trimp` | float? | daily metrics |
| `day_demand` | string? | nutrition demand override |
| `hard_set_count` | int? | completed working sets |
| `mean_rpe` | float? | set entries |

Spike implementation: `run_spike.py` builds a practical subset from available exports.
