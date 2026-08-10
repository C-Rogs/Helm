# Data safety

Canonical reference for Helm's data ownership, backup behaviour, and restore semantics. Frozen at M1.2 for export/HealthKit semantics; iCloud backup policy updated to **excluded** (schema hardening / HealthKit re-ingest). Training-history JSON + Hevy CSV import added for prescription-relevant restore without a full database file. Opt-in **iCloud Drive sync** added for profile/engine config and optional 90-day workout history (survives app delete/reinstall on the same Apple ID).

---

## System of record

The GRDB store at `Application Support/Helm/helm.sqlite` is the system of record for all Helm-derived health and training data (daily metrics, body composition, sleep, nutrition, workouts, chat, and later tables as migrations land). HealthKit remains the source of truth for raw samples; Helm ingests into GRDB and computes on top of it.

---

## iCloud device backup

**Decision: excluded.**

The `Application Support/Helm/` directory is marked `isExcludedFromBackup = true` at creation time (`iCloudBackupPolicy.default`). HealthKit re-backfill rebuilds health-derived rows after a fresh install or new device. Intentional offline copies use **Settings > Data & Backup** export, not iCloud device backup.

Keychain items (API keys) follow Apple's Keychain backup rules separately; they are not part of the SQLite file.

Opt-in: callers may still pass `backupPolicy: .included` to `DatabaseLocation.defaultDatabaseURL` for local experiments.

---

## iCloud Drive sync (opt-in)

Separate from device backup. Writes JSON into the app ubiquity container (`iCloud.com.cameronro.helm` / `Documents/HelmBackup/`).

| Toggle | File | Contents |
|---|---|---|
| Sync profile & engine config | `helm-profile.json` | Memory profile, body profile, training plan settings, mesocycle JSON, onboarding completed flag |
| Include workout history (90 days) | `helm-training-history.json` | Same schema as Training History export (`TrainingHistoryExport` v1) |

- **Conflicts:** last-write-wins via profile `updatedAt`.
- **Size:** Settings shows live byte estimates for profile and history (session count included).
- **After app delete:** UserDefaults toggles are wiped. On next launch, if local looks empty and iCloud has a profile file, Helm restores automatically and re-enables the toggles.
- **Manual:** Back Up Now / Restore from iCloud on the Data & Backup screen.
- Debounced push after profile/plan/body saves, completed workouts (when history on), onboarding complete, and backgrounding.

PBs are not stored separately; restoring 90-day history rebuilds them from sessions.

---

## Song tempo lookup (opt-in)

**Default: off.** Toggle at **Settings > Spotify > Song tempo**.

Only local-library tracks arrive with a BPM tag (`MPMediaItemPropertyBeatsPerMinute`). Spotify App Remote exposes no tempo, Spotify retired the Web API `/audio-features` endpoint in November 2024, and the Apple Music catalog has no tempo field, so tempo for streamed tracks can only come from a name-based catalog lookup.

| Item | Behaviour |
|---|---|
| Providers | ReccoBeats audio features for Spotify track IDs, then Deezer public catalog (`api.deezer.com`) as fallback; no key or account |
| Sent off device | Spotify track ID when available; otherwise track title and artist only, for tracks with no BPM tag |
| Never sent | Workout, health, session, or account data |
| Stored | Resolved tempo in UserDefaults (`helm.songTempo.cache.tempos`), misses retried after 14 days |
| Clearing | **Clear cached tempos** on the same screen |

Coverage is partial and provider-dependent. Exact Spotify track IDs provide substantially better coverage than title/artist matching; tracks without a tempo still render as spans on the session timeline, so the chart degrades rather than emptying. Lookup is capped per summary render and bounded by a time budget, so the finish summary never waits on the network.

---

## Manual export

Available from **Settings > Data & Backup**:

| Action | Output | Contents |
|---|---|---|
| Export Database | `.sqlite` file via share sheet | Checkpointed GRDB backup (SQLite backup API, consistent snapshot) |
| Export Diagnostics | `.zip` file via share sheet | Ring buffer + OSLog extract per `Docs/DIAGNOSTICS.md` |
| Export Full Backup | `.zip` file via share sheet | `helm.sqlite` + diagnostics bundle files |
| Export Training History | `.json` via share sheet | Last ~90 days of completed sessions, sets, custom exercises, and aliases (`TrainingHistoryExport` schema v1) |

Exports land wherever the share sheet sends them (AirDrop, Files, Mail). Nothing is uploaded automatically except opt-in iCloud Drive sync above.

Prefer **Training History JSON** or **iCloud sync** for wipe/reinstall recovery of prescription inputs (prior weights, weekly volume, familiar exercises). Full sqlite remains for rare full-device forensics; it is large because it also holds health ingest, food cache, and chat.

---

## Restore semantics

### iCloud Drive (in-app)

1. Enable **Sync profile & engine config** (and optionally workout history) under Settings > Data & Backup.
2. Back Up Now, or wait for automatic debounced push after saves / finished workouts.
3. Delete app and reinstall (same Apple ID, iCloud Drive on): launch restores profile/engine config; history imports if that file was present.
4. Or tap **Restore from iCloud** for a forced pull (last-write-wins overwrite of profile fields; history import stays idempotent by session id).

### Training History JSON (in-app)

1. Settings > Data & Backup > **Import Training History**.
2. Pick a previously exported `helm-training-history-*.json` from Files / AirDrop.
3. Helm upserts custom exercises and aliases, then inserts completed sessions whose IDs are not already present (idempotent).
4. HealthKit data is unchanged; readiness still comes from HealthKit re-backfill.

### Hevy workout CSV (in-app)

1. Export workouts from Hevy (CSV).
2. Settings > Data & Backup > **Import Hevy CSV**.
3. Helm clips to the **last 90 days** relative to the newest session in the file, skips cardio rows without reps, and previews exercise-name mappings.
4. On confirm, sessions land as completed `source=import` history with deterministic IDs (`hevy-…`) so re-import skips duplicates.

### iCloud device restore (new or replaced iPhone)

1. `helm.sqlite` is **not** restored from iCloud device backup (directory excluded).
2. On first launch, GRDB starts empty (or from whatever is already on disk) and migrations run.
3. **HealthKit anchor cursors do not survive a device change.** Anchors are device-specific. After restore / reinstall, ingest cursors are treated as missing and reset to "fetch from beginning of window".
4. **Re-backfill runs** (`BackfillService`): the bounded HealthKit window is re-fetched and merged idempotently into GRDB.
5. Helm-only data not present in HealthKit (logged workouts, chat, food templates, coach state, etc.) does **not** come back from device backup. Use iCloud Drive sync, Training History JSON, Hevy CSV, or a prior full database export if that history matters.

### Manual database file replacement (advanced)

If Cameron copies an exported `helm.sqlite` over the live file (e.g. via Files on a jailbroken path, or Xcode device container):

1. Quit Helm completely before replacing the file.
2. Replace `helm.sqlite` (and delete `helm.sqlite-wal` / `helm.sqlite-shm` if present so the next open starts clean).
3. On next launch, migrations run if the file is from an older schema version.
4. HealthKit anchors are **not** in the SQLite file; they reset the same as a device restore (step 3–4 above).
5. If the replaced file is from a **newer** schema than the installed app, migration will fail safely; use a matching app version or a file from the same or older schema.

There is still no in-app full-database swap UI; Training History JSON and iCloud Drive sync are the supported light restore paths.

### What manual export / iCloud sync does *not* guarantee

- **Cross-device HealthKit sync**: HealthKit data on the new device may differ from the old device. GRDB holds what was ingested on the source device; backfill re-reads what HealthKit exposes on the target device.
- **API keys**: Keychain; re-enter on a fresh install unless restored via encrypted Keychain backup.
- **Chat / nutrition / food log**: Not included in iCloud Drive profile or 90-day history sync.
- **Mesocycle** is included in profile sync; coach chat is not.

---

## Related docs

- `Docs/DIAGNOSTICS.md`: log export bundle schema and redaction rules
- `PLAN.md`: locked decision on manual export from M1; iCloud exclusion supersedes the original M1.2 "included" note
