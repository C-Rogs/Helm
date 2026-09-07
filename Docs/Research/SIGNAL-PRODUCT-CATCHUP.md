# Signal product catch-up roadmap

> Full board vs BWS+/MacroFactor/Hevy/Fitbod/RP. Execute wave-by-wave from parent chat with Task subagents.
> Companion: `BWS-PLUS-VS-SIGNAL.md`.

## Execution model

- **Parent chat (this repo):** decisions, merge, build verify, docs.
- **Subagents:** implement one wave slice with full pasted context (no reliance on parent history).
- Cameron does **not** need separate agent chats unless he wants parallel personal experiments.

## Ceremony design (locked)

- **Check-in day:** user-selected weekday (Settings + Nutrition). Default Sunday local.
- **Math window:** always **rolling last 7 calendar days** ending at check-in (or “as of today” when previewing early). Do not switch engines to calendar-week ISO unless check-in day forces a display label.
- Same rolling-7 pattern for training week review volume ledger where relevant; “next week” preview can use schedule week-ahead.

## Waves

| Wave | Scope | Status |
|------|--------|--------|
| 1 | Rituals: nutrition check-in UI + training week review | **In tree** - shared weekday `helm.nutrition.checkInWeekday` (default Sunday); rolling 7d math; Train week review sheet; Nutrition check-in sheet + Settings picker; QA fixes (cutoff day unify, auto-present once, exclude clears mass, rolling-7 goals) |
| 2 | Journey: Progress tab, recomp card, onboarding rewrite, phase narrative | **In tree** - Progress 5th tab + hub; `PhaseNarrativeFormatter` + `RecompStoryCard`; onboarding Welcome → plan → body → Health → ready (Hevy/backfill → Settings) |
| 3 | Modifiers: Your-plan strip, muscle prioritizer (real volume), warm empties, inline explain | **In tree** - Train Your-plan strip → PlanBuilder; PlanKit +20% focus redistrib (1–3 muscles) + chip picker; warm empties; Explain on Dashboard ARC + Train volume |
| 4 | Form + celebration: exercise detail sheet, rest coaching, milestones | **In tree** - FORM|HISTORY exercise sheet; RestCoachingPolicy under UP NEXT + expiry prefs; quartile accessory toast (not prHit) + finish checkpoints |
| 5 | Thin content: demo links, pattern teasers, optional step goal; skip recipe CMS | Pending |

## Non-goals

Lesson CMS, recipe empire, Tron default, paywall, abandon instrument thesis.

## Commands

- `build Wave 1` … `build Wave 5` from parent
- Subagents: one slice per Task, full file paths + acceptance in prompt
