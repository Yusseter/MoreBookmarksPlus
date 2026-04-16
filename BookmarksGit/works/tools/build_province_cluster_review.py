from __future__ import annotations

import argparse
import csv
import re
from pathlib import Path
from typing import Dict, Iterable, List


REPO_ROOT = Path(__file__).resolve().parents[2]
GENERATED_ROOT = REPO_ROOT / "works" / "analysis" / "generated" / "province_relation_mapping" / "cluster_reviews"
MASTER_PATH = REPO_ROOT / "works" / "map_data_sources" / "province_relation_master.csv"
CURRENT_LANDED_TITLES_PATH = REPO_ROOT / "common" / "landed_titles" / "00_landed_titles.txt"
LIVE_HISTORY_PATH = REPO_ROOT / "history" / "provinces" / "00_MB_PROVINCES.txt"
TEST_HISTORY_PATH = REPO_ROOT / "test_files" / "history" / "provinces" / "00_MB_PROVINCES.txt"
SOURCE_HISTORY_DIR = Path(
    r"C:\Program Files (x86)\Steam\steamapps\workshop\content\1158310\2216670956\0backup\history\provinces"
)


def read_csv(path: Path) -> List[Dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def write_csv(path: Path, rows: List[Dict[str, str]], fieldnames: List[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def split_lines(text: str) -> List[str]:
    return re.split(r"\r?\n", text)


def strip_line_comment(line: str) -> str:
    comment_index = line.find("#")
    if comment_index < 0:
        return line
    return line[:comment_index]


def extract_named_title_block(text: str, title_name: str) -> str:
    match = re.search(rf"(^|\n)\s*{re.escape(title_name)}\s*=\s*\{{", text)
    if not match:
        return ""

    start = match.start()
    sub = text[start:]
    depth = 0
    end_index = None
    for index, char in enumerate(sub):
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                end_index = index + 1
                break

    if end_index is None:
        return ""
    return sub[:end_index]


def get_province_ids_from_title_block(text: str, title_name: str) -> set[str]:
    block = extract_named_title_block(text, title_name)
    if not block:
        return set()
    return set(re.findall(r"province\s*=\s*(\d+)", block))


def parse_province_title_bindings(path: Path, prefix: str) -> Dict[int, Dict[str, str]]:
    text = path.read_text(encoding="utf-8-sig")
    lines = split_lines(text)
    stack: List[tuple[str, int]] = []
    brace_depth = 0
    bindings: Dict[int, Dict[str, str]] = {}

    for raw_line in lines:
        visible = strip_line_comment(raw_line)
        title_match = re.match(r"^\s*([ehkdcb]_[A-Za-z0-9_\/\.\-']+)\s*=\s*\{", visible)
        if title_match:
            stack.append((title_match.group(1), brace_depth))

        province_match = re.match(r"^\s*province\s*=\s*(\d+)\s*$", visible)
        if province_match:
            province_id = int(province_match.group(1))
            values = {
                f"{prefix}_root_title": "",
                f"{prefix}_kingdom": "",
                f"{prefix}_duchy": "",
                f"{prefix}_county": "",
                f"{prefix}_barony": "",
                f"{prefix}_title_path": "",
            }
            path_parts: List[str] = []
            for title, _depth in stack:
                path_parts.append(title)
                if title.startswith(("e_", "h_")) and not values[f"{prefix}_root_title"]:
                    values[f"{prefix}_root_title"] = title
                elif title.startswith("k_") and not values[f"{prefix}_kingdom"]:
                    values[f"{prefix}_kingdom"] = title
                elif title.startswith("d_") and not values[f"{prefix}_duchy"]:
                    values[f"{prefix}_duchy"] = title
                elif title.startswith("c_") and not values[f"{prefix}_county"]:
                    values[f"{prefix}_county"] = title
                elif title.startswith("b_") and not values[f"{prefix}_barony"]:
                    values[f"{prefix}_barony"] = title
            values[f"{prefix}_title_path"] = " > ".join(path_parts)
            bindings[province_id] = values

        brace_depth += visible.count("{") - visible.count("}")
        while stack and stack[-1][1] >= brace_depth:
            stack.pop()

    return bindings


def get_top_level_blocks(text: str) -> Dict[str, str]:
    lines = split_lines(text)
    blocks: Dict[str, str] = {}
    in_block = False
    block_name = ""
    block_start = -1
    depth = 0

    for index, line in enumerate(lines):
        if not in_block:
            match = re.match(r"^\s*([A-Za-z0-9_:\.\-\?]+)\s*=\s*\{", line)
            if match:
                block_name = match.group(1)
                block_start = index
                depth = strip_line_comment(line).count("{") - strip_line_comment(line).count("}")
                if depth <= 0:
                    blocks[block_name] = "\n".join(lines[block_start : index + 1])
                    block_name = ""
                    block_start = -1
                    depth = 0
                else:
                    in_block = True
            continue

        depth += strip_line_comment(line).count("{") - strip_line_comment(line).count("}")
        if depth == 0:
            blocks[block_name] = "\n".join(lines[block_start : index + 1])
            block_name = ""
            block_start = -1
            in_block = False

    return blocks


def get_numeric_history_blocks_from_directory(path: Path) -> Dict[str, str]:
    result: Dict[str, str] = {}
    for file_path in sorted(path.glob("*.txt")):
        blocks = get_top_level_blocks(file_path.read_text(encoding="utf-8-sig"))
        for block_name in blocks:
            if block_name.isdigit() and block_name not in result:
                result[block_name] = file_path.name
    return result


def get_numeric_history_blocks_from_file(path: Path) -> Dict[str, str]:
    if not path.exists():
        return {}
    blocks = get_top_level_blocks(path.read_text(encoding="utf-8-sig"))
    return {name: path.name for name in blocks if name.isdigit()}


def get_target_kind(row: Dict[str, str]) -> str:
    target_name = (row.get("target_name") or "").strip()
    if target_name.startswith("sea_") or target_name.startswith("SEA_"):
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


def get_filter_reason(row: Dict[str, str], source_root: str, target_root: str) -> str:
    reasons: List[str] = []
    if source_root and row.get("source_root_title") == source_root:
        reasons.append("source_root")
    if target_root and row.get("target_root_title") == target_root:
        reasons.append("target_root")
    return ",".join(reasons)


def get_promotion_hint(row: Dict[str, str]) -> str:
    target_kind = row["target_kind"]
    classification = row["classification"]
    status = row["status"]

    if not row["target_province_id"]:
        return "blocked:no_target"
    if not row["target_title_path"]:
        return "blocked:no_target_title"
    if target_kind in {"sea", "impassable", "unmapped", "unbound"}:
        return f"blocked:{target_kind}"
    if row["source_history_exists"] != "yes":
        return "blocked:no_source_history"
    if classification == "exact" and status == "mapped" and row["apply_to_history"] == "yes":
        return "ready:exact"

    confidence = float(row["confidence"] or 0.0)
    overlap_score = float(row["overlap_score"] or 0.0)
    target_coverage = float(row["target_coverage"] or 0.0)
    candidate_count = int(row["candidate_count"] or 0)
    target_source_count_all = int(row["target_source_count_all"] or 0)
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


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", default="", help="Filter rows by source_root_title.")
    parser.add_argument("--target-root", default="", help="Filter rows by current target root title.")
    parser.add_argument("--target-title-block", default="", help="Filter rows whose target province is inside the named landed_titles block.")
    parser.add_argument("--cluster-name", default="", help="Output slug override.")
    parser.add_argument("--limit", type=int, default=0, help="Optional row limit after sorting.")
    return parser.parse_args()


def build_slug(source_root: str, target_root: str, cluster_name: str) -> str:
    if cluster_name:
        return re.sub(r"[^a-zA-Z0-9_\-]+", "_", cluster_name).strip("_")
    parts = []
    if source_root:
        parts.append(f"source_{source_root}")
    if target_root:
        parts.append(f"target_{target_root}")
    if not parts:
        parts.append("all")
    return "__".join(parts)


def row_sort_key(row: Dict[str, str]) -> tuple:
    return (
        row["promotion_hint"] != "ready:exact",
        row["promotion_hint"] == "review:manual",
        -float(row["confidence"] or 0.0),
        -float(row["overlap_score"] or 0.0),
        -float(row["target_coverage"] or 0.0),
        row["source_province_id"],
    )


def count_by(rows: Iterable[Dict[str, str]], field: str) -> Dict[str, int]:
    counts: Dict[str, int] = {}
    for row in rows:
        value = row.get(field) or ""
        counts[value] = counts.get(value, 0) + 1
    return dict(sorted(counts.items(), key=lambda item: (-item[1], item[0])))


def main() -> None:
    args = parse_args()
    if not args.source_root and not args.target_root and not args.target_title_block:
        raise SystemExit("At least one of --source-root, --target-root or --target-title-block is required.")

    current_landed_titles_text = CURRENT_LANDED_TITLES_PATH.read_text(encoding="utf-8-sig")
    current_bindings = parse_province_title_bindings(CURRENT_LANDED_TITLES_PATH, "target")
    target_title_block_ids = get_province_ids_from_title_block(current_landed_titles_text, args.target_title_block) if args.target_title_block else set()
    source_history_blocks = get_numeric_history_blocks_from_directory(SOURCE_HISTORY_DIR)
    live_history_blocks = get_numeric_history_blocks_from_file(LIVE_HISTORY_PATH)
    test_history_blocks = get_numeric_history_blocks_from_file(TEST_HISTORY_PATH)

    rows = read_csv(MASTER_PATH)
    target_candidates: Dict[str, List[Dict[str, str]]] = {}
    for row in rows:
        target_id = row.get("target_province_id") or ""
        if not target_id:
            continue
        target_candidates.setdefault(target_id, []).append(row)

    target_meta: Dict[str, Dict[str, str]] = {}
    for target_id, candidate_rows in target_candidates.items():
        sorted_rows = sorted(
            candidate_rows,
            key=lambda item: (
                -float(item.get("overlap_score") or 0.0),
                -float(item.get("confidence") or 0.0),
                item.get("source_province_id") or "",
            ),
        )
        first = sorted_rows[0]
        second_overlap = 0.0
        if len(sorted_rows) > 1:
            second_overlap = float(sorted_rows[1].get("overlap_score") or 0.0)
        target_meta[target_id] = {
            "target_source_count_all": str(len(sorted_rows)),
            "target_best_source_id": first.get("source_province_id", ""),
            "target_best_overlap_score": first.get("overlap_score", "0"),
            "target_second_best_overlap_score": f"{second_overlap:.6f}",
            "target_overlap_gap": f"{float(first.get('overlap_score') or 0.0) - second_overlap:.6f}",
        }

    enriched_rows: List[Dict[str, str]] = []

    for row in rows:
        target_province_id = int(row["target_province_id"]) if row.get("target_province_id") else None
        binding = current_bindings.get(target_province_id or -1, {})
        source_province_id = row["source_province_id"]

        enriched = dict(row)
        enriched.update(
            {
                "target_root_title": binding.get("target_root_title", ""),
                "target_kingdom": binding.get("target_kingdom", ""),
                "target_duchy": binding.get("target_duchy", ""),
                "target_county": binding.get("target_county", ""),
                "target_barony": binding.get("target_barony", ""),
                "target_title_path": binding.get("target_title_path", ""),
                "source_history_exists": "yes" if source_province_id in source_history_blocks else "no",
                "source_history_file": source_history_blocks.get(source_province_id, ""),
                "live_target_history_exists": "yes" if (row.get("target_province_id") or "") in live_history_blocks else "no",
                "test_target_history_exists": "yes" if (row.get("target_province_id") or "") in test_history_blocks else "no",
            }
        )
        meta = target_meta.get(row.get("target_province_id") or "", {})
        enriched.update(meta)
        enriched["target_is_best_source"] = "yes" if meta.get("target_best_source_id") == source_province_id else "no"
        enriched["target_kind"] = get_target_kind(enriched)
        enriched["filter_reason"] = get_filter_reason(enriched, args.source_root, args.target_root)
        if args.target_title_block and (row.get("target_province_id") or "") in target_title_block_ids:
            enriched["filter_reason"] = ",".join([x for x in [enriched["filter_reason"], "target_title_block"] if x])

        if not enriched["filter_reason"]:
            continue

        enriched["promotion_hint"] = get_promotion_hint(enriched)
        enriched_rows.append(enriched)

    enriched_rows.sort(key=row_sort_key)
    if args.limit > 0:
        enriched_rows = enriched_rows[: args.limit]

    slug = build_slug(args.source_root, args.target_root, args.cluster_name)
    csv_path = GENERATED_ROOT / f"{slug}.csv"
    summary_path = GENERATED_ROOT / f"{slug}_summary.md"

    fieldnames = [
        "filter_reason",
        "source_province_id",
        "source_name",
        "source_root_title",
        "source_kingdom",
        "source_duchy",
        "source_county",
        "source_barony",
        "source_rgb",
        "target_province_id",
        "target_rgb",
        "target_name",
        "target_root_title",
        "target_kingdom",
        "target_duchy",
        "target_county",
        "target_barony",
        "target_title_path",
        "classification",
        "status",
        "apply_to_history",
        "confidence",
        "overlap_score",
        "centroid_score",
        "neighbor_score",
        "name_score",
        "target_coverage",
        "overlap_pixels",
        "source_pixel_count",
        "target_pixel_count",
        "candidate_count",
        "target_source_count_all",
        "target_best_source_id",
        "target_best_overlap_score",
        "target_second_best_overlap_score",
        "target_overlap_gap",
        "target_is_best_source",
        "source_history_exists",
        "source_history_file",
        "live_target_history_exists",
        "test_target_history_exists",
        "target_kind",
        "promotion_hint",
        "notes",
        "top_candidates",
    ]
    write_csv(csv_path, enriched_rows, fieldnames)

    summary_lines = [
        "# Province Cluster Review",
        "",
        f"- rows: `{len(enriched_rows)}`",
        f"- source_root filter: `{args.source_root or '<none>'}`",
        f"- target_root filter: `{args.target_root or '<none>'}`",
        f"- target_title_block filter: `{args.target_title_block or '<none>'}`",
        f"- csv: `{csv_path}`",
        "",
        "## Promotion Hints",
        "",
    ]

    for key, value in count_by(enriched_rows, "promotion_hint").items():
        summary_lines.append(f"- `{key}`: `{value}`")

    summary_lines.extend(["", "## Classifications", ""])
    for key, value in count_by(enriched_rows, "classification").items():
        summary_lines.append(f"- `{key}`: `{value}`")

    summary_lines.extend(["", "## Target Kinds", ""])
    for key, value in count_by(enriched_rows, "target_kind").items():
        summary_lines.append(f"- `{key}`: `{value}`")

    write_text(summary_path, "\n".join(summary_lines) + "\n")


if __name__ == "__main__":
    main()
