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
    return parser.parse_args()


def read_csv_by_key(path: Path, key: str) -> dict[str, dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        return {row[key]: row for row in csv.DictReader(handle)}


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
    args.output_csv.parent.mkdir(parents=True, exist_ok=True)
    with args.output_csv.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=OUTPUT_COLUMNS)
        writer.writeheader()
        for row in rows:
            writer.writerow({column: row[column] for column in OUTPUT_COLUMNS})

    print(f"wrote: {args.output_csv}")
    print(f"rows: {len(rows)}")


if __name__ == "__main__":
    main()
