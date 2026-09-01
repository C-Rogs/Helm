#!/usr/bin/env python3
"""Stamp pickerRank on overlay exercises from cameron_used_exercises.json.

Match overlay display/alias/canonical names to the Hevy frequency list (already
sorted by setCount desc). Matched rows take that file order. Unmatched overlay
extras follow. Rewrites both bundled exercises.json copies at seedVersion 10.
"""
from __future__ import annotations

import json
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HELM_SEED = ROOT / "Helm" / "Resources" / "ExerciseSeed" / "exercises.json"
PACKAGE_SEED = (
    ROOT
    / "Packages"
    / "Persistence"
    / "Sources"
    / "Persistence"
    / "Resources"
    / "ExerciseSeed"
    / "exercises.json"
)
USED_PATH = ROOT / "scripts" / "catalog-prep" / "cameron_used_exercises.json"

NEW_SEED_VERSION = 10


def norm(text: str) -> str:
    t = text.lower().replace("-", " ").replace("_", " ")
    return " ".join(re.findall(r"[a-z0-9]+", t))


def overlay_names(entry: dict) -> set[str]:
    names = {norm(entry.get("displayName") or ""), norm(entry.get("canonicalName") or "")}
    for alias in entry.get("aliases") or []:
        names.add(norm(alias))
    return {n for n in names if n}


def hevy_rank(entry: dict, hevy_ranks: dict[str, int]) -> int | None:
    names = overlay_names(entry)
    ranks = [hevy_ranks[n] for n in names if n in hevy_ranks]
    return min(ranks) if ranks else None


def main() -> None:
    overlay_doc = json.loads(HELM_SEED.read_text())
    used = json.loads(USED_PATH.read_text())
    hevy_rows = used["exercises"]
    hevy_ranks = {norm(row["name"]): index for index, row in enumerate(hevy_rows)}

    entries = list(overlay_doc["exercises"])
    keyed = []
    unmatched_offset = len(hevy_rows)
    unmatched_i = 0
    for original_index, entry in enumerate(entries):
        rank = hevy_rank(entry, hevy_ranks)
        if rank is None:
            rank = unmatched_offset + unmatched_i
            unmatched_i += 1
        keyed.append((rank, original_index, entry))

    keyed.sort(key=lambda item: (item[0], item[1]))
    ranked_entries = []
    matched = 0
    for new_rank, (_, _, entry) in enumerate(keyed):
        row = dict(entry)
        row["pickerRank"] = new_rank
        if hevy_rank(entry, hevy_ranks) is not None:
            matched += 1
        ranked_entries.append(row)

    overlay_doc["seedVersion"] = NEW_SEED_VERSION
    overlay_doc["exercises"] = ranked_entries
    text = json.dumps(overlay_doc, indent=2) + "\n"
    HELM_SEED.write_text(text)
    shutil.copyfile(HELM_SEED, PACKAGE_SEED)

    print(
        f"seedVersion={NEW_SEED_VERSION} overlay={len(ranked_entries)} "
        f"hevy_matched={matched} extras={len(ranked_entries) - matched}"
    )
    if ranked_entries:
        print(f"top={ranked_entries[0]['displayName']} rank=0")


if __name__ == "__main__":
    main()
