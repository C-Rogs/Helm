# Data safety

Canonical reference for Helm's data ownership, backup behaviour, and restore semantics. Frozen at M1.2; later sections that touch export, restore, or HealthKit anchors must stay consistent with this document.

---

## System of record

The GRDB store at `Application Support/Helm/helm.sqlite` is the system of record for all Helm-derived health and training data (daily metrics, body composition, sleep, nutrition, and later tables as migrations land). HealthKit remains the source of truth for raw samples; Helm ingests into GRDB and computes on top of it.

---

## iCloud device backup

**Decision (M1.2): included.**

The `Application Support/Helm/` directory is explicitly marked `isExcludedFromBackup = false` at creation time. Helm data rides in the user's normal iCloud device backup unless Cameron later changes this policy in code and documents the new decision here.

Keychain items (API keys) follow Apple's Keychain backup rules separately; they are not part of the SQLite file.

---

## Manual export

Available from **Settings > Data & Backup**:

| Action | Output | Contents |
|---|---|---|
| Export Database | `.sqlite` file via share sheet | Checkpointed GRDB backup (SQLite backup API, consistent snapshot) |
| Export Diagnostics | `.zip` file via share sheet | Ring buffer + OSLog extract per `Docs/DIAGNOSTICS.md` |
| Export Full Backup | `.zip` file via share sheet | `helm.sqlite` + diagnostics bundle files |

Exports land wherever the share sheet sends them (AirDrop, Files, Mail). Nothing is uploaded automatically.

---

## Restore semantics

Helm does not ship an in-app "import database" flow in M1.2. Restore is documented so downstream work (M1.3 anchors, M1.4 backfill) and Cameron know what to expect.

### iCloud device restore (new or replaced iPhone)

1. `helm.sqlite` restores from the device backup into `Application Support/Helm/`.
2. **HealthKit anchor cursors do not survive a device change.** Anchors are stored locally (UserDefaults or GRDB, depending on M1.3 implementation) and are device-specific. After restore, all ingest cursors are treated as missing and reset to "fetch from beginning of window".
3. **Re-backfill runs** on first launch after restore (M1.4 `BackfillService`): the 6-month bounded window is re-fetched from HealthKit and merged idempotently into the restored GRDB rows. Existing GRDB data from the backup is kept; HealthKit fills gaps and updates changed samples.
4. Readiness baselines and any persisted profile state in GRDB survive intact from the backup file.

### Manual database file replacement (advanced)

If Cameron copies an exported `helm.sqlite` over the live file (e.g. via Files on a jailbroken path, or Xcode device container):

1. Quit Helm completely before replacing the file.
2. Replace `helm.sqlite` (and delete `helm.sqlite-wal` / `helm.sqlite-shm` if present so the next open starts clean).
3. On next launch, migrations run if the file is from an older schema version.
4. HealthKit anchors are **not** in the SQLite file; they reset the same as a device restore (step 2–3 above).
5. If the replaced file is from a **newer** schema than the installed app, migration will fail safely; use a matching app version or a file from the same or older schema.

### What manual export does *not* guarantee

- **Cross-device HealthKit sync**: HealthKit data on the new device may differ from the old device. GRDB holds what was ingested on the source device; backfill re-reads what HealthKit exposes on the target device.
- **Gemini chat history**: not in the GRDB health schema at M1.2; chat persistence lands in M4.5.
- **API keys**: Keychain; re-enter on a fresh install unless restored via encrypted Keychain backup.

---

## Related docs

- `Docs/DIAGNOSTICS.md`: log export bundle schema and redaction rules
- `PLAN.md`: locked decision on manual export from M1, iCloud inclusion explicit, anchors reset on restore
