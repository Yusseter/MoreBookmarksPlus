from __future__ import annotations

import argparse
import csv
import re
from pathlib import Path


TITLE_PATTERN = re.compile(r"^\s*([ekdcbh]_[A-Za-z0-9_]+)\s*=\s*\{")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Rebuild title_relation_master_manuel.csv so mod_title_id reflects current repo title ids and marks differing mappings."
    )
    parser.add_argument("--master-csv", type=Path, required=True)
    parser.add_argument("--current-landed-titles", type=Path, required=True)
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


def load_master_rows(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def write_manual_csv(path: Path, rows: list[tuple[str, str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle, lineterminator="\n")
        writer.writerow(["source_title_id", "mod_title_id", "mod_title_id_differs"])
        writer.writerows(rows)


def write_mapping_report(
    path: Path,
    rows: list[tuple[str, str, str, str]],
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle, lineterminator="\n")
        writer.writerow(["source_title_id", "original_mod_title_id", "current_mod_title_id", "resolution"])
        writer.writerows(rows)


def write_summary(
    path: Path,
    total_rows: int,
    mod_rows: int,
    kept_original_mod_id_count: int,
    switched_to_source_title_id_count: int,
    cleared_count: int,
) -> None:
    lines = [
        "# Title Relation Manual Rebuild Summary",
        "",
        f"- source rows total: {total_rows}",
        f"- rows with mod mapping in master: {mod_rows}",
        f"- rows kept on original mod title id: {kept_original_mod_id_count}",
        f"- rows switched to current source title id: {switched_to_source_title_id_count}",
        f"- rows cleared because no current counterpart exists: {cleared_count}",
    ]
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    args = parse_args()

    current_title_ids = parse_title_ids(args.current_landed_titles)
    master_rows = load_master_rows(args.master_csv)

    manual_rows: list[tuple[str, str, str]] = []
    mapping_report_rows: list[tuple[str, str, str, str]] = []
    kept_original_mod_id_count = 0
    switched_to_source_title_id_count = 0
    cleared_count = 0
    mod_rows = 0

    for row in master_rows:
        source_title_id = (row.get("source_title_id") or "").strip()
        canonical_title_id = (row.get("canonical_title_id") or "").strip()
        canonical_namespace = (row.get("canonical_namespace") or "").strip()

        current_mod_title_id = ""
        resolution = ""

        if canonical_namespace == "mod":
            mod_rows += 1
            if canonical_title_id in current_title_ids:
                current_mod_title_id = canonical_title_id
                resolution = "keep:original_mod_title_id_exists_in_current_repo"
                kept_original_mod_id_count += 1
            elif source_title_id in current_title_ids:
                current_mod_title_id = source_title_id
                resolution = "switch:use_current_source_title_id"
                switched_to_source_title_id_count += 1
            else:
                resolution = "clear:no_current_counterpart"
                cleared_count += 1

            mapping_report_rows.append(
                (source_title_id, canonical_title_id, current_mod_title_id, resolution)
            )

        diff_flag = "yes" if current_mod_title_id and current_mod_title_id != source_title_id else ""
        manual_rows.append((source_title_id, current_mod_title_id, diff_flag))

    write_manual_csv(args.manual_output, manual_rows)
    report_dir = args.report_dir
    write_mapping_report(report_dir / "original_mod_to_current_title_map.csv", mapping_report_rows)
    write_summary(
        report_dir / "title_relation_manual_rebuild_summary.md",
        total_rows=len(master_rows),
        mod_rows=mod_rows,
        kept_original_mod_id_count=kept_original_mod_id_count,
        switched_to_source_title_id_count=switched_to_source_title_id_count,
        cleared_count=cleared_count,
    )

    print(f"source_rows_total={len(master_rows)}")
    print(f"mod_rows={mod_rows}")
    print(f"kept_original_mod_id_count={kept_original_mod_id_count}")
    print(f"switched_to_source_title_id_count={switched_to_source_title_id_count}")
    print(f"cleared_count={cleared_count}")
    print(f"manual_output={args.manual_output}")
    print(f"mapping_report={report_dir / 'original_mod_to_current_title_map.csv'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
