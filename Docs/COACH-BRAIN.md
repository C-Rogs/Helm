# Coach Brain: Deep Research Prompts

Cameron runs each prompt below in a separate Gemini deep research session. The agent outputs valid JSON matching the `MethodologyDocument` schema. After all seven sessions, merge outputs into one `methodology.json` and replace the placeholder bundle at `Helm/Resources/MethodologySeed/methodology.json`.

## Prompt Template (shared prefix per module session)

```
You are a sports-science researcher producing a structured knowledge base for a training-coach AI. Output ONLY valid JSON. No markdown, no prose outside the JSON. Every statement in topics must be backed by at least one evidence citation.

Schema:
{
  "modules": [{
    "id": "module-id",
    "title": "Module Title",
    "description": "one-sentence summary",
    "topicIDs": ["module-topic-slug"],
    "evidenceIDs": ["ev-module-topic-slug"],
    "autoAssign": { "phases": ["cut"]|["maintain"]|["gain"], "goals": ["keyword"], "always": false }
  }],
  "evidence": [{
    "id": "ev-module-topic",
    "title": "finding title",
    "summary": "2-3 sentences. What the research found. Practical application. Keep compact -- injected into LLM context every turn.",
    "citation": "Author (Year). Journal. DOI or PMID if available.",
    "url": "https://doi.org/...",
    "placeholder": false
  }],
  "topics": [{
    "id": "module-topic",
    "title": "topic title",
    "body": "3-4 short paragraphs max. Coaching-relevant summary. No filler. What the coach needs to know to apply this science.",
    "citationIDs": ["ev-module-topic"]
  }]
}

Constraints per module:
- 8-15 evidence records (compact is better -- they all go into LLM context)
- 4-8 topics
- Evidence IDs: ev-{module}-{topic-slug}
- Topic IDs: {module}-{topic-slug}
- autoAssign.phases: use ONLY "cut", "maintain", "gain"
- autoAssign.goals: short keywords matching likely athlete emphasis phrases
- autoAssign.always: true for modules every athlete needs
```

## Module Prompts

### 1. Hypertrophy

```
Module: hypertrophy / "Muscle Hypertrophy"
autoAssign: always=true (every athlete needs this)

Cover: MEV/MRV volume landmarks, weekly set progression, training frequency (2x vs 3x/week), exercise selection for hypertrophy, rep ranges (5-30), proximity to failure, rest intervals, stretch-mediated hypertrophy, partial ROM, drop sets and intensity techniques, volume titration from biofeedback, minimum effective dose, overreaching detection.

Coach lens: "Am I doing enough sets?", "Should I add a day?", "Is this exercise optimal for my goal?"
```

### 2. Nutrition

```
Module: nutrition / "Sports Nutrition"
autoAssign: always=true (every athlete needs this)

Cover: TDEE estimation and adaptive tracking, macro partitioning (protein 1.6-2.2 g/kg, fat minimums, carb periodization), peri-workout nutrition timing, bulking vs cutting rate limits (0.25-0.5% bodyweight/week), refeeds and diet breaks, micronutrient priorities, hydration, supplement evidence (creatine, caffeine, beta-alanine, protein timing), sleep-nutrition interaction, alcohol and recovery, flexible dieting.

Coach lens: "Am I eating enough to build muscle?", "How fast can I cut?", "Is this meal aligned with my phase?"
```

### 3. Recovery

```
Module: recovery / "Recovery and Readiness"
autoAssign: always=true (every athlete needs this)

Cover: HRV as readiness marker (rMSSD, SDNN, trend vs single-day), sleep architecture (deep sleep, REM, minimums), sleep hygiene, autonomic recovery post-training, deload types (volume, intensity, active rest), stress-life-recovery balance, subjective readiness (RPE, soreness, mood), heart rate recovery, cold exposure and hypertrophy interference, massage/compression evidence, travel effects.

Coach lens: "HRV dropped -- skip today?", "Slept 5 hours -- adjust?", "When should I deload?"
```

### 4. Strength

```
Module: strength / "Strength and Performance"
autoAssign: phases=["gain"], goals=["strength","power","peaking"]

Cover: RPE/RIR scales and calibration, periodization models (linear, block, DUP), specificity principle, load progression (double progression, dynamic double progression, APRE), velocity-based training, 1RM estimation (Epley, Brzycki), strength-hypertrophy relationship, rate of force development, accommodating resistance, potentiation, warm-up protocols, skill acquisition, concurrent training interference, peaking and tapering, failure training tradeoffs.

Coach lens: "Is my E1RM progressing?", "Should I test my 1RM?", "What RPE should this set feel like?"
```

### 5. Rehab

```
Module: rehab / "Pain, Injury, and Return to Training"
autoAssign: goals=["rehab","recovery","injury","pain"]

Cover: Pain science (nociception vs pain, central sensitization, fear-avoidance), load management (acute:chronic workload ratio), tendon rehab principles (progressive loading, isometric analgesia), return-to-training frameworks, exercise regression hierarchy (ROM -> load -> speed -> complexity), biopsychosocial model, imaging and pain correlation caveats, regional considerations (shoulder, low back, knee), warm-up and prehab evidence, movement screening limitations, scope of practice red flags.

Coach lens: "My shoulder hurts on press -- what do I do?", "Can I train through this?", "When is it safe to go heavy again?"
```

### 6. Endurance

```
Module: endurance / "Endurance and Concurrent Training"
autoAssign: goals=["cardio","endurance","conditioning","running"]

Cover: Energy system overview (ATP-PC, glycolytic, oxidative), concurrent training interference (AMPK vs mTOR signalling), programming endurance around hypertrophy (session order, proximity, intensity), conditioning for strength athletes (HIIT vs LISS, minimum effective dose), VO2max and health outcomes, heart rate zone training, running economy, cycling/rowing cross-training, breathing mechanics, fatigue management across modalities.

Coach lens: "Should I do cardio on rest days?", "Will running kill my gains?", "How much conditioning do I actually need?"
```

### 7. Science-Based Lifting

```
Module: lifting / "Science-Based Lifting"
autoAssign: always=true (every athlete lifts)

Cover: Progressive overload principles in practice (load, reps, density, ROM), biomechanics of common patterns (squat, hinge, press, pull, carry), bracing and intra-abdominal pressure, stance and grip variants with tradeoffs, range of motion quality vs load, tempo and eccentric control evidence, mind-muscle connection (when it helps, when it does not), form cues that transfer vs folklore cues, exercise technique teaching progressions, common technique faults and fixes, equipment setup (bar path, bench angle, cable height), bilateral vs unilateral work, stability demands vs output, when to chase perfect form vs when to accept ugly-but-safe working sets.

Do NOT rehash volume landmarks, mesocycle periodization, or RPE scales already covered by hypertrophy and strength modules. Focus on how the athlete executes lifts in the gym.

Coach lens: "Is my squat depth good enough?", "Should I pause at the bottom?", "Are my elbows flaring a problem?", "How do I brace for a heavy set?", "Is this cue science or gym lore?"
```

## Output Assembly

After all seven sessions complete, merge the JSON outputs into one `methodology.json`:

```json
{
  "seedVersion": 2,
  "placeholder": false,
  "modules": [ /* union of all seven module arrays */ ],
  "evidence": [ /* union of all seven evidence arrays */ ],
  "topics": [ /* union of all seven topic arrays */ ]
}
```

Replace `Helm/Resources/MethodologySeed/methodology.json` with this file. The app loads it at startup via `MethodologyBootstrap` which configures both `MethodologyEvidenceSupport` and `ResourceModuleIndex`.
