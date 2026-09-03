#!/usr/bin/env python3
"""Pattern-detection research spike for Signal/Helm.

Builds a day matrix from Apple Health preprocess CSV + Helm sqlite exports,
runs catalog contrasts, label-shuffle nulls, analogous-day neighbors,
and a propose-then-test simulation (fixed proposer, no live LLM).

Usage:
  python3 scripts/pattern-spike/run_spike.py
"""

from __future__ import annotations

import csv
import json
import math
import random
import sqlite3
import statistics
from dataclasses import asdict, dataclass
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Callable, Iterable

ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / "Docs" / "Research"
OUT_JSON = OUT_DIR / "pattern-spike-results.json"

AH_CSV = Path.home() / "Downloads" / "apple_health_export 2" / "apple_health_out" / "daily_features.csv"
HELM_DB = Path.home() / "Downloads" / "helm-2026-08-24T18-35-50Z.sqlite"
HELM_DB_NUTRI = Path.home() / "Downloads" / "helm-2026-08-04T14-25-49Z.sqlite"
HEVY_CSV = Path.home() / "Downloads" / "HevyExport 4.csv"

MIN_N_ARM = 12
MIN_EFFECT_ABS = 0.15  # Cliff's delta threshold for "ship" language
FDR_Q = 0.10
SHUFFLE_N = 500
RNG = random.Random(42)


@dataclass
class DayRow:
    date: str
    diet_energy_kcal: float | None = None
    diet_protein_g: float | None = None
    breakfast_logged: bool | None = None
    alcohol: bool = False
    alcohol_count: float = 0.0
    sleep_asleep_min: float | None = None
    sleep_rem_min: float | None = None
    sleep_awake_min: float | None = None
    hrv_sdnn: float | None = None
    resting_hr: float | None = None
    bodymass_kg: float | None = None
    workout_minutes: float | None = None
    workouts_count: float | None = None
    prior_day_trimp: float | None = None
    arc_score: float | None = None
    arc_band: str | None = None
    hard_set_count: float | None = None
    mean_rpe: float | None = None
    day_demand: str | None = None
    hevy_volume: float | None = None  # sum weight*reps


@dataclass
class ContrastResult:
    id: str
    hypothesis: str
    exposure: str
    outcome: str
    lag_days: int
    n_exposure: int
    n_control: int
    median_exposure: float | None
    median_control: float | None
    median_delta: float | None
    cliffs_delta: float | None
    p_mannwhitney: float | None
    shuffle_p: float | None
    fdr_q: float | None
    verdict: str
    notes: str
    source: str


def fnum(x) -> float | None:
    if x is None or x == "":
        return None
    try:
        return float(x)
    except (TypeError, ValueError):
        return None


def parse_day(s: str) -> date:
    return date.fromisoformat(s[:10])


def add_days(d: str, n: int) -> str:
    return (parse_day(d) + timedelta(days=n)).isoformat()


def cliffs_delta(a: list[float], b: list[float]) -> float | None:
    if not a or not b:
        return None
    gt = lt = 0
    for x in a:
        for y in b:
            if x > y:
                gt += 1
            elif x < y:
                lt += 1
    return (gt - lt) / (len(a) * len(b))


def mann_whitney_u_p(a: list[float], b: list[float]) -> float | None:
    """Two-sided MW U via normal approx with tie correction. Adequate for spike."""
    if len(a) < 3 or len(b) < 3:
        return None
    n1, n2 = len(a), len(b)
    combined = [(v, 0) for v in a] + [(v, 1) for v in b]
    combined.sort(key=lambda t: t[0])
    ranks = [0.0] * len(combined)
    i = 0
    while i < len(combined):
        j = i
        while j + 1 < len(combined) and combined[j + 1][0] == combined[i][0]:
            j += 1
        avg = (i + j + 2) / 2.0  # 1-based ranks
        for k in range(i, j + 1):
            ranks[k] = avg
        i = j + 1
    r1 = sum(ranks[i] for i, (_, g) in enumerate(combined) if g == 0)
    u1 = r1 - n1 * (n1 + 1) / 2.0
    mu = n1 * n2 / 2.0
    # tie correction
    tie_term = 0.0
    i = 0
    vals = [v for v, _ in combined]
    while i < len(vals):
        j = i
        while j + 1 < len(vals) and vals[j + 1] == vals[i]:
            j += 1
        t = j - i + 1
        if t > 1:
            tie_term += t * (t * t - 1)
        i = j + 1
    n = n1 + n2
    sigma2 = (n1 * n2 / 12.0) * ((n + 1) - tie_term / (n * (n - 1))) if n > 1 else 0.0
    if sigma2 <= 0:
        return None
    z = (u1 - mu) / math.sqrt(sigma2)
    # two-sided from normal CDF
    p = 2.0 * (1.0 - 0.5 * (1.0 + math.erf(abs(z) / math.sqrt(2))))
    return min(1.0, max(0.0, p))


def bh_fdr(pvals: list[float | None]) -> list[float | None]:
    indexed = [(i, p) for i, p in enumerate(pvals) if p is not None]
    m = len(indexed)
    out: list[float | None] = [None] * len(pvals)
    if m == 0:
        return out
    indexed.sort(key=lambda t: t[1])
    prev = 1.0
    ranked: list[tuple[int, float]] = []
    for rank, (i, p) in enumerate(reversed(indexed), start=1):
        q = min(prev, p * m / (m - rank + 1))
        prev = q
        ranked.append((i, q))
    for i, q in ranked:
        out[i] = q
    return out


def load_apple_health(path: Path) -> dict[str, DayRow]:
    rows: dict[str, DayRow] = {}
    if not path.exists():
        return rows
    with path.open() as f:
        for r in csv.DictReader(f):
            d = r["date"]
            kcal = fnum(r.get("diet_energy_kcal"))
            protein = fnum(r.get("diet_protein_g"))
            # Treat exact zeros as missing (preprocess pads empty diet days with 0).
            if kcal is not None and kcal <= 0:
                kcal = None
            if protein is not None and protein <= 0:
                protein = None
            sleep = fnum(r.get("sleep_asleep_min"))
            if sleep is not None and sleep <= 0:
                sleep = None
            rows[d] = DayRow(
                date=d,
                diet_energy_kcal=kcal,
                diet_protein_g=protein,
                sleep_asleep_min=sleep,
                sleep_rem_min=fnum(r.get("sleep_rem_min")),
                sleep_awake_min=fnum(r.get("sleep_awake_min")),
                hrv_sdnn=fnum(r.get("hrv_sdnn")),
                resting_hr=fnum(r.get("resting_hr")),
                bodymass_kg=fnum(r.get("bodymass_kg")),
                workout_minutes=fnum(r.get("workout_minutes")),
                workouts_count=fnum(r.get("workouts_count")),
            )
    return rows


def merge_helm(db_path: Path, rows: dict[str, DayRow]) -> None:
    if not db_path.exists():
        return
    con = sqlite3.connect(db_path)
    con.row_factory = sqlite3.Row
    cur = con.cursor()

    for r in cur.execute("SELECT * FROM daily_metrics"):
        d = r["helm_day"]
        row = rows.setdefault(d, DayRow(date=d))
        if r["dietary_energy_kcal"] is not None and r["dietary_energy_kcal"] > 0:
            row.diet_energy_kcal = r["dietary_energy_kcal"]
        if r["dietary_protein_grams"] is not None and r["dietary_protein_grams"] > 0:
            row.diet_protein_g = r["dietary_protein_grams"]
        if r["hrv_sdnn_ms"] is not None:
            row.hrv_sdnn = float(r["hrv_sdnn_ms"])
        if r["resting_heart_rate"] is not None:
            row.resting_hr = float(r["resting_heart_rate"])
        if r["prior_day_trimp"] is not None:
            row.prior_day_trimp = r["prior_day_trimp"]

    # sleep aggregates per helm_day
    sleep_sql = """
      SELECT helm_day, stage,
             SUM((julianday(end_at) - julianday(start_at)) * 24.0 * 60.0) AS mins
      FROM sleep_record
      GROUP BY helm_day, stage
    """
    sleep: dict[str, dict[str, float]] = {}
    for r in cur.execute(sleep_sql):
        sleep.setdefault(r["helm_day"], {})[r["stage"]] = r["mins"] or 0.0
    for d, stages in sleep.items():
        row = rows.setdefault(d, DayRow(date=d))
        asleep = sum(
            stages.get(s, 0.0)
            for s in ("asleepCore", "asleepDeep", "asleepREM", "asleepUnspecified")
        )
        if asleep > 0:
            row.sleep_asleep_min = asleep
        if "asleepREM" in stages:
            row.sleep_rem_min = stages["asleepREM"]
        if "awake" in stages:
            row.sleep_awake_min = stages["awake"]

    for r in cur.execute("SELECT helm_day, mass_kg FROM body_composition WHERE mass_kg IS NOT NULL"):
        row = rows.setdefault(r["helm_day"], DayRow(date=r["helm_day"]))
        row.bodymass_kg = r["mass_kg"]

    for r in cur.execute("SELECT helm_day, score_json FROM readiness_daily_score"):
        row = rows.setdefault(r["helm_day"], DayRow(date=r["helm_day"]))
        try:
            payload = json.loads(r["score_json"])
            row.arc_score = fnum(payload.get("score"))
            row.arc_band = payload.get("band")
        except json.JSONDecodeError:
            pass

    # workout duration + sets if present
    try:
        for r in cur.execute(
            """
            SELECT date(started_at) AS d,
                   SUM((julianday(COALESCE(ended_at, started_at)) - julianday(started_at)) * 24 * 60) AS mins,
                   COUNT(*) AS c
            FROM workout_session
            WHERE deleted_at IS NULL OR deleted_at = ''
            GROUP BY 1
            """
        ):
            if not r["d"]:
                continue
            row = rows.setdefault(r["d"], DayRow(date=r["d"]))
            if r["mins"]:
                row.workout_minutes = r["mins"]
            row.workouts_count = float(r["c"] or 0)
    except sqlite3.OperationalError:
        pass

    con.close()


def merge_nutrition_meals(db_path: Path, rows: dict[str, DayRow]) -> dict:
    """Breakfast + crude alcohol name heuristic + nutrition_day macros."""
    stats = {
        "breakfast_days": 0,
        "alcohol_name_days": 0,
        "alcohol_source_days": 0,
        "meal_days": 0,
        "nutrition_day_rows": 0,
    }
    if not db_path.exists():
        return stats
    con = sqlite3.connect(db_path)
    cur = con.cursor()
    drink_pat = (
        "%vodka%",
        "%beer%",
        "%wine%",
        "%whisky%",
        "%whiskey%",
        "%lager%",
        "%cider%",
        "%prosecco%",
        "%guinness%",
        "%aperol%",
        "%tequila%",
        "%gin %",
        "% rum%",
    )
    breakfast_days = set()
    alcohol_days = set()
    meal_days = set()
    for (d,) in cur.execute("SELECT DISTINCT helm_day FROM meal"):
        meal_days.add(d)
    for (d,) in cur.execute("SELECT DISTINCT helm_day FROM meal WHERE bucket='breakfast'"):
        breakfast_days.add(d)
        row = rows.setdefault(d, DayRow(date=d))
        row.breakfast_logged = True
    for (d,) in cur.execute("SELECT DISTINCT helm_day FROM meal WHERE source='alcohol'"):
        alcohol_days.add(d)
    # name heuristic
    clauses = " OR ".join(["lower(name) LIKE ?" for _ in drink_pat])
    for (d,) in cur.execute(f"SELECT DISTINCT helm_day FROM meal WHERE {clauses}", drink_pat):
        alcohol_days.add(d)
    for d in alcohol_days:
        row = rows.setdefault(d, DayRow(date=d))
        row.alcohol = True
        row.alcohol_count = max(row.alcohol_count, 1.0)
    # mark explicit non-breakfast days among meal days as False when we have meal coverage
    for d in meal_days:
        row = rows.setdefault(d, DayRow(date=d))
        if row.breakfast_logged is None:
            row.breakfast_logged = d in breakfast_days
    # Prefer Helm nutrition_day totals when present (fixes null daily_metrics diet fields).
    nutri_n = 0
    for r in cur.execute(
        """
        SELECT helm_day, total_energy_kcal, total_protein_grams
        FROM nutrition_day
        WHERE total_energy_kcal IS NOT NULL OR total_protein_grams IS NOT NULL
        """
    ):
        nutri_n += 1
        row = rows.setdefault(r[0], DayRow(date=r[0]))
        if r[1] is not None and r[1] > 0:
            row.diet_energy_kcal = r[1]
        if r[2] is not None and r[2] > 0:
            row.diet_protein_g = r[2]
    stats["breakfast_days"] = len(breakfast_days)
    stats["alcohol_name_days"] = len(alcohol_days)
    stats["alcohol_source_days"] = cur.execute(
        "SELECT COUNT(DISTINCT helm_day) FROM meal WHERE source='alcohol'"
    ).fetchone()[0]
    stats["meal_days"] = len(meal_days)
    stats["nutrition_day_rows"] = nutri_n
    con.close()
    return stats


def merge_hevy(path: Path, rows: dict[str, DayRow]) -> int:
    if not path.exists():
        return 0
    # Hevy: "31 May 2026, 17:53"
    vol: dict[str, float] = {}
    with path.open() as f:
        for r in csv.DictReader(f):
            start = r.get("start_time") or ""
            try:
                dt = datetime.strptime(start.split(",")[0].strip(), "%d %b %Y")
            except ValueError:
                continue
            d = dt.date().isoformat()
            w = fnum(r.get("weight_kg")) or 0.0
            reps = fnum(r.get("reps")) or 0.0
            vol[d] = vol.get(d, 0.0) + w * reps
    for d, v in vol.items():
        row = rows.setdefault(d, DayRow(date=d))
        row.hevy_volume = v
        row.workouts_count = max(row.workouts_count or 0.0, 1.0)
    return len(vol)


def outcome_values(
    rows: dict[str, DayRow],
    exposure_days: Iterable[str],
    outcome_fn: Callable[[DayRow], float | None],
    lag: int,
) -> list[float]:
    out = []
    for d in exposure_days:
        target = add_days(d, lag)
        row = rows.get(target)
        if not row:
            continue
        v = outcome_fn(row)
        if v is not None and not math.isnan(v):
            out.append(v)
    return out


def contrast(
    rows: dict[str, DayRow],
    *,
    hid: str,
    hypothesis: str,
    exposure_days: set[str],
    control_days: set[str],
    outcome_fn: Callable[[DayRow], float | None],
    lag: int,
    exposure: str,
    outcome: str,
    source: str,
    notes: str = "",
) -> ContrastResult:
    a = outcome_values(rows, exposure_days, outcome_fn, lag)
    b = outcome_values(rows, control_days, outcome_fn, lag)
    med_a = statistics.median(a) if a else None
    med_b = statistics.median(b) if b else None
    delta = (med_a - med_b) if med_a is not None and med_b is not None else None
    cd = cliffs_delta(a, b)
    p = mann_whitney_u_p(a, b)

    shuffle_p = None
    if len(a) >= 5 and len(b) >= 5 and delta is not None:
        pool_days = list(exposure_days | control_days)
        obs = abs(delta)
        hits = 0
        for _ in range(SHUFFLE_N):
            RNG.shuffle(pool_days)
            n_exp = len(exposure_days)
            sh_exp = set(pool_days[:n_exp])
            sh_ctrl = set(pool_days[n_exp:])
            sa = outcome_values(rows, sh_exp, outcome_fn, lag)
            sb = outcome_values(rows, sh_ctrl, outcome_fn, lag)
            if not sa or not sb:
                continue
            sd = abs(statistics.median(sa) - statistics.median(sb))
            if sd >= obs - 1e-12:
                hits += 1
        shuffle_p = hits / SHUFFLE_N

    return ContrastResult(
        id=hid,
        hypothesis=hypothesis,
        exposure=exposure,
        outcome=outcome,
        lag_days=lag,
        n_exposure=len(a),
        n_control=len(b),
        median_exposure=med_a,
        median_control=med_b,
        median_delta=delta,
        cliffs_delta=cd,
        p_mannwhitney=p,
        shuffle_p=shuffle_p,
        fdr_q=None,
        verdict="pending",
        notes=notes,
        source=source,
    )


def assign_verdicts(results: list[ContrastResult]) -> None:
    pvals = [r.shuffle_p if r.shuffle_p is not None else r.p_mannwhitney for r in results]
    qs = bh_fdr(pvals)
    for r, q in zip(results, qs):
        r.fdr_q = q
        if r.n_exposure < MIN_N_ARM or r.n_control < MIN_N_ARM:
            r.verdict = "kill_sample"
            r.notes = (r.notes + " ").strip() + f"Need ≥{MIN_N_ARM}/arm."
            continue
        cd = abs(r.cliffs_delta) if r.cliffs_delta is not None else 0.0
        sig = (q is not None and q <= FDR_Q) or (
            r.shuffle_p is not None and r.shuffle_p <= 0.05
        )
        if sig and cd >= MIN_EFFECT_ABS:
            r.verdict = "ship"
        elif sig and cd >= 0.08:
            r.verdict = "soft"
        elif r.n_exposure >= MIN_N_ARM and not sig:
            r.verdict = "kill_null"
            r.notes = (r.notes + " ").strip() + "Survived N but not FDR/shuffle."
        else:
            r.verdict = "soft"


def analogous_days(rows: dict[str, DayRow], query_mask: Callable[[DayRow], bool], k: int = 5):
    feature_keys = [
        "diet_energy_kcal",
        "diet_protein_g",
        "sleep_asleep_min",
        "hrv_sdnn",
        "resting_hr",
        "workout_minutes",
    ]

    def vec(row: DayRow) -> list[float | None]:
        return [getattr(row, f) for f in feature_keys]

    # z-score params over complete-ish rows
    cols = {f: [] for f in feature_keys}
    for row in rows.values():
        v = vec(row)
        if sum(x is not None for x in v) < 4:
            continue
        for f, x in zip(feature_keys, v):
            if x is not None:
                cols[f].append(x)
    mu = {f: statistics.mean(vs) if vs else 0.0 for f, vs in cols.items()}
    sd = {
        f: statistics.pstdev(vs) if len(vs) > 1 else 1.0 for f, vs in cols.items()
    }

    def zvec(row: DayRow) -> list[float]:
        out = []
        for f in feature_keys:
            x = getattr(row, f)
            if x is None or sd[f] == 0:
                out.append(0.0)
            else:
                out.append((x - mu[f]) / sd[f])
        return out

    queries = [r for r in rows.values() if query_mask(r)]
    pool = [r for r in rows.values() if sum(x is not None for x in vec(r)) >= 4]
    examples = []
    for q in queries[:8]:
        qv = zvec(q)
        scored = []
        for p in pool:
            if p.date == q.date:
                continue
            pv = zvec(p)
            dist = math.sqrt(sum((a - b) ** 2 for a, b in zip(qv, pv)))
            scored.append((dist, p))
        scored.sort(key=lambda t: t[0])
        neighbors = [
            {
                "date": n.date,
                "dist": round(dist, 3),
                "diet_energy_kcal": n.diet_energy_kcal,
                "diet_protein_g": n.diet_protein_g,
                "sleep_asleep_min": n.sleep_asleep_min,
                "hrv_sdnn": n.hrv_sdnn,
                "workout_minutes": n.workout_minutes,
            }
            for dist, n in scored[:k]
        ]
        examples.append({"query": q.date, "neighbors": neighbors})
    return {
        "feature_keys": feature_keys,
        "query_count": len(queries),
        "examples": examples,
    }


def propose_then_test_simulation(catalog_ids: set[str], all_results: list[ContrastResult]):
    """Fixed proposer: catalog + distractors. Precision = share of proposals that ship/soft."""
    proposals = [
        "alcohol_lower_kcal",
        "alcohol_worse_sleep",
        "alcohol_next_weight_down",
        "breakfast_lower_protein",
        "low_sleep_higher_rhr",
        "workout_day_more_sleep",  # distractor direction often wrong
        "high_kcal_next_weight_up",
        "low_hrv_fewer_workout_min",
        "high_protein_more_workouts",  # distractor
        "prior_workout_lower_protein",
        "moon_phase_hrv",  # impossible distractor not in results
        "office_better_gym",
    ]
    by_id = {r.id: r for r in all_results}
    evaluated = []
    for pid in proposals:
        r = by_id.get(pid)
        if r is None:
            evaluated.append(
                {
                    "id": pid,
                    "status": "untestable_or_missing",
                    "in_catalog": pid in catalog_ids,
                }
            )
            continue
        evaluated.append(
            {
                "id": pid,
                "status": r.verdict,
                "in_catalog": pid in catalog_ids,
                "n_exposure": r.n_exposure,
                "n_control": r.n_control,
                "cliffs_delta": r.cliffs_delta,
                "shuffle_p": r.shuffle_p,
            }
        )
    testable = [e for e in evaluated if e["status"] not in ("untestable_or_missing", "kill_sample")]
    positives = [e for e in testable if e["status"] in ("ship", "soft")]
    return {
        "proposals": proposals,
        "evaluated": evaluated,
        "precision_among_testable": (len(positives) / len(testable)) if testable else None,
        "note": "Simulated proposer (no live Gemini). Real coach loop would emit constrained JSON only.",
    }


def coverage(rows: dict[str, DayRow]) -> dict:
    def rate(fn):
        vals = [fn(r) for r in rows.values()]
        n = sum(1 for v in vals if v is not None and v is not False)
        if fn.__name__ == "<lambda>":
            pass
        return n

    n = len(rows)
    return {
        "days": n,
        "date_min": min(rows) if rows else None,
        "date_max": max(rows) if rows else None,
        "diet_energy": sum(1 for r in rows.values() if r.diet_energy_kcal is not None),
        "diet_protein": sum(1 for r in rows.values() if r.diet_protein_g is not None),
        "sleep": sum(1 for r in rows.values() if r.sleep_asleep_min is not None),
        "hrv": sum(1 for r in rows.values() if r.hrv_sdnn is not None),
        "rhr": sum(1 for r in rows.values() if r.resting_hr is not None),
        "weight": sum(1 for r in rows.values() if r.bodymass_kg is not None),
        "workout_min": sum(1 for r in rows.values() if r.workout_minutes is not None),
        "alcohol_days": sum(1 for r in rows.values() if r.alcohol),
        "breakfast_true": sum(1 for r in rows.values() if r.breakfast_logged is True),
        "breakfast_false": sum(1 for r in rows.values() if r.breakfast_logged is False),
        "arc": sum(1 for r in rows.values() if r.arc_score is not None),
        "hevy_days": sum(1 for r in rows.values() if r.hevy_volume is not None),
        "office_days": sum(1 for r in rows.values() if r.day_demand == "office"),
    }


def main() -> None:
    rows = load_apple_health(AH_CSV)
    merge_helm(HELM_DB, rows)
    nutri_stats = merge_nutrition_meals(HELM_DB_NUTRI, rows)
    hevy_days = merge_hevy(HEVY_CSV, rows)

    # also try alcohol/breakfast from primary helm db
    nutri_stats_primary = merge_nutrition_meals(HELM_DB, rows)

    all_days = sorted(rows)
    alcohol_days = {d for d, r in rows.items() if r.alcohol}
    non_alcohol = {d for d in all_days if d not in alcohol_days}

    breakfast_days = {d for d, r in rows.items() if r.breakfast_logged is True}
    no_breakfast = {d for d, r in rows.items() if r.breakfast_logged is False}

    # sleep tertiles among days with sleep
    sleep_vals = [(d, r.sleep_asleep_min) for d, r in rows.items() if r.sleep_asleep_min]
    sleep_vals.sort(key=lambda t: t[1])
    low_sleep = set()
    high_sleep = set()
    if len(sleep_vals) >= 30:
        t = max(1, len(sleep_vals) // 3)
        low_sleep = {d for d, _ in sleep_vals[:t]}
        high_sleep = {d for d, _ in sleep_vals[-t:]}

    workout_days = {
        d
        for d, r in rows.items()
        if (r.workouts_count or 0) > 0 or (r.workout_minutes or 0) > 20 or (r.hevy_volume or 0) > 0
    }
    rest_days = {d for d in all_days if d not in workout_days}

    # kcal tertiles
    kcal_vals = [(d, r.diet_energy_kcal) for d, r in rows.items() if r.diet_energy_kcal]
    kcal_vals.sort(key=lambda t: t[1])
    high_kcal = set()
    low_kcal = set()
    if len(kcal_vals) >= 30:
        t = max(1, len(kcal_vals) // 3)
        low_kcal = {d for d, _ in kcal_vals[:t]}
        high_kcal = {d for d, _ in kcal_vals[-t:]}

    hrv_vals = [(d, r.hrv_sdnn) for d, r in rows.items() if r.hrv_sdnn]
    hrv_vals.sort(key=lambda t: t[1])
    low_hrv = set()
    high_hrv = set()
    if len(hrv_vals) >= 30:
        t = max(1, len(hrv_vals) // 3)
        low_hrv = {d for d, _ in hrv_vals[:t]}
        high_hrv = {d for d, _ in hrv_vals[-t:]}

    protein_vals = [(d, r.diet_protein_g) for d, r in rows.items() if r.diet_protein_g]
    protein_vals.sort(key=lambda t: t[1])
    high_protein = set()
    low_protein = set()
    if len(protein_vals) >= 30:
        t = max(1, len(protein_vals) // 3)
        low_protein = {d for d, _ in protein_vals[:t]}
        high_protein = {d for d, _ in protein_vals[-t:]}

    results: list[ContrastResult] = []

    results.append(
        contrast(
            rows,
            hid="alcohol_lower_kcal",
            hypothesis="Alcohol day → lower total dietary kcal",
            exposure_days=alcohol_days,
            control_days=non_alcohol,
            outcome_fn=lambda r: r.diet_energy_kcal,
            lag=0,
            exposure="alcohol",
            outcome="diet_energy_kcal",
            source="helm_meal_heuristic",
            notes="Alcohol labeling sparse historically.",
        )
    )
    results.append(
        contrast(
            rows,
            hid="alcohol_worse_sleep",
            hypothesis="Alcohol day → less REM / asleep",
            exposure_days=alcohol_days,
            control_days=non_alcohol,
            outcome_fn=lambda r: r.sleep_rem_min if r.sleep_rem_min is not None else r.sleep_asleep_min,
            lag=0,
            exposure="alcohol",
            outcome="sleep_rem_or_asleep",
            source="helm_meal_heuristic",
        )
    )
    results.append(
        contrast(
            rows,
            hid="alcohol_next_weight_down",
            hypothesis="Alcohol day → lower next-morning weight",
            exposure_days=alcohol_days,
            control_days=non_alcohol,
            outcome_fn=lambda r: r.bodymass_kg,
            lag=1,
            exposure="alcohol",
            outcome="bodymass_kg",
            source="helm_meal_heuristic",
        )
    )
    results.append(
        contrast(
            rows,
            hid="breakfast_lower_protein",
            hypothesis="Breakfast logged → lower day protein",
            exposure_days=breakfast_days,
            control_days=no_breakfast,
            outcome_fn=lambda r: r.diet_protein_g,
            lag=0,
            exposure="breakfast_logged",
            outcome="diet_protein_g",
            source="helm_meal_bucket",
        )
    )
    results.append(
        contrast(
            rows,
            hid="low_sleep_higher_rhr",
            hypothesis="Low-sleep tertile → higher next-day resting HR",
            exposure_days=low_sleep,
            control_days=high_sleep,
            outcome_fn=lambda r: r.resting_hr,
            lag=1,
            exposure="low_sleep_tertile",
            outcome="resting_hr",
            source="ah_plus_helm",
        )
    )
    results.append(
        contrast(
            rows,
            hid="low_sleep_lower_hrv",
            hypothesis="Low-sleep tertile → lower next-day HRV",
            exposure_days=low_sleep,
            control_days=high_sleep,
            outcome_fn=lambda r: r.hrv_sdnn,
            lag=1,
            exposure="low_sleep_tertile",
            outcome="hrv_sdnn",
            source="ah_plus_helm",
        )
    )
    results.append(
        contrast(
            rows,
            hid="workout_day_more_sleep",
            hypothesis="Workout day → more sleep that night (often false)",
            exposure_days=workout_days,
            control_days=rest_days,
            outcome_fn=lambda r: r.sleep_asleep_min,
            lag=0,
            exposure="workout_day",
            outcome="sleep_asleep_min",
            source="ah_plus_helm_hevy",
        )
    )
    results.append(
        contrast(
            rows,
            hid="high_kcal_next_weight_up",
            hypothesis="High-kcal tertile → higher next-morning weight",
            exposure_days=high_kcal,
            control_days=low_kcal,
            outcome_fn=lambda r: r.bodymass_kg,
            lag=1,
            exposure="high_kcal_tertile",
            outcome="bodymass_kg",
            source="ah_plus_helm",
        )
    )
    results.append(
        contrast(
            rows,
            hid="low_hrv_fewer_workout_min",
            hypothesis="Low-HRV tertile → fewer same-day workout minutes",
            exposure_days=low_hrv,
            control_days=high_hrv,
            outcome_fn=lambda r: r.workout_minutes,
            lag=0,
            exposure="low_hrv_tertile",
            outcome="workout_minutes",
            source="ah_plus_helm",
            notes="Confounded if readiness gating already cuts sessions.",
        )
    )
    results.append(
        contrast(
            rows,
            hid="prior_workout_lower_protein",
            hypothesis="Prior-day workout → lower next-day protein",
            exposure_days=workout_days,
            control_days=rest_days,
            outcome_fn=lambda r: r.diet_protein_g,
            lag=1,
            exposure="prior_workout",
            outcome="diet_protein_g",
            source="ah_plus_helm",
        )
    )
    results.append(
        contrast(
            rows,
            hid="high_protein_more_workouts",
            hypothesis="High-protein tertile → more workout minutes (distractor)",
            exposure_days=high_protein,
            control_days=low_protein,
            outcome_fn=lambda r: r.workout_minutes,
            lag=0,
            exposure="high_protein_tertile",
            outcome="workout_minutes",
            source="ah_plus_helm",
        )
    )
    results.append(
        contrast(
            rows,
            hid="office_better_gym",
            hypothesis="Office demand → higher Hevy volume",
            exposure_days={d for d, r in rows.items() if r.day_demand == "office"},
            control_days={d for d, r in rows.items() if r.day_demand and r.day_demand != "office"},
            outcome_fn=lambda r: r.hevy_volume,
            lag=0,
            exposure="office",
            outcome="hevy_volume",
            source="demand_override",
            notes="No office demand overrides in export.",
        )
    )

    # ARC band contrast if enough
    depleted = {d for d, r in rows.items() if r.arc_band == "depleted"}
    primed = {d for d, r in rows.items() if r.arc_band in ("balanced", "primed")}
    results.append(
        contrast(
            rows,
            hid="arc_depleted_less_volume",
            hypothesis="ARC depleted → lower same-day Hevy volume",
            exposure_days=depleted,
            control_days=primed,
            outcome_fn=lambda r: r.hevy_volume if r.hevy_volume is not None else r.workout_minutes,
            lag=0,
            exposure="arc_depleted",
            outcome="volume_or_minutes",
            source="helm_readiness",
            notes="Tautology risk vs readiness gating.",
        )
    )

    assign_verdicts(results)

    # Analogous days: high-kcal days as stand-in for "social/alcohol-like"
    analog = analogous_days(
        rows,
        lambda r: (r.diet_energy_kcal or 0) > 0
        and r.diet_energy_kcal is not None
        and r.date in high_kcal,
    )

    catalog_ids = {
        "alcohol_lower_kcal",
        "alcohol_worse_sleep",
        "alcohol_next_weight_down",
        "breakfast_lower_protein",
        "low_sleep_higher_rhr",
        "low_sleep_lower_hrv",
        "high_kcal_next_weight_up",
        "low_hrv_fewer_workout_min",
        "prior_workout_lower_protein",
        "office_better_gym",
        "arc_depleted_less_volume",
    }
    ptt = propose_then_test_simulation(catalog_ids, results)

    payload = {
        "generated_at": datetime.now().astimezone().isoformat(),
        "inputs": {
            "apple_health_csv": str(AH_CSV),
            "helm_db": str(HELM_DB),
            "helm_nutrition_db": str(HELM_DB_NUTRI),
            "hevy_csv": str(HEVY_CSV),
            "hevy_days": hevy_days,
            "nutrition_stats": nutri_stats,
            "nutrition_stats_primary_db": nutri_stats_primary,
        },
        "coverage": coverage(rows),
        "gates": {
            "min_n_arm": MIN_N_ARM,
            "min_cliffs_delta_ship": MIN_EFFECT_ABS,
            "fdr_q": FDR_Q,
            "shuffle_n": SHUFFLE_N,
        },
        "contrasts": [asdict(r) for r in results],
        "analogous_days": analog,
        "propose_then_test": ptt,
        "data_gaps": {
            "alcohol_source_days": nutri_stats.get("alcohol_source_days", 0)
            + nutri_stats_primary.get("alcohol_source_days", 0),
            "alcohol_name_days": coverage(rows)["alcohol_days"],
            "breakfast_days": coverage(rows)["breakfast_true"],
            "office_days": coverage(rows)["office_days"],
            "arc_days": coverage(rows)["arc"],
            "hk_alcoholic_beverages": "absent from Jun 2025 Apple Health export types",
        },
    }

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    OUT_JSON.write_text(json.dumps(payload, indent=2, default=str))
    print(f"Wrote {OUT_JSON}")
    print("Coverage:", json.dumps(payload["coverage"], indent=2))
    print("Verdicts:")
    for r in results:
        print(
            f"  {r.verdict:12} {r.id:28} n={r.n_exposure}/{r.n_control} "
            f"d={r.cliffs_delta} shuffle_p={r.shuffle_p} q={r.fdr_q}"
        )


if __name__ == "__main__":
    main()
