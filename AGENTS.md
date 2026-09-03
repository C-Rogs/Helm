# Helm - agent brief

iOS training coach app (SwiftUI + local packages). Workspace root is this repo only.

## Ignore outside this repo

Do **not** follow:

- `/Users/cameronro/Development/CLAUDE.md` / `LAB_CLAUDE.md` (lab vibe-coding interview flow)
- Z2H / `z2h-cli` / bigbrain-vibe workflows
- Zendesk / dapulse / TSE ticket workflows

Those belong to other workspaces.

GitHub: **C-Rogs** only in this repo. Never camronday. Origin is HTTPS.

## Default mode: app-first

Improve from live app + code. Do not walk `PLAN.md` / `PROGRESS.md` section queues unless Cameron says `build M#.#` or `build F-*`.

Section builds: full contract in `.cursor/rules/helm-build-agent.mdc` and `PLAN.md`.

## Build / test

Prefer `scripts/xcodebuild.sh build` or `scripts/xcodebuild.sh test` (quiet + xcbeautify).

## Docs (read when relevant)

| Touching | Read |
|---|---|
| Logging / signposts | `Docs/DIAGNOSTICS.md` |
| UI / DesignSystem / layout | `Docs/DESIGN-SYSTEM.md`, `Docs/HAPTICS.md` |
| Training engine constants | `Docs/Research/RECONCILE.md` (not raw `*.rtf`) |

## Context hygiene

- Prefer a fresh chat when the prior thread is long or off-topic.
- `@` 2-3 files that matter; avoid pasting large dumps or research RTF.
- Broad codebase exploration → Task `explore` subagent; keep parent chat thin.
- Caveman terse replies stay on unless Cameron says `stop caveman` / `normal mode`.
