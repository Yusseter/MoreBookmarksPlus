from __future__ import annotations

import argparse
import codecs
import csv
import hashlib
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


TITLE_RE = re.compile(r"^\s*([ekdcbh]_[A-Za-z0-9_'\-]+)\s*=\s*\{")
PROVINCE_RE = re.compile(r"\bprovince\s*=\s*(\d+)\b")


@dataclass(frozen=True)
class TextFile:
    path: Path
    text: str
    has_bom: bool
    newline: str


@dataclass(frozen=True)
class TitleBlock:
    title_id: str
    start_index: int
    end_index: int
    start_line: int
    end_line: int
    text: str
    normalized_text: str
    normalized_hash: str
    province_ids: tuple[int, ...]


def parse_args() -> argparse.Namespace:
    repo_root = Path(__file__).resolve().parents[2]
    output_dir = repo_root / "works/analysis/generated/landed_titles_source_audit"
    parser = argparse.ArgumentParser(
        description="Preview or apply county block replacements from county_source_fix_plan.csv."
    )
    parser.add_argument("--fix-plan", type=Path, default=output_dir / "county_source_fix_plan.csv")
    parser.add_argument("--current-landed-titles", type=Path, default=repo_root / "common/landed_titles/00_landed_titles.txt")
    parser.add_argument(
        "--test-landed-titles",
        type=Path,
        default=repo_root / "test_files/common/landed_titles/00_landed_titles.txt",
    )
    parser.add_argument("--output-dir", type=Path, default=output_dir)
    parser.add_argument("--action", default="replace_with_mod_block")
    parser.add_argument("--apply", action="store_true", help="Write replacements. Without this flag only preview files are written.")
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


def dominant_newline(text: str) -> str:
    crlf = text.count("\r\n")
    lf = text.count("\n") - crlf
    return "\r\n" if crlf >= lf and crlf > 0 else "\n"


def read_text_file(path: Path) -> TextFile:
    data = path.read_bytes()
    has_bom = data.startswith(codecs.BOM_UTF8)
    text = data.decode("utf-8-sig")
    return TextFile(path=path, text=text, has_bom=has_bom, newline=dominant_newline(text))


def write_text_file(file: TextFile, text: str) -> None:
    data = text.encode("utf-8")
    if file.has_bom:
        data = codecs.BOM_UTF8 + data
    file.path.write_bytes(data)


def split_lines_keepends(text: str) -> list[str]:
    lines = text.splitlines(keepends=True)
    if text and (not lines or not lines[-1].endswith(("\n", "\r"))):
        return lines
    return lines


def parse_title_blocks(text: str, tier: str = "c") -> dict[str, list[TitleBlock]]:
    lines = split_lines_keepends(text)
    result: dict[str, list[TitleBlock]] = {}
    stack: list[dict[str, object]] = []
    depth = 0

    for index, line in enumerate(lines):
        clean = strip_comment(line)
        match = TITLE_RE.match(clean)
        if match:
            title_id = match.group(1)
            stack.append(
                {
                    "title_id": title_id,
                    "start_index": index,
                    "start_line": index + 1,
                    "depth": depth + 1,
                }
            )

        depth += clean.count("{") - clean.count("}")
        while stack and depth < int(stack[-1]["depth"]):
            item = stack.pop()
            title_id = str(item["title_id"])
            if title_id.startswith(f"{tier}_"):
                block_lines = lines[int(item["start_index"]) : index + 1]
                block_text = "".join(block_lines)
                normalized = normalize_block(block_text)
                block = TitleBlock(
                    title_id=title_id,
                    start_index=int(item["start_index"]),
                    end_index=index,
                    start_line=int(item["start_line"]),
                    end_line=index + 1,
                    text=block_text,
                    normalized_text=normalized,
                    normalized_hash=hashlib.sha256(normalized.encode("utf-8")).hexdigest(),
                    province_ids=tuple(int(value) for value in PROVINCE_RE.findall(block_text)),
                )
                result.setdefault(title_id, []).append(block)
        if depth < 0:
            depth = 0
            stack.clear()

    return result


def read_fix_plan(path: Path, action: str) -> list[dict[str, str]]:
    with path.open(encoding="utf-8", newline="") as handle:
        return [row for row in csv.DictReader(handle) if row.get("action") == action]


def split_source_location(value: str) -> tuple[Path, int]:
    path_text, line_text = value.rsplit(":", 1)
    return Path(path_text), int(line_text)


def first_indent(text: str) -> str:
    for line in text.splitlines():
        if line.strip():
            return re.match(r"^[ \t]*", line).group(0)
    return ""


def normalize_newlines(text: str, newline: str) -> str:
    normalized = text.replace("\r\n", "\n").replace("\r", "\n")
    return normalized.replace("\n", newline)


def reindent_block(source_text: str, current_text: str) -> str:
    source_indent = first_indent(source_text)
    current_indent = first_indent(current_text)
    result = []
    for line in source_text.splitlines(keepends=True):
        newline = ""
        body = line
        if body.endswith("\r\n"):
            body = body[:-2]
            newline = "\r\n"
        elif body.endswith("\n"):
            body = body[:-1]
            newline = "\n"
        elif body.endswith("\r"):
            body = body[:-1]
            newline = "\r"

        if body.strip() and body.startswith(source_indent):
            body = current_indent + body[len(source_indent) :]
        elif body.strip():
            body = current_indent + body.lstrip(" \t")
        result.append(body + newline)
    return "".join(result)


def pick_source_block(source_blocks: dict[str, list[TitleBlock]], county_id: str, source_line: int) -> TitleBlock | None:
    candidates = source_blocks.get(county_id, [])
    if not candidates:
        return None
    for candidate in candidates:
        if candidate.start_line == source_line:
            return candidate
    if len(candidates) == 1:
        return candidates[0]
    return min(candidates, key=lambda block: abs(block.start_line - source_line))


def single_target_block(target_blocks: dict[str, list[TitleBlock]], county_id: str) -> TitleBlock | None:
    candidates = target_blocks.get(county_id, [])
    if len(candidates) != 1:
        return None
    return candidates[0]


def write_csv(path: Path, rows: Iterable[dict[str, object]], fieldnames: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, lineterminator="\n")
        writer.writeheader()
        for row in rows:
            writer.writerow({field: row.get(field, "") for field in fieldnames})


def make_replacement(source_block: TitleBlock, target_block: TitleBlock, target_file: TextFile) -> str:
    replacement = reindent_block(source_block.text, target_block.text)
    return normalize_newlines(replacement, target_file.newline)


def apply_replacements(target_file: TextFile, target_blocks: dict[str, list[TitleBlock]], replacements: dict[str, str]) -> None:
    lines = split_lines_keepends(target_file.text)
    changes: list[tuple[int, int, str]] = []
    for county_id, replacement in replacements.items():
        block = single_target_block(target_blocks, county_id)
        if block is None:
            raise RuntimeError(f"Target block not found exactly once in {target_file.path}: {county_id}")
        changes.append((block.start_index, block.end_index, replacement))

    for start_index, end_index, replacement in sorted(changes, reverse=True):
        lines[start_index : end_index + 1] = replacement.splitlines(keepends=True)

    write_text_file(target_file, "".join(lines))


def main() -> int:
    args = parse_args()
    plan_rows = read_fix_plan(args.fix_plan, args.action)
    if not plan_rows:
        raise RuntimeError(f"No fix plan rows found for action={args.action}")

    current_file = read_text_file(args.current_landed_titles)
    test_file = read_text_file(args.test_landed_titles)
    current_blocks = parse_title_blocks(current_file.text)
    test_blocks = parse_title_blocks(test_file.text)

    source_files: dict[Path, TextFile] = {}
    source_blocks_by_file: dict[Path, dict[str, list[TitleBlock]]] = {}
    preview_rows: list[dict[str, object]] = []
    current_replacements: dict[str, str] = {}
    test_replacements: dict[str, str] = {}

    for row in plan_rows:
        county_id = row["county_id"]
        source_path, source_line = split_source_location(row["source_block_path"])
        if source_path not in source_files:
            source_files[source_path] = read_text_file(source_path)
            source_blocks_by_file[source_path] = parse_title_blocks(source_files[source_path].text)

        source_block = pick_source_block(source_blocks_by_file[source_path], county_id, source_line)
        current_block = single_target_block(current_blocks, county_id)
        test_block = single_target_block(test_blocks, county_id)
        status = "ok"
        if source_block is None:
            status = "error:source_block_not_found"
        elif current_block is None:
            status = "error:current_block_not_found_once"
        elif test_block is None:
            status = "error:test_block_not_found_once"

        source_hash = source_block.normalized_hash if source_block else ""
        current_hash = current_block.normalized_hash if current_block else ""
        test_hash = test_block.normalized_hash if test_block else ""
        if status == "ok":
            current_replacements[county_id] = make_replacement(source_block, current_block, current_file)
            test_replacements[county_id] = make_replacement(source_block, test_block, test_file)

        preview_rows.append(
            {
                "county_id": county_id,
                "status": status,
                "source_block_path": f"{source_path}:{source_block.start_line if source_block else source_line}",
                "current_start_line": current_block.start_line if current_block else "",
                "current_end_line": current_block.end_line if current_block else "",
                "test_start_line": test_block.start_line if test_block else "",
                "test_end_line": test_block.end_line if test_block else "",
                "current_province_ids": " ".join(str(value) for value in current_block.province_ids) if current_block else "",
                "source_province_ids": " ".join(str(value) for value in source_block.province_ids) if source_block else "",
                "current_equals_source": "yes" if current_hash and current_hash == source_hash else "no",
                "test_equals_source": "yes" if test_hash and test_hash == source_hash else "no",
                "current_equals_test_before": "yes" if current_hash and current_hash == test_hash else "no",
                "current_hash": current_hash,
                "source_hash": source_hash,
            }
        )

    preview_path = args.output_dir / f"county_source_{args.action}_preview.csv"
    report_path = args.output_dir / f"county_source_{args.action}_apply_report.csv"
    fieldnames = [
        "county_id",
        "status",
        "source_block_path",
        "current_start_line",
        "current_end_line",
        "test_start_line",
        "test_end_line",
        "current_province_ids",
        "source_province_ids",
        "current_equals_source",
        "test_equals_source",
        "current_equals_test_before",
        "current_hash",
        "source_hash",
    ]
    write_csv(preview_path, preview_rows, fieldnames)

    errors = [row for row in preview_rows if row["status"] != "ok"]
    if errors:
        write_csv(report_path, preview_rows, fieldnames)
        raise RuntimeError(f"Preview has {len(errors)} errors; not applying")

    if args.apply:
        apply_replacements(current_file, current_blocks, current_replacements)
        apply_replacements(test_file, test_blocks, test_replacements)
        write_csv(report_path, preview_rows, fieldnames)
        print(f"applied rows: {len(preview_rows)}")
    else:
        print(f"preview rows: {len(preview_rows)}")
    print(f"preview: {preview_path}")
    if args.apply:
        print(f"apply report: {report_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
