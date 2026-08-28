#!/usr/bin/env python3
"""Rebuild exercises.json seed 8: overlay keeps own ids, Hevy export is the floor.

FEDB rows stay in the bundle for GIFs/history, then hiddenIDs soft-deletes every
FEDB id that is not itself an overlay id.
"""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SEED = ROOT / "Helm" / "Resources" / "ExerciseSeed"
PREP = ROOT / "scripts" / "catalog-prep"
OVERLAY_PATH = SEED / "exercises.json"
FEDB_PATH = SEED / "free-exercise-db.json"
USED_PATH = PREP / "cameron_used_exercises.json"

NEW_SEED_VERSION = 8

ROPE_ALIASES = [
    "Hammer Curl (Cable)",
    "Cable Hammer Curl",
    "Rope Hammer Curl",
    "Hammer Curl Rope",
    "Hammer Curls Rope",
    "hammer curls cable",
    "rope attachment hammer curl",
    "cable hammer curls",
]

MUSCLE_GUESS = {
    "deadlift": "hamstrings",
    "face pull": "shoulders",
    "triceps": "triceps",
    "shoulder": "shoulders",
    "press": "chest",
    "curl": "biceps",
    "raise": "shoulders",
    "calf": "calves",
    "shrug": "traps",
    "row": "upper back",
    "pullover": "lats",
    "t bar": "upper back",
    "hanging": "abdominals",
    "plank": "abdominals",
    "treadmill": "legs",
    "dip": "triceps",
}


def norm(text: str) -> str:
    t = text.lower().replace("-", " ").replace("_", " ")
    return " ".join(re.findall(r"[a-z0-9]+", t))


def slug(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", norm(text)).strip("-")


def equipment_from_title(name: str) -> str | None:
    m = re.search(r"\(([^)]+)\)\s*$", name)
    inner = (m.group(1) if m else name).lower()
    for token in ("dumbbell", "barbell", "cable", "machine", "band", "kettlebell", "smith"):
        if token in inner:
            return token
    if "plate" in inner:
        return "machine"
    if "rope" in inner:
        return "cable"
    return None


def muscle_from_title(name: str) -> str | None:
    n = name.lower()
    for needle, muscle in MUSCLE_GUESS.items():
        if needle in n:
            return muscle
    return None


def overlay_names(entry: dict) -> set[str]:
    names = {norm(entry.get("displayName") or "")}
    for alias in entry.get("aliases") or []:
        names.add(norm(alias))
    return {n for n in names if n}


def main() -> None:
    overlay_doc = json.loads(OVERLAY_PATH.read_text())
    fedb = json.loads(FEDB_PATH.read_text())
    used = json.loads(USED_PATH.read_text())
    hevy_names = [row["name"] for row in used["exercises"]]

    entries: list[dict] = []
    seen_ids: set[str] = set()
    matched_hevy: set[str] = set()

    for entry in overlay_doc["exercises"]:
        if entry["id"] in seen_ids:
            continue
        seen_ids.add(entry["id"])
        names = overlay_names(entry)
        hevy_hit = next((h for h in hevy_names if norm(h) in names or names & {norm(h)}), None)
        if hevy_hit:
            matched_hevy.add(hevy_hit)
            entry = dict(entry)
            entry["displayName"] = hevy_hit
            aliases = list(dict.fromkeys([*(entry.get("aliases") or []), hevy_hit, entry["displayName"]]))
            if "hammer curl" in norm(hevy_hit) and "cable" in (entry.get("equipment") or "") + hevy_hit.lower():
                aliases = list(dict.fromkeys(aliases + ROPE_ALIASES))
            entry["aliases"] = aliases
            entry["isPickerDefault"] = True
        else:
            entry = dict(entry)
            entry.setdefault("isPickerDefault", True)
        entries.append(entry)

    overlay_name_index = {n: e for e in entries for n in overlay_names(e)}
    for hevy in hevy_names:
        if hevy in matched_hevy:
            continue
        n = norm(hevy)
        existing = overlay_name_index.get(n)
        if existing is not None:
            aliases = list(dict.fromkeys([*(existing.get("aliases") or []), hevy]))
            existing["aliases"] = aliases
            existing["displayName"] = hevy
            existing["isPickerDefault"] = True
            matched_hevy.add(hevy)
            continue
        eid = f"seed-cam-{slug(hevy)}"
        if eid in seen_ids:
            eid = f"seed-hevy-{slug(hevy)}"
        entry = {
            "id": eid,
            "canonicalName": n,
            "displayName": hevy,
            "aliases": [hevy],
            "exerciseMode": "weight_reps",
            "primaryMuscleGroup": muscle_from_title(hevy),
            "secondaryMuscleGroups": [],
            "movementPattern": "isolation",
            "isPickerDefault": True,
            "isHevyLibrary": True,
        }
        equip = equipment_from_title(hevy)
        if equip:
            entry["equipment"] = equip
        if "hammer curl" in n and equip == "cable":
            entry["aliases"] = list(dict.fromkeys(entry["aliases"] + ROPE_ALIASES))
        if any(k in n for k in ("running", "treadmill", "walk")):
            entry["exerciseMode"] = "distanceDuration"
            entry["movementPattern"] = "cardio"
        if "plank" in n:
            entry["exerciseMode"] = "duration"
            entry["movementPattern"] = "core"
        entry = {k: v for k, v in entry.items() if v is not None}
        entries.append(entry)
        seen_ids.add(eid)
        matched_hevy.add(hevy)

    overlay_ids = {e["id"] for e in entries}
    hidden = sorted(f"seed-{row['id']}" for row in fedb if f"seed-{row['id']}" not in overlay_ids)

    overlay_doc["seedVersion"] = NEW_SEED_VERSION
    overlay_doc["placeholder"] = False
    overlay_doc["pickerCuration"] = "explicit"
    overlay_doc["hiddenIDs"] = hidden
    overlay_doc["exercises"] = entries
    OVERLAY_PATH.write_text(json.dumps(overlay_doc, indent=2) + "\n")

    print(f"overlay={len(entries)} hidden={len(hidden)} hevy_floor={len(hevy_names)} matched={len(matched_hevy)}")
    missing = [h for h in hevy_names if h not in matched_hevy]
    if missing:
        print("unmatched hevy", missing)


if __name__ == "__main__":
    main()
