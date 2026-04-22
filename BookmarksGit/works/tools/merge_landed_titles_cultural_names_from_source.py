from __future__ import annotations

import argparse
import csv
import re
from dataclasses import dataclass
from pathlib import Path


TITLE_RE = re.compile(r"^\s*([ekdcbh]_[A-Za-z0-9_'\-]+)\s*=\s*\{")
CULTURAL_NAMES_RE = re.compile(r"^\s*cultural_names\s*=\s*\{")
ENTRY_RE = re.compile(r"^\s*([A-Za-z0-9_]+)\s*=\s*([^#\s]+)")
DEFAULT_KEYS = ("name_list_persian_turkish_anatolian", "name_list_turkish")


@dataclass
class CulturalEntry:
    key: str
    value: str
    line_index: int
    text_after_indent: str
    indent: str


@dataclass
class CulturalBlock:
    path: tuple[str, ...]
    title_line: int
    block_start_index: int
    block_end_index: int
    entries_by_key: dict[str, list[CulturalEntry]]
    order: list[CulturalEntry]


@dataclass
class MergeRow:
    title_path: str
    title_id: str
    missing_key: str
    value: str
    source_line: int
    target_line: int
    status: str


def parse_args() -> argparse.Namespace:
    repo_root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(
        description="Merge selected cultural_names entries from a source landed_titles file by exact title path."
    )
    parser.add_argument(
        "--source-landed-titles",
        type=Path,
        default=Path(
            r"F:\Storage\Codding\git\Crusader Kings III\Leviathonlx MoreBookmarks-Plus\BookmarksGit\common\landed_titles\00_landed_titles.txt"
        ),
    )
    parser.add_argument(
        "--target-landed-titles",
        type=Path,
        default=repo_root / "common/landed_titles/00_landed_titles.txt",
    )
    parser.add_argument(
        "--output-csv",
        type=Path,
        default=repo_root / "works/analysis/generated/landed_titles_cultural_names_merge/cultural_names_missing_from_source.csv",
    )
    parser.add_argument("--keys", nargs="+", default=list(DEFAULT_KEYS))
    parser.add_argument("--apply", action="store_true")
    return parser.parse_args()


def strip_comment(line: str) -> str:
    return line.split("#", 1)[0]


def brace_delta(line: str) -> int:
    clean = strip_comment(line)
    return clean.count("{") - clean.count("}")


def leading_indent(line: str) -> str:
    return line[: len(line) - len(line.lstrip(" \t"))]


def detect_newline(lines: list[str]) -> str:
    for line in lines:
        if line.endswith("\r\n"):
            return "\r\n"
        if line.endswith("\n"):
            return "\n"
    return "\n"


def read_lines(path: Path) -> list[str]:
    return path.read_text(encoding="utf-8-sig", errors="replace").splitlines(keepends=True)


def parse_cultural_blocks(lines: list[str]) -> dict[tuple[str, ...], CulturalBlock]:
    blocks: dict[tuple[str, ...], CulturalBlock] = {}
    title_lines: dict[tuple[str, ...], int] = {}
    depth = 0
    stack: list[tuple[str, int]] = []
    i = 0

    while i < len(lines):
        line = lines[i]
        before_depth = depth
        title_match = TITLE_RE.match(line)
        if title_match:
            title_id = title_match.group(1)
            after_depth = before_depth + brace_delta(line)
            path = tuple([item[0] for item in stack] + [title_id])
            title_lines[path] = i + 1
            if after_depth > before_depth:
                stack.append((title_id, after_depth))
            depth = after_depth
            while stack and depth < stack[-1][1]:
                stack.pop()
            i += 1
            continue

        if CULTURAL_NAMES_RE.match(line) and stack:
            path = tuple(item[0] for item in stack)
            entries_by_key: dict[str, list[CulturalEntry]] = {}
            order: list[CulturalEntry] = []
            balance = brace_delta(line)
            j = i + 1
            while j < len(lines) and balance > 0:
                entry_match = ENTRY_RE.match(strip_comment(lines[j]))
                if entry_match:
                    key = entry_match.group(1)
                    value = entry_match.group(2)
                    entry = CulturalEntry(
                        key=key,
                        value=value,
                        line_index=j,
                        text_after_indent=lines[j].lstrip(" \t"),
                        indent=leading_indent(lines[j]),
                    )
                    entries_by_key.setdefault(key, []).append(entry)
                    order.append(entry)
                balance += brace_delta(lines[j])
                j += 1

            blocks[path] = CulturalBlock(
                path=path,
                title_line=title_lines.get(path, i + 1),
                block_start_index=i,
                block_end_index=j - 1,
                entries_by_key=entries_by_key,
                order=order,
            )

            for skipped_index in range(i, j):
                depth += brace_delta(lines[skipped_index])
            while stack and depth < stack[-1][1]:
                stack.pop()
            i = j
            continue

        depth += brace_delta(line)
        while stack and depth < stack[-1][1]:
            stack.pop()
        i += 1

    return blocks


def block_has_entry(block: CulturalBlock, key: str, value: str) -> bool:
    return any(entry.value == value for entry in block.entries_by_key.get(key, []))


def build_missing_rows(
    source_blocks: dict[tuple[str, ...], CulturalBlock],
    target_blocks: dict[tuple[str, ...], CulturalBlock],
    keys: set[str],
) -> list[MergeRow]:
    rows: list[MergeRow] = []
    for path, source_block in source_blocks.items():
        target_block = target_blocks.get(path)
        if not target_block:
            continue
        for source_entry in source_block.order:
            if source_entry.key not in keys:
                continue
            if block_has_entry(target_block, source_entry.key, source_entry.value):
                continue
            rows.append(
                MergeRow(
                    title_path=" > ".join(path),
                    title_id=path[-1],
                    missing_key=source_entry.key,
                    value=source_entry.value,
                    source_line=source_entry.line_index + 1,
                    target_line=target_block.title_line,
                    status="will_add",
                )
            )
    return rows


def get_insert_indent(target_block: CulturalBlock, source_entry: CulturalEntry) -> str:
    if "name_list_persian_turkish" in target_block.entries_by_key:
        return target_block.entries_by_key["name_list_persian_turkish"][0].indent
    if target_block.order:
        return target_block.order[0].indent
    return source_entry.indent


def entry_token(entry: CulturalEntry) -> tuple[str, str]:
    return (entry.key, entry.value)


def insert_missing_entries(
    lines: list[str],
    source_blocks: dict[tuple[str, ...], CulturalBlock],
    target_blocks: dict[tuple[str, ...], CulturalBlock],
    keys: set[str],
) -> int:
    newline = detect_newline(lines)
    additions_by_block: dict[tuple[str, ...], list[CulturalEntry]] = {}
    for path, source_block in source_blocks.items():
        target_block = target_blocks.get(path)
        if not target_block:
            continue
        missing_entries = [
            source_entry
            for source_entry in source_block.order
            if source_entry.key in keys and not block_has_entry(target_block, source_entry.key, source_entry.value)
        ]
        if missing_entries:
            additions_by_block[path] = missing_entries

    additions = 0
    for path in sorted(additions_by_block, key=lambda p: target_blocks[p].block_start_index, reverse=True):
        target_block = target_blocks[path]
        source_block = source_blocks[path]
        block_lines = lines[target_block.block_start_index : target_block.block_end_index + 1]
        entry_relative_indices = {
            entry_token(entry): entry.line_index - target_block.block_start_index for entry in target_block.order
        }

        for source_entry in additions_by_block[path]:
            source_order = source_block.order
            source_position = source_order.index(source_entry)
            insert_at = None

            for previous_entry in reversed(source_order[:source_position]):
                previous_token = entry_token(previous_entry)
                if previous_token in entry_relative_indices:
                    insert_at = entry_relative_indices[previous_token] + 1
                    break

            if insert_at is None:
                for next_entry in source_order[source_position + 1 :]:
                    next_token = entry_token(next_entry)
                    if next_token in entry_relative_indices:
                        insert_at = entry_relative_indices[next_token]
                        break

            if insert_at is None:
                insert_at = len(block_lines) - 1

            indent = get_insert_indent(target_block, source_entry)
            new_line = indent + source_entry.text_after_indent.rstrip("\r\n") + newline
            block_lines.insert(insert_at, new_line)
            additions += 1

            for key, index in list(entry_relative_indices.items()):
                if index >= insert_at:
                    entry_relative_indices[key] = index + 1
            entry_relative_indices[entry_token(source_entry)] = insert_at

        lines[target_block.block_start_index : target_block.block_end_index + 1] = block_lines

    return additions


def write_report(path: Path, rows: list[MergeRow]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=["title_path", "title_id", "missing_key", "value", "source_line", "target_line", "status"],
        )
        writer.writeheader()
        for row in rows:
            writer.writerow(
                {
                    "title_path": row.title_path,
                    "title_id": row.title_id,
                    "missing_key": row.missing_key,
                    "value": row.value,
                    "source_line": row.source_line,
                    "target_line": row.target_line,
                    "status": row.status,
                }
            )


def main() -> None:
    args = parse_args()
    keys = set(args.keys)
    source_lines = read_lines(args.source_landed_titles)
    target_lines = read_lines(args.target_landed_titles)
    source_blocks = parse_cultural_blocks(source_lines)
    target_blocks = parse_cultural_blocks(target_lines)
    rows = build_missing_rows(source_blocks, target_blocks, keys)
    write_report(args.output_csv, rows)

    print(f"report: {args.output_csv}")
    print(f"will_add: {len(rows)}")
    print(f"target: {args.target_landed_titles}")

    if args.apply:
        added = insert_missing_entries(target_lines, source_blocks, target_blocks, keys)
        args.target_landed_titles.write_text("".join(target_lines), encoding="utf-8-sig")
        print(f"applied: {added}")


if __name__ == "__main__":
    main()
