#!/usr/bin/env python3
"""Aggregate an Instruments Time Profiler export for sleep hot-path decisions."""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter
from pathlib import Path


INTERESTING = (
    b"SleepRepository",
    b"SleepAggregation",
    b"SleepInterval",
    b"ISO8601Coding",
    b"NSISO8601",
    b"__ResetUDateFormat",
    b"NutritionLookup",
    b"ReadinessHistoryBuilder",
    b"SleepFetchOverlapping",
    b"ReadinessHistoryBuild",
    b"DashboardView",
    b"icu::",
)


def parse_hangs(path: Path) -> list[dict]:
    text = path.read_text(errors="replace")
    ht_ids = {
        m.group(1): m.group(2)
        for m in re.finditer(r'<hang-type id="(\d+)"[^>]*fmt="([^"]+)"', text)
    }
    rows = []
    for row in re.findall(r"<row>(.*?)</row>", text, re.S):
        st = re.search(r'<start-time[^>]*fmt="([^"]+)"', row)
        dur = re.search(r'<duration[^>]*fmt="([^"]+)"', row)
        ht = re.search(r'<hang-type (?:id="(\d+)"[^>]*fmt="([^"]+)"|ref="(\d+)")', row)
        if not (st and dur and ht):
            continue
        hang_type = ht.group(2) if ht.group(2) else ht_ids.get(ht.group(3), "?")
        rows.append({"start": st.group(1), "duration": dur.group(1), "type": hang_type})
    return rows


def aggregate_time_profile(path: Path) -> dict:
    frame_names: dict[bytes, bytes] = {}
    anyf: Counter[bytes] = Counter()
    bins: Counter[bytes] = Counter()
    samples = 0
    with path.open("rb") as f:
        data = f.read()
    pos = 0
    frame_def = re.compile(br'<frame id="(\d+)" name="([^"]+)"')
    frame_any = re.compile(br'<frame (?:id="(\d+)" name="([^"]+)"|ref="(\d+)")')
    bin_def = re.compile(br'<binary id="(\d+)" name="([^"]+)"')
    bin_any = re.compile(br'<binary (?:id="(\d+)" name="([^"]+)"|ref="(\d+)")')
    while True:
        s = data.find(b"<row>", pos)
        if s < 0:
            break
        e = data.find(b"</row>", s)
        if e < 0:
            break
        row = data[s:e]
        pos = e + 6
        samples += 1
        for m in frame_def.finditer(row):
            frame_names[m.group(1)] = m.group(2)
        for m in bin_def.finditer(row):
            frame_names[b"bin:" + m.group(1)] = m.group(2)
        row_bins: set[bytes] = set()
        for m in bin_any.finditer(row):
            name = m.group(2) if m.group(2) is not None else frame_names.get(b"bin:" + m.group(3), b"?")
            row_bins.add(name)
        for name in row_bins:
            bins[name] += 1
        seen: set[bytes] = set()
        for m in frame_any.finditer(row):
            fr = m.group(2) if m.group(2) is not None else frame_names.get(m.group(3), b"?")
            if fr in seen:
                continue
            seen.add(fr)
            if any(p in fr for p in INTERESTING):
                anyf[fr] += 1
    return {
        "samples": samples,
        "top_binaries": [
            {"name": k.decode(errors="replace"), "count": v} for k, v in bins.most_common(15)
        ],
        "interesting": [
            {"name": k.decode(errors="replace"), "count": v} for k, v in anyf.most_common(40)
        ],
    }


def render_report(
    matrix_path: Path | None,
    hangs: list[dict],
    profile: dict | None,
    out: Path,
) -> None:
    lines: list[str] = []
    lines.append("# Helm sleep hot-path report")
    lines.append("")
    lines.append("## Decision matrix")
    if matrix_path and matrix_path.exists():
        lines.append(f"Source: `{matrix_path}`")
        lines.append("")
        try:
            matrix = json.loads(matrix_path.read_text())
            lines.append("| case | scale | rows | iters | totalMs | perOpUs | vs iso |")
            lines.append("|---|---|---|---|---|---|---|")
            for row in matrix.get("rows", []):
                rel = row.get("relativeToIsoDecode")
                rel_s = f"{rel:.2f}" if isinstance(rel, (int, float)) else "-"
                lines.append(
                    f"| {row.get('caseName')} | {row.get('scale')} | {row.get('rows')} | "
                    f"{row.get('iterations')} | {row.get('totalMs', 0):.1f} | "
                    f"{row.get('perOpUs', 0):.3f} | {rel_s} |"
                )
        except Exception as exc:  # noqa: BLE001
            lines.append(f"(failed to parse matrix: {exc})")
    else:
        lines.append("_No `/tmp/helm-sleep-hotpath.json` yet. Run the Swift Testing benches first._")

    lines.append("")
    lines.append("## How to read the matrix")
    lines.append("")
    lines.append("- `epochDecodeOnly` much faster than `foundationISODecodeOnly` + decode dominates `fetchOverlapping` -> migrate to REAL timestamps.")
    lines.append("- `isoDecodeOnly` / `fastISODecodeOnly` close to epoch -> production fast parser is winning (keep string schema).")
    lines.append("- `fetchRowsNoDecode` ~= `fetchOverlapping` -> I/O/query shape, not formatter.")
    lines.append("- `readinessHistory30d` >> night summaries -> off-main + cache decoded records.")
    lines.append("")
    lines.append("## Hangs")
    lines.append("")
    if hangs:
        lines.append(f"Count: {len(hangs)}")
        for h in hangs:
            lines.append(f"- `{h['start']}` {h['duration']} ({h['type']})")
    else:
        lines.append("_No hang export or empty._")

    lines.append("")
    lines.append("## Time profile interesting frames")
    lines.append("")
    if profile:
        lines.append(f"Samples: {profile.get('samples', 0)}")
        lines.append("")
        lines.append("### Top binaries")
        for b in profile.get("top_binaries", [])[:10]:
            lines.append(f"- {b['count']}: `{b['name']}`")
        lines.append("")
        lines.append("### Hot symbols")
        for f in profile.get("interesting", [])[:25]:
            lines.append(f"- {f['count']}: `{f['name'][:140]}`")
    else:
        lines.append("_No time-profile XML provided._")

    lines.append("")
    lines.append("## Instruments POI")
    lines.append("")
    lines.append("Filter Points of Interest for `SleepFetchOverlapping` and `ReadinessHistoryBuild`.")
    out.write_text("\n".join(lines) + "\n")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--matrix", type=Path, default=Path("/tmp/helm-sleep-hotpath.json"))
    parser.add_argument("--hangs", type=Path, default=None)
    parser.add_argument("--time-profile", type=Path, default=None)
    parser.add_argument("--out", type=Path, default=Path("/tmp/helm-hotpath-report.md"))
    args = parser.parse_args()

    hangs = parse_hangs(args.hangs) if args.hangs and args.hangs.exists() else []
    profile = (
        aggregate_time_profile(args.time_profile)
        if args.time_profile and args.time_profile.exists()
        else None
    )
    render_report(args.matrix, hangs, profile, args.out)
    print(args.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
