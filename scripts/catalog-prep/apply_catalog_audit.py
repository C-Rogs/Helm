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

    # --- Manual corrections from Cameron's mapping review ---
    # Plain-name entries that must exist and must not be shadowed by qualified variants.
    MANUAL_ENTRIES = [
        {
            "id": "seed-cam-running",
            "canonicalName": "running",
            "displayName": "Running",
            "aliases": ["Running", "Treadmill", "Running, Treadmill", "Running Treadmill"],
            "exerciseMode": "distanceDuration",
            "primaryMuscleGroup": "legs",
            "secondaryMuscleGroups": [],
            "movementPattern": "cardio",
            "coachingCues": [
                "Land under your hips with a quick cadence.",
                "Relax shoulders; keep an easy breathing rhythm.",
            ],
        },
        {
            "id": "seed-cam-walking",
            "canonicalName": "walking",
            "displayName": "Walking",
            "aliases": ["Walking", "Walking, Treadmill", "Walking Treadmill"],
            "exerciseMode": "distanceDuration",
            "primaryMuscleGroup": "legs",
            "secondaryMuscleGroups": [],
            "movementPattern": "cardio",
            "coachingCues": [
                "Stand tall; swing the arms naturally.",
                "Brisk pace keeps it useful as active recovery.",
            ],
        },
        {
            "id": "seed-cam-hammer-curl-dumbbell",
            "canonicalName": "hammer curl dumbbell",
            "displayName": "Hammer Curl (Dumbbell)",
            "aliases": ["Hammer Curl (Dumbbell)", "Dumbbell Hammer Curl"],
            "equipment": "dumbbell",
            "primaryMuscleGroup": "biceps",
            "secondaryMuscleGroups": ["forearms"],
            "movementPattern": "isolation",
            "coachingCues": [
                "Keep palms facing each other the whole way up.",
                "Elbows pinned to your sides; no swinging.",
                "Curl to shoulder height and lower slowly.",
            ],
        },
        {
            "id": "seed-cam-preacher-curl-dumbbell",
            "canonicalName": "preacher curl dumbbell",
            "displayName": "Preacher Curl (Dumbbell)",
            "aliases": ["Preacher Curl (Dumbbell)", "Dumbbell Preacher Curl", "Preacher Curl"],
            "equipment": "dumbbell",
            "primaryMuscleGroup": "biceps",
            "secondaryMuscleGroups": ["forearms"],
            "movementPattern": "isolation",
            "coachingCues": [
                "Arms flat on the pad; elbows stay planted.",
                "Curl up and squeeze at the top.",
                "Lower slowly to a full stretch without hyperextending.",
            ],
        },
        {
            "id": "seed-cam-triceps-extension-dumbbell",
            "canonicalName": "triceps extension dumbbell",
            "displayName": "Triceps Extension (Dumbbell)",
            "aliases": ["Triceps Extension (Dumbbell)", "Dumbbell Triceps Extension", "Lying Triceps Extension (Dumbbell)"],
            "equipment": "dumbbell",
            "primaryMuscleGroup": "triceps",
            "secondaryMuscleGroups": [],
            "movementPattern": "isolation",
            "coachingCues": [
                "Upper arms stay vertical; only the forearms move.",
                "Lower until you feel a deep triceps stretch.",
                "Extend fully without locking out hard.",
            ],
        },
        {
            "id": "seed-cam-triceps-extension-cable-bar",
            "canonicalName": "triceps extension cable bar",
            "displayName": "Triceps Extension (Cable Bar)",
            "aliases": ["Triceps Extension (Cable Bar)", "Cable Bar Triceps Extension", "Straight Bar Triceps Extension"],
            "equipment": "cable",
            "primaryMuscleGroup": "triceps",
            "secondaryMuscleGroups": [],
            "movementPattern": "isolation",
            "coachingCues": [
                "Elbows glued to your ribs; push the bar down and around.",
                "Split the hands slightly at lockout for full contraction.",
                "Control the return; keep tension on the triceps.",
            ],
        },
    ]
    existing_ids = {e["id"] for e in kept_overlay_entries}
    for m in MANUAL_ENTRIES:
        if m["id"] not in existing_ids:
            kept_overlay_entries.append(m)
            existing_ids.add(m["id"])

    # DB-only rows that need display-name corrections (no overlay entry exists,
    # so the raw free-exercise-db name shows and matches).
    MANUAL_DB_RENAMES = {
        "seed-Cable_Seated_Lateral_Raise": {
            "displayName": "Cable Lateral Raise",
            "aliases": [
                "Cable Lateral Raise",
                "Standing Cable Lateral Raise",
                "Cable Seated Lateral Raise",
                # Hevy title kept verbatim so import resolution hits this entry first.
                "Lateral Raise (Cable)",
            ],
        },
        "seed-Low_Cable_Triceps_Extension": {
            "displayName": "Triceps Extension (Cable Bar)",
            "aliases": [
                "Triceps Extension (Cable Bar)",
                "Triceps Extension (Cable)",
                "Low Cable Triceps Extension",
                "Cable Bar Triceps Extension",
            ],
        },
    }
    by_id = {e["id"]: e for e in kept_overlay_entries}
    for ref, fix in MANUAL_DB_RENAMES.items():
        entry = by_id.get(ref)
        if entry is None:
            ds_id = ref.removeprefix("seed-")
            db_row = db_by_id.get(ds_id)
            if not db_row:
                continue
            muscles = db_row.get("primaryMuscles") or []
            secondary = [m for m in (db_row.get("secondaryMuscles") or [])]
            entry = {
                "id": ref,
                "canonicalName": norm(fix["displayName"]),
                "displayName": fix["displayName"],
                "aliases": list(fix["aliases"]),
                "exerciseMode": used_mode,
                "equipment": (db_row.get("equipment") or "").strip().lower() or None,
                "primaryMuscleGroup": muscles[0] if muscles else None,
                "secondaryMuscleGroups": secondary,
                "movementPattern": "isolation",
                "isPickerDefault": True,
                "isHevyLibrary": False,
            }
            entry = {k: v for k, v in entry.items() if v is not None}
            kept_overlay_entries.append(entry)
        else:
            entry = dict(entry)
            entry["displayName"] = fix["displayName"]
            entry["aliases"] = sorted({*entry.get("aliases", []), *fix["aliases"]})
            kept_overlay_entries[:] = [
                m if m["id"] != ref else entry for m in kept_overlay_entries
            ]

    # Preacher Hammer Dumbbell Curl: hammer-agnostic alias must not capture plain hammer curls.
    for e in kept_overlay_entries:
        if e["id"] == "seed-Preacher_Hammer_Dumbbell_Curl":
            e.setdefault("aliases", [])
            e["aliases"] = [a for a in e["aliases"] if norm(a) != "hammer curl dumbbell"]
            if "Preacher Hammer Dumbbell Curl" not in e["aliases"]:
                e["aliases"].append("Preacher Hammer Dumbbell Curl")
        # Cable Seated Lateral Raise: Cameron does these standing; make standing the
        # primary name so plain cable lateral raises resolve here, seated stays as variant name.
        if e["id"] == "seed-Cable_Seated_Lateral_Raise":
            e["displayName"] = "Cable Lateral Raise"
            aliases = list({*e.get("aliases", []), "Cable Lateral Raise", "Standing Cable Lateral Raise"})
            e["aliases"] = sorted(aliases)
        # Standing Dumbbell Triceps Extension: drop the standing qualifier from the
        # plain-name space; the neutral dumbbell triceps extension entry owns it now.
        if e["id"] == "seed-Standing_Dumbbell_Triceps_Extension":
            e.setdefault("aliases", [])
            e["aliases"] = [a for a in e["aliases"] if norm(a) != "triceps extension dumbbell"]

    # --- Link overlay rows to their free-exercise-db twins ---
    # The merger only attaches images/instructions when sourceDatasetID is set;
    # without it the row inserts as a new record and shows the generic fallback icon.
    def db_canon(name: str) -> str:
        return norm(name)

    db_by_canonical: dict[str, dict] = {}
    for r in db:
        db_by_canonical.setdefault(db_canon(r["name"]), r)

    # Hand-mapped twins for rows whose wording differs from any DB name.
    # Curated: wrong pictures are worse than no picture, so only confident pairs.
    MANUAL_TWIN_IDS = {
        "seed-bench-press": "Barbell_Bench_Press_-_Medium_Grip",
        "seed-squat": "Barbell_Squat",
        "seed-lat-pulldown": "Close-Grip_Front_Lat_Pulldown",
        "seed-dumbbell-lateral-raise": "Side_Lateral_Raise",
        "seed-overhead-press": "Standing_Barbell_Press_Behind_Neck",
        "seed-pull-up": "Weighted_Pull_Ups",
        "seed-cam-push-up": "Pushups",
        "seed-cam-bench-press-dumbbell": "Dumbbell_Bench_Press",
        "seed-cam-incline-bench-press-dumbbell": "Incline_Dumbbell_Press",
        "seed-cam-incline-chest-fly-dumbbell": "Incline_Dumbbell_Flyes",
        "seed-cam-chest-fly-dumbbell": "Dumbbell_Flyes",
        "seed-cam-skullcrusher-barbell": "EZ-Bar_Skullcrusher",
        "seed-cam-skullcrusher-dumbbell": "Decline_Dumbbell_Triceps_Extension",
        "seed-cam-triceps-dip": "Dips_-_Triceps_Version",
        "seed-cam-chest-dip": "Dips_-_Chest_Version",
        "seed-cam-bench-dip": "Bench_Dips",
        "seed-cam-push-up-close-grip": "Pushups_Close_and_Wide_Hand_Positions",
        "seed-cam-nordic-hamstrings-curls": "Hyperextensions_Back_Extensions",
        "seed-cam-decline-crunch-weighted": "Decline_Crunch",
        "seed-cam-jm-press-barbell": "JM_Press",
        "seed-cam-behind-the-back-curl-cable": "Cable_Hammer_Curls_-_Rope_Attachment",
        "seed-cam-reverse-grip-tricep-pushdown": "Reverse_Grip_Triceps_Pushdown",
        "seed-cam-triceps-kickback-cable": "Tricep_Dumbbell_Kickback",
        "seed-cam-single-arm-triceps-pushdown-cable": "Triceps_Pushdown",
        "seed-cam-straight-arm-lat-pulldown-cable": "Straight-Arm_Pulldown",
        "seed-cam-low-cable-fly-crossovers": "Cable_Crossover",
        "seed-cam-cable-fly-crossovers": "Cable_Crossover",
        "seed-single-arm-cable-lateral-raise": "Cable_Seated_Lateral_Raise",
        "seed-Cable_Seated_Lateral_Raise": "Cable_Shrugs",
        "seed-cam-seated-row-machine": "Seated_Cable_Rows",
        "seed-cam-seated-cable-row-v-grip-cable": "Seated_Cable_Rows",
        "seed-seated-cable-row": "Seated_Cable_Rows",
        "seed-cam-seated-shoulder-press-machine": "Cable_Shoulder_Press",
        "seed-cam-shoulder-press-machine-plates": "Cable_Shoulder_Press",
        "seed-cam-lateral-raise-machine": "Lateral_Raise_-_With_Bands",
        "seed-cam-chest-fly-machine": "Butterfly",
        "seed-cam-butterfly-pec-deck": "Butterfly",
        "seed-cam-chest-press-machine": "Leverage_Chest_Press",
        "seed-machine-chest-press": "Leverage_Chest_Press",
        "seed-cam-incline-chest-press-machine": "Leverage_Incline_Chest_Press",
        "seed-cam-seated-dip-machine": "Dip_Machine",
        "seed-cam-hack-squat-machine": "Hack_Squat",
        "seed-cam-preacher-curl-barbell": "Barbell_Curl",
        "seed-cam-preacher-curl-machine": "Machine_Preacher_Curls",
        "seed-ez-bar-curl": "EZ-Bar_Curl",
        "seed-romanian-deadlift": "Romanian_Deadlift",
        "seed-cam-shrug-cable": "Cable_Shrugs",
        "seed-cable-face-pull": "Face_Pull",
        "seed-triceps-rope-pushdown": "Triceps_Pushdown_-_Rope_Attachment",
        "seed-horizontal-leg-press": "Leg_Press",
        "seed-lying-leg-curl": "Lying_Leg_Curls",
        "seed-seated-leg-curl": "Seated_Leg_Curl",
        "seed-leg-extension": "Leg_Extensions",
        "seed-calf-extension": "Seated_Calf_Raise",
        "seed-machine-crunch": "Ab_Crunch_Machine",
        "seed-chest-supported-row": "Leverage_Iso_Row",
        "seed-cam-back-extension-weighted-hyperextension": "Hyperextensions_Back_Extensions",
        "seed-cam-hip-adduction-machine": "Cable_Hip_Adduction",
        "seed-hip-thrust": "Barbell_Hip_Thrust",
        "seed-cam-hip-thrust-machine": "Barbell_Hip_Thrust",
        "seed-barbell-row": "Bent_Over_Barbell_Row",
        "seed-single-arm-dumbbell-row": "One-Arm_Dumbbell_Row",
        "seed-standing-calf-raise": "Standing_Calf_Raises",
        "seed-cam-standing-calf-raise-dumbbell": "Rocking_Standing_Calf_Raise",
        "seed-cam-single-leg-standing-calf-raise-machine": "Standing_Calf_Raises",
        "seed-cam-seated-dumbbell-shoulder-press": "Seated_Dumbbell_Press",
        "seed-cam-seated-overhead-press-dumbbell": "Seated_Dumbbell_Press",
        "seed-dumbbell-curl": "Dumbbell_Bicep_Curl",
        "seed-cam-bicep-curl-barbell": "Barbell_Curl",
        "seed-cam-bicep-curl-cable": "Cable_Hammer_Curls_-_Rope_Attachment",
        "seed-cam-hammer-curl-cable": "Cable_Hammer_Curls_-_Rope_Attachment",
        "seed-cam-hammer-curl-dumbbell": "Alternate_Hammer_Curl",
        "seed-cam-preacher-curl-dumbbell": "Zottman_Curl",
        "seed-cam-seated-incline-curl-dumbbell": "Incline_Dumbbell_Curl",
        "seed-tricep-pushdown": "Triceps_Pushdown",
        "seed-cam-rear-delt-reverse-fly-machine": "Butterfly",
        "seed-cam-rear-delt-reverse-fly-cable": "Cable_Rear_Delt_Fly",
        "seed-cam-rear-delt-reverse-fly-dumbbell": "Reverse_Flyes",
        "seed-cam-reverse-fly-single-arm-cable": "Cable_Rear_Delt_Fly",
        "seed-cam-chest-supported-y-raise-dumbbell": "Alternating_Deltoid_Raise",
        "seed-cam-single-arm-tricep-extension-dumbbell": "Cable_One_Arm_Tricep_Extension",
        "seed-cam-triceps-extension-dumbbell": "Lying_Dumbbell_Tricep_Extension",
        "seed-cam-single-leg-romanian-deadlift-dumbbell": "Romanian_Deadlift",
        "seed-cam-romanian-deadlift-dumbbell": "Romanian_Deadlift",
        "seed-cam-lat-pulldown-machine": "Close-Grip_Front_Lat_Pulldown",
        "seed-cam-lat-pulldown-close-grip-cable": "One_Arm_Lat_Pulldown",
        "seed-cam-bulgarian-split-squat": "Split_Squat_with_Dumbbells",
        "seed-cam-side-plank": "Plank",
        "seed-cam-cycling": "Bicycling",
        "seed-cam-diamond-push-up": "Pushups_Close_and_Wide_Hand_Positions",
        "seed-seated-dumbbell-shoulder-press": "Seated_Dumbbell_Press",
        "seed-cam-triceps-extension-cable-bar": "Triceps_Pushdown",
        "seed-Low_Cable_Triceps_Extension": "Cable_Incline_Pushdown",
    }

    linked = 0
    for e in kept_overlay_entries:
        if e.get("sourceDatasetID"):
            continue
        ds_id = MANUAL_TWIN_IDS.get(e["id"])
        if not ds_id or ds_id not in db_by_id:
            twin = db_by_canonical.get(db_canon(e["canonicalName"]))
            ds_id = twin["id"] if twin else None
        if ds_id and ds_id in db_by_id:
            e["sourceDatasetID"] = ds_id
            linked += 1

    # --- Unhide rows Cameron's wording needs but the audit hid ---
    # "Dumbbell Row" fuzzy-matched to Standing Dumbbell Upright Row because the
    # one-arm row was hidden; restore it so the natural match wins.
    unhide_ids = {"One-Arm_Dumbbell_Row"}
    hide_ids -= {f"seed-{i}" for i in unhide_ids}

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

    # Manual correction entries map to fixed archetypes.
    MANUAL_ARCHETYPES = {
        "seed-cam-hammer-curl-dumbbell": "hammer_curl",
        "seed-cam-preacher-curl-dumbbell": "preacher_curl",
        "seed-cam-triceps-extension-dumbbell": "overhead_triceps_extension",
        "seed-cam-triceps-extension-cable-bar": "triceps_pushdown",
        "seed-cam-running": "running",
        "seed-cam-walking": "running",
    }
    for ref, arch_id in MANUAL_ARCHETYPES.items():
        mapping[ref] = arch_id

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
