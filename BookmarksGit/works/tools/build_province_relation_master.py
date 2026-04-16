from __future__ import annotations

import csv
import math
import re
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Tuple

from PIL import Image


REPO_ROOT = Path(__file__).resolve().parents[2]
GENERATED_ROOT = REPO_ROOT / "works" / "analysis" / "generated" / "province_relation_mapping"
MASTER_PATH = REPO_ROOT / "works" / "map_data_sources" / "province_relation_master.csv"
MANUAL_REVIEW_PATH = GENERATED_ROOT / "province_relation_manual_review.csv"
PREVIEW_PATH = GENERATED_ROOT / "province_relation_split_merge_preview.csv"
COVERAGE_PATH = GENERATED_ROOT / "province_relation_coverage.csv"
SUMMARY_PATH = GENERATED_ROOT / "province_relation_summary.md"

SOURCE_IMAGE_PATH = REPO_ROOT / "works" / "map_data_sources" / "provinces_modlu_dogu.png"
TARGET_IMAGE_PATH = REPO_ROOT / "map_data" / "provinces.png"
SOURCE_DEFINITION_PATH = REPO_ROOT / "works" / "map_data_sources" / "definition_modlu.csv"
TARGET_DEFINITION_PATH = REPO_ROOT / "map_data" / "definition.csv"
TARGET_TRACKING_PATH = REPO_ROOT / "works" / "analysis" / "generated" / "final_orijinal_tracking_preserve_old_ids.csv"
SOURCE_LANDED_TITLES_PATH = Path(
    r"C:\Program Files (x86)\Steam\steamapps\workshop\content\1158310\2216670956\0backup\common\landed_titles\00_landed_titles.txt"
)


@dataclass
class ProvinceStat:
    count: int = 0
    min_x: int = 10**9
    min_y: int = 10**9
    max_x: int = -1
    max_y: int = -1
    sum_x: int = 0
    sum_y: int = 0

    def update(self, x: int, y: int) -> None:
        self.count += 1
        self.sum_x += x
        self.sum_y += y
        if x < self.min_x:
            self.min_x = x
        if y < self.min_y:
            self.min_y = y
        if x > self.max_x:
            self.max_x = x
        if y > self.max_y:
            self.max_y = y

    @property
    def centroid(self) -> Tuple[float, float]:
        if self.count <= 0:
            return (0.0, 0.0)
        return (self.sum_x / self.count, self.sum_y / self.count)


def ensure_directory(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)


def rgb_to_key(rgb: Tuple[int, int, int]) -> str:
    return f"{rgb[0]},{rgb[1]},{rgb[2]}"


def normalize_name(text: str) -> str:
    normalized = re.sub(r"[^a-z0-9]+", " ", text.lower()).strip()
    tokens = [token for token in normalized.split() if token]
    return " ".join(tokens)


def name_score(source_name: str, target_name: str) -> float:
    source_norm = normalize_name(source_name)
    target_norm = normalize_name(target_name)
    if not source_norm or not target_norm:
        return 0.0
    if source_norm == target_norm:
        return 1.0
    source_tokens = set(source_norm.split())
    target_tokens = set(target_norm.split())
    if not source_tokens or not target_tokens:
        return 0.0
    overlap = len(source_tokens & target_tokens)
    union = len(source_tokens | target_tokens)
    if union <= 0:
        return 0.0
    return overlap / union


def parse_definition(path: Path) -> Dict[str, Dict[str, str]]:
    result: Dict[str, Dict[str, str]] = {}
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        for raw_line in handle:
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split(";")
            if len(parts) < 5:
                continue
            province_id, r, g, b, name = parts[:5]
            if not province_id.isdigit():
                continue
            rgb = f"{r},{g},{b}"
            result[rgb] = {
                "id": province_id,
                "name": name,
                "rgb": rgb,
            }
    return result


def parse_target_tracking(path: Path) -> Dict[int, Dict[str, str]]:
    result: Dict[int, Dict[str, str]] = {}
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            old_subset = (row.get("old_subset") or "").strip()
            if old_subset != "orijinal_dogu":
                continue
            final_new_id = row.get("final_new_id") or ""
            if not final_new_id.isdigit():
                continue
            result[int(final_new_id)] = row
    return result


def parse_landed_title_bindings(path: Path) -> Dict[int, Dict[str, str]]:
    text = path.read_text(encoding="utf-8-sig")
    lines = re.split(r"\r?\n", text)
    stack: List[Tuple[str, int]] = []
    brace_depth = 0
    bindings: Dict[int, Dict[str, str]] = {}

    for line in lines:
        visible = line.split("#", 1)[0]
        title_match = re.match(r"^\s*([ehkdcb]_[A-Za-z0-9_\/\.\-]+)\s*=\s*\{", visible)
        if title_match:
            stack.append((title_match.group(1), brace_depth))

        province_match = re.match(r"^\s*province\s*=\s*(\d+)\s*$", visible)
        if province_match:
            province_id = int(province_match.group(1))
            values = {
                "source_root_title": "",
                "source_kingdom": "",
                "source_duchy": "",
                "source_county": "",
                "source_barony": "",
                "source_title_path": "",
            }
            path_parts: List[str] = []
            for title, _depth in stack:
                path_parts.append(title)
                if title.startswith(("e_", "h_")) and not values["source_root_title"]:
                    values["source_root_title"] = title
                elif title.startswith("k_") and not values["source_kingdom"]:
                    values["source_kingdom"] = title
                elif title.startswith("d_") and not values["source_duchy"]:
                    values["source_duchy"] = title
                elif title.startswith("c_") and not values["source_county"]:
                    values["source_county"] = title
                elif title.startswith("b_") and not values["source_barony"]:
                    values["source_barony"] = title
            values["source_title_path"] = " > ".join(path_parts)
            bindings[province_id] = values

        opens = visible.count("{")
        closes = visible.count("}")
        brace_depth += opens - closes
        while stack and stack[-1][1] >= brace_depth:
            stack.pop()

    return bindings


def candidate_coverage(overlap: int, target_pixels: int) -> float:
    if target_pixels <= 0:
        return 0.0
    return overlap / target_pixels


def centroid_similarity(source: ProvinceStat, target: ProvinceStat, diagonal: float) -> float:
    sx, sy = source.centroid
    tx, ty = target.centroid
    distance = math.dist((sx, sy), (tx, ty))
    max_distance = diagonal * 0.25
    if max_distance <= 0:
        return 0.0
    return max(0.0, 1.0 - (distance / max_distance))


def compute_neighbor_score(
    source_rgb: str,
    target_rgb: str,
    source_neighbors: Dict[str, set[str]],
    target_neighbors: Dict[str, set[str]],
    provisional_best: Dict[str, str],
) -> float:
    source_set = source_neighbors.get(source_rgb, set())
    target_set = target_neighbors.get(target_rgb, set())
    mapped = {provisional_best.get(neighbor, "") for neighbor in source_set}
    mapped.discard("")
    if not mapped and not target_set:
        return 1.0
    if not mapped or not target_set:
        return 0.0
    intersection = len(mapped & target_set)
    union = len(mapped | target_set)
    if union <= 0:
        return 0.0
    return intersection / union


def read_existing_master(path: Path) -> Dict[str, Dict[str, str]]:
    if not path.exists():
        return {}
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        return {row["source_province_id"]: row for row in reader if row.get("source_province_id")}


def write_csv(path: Path, rows: List[Dict[str, str]], fieldnames: List[str]) -> None:
    ensure_directory(path)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def build_image_metrics(
    source_image: Path,
    target_image: Path,
    source_rgb_set: set[str],
    target_rgb_set: set[str],
) -> Tuple[
    Dict[str, ProvinceStat],
    Dict[str, ProvinceStat],
    Counter[Tuple[str, str]],
    Dict[str, set[str]],
    Dict[str, set[str]],
]:
    src = Image.open(source_image).convert("RGB")
    tgt = Image.open(target_image).convert("RGB")
    if src.size != tgt.size:
        raise RuntimeError(f"Image dimensions do not match: {src.size} vs {tgt.size}")

    width, height = src.size
    source_stats: Dict[str, ProvinceStat] = {}
    target_stats: Dict[str, ProvinceStat] = {}
    pair_counts: Counter[Tuple[str, str]] = Counter()
    source_neighbors: Dict[str, set[str]] = defaultdict(set)
    target_neighbors: Dict[str, set[str]] = defaultdict(set)

    src_pixels = src.load()
    tgt_pixels = tgt.load()

    for y in range(height):
        for x in range(width):
            source_rgb = rgb_to_key(src_pixels[x, y])
            target_rgb = rgb_to_key(tgt_pixels[x, y])

            if source_rgb != "0,0,0" and source_rgb in source_rgb_set:
                source_stats.setdefault(source_rgb, ProvinceStat()).update(x, y)
            if target_rgb != "0,0,0" and target_rgb in target_rgb_set:
                target_stats.setdefault(target_rgb, ProvinceStat()).update(x, y)
            if (
                source_rgb != "0,0,0"
                and target_rgb != "0,0,0"
                and source_rgb in source_rgb_set
                and target_rgb in target_rgb_set
            ):
                pair_counts[(source_rgb, target_rgb)] += 1

            if x + 1 < width:
                right_source = rgb_to_key(src_pixels[x + 1, y])
                right_target = rgb_to_key(tgt_pixels[x + 1, y])
                if (
                    source_rgb in source_rgb_set
                    and right_source in source_rgb_set
                    and source_rgb != right_source
                ):
                    source_neighbors[source_rgb].add(right_source)
                    source_neighbors[right_source].add(source_rgb)
                if (
                    target_rgb in target_rgb_set
                    and right_target in target_rgb_set
                    and target_rgb != right_target
                ):
                    target_neighbors[target_rgb].add(right_target)
                    target_neighbors[right_target].add(target_rgb)

            if y + 1 < height:
                down_source = rgb_to_key(src_pixels[x, y + 1])
                down_target = rgb_to_key(tgt_pixels[x, y + 1])
                if (
                    source_rgb in source_rgb_set
                    and down_source in source_rgb_set
                    and source_rgb != down_source
                ):
                    source_neighbors[source_rgb].add(down_source)
                    source_neighbors[down_source].add(source_rgb)
                if (
                    target_rgb in target_rgb_set
                    and down_target in target_rgb_set
                    and target_rgb != down_target
                ):
                    target_neighbors[target_rgb].add(down_target)
                    target_neighbors[down_target].add(target_rgb)

    return source_stats, target_stats, pair_counts, source_neighbors, target_neighbors


def main() -> None:
    GENERATED_ROOT.mkdir(parents=True, exist_ok=True)

    source_definition = parse_definition(SOURCE_DEFINITION_PATH)
    target_definition = parse_definition(TARGET_DEFINITION_PATH)
    managed_target_rows = parse_target_tracking(TARGET_TRACKING_PATH)
    source_bindings = parse_landed_title_bindings(SOURCE_LANDED_TITLES_PATH)

    source_definition_all = {
        rgb: meta
        for rgb, meta in source_definition.items()
        if meta["id"].isdigit()
    }
    target_id_to_meta = {
        int(meta["id"]): meta
        for meta in target_definition.values()
        if meta["id"].isdigit()
    }

    managed_target_ids = set(managed_target_rows.keys())
    target_rgb_to_meta = {
        meta["rgb"]: meta
        for province_id, meta in target_id_to_meta.items()
        if province_id in managed_target_ids
    }

    source_rgb_set = set(source_definition_all.keys())
    target_rgb_set = set(target_rgb_to_meta.keys())
    width, height = Image.open(SOURCE_IMAGE_PATH).size
    diagonal = math.dist((0, 0), (width, height))

    source_stats, target_stats, pair_counts, source_neighbors, target_neighbors = build_image_metrics(
        SOURCE_IMAGE_PATH,
        TARGET_IMAGE_PATH,
        source_rgb_set,
        target_rgb_set,
    )
    source_rgb_to_meta = {
        rgb: source_definition_all[rgb]
        for rgb in source_stats.keys()
        if rgb in source_definition_all
    }

    provisional_best: Dict[str, str] = {}
    candidate_cache: Dict[str, List[Dict[str, float | int | str]]] = {}
    for source_rgb, source_stat in source_stats.items():
        source_pixels = source_stat.count
        candidates: List[Dict[str, float | int | str]] = []
        for target_rgb in target_rgb_set:
            overlap = pair_counts.get((source_rgb, target_rgb), 0)
            if overlap <= 0:
                continue
            target_stat = target_stats.get(target_rgb)
            if target_stat is None:
                continue
            overlap_score = overlap / source_pixels if source_pixels else 0.0
            coverage = candidate_coverage(overlap, target_stat.count)
            candidates.append(
                {
                    "target_rgb": target_rgb,
                    "overlap_pixels": overlap,
                    "overlap_score": overlap_score,
                    "candidate_coverage": coverage,
                }
            )
        candidates.sort(
            key=lambda row: (
                float(row["overlap_score"]),
                float(row["candidate_coverage"]),
                int(row["overlap_pixels"]),
            ),
            reverse=True,
        )
        candidate_cache[source_rgb] = candidates
        if candidates:
            provisional_best[source_rgb] = str(candidates[0]["target_rgb"])

    merge_targets = Counter(provisional_best.values())
    existing_master = read_existing_master(MASTER_PATH)

    fieldnames = [
        "source_province_id",
        "source_rgb",
        "target_province_id",
        "target_rgb",
        "classification",
        "confidence",
        "overlap_score",
        "centroid_score",
        "neighbor_score",
        "source_root_title",
        "source_kingdom",
        "source_duchy",
        "source_county",
        "source_barony",
        "apply_to_history",
        "notes",
        "status",
        "source_name",
        "target_name",
        "target_coverage",
        "overlap_pixels",
        "source_pixel_count",
        "target_pixel_count",
        "candidate_count",
        "name_score",
        "top_candidates",
    ]

    preview_fieldnames = [
        "source_province_id",
        "source_rgb",
        "source_name",
        "candidate_rank",
        "target_province_id",
        "target_rgb",
        "target_name",
        "overlap_pixels",
        "overlap_score",
        "target_coverage",
    ]

    coverage_fieldnames = [
        "source_province_id",
        "source_name",
        "source_rgb",
        "classification",
        "status",
        "apply_to_history",
        "target_province_id",
        "target_name",
        "confidence",
    ]

    master_rows: List[Dict[str, str]] = []
    preview_rows: List[Dict[str, str]] = []
    coverage_rows: List[Dict[str, str]] = []

    for source_rgb, source_meta in sorted(source_rgb_to_meta.items(), key=lambda item: int(item[1]["id"])):
        source_id = source_meta["id"]
        source_name = source_meta["name"]
        source_stat = source_stats.get(source_rgb)
        source_binding = source_bindings.get(int(source_id), {})
        existing_row = existing_master.get(source_id, {})

        row: Dict[str, str] = {
            "source_province_id": source_id,
            "source_rgb": source_rgb,
            "target_province_id": "",
            "target_rgb": "",
            "classification": "manual_review",
            "confidence": "0.000000",
            "overlap_score": "0.000000",
            "centroid_score": "0.000000",
            "neighbor_score": "0.000000",
            "source_root_title": source_binding.get("source_root_title", ""),
            "source_kingdom": source_binding.get("source_kingdom", ""),
            "source_duchy": source_binding.get("source_duchy", ""),
            "source_county": source_binding.get("source_county", ""),
            "source_barony": source_binding.get("source_barony", ""),
            "apply_to_history": "no",
            "notes": "",
            "status": "manual_review",
            "source_name": source_name,
            "target_name": "",
            "target_coverage": "0.000000",
            "overlap_pixels": "0",
            "source_pixel_count": str(source_stat.count if source_stat else 0),
            "target_pixel_count": "0",
            "candidate_count": "0",
            "name_score": "0.000000",
            "top_candidates": "",
        }

        candidates = candidate_cache.get(source_rgb, [])
        row["candidate_count"] = str(len(candidates))
        top_candidates: List[str] = []
        for index, candidate in enumerate(candidates[:5], start=1):
            target_rgb = str(candidate["target_rgb"])
            target_meta = target_rgb_to_meta[target_rgb]
            top_candidates.append(
                f"{index}:{target_meta['id']}:{candidate['overlap_score']:.4f}:{candidate['candidate_coverage']:.4f}"
            )
            preview_rows.append(
                {
                    "source_province_id": source_id,
                    "source_rgb": source_rgb,
                    "source_name": source_name,
                    "candidate_rank": str(index),
                    "target_province_id": target_meta["id"],
                    "target_rgb": target_rgb,
                    "target_name": target_meta["name"],
                    "overlap_pixels": str(candidate["overlap_pixels"]),
                    "overlap_score": f"{float(candidate['overlap_score']):.6f}",
                    "target_coverage": f"{float(candidate['candidate_coverage']):.6f}",
                }
            )
        row["top_candidates"] = " | ".join(top_candidates)

        if candidates and source_stat:
            best = candidates[0]
            target_rgb = str(best["target_rgb"])
            target_meta = target_rgb_to_meta[target_rgb]
            target_stat = target_stats[target_rgb]
            n_score = compute_neighbor_score(source_rgb, target_rgb, source_neighbors, target_neighbors, provisional_best)
            c_score = centroid_similarity(source_stat, target_stat, diagonal)
            nm_score = name_score(source_name, target_meta["name"])
            overlap_score = float(best["overlap_score"])
            t_coverage = float(best["candidate_coverage"])
            confidence = (
                0.50 * overlap_score
                + 0.15 * t_coverage
                + 0.20 * n_score
                + 0.10 * c_score
                + 0.05 * nm_score
            )
            runner_up = candidates[1] if len(candidates) > 1 else None
            runner_conf = 0.0
            if runner_up:
                target_rgb_2 = str(runner_up["target_rgb"])
                target_stat_2 = target_stats[target_rgb_2]
                runner_conf = (
                    0.50 * float(runner_up["overlap_score"])
                    + 0.15 * float(runner_up["candidate_coverage"])
                    + 0.20 * compute_neighbor_score(
                        source_rgb, target_rgb_2, source_neighbors, target_neighbors, provisional_best
                    )
                    + 0.10 * centroid_similarity(source_stat, target_stat_2, diagonal)
                    + 0.05 * name_score(source_name, target_rgb_to_meta[target_rgb_2]["name"])
                )

            classification = "manual_review"
            notes = []
            if merge_targets[target_rgb] > 1 and overlap_score >= 0.25:
                classification = "merge"
                notes.append("best_target_shared_by_multiple_sources")
            elif overlap_score >= 0.80 and t_coverage >= 0.60 and confidence >= 0.80 and (confidence - runner_conf) >= 0.10:
                classification = "exact"
                notes.append("dominant_overlap")
            elif len(candidates) > 1 and (overlap_score + float(candidates[1]["overlap_score"])) >= 0.80:
                classification = "split"
                notes.append("top_two_overlap_share")
            elif overlap_score >= 0.50 and confidence >= 0.60:
                classification = "manual_review"
                notes.append("strong_but_not_exact")
            else:
                classification = "manual_review"
                notes.append("low_confidence")

            if existing_row and existing_row.get("notes", "").strip() and not existing_row.get("notes", "").startswith("auto:"):
                row["notes"] = existing_row["notes"]
                row["classification"] = existing_row.get("classification", classification)
                row["status"] = existing_row.get("status", "manual_review")
                row["apply_to_history"] = existing_row.get("apply_to_history", "no")
            else:
                row["classification"] = classification
                row["status"] = "mapped" if classification == "exact" else "manual_review"
                row["apply_to_history"] = "yes" if classification == "exact" else "no"
                row["notes"] = "auto: " + ",".join(notes)

            row["target_province_id"] = target_meta["id"]
            row["target_rgb"] = target_rgb
            row["target_name"] = target_meta["name"]
            row["confidence"] = f"{confidence:.6f}"
            row["overlap_score"] = f"{overlap_score:.6f}"
            row["centroid_score"] = f"{c_score:.6f}"
            row["neighbor_score"] = f"{n_score:.6f}"
            row["target_coverage"] = f"{t_coverage:.6f}"
            row["overlap_pixels"] = str(best["overlap_pixels"])
            row["target_pixel_count"] = str(target_stat.count)
            row["name_score"] = f"{nm_score:.6f}"
        else:
            row["notes"] = "auto: no_overlap_candidate"

        master_rows.append(row)
        coverage_rows.append(
            {
                "source_province_id": row["source_province_id"],
                "source_name": row["source_name"],
                "source_rgb": row["source_rgb"],
                "classification": row["classification"],
                "status": row["status"],
                "apply_to_history": row["apply_to_history"],
                "target_province_id": row["target_province_id"],
                "target_name": row["target_name"],
                "confidence": row["confidence"],
            }
        )

    manual_review_rows = [row for row in master_rows if row["status"] != "mapped"]
    exact_rows = [row for row in master_rows if row["status"] == "mapped" and row["classification"] == "exact"]
    split_merge_rows = [row for row in master_rows if row["classification"] in {"split", "merge"}]

    write_csv(MASTER_PATH, master_rows, fieldnames)
    write_csv(MANUAL_REVIEW_PATH, manual_review_rows, fieldnames)
    write_csv(PREVIEW_PATH, preview_rows, preview_fieldnames)
    write_csv(COVERAGE_PATH, coverage_rows, coverage_fieldnames)

    summary_lines = [
        "# Province Relation Summary",
        "",
        f"- master rows: `{len(master_rows)}`",
        f"- exact mapped rows: `{len(exact_rows)}`",
        f"- split/merge rows: `{len(split_merge_rows)}`",
        f"- manual review rows: `{len(manual_review_rows)}`",
        "",
        "## Classification Counts",
        "",
    ]

    class_counts = Counter(row["classification"] for row in master_rows)
    for classification, count in sorted(class_counts.items()):
        summary_lines.append(f"- `{classification}`: `{count}`")

    summary_lines.extend(
        [
            "",
            "## Notes",
            "",
            "- Source subset is `modlu_dogu`; target subset is current final provinces traced from `orijinal_dogu`.",
            "- Matching is identity-warp for this run because source and target province atlases already share dimensions.",
            "- Only `exact` rows are marked `apply_to_history = yes`.",
        ]
    )

    ensure_directory(SUMMARY_PATH)
    SUMMARY_PATH.write_text("\r\n".join(summary_lines) + "\r\n", encoding="utf-8")


if __name__ == "__main__":
    main()
