# Gemini browser: coach archetype catalog preprocessing

```bash
cd /Users/cameronro/Development/Helm
# Inputs already generated in scripts/catalog-prep/ — re-run if needed:
python3 scripts/catalog-prep/export_helm_inputs.py   # if script exists
# cameron_used from CSV (hevylog.rtf is RTF — use plain CSV):
python3 -c "..." # see cameron_used_exercises.json already built from HevyExport 4.csv
```

**Generated files (ready now):**

| File | Contents |
|------|----------|
| `helm_catalog.json` | 873 exercises (full) |
| `helm_catalog_compact.json` | 873 exercises (id + muscle only) |
| `hevy_style_staples.json` | 77 staples |
| `cameron_used_exercises.json` | **115 exercises** from `HevyExport 4.csv` (5,227 set rows) |

Path: `/Users/cameronro/Development/Helm/scripts/catalog-prep/`

**Note:** `hevylog.rtf` is RTF-wrapped; use `HevyExport 4.csv` for parsing (same data). Upload files from Finder or zip the folder.

## Model

Use **Gemini 3.6 Thinking** (or **3.1 Pro** if output breaks). Temperature 0 if available.

## How to attach files in Gemini

1. Open [gemini.google.com](https://gemini.google.com)
2. Start a **new chat** per pass (keeps context clean)
3. Click **+** / attach → upload JSON files listed for each pass
4. If file too large: paste compact version or split by muscle (see Pass 2)

---

## Pass 1 — Design archetypes (~80–150)

**Upload:**
- `cameron_used_exercises.json`
- `hevy_style_staples.json`
- `helm_catalog_compact.json` (muscle/movement summary of all 873)

**Paste this prompt:**

```
You are a strength-training data engineer building a coach-facing exercise archetype layer for an iOS lifting app.

TASK: Design 80–150 movement archetypes. Do NOT map individual exercise IDs yet.

INPUTS (attached):
1. cameron_used_exercises.json — exercises I actually log in Hevy (prioritize these as "core")
2. hevy_style_staples.json — ~77 Hevy-style staple names
3. helm_catalog_compact.json — 873 Helm exercises (id, displayName, muscle, pattern, equipment) for coverage reference

RULES:
- Group by movement pattern + primary muscle + intent, NOT by equipment variant
  GOOD: one archetype "incline_press" covers barbell incline, dumbbell incline, machine incline
  BAD: one archetype per equipment
- Split when muscles differ (e.g. chest dip vs triceps dip)
- Use Hevy-style displayName (equipment in parentheses where helpful)
- id: stable snake_case (incline_press, lateral_raise, triceps_pushdown)
- Each archetype needs: id, displayName, coachAliases (10–20 casual phrases), primaryMuscleGroup, movementPattern, equipmentClasses[], defaultVariantPriority[], priority (core|common|extended), hevyNames[]

Mark priority "core" for: cameron_used top exercises + hevy_style staples.

REGRESSION FIXTURES (must be same archetype or clearly related variants):
- "Incline Dumbbell Press" / "incline db" → incline_press
- "Barbell Bench Press" / "flat bench" / "bb bench" → bench_press
- "Seated Dumbbell Shoulder Press" → shoulder_press
- "Chest Fly Machine" / "pec deck" / "Butterfly" → chest_fly
- "Dips - Triceps Version" vs chest dips → separate archetypes if needed

OUTPUT: JSON only, no markdown:
{
  "schemaVersion": "coach_archetypes_draft.v1",
  "archetypes": [ ... ]
}
```

**Save Gemini's response** as `archetypes_draft.json` in this folder.

---

## Pass 2 — Map every Helm exercise ID

**Upload:**
- `archetypes_draft.json` (from Pass 1)
- `helm_catalog.json` (full file — if too big, run twice by muscle batch below)

**Paste this prompt:**

```
Map EVERY Helm exercise id to exactly one archetypeId from archetypes_draft.json.

INPUTS (attached):
1. archetypes_draft.json — your archetype definitions from Pass 1
2. helm_catalog.json — catalog[] array with 873 exercises (id, displayName, muscles, equipment)

RULES:
- Output mapping for 100% of catalog[].id — no orphans
- Many exercise IDs → one archetype (many-to-one)
- Never rename or invent exercise ids
- If nothing fits, create a new archetype in "unmappedReview" array with suggested id — but aim for zero unmapped

Also output variants summary per archetype:
- member exerciseIds[]
- preferredDefaultExerciseId (prefer cameron_used frequency if you have that context from archetype priority)

OUTPUT: JSON only:
{
  "schemaVersion": "coach_mapping_draft.v1",
  "mapping": { "seed-bench-press": "bench_press", ... },
  "variants": { "bench_press": { "members": [...], "preferredDefaultExerciseId": "..." } },
  "unmappedReview": []
}
```

### If `helm_catalog.json` won't upload (too large)

Split by muscle in terminal:

```bash
python3 - <<'PY'
import json
from pathlib import Path
p = Path("scripts/catalog-prep/helm_catalog.json")
data = json.loads(p.read_text())
by_muscle = {}
for e in data["catalog"]:
    m = e.get("primaryMuscleGroup") or "unknown"
    by_muscle.setdefault(m, []).append(e)
out = Path("scripts/catalog-prep/batches")
out.mkdir(exist_ok=True)
for m, items in by_muscle.items():
    (out / f"helm_{m}.json").write_text(json.dumps(items, indent=2))
    print(m, len(items))
PY
```

Run Pass 2 once per batch file; merge `mapping` objects in a text editor or follow-up Gemini message.

---

## Pass 3 — Merge + validate + aliases

**Upload:**
- `archetypes_draft.json`
- `mapping_draft.json` (from Pass 2)
- `cameron_used_exercises.json`

**Paste this prompt:**

```
Merge into final coach_archetype_catalog.v1 and validate.

INPUTS (attached): archetypes_draft, mapping_draft, cameron_used_exercises

Produce:
{
  "schemaVersion": "coach_archetype_catalog.v1",
  "generatedAt": "<ISO8601>",
  "archetypes": [...],
  "mapping": { ... },
  "variants": { ... },
  "aliasSuggestions": [ { "exerciseId", "newAliases": [] } ],
  "validation": {
    "archetypeCount": N,
    "mappedHelmIdCount": N,
    "mappingCoveragePercent": 100,
    "unmappedCameronUsed": [],
    "archetypesWithManyVariants": [],
    "regressionFixtures": { "incline_db": "incline_press", ... }
  }
}

Checks:
- mappingCoveragePercent must be 100
- Every cameron_used exercise name must appear in some archetype (via hevyNames, coachAliases, or variant displayName)
- aliasSuggestions: high-confidence only, for exercises.json overlay
- JSON only, no commentary
```

**Save as:** `coach_archetype_catalog.json`

Copy final file to:
`Helm/Resources/ExerciseSeed/coach_archetype_catalog.json`

---

## Quick sanity check (terminal)

```bash
python3 - <<'PY'
import json
from pathlib import Path
cat = json.loads(Path("scripts/catalog-prep/coach_archetype_catalog.json").read_text())
helm = json.loads(Path("scripts/catalog-prep/helm_catalog.json").read_text())
ids = {e["id"] for e in helm["catalog"]}
mapped = set(cat["mapping"].keys())
missing = ids - mapped
extra = mapped - ids
print("archetypes:", len(cat["archetypes"]))
print("mapped:", len(mapped), "expected:", len(ids))
print("missing:", len(missing), "extra:", len(extra))
if missing:
    print("sample missing:", list(missing)[:5])
PY
```

When validation passes, come back to Cursor to implement runtime resolver (plan Part 3).
