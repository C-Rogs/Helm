#!/usr/bin/env python3
"""Convert McCance & Widdowson CoFID 2021 Excel to Helm cofid_foods.json."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_XLSX = Path("/tmp/cofid-build/CoFID_2021.xlsx")
OUTPUT = ROOT / "Packages/Domain/Sources/NutritionKit/Resources/cofid_foods.json"

# Common search terms → CoFID food code (McCance & Widdowson 2021).
SYNONYM_OVERLAY: dict[str, str] = {
    "grilled chicken breast": "18-323",
    "chicken breast grilled": "18-323",
    "chicken breast": "18-323",
    "roasted chicken breast": "18-323",
    "white rice cooked": "11-862",
    "white rice": "11-862",
    "steamed rice": "11-862",
    "cooked white rice": "11-862",
    "cooking oil": "17-686",
    "vegetable oil": "17-686",
    "salmon grilled": "16-357",
    "grilled salmon": "16-357",
    "salmon fillet": "16-357",
    "baked salmon": "16-357",
    "brown rice cooked": "11-869",
    "cooked brown rice": "11-869",
    "egg whole": "12-940",
    "hard boiled egg": "12-940",
    "boiled egg": "12-940",
    "whole egg": "12-940",
    "greek yogurt": "12-555",
    "plain greek yogurt": "12-555",
    "nonfat greek yogurt": "12-555",
    "oatmeal": "11-1107",
    "cooked oatmeal": "11-1107",
    "oats cooked": "11-1107",
    "porridge": "11-1107",
    "banana": "14-318",
    "bananas raw": "14-318",
    "raw banana": "14-318",
    "broccoli": "13-503",
    "cooked broccoli": "13-503",
    "steamed broccoli": "13-503",
    "sweet potato": "13-671",
    "baked sweet potato": "13-671",
    "sweet potato cooked": "13-671",
    "ground beef": "18-470",
    "lean ground beef": "18-470",
    "beef mince": "18-470",
    "pasta cooked": "11-1129",
    "cooked pasta": "11-1129",
    "spaghetti cooked": "11-1129",
    "penne cooked": "11-1129",
    "avocado": "14-386",
    "sliced avocado": "14-386",
    "whey protein": "generic_protein_shake",
    "protein powder": "generic_protein_shake",
    "whey protein powder": "generic_protein_shake",
    "almond butter": "generic_almond_butter",
    "natural almond butter": "generic_almond_butter",
    "cottage cheese": "12-539",
    "low fat cottage cheese": "12-550",
    "tuna canned": "16-416",
    "canned tuna": "16-416",
    "tuna in water": "16-416",
    "olive oil": "17-038",
    "mixed greens salad": "13-520",
    "salad greens": "13-520",
    "romaine lettuce": "13-520",
    "lettuce": "13-520",
    "salad dressing": "generic_sauce",
    "dressing": "generic_sauce",
    "vinaigrette": "generic_sauce",
    "butter": "generic_butter",
    "hidden butter": "generic_butter",
    "cream": "generic_cream",
    "heavy cream": "generic_cream",
    "honey": "generic_honey",
    "maple syrup": "generic_honey",
    "protein bar": "generic_protein_bar",
    "granola bar": "generic_protein_bar",
    "energy bar": "generic_protein_bar",
    "smoothie": "generic_smoothie",
    "fruit smoothie": "generic_smoothie",
    "wrap": "generic_wrap",
    "sandwich": "generic_wrap",
    "sub sandwich": "generic_wrap",
    "sushi roll": "generic_sushi",
    "sushi": "generic_sushi",
    "french fries": "generic_fries",
    "fries": "generic_fries",
    "chips": "generic_fries",
    "bacon": "generic_bacon",
    "cooked bacon": "generic_bacon",
    "ham": "generic_ham",
    "deli ham": "generic_ham",
    "american cheese": "generic_cheese_slice",
    "cheese slice": "generic_cheese_slice",
    "apple": "generic_apple",
    "apples raw": "generic_apple",
    "berries": "generic_berries",
    "strawberries": "generic_berries",
    "blueberries": "generic_berries",
    "orange": "generic_orange",
    "oranges": "generic_orange",
    "peanuts": "generic_peanut",
    "cereal": "generic_cereal",
    "granola": "generic_cereal",
    "quinoa cooked": "generic_quinoa",
    "quinoa": "generic_quinoa",
    "couscous cooked": "generic_couscous",
    "couscous": "generic_couscous",
    "hummus": "generic_hummus",
    "salsa": "generic_salsa",
    "guacamole": "generic_guacamole",
    "ice cream": "generic_ice_cream",
    "vanilla ice cream": "generic_ice_cream",
    "protein shake": "generic_protein_shake",
    "stir fry": "generic_mixed",
    "curry": "generic_mixed",
    "casserole": "generic_mixed",
    "bowl": "generic_mixed",
    "mixed dish": "generic_mixed",
    "pineapple": "14-376",
    "sourdough": "11-1145",
    "sourdough bread": "11-1145",
}

GENERIC_FOODS: list[dict] = [
    {
        "fdcId": "generic_mixed",
        "description": "Mixed dish, average UK meal",
        "synonyms": ["mixed dish", "stir fry", "curry", "casserole", "bowl"],
        "per100g": {"kcal": 180, "proteinG": 10.0, "carbsG": 15.0, "fatG": 9.0},
    },
    {
        "fdcId": "generic_sauce",
        "description": "Sauce, salad dressing, average",
        "synonyms": ["salad dressing", "dressing", "vinaigrette"],
        "per100g": {"kcal": 430, "proteinG": 1.0, "carbsG": 8.0, "fatG": 45.0},
    },
    {
        "fdcId": "generic_butter",
        "description": "Butter, without salt",
        "synonyms": ["butter", "hidden butter"],
        "per100g": {"kcal": 717, "proteinG": 0.9, "carbsG": 0.1, "fatG": 81.1},
    },
    {
        "fdcId": "generic_cream",
        "description": "Cream, double, average",
        "synonyms": ["cream", "heavy cream", "whipping cream"],
        "per100g": {"kcal": 340, "proteinG": 2.1, "carbsG": 2.8, "fatG": 36.1},
    },
    {
        "fdcId": "generic_honey",
        "description": "Honey, average",
        "synonyms": ["honey", "maple syrup"],
        "per100g": {"kcal": 304, "proteinG": 0.3, "carbsG": 82.4, "fatG": 0},
    },
    {
        "fdcId": "generic_protein_bar",
        "description": "Cereal bar, average",
        "synonyms": ["protein bar", "granola bar", "energy bar"],
        "per100g": {"kcal": 471, "proteinG": 10.1, "carbsG": 64.4, "fatG": 20.4},
    },
    {
        "fdcId": "generic_smoothie",
        "description": "Smoothie, fruit, average",
        "synonyms": ["fruit smoothie", "smoothie"],
        "per100g": {"kcal": 65, "proteinG": 0.8, "carbsG": 15.0, "fatG": 0.3},
    },
    {
        "fdcId": "generic_wrap",
        "description": "Sandwich, white bread, average filling",
        "synonyms": ["wrap", "sandwich", "sub sandwich"],
        "per100g": {"kcal": 218, "proteinG": 12.0, "carbsG": 24.0, "fatG": 8.0},
    },
    {
        "fdcId": "generic_sushi",
        "description": "Sushi, assorted, average",
        "synonyms": ["sushi roll", "sushi"],
        "per100g": {"kcal": 130, "proteinG": 6.0, "carbsG": 22.0, "fatG": 2.0},
    },
    {
        "fdcId": "generic_fries",
        "description": "Potatoes, chips, fried",
        "synonyms": ["french fries", "fries", "chips"],
        "per100g": {"kcal": 312, "proteinG": 3.4, "carbsG": 41.4, "fatG": 14.7},
    },
    {
        "fdcId": "generic_bacon",
        "description": "Bacon, back, grilled",
        "synonyms": ["bacon", "cooked bacon"],
        "per100g": {"kcal": 541, "proteinG": 37.0, "carbsG": 1.4, "fatG": 41.8},
    },
    {
        "fdcId": "generic_ham",
        "description": "Ham, cooked, sliced",
        "synonyms": ["ham", "deli ham"],
        "per100g": {"kcal": 145, "proteinG": 21.0, "carbsG": 1.5, "fatG": 5.5},
    },
    {
        "fdcId": "generic_cheese_slice",
        "description": "Cheese, processed, average",
        "synonyms": ["american cheese", "cheese slice"],
        "per100g": {"kcal": 371, "proteinG": 18.0, "carbsG": 3.7, "fatG": 31.3},
    },
    {
        "fdcId": "generic_apple",
        "description": "Apples, eating, raw, flesh and skin",
        "synonyms": ["apple", "apples raw"],
        "per100g": {"kcal": 52, "proteinG": 0.3, "carbsG": 13.8, "fatG": 0.2},
    },
    {
        "fdcId": "generic_berries",
        "description": "Strawberries, raw",
        "synonyms": ["berries", "strawberries", "blueberries"],
        "per100g": {"kcal": 32, "proteinG": 0.7, "carbsG": 7.7, "fatG": 0.3},
    },
    {
        "fdcId": "generic_orange",
        "description": "Oranges, flesh only",
        "synonyms": ["orange", "oranges"],
        "per100g": {"kcal": 47, "proteinG": 0.9, "carbsG": 11.8, "fatG": 0.1},
    },
    {
        "fdcId": "generic_peanut",
        "description": "Peanuts, plain",
        "synonyms": ["peanuts"],
        "per100g": {"kcal": 567, "proteinG": 25.8, "carbsG": 16.1, "fatG": 49.2},
    },
    {
        "fdcId": "generic_cereal",
        "description": "Breakfast cereal, average",
        "synonyms": ["cereal", "granola"],
        "per100g": {"kcal": 489, "proteinG": 10.1, "carbsG": 64.0, "fatG": 22.0},
    },
    {
        "fdcId": "generic_quinoa",
        "description": "Quinoa, boiled in unsalted water",
        "synonyms": ["quinoa cooked", "quinoa"],
        "per100g": {"kcal": 120, "proteinG": 4.4, "carbsG": 21.3, "fatG": 1.9},
    },
    {
        "fdcId": "generic_couscous",
        "description": "Couscous, plain, cooked",
        "synonyms": ["couscous cooked", "couscous"],
        "per100g": {"kcal": 112, "proteinG": 3.8, "carbsG": 23.2, "fatG": 0.2},
    },
    {
        "fdcId": "generic_hummus",
        "description": "Hummus, commercial",
        "synonyms": ["hummus"],
        "per100g": {"kcal": 166, "proteinG": 7.9, "carbsG": 14.3, "fatG": 9.6},
    },
    {
        "fdcId": "generic_salsa",
        "description": "Salsa, tomato based",
        "synonyms": ["salsa"],
        "per100g": {"kcal": 36, "proteinG": 1.5, "carbsG": 7.0, "fatG": 0.2},
    },
    {
        "fdcId": "generic_guacamole",
        "description": "Guacamole, homemade",
        "synonyms": ["guacamole"],
        "per100g": {"kcal": 167, "proteinG": 2.0, "carbsG": 8.5, "fatG": 15.4},
    },
    {
        "fdcId": "generic_ice_cream",
        "description": "Ice cream, dairy, vanilla",
        "synonyms": ["ice cream", "vanilla ice cream"],
        "per100g": {"kcal": 207, "proteinG": 3.5, "carbsG": 23.6, "fatG": 11.0},
    },
    {
        "fdcId": "generic_almond_butter",
        "description": "Nut butter, almond, no added salt",
        "synonyms": ["almond butter", "natural almond butter"],
        "per100g": {"kcal": 614, "proteinG": 21.2, "carbsG": 6.5, "fatG": 55.5},
    },
    {
        "fdcId": "generic_protein_shake",
        "description": "Protein supplement, whey based, powder",
        "synonyms": ["whey protein", "protein powder", "whey protein powder", "protein shake"],
        "per100g": {"kcal": 352, "proteinG": 78.1, "carbsG": 6.3, "fatG": 1.6},
    },
]


def normalize(text: str) -> str:
    lowered = text.lower().replace(",", " ").replace("-", " ")
    tokens = re.findall(r"[a-z0-9]+", lowered)
    return " ".join(tokens).strip()


def as_float(value) -> float:
    if value is None or (isinstance(value, float) and pd.isna(value)):
        return 0.0
    try:
        return float(value)
    except (TypeError, ValueError):
        return 0.0


def auto_synonyms(description: str) -> list[str]:
    synonyms: set[str] = set()
    normalized = normalize(description)
    if normalized:
        synonyms.add(normalized)

    parts = [part.strip() for part in description.split(",") if part.strip()]
    if len(parts) >= 2:
        synonyms.add(normalize(parts[0]))
        synonyms.add(normalize(parts[-1]))
        synonyms.add(normalize(" ".join(reversed(parts[0].split()))))

    without_parenthetical = re.sub(r"\([^)]*\)", "", description)
    cleaned = normalize(without_parenthetical)
    if cleaned:
        synonyms.add(cleaned)

    return sorted(s for s in synonyms if s and s != normalized)


def load_cofid_foods(xlsx_path: Path) -> list[dict]:
    df = pd.read_excel(xlsx_path, sheet_name="1.3 Proximates", header=None)
    data = df.iloc[3:].copy()
    data.columns = [
        "code",
        "name",
        "description",
        "group",
        "previous",
        "references",
        "footnote",
        "water",
        "nitrogen",
        "protein",
        "fat",
        "carb",
        "kcal",
        "kj",
        *range(data.shape[1] - 14),
    ]

    foods: list[dict] = []
    by_code: dict[str, dict] = {}

    for _, row in data.iterrows():
        code = str(row["code"]).strip() if pd.notna(row["code"]) else ""
        name = str(row["name"]).strip() if pd.notna(row["name"]) else ""
        if not code or not name:
            continue

        protein = as_float(row["protein"])
        fat = as_float(row["fat"])
        carb = as_float(row["carb"])
        kcal = as_float(row["kcal"])
        if kcal <= 0 and (protein > 0 or fat > 0 or carb > 0):
            kcal = protein * 4 + carb * 4 + fat * 9

        record = {
            "fdcId": code,
            "description": name,
            "synonyms": auto_synonyms(name),
            "per100g": {
                "kcal": round(kcal, 1),
                "proteinG": round(protein, 1),
                "carbsG": round(carb, 1),
                "fatG": round(fat, 1),
            },
        }
        foods.append(record)
        by_code[code] = record

    for synonym, code in SYNONYM_OVERLAY.items():
        target = by_code.get(code)
        if target is None:
            continue
        normalized_synonym = normalize(synonym)
        if normalized_synonym and normalized_synonym not in target["synonyms"]:
            target["synonyms"].append(normalized_synonym)

    reserved_synonyms = {normalize(synonym) for synonym in SYNONYM_OVERLAY}
    for record in foods:
        record["synonyms"] = [
            synonym
            for synonym in record["synonyms"]
            if normalize(synonym) not in reserved_synonyms
            or normalize(synonym) in {normalize(s) for s in SYNONYM_OVERLAY if SYNONYM_OVERLAY[s] == record["fdcId"]}
        ]

    existing_codes = {food["fdcId"] for food in foods}
    for generic in GENERIC_FOODS:
        code = generic["fdcId"]
        if code in existing_codes:
            target = by_code[code]
            for synonym in generic["synonyms"]:
                normalized_synonym = normalize(synonym)
                if normalized_synonym not in target["synonyms"]:
                    target["synonyms"].append(normalized_synonym)
            continue
        foods.append(generic)
        by_code[code] = generic

    return foods


def main() -> int:
    xlsx_path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_XLSX
    if not xlsx_path.exists():
        print(f"Missing CoFID workbook: {xlsx_path}", file=sys.stderr)
        return 1

    foods = load_cofid_foods(xlsx_path)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    payload = {"foods": foods}
    encoded = json.dumps(payload, separators=(",", ":"), ensure_ascii=False)
    OUTPUT.write_text(encoded, encoding="utf-8")

    size_mb = OUTPUT.stat().st_size / (1024 * 1024)
    print(f"Wrote {len(foods)} foods to {OUTPUT} ({size_mb:.2f} MB)")
    if size_mb >= 8:
        print("WARNING: bundle exceeds 8 MB target", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
