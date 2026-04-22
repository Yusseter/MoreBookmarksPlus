from __future__ import annotations

import argparse
import csv
import hashlib
import re
from dataclasses import dataclass
from pathlib import Path


TITLE_PATTERN = re.compile(r"^\s*([ekdcbh]_[A-Za-z0-9_]+)\s*=\s*\{")


@dataclass
class BlockInfo:
    title_id: str
    start_line: int
    end_line: int
    line_count: int
    sha256: str
    normalized_text: str


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Compare landed_titles blocks between two repos by title id."
    )
    parser.add_argument("--source-landed-titles", type=Path, required=True)
    parser.add_argument("--mod-landed-titles", type=Path, required=True)
    parser.add_argument("--report-dir", type=Path, required=True)
    return parser.parse_args()


def strip_comment(line: str) -> str:
    if "#" in line:
        return line.split("#", 1)[0]
    return line


def normalize_block(text: str) -> str:
    normalized_lines = []
    for raw_line in text.splitlines():
        line = strip_comment(raw_line).rstrip()
        if line.strip():
            normalized_lines.append(line)
    return "\n".join(normalized_lines)


def parse_blocks(path: Path) -> dict[str, BlockInfo]:
    lines = path.read_text(encoding="utf-8-sig").splitlines()
    blocks: dict[str, BlockInfo] = {}
    stack: list[tuple[str, int, int]] = []
    depth = 0

    for line_number, line in enumerate(lines, start=1):
        stripped = strip_comment(line)
        match = TITLE_PATTERN.match(stripped)
        if match:
            title_id = match.group(1)
            stack.append((title_id, line_number, depth))

        depth += stripped.count("{")
        depth -= stripped.count("}")

        while stack and depth == stack[-1][2]:
            title_id, start_line, base_depth = stack.pop()
            block_lines = lines[start_line - 1 : line_number]
            normalized_text = normalize_block("\n".join(block_lines))
            sha256 = hashlib.sha256(normalized_text.encode("utf-8")).hexdigest()
            blocks[title_id] = BlockInfo(
                title_id=title_id,
                start_line=start_line,
                end_line=line_number,
                line_count=line_number - start_line + 1,
                sha256=sha256,
                normalized_text=normalized_text,
            )

    return blocks


def write_single_column_csv(path: Path, header: str, rows: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle, lineterminator="\n")
        writer.writerow([header])
        for row in rows:
            writer.writerow([row])


def write_changed_csv(path: Path, rows: list[tuple[str, BlockInfo, BlockInfo]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle, lineterminator="\n")
        writer.writerow(
            [
                "title_id",
                "source_start_line",
                "source_end_line",
                "source_line_count",
                "mod_start_line",
                "mod_end_line",
                "mod_line_count",
                "source_sha256",
                "mod_sha256",
            ]
        )
        for title_id, source_info, mod_info in rows:
            writer.writerow(
                [
                    title_id,
                    source_info.start_line,
                    source_info.end_line,
                    source_info.line_count,
                    mod_info.start_line,
                    mod_info.end_line,
                    mod_info.line_count,
                    source_info.sha256,
                    mod_info.sha256,
                ]
            )


def write_summary(
    path: Path,
    source_block_count: int,
    mod_block_count: int,
    shared_count: int,
    identical_count: int,
    changed_count: int,
    source_only_count: int,
    mod_only_count: int,
) -> None:
    lines = [
        "# Landed Titles Block Compare Summary",
        "",
        f"- source block count: {source_block_count}",
        f"- mod block count: {mod_block_count}",
        f"- shared block count: {shared_count}",
        f"- shared identical block count: {identical_count}",
        f"- shared changed block count: {changed_count}",
        f"- source-only block count: {source_only_count}",
        f"- mod-only block count: {mod_only_count}",
    ]
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    args = parse_args()
    source_blocks = parse_blocks(args.source_landed_titles)
    mod_blocks = parse_blocks(args.mod_landed_titles)

    source_ids = set(source_blocks)
    mod_ids = set(mod_blocks)
    shared_ids = source_ids & mod_ids
    source_only_ids = sorted(source_ids - mod_ids)
    mod_only_ids = sorted(mod_ids - source_ids)

    identical_ids: list[str] = []
    changed_rows: list[tuple[str, BlockInfo, BlockInfo]] = []
    for title_id in sorted(shared_ids):
        source_info = source_blocks[title_id]
        mod_info = mod_blocks[title_id]
        if source_info.sha256 == mod_info.sha256:
            identical_ids.append(title_id)
        else:
            changed_rows.append((title_id, source_info, mod_info))

    report_dir = args.report_dir
    write_single_column_csv(report_dir / "shared_identical_titles.csv", "title_id", identical_ids)
    write_single_column_csv(report_dir / "source_only_block_titles.csv", "title_id", source_only_ids)
    write_single_column_csv(report_dir / "mod_only_block_titles.csv", "title_id", mod_only_ids)
    write_changed_csv(report_dir / "shared_changed_titles.csv", changed_rows)
    write_summary(
        report_dir / "landed_titles_block_compare_summary.md",
        source_block_count=len(source_ids),
        mod_block_count=len(mod_ids),
        shared_count=len(shared_ids),
        identical_count=len(identical_ids),
        changed_count=len(changed_rows),
        source_only_count=len(source_only_ids),
        mod_only_count=len(mod_only_ids),
    )

    print(f"source_block_count={len(source_ids)}")
    print(f"mod_block_count={len(mod_ids)}")
    print(f"shared_block_count={len(shared_ids)}")
    print(f"shared_identical_block_count={len(identical_ids)}")
    print(f"shared_changed_block_count={len(changed_rows)}")
    print(f"source_only_block_count={len(source_only_ids)}")
    print(f"mod_only_block_count={len(mod_only_ids)}")
    print(f"summary_output={report_dir / 'landed_titles_block_compare_summary.md'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
