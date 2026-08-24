#!/usr/bin/env python3
"""Apply reviewed catalog_audit.csv decisions to the Helm exercise seeds.

Reads scripts/catalog-prep/catalog_audit.csv (action column: keep / hide / rename /
merge_into:<target-id> / add_new) and rewrites:

  Helm/Resources/ExerciseSeed/exercises.json            overlay (seedVersion bumped to 7)
  Helm/Resources/ExerciseSeed/coach_archetype_catalog.json

Hidden rows are recorded in the new "hiddenIDs" manifest field; the importer soft-deletes
them so session history foreign keys stay intact.
"""

import csv
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PREP = ROOT / "scripts" / "catalog-prep"
SEED_DIR = ROOT / "Helm" / "Resources" / "ExerciseSeed"

AUDIT_CSV = PREP / "catalog_audit.csv"
OVERLAY_PATH = SEED_DIR / "exercises.json"
DB_PATH = SEED_DIR / "free-exercise-db.json"
ARCH_PATH = SEED_DIR / "coach_archetype_catalog.json"

NEW_SEED_VERSION = 7

EQUIPMENT_DISPLAY = {
    "barbell": "Barbell",
    "dumbbell": "Dumbbell",
    "cable": "Cable",
    "machine": "Machine",
    "kettlebell": "Kettlebell",
    "band": "Band",
    "smith": "Smith Machine",
}

MOVEMENT_BY_ARCHETYPE = {
    "squat": "squat", "hack_squat": "squat", "leg_press": "squat", "leg_extension": "squat",
    "deadlift": "hinge", "hip_thrust": "hinge", "romanian_deadlift": "hinge",
    "back_extension": "hinge", "good_morning": "hinge",
    "lunge": "lunge", "split_squat": "lunge", "step_up": "lunge",
    "bench_press": "horizontalPush", "incline_press": "horizontalPush", "decline_press": "horizontalPush",
    "chest_fly": "isolation", "incline_chest_fly": "isolation",
    "shoulder_press": "verticalPush", "lateral_raise": "isolation", "front_raise": "isolation",
    "y_raise": "isolation", "rear_delt_fly": "isolation", "shrug": "isolation", "upright_row": "horizontalPull",
    "lat_pulldown": "verticalPull", "pull_up": "verticalPull", "straight_arm_pulldown": "verticalPull",
    "bent_over_row": "horizontalPull", "seated_row": "horizontalPull", "chest_supported_row": "horizontalPull",
    "single_arm_row": "horizontalPull", "face_pull": "horizontalPull",
    "biceps_curl": "isolation", "hammer_curl": "isolation", "preacher_curl": "isolation",
    "spider_curl": "isolation", "incline_biceps_curl": "isolation", "wrist_curl": "isolation",
    "triceps_pushdown": "isolation", "overhead_triceps_extension": "isolation",
    "skullcrusher": "isolation", "triceps_kickback": "isolation", "triceps_dip": "isolation",
    "standing_calf_raise": "isolation", "seated_calf_raise": "isolation", "donkey_calf_raise": "isolation",
    "crunch": "core", "sit_up": "core", "cable_crunch": "core", "hanging_leg_raise": "core",
    "plank": "core", "russian_twist": "core", "ab_rollout": "core", "pallof_press": "core",
    "running": "cardio", "cycling": "cardio", "rowing_machine": "cardio", "jump_rope": "cardio",
}


def norm(text: str) -> str:
    t = text.lower().replace("-", " ").replace("_", " ")
    return " ".join(re.findall(r"[a-z0-9]+", t))


def title_case_base(base: str) -> str:
    minor = {"of", "the", "and", "to", "a", "an", "with", "on"}
    words = base.split()
    out = []
    for i, w in enumerate(words):
        out.append(w if (w in minor and i > 0) else w.capitalize())
    return " ".join(out)


def hevy_display(title: str) -> str:
    """'Hip Thrust (Machine)' -> unchanged; 'push up' -> 'Push Up'; adds equipment suffix if known."""
    m = re.match(r"^(.*?)\s*\(([^)]+)\)\s*$", title.strip())
    if m:
        return f"{title_case_base(m.group(1))} ({m.group(2).strip()})"
    return title_case_base(title.strip())


def load_audit():
    with AUDIT_CSV.open() as fh:
        return list(csv.DictReader(fh))


def main():
    audit = load_audit()
    overlay = json.loads(OVERLAY_PATH.read_text())
    db = json.loads(DB_PATH.read_text())
    arch = json.loads(ARCH_PATH.read_text())

    db_by_id = {r["id"]: r for r in db}
    overlay_by_id = {e["id"]: e for e in overlay["exercises"]}

    # --- Parse actions ---
    keep_ids, hide_ids, rename_map, merge_map, adds = set(), set(), {}, {}, []
    for row in audit:
        action = (row["action"] or "").strip()
        rid = (row["id"] or "").strip()
        if action == "add_new" or (not rid and row.get("proposed_canonical")):
            if not row.get("proposed_canonical"):
                continue
            adds.append(row)
        elif action.startswith("merge_into:"):
            target = action.split(":", 1)[1].strip()
            if rid and target:
                merge_map[rid] = target
        elif action == "hide":
            if rid:
                hide_ids.add(rid)
        elif action == "rename":
            if rid:
                rename_map[rid] = row
            keep_ids.add(rid)
        else:  # keep (default)
            if rid:
                keep_ids.add(rid)

    # Rows merged into a target are treated as hidden aliases of the target.
    for src in merge_map:
        hide_ids.add(src)

    # --- Build final visible catalogue refs ---
    # A ref is either an overlay id (seed-<slug>) or seed-<DatasetId>.
    def display_for(ref: str) -> str | None:
        entry = overlay_by_id.get(ref)
        if entry:
            return entry["displayName"]
        ds_id = ref.removeprefix("seed-")
        row = db_by_id.get(ds_id)
        if row:
            return row["name"]
        return None

    all_refs = {f"seed-{r['id']}" for r in db} | set(overlay_by_id.keys()) - hide_ids
    visible_refs = sorted((all_refs - hide_ids))

    # --- Rewrite overlay ---
    kept_overlay_entries = []
    seen_ids = set()
    for e in overlay["exercises"]:
        if e["id"] in hide_ids or e["id"] in seen_ids:
            continue
        if e["id"] in rename_map:
            row = rename_map[e["id"]]
            e = dict(e)
            if row.get("display_name"):
                e["displayName"] = hevy_display(row["display_name"])
                e["aliases"] = list({*e.get("aliases", []), row["display_name"], e["displayName"]})
            if row.get("muscle"):
                e["primaryMuscleGroup"] = row["muscle"].lower()
            if row.get("equipment"):
                e["equipment"] = row["equipment"].lower()
        seen_ids.add(e["id"])
        e.setdefault("isPickerDefault", True)
        e["isPickerDefault"] = True
        kept_overlay_entries.append(e)

    # --- Add new entries from unmatched used titles ---
    used_mode = "weight_reps"
    existing_canonicals = {norm(e["canonicalName"]) for e in kept_overlay_entries}
    for row in adds:
        canonical = norm(row["proposed_canonical"])
        if canonical in existing_canonicals:
            continue
        existing_canonicals.add(canonical)
        equip_raw = (row.get("equipment") or "").strip().lower()
        display = hevy_display(row.get("display_name") or row["proposed_canonical"])
        slug = canonical.replace(" ", "-")
        archetype = (row.get("archetype") or "").strip()
        movement = MOVEMENT_BY_ARCHETYPE.get(archetype, "isolation")
        entry = {
            "id": f"seed-cam-{slug}",
            "canonicalName": canonical,
            "displayName": display,
            "aliases": [display],
            "exerciseMode": used_mode,
            "equipment": equip_raw or None,
            "primaryMuscleGroup": (row.get("muscle") or "").strip().lower() or None,
            "secondaryMuscleGroups": [],
            "movementPattern": movement,
            "isPickerDefault": True,
            "isHevyLibrary": False,
        }
        entry = {k: v for k, v in entry.items() if v is not None}
        kept_overlay_entries.append(entry)

    overlay_doc = {
        "seedVersion": NEW_SEED_VERSION,
        "placeholder": False,
        "catalogResource": "free-exercise-db",
        "pickerCuration": "explicit",
        "hiddenIDs": sorted(hide_ids),
        "exercises": kept_overlay_entries,
    }
    OVERLAY_PATH.write_text(json.dumps(overlay_doc, indent=2) + "\n")

    # --- Rewrite archetype catalogue against visible refs ---
    mapping = {}
    for ref in visible_refs:
        key = ref.removeprefix("seed-")
        arch_id = arch["mapping"].get(ref) or arch["mapping"].get(key)
        if arch_id:
            mapping[ref] = arch_id

    # Merge sources resolve to their target's archetype.
    for src, tgt in merge_map.items():
        tgt_arch = mapping.get(tgt) or arch["mapping"].get(tgt.removeprefix("seed-"))
        if tgt_arch:
            mapping[src] = tgt_arch

    # New cameron rows use their suggested archetype.
    for row in adds:
        arch_id = (row.get("archetype") or "").strip()
        if arch_id:
            mapping[f"seed-cam-{norm(row['proposed_canonical']).replace(' ', '-')}"] = arch_id

    variants = {}
    for ref, arch_id in mapping.items():
        variants.setdefault(arch_id, []).append(ref)

    new_variants = {}
    for arch_id, members in variants.items():
        old = arch["variants"].get(arch_id, {})
        preferred = old.get("preferredDefaultExerciseId")
        if preferred not in members:
            # Prefer an overlay/cameron row, else alphabetical first.
            preferred = next(
                (m for m in members if m.startswith("seed-cam-")),
                next((m for m in members if overlay_by_id.get(m)), sorted(members)[0]),
            )
        new_variants[arch_id] = {
            "members": sorted(members),
            "preferredDefaultExerciseId": preferred,
        }

    kept_archetype_ids = set(new_variants.keys())
    new_archetypes = [a for a in arch["archetypes"] if a["id"] in kept_archetype_ids]

    arch_doc = {
        "schemaVersion": arch.get("schemaVersion", "coach_archetype_catalog.v1"),
        "generatedAt": arch.get("generatedAt"),
        "archetypes": new_archetypes,
        "mapping": dict(sorted(mapping.items())),
        "variants": dict(sorted(new_variants.items())),
        "aliasSuggestions": arch.get("aliasSuggestions"),
        "validation": arch.get("validation"),
    }
    ARCH_PATH.write_text(json.dumps(arch_doc, indent=2) + "\n")

    print(f"visible catalogue rows: {len(visible_refs)}")
    print(f"overlay entries: {len(kept_overlay_entries)} (added {len(adds)} from Cameron history)")
    print(f"hidden/merged rows: {len(hide_ids)}")
    print(f"archetypes kept: {len(new_archetypes)}")
    print(f"seedVersion -> {NEW_SEED_VERSION}")


if __name__ == "__main__":
    main()
