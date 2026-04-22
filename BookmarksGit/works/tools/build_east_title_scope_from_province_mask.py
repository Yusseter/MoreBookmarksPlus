from __future__ import annotations

import argparse
import csv
import re
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

from PIL import Image


TITLE_RE = re.compile(r"^\s*([ekdcbh]_[A-Za-z0-9_'\-]+)\s*=\s*\{")
PROVINCE_RE = re.compile(r"\bprovince\s*=\s*(\d+)\b")
CAPITAL_RE = re.compile(r"\bcapital\s*=\s*(c_[A-Za-z0-9_'\-]+)\b")
TITLE_TIERS = {"e", "k", "d", "c", "b", "h"}
OUTPUT_SUBDIR = "mask_east_scope"


@dataclass(frozen=True)
class TitleInfo:
    title_id: str
    tier: str
    line_no: int
    parent_id: str
    root_title: str
    path: str


@dataclass(frozen=True)
class StackItem:
    title_id: str
    depth: int


@dataclass(frozen=True)
class ProvinceBinding:
    province_id: int
    line_no: int
    root_title: str
    kingdom: str
    duchy: str
    county: str
    barony: str
    path: str


@dataclass(frozen=True)
class ManualRow:
    line_no: int
    source_title_id: str
    mod_title_id: str
    is_same_title_id: str


def parse_args() -> argparse.Namespace:
    repo_root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(
        description="Build a non-barony east title scope from a province mask PNG and compare it to title_relation_master_manuel.csv."
    )
    parser.add_argument(
        "--mask-png",
        type=Path,
        default=repo_root / "works" / "map_data_sources" / "provinces_birlesim_dogu 2026-04-19.png",
    )
    parser.add_argument("--definition-csv", type=Path, default=repo_root / "map_data" / "definition.csv")
    parser.add_argument(
        "--landed-titles",
        type=Path,
        default=repo_root / "common" / "landed_titles" / "00_landed_titles.txt",
    )
    parser.add_argument("--manual-csv", type=Path, default=repo_root / "title_relation_master_manuel.csv")
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=repo_root
        / "works"
        / "analysis"
        / "generated"
        / "title_relation_manual_validation"
        / OUTPUT_SUBDIR,
    )
    return parser.parse_args()


def strip_comment(line: str) -> str:
    return line.split("#", 1)[0]


def brace_delta(line: str) -> int:
    clean = strip_comment(line)
    return clean.count("{") - clean.count("}")


def tier_of(title_id: str) -> str:
    return title_id.split("_", 1)[0] if "_" in title_id else ""


def is_title_id(value: str) -> bool:
    return tier_of(value) in TITLE_TIERS


def read_mask_rgbs(path: Path) -> set[tuple[int, int, int]]:
    image = Image.open(path).convert("RGBA")
    rgbs: set[tuple[int, int, int]] = set()
    for red, green, blue, alpha in image.getdata():
        if alpha == 0:
            continue
        if (red, green, blue) == (0, 0, 0):
            continue
        rgbs.add((red, green, blue))
    return rgbs


def read_definition(path: Path) -> dict[tuple[int, int, int], list[dict[str, str]]]:
    by_rgb: dict[tuple[int, int, int], list[dict[str, str]]] = defaultdict(list)
    with path.open(encoding="utf-8-sig", newline="") as handle:
        reader = csv.reader(handle, delimiter=";")
        for row in reader:
            if len(row) < 4:
                continue
            try:
                province_id = int(row[0])
                red = int(row[1])
                green = int(row[2])
                blue = int(row[3])
            except ValueError:
                continue
            if province_id == 0:
                continue
            by_rgb[(red, green, blue)].append(
                {
                    "province_id": str(province_id),
                    "red": str(red),
                    "green": str(green),
                    "blue": str(blue),
                    "province_name": row[4] if len(row) > 4 else "",
                    "terrain_or_x": row[5] if len(row) > 5 else "",
                }
            )
    return by_rgb


def parse_landed_titles(
    path: Path,
) -> tuple[dict[str, TitleInfo], Counter[str], dict[int, list[ProvinceBinding]], dict[str, list[str]]]:
    titles: dict[str, TitleInfo] = {}
    title_counts: Counter[str] = Counter()
    province_bindings: dict[int, list[ProvinceBinding]] = defaultdict(list)
    capital_refs_by_owner: dict[str, list[str]] = defaultdict(list)
    stack: list[StackItem] = []
    depth = 0

    for line_no, line in enumerate(path.read_text(encoding="utf-8-sig").splitlines(), start=1):
        clean = strip_comment(line)
        match = TITLE_RE.match(clean)
        if match:
            title_id = match.group(1)
            title_depth = depth + 1
            parent_id = stack[-1].title_id if stack else ""
            path_ids = [item.title_id for item in stack] + [title_id]
            title_counts[title_id] += 1
            if title_id not in titles:
                titles[title_id] = TitleInfo(
                    title_id=title_id,
                    tier=tier_of(title_id),
                    line_no=line_no,
                    parent_id=parent_id,
                    root_title=path_ids[0] if path_ids else title_id,
                    path=" > ".join(path_ids),
                )
            stack.append(StackItem(title_id=title_id, depth=title_depth))

        province_match = PROVINCE_RE.search(clean)
        if province_match and stack:
            province_id = int(province_match.group(1))
            path_ids = [item.title_id for item in stack]
            values = {
                "root_title": "",
                "kingdom": "",
                "duchy": "",
                "county": "",
                "barony": "",
            }
            for title_id in path_ids:
                if title_id.startswith(("e_", "h_")):
                    values["root_title"] = values["root_title"] or title_id
                elif title_id.startswith("k_"):
                    values["kingdom"] = title_id
                elif title_id.startswith("d_"):
                    values["duchy"] = title_id
                elif title_id.startswith("c_"):
                    values["county"] = title_id
                elif title_id.startswith("b_"):
                    values["barony"] = title_id
            province_bindings[province_id].append(
                ProvinceBinding(
                    province_id=province_id,
                    line_no=line_no,
                    root_title=values["root_title"],
                    kingdom=values["kingdom"],
                    duchy=values["duchy"],
                    county=values["county"],
                    barony=values["barony"],
                    path=" > ".join(path_ids),
                )
            )

        capital_match = CAPITAL_RE.search(clean)
        if capital_match and stack:
            owner = stack[-1].title_id
            capital_refs_by_owner[owner].append(capital_match.group(1))

        depth += brace_delta(line)
        while stack and depth < stack[-1].depth:
            stack.pop()
        if depth < 0:
            depth = 0
            stack.clear()

    return titles, title_counts, province_bindings, capital_refs_by_owner


def parse_csv_line(line: str) -> list[str]:
    return next(csv.reader([line], skipinitialspace=True))


def normalize_manual_fields(row: list[str]) -> list[str]:
    normalized = list(row)
    while len(normalized) > 3 and not normalized[-1].strip():
        normalized.pop()
    return normalized


def read_manual_rows(path: Path) -> list[ManualRow]:
    lines = path.read_text(encoding="utf-8-sig").splitlines()
    rows: list[ManualRow] = []
    for line_no, line in enumerate(lines[1:], start=2):
        if not line.strip():
            continue
        parsed = normalize_manual_fields(parse_csv_line(line))
        padded = parsed + [""] * max(0, 3 - len(parsed))
        source_title_id = padded[0].strip()
        if not source_title_id:
            continue
        rows.append(
            ManualRow(
                line_no=line_no,
                source_title_id=source_title_id,
                mod_title_id=padded[1].strip(),
                is_same_title_id=padded[2].strip(),
            )
        )
    return rows


def add_title_with_ancestors(
    title_id: str,
    reason: str,
    titles: dict[str, TitleInfo],
    included: set[str],
    reasons: dict[str, set[str]],
) -> bool:
    if title_id not in titles:
        return False
    changed = False
    for path_title in titles[title_id].path.split(" > "):
        if path_title.startswith("b_"):
            continue
        if path_title not in included:
            included.add(path_title)
            changed = True
        reasons[path_title].add(reason)
    return changed


def build_mask_scope(
    mask_rgbs: set[tuple[int, int, int]],
    definition_by_rgb: dict[tuple[int, int, int], list[dict[str, str]]],
    titles: dict[str, TitleInfo],
    province_bindings: dict[int, list[ProvinceBinding]],
    capital_refs_by_owner: dict[str, list[str]],
) -> tuple[
    set[str],
    dict[str, set[str]],
    list[dict[str, object]],
    list[dict[str, object]],
    list[dict[str, object]],
]:
    included_titles: set[str] = set()
    title_reasons: dict[str, set[str]] = defaultdict(set)
    province_rows: list[dict[str, object]] = []
    unmatched_rgb_rows: list[dict[str, object]] = []
    unbound_province_rows: list[dict[str, object]] = []
    capital_owners_by_county: dict[str, list[str]] = defaultdict(list)
    for owner_title, capital_counties in capital_refs_by_owner.items():
        for capital_county in capital_counties:
            capital_owners_by_county[capital_county].append(owner_title)

    for red, green, blue in sorted(mask_rgbs):
        definition_rows = definition_by_rgb.get((red, green, blue), [])
        if not definition_rows:
            unmatched_rgb_rows.append({"red": red, "green": green, "blue": blue})
            continue

        for definition_row in definition_rows:
            province_id = int(definition_row["province_id"])
            bindings = province_bindings.get(province_id, [])
            if not bindings:
                unbound_province_rows.append(
                    {
                        **definition_row,
                        "binding_status": "missing_landed_title_binding",
                    }
                )
                province_rows.append(
                    {
                        **definition_row,
                        "binding_status": "missing_landed_title_binding",
                        "root_title": "",
                        "kingdom": "",
                        "duchy": "",
                        "county": "",
                        "barony": "",
                        "title_path": "",
                    }
                )
                continue

            for binding in bindings:
                province_rows.append(
                    {
                        **definition_row,
                        "binding_status": "bound",
                        "root_title": binding.root_title,
                        "kingdom": binding.kingdom,
                        "duchy": binding.duchy,
                        "county": binding.county,
                        "barony": binding.barony,
                        "title_path": binding.path,
                        "landed_titles_line_no": binding.line_no,
                    }
                )
                for title_id in binding.path.split(" > "):
                    if title_id.startswith("b_"):
                        continue
                    if is_title_id(title_id):
                        included_titles.add(title_id)
                        title_reasons[title_id].add("province_path")

    changed = True
    while changed:
        changed = False
        for county_title in [title_id for title_id in included_titles if title_id.startswith("c_")]:
            for owner_title in capital_owners_by_county.get(county_title, []):
                if add_title_with_ancestors(
                    owner_title,
                    f"reverse_capital_owner_of:{county_title}",
                    titles,
                    included_titles,
                    title_reasons,
                ):
                    changed = True

    included_titles = {title_id for title_id in included_titles if not title_id.startswith("b_")}
    return included_titles, title_reasons, province_rows, unmatched_rgb_rows, unbound_province_rows


def sort_titles_by_landed_order(title_ids: Iterable[str], titles: dict[str, TitleInfo]) -> list[str]:
    return sorted(title_ids, key=lambda title_id: (titles.get(title_id).line_no if title_id in titles else 10**12, title_id))


def write_csv(path: Path, rows: Iterable[dict[str, object]], fieldnames: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, lineterminator="\n")
        writer.writeheader()
        for row in rows:
            writer.writerow({field: row.get(field, "") for field in fieldnames})


def build_comparison_rows(
    manual_rows: list[ManualRow],
    mask_titles: set[str],
    title_reasons: dict[str, set[str]],
    titles: dict[str, TitleInfo],
) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    manual_non_barony: dict[str, ManualRow] = {}
    for row in manual_rows:
        if row.source_title_id.startswith("b_"):
            continue
        manual_non_barony.setdefault(row.source_title_id, row)

    manual_title_ids = set(manual_non_barony)
    for title_id in sort_titles_by_landed_order(manual_title_ids, titles):
        manual = manual_non_barony[title_id]
        info = titles.get(title_id)
        change = "" if title_id in mask_titles else "removed_by_mask"
        rows.append(
            {
                "source_title_id": title_id,
                "mod_title_id": manual.mod_title_id,
                "is_same_title_id": manual.is_same_title_id,
                "mask_scope_change": change,
                "mask_scope_reasons": ";".join(sorted(title_reasons.get(title_id, []))),
                "source_tier": tier_of(title_id),
                "source_line_no": info.line_no if info else "",
                "source_parent_id": info.parent_id if info else "",
                "source_root_title": info.root_title if info else "",
                "source_title_path": info.path if info else "",
                "manual_line_no": manual.line_no,
            }
        )

    for title_id in sort_titles_by_landed_order(mask_titles - manual_title_ids, titles):
        info = titles.get(title_id)
        rows.append(
            {
                "source_title_id": title_id,
                "mod_title_id": "",
                "is_same_title_id": "",
                "mask_scope_change": "added_by_mask",
                "mask_scope_reasons": ";".join(sorted(title_reasons.get(title_id, []))),
                "source_tier": tier_of(title_id),
                "source_line_no": info.line_no if info else "",
                "source_parent_id": info.parent_id if info else "",
                "source_root_title": info.root_title if info else "",
                "source_title_path": info.path if info else "",
                "manual_line_no": "",
            }
        )

    return rows


def build_manual_like_rows(
    manual_rows: list[ManualRow],
    mask_titles: set[str],
    titles: dict[str, TitleInfo],
) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    manual_non_barony: dict[str, ManualRow] = {}
    for row in manual_rows:
        if row.source_title_id.startswith("b_"):
            continue
        if row.source_title_id not in manual_non_barony:
            manual_non_barony[row.source_title_id] = row
            rows.append(
                {
                    "source_title_id": row.source_title_id,
                    "mod_title_id": row.mod_title_id,
                    "is_same_title_id": row.is_same_title_id,
                    "mask_scope_change": "" if row.source_title_id in mask_titles else "removed_by_mask",
                }
            )

    for title_id in sort_titles_by_landed_order(mask_titles - set(manual_non_barony), titles):
        rows.append(
            {
                "source_title_id": title_id,
                "mod_title_id": "",
                "is_same_title_id": "",
                "mask_scope_change": "added_by_mask",
            }
        )

    return rows


def write_manual_like_csv(path: Path, rows: Iterable[dict[str, object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        handle.write("source_title_id, mod_title_id, is_same_title_id, mask_scope_change,\n")
        for row in rows:
            handle.write(
                f"{row.get('source_title_id', '')}, "
                f"{row.get('mod_title_id', '')}, "
                f"{row.get('is_same_title_id', '')}, "
                f"{row.get('mask_scope_change', '')},\n"
            )


def build_title_rows(
    mask_titles: set[str],
    title_reasons: dict[str, set[str]],
    titles: dict[str, TitleInfo],
) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    for title_id in sort_titles_by_landed_order(mask_titles, titles):
        info = titles.get(title_id)
        rows.append(
            {
                "source_title_id": title_id,
                "source_tier": tier_of(title_id),
                "mask_scope_reasons": ";".join(sorted(title_reasons.get(title_id, []))),
                "source_line_no": info.line_no if info else "",
                "source_parent_id": info.parent_id if info else "",
                "source_root_title": info.root_title if info else "",
                "source_title_path": info.path if info else "",
            }
        )
    return rows


def write_summary(
    path: Path,
    *,
    mask_png: Path,
    definition_csv: Path,
    landed_titles: Path,
    manual_csv: Path,
    mask_rgb_count: int,
    mask_province_count: int,
    unmatched_rgb_count: int,
    unbound_province_count: int,
    mask_title_count: int,
    manual_non_barony_count: int,
    added_count: int,
    removed_count: int,
    unchanged_count: int,
    duplicate_title_count: int,
    output_files: dict[str, Path],
) -> None:
    lines = [
        "# Mask East Title Scope Summary",
        "",
        f"- mask png: {mask_png}",
        f"- definition csv: {definition_csv}",
        f"- landed titles: {landed_titles}",
        f"- manual csv: {manual_csv}",
        "",
        f"- non-black mask rgb count: {mask_rgb_count}",
        f"- matched mask province count: {mask_province_count}",
        f"- unmatched mask rgb count: {unmatched_rgb_count}",
        f"- unbound mask province count: {unbound_province_count}",
        f"- mask non-barony title count: {mask_title_count}",
        f"- manual non-barony title count: {manual_non_barony_count}",
        f"- added_by_mask title count: {added_count}",
        f"- removed_by_mask title count: {removed_count}",
        f"- unchanged title count: {unchanged_count}",
        f"- duplicate source title ids in landed_titles: {duplicate_title_count}",
        "",
        "## Outputs",
    ]
    for label, output_path in output_files.items():
        lines.append(f"- {label}: {output_path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    args = parse_args()

    mask_rgbs = read_mask_rgbs(args.mask_png)
    definition_by_rgb = read_definition(args.definition_csv)
    titles, title_counts, province_bindings, capital_refs_by_owner = parse_landed_titles(args.landed_titles)
    manual_rows = read_manual_rows(args.manual_csv)

    mask_titles, title_reasons, province_rows, unmatched_rgb_rows, unbound_province_rows = build_mask_scope(
        mask_rgbs,
        definition_by_rgb,
        titles,
        province_bindings,
        capital_refs_by_owner,
    )

    comparison_rows = build_comparison_rows(manual_rows, mask_titles, title_reasons, titles)
    manual_like_rows = build_manual_like_rows(manual_rows, mask_titles, titles)
    title_rows = build_title_rows(mask_titles, title_reasons, titles)

    manual_non_barony_ids = {row.source_title_id for row in manual_rows if not row.source_title_id.startswith("b_")}
    added_count = sum(1 for row in comparison_rows if row["mask_scope_change"] == "added_by_mask")
    removed_count = sum(1 for row in comparison_rows if row["mask_scope_change"] == "removed_by_mask")
    unchanged_count = sum(1 for row in comparison_rows if not row["mask_scope_change"])
    matched_province_ids = {
        int(definition_row["province_id"])
        for rgb in mask_rgbs
        for definition_row in definition_by_rgb.get(rgb, [])
    }

    args.output_dir.mkdir(parents=True, exist_ok=True)
    comparison_path = args.output_dir / "title_relation_master_manuel_mask_east_scope.csv"
    manual_like_path = args.output_dir / "title_relation_master_manuel_mask_scope_manual_like.csv"
    titles_path = args.output_dir / "mask_east_scope_titles.csv"
    provinces_path = args.output_dir / "mask_east_scope_provinces.csv"
    unmatched_rgb_path = args.output_dir / "mask_east_scope_unmatched_rgb.csv"
    unbound_provinces_path = args.output_dir / "mask_east_scope_unbound_provinces.csv"
    summary_path = args.output_dir / "mask_east_scope_summary.md"

    write_csv(
        comparison_path,
        comparison_rows,
        [
            "source_title_id",
            "mod_title_id",
            "is_same_title_id",
            "mask_scope_change",
            "mask_scope_reasons",
            "source_tier",
            "source_line_no",
            "source_parent_id",
            "source_root_title",
            "source_title_path",
            "manual_line_no",
        ],
    )
    write_manual_like_csv(manual_like_path, manual_like_rows)
    write_csv(
        titles_path,
        title_rows,
        [
            "source_title_id",
            "source_tier",
            "mask_scope_reasons",
            "source_line_no",
            "source_parent_id",
            "source_root_title",
            "source_title_path",
        ],
    )
    write_csv(
        provinces_path,
        province_rows,
        [
            "province_id",
            "red",
            "green",
            "blue",
            "province_name",
            "terrain_or_x",
            "binding_status",
            "root_title",
            "kingdom",
            "duchy",
            "county",
            "barony",
            "title_path",
            "landed_titles_line_no",
        ],
    )
    write_csv(unmatched_rgb_path, unmatched_rgb_rows, ["red", "green", "blue"])
    write_csv(
        unbound_provinces_path,
        unbound_province_rows,
        ["province_id", "red", "green", "blue", "province_name", "terrain_or_x", "binding_status"],
    )

    duplicate_title_count = sum(1 for _title_id, count in title_counts.items() if count > 1)
    write_summary(
        summary_path,
        mask_png=args.mask_png,
        definition_csv=args.definition_csv,
        landed_titles=args.landed_titles,
        manual_csv=args.manual_csv,
        mask_rgb_count=len(mask_rgbs),
        mask_province_count=len(matched_province_ids),
        unmatched_rgb_count=len(unmatched_rgb_rows),
        unbound_province_count=len(unbound_province_rows),
        mask_title_count=len(mask_titles),
        manual_non_barony_count=len(manual_non_barony_ids),
        added_count=added_count,
        removed_count=removed_count,
        unchanged_count=unchanged_count,
        duplicate_title_count=duplicate_title_count,
        output_files={
            "comparison": comparison_path,
            "manual-like comparison": manual_like_path,
            "mask titles": titles_path,
            "mask provinces": provinces_path,
            "unmatched rgb": unmatched_rgb_path,
            "unbound provinces": unbound_provinces_path,
            "summary": summary_path,
        },
    )

    print(f"mask rgbs: {len(mask_rgbs)}")
    print(f"mask provinces: {len(matched_province_ids)}")
    print(f"mask non-barony titles: {len(mask_titles)}")
    print(f"manual non-barony titles: {len(manual_non_barony_ids)}")
    print(f"added_by_mask: {added_count}")
    print(f"removed_by_mask: {removed_count}")
    print(f"unmatched rgbs: {len(unmatched_rgb_rows)}")
    print(f"unbound provinces: {len(unbound_province_rows)}")
    print(f"summary: {summary_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
