from __future__ import annotations

import argparse
import csv
from pathlib import Path


OUTPUT_COLUMNS = [
    "county_id",
    "current_source",
    "expected_source",
    "status",
]

NOTE_MARKER = " #"


ACTION_PRIORITY = {
    "replace_with_vanilla_block": 0,
    "replace_with_mod_block": 1,
    "manual_review": 2,
}

STATUS_PRIORITY = {
    "mismatch": 0,
    "mixed": 1,
    "unknown": 2,
    "review": 3,
    "skip": 4,
}


def parse_args() -> argparse.Namespace:
    repo_root = Path(__file__).resolve().parents[2]
    default_dir = repo_root / "works/analysis/generated/landed_titles_source_audit"
    parser = argparse.ArgumentParser(description="Build a compact county source manual-review worklist CSV.")
    parser.add_argument("--audit-csv", type=Path, default=default_dir / "county_source_audit.csv")
    parser.add_argument("--fix-plan-csv", type=Path, default=default_dir / "county_source_fix_plan.csv")
    parser.add_argument("--output-csv", type=Path, default=default_dir / "county_source_manual_worklist.csv")
    parser.add_argument(
        "--preserved-notes-csv",
        type=Path,
        default=default_dir / "county_source_manual_worklist_preserved_notes.csv",
    )
    return parser.parse_args()


def read_csv_by_key(path: Path, key: str) -> dict[str, dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        return {row[key]: row for row in csv.DictReader(handle)}


def split_status_note(value: str) -> tuple[str, str]:
    if NOTE_MARKER not in value:
        return value.strip(), ""
    status, note = value.split(NOTE_MARKER, 1)
    return status.strip(), f"{NOTE_MARKER}{note.rstrip()}"


def read_existing_notes(path: Path, preserved_notes_path: Path) -> dict[str, str]:
    notes: dict[str, str] = {}

    if path.exists():
        with path.open("r", encoding="utf-8-sig", newline="") as handle:
            for row in csv.DictReader(handle):
                county_id = row.get("county_id", "")
                _, note = split_status_note(row.get("status", ""))
                if county_id and note:
                    notes[county_id] = note

    if preserved_notes_path.exists():
        with preserved_notes_path.open("r", encoding="utf-8-sig", newline="") as handle:
            for row in csv.DictReader(handle):
                county_id = row.get("county_id", "")
                note = row.get("note", "").strip()
                if county_id and note:
                    if not note.startswith("#"):
                        note = f"# {note}"
                    notes[county_id] = f" {note}"

    return notes


def write_preserved_notes(path: Path, notes: dict[str, str], active_counties: set[str]) -> int:
    preserved_rows = [
        {
            "county_id": county_id,
            "note": note.strip(),
            "preserved_reason": "county_not_in_current_worklist",
        }
        for county_id, note in sorted(notes.items())
        if county_id not in active_counties
    ]

    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=["county_id", "note", "preserved_reason"])
        writer.writeheader()
        writer.writerows(preserved_rows)

    return len(preserved_rows)


def simple_status(audit_status: str) -> str:
    if audit_status.startswith("mismatch:"):
        return "mismatch"
    if audit_status.startswith("review:"):
        return "review"
    if audit_status == "manual_review:mixed":
        return "mixed"
    if audit_status == "manual_review:unknown":
        return "unknown"
    if audit_status.startswith("skip:"):
        return "skip"
    return audit_status


def sort_key(row: dict[str, str]) -> tuple[int, str, int, str]:
    action = row["_action"]
    status = row["status"]
    return (
        ACTION_PRIORITY.get(action, 99),
        STATUS_PRIORITY.get(status, 99),
        row["expected_source"],
        row["county_id"],
    )


def main() -> None:
    args = parse_args()
    audit_by_county = read_csv_by_key(args.audit_csv, "county_id")
    existing_notes = read_existing_notes(args.output_csv, args.preserved_notes_csv)

    rows: list[dict[str, str]] = []
    with args.fix_plan_csv.open("r", encoding="utf-8-sig", newline="") as handle:
        for plan_row in csv.DictReader(handle):
            action = plan_row["action"]
            if action == "no_action":
                continue

            county_id = plan_row["county_id"]
            audit_row = audit_by_county[county_id]
            rows.append(
                {
                    "county_id": county_id,
                    "current_source": plan_row["current_block_source"],
                    "expected_source": plan_row["expected_source"],
                    "status": simple_status(audit_row["audit_status"]),
                    "_action": action,
                }
            )

    rows.sort(key=sort_key)
    active_counties = {row["county_id"] for row in rows}
    preserved_note_count = write_preserved_notes(args.preserved_notes_csv, existing_notes, active_counties)

    args.output_csv.parent.mkdir(parents=True, exist_ok=True)
    with args.output_csv.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=OUTPUT_COLUMNS)
        writer.writeheader()
        for row in rows:
            output_row = {column: row[column] for column in OUTPUT_COLUMNS}
            note = existing_notes.get(row["county_id"], "")
            if note:
                output_row["status"] = f"{output_row['status']}{note}"
            writer.writerow(output_row)

    print(f"wrote: {args.output_csv}")
    print(f"rows: {len(rows)}")
    print(f"preserved notes: {preserved_note_count}")


if __name__ == "__main__":
    main()
