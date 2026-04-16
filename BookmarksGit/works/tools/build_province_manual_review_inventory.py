from __future__ import annotations

import csv
from collections import Counter, defaultdict
from pathlib import Path
from typing import Dict, List


REPO_ROOT = Path(__file__).resolve().parents[2]
MASTER_PATH = REPO_ROOT / "works" / "map_data_sources" / "province_relation_master.csv"
GENERATED_ROOT = REPO_ROOT / "works" / "analysis" / "generated" / "province_relation_mapping" / "manual_review_inventory"
CLUSTER_REVIEW_ROOT = REPO_ROOT / "works" / "analysis" / "generated" / "province_relation_mapping" / "cluster_reviews"


def read_csv(path: Path) -> List[Dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def write_csv(path: Path, rows: List[Dict[str, str]], fieldnames: List[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def as_float(value: str) -> float:
    try:
        return float(value or 0.0)
    except ValueError:
        return 0.0


def as_int(value: str) -> int:
    try:
        return int(value or 0)
    except ValueError:
        return 0


def get_target_kind(row: Dict[str, str]) -> str:
    target_name = (row.get("target_province_name") or row.get("target_name") or "").strip()
    if target_name.startswith(("sea_", "SEA_")):
        return "sea"
    if target_name.upper().startswith("IMPASSABLE "):
        return "impassable"
    if row.get("target_barony"):
        return "playable"
    if row.get("target_title_path"):
        return "bound_non_barony"
    if not row.get("target_province_id"):
        return "unmapped"
    return "unbound"


def get_promotion_hint(row: Dict[str, str]) -> str:
    target_kind = get_target_kind(row)
    classification = row["classification"]
    status = row["status"]

    if not row["target_province_id"]:
        return "blocked:no_target"
    if not row.get("target_title_path"):
        return "blocked:no_target_title"
    if target_kind in {"sea", "impassable", "unmapped", "unbound"}:
        return f"blocked:{target_kind}"
    if row.get("source_history_exists") != "yes":
        return "blocked:no_source_history"
    if classification == "exact" and status == "mapped" and row.get("apply_to_history") == "yes":
        return "ready:exact"

    confidence = as_float(row.get("confidence", "0"))
    overlap_score = as_float(row.get("overlap_score", "0"))
    target_coverage = as_float(row.get("target_coverage", "0"))
    candidate_count = as_int(row.get("candidate_count", "0"))
    target_source_count_all = as_int(row.get("target_source_count_all", "0"))
    target_is_best_source = row.get("target_is_best_source") == "yes"

    if classification == "split" and target_coverage >= 0.98 and overlap_score >= 0.80 and confidence >= 0.70:
        return "review:target_fully_captured"
    if candidate_count == 1 and target_source_count_all == 1 and overlap_score >= 0.95 and target_coverage >= 0.95 and confidence >= 0.60:
        return "review:strong_single_candidate"
    if target_source_count_all > 1 and target_coverage < 0.50 and overlap_score >= 0.90:
        return "blocked:shared_target_low_coverage"
    if target_source_count_all > 1 and not target_is_best_source:
        return "blocked:not_primary_target_source"
    if overlap_score >= 0.90 and confidence >= 0.65 and target_kind == "playable" and target_coverage >= 0.50 and target_source_count_all == 1:
        return "review:high_overlap"
    return "review:manual"


def normalize_name(value: str) -> str:
    return (value or "").strip() or "<blank>"


def build_manual_worklist(rows: List[Dict[str, str]]) -> List[Dict[str, str]]:
    worklist: List[Dict[str, str]] = []
    for row in rows:
        if row["status"] != "manual_review":
            continue
        enriched = dict(row)
        enriched["promotion_hint"] = get_promotion_hint(row)
        enriched["target_kind"] = get_target_kind(row)
        enriched["source_root_title"] = normalize_name(row.get("source_root_title", ""))
        enriched["target_root_title"] = normalize_name(row.get("target_root_title", ""))
        enriched["source_kingdom"] = normalize_name(row.get("source_kingdom", ""))
        enriched["source_duchy"] = normalize_name(row.get("source_duchy", ""))
        enriched["source_county"] = normalize_name(row.get("source_county", ""))
        enriched["source_barony"] = normalize_name(row.get("source_barony", ""))
        enriched["target_kingdom"] = normalize_name(row.get("target_kingdom", ""))
        enriched["target_duchy"] = normalize_name(row.get("target_duchy", ""))
        enriched["target_county"] = normalize_name(row.get("target_county", ""))
        enriched["target_barony"] = normalize_name(row.get("target_barony", ""))
        worklist.append(enriched)

    hint_order = {
        "review:target_fully_captured": 0,
        "review:strong_single_candidate": 1,
        "review:high_overlap": 2,
        "review:manual": 3,
        "blocked:not_primary_target_source": 4,
        "blocked:shared_target_low_coverage": 5,
        "blocked:no_source_history": 6,
    }

    worklist.sort(
        key=lambda row: (
            hint_order.get(row["promotion_hint"], 99),
            0 if row.get("source_history_exists") == "yes" else 1,
            -as_float(row.get("confidence", "0")),
            -as_float(row.get("overlap_score", "0")),
            row.get("target_root_title", ""),
            row.get("target_kingdom", ""),
            row.get("target_duchy", ""),
            row.get("target_county", ""),
            row.get("target_barony", ""),
            row.get("source_province_id", ""),
        )
    )
    return worklist


def build_root_summary(worklist: List[Dict[str, str]]) -> List[Dict[str, str]]:
    grouped: Dict[str, List[Dict[str, str]]] = defaultdict(list)
    for row in worklist:
        grouped[row["source_root_title"]].append(row)

    summary: List[Dict[str, str]] = []
    for source_root, rows in sorted(grouped.items(), key=lambda item: (-len(item[1]), item[0])):
        hint_counts = Counter(row["promotion_hint"] for row in rows)
        summary.append(
            {
                "source_root_title": source_root,
                "row_count": str(len(rows)),
                "with_source_history": str(sum(1 for row in rows if row.get("source_history_exists") == "yes")),
                "review_high_overlap": str(hint_counts.get("review:high_overlap", 0)),
                "review_target_fully_captured": str(hint_counts.get("review:target_fully_captured", 0)),
                "review_strong_single_candidate": str(hint_counts.get("review:strong_single_candidate", 0)),
                "review_manual": str(hint_counts.get("review:manual", 0)),
                "blocked_not_primary_target_source": str(hint_counts.get("blocked:not_primary_target_source", 0)),
                "blocked_shared_target_low_coverage": str(hint_counts.get("blocked:shared_target_low_coverage", 0)),
                "blocked_no_source_history": str(hint_counts.get("blocked:no_source_history", 0)),
            }
        )
    return summary


def build_auto_backlog(worklist: List[Dict[str, str]]) -> List[Dict[str, str]]:
    backlog = [
        row
        for row in worklist
        if row["promotion_hint"] in {"review:target_fully_captured", "review:strong_single_candidate", "review:high_overlap"}
    ]
    backlog.sort(
        key=lambda row: (
            {"review:target_fully_captured": 0, "review:strong_single_candidate": 1, "review:high_overlap": 2}[row["promotion_hint"]],
            -as_float(row.get("overlap_score", "0")),
            -as_float(row.get("confidence", "0")),
        )
    )
    return backlog


def build_subtree_candidates(worklist: List[Dict[str, str]]) -> List[Dict[str, str]]:
    grouped: Dict[str, List[Dict[str, str]]] = defaultdict(list)
    for row in worklist:
        if row["target_kind"] != "playable":
            continue
        county_key = "|".join(
            [
                row["target_root_title"],
                row["target_kingdom"],
                row["target_duchy"],
                row["target_county"],
            ]
        )
        grouped[county_key].append(row)

    results: List[Dict[str, str]] = []
    for county_key, rows in grouped.items():
        distinct_source_roots = sorted({row["source_root_title"] for row in rows})
        distinct_source_counties = sorted({row["source_county"] for row in rows})
        distinct_source_baronies = sorted({row["source_barony"] for row in rows})
        distinct_target_provinces = sorted({row["target_province_id"] for row in rows if row["target_province_id"]})
        hint_counts = Counter(row["promotion_hint"] for row in rows)
        avg_overlap = sum(as_float(row["overlap_score"]) for row in rows) / len(rows)
        avg_confidence = sum(as_float(row["confidence"]) for row in rows) / len(rows)

        recommendation = ""
        if len(rows) >= 3 and len(distinct_source_counties) >= 2:
            recommendation = "subtree_migration_candidate"
        elif hint_counts.get("blocked:shared_target_low_coverage", 0) >= 2:
            recommendation = "shared_target_conflict"
        elif hint_counts.get("blocked:not_primary_target_source", 0) >= 2:
            recommendation = "competing_source_conflict"

        if not recommendation:
            continue

        target_root, target_kingdom, target_duchy, target_county = county_key.split("|")
        results.append(
            {
                "target_root_title": target_root,
                "target_kingdom": target_kingdom,
                "target_duchy": target_duchy,
                "target_county": target_county,
                "row_count": str(len(rows)),
                "distinct_source_roots": str(len(distinct_source_roots)),
                "distinct_source_counties": str(len(distinct_source_counties)),
                "distinct_source_baronies": str(len(distinct_source_baronies)),
                "distinct_target_provinces": str(len(distinct_target_provinces)),
                "with_source_history": str(sum(1 for row in rows if row.get("source_history_exists") == "yes")),
                "review_high_overlap": str(hint_counts.get("review:high_overlap", 0)),
                "review_target_fully_captured": str(hint_counts.get("review:target_fully_captured", 0)),
                "review_manual": str(hint_counts.get("review:manual", 0)),
                "blocked_not_primary_target_source": str(hint_counts.get("blocked:not_primary_target_source", 0)),
                "blocked_shared_target_low_coverage": str(hint_counts.get("blocked:shared_target_low_coverage", 0)),
                "blocked_no_source_history": str(hint_counts.get("blocked:no_source_history", 0)),
                "avg_overlap_score": f"{avg_overlap:.6f}",
                "avg_confidence": f"{avg_confidence:.6f}",
                "recommendation": recommendation,
                "source_roots": " | ".join(distinct_source_roots[:6]),
                "source_counties": " | ".join(distinct_source_counties[:6]),
            }
        )

    results.sort(
        key=lambda row: (
            0 if row["recommendation"] == "subtree_migration_candidate" else 1,
            -int(row["row_count"]),
            -int(row["distinct_source_counties"]),
            row["target_root_title"],
            row["target_kingdom"],
            row["target_duchy"],
            row["target_county"],
        )
    )
    return results


def build_summary_text(worklist: List[Dict[str, str]], root_summary: List[Dict[str, str]], auto_backlog: List[Dict[str, str]], subtree_candidates: List[Dict[str, str]]) -> str:
    hint_counts = Counter(row["promotion_hint"] for row in worklist)
    lines = [
        "# Province Manual Review Inventory",
        "",
        f"- manual_review rows: `{len(worklist)}`",
        f"- source roots with manual_review: `{len(root_summary)}`",
        f"- remaining near-auto backlog: `{len(auto_backlog)}`",
        f"- subtree migration candidates: `{len(subtree_candidates)}`",
        "",
        "## Promotion Hints",
        "",
    ]

    for hint, count in sorted(hint_counts.items(), key=lambda item: (-item[1], item[0])):
        lines.append(f"- `{hint}`: `{count}`")

    lines.extend(["", "## Top Source Roots", ""])
    for row in root_summary[:15]:
        lines.append(
            "- `{0}`: rows=`{1}`, high_overlap=`{2}`, manual=`{3}`, not_primary=`{4}`, shared_target=`{5}`".format(
                row["source_root_title"],
                row["row_count"],
                row["review_high_overlap"],
                row["review_manual"],
                row["blocked_not_primary_target_source"],
                row["blocked_shared_target_low_coverage"],
            )
        )

    lines.extend(["", "## Top Subtree Migration Candidates", ""])
    for row in subtree_candidates[:15]:
        lines.append(
            "- `{0} > {1} > {2} > {3}`: rows=`{4}`, recommendation=`{5}`, source_counties=`{6}`".format(
                row["target_root_title"],
                row["target_kingdom"],
                row["target_duchy"],
                row["target_county"],
                row["row_count"],
                row["recommendation"],
                row["distinct_source_counties"],
            )
        )

    return "\n".join(lines) + "\n"


def read_probe_rows() -> List[Dict[str, str]]:
    rows: List[Dict[str, str]] = []
    if not CLUSTER_REVIEW_ROOT.exists():
        return rows

    for csv_path in sorted(CLUSTER_REVIEW_ROOT.glob("*.csv")):
        for row in read_csv(csv_path):
            enriched = dict(row)
            enriched["probe_name"] = csv_path.stem
            rows.append(enriched)
    return rows


def build_probe_worklist(rows: List[Dict[str, str]]) -> List[Dict[str, str]]:
    worklist = [
        row
        for row in rows
        if row.get("promotion_hint") != "ready:exact"
    ]

    hint_order = {
        "review:target_fully_captured": 0,
        "review:strong_single_candidate": 1,
        "review:high_overlap": 2,
        "review:manual": 3,
        "blocked:not_primary_target_source": 4,
        "blocked:shared_target_low_coverage": 5,
        "blocked:no_source_history": 6,
        "blocked:no_target_title": 7,
        "blocked:no_target": 8,
    }
    worklist.sort(
        key=lambda row: (
            row.get("probe_name", ""),
            hint_order.get(row.get("promotion_hint", ""), 99),
            0 if row.get("source_history_exists") == "yes" else 1,
            -as_float(row.get("overlap_score", "0")),
            row.get("target_title_path", ""),
            row.get("source_province_id", ""),
        )
    )
    return worklist


def build_probe_summary(rows: List[Dict[str, str]]) -> List[Dict[str, str]]:
    grouped: Dict[str, List[Dict[str, str]]] = defaultdict(list)
    for row in rows:
        grouped[row["probe_name"]].append(row)

    results: List[Dict[str, str]] = []
    for probe_name, probe_rows in sorted(grouped.items()):
        hint_counts = Counter(row.get("promotion_hint", "") for row in probe_rows)
        target_kind_counts = Counter(row.get("target_kind", "") for row in probe_rows)

        recommendation = "park"
        if hint_counts.get("review:target_fully_captured", 0) or hint_counts.get("review:strong_single_candidate", 0) or hint_counts.get("review:high_overlap", 0):
            recommendation = "continue_exact_probe"
        elif (
            probe_name.startswith(("c_", "d_"))
            and (hint_counts.get("review:manual", 0) > 0)
            and (
                hint_counts.get("blocked:not_primary_target_source", 0) > 0
                or hint_counts.get("blocked:shared_target_low_coverage", 0) > 0
            )
        ):
            recommendation = "subtree_migration_candidate"

        results.append(
            {
                "probe_name": probe_name,
                "row_count": str(len(probe_rows)),
                "playable_rows": str(target_kind_counts.get("playable", 0)),
                "sea_rows": str(target_kind_counts.get("sea", 0)),
                "ready_exact": str(hint_counts.get("ready:exact", 0)),
                "review_target_fully_captured": str(hint_counts.get("review:target_fully_captured", 0)),
                "review_strong_single_candidate": str(hint_counts.get("review:strong_single_candidate", 0)),
                "review_high_overlap": str(hint_counts.get("review:high_overlap", 0)),
                "review_manual": str(hint_counts.get("review:manual", 0)),
                "blocked_not_primary_target_source": str(hint_counts.get("blocked:not_primary_target_source", 0)),
                "blocked_shared_target_low_coverage": str(hint_counts.get("blocked:shared_target_low_coverage", 0)),
                "blocked_no_source_history": str(hint_counts.get("blocked:no_source_history", 0)),
                "recommendation": recommendation,
            }
        )

    results.sort(
        key=lambda row: (
            0 if row["recommendation"] == "continue_exact_probe" else 1 if row["recommendation"] == "subtree_migration_candidate" else 2,
            -int(row["row_count"]),
            row["probe_name"],
        )
    )
    return results


def build_probe_summary_text(probe_summary: List[Dict[str, str]], probe_worklist: List[Dict[str, str]]) -> str:
    recommendation_counts = Counter(row["recommendation"] for row in probe_summary)
    lines = [
        "# Province Probe Review Inventory",
        "",
        f"- probe files: `{len(probe_summary)}`",
        f"- unresolved probe rows: `{len(probe_worklist)}`",
        f"- continue_exact_probe: `{recommendation_counts.get('continue_exact_probe', 0)}`",
        f"- subtree_migration_candidate: `{recommendation_counts.get('subtree_migration_candidate', 0)}`",
        f"- park: `{recommendation_counts.get('park', 0)}`",
        "",
        "## Probe Recommendations",
        "",
    ]

    for row in probe_summary:
        lines.append(
            "- `{0}`: recommendation=`{1}`, rows=`{2}`, high_overlap=`{3}`, manual=`{4}`, not_primary=`{5}`, shared_target=`{6}`".format(
                row["probe_name"],
                row["recommendation"],
                row["row_count"],
                row["review_high_overlap"],
                row["review_manual"],
                row["blocked_not_primary_target_source"],
                row["blocked_shared_target_low_coverage"],
            )
        )

    return "\n".join(lines) + "\n"


def main() -> None:
    rows = read_csv(MASTER_PATH)
    worklist = build_manual_worklist(rows)
    root_summary = build_root_summary(worklist)
    auto_backlog = build_auto_backlog(worklist)
    subtree_candidates = build_subtree_candidates(worklist)
    probe_rows = read_probe_rows()
    probe_worklist = build_probe_worklist(probe_rows)
    probe_summary = build_probe_summary(probe_rows)

    GENERATED_ROOT.mkdir(parents=True, exist_ok=True)

    worklist_fields = [
        "source_province_id",
        "source_province_name",
        "source_root_title",
        "source_kingdom",
        "source_duchy",
        "source_county",
        "source_barony",
        "target_province_id",
        "target_province_name",
        "target_root_title",
        "target_kingdom",
        "target_duchy",
        "target_county",
        "target_barony",
        "classification",
        "status",
        "apply_to_history",
        "promotion_hint",
        "target_kind",
        "source_history_exists",
        "confidence",
        "overlap_score",
        "target_coverage",
        "target_source_count_all",
        "target_best_source_id",
        "target_best_overlap_score",
        "target_overlap_gap",
        "notes",
        "top_candidates",
    ]
    write_csv(GENERATED_ROOT / "province_manual_review_worklist.csv", worklist, worklist_fields)

    root_fields = [
        "source_root_title",
        "row_count",
        "with_source_history",
        "review_high_overlap",
        "review_target_fully_captured",
        "review_strong_single_candidate",
        "review_manual",
        "blocked_not_primary_target_source",
        "blocked_shared_target_low_coverage",
        "blocked_no_source_history",
    ]
    write_csv(GENERATED_ROOT / "province_manual_review_root_summary.csv", root_summary, root_fields)

    write_csv(GENERATED_ROOT / "province_auto_candidate_backlog.csv", auto_backlog, worklist_fields)

    subtree_fields = [
        "target_root_title",
        "target_kingdom",
        "target_duchy",
        "target_county",
        "row_count",
        "distinct_source_roots",
        "distinct_source_counties",
        "distinct_source_baronies",
        "distinct_target_provinces",
        "with_source_history",
        "review_high_overlap",
        "review_target_fully_captured",
        "review_manual",
        "blocked_not_primary_target_source",
        "blocked_shared_target_low_coverage",
        "blocked_no_source_history",
        "avg_overlap_score",
        "avg_confidence",
        "recommendation",
        "source_roots",
        "source_counties",
    ]
    write_csv(GENERATED_ROOT / "province_subtree_migration_candidates.csv", subtree_candidates, subtree_fields)

    summary_text = build_summary_text(worklist, root_summary, auto_backlog, subtree_candidates)
    write_text(GENERATED_ROOT / "province_manual_review_summary.md", summary_text)

    probe_fields = [
        "probe_name",
        "filter_reason",
        "source_province_id",
        "source_name",
        "source_root_title",
        "source_kingdom",
        "source_duchy",
        "source_county",
        "source_barony",
        "target_province_id",
        "target_name",
        "target_root_title",
        "target_kingdom",
        "target_duchy",
        "target_county",
        "target_barony",
        "classification",
        "status",
        "apply_to_history",
        "target_kind",
        "promotion_hint",
        "source_history_exists",
        "confidence",
        "overlap_score",
        "target_coverage",
        "target_source_count_all",
        "target_best_source_id",
        "target_best_overlap_score",
        "target_overlap_gap",
        "notes",
        "top_candidates",
    ]
    write_csv(GENERATED_ROOT / "province_probe_review_worklist.csv", probe_worklist, probe_fields)

    probe_summary_fields = [
        "probe_name",
        "row_count",
        "playable_rows",
        "sea_rows",
        "ready_exact",
        "review_target_fully_captured",
        "review_strong_single_candidate",
        "review_high_overlap",
        "review_manual",
        "blocked_not_primary_target_source",
        "blocked_shared_target_low_coverage",
        "blocked_no_source_history",
        "recommendation",
    ]
    write_csv(GENERATED_ROOT / "province_probe_summary.csv", probe_summary, probe_summary_fields)
    write_text(GENERATED_ROOT / "province_probe_summary.md", build_probe_summary_text(probe_summary, probe_worklist))


if __name__ == "__main__":
    main()
