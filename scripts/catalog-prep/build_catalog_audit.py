#!/usr/bin/env python3
"""Build a review CSV proposing keep/merge/hide/rename/add_new actions for the Helm exercise catalogue.

Inputs (repo-relative):
  scripts/catalog-prep/cameron_used_exercises.json
  scripts/catalog-prep/hevy_style_staples.json
  Helm/Resources/ExerciseSeed/free-exercise-db.json
  Helm/Resources/ExerciseSeed/exercises.json
  Helm/Resources/ExerciseSeed/coach_archetype_catalog.json

Output:
  scripts/catalog-prep/catalog_audit.csv          one row per catalogue entry + unmatched used title
  scripts/catalog-prep/catalog_audit_summary.md   counts per proposed action
"""

import csv
import json
import re
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PREP = ROOT / "scripts" / "catalog-prep"
SEED_DIR = ROOT / "Helm" / "Resources" / "ExerciseSeed"

USED_PATH = PREP / "cameron_used_exercises.json"
STAPLES_PATH = PREP / "hevy_style_staples.json"
DB_PATH = SEED_DIR / "free-exercise-db.json"
OVERLAY_PATH = SEED_DIR / "exercises.json"
ARCH_PATH = SEED_DIR / "coach_archetype_catalog.csv" if False else SEED_DIR / "coach_archetype_catalog.json"

AUDIT_CSV = PREP / "catalog_audit.csv"
SUMMARY_MD = PREP / "catalog_audit_summary.md"

EQUIPMENT_TOKENS = {
    "machine": "machine",
    "cable": "cable",
    "dumbbell": "dumbbell",
    "db": "dumbbell",
    "barbell": "barbell",
    "bb": "barbell",
    "rope": "cable",
    "smith": "smith",
    "band": "band",
    "kettlebell": "kettlebell",
    "kb": "kettlebell",
}

# Display-equipment suffix used by Hevy-style names, e.g. "Hip Thrust (Machine)".
EQUIP_DISPLAY_ORDER = ["Barbell", "Dumbbell", "Cable", "Machine", "Kettlebell", "Band", "Smith Machine"]


def norm(text: str) -> str:
    t = text.lower().replace("-", " ").replace("_", " ")
    return " ".join(re.findall(r"[a-z0-9]+", t))


def base_name(title: str) -> tuple[str, str | None]:
    """Split 'Hip Thrust (Machine)' -> ('Hip Thrust', 'Machine')."""
    m = re.match(r"^(.*?)\s*\(([^)]+)\)\s*$", title.strip())
    if m:
        return m.group(1).strip(), m.group(2).strip()
    return title.strip(), None


def equipment_from_title(title: str) -> str | None:
    _, suffix = base_name(title)
    if not suffix:
        return None
    s = suffix.lower()
    if "smith" in s:
        return "smith"
    if "barbell" in s or s == "bb":
        return "barbell"
    if "dumbbell" in s or s == "db":
        return "dumbbell"
    if "cable" in s:
        return "cable"
    if "machine" in s:
        return "machine"
    if "kettlebell" in s or s == "kb":
        return "kettlebell"
    if "band" in s:
        return "band"
    return None


def load_inputs():
    used = json.loads(USED_PATH.read_text())["exercises"]
    staples_raw = json.loads(STAPLES_PATH.read_text())["staples"]
    staples = {norm(s["canonical"]) for s in staples_raw}
    db = json.loads(DB_PATH.read_text())
    overlay = json.loads(OVERLAY_PATH.read_text())
    arch = json.loads(ARCH_PATH.read_text())
    return used, staples, db, overlay, arch


def main():
    used, staple_canons, db, overlay, arch = load_inputs()

    usage_by_norm = {}
    for e in used:
        n = norm(e["name"])
        cur = usage_by_norm.get(n)
        if cur is None or e["setCount"] > cur["setCount"]:
            usage_by_norm[n] = e

    # Seed overlay rows are canonical entries with stable ids.
    seed_ids_by_alias: dict[str, list[str]] = defaultdict(list)
    for entry in overlay["exercises"]:
        for alias in [entry["canonicalName"], entry["displayName"], *entry.get("aliases", [])]:
            seed_ids_by_alias[norm(alias)].append(entry["id"])

    # DB canonical name -> row id
    db_id_by_name = {norm(r["name"]): r["id"] for r in db}
    # Archetype info
    mapping = arch["mapping"]
    variants = arch["variants"]
    archetype_display = {a["id"]: a["displayName"] for a in arch["archetypes"]}

    def archetype_for(exercise_ref: str) -> str:
        key = exercise_ref.removeprefix("seed-")
        return mapping.get(exercise_ref) or mapping.get(key) or ""

    # --- Match each used title to catalogue ---
    matched_used: dict[str, dict] = {}  # used name -> match info
    unmatched_used: list[dict] = []

    for e in sorted(used, key=lambda x: -x["setCount"]):
        title = e["name"]
        n = norm(title)
        base, _suffix = base_name(title)
        nb = norm(base)

        hit = None
        kind = None
        if n in seed_ids_by_alias:
            hit = seed_ids_by_alias[n][0]
            kind = "seed-alias"
        elif nb in seed_ids_by_alias and equipment_from_title(title):
            candidates = seed_ids_by_alias[nb]
            equip = equipment_from_title(title)
            exact = [c for c in candidates if c.endswith(f"-{equip}")]
            if exact:
                hit = exact[0]
                kind = "seed-base+equip"
            else:
                # Same base exists but not in this equipment: keep as a distinct row
                # (e.g. Hip Thrust (Machine) vs barbell-only catalogue) rather than collapse.
                unmatched_used.append(e)
                continue
        elif n in db_id_by_name:
            hit = f"seed-{db_id_by_name[n]}"
            kind = "db-name"
        else:
            # token-subset match against DB names; prefer the candidate with fewest extra
            # tokens (plainest name) so "Push Up" does not latch onto a qualified variant.
            toks = set(n.split())
            best = None
            best_extra = None
            best_len = -1
            for name, rid in db_id_by_name.items():
                kt = set(name.split())
                if not (toks and toks.issubset(kt)):
                    continue
                extra = len(kt) - len(toks)
                # Reject qualified candidates when the query is plain: a modifier like
                # close-grip/suspended/incline means a different exercise, not a naming variant.
                if extra > 0 and any(
                    mod in name
                    for mod in (
                        "close grip", "close", "wide", "incline", "decline", "suspended",
                        "single arm", "single", "one arm", "plyo", "clock", "side plank",
                        "weighted", "feet", "ball", "band", "kettlebell",
                    )
                ):
                    continue
                if best is None or extra < best_extra or (extra == best_extra and len(name) < best_len):
                    best = rid
                    best_extra = extra
                    best_len = len(name)
            if best:
                hit = f"seed-{best}"
                kind = "db-token-subset"

        if hit:
            matched_used[title] = {"ref": hit, "kind": kind, **e}
        else:
            unmatched_used.append(e)

    # --- Catalogue rows: build working list from DB + overlay ---
    overlay_by_source = {}
    for entry in overlay["exercises"]:
        sid = entry.get("sourceDatasetID")
        if sid:
            overlay_by_source[sid] = entry

    rows = []  # dicts for CSV
    used_refs_matched = {m["ref"] for m in matched_used.values()}

    # usage counts per catalogue ref (via matched used titles)
    usage_sets_by_ref = defaultdict(int)
    usage_workouts_by_ref = defaultdict(int)
    usage_last_by_ref = {}
    usage_titles_by_ref = defaultdict(list)
    for title, m in matched_used.items():
        ref = m["ref"]
        usage_sets_by_ref[ref] += m["setCount"]
        usage_workouts_by_ref[ref] += m["workoutCount"]
        prev_last = usage_last_by_ref.get(ref)
        if prev_last is None or (m.get("lastUsed") or "") > prev_last:
            usage_last_by_ref[ref] = m.get("lastUsed") or ""
        usage_titles_by_ref[ref].append(title)

    # Group near-duplicates inside same archetype+equipment for merge proposals.
    group_members = defaultdict(list)
    for r in db:
        ref = f"seed-{r['id']}"
        arch_id = archetype_for(ref)
        equip = (r.get("equipment") or "other").lower()
        group_members[(arch_id, equip)].append((ref, r))

    merge_target = {}  # ref -> canonical ref within its group
    for key, members in group_members.items():
        if len(members) < 2:
            continue
        ranked = sorted(
            members,
            key=lambda mr: (-usage_sets_by_ref.get(mr[0], 0), -(1 if mr[1].get("name", "").lower() in staple_canons else 0), len(mr[1]["name"])),
        )
        canon_ref, canon_row = ranked[0]
        for ref, row in members:
            if ref == canon_ref:
                continue
            n_ref = norm(row["name"])
            n_canon = norm(canon_row["name"])
            # Only merge when normalized names are equal after stripping single-arm/one-arm prefixes,
            # or identical modulo punctuation/plural. Conservative on purpose.
            def simplify(s: str) -> str:
                s = re.sub(r"\b(one|single)[- ]?arm\b|\bone[- ]arm\b", "", s)
                s = re.sub(r"\bs\b", "", s) if False else s
                s = re.sub(r"\b(tricep)\b", "triceps", s)
                s = re.sub(r"\bpush ?ups?\b", "push up", s)
                s = re.sub(r"\b(push up)s\b", r"\1", s)
                return " ".join(sorted(s.split()))
            if simplify(n_ref) == simplify(n_canon):
                merge_target[ref] = canon_ref

    hide_keywords = ("smr", "stretch")

    for r in db:
        ref = f"seed-{r['id']}"
        name = r["name"]
        low = name.lower()
        arch_id = archetype_for(ref)
        sets = usage_sets_by_ref.get(ref, 0)
        workouts = usage_workouts_by_ref.get(ref, 0)
        last = usage_last_by_ref.get(ref, "")
        is_staple = norm(name) in staple_canons

        action = "keep"
        notes = ""
        target = ""

        if ref in merge_target:
            tgt = merge_target[ref]
            action = f"merge_into:{tgt}"
            target = tgt
            notes = "duplicate variant of same movement/equipment"
        elif sets > 0:
            action = "keep"
            notes = f"used by Cameron ({sets} sets)"
        elif is_staple:
            action = "keep"
            notes = "hevy-style staple"
        elif any(k in low for k in hide_keywords) or (r.get("category") or "").lower() == "stretching":
            action = "hide"
            notes = "stretch/SMR row"
        elif arch_id in ("", "sled_push_pull") or (r.get("category") or "").lower() in (
            "strongman",
            "plyometrics",
        ):
            action = "hide"
            notes = "niche/unused category"
        else:
            action = "hide"
            notes = "unused by Cameron and not a staple"

        ov = overlay_by_source.get(r["id"])
        display = ov["displayName"] if ov else None

        rows.append(
            {
                "id": ref,
                "display_name": display or "",
                "canonical_name": name.lower(),
                "muscle": (ov or {}).get("primaryMuscleGroup") or (r.get("primaryMuscles") or [""])[0],
                "equipment": (ov or {}).get("equipment") or r.get("equipment") or "",
                "archetype": arch_id,
                "cameron_sets": sets,
                "cameron_workouts": workouts,
                "last_used": last,
                "action": action,
                "proposed_canonical": target,
                "notes": notes,
            }
        )

    # Overlay-only rows that don't exist in DB (all current seeds do exist via sourceDatasetID,
    # but be safe and include any without a source id).
    db_ids = {r["id"] for r in db}
    for entry in overlay["exercises"]:
        sid = entry.get("sourceDatasetID")
        if sid and sid in db_ids:
            continue
        ref = entry["id"]
        sets = usage_sets_by_ref.get(ref, 0)
        rows.append(
            {
                "id": ref,
                "display_name": entry["displayName"],
                "canonical_name": entry["canonicalName"],
                "muscle": entry.get("primaryMuscleGroup") or "",
                "equipment": entry.get("equipment") or "",
                "archetype": archetype_for(ref),
                "cameron_sets": sets,
                "cameron_workouts": usage_workouts_by_ref.get(ref, 0),
                "last_used": usage_last_by_ref.get(ref, ""),
                "action": "keep" if sets > 0 or entry.get("isHevyLibrary") else "hide",
                "proposed_canonical": "",
                "notes": "overlay-only row",
            }
        )

    # Unmatched used titles -> add_new rows
    for e in unmatched_used:
        title = e["name"]
        base, _suffix = base_name(title)
        equip_guess = equipment_from_title(title)
        muscle_guess = guess_muscle(base)
        rows.append(
            {
                "id": "",
                "display_name": hevy_style_display(title),
                "canonical_name": norm(title),
                "muscle": muscle_guess,
                "equipment": equip_guess or "",
                "archetype": suggest_archetype(norm(base), arch),
                "cameron_sets": e["setCount"],
                "cameron_workouts": e["workoutCount"],
                "last_used": e.get("lastUsed") or "",
                "action": "add_new",
                "proposed_canonical": norm(title),
                "notes": "logged in Hevy history but missing from catalogue",
            }
        )

    rows.sort(key=lambda r: (r["action"].startswith("add_new"), r["action"], -(r["cameron_sets"] or 0)))

    fieldnames = [
        "action", "id", "display_name", "canonical_name", "muscle", "equipment",
        "archetype", "cameron_sets", "cameron_workouts", "last_used",
        "proposed_canonical", "notes",
    ]
    with AUDIT_CSV.open("w", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)

    counts = Counter(r["action"].split(":")[0] for r in rows)
    adds = sum(1 for r in rows if r["action"] == "add_new")
    merges = sum(1 for r in rows if r["action"].startswith("merge_into"))
    keeps = counts.get("keep", 0)

    summary = [
        "# Catalogue audit summary",
        "",
        f"- Catalogue rows audited: {len(rows) - adds}",
        f"- Missing-from-catalogue used titles proposed as add_new: {adds}",
        f"- keep (used or staple): {keeps}",
        f"- merge_into proposals: {merges}",
        f"- hide proposals: {counts.get('hide', 0)}",
        "",
        "Edit `action` per row in catalog_audit.csv (keep / hide / rename / add_new / merge_into:<target-id>) then hand back.",
        "",
        "## Top unmatched used titles (proposed add_new)",
        "",
    ]
    for r in rows:
        if r["action"] == "add_new" and r["cameron_sets"] >= 5:
            summary.append(f"- {r['display_name']} | {r['cameron_sets']} sets, muscle guess: {r['muscle']}, equip: {r['equipment']}")
    SUMMARY_MD.write_text("\n".join(summary) + "\n")

    print(f"wrote {AUDIT_CSV} ({len(rows)} rows)")
    print(f"wrote {SUMMARY_MD}")


MUSCLE_HINTS = {
    "chest fly": "chest", "fly": "chest", "pec": "chest", "bench": "chest", "press": None,
    "curl": "biceps", "row": "upper back", "pulldown": "lats", "pull up": "lats", "pull-up": "lats",
    "lat": "lats", "extension": None, "thrust": "glutes", "bridge": "glutes", "abduction": "abductors",
    "adduction": "adductors", "calf raise": "calves", "leg curl": "hamstrings", "leg press": "quadriceps",
    "squat": "quadriceps", "deadlift": "hamstrings", "rdl": "hamstrings", "lateral raise": "shoulders",
    "kickback": "triceps", "pushdown": "triceps", "pushdowns": "triceps", "skullcrusher": "triceps",
    "dip": None, "crunch": "abs", "plank": "abs", "raise": "shoulders", "shrug": "traps",
}


def guess_muscle(base: str) -> str:
    b = base.lower()
    if "triceps" in b or "tricep" in b:
        return "triceps"
    if "biceps" in b or "bicep" in b or "hammer curl" in b or "preacher" in b:
        return "biceps"
    for kw, muscle in MUSCLE_HINTS.items():
        if kw in b and muscle:
            return muscle
    if "back extension" in b or "hyperextension" in b:
        return "lower back"
    if "y raise" in b:
        return "shoulders"
    if "nordic" in b:
        return "hamstrings"
    if "hex press" in b:
        return "chest"
    if "split squat" in b:
        return "quadriceps"
    if "romanian deadlift" in b:
        return "hamstrings"
    return ""


def suggest_archetype(base_norm: str, arch: dict) -> str:
    for a in arch["archetypes"]:
        aliases = {norm(x) for x in ([a["displayName"], a["id"], *a.get("coachAliases", [])])}
        if base_norm in aliases:
            return a["id"]
    for a in arch["archetypes"]:
        aliases = {norm(x) for x in ([a["displayName"], *a.get("coachAliases", [])])}
        bt = set(base_norm.split())
        if bt and bt.issubset(set().union(*[set(al.split()) for al in aliases])):
            return a["id"]
    return ""


def hevy_style_display(title: str) -> str:
    base, suffix = base_name(title)
    if suffix:
        return f"{base} ({suffix})"
    equip = None
    words = base.lower().split()
    for i, w in enumerate(words):
        if w in EQUIPMENT_TOKENS and EQUIPMENT_TOKENS[w] != "cable" or w in ("rope",):
            mapped = EQUIPMENT_TOKENS[w]
            display = {"barbell": "Barbell", "dumbbell": "Dumbbell", "machine": "Machine",
                       "kettlebell": "Kettlebell", "band": "Band", "smith": "Smith Machine"}.get(mapped)
            if display:
                stripped = " ".join(words[:i] + words[i + 1:])
                return f"{stripped.title()} ({display})"
    return title


if __name__ == "__main__":
    main()
