from __future__ import annotations

import argparse
import csv
import hashlib
import re
from collections import Counter, defaultdict
from dataclasses import dataclass
from difflib import SequenceMatcher
from pathlib import Path
from typing import Iterable

from PIL import Image


TITLE_RE = re.compile(r"^\s*([ekdcbh]_[A-Za-z0-9_'\-]+)\s*=\s*\{")
PROVINCE_RE = re.compile(r"\bprovince\s*=\s*(\d+)\b")


@dataclass(frozen=True)
class TitleBlock:
    title_id: str
    source_file: str
    start_line: int
    end_line: int
    parent_id: str
    root_title: str
    path: str
    text: str
    normalized_text: str
    normalized_hash: str
    province_ids: tuple[int, ...]


def parse_args() -> argparse.Namespace:
    repo_root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(
        description="Audit current county blocks against expected map source and vanilla/mod source blocks."
    )
    parser.add_argument("--current-landed-titles", type=Path, default=repo_root / "common/landed_titles/00_landed_titles.txt")
    parser.add_argument(
        "--vanilla-landed-titles-dir",
        type=Path,
        default=Path(r"C:\Program Files (x86)\Steam\steamapps\common\Crusader Kings III\game\common\landed_titles"),
    )
    parser.add_argument(
        "--mod-landed-titles-dir",
        type=Path,
        default=Path(r"F:\Storage\Codding\git\Crusader Kings III\Leviathonlx MoreBookmarks-Plus\BookmarksGit\common\landed_titles"),
    )
    parser.add_argument("--definition-csv", type=Path, default=repo_root / "map_data/definition.csv")
    parser.add_argument(
        "--east-mask",
        type=Path,
        default=repo_root / "works/map_data_sources/provinces_birlesim_dogu 2026-04-19.png",
    )
    parser.add_argument("--mod-kalan-mask", type=Path, default=repo_root / "works/map_data_sources/provinces_modlu_kalan.png")
    parser.add_argument("--final-provinces", type=Path, default=repo_root / "map_data/provinces.png")
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=repo_root / "works/analysis/generated/landed_titles_source_audit",
    )
    return parser.parse_args()


def strip_comment(line: str) -> str:
    return line.split("#", 1)[0]


def normalize_block(text: str) -> str:
    lines = []
    for line in text.splitlines():
        clean = strip_comment(line).strip()
        if not clean:
            continue
        clean = re.sub(r"\s+", " ", clean)
        lines.append(clean)
    return "\n".join(lines)


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8-sig")


def parse_title_blocks(path: Path, tier: str = "c") -> list[TitleBlock]:
    lines = read_text(path).splitlines()
    blocks: list[TitleBlock] = []
    stack: list[dict[str, object]] = []
    depth = 0

    for index, line in enumerate(lines):
        clean = strip_comment(line)
        match = TITLE_RE.match(clean)
        if match:
            title_id = match.group(1)
            path_ids = [str(item["title_id"]) for item in stack] + [title_id]
            stack.append(
                {
                    "title_id": title_id,
                    "start_index": index,
                    "start_line": index + 1,
                    "depth": depth + 1,
                    "parent_id": path_ids[-2] if len(path_ids) > 1 else "",
                    "root_title": path_ids[0],
                    "path": " > ".join(path_ids),
                }
            )

        depth += clean.count("{") - clean.count("}")
        while stack and depth < int(stack[-1]["depth"]):
            item = stack.pop()
            title_id = str(item["title_id"])
            if title_id.startswith(f"{tier}_"):
                block_lines = lines[int(item["start_index"]) : index + 1]
                text = "\n".join(block_lines)
                normalized = normalize_block(text)
                province_ids = tuple(int(value) for value in PROVINCE_RE.findall(text))
                blocks.append(
                    TitleBlock(
                        title_id=title_id,
                        source_file=str(path),
                        start_line=int(item["start_line"]),
                        end_line=index + 1,
                        parent_id=str(item["parent_id"]),
                        root_title=str(item["root_title"]),
                        path=str(item["path"]),
                        text=text,
                        normalized_text=normalized,
                        normalized_hash=hashlib.sha256(normalized.encode("utf-8")).hexdigest(),
                        province_ids=province_ids,
                    )
                )
        if depth < 0:
            depth = 0
            stack.clear()

    return blocks


def parse_blocks_from_dir(path: Path) -> dict[str, list[TitleBlock]]:
    result: dict[str, list[TitleBlock]] = defaultdict(list)
    for file_path in sorted(path.glob("*.txt")):
        for block in parse_title_blocks(file_path):
            result[block.title_id].append(block)
    return result


def read_definition(path: Path) -> dict[int, tuple[int, int, int, str]]:
    result: dict[int, tuple[int, int, int, str]] = {}
    with path.open(encoding="utf-8-sig", newline="") as handle:
        reader = csv.reader(handle, delimiter=";")
        for row in reader:
            if len(row) < 5:
                continue
            try:
                province_id = int(row[0])
                red = int(row[1])
                green = int(row[2])
                blue = int(row[3])
            except ValueError:
                continue
            result[province_id] = (red, green, blue, row[4])
    return result


def read_rgb_set(path: Path) -> set[tuple[int, int, int]]:
    image = Image.open(path).convert("RGB")
    return set(image.getdata()) - {(0, 0, 0)}


def classify_province(
    province_id: int,
    definition: dict[int, tuple[int, int, int, str]],
    east_rgbs: set[tuple[int, int, int]],
    mod_kalan_rgbs: set[tuple[int, int, int]],
    final_rgbs: set[tuple[int, int, int]],
) -> dict[str, object]:
    if province_id not in definition:
        return {
            "province_id": province_id,
            "rgb": "",
            "province_name": "",
            "province_source": "missing_definition",
            "in_final_map": "",
        }

    red, green, blue, province_name = definition[province_id]
    rgb = (red, green, blue)
    in_east = rgb in east_rgbs
    in_mod_kalan = rgb in mod_kalan_rgbs
    in_final = rgb in final_rgbs
    if in_east and in_mod_kalan:
        source = "both_masks"
    elif in_east:
        source = "vanilla_east"
    elif in_mod_kalan:
        source = "mod_kalan"
    elif in_final:
        source = "final_only_unclassified"
    else:
        source = "not_in_masks_or_final"
    return {
        "province_id": province_id,
        "rgb": f"{red},{green},{blue}",
        "province_name": province_name,
        "province_source": source,
        "in_final_map": "yes" if in_final else "no",
    }


def expected_source_from_counts(counts: Counter[str]) -> str:
    known_total = counts["vanilla_east"] + counts["mod_kalan"]
    if known_total == 0:
        if sum(counts.values()) == 0:
            return "no_provinces"
        return "unknown"
    if counts["vanilla_east"] and not counts["mod_kalan"] and counts["both_masks"] == 0:
        if known_total == sum(counts.values()):
            return "vanilla"
        return "vanilla_with_unknown"
    if counts["mod_kalan"] and not counts["vanilla_east"] and counts["both_masks"] == 0:
        if known_total == sum(counts.values()):
            return "mod"
        return "mod_with_unknown"
    return "mixed"


def best_match(block: TitleBlock, candidates: list[TitleBlock]) -> tuple[str, str, float]:
    if not candidates:
        return "", "", 0.0
    exact = [candidate for candidate in candidates if candidate.normalized_hash == block.normalized_hash]
    if exact:
        first = exact[0]
        return "yes", f"{first.source_file}:{first.start_line}", 1.0
    best = max(candidates, key=lambda candidate: SequenceMatcher(None, block.normalized_text, candidate.normalized_text).ratio())
    ratio = SequenceMatcher(None, block.normalized_text, best.normalized_text).ratio()
    return "no", f"{best.source_file}:{best.start_line}", ratio


def current_source_label(vanilla_exact: str, mod_exact: str, vanilla_ratio: float, mod_ratio: float) -> str:
    if vanilla_exact == "yes" and mod_exact == "yes":
        return "both_exact"
    if vanilla_exact == "yes":
        return "vanilla_exact"
    if mod_exact == "yes":
        return "mod_exact"
    if vanilla_ratio == 0.0 and mod_ratio == 0.0:
        return "no_source_candidate"
    if vanilla_ratio >= mod_ratio:
        return "vanilla_closest"
    return "mod_closest"


def audit_status(expected_source: str, source_label: str) -> str:
    if expected_source in {"mixed", "vanilla_with_unknown", "mod_with_unknown", "unknown"}:
        return f"manual_review:{expected_source}"
    if expected_source == "no_provinces":
        return "skip:no_provinces"
    if expected_source == "vanilla":
        if source_label in {"vanilla_exact", "both_exact"}:
            return "ok"
        if source_label == "mod_exact":
            return "mismatch:expected_vanilla_current_mod"
        return "review:expected_vanilla_source_not_exact"
    if expected_source == "mod":
        if source_label in {"mod_exact", "both_exact"}:
            return "ok"
        if source_label == "vanilla_exact":
            return "mismatch:expected_mod_current_vanilla"
        return "review:expected_mod_source_not_exact"
    return "review:unhandled"


def build_fix_plan_row(row: dict[str, object]) -> dict[str, object]:
    audit = str(row["audit_status"])
    expected = str(row["expected_source"])
    current = str(row["current_block_source"])

    if audit == "ok":
        return {
            "county_id": row["county_id"],
            "action": "no_action",
            "expected_source": expected,
            "current_block_source": current,
            "source_block_path": "",
            "confidence": "not_needed",
            "reason": "current county block already matches expected source class",
        }

    if audit == "mismatch:expected_mod_current_vanilla":
        source_path = str(row["mod_best_match"])
        if not source_path:
            return {
                "county_id": row["county_id"],
                "action": "manual_review",
                "expected_source": expected,
                "current_block_source": current,
                "source_block_path": "",
                "confidence": "manual",
                "reason": "expected mod source, but no mod county block candidate was found",
            }
        return {
            "county_id": row["county_id"],
            "action": "replace_with_mod_block",
            "expected_source": expected,
            "current_block_source": current,
            "source_block_path": source_path,
            "confidence": "high",
            "reason": "all classified county provinces are in mod_kalan, while current block is exact vanilla",
        }

    if audit == "mismatch:expected_vanilla_current_mod":
        source_path = str(row["vanilla_best_match"])
        if not source_path:
            return {
                "county_id": row["county_id"],
                "action": "manual_review",
                "expected_source": expected,
                "current_block_source": current,
                "source_block_path": "",
                "confidence": "manual",
                "reason": "expected vanilla source, but no vanilla county block candidate was found",
            }
        return {
            "county_id": row["county_id"],
            "action": "replace_with_vanilla_block",
            "expected_source": expected,
            "current_block_source": current,
            "source_block_path": source_path,
            "confidence": "review_required",
            "reason": "reverse mismatch; check border or intentional mod-canonical cases before applying",
        }

    preferred_source = ""
    if expected.startswith("mod"):
        preferred_source = str(row["mod_best_match"])
    elif expected.startswith("vanilla"):
        preferred_source = str(row["vanilla_best_match"])

    return {
        "county_id": row["county_id"],
        "action": "manual_review",
        "expected_source": expected,
        "current_block_source": current,
        "source_block_path": preferred_source,
        "confidence": "manual",
        "reason": f"audit_status={audit}; not safe for automatic source replacement",
    }


def write_csv(path: Path, rows: Iterable[dict[str, object]], fieldnames: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, lineterminator="\n")
        writer.writeheader()
        for row in rows:
            writer.writerow({field: row.get(field, "") for field in fieldnames})


def write_fix_plan_summary(path: Path, fix_plan_rows: list[dict[str, object]], output_files: dict[str, Path]) -> None:
    action_counts = Counter(str(row["action"]) for row in fix_plan_rows)
    confidence_counts = Counter(str(row["confidence"]) for row in fix_plan_rows)
    lines = [
        "# County Source Fix Plan",
        "",
        f"- plan rows: {len(fix_plan_rows)}",
        "",
        "## Actions",
    ]
    for key, count in action_counts.most_common():
        lines.append(f"- {key}: {count}")
    lines.extend(["", "## Confidence"])
    for key, count in confidence_counts.most_common():
        lines.append(f"- {key}: {count}")
    lines.extend(["", "## Outputs"])
    for label, output_path in output_files.items():
        lines.append(f"- {label}: {output_path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_summary(path: Path, rows: list[dict[str, object]], province_rows: list[dict[str, object]], output_files: dict[str, Path]) -> None:
    status_counts = Counter(str(row["audit_status"]) for row in rows)
    expected_counts = Counter(str(row["expected_source"]) for row in rows)
    source_counts = Counter(str(row["current_block_source"]) for row in rows)
    province_counts = Counter(str(row["province_source"]) for row in province_rows)
    lines = [
        "# Landed Title County Source Audit",
        "",
        f"- county rows: {len(rows)}",
        f"- province rows: {len(province_rows)}",
        "",
        "## Audit Status",
    ]
    for key, count in status_counts.most_common():
        lines.append(f"- {key}: {count}")
    lines.extend(["", "## Expected Source"])
    for key, count in expected_counts.most_common():
        lines.append(f"- {key}: {count}")
    lines.extend(["", "## Current Block Source"])
    for key, count in source_counts.most_common():
        lines.append(f"- {key}: {count}")
    lines.extend(["", "## Province Source"])
    for key, count in province_counts.most_common():
        lines.append(f"- {key}: {count}")
    lines.extend(["", "## Outputs"])
    for label, output_path in output_files.items():
        lines.append(f"- {label}: {output_path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    args = parse_args()
    definition = read_definition(args.definition_csv)
    east_rgbs = read_rgb_set(args.east_mask)
    mod_kalan_rgbs = read_rgb_set(args.mod_kalan_mask)
    final_rgbs = read_rgb_set(args.final_provinces)

    current_blocks = parse_title_blocks(args.current_landed_titles)
    vanilla_blocks = parse_blocks_from_dir(args.vanilla_landed_titles_dir)
    mod_blocks = parse_blocks_from_dir(args.mod_landed_titles_dir)

    county_rows: list[dict[str, object]] = []
    province_rows: list[dict[str, object]] = []
    for block in current_blocks:
        province_details = [
            classify_province(province_id, definition, east_rgbs, mod_kalan_rgbs, final_rgbs)
            for province_id in block.province_ids
        ]
        counts = Counter(str(detail["province_source"]) for detail in province_details)
        expected_source = expected_source_from_counts(counts)
        vanilla_exact, vanilla_match, vanilla_ratio = best_match(block, vanilla_blocks.get(block.title_id, []))
        mod_exact, mod_match, mod_ratio = best_match(block, mod_blocks.get(block.title_id, []))
        source_label = current_source_label(vanilla_exact, mod_exact, vanilla_ratio, mod_ratio)
        status = audit_status(expected_source, source_label)

        for detail in province_details:
            province_rows.append(
                {
                    "county_id": block.title_id,
                    "county_path": block.path,
                    "county_line": block.start_line,
                    **detail,
                }
            )

        county_rows.append(
            {
                "county_id": block.title_id,
                "audit_status": status,
                "expected_source": expected_source,
                "current_block_source": source_label,
                "current_file": block.source_file,
                "current_start_line": block.start_line,
                "current_end_line": block.end_line,
                "current_parent_id": block.parent_id,
                "current_root_title": block.root_title,
                "current_title_path": block.path,
                "province_ids": " ".join(str(province_id) for province_id in block.province_ids),
                "province_names": " | ".join(str(detail["province_name"]) for detail in province_details),
                "province_sources": " | ".join(str(detail["province_source"]) for detail in province_details),
                "vanilla_east_count": counts["vanilla_east"],
                "mod_kalan_count": counts["mod_kalan"],
                "both_masks_count": counts["both_masks"],
                "unknown_count": counts["missing_definition"] + counts["final_only_unclassified"] + counts["not_in_masks_or_final"],
                "vanilla_exact": vanilla_exact,
                "vanilla_best_match": vanilla_match,
                "vanilla_similarity": f"{vanilla_ratio:.6f}",
                "mod_exact": mod_exact,
                "mod_best_match": mod_match,
                "mod_similarity": f"{mod_ratio:.6f}",
            }
        )

    high_signal = [row for row in county_rows if str(row["audit_status"]).startswith("mismatch:")]
    manual_review = [row for row in county_rows if str(row["audit_status"]).startswith(("manual_review:", "review:"))]
    fix_plan_rows = [build_fix_plan_row(row) for row in county_rows]

    args.output_dir.mkdir(parents=True, exist_ok=True)
    county_path = args.output_dir / "county_source_audit.csv"
    high_signal_path = args.output_dir / "county_source_high_signal_mismatches.csv"
    manual_review_path = args.output_dir / "county_source_manual_review.csv"
    province_path = args.output_dir / "county_source_province_detail.csv"
    fix_plan_path = args.output_dir / "county_source_fix_plan.csv"
    summary_path = args.output_dir / "county_source_audit_summary.md"
    fix_plan_summary_path = args.output_dir / "county_source_fix_plan_summary.md"

    county_fields = [
        "county_id",
        "audit_status",
        "expected_source",
        "current_block_source",
        "current_file",
        "current_start_line",
        "current_end_line",
        "current_parent_id",
        "current_root_title",
        "current_title_path",
        "province_ids",
        "province_names",
        "province_sources",
        "vanilla_east_count",
        "mod_kalan_count",
        "both_masks_count",
        "unknown_count",
        "vanilla_exact",
        "vanilla_best_match",
        "vanilla_similarity",
        "mod_exact",
        "mod_best_match",
        "mod_similarity",
    ]
    province_fields = [
        "county_id",
        "county_path",
        "county_line",
        "province_id",
        "rgb",
        "province_name",
        "province_source",
        "in_final_map",
    ]
    fix_plan_fields = [
        "county_id",
        "action",
        "expected_source",
        "current_block_source",
        "source_block_path",
        "confidence",
        "reason",
    ]
    write_csv(county_path, county_rows, county_fields)
    write_csv(high_signal_path, high_signal, county_fields)
    write_csv(manual_review_path, manual_review, county_fields)
    write_csv(province_path, province_rows, province_fields)
    write_csv(fix_plan_path, fix_plan_rows, fix_plan_fields)
    write_summary(
        summary_path,
        county_rows,
        province_rows,
        {
            "county audit": county_path,
            "high signal mismatches": high_signal_path,
            "manual review": manual_review_path,
            "province detail": province_path,
            "fix plan": fix_plan_path,
            "fix plan summary": fix_plan_summary_path,
            "summary": summary_path,
        },
    )
    write_fix_plan_summary(
        fix_plan_summary_path,
        fix_plan_rows,
        {
            "fix plan": fix_plan_path,
            "fix plan summary": fix_plan_summary_path,
        },
    )

    print(f"county rows: {len(county_rows)}")
    print(f"high signal mismatches: {len(high_signal)}")
    print(f"manual/review rows: {len(manual_review)}")
    print(f"fix plan: {fix_plan_path}")
    print(f"summary: {summary_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
