# Data safety

Canonical reference for Helm's data ownership, backup behaviour, and restore semantics. Frozen at M1.2 for export/HealthKit semantics; iCloud backup policy updated to **excluded** (schema hardening / HealthKit re-ingest). Training-history JSON + Hevy CSV import added for prescription-relevant restore without a full database file.

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

## Manual export

Available from **Settings > Data & Backup**:

| Action | Output | Contents |
|---|---|---|
| Export Database | `.sqlite` file via share sheet | Checkpointed GRDB backup (SQLite backup API, consistent snapshot) |
| Export Diagnostics | `.zip` file via share sheet | Ring buffer + OSLog extract per `Docs/DIAGNOSTICS.md` |
| Export Full Backup | `.zip` file via share sheet | `helm.sqlite` + diagnostics bundle files |
| Export Training History | `.json` via share sheet | Last ~90 days of completed sessions, sets, custom exercises, and aliases (`TrainingHistoryExport` schema v1) |

Exports land wherever the share sheet sends them (AirDrop, Files, Mail). Nothing is uploaded automatically.

Prefer **Training History JSON** for wipe/reinstall recovery of prescription inputs (prior weights, weekly volume, familiar exercises). Full sqlite remains for rare full-device forensics; it is large because it also holds health ingest, food cache, and chat.

---

## Restore semantics

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
5. Helm-only data not present in HealthKit (logged workouts, chat, food templates, coach state, etc.) does **not** come back from iCloud. Use Training History JSON, Hevy CSV, or a prior full database export if that history matters.

### Manual database file replacement (advanced)

If Cameron copies an exported `helm.sqlite` over the live file (e.g. via Files on a jailbroken path, or Xcode device container):

1. Quit Helm completely before replacing the file.
2. Replace `helm.sqlite` (and delete `helm.sqlite-wal` / `helm.sqlite-shm` if present so the next open starts clean).
3. On next launch, migrations run if the file is from an older schema version.
4. HealthKit anchors are **not** in the SQLite file; they reset the same as a device restore (step 3–4 above).
5. If the replaced file is from a **newer** schema than the installed app, migration will fail safely; use a matching app version or a file from the same or older schema.

There is still no in-app full-database swap UI; Training History JSON is the supported light restore path.

### What manual export does *not* guarantee

- **Cross-device HealthKit sync**: HealthKit data on the new device may differ from the old device. GRDB holds what was ingested on the source device; backfill re-reads what HealthKit exposes on the target device.
- **API keys**: Keychain; re-enter on a fresh install unless restored via encrypted Keychain backup.
- **Mesocycle / chat / nutrition**: Training History JSON restores logged sets only, not coach chat or food logs.

---

## Related docs

- `Docs/DIAGNOSTICS.md`: log export bundle schema and redaction rules
- `PLAN.md`: locked decision on manual export from M1; iCloud exclusion supersedes the original M1.2 "included" note
