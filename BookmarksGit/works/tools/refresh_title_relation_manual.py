from __future__ import annotations

import argparse
import csv
import re
from dataclasses import dataclass
from pathlib import Path


TITLE_PATTERN = re.compile(r"^\s*([ekdcbh]_[A-Za-z0-9_]+)\s*=\s*\{")


@dataclass
class RefreshStats:
    total_rows: int = 0
    before_nonempty: int = 0
    after_nonempty: int = 0
    unchanged_rows: int = 0
    changed_rows: int = 0
    kept_valid_manual: int = 0
    filled_from_master: int = 0
    cleared_invalid_manual: int = 0
    blank_rows: int = 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Refresh title_relation_master_manuel.csv against current mod title ids."
    )
    parser.add_argument("--manual-input", type=Path, required=True)
    parser.add_argument("--master-csv", type=Path, required=True)
    parser.add_argument("--source-landed-titles", type=Path, required=True)
    parser.add_argument("--mod-landed-titles", type=Path, required=True)
    parser.add_argument("--manual-output", type=Path, required=True)
    parser.add_argument("--report-dir", type=Path, required=True)
    return parser.parse_args()


def parse_title_ids(path: Path) -> set[str]:
    title_ids: set[str] = set()
    for line in path.read_text(encoding="utf-8-sig").splitlines():
        match = TITLE_PATTERN.match(line)
        if match:
            title_ids.add(match.group(1))
    return title_ids


def load_manual_map(path: Path) -> dict[str, str]:
    mapping: dict[str, str] = {}
    with path.open(encoding="utf-8-sig", newline="") as handle:
        reader = csv.reader(handle, skipinitialspace=True)
        next(reader, None)
        for row in reader:
            if not row:
                continue
            source_title_id = row[0].strip() if len(row) > 0 else ""
            mod_title_id = row[1].strip() if len(row) > 1 else ""
            if source_title_id:
                mapping[source_title_id] = mod_title_id
    return mapping


def load_master_rows(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def build_output_rows(
    master_rows: list[dict[str, str]],
    current_manual_map: dict[str, str],
    mod_title_ids: set[str],
) -> tuple[list[tuple[str, str, str]], RefreshStats]:
    output_rows: list[tuple[str, str, str]] = []
    stats = RefreshStats(total_rows=len(master_rows))

    for row in master_rows:
        source_title_id = (row.get("source_title_id") or "").strip()
        canonical_namespace = (row.get("canonical_namespace") or "").strip()
        canonical_title_id = (row.get("canonical_title_id") or "").strip()
        current_manual = current_manual_map.get(source_title_id, "").strip()
        desired_manual = ""

        if current_manual:
            stats.before_nonempty += 1

        if current_manual and current_manual in mod_title_ids:
            desired_manual = current_manual
            stats.kept_valid_manual += 1
        elif canonical_namespace == "mod" and canonical_title_id in mod_title_ids:
            desired_manual = canonical_title_id
            if current_manual != desired_manual:
                stats.filled_from_master += 1
        elif current_manual:
            stats.cleared_invalid_manual += 1

        if desired_manual:
            stats.after_nonempty += 1
        else:
            stats.blank_rows += 1

        if current_manual == desired_manual:
            stats.unchanged_rows += 1
        else:
            stats.changed_rows += 1

        diff_flag = "yes" if desired_manual and desired_manual != source_title_id else ""
        output_rows.append((source_title_id, desired_manual, diff_flag))

    return output_rows, stats


def write_manual_csv(path: Path, rows: list[tuple[str, str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle, lineterminator="\n")
        writer.writerow(["source_title_id", "mod_title_id", "mod_title_id_differs"])
        writer.writerows(rows)


def write_title_list_csv(path: Path, header: str, values: set[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle, lineterminator="\n")
        writer.writerow([header])
        for value in sorted(values):
            writer.writerow([value])


def write_summary(
    path: Path,
    stats: RefreshStats,
    source_title_ids: set[str],
    mod_title_ids: set[str],
    shared_title_ids: set[str],
    source_only_title_ids: set[str],
    mod_only_title_ids: set[str],
    manual_output: Path,
) -> None:
    lines = [
        "# Title Manual Refresh Summary",
        "",
        f"- source title count: {len(source_title_ids)}",
        f"- mod title count: {len(mod_title_ids)}",
        f"- shared title count: {len(shared_title_ids)}",
        f"- source-only title count: {len(source_only_title_ids)}",
        f"- mod-only title count: {len(mod_only_title_ids)}",
        "",
        f"- manual rows total: {stats.total_rows}",
        f"- manual rows non-empty before: {stats.before_nonempty}",
        f"- manual rows non-empty after: {stats.after_nonempty}",
        f"- unchanged rows: {stats.unchanged_rows}",
        f"- changed rows: {stats.changed_rows}",
        f"- valid manual rows kept: {stats.kept_valid_manual}",
        f"- rows filled from master: {stats.filled_from_master}",
        f"- invalid manual rows cleared: {stats.cleared_invalid_manual}",
        f"- blank rows after refresh: {stats.blank_rows}",
        "",
        f"- refreshed manual csv: {manual_output}",
    ]
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    args = parse_args()

    source_title_ids = parse_title_ids(args.source_landed_titles)
    mod_title_ids = parse_title_ids(args.mod_landed_titles)
    shared_title_ids = source_title_ids & mod_title_ids
    source_only_title_ids = source_title_ids - mod_title_ids
    mod_only_title_ids = mod_title_ids - source_title_ids

    current_manual_map = load_manual_map(args.manual_input)
    master_rows = load_master_rows(args.master_csv)
    output_rows, stats = build_output_rows(master_rows, current_manual_map, mod_title_ids)

    write_manual_csv(args.manual_output, output_rows)

    report_dir = args.report_dir
    write_title_list_csv(report_dir / "source_only_titles.csv", "title_id", source_only_title_ids)
    write_title_list_csv(report_dir / "mod_only_titles.csv", "title_id", mod_only_title_ids)
    write_summary(
        report_dir / "title_manual_refresh_summary.md",
        stats,
        source_title_ids,
        mod_title_ids,
        shared_title_ids,
        source_only_title_ids,
        mod_only_title_ids,
        args.manual_output,
    )

    print(f"manual_rows_total={stats.total_rows}")
    print(f"manual_rows_changed={stats.changed_rows}")
    print(f"manual_rows_nonempty_after={stats.after_nonempty}")
    print(f"source_title_count={len(source_title_ids)}")
    print(f"mod_title_count={len(mod_title_ids)}")
    print(f"shared_title_count={len(shared_title_ids)}")
    print(f"source_only_title_count={len(source_only_title_ids)}")
    print(f"mod_only_title_count={len(mod_only_title_ids)}")
    print(f"manual_output={args.manual_output}")
    print(f"summary_output={report_dir / 'title_manual_refresh_summary.md'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
