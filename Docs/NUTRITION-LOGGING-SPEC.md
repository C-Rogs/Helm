# Native food logging spec

> **Status:** Approved 2026-07-24 (interview). **Goal:** replace MyFitnessPal on Cameron's iPhone. Helm-native logging is source of truth; Apple Health receives write-through aggregates for ecosystem compatibility.

---

## 1. Goal

Helm becomes the sole daily food logger. Cameron deletes MFP after a 7-day soak (DT7). Native logging must cover:

- Repeat breakfasts via saved templates (photo when portions drift)
- Branded UK packaged foods (barcode + type-to-find)
- Generic UK produce and ingredients (on-device CoFID)
- Complex plates and leftovers (existing photo pipeline)
- Explicit alcohol and quick-add kcal
- Full meal history edit/delete and copy flows

Accuracy bar: ~90% of staples work on day one; manual/custom food and offline queue handle the rest.

---

## 2. User stories (ranked)

| # | Story | Acceptance |
|---|-------|------------|
| 1 | Log my work breakfast in ≤2 taps on a stable day | Saved template logs all items with last-used portions; totals update targets card immediately |
| 2 | Scan or search a UK branded snack (Grenade, Arla, PhD) | Barcode or text search resolves via Open Food Facts; portion defaults to last-used serving |
| 3 | Search generic food offline (pineapple, sourdough) | Full CoFID bundle searchable on-device; offline banner when OFF unavailable |
| 4 | Log mixed leftovers without barcode | Photo → confirm sheet → save (existing path); or manual line-item builder |
| 5 | Log beer explicitly | Alcohol entry with drink preset + count; kcal counts toward TDEE; macro gap only for untracked remainder |
| 6 | Fix a wrong scan from yesterday | Edit past meal; GRDB + HealthKit samples updated; totals reconcile |
| 7 | Copy Tuesday breakfast to today | Copy single meal bucket or copy full yesterday into today |
| 8 | Log while offline at work | CoFID + cached recents work; new branded search queues pending import; photo works on-device |
| 9 | Brief MFP overlap without double-count | Helm + MFP both writing to HealthKit during transition; dedup policy prevents 2× kcal |
| 10 | Quick-add 740 kcal beer without macros | Kcal-only entry counts toward TDEE; surfaces in macro gap |

---

## 3. Entry modes

### 3.1 Search (CoFID + OFF)

**Flow:** FAB → Search → type query → results list (local CoFID first, OFF when online) → pick food → portion step → pick bucket → save.

**Taps (repeat food with portion memory):** FAB → Search → tap recent → confirm → save (~3).

**Error states:**

| State | UX |
|-------|-----|
| Offline, CoFID miss | Banner: full library unavailable; suggest photo or custom food |
| Online, OFF miss | "Not found" + create custom food CTA |
| Network error | Retry + offline fallback to CoFID/recents |

### 3.2 Barcode (OFF)

**Flow:** FAB → Barcode → scan → OFF product lookup → cache locally → portion step → bucket → save.

**Miss:** manual entry form pre-filled with barcode; queue `PendingFoodImport` if offline.

### 3.3 Photo (shipped M9.x)

Unchanged production path. After M14.1, grounded lookup resolves against **CoFID** not USDA. Manual log and photo share `MealLineItemEditor` (extracted from `PhotoMealConfirmSheet`).

### 3.4 Quick-add kcal

**Flow:** FAB → Quick add → kcal field (+ optional label) → bucket → save.

Counts toward TDEE. No P/C/F unless user expands "add macros".

### 3.5 Alcohol

**Flow:** FAB → Alcohol (or bucket + alcohol type) → preset drink (beer, wine, spirit) × quantity → kcal computed → save.

Explicit alcohol kcal; `MacroGapCalculator` handles remainder on days with mixed logging.

### 3.6 Saved meal template

**Flow:** Save current bucket as template → name → log template (1 tap) → optional confirm → save.

Hybrid default: template daily; photo when portions drift; "update template from this log" after edit.

### 3.7 Copy meal / copy yesterday

**Copy meal:** bucket header menu → Copy to today (or pick day).

**Copy yesterday:** day menu → Copy all meals to today.

### 3.8 Recents

Recents list on search screen: last 50 unique foods with last portion. Tapping logs with remembered serving.

---

## 4. Data model

### 4.1 Core extensions

```swift
// MealRecord extensions (Core)
enum MealBucket: String, Codable { case breakfast, lunch, dinner, snacks }
enum MealRecord.Source { case healthKit, manual, photo, barcode, quickAdd, alcohol, template }

// New: FoodProductRef - stable ID across CoFID, OFF, custom
struct FoodProductRef: Sendable, Codable {
    enum Origin: String, Codable { case cofid, openFoodFacts, custom }
    let origin: Origin
    let externalID: String  // CoFID code, OFF barcode, or custom UUID
    let displayName: String
}

struct MealLineItemRecord: Sendable, Codable, Identifiable {
    let id: UUID
    let mealID: UUID
    let foodRef: FoodProductRef
    let grams: Double
    let servingLabel: String?  // e.g. "1 pot"
    let energyKcal, proteinG, carbsG, fatG: Double
    let sortOrder: Int
}

struct FoodPortionPreference: Sendable, Codable {
    let foodRef: FoodProductRef
    let grams: Double
    let servingLabel: String?
    let lastUsedAt: Date
}

struct MealTemplate: Sendable, Codable, Identifiable {
    let id: UUID
    let name: String
    let bucket: MealBucket
    let lineItems: [MealLineItem]  // snapshot portions
    let updatedAt: Date
}

struct PendingFoodImport: Sendable, Codable, Identifiable {
    let id: UUID
    let createdAt: Date
    let barcode: String?
    let photoMealID: UUID?
    let provisionalLineItems: [MealLineItem]
    let status: Status  // pending, resolved, failed
}
```

### 4.2 GRDB migration `v10_food_logging`

New tables:

| Table | Purpose |
|-------|---------|
| `meal_line_item` | Line items per meal (FK `meal.id`) |
| `food_product_cache` | OFF/CoFID/custom product snapshots |
| `food_portion_preference` | Last-used portion per `food_ref` |
| `meal_template` + `meal_template_item` | Saved meals |
| `pending_food_import` | Offline / failed lookup queue |
| `food_log_recent` | Denormalised recents for fast search UI |

`meal` table additions (migration alters):

- `bucket TEXT NOT NULL DEFAULT 'snacks'`
- `meal_source` enum expansion via `source` column values

### 4.3 CoFID bundle

- **Source:** McCance & Widdowson's Composition of Foods Integrated Dataset 2021 (UK Government OGL).
- **Ship:** full dataset (~2,900 foods) as compressed JSON in `NutritionKit/Resources/cofid_foods.json`.
- **Replaces:** USDA SR Legacy subset from M9.4 (removed in M14.1).
- **Record shape:** reuse `NutritionFoodRecord` with `cofidCode` in `fdcId` field (rename to `foodCode` in M14.1 if agent chooses; alias acceptable).
- **Attribution:** CoFID + OGL credit in Sources / Methodology screen.

---

## 5. Food resolution chain

```
User query or barcode
        │
        ▼
┌───────────────────┐
│ 1. Recents cache  │── hit ──► FoodProductRef + last portion
└─────────┬─────────┘
          │ miss
          ▼
┌───────────────────┐
│ 2. CoFID (local)  │── hit ──► per-100g macros, confidence: exact/synonym/partial
└─────────┬─────────┘
          │ miss / branded
          ▼
┌───────────────────┐
│ 3. OFF API        │── hit ──► cache in food_product_cache, confidence: branded
│ (online only)     │
└─────────┬─────────┘
          │ miss
          ▼
┌───────────────────┐
│ 4. Custom food    │── user-entered per-100g or per-serving
└───────────────────┘
```

**Confidence levels:** `exact | synonym | partial | branded | custom | fallback`

Photo pipeline: vision decomposition → CoFID resolve per line item (same `NutritionLookup`).

**Offline:** steps 1–2 only; banner + suggest photo; queue step 3 for background.

---

## 6. HealthKit write contract

Unchanged sample types per meal write:

- `HKQuantityTypeIdentifier.dietaryEnergyConsumed` (kcal)
- `dietaryProtein`, `dietaryCarbohydrates`, `dietaryFatTotal`

**Metadata (existing keys):**

- `com.cameronro.helm.meal_id` - UUID linking four samples
- `com.cameronro.helm.meal_name`
- `com.cameronro.helm.meal_source` - `manual | photo | barcode | quickAdd | alcohol | template`

**Source bundle:** Helm app bundle ID; `IngestSampleFilter` excludes own writes from anchored ingest.

**Edit semantics:**

- Edit meal → delete old four samples by `meal_id` metadata query → write new four samples (same `meal_id` or new with GRDB FK update).
- Delete meal → delete HK samples + GRDB rows + line items.

**GRDB is rich source; HK is aggregate write-through** for Apple Health ecosystem and TDEE ingest path continuity.

### MFP coexistence (transition)

During overlap phase Cameron runs both apps. Policy (implement in M14.8):

1. **Primary logger toggle** in Settings → Nutrition: `Helm only | Merge external` (default `Merge external` during transition).
2. **Merge mode:** ingest external HK dietary samples (MFP bundle) for days where Helm has no meals; for overlapping time windows within ±15 min and similar kcal (±10%), prefer Helm entry.
3. **Helm only:** ignore non-Helm dietary sources except trend weight.

Exact dedup thresholds are implementation-tunable; fixture tests required.

---

## 7. Integration points

| Component | Role |
|-----------|------|
| `NutritionEngine` | Unchanged interface; `NutritionActualResolver` reads GRDB meals + HK aggregates |
| `NutritionTrendBuilder` | TDEE uses total logged kcal including quick-add and alcohol |
| `MacroGapCalculator` | Gap after explicit alcohol subtracted |
| `PhotoMealService` | Unchanged; lookup switches to CoFID |
| `ManualMealService` (new) | Search/barcode/template/quick-add/alcohol → GRDB + HK |
| `NutritionBootstrap` | Wire resolver, OFF client, meal services |
| `NutritionView` | Targets card + bucket meal lists + FAB |
| `NutritionDaySummaryCard` | Unchanged hero; meal detail drill-down optional M14.6+ |
| Coach context | Meal names + bucket totals in daily snapshot; alcohol narratable |
| Dashboard card | Unchanged wiring via `NutritionService` |

---

## 8. Non-goals (v1)

- Recipe builder (multi-ingredient recipes as first-class entity)
- Meal planning / weekly prep calendar
- Social / sharing meals
- Micronutrients (sodium, vitamins, etc.)
- Restaurant menu lookup
- Water tracking
- AI meal suggestions
- Voice logging outside Chat coach dictate

---

## 9. Phased delivery (PLAN.md `M14.x`)

See `PLAN.md` § M14 Native food logging. Summary:

| Section | Deliverable |
|---------|-------------|
| M14.1 | CoFID bundle replaces USDA |
| M14.2 | GRDB v10 food-logging schema + Core models |
| M14.3 | Food resolver + OFF client + product cache |
| M14.4 | ManualMealService + HK write-through + quick-add/alcohol |
| M14.5 | Search + barcode UI + shared MealLineItemEditor |
| M14.6 | Nutrition tab buckets + multi-action FAB + tip |
| M14.7 | Recents, portion memory, templates, copy meal |
| M14.8 | Edit/delete history + HK sync + MFP dedup |
| M14.9 | Offline pending import queue + background resolve |

**Device gate:** DT7 - MFP deleted 7 days.

**First build:** `build M14.1`

---

## 10. Risks

| Risk | Mitigation |
|------|------------|
| CoFID bundle size | Compress JSON; measure <8 MB; lazy load index if needed |
| OFF UK coverage gaps | Personal cache grows; custom food; 90% bar not 100% |
| OFF rate limits / API changes | Cache aggressively; user-agent per OFF guide; no telemetry |
| MFP double-count during overlap | Dedup policy + Settings toggle; DT7 validates |
| HK edit/delete race with anchored ingest | Serialize via HealthKitIngest actor; meal_id metadata query |
| CoFID OGL attribution | Sources screen credit |
| Offline queue complexity | Ship M14.9 last; core logging works online-first |
| M9.4 USDA tests | Rewrite fixtures for CoFID in M14.1 |

---

## Appendix: Interview decisions log

- Template hybrid (default template, photo on drift)
- OFF API + full CoFID on-device (no USDA)
- Offline: local DB + banner + photo queue
- Retroactive edit all foods
- Smart portions + remember last serving
- Four meal buckets
- Edit/delete/copy history all in v1
- GRDB + HK write-through
- MFP overlap with dedup
- Quick-add kcal → TDEE
- Explicit alcohol + gap fallback
- Targets-first layout, multi-action FAB, one-time tip only
- Full MVP scope, good-enough accuracy
- DT7 new gate; photo + manual share line-item editor
