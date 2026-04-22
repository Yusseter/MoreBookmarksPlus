from __future__ import annotations

import argparse
import csv
import re
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

TITLE_RE = re.compile(r"^\s*([ekdcbh]_[A-Za-z0-9_'\-]+)\s*=\s*\{")
TITLE_PREFIXES = {"e", "k", "d", "c", "b", "h"}
NO_COUNTERPART = "*there_is_no*"


@dataclass(frozen=True)
class TitleInfo:
    title_id: str
    tier: str
    line_no: int
    parent_id: str
    path: str


@dataclass(frozen=True)
class ManualRow:
    line_no: int
    source_title_id: str
    mod_title_id_raw: str
    is_same_raw: str
    raw_line: str


@dataclass(frozen=True)
class ModToken:
    index: int
    raw: str
    title_id: str
    is_second: bool
    is_no_counterpart: bool


@dataclass(frozen=True)
class SameToken:
    index: int
    raw: str


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Validate title_relation_master_manuel.csv without changing it."
    )
    base = Path(r"F:\Storage\Codding\git\Crusader Kings III\Yusseter MoreBookmarksPlus\BookmarksGit")
    leviathon = Path(r"F:\Storage\Codding\git\Crusader Kings III\Leviathonlx MoreBookmarks-Plus\BookmarksGit")
    parser.add_argument("--manual-csv", type=Path, default=base / "title_relation_master_manuel.csv")
    parser.add_argument("--before-manual-csv", type=Path, default=base / "title_relation_master_manuel_before_manuel.csv")
    parser.add_argument("--source-landed-titles", type=Path, default=base / "common/landed_titles/00_landed_titles.txt")
    parser.add_argument("--mod-landed-titles", type=Path, default=leviathon / "common/landed_titles/00_landed_titles.txt")
    parser.add_argument("--master-csv", type=Path, default=base / "works/map_data_sources/title_relation_master.csv")
    parser.add_argument("--output-dir", type=Path, default=base / "works/analysis/generated/title_relation_manual_validation")
    return parser.parse_args()


def strip_comment(line: str) -> str:
    return line.split("#", 1)[0]


def count_braces(line: str) -> tuple[int, int]:
    clean = strip_comment(line)
    return clean.count("{"), clean.count("}")


def parse_landed_titles(path: Path) -> tuple[dict[str, TitleInfo], Counter[str]]:
    titles: dict[str, TitleInfo] = {}
    title_counts: Counter[str] = Counter()
    stack: list[tuple[str, int]] = []
    depth = 0

    for line_no, line in enumerate(path.read_text(encoding="utf-8-sig").splitlines(), start=1):
        clean = strip_comment(line)
        match = TITLE_RE.match(clean)
        opens, closes = count_braces(line)

        if match:
            title_id = match.group(1)
            title_depth = depth + 1
            parent_id = stack[-1][0] if stack else ""
            path_ids = [item[0] for item in stack] + [title_id]
            title_counts[title_id] += 1
            if title_id not in titles:
                titles[title_id] = TitleInfo(
                    title_id=title_id,
                    tier=title_id.split("_", 1)[0],
                    line_no=line_no,
                    parent_id=parent_id,
                    path=" > ".join(path_ids),
                )
            stack.append((title_id, title_depth))

        depth += opens - closes
        while stack and depth < stack[-1][1]:
            stack.pop()
        if depth < 0:
            depth = 0
            stack.clear()

    return titles, title_counts


def parse_csv_line(line: str) -> list[str]:
    return next(csv.reader([line], skipinitialspace=True))


def normalize_manual_fields(row: list[str]) -> list[str]:
    # The working file intentionally keeps a trailing comma. Treat that last
    # empty field as formatting, not as a fourth semantic column.
    normalized = list(row)
    while len(normalized) > 3 and not normalized[-1].strip():
        normalized.pop()
    return normalized


def read_manual_rows(path: Path) -> tuple[list[str], list[ManualRow], list[tuple[int, str, int]]]:
    lines = path.read_text(encoding="utf-8-sig").splitlines()
    if not lines:
        return [], [], []

    header = [cell.strip() for cell in normalize_manual_fields(parse_csv_line(lines[0]))]
    rows: list[ManualRow] = []
    field_count_flags: list[tuple[int, str, int]] = []

    for line_no, line in enumerate(lines[1:], start=2):
        if not line.strip():
            continue
        raw_row = parse_csv_line(line)
        row = normalize_manual_fields(raw_row)
        if len(row) not in {2, 3}:
            field_count_flags.append((line_no, line, len(row)))
        padded = row + [""] * max(0, 3 - len(row))
        rows.append(
            ManualRow(
                line_no=line_no,
                source_title_id=padded[0].strip(),
                mod_title_id_raw=padded[1].strip(),
                is_same_raw=padded[2].strip(),
                raw_line=line,
            )
        )
    return header, rows, field_count_flags


def split_ampersand(value: str) -> list[str]:
    if not value.strip():
        return []
    return [part.strip() for part in value.split("&")]


def parse_mod_tokens(value: str) -> list[ModToken]:
    tokens: list[ModToken] = []
    for index, part in enumerate(split_ampersand(value), start=1):
        raw = part.strip()
        is_second = "(second)" in raw
        title_id = raw.replace("(second)", "").strip()
        is_no_counterpart = title_id == NO_COUNTERPART
        tokens.append(ModToken(index=index, raw=raw, title_id=title_id, is_second=is_second, is_no_counterpart=is_no_counterpart))
    return tokens


def parse_same_tokens(value: str) -> list[SameToken]:
    return [SameToken(index=index, raw=part.strip()) for index, part in enumerate(split_ampersand(value), start=1)]


def tier_of(title_id: str) -> str:
    return title_id.split("_", 1)[0] if "_" in title_id else ""


def load_master_source_ids(path: Path) -> set[str]:
    if not path.exists():
        return set()
    with path.open(encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        return {row.get("source_title_id", "").strip() for row in reader if row.get("source_title_id", "").strip()}


def extract_marked_bad_rows(path: Path) -> list[dict[str, str]]:
    if not path.exists():
        return []
    rows: list[dict[str, str]] = []
    for line_no, line in enumerate(path.read_text(encoding="utf-8-sig").splitlines(), start=1):
        if "HATALI" not in line:
            continue
        clean = strip_comment(line).rstrip()
        parsed = parse_csv_line(clean)
        source_title_id = parsed[0].strip() if len(parsed) > 0 else ""
        bad_mod_title_id = parsed[1].strip() if len(parsed) > 1 else ""
        rows.append(
            {
                "before_line_no": str(line_no),
                "source_title_id": source_title_id,
                "bad_mod_title_id": bad_mod_title_id,
                "before_raw_line": line,
            }
        )
    return rows


def write_csv(path: Path, rows: Iterable[dict[str, object]], fieldnames: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, lineterminator="\n")
        writer.writeheader()
        for row in rows:
            writer.writerow({key: row.get(key, "") for key in fieldnames})


def add_flag(
    flags: list[dict[str, object]],
    severity: str,
    code: str,
    row: ManualRow | None,
    message: str,
    mod_token: ModToken | None = None,
    detail: str = "",
) -> None:
    flags.append(
        {
            "severity": severity,
            "code": code,
            "line_no": row.line_no if row else "",
            "source_title_id": row.source_title_id if row else "",
            "mod_title_id": mod_token.title_id if mod_token else "",
            "mod_token_raw": mod_token.raw if mod_token else "",
            "token_index": mod_token.index if mod_token else "",
            "message": message,
            "detail": detail,
        }
    )


def main() -> int:
    args = parse_args()
    output_dir = args.output_dir
    output_dir.mkdir(parents=True, exist_ok=True)

    source_titles, source_title_counts = parse_landed_titles(args.source_landed_titles)
    mod_titles, mod_title_counts = parse_landed_titles(args.mod_landed_titles)
    header, manual_rows, field_count_flags = read_manual_rows(args.manual_csv)
    master_source_ids = load_master_source_ids(args.master_csv)

    flags: list[dict[str, object]] = []
    source_occurrences: defaultdict[str, list[ManualRow]] = defaultdict(list)
    mod_occurrences: defaultdict[str, list[tuple[ManualRow, ModToken]]] = defaultdict(list)
    token_detail_rows: list[dict[str, object]] = []
    parent_context_rows: list[dict[str, object]] = []
    same_id_context_rows: list[dict[str, object]] = []

    expected_header = ["source_title_id", "mod_title_id", "is_same_title_id"]
    if header != expected_header:
        flags.append(
            {
                "severity": "warning",
                "code": "unexpected_header",
                "line_no": 1,
                "source_title_id": "",
                "mod_title_id": "",
                "mod_token_raw": "",
                "token_index": "",
                "message": "Manual CSV header differs from expected source_title_id, mod_title_id, is_same_title_id.",
                "detail": " | ".join(header),
            }
        )

    for line_no, raw_line, actual_count in field_count_flags:
        flags.append(
            {
                "severity": "error",
                "code": "csv_field_count_not_3",
                "line_no": line_no,
                "source_title_id": "",
                "mod_title_id": "",
                "mod_token_raw": "",
                "token_index": "",
                "message": "CSV row must have exactly 3 fields.",
                "detail": f"field_count={actual_count}; raw={raw_line}",
            }
        )

    manual_by_source: dict[str, ManualRow] = {}
    mapped_tokens_by_source: dict[str, list[ModToken]] = {}
    same_tokens_by_source: dict[str, list[SameToken]] = {}

    for row in manual_rows:
        source_occurrences[row.source_title_id].append(row)
        manual_by_source.setdefault(row.source_title_id, row)
        mapped_tokens_by_source[row.source_title_id] = parse_mod_tokens(row.mod_title_id_raw)
        same_tokens_by_source[row.source_title_id] = parse_same_tokens(row.is_same_raw)

    for source_title_id, occurrences in source_occurrences.items():
        if source_title_id and len(occurrences) > 1:
            for row in occurrences:
                add_flag(flags, "error", "duplicate_source_title_id", row, "source_title_id appears more than once.")

    for row in manual_rows:
        source_info = source_titles.get(row.source_title_id)
        mod_tokens = mapped_tokens_by_source[row.source_title_id]
        same_tokens = same_tokens_by_source[row.source_title_id]

        if not row.source_title_id:
            add_flag(flags, "error", "blank_source_title_id", row, "source_title_id is blank.")
            continue

        if tier_of(row.source_title_id) not in TITLE_PREFIXES:
            add_flag(flags, "error", "invalid_source_title_tier", row, "source_title_id has invalid tier prefix.")

        if row.source_title_id not in source_titles:
            add_flag(flags, "error", "source_title_missing_in_yusseter_landed_titles", row, "source_title_id is not present in source landed_titles.")

        if source_title_counts[row.source_title_id] > 1:
            add_flag(flags, "warning", "source_title_duplicate_in_landed_titles", row, "source_title_id is defined multiple times in source landed_titles.")

        if not mod_tokens:
            severity = "error" if tier_of(row.source_title_id) != "b" else "info"
            add_flag(flags, severity, "blank_mod_title_id", row, "mod_title_id is blank.")

        if mod_tokens and same_tokens and len(same_tokens) != len(mod_tokens):
            add_flag(
                flags,
                "error",
                "is_same_token_count_mismatch",
                row,
                "is_same_title_id token count must match mod_title_id token count when ampersand mapping is used.",
                detail=f"mod_tokens={len(mod_tokens)}; same_tokens={len(same_tokens)}",
            )

        if mod_tokens and not same_tokens:
            add_flag(flags, "error", "blank_is_same_title_id", row, "is_same_title_id is blank for a nonblank mod_title_id.")

        for token in mod_tokens:
            same_raw = same_tokens[token.index - 1].raw if token.index - 1 < len(same_tokens) else ""
            expected_same = "no"
            if token.title_id == row.source_title_id and not token.is_no_counterpart:
                expected_same = "yes"

            if same_raw not in {"yes", "no"}:
                add_flag(flags, "error", "invalid_is_same_value", row, "is_same_title_id token must be yes or no.", token, detail=f"value={same_raw}")
            elif same_raw != expected_same:
                add_flag(
                    flags,
                    "error",
                    "is_same_value_incorrect",
                    row,
                    "is_same_title_id value does not match source/mod title identity.",
                    token,
                    detail=f"expected={expected_same}; actual={same_raw}",
                )

            if token.is_no_counterpart:
                token_detail_rows.append(
                    {
                        "line_no": row.line_no,
                        "source_title_id": row.source_title_id,
                        "mod_title_id": token.title_id,
                        "mod_token_raw": token.raw,
                        "token_index": token.index,
                        "is_second": token.is_second,
                        "is_same_title_id": same_raw,
                        "source_exists": row.source_title_id in source_titles,
                        "mod_exists": "sentinel",
                        "tier_match": "sentinel",
                    }
                )
                continue

            if not token.title_id:
                add_flag(flags, "error", "blank_mod_token", row, "mod_title_id contains a blank ampersand token.", token)
                continue

            if tier_of(token.title_id) not in TITLE_PREFIXES:
                add_flag(flags, "error", "invalid_mod_title_tier", row, "mod_title_id token has invalid tier prefix.", token)

            if token.title_id not in mod_titles:
                add_flag(flags, "error", "mod_title_missing_in_leviathon_landed_titles", row, "mod_title_id token is not present in Leviathon landed_titles.", token)

            if mod_title_counts[token.title_id] > 1:
                add_flag(flags, "warning", "mod_title_duplicate_in_landed_titles", row, "mod_title_id token is defined multiple times in Leviathon landed_titles.", token)

            source_tier = source_info.tier if source_info else tier_of(row.source_title_id)
            mod_tier = mod_titles[token.title_id].tier if token.title_id in mod_titles else tier_of(token.title_id)
            if source_tier and mod_tier and source_tier != mod_tier:
                add_flag(flags, "error", "tier_mismatch", row, "source_title_id and mod_title_id token tiers differ.", token, detail=f"source_tier={source_tier}; mod_tier={mod_tier}")

            mod_occurrences[token.title_id].append((row, token))
            token_detail_rows.append(
                {
                    "line_no": row.line_no,
                    "source_title_id": row.source_title_id,
                    "mod_title_id": token.title_id,
                    "mod_token_raw": token.raw,
                    "token_index": token.index,
                    "is_second": token.is_second,
                    "is_same_title_id": same_raw,
                    "source_exists": row.source_title_id in source_titles,
                    "mod_exists": token.title_id in mod_titles,
                    "tier_match": source_tier == mod_tier if source_tier and mod_tier else "unknown",
                }
            )

    duplicate_mod_rows: list[dict[str, object]] = []
    for mod_title_id, occurrences in sorted(mod_occurrences.items()):
        if len({row.source_title_id for row, _token in occurrences}) <= 1:
            continue
        non_second = [(row, token) for row, token in occurrences if not token.is_second]
        if len(non_second) > 1:
            status = "error:multiple_primary_uses"
            for row, token in non_second:
                add_flag(
                    flags,
                    "error",
                    "duplicate_mod_title_without_second",
                    row,
                    "Same mod_title_id is used by multiple source_title_id rows without (second).",
                    token,
                    detail=f"mod_title_id={mod_title_id}; source_count={len({r.source_title_id for r, _t in occurrences})}",
                )
        elif len(non_second) == 0:
            status = "warning:only_second_uses"
            for row, token in occurrences:
                add_flag(
                    flags,
                    "warning",
                    "duplicate_mod_title_only_second",
                    row,
                    "Same mod_title_id is duplicated but all occurrences are marked (second); expected one primary occurrence.",
                    token,
                    detail=f"mod_title_id={mod_title_id}; source_count={len({r.source_title_id for r, _t in occurrences})}",
                )
        else:
            status = "allowed:secondary_uses_marked"

        for row, token in occurrences:
            duplicate_mod_rows.append(
                {
                    "status": status,
                    "mod_title_id": mod_title_id,
                    "source_title_id": row.source_title_id,
                    "line_no": row.line_no,
                    "is_second": token.is_second,
                    "mod_token_raw": token.raw,
                    "all_sources": " | ".join(sorted({r.source_title_id for r, _t in occurrences})),
                }
            )

    for row in manual_rows:
        source_info = source_titles.get(row.source_title_id)
        if not source_info or not source_info.parent_id:
            continue
        parent_manual = manual_by_source.get(source_info.parent_id)
        parent_mod_tokens = mapped_tokens_by_source.get(source_info.parent_id, [])
        parent_mod_token_ids = {token.title_id for token in parent_mod_tokens if token.title_id and not token.is_no_counterpart}
        parent_mod_token_raw = " & ".join(token.raw for token in parent_mod_tokens)

        for token in mapped_tokens_by_source.get(row.source_title_id, []):
            if token.is_no_counterpart or token.title_id not in mod_titles:
                continue
            mod_parent_id = mod_titles[token.title_id].parent_id
            if not parent_manual or not parent_mod_token_ids:
                status = "uncheckable:no_parent_mapping"
            elif mod_parent_id in parent_mod_token_ids:
                status = "ok"
            else:
                status = "mismatch"
                add_flag(
                    flags,
                    "warning",
                    "parent_mapping_mismatch",
                    row,
                    "Mod title parent is not among mapped mod counterparts of the source title parent.",
                    token,
                    detail=f"source_parent={source_info.parent_id}; source_parent_mod_tokens={parent_mod_token_raw}; mod_parent={mod_parent_id}",
                )

            parent_context_rows.append(
                {
                    "status": status,
                    "line_no": row.line_no,
                    "source_title_id": row.source_title_id,
                    "source_parent_id": source_info.parent_id,
                    "source_parent_mod_tokens": parent_mod_token_raw,
                    "mod_title_id": token.title_id,
                    "mod_parent_id": mod_parent_id,
                    "source_path": source_info.path,
                    "mod_path": mod_titles[token.title_id].path,
                }
            )

            if token.title_id == row.source_title_id:
                same_id_context_rows.append(
                    {
                        "line_no": row.line_no,
                        "title_id": row.source_title_id,
                        "status": "same_parent" if source_info.parent_id == mod_parent_id else "different_parent",
                        "source_parent_id": source_info.parent_id,
                        "mod_parent_id": mod_parent_id,
                        "source_path": source_info.path,
                        "mod_path": mod_titles[token.title_id].path,
                    }
                )

    coverage_rows: list[dict[str, object]] = []
    manual_sources = {row.source_title_id for row in manual_rows if row.source_title_id}
    if master_source_ids:
        for source_title_id in sorted(master_source_ids - manual_sources):
            coverage_rows.append({"status": "missing_from_manual", "source_title_id": source_title_id})
            flags.append(
                {
                    "severity": "error",
                    "code": "source_title_missing_from_manual_vs_master",
                    "line_no": "",
                    "source_title_id": source_title_id,
                    "mod_title_id": "",
                    "mod_token_raw": "",
                    "token_index": "",
                    "message": "source_title_id exists in title_relation_master.csv but not in manual csv.",
                    "detail": "",
                }
            )
        for source_title_id in sorted(manual_sources - master_source_ids):
            coverage_rows.append({"status": "extra_in_manual", "source_title_id": source_title_id})
            flags.append(
                {
                    "severity": "warning",
                    "code": "source_title_extra_in_manual_vs_master",
                    "line_no": manual_by_source[source_title_id].line_no if source_title_id in manual_by_source else "",
                    "source_title_id": source_title_id,
                    "mod_title_id": "",
                    "mod_token_raw": "",
                    "token_index": "",
                    "message": "source_title_id exists in manual csv but not in title_relation_master.csv.",
                    "detail": "",
                }
            )

    marked_bad_rows: list[dict[str, object]] = []
    for bad in extract_marked_bad_rows(args.before_manual_csv):
        source_title_id = bad["source_title_id"]
        bad_mod_title_id = bad["bad_mod_title_id"]
        current = manual_by_source.get(source_title_id)
        current_tokens = mapped_tokens_by_source.get(source_title_id, [])
        current_token_ids = [token.title_id for token in current_tokens]
        still_present = bad_mod_title_id in current_token_ids if bad_mod_title_id else False
        status = "still_present" if still_present else "cleared"
        if current is None:
            status = "source_missing_from_current_manual"
        if still_present and current is not None:
            add_flag(
                flags,
                "warning",
                "marked_bad_token_still_present",
                current,
                "A token manually marked HATALI in before-manual file still appears in current manual csv.",
                detail=f"bad_mod_title_id={bad_mod_title_id}; before_line_no={bad['before_line_no']}",
            )
        marked_bad_rows.append(
            {
                **bad,
                "current_line_no": current.line_no if current else "",
                "current_mod_title_id": current.mod_title_id_raw if current else "",
                "current_is_same_title_id": current.is_same_raw if current else "",
                "status": status,
            }
        )

    flags.sort(key=lambda row: (str(row["severity"]), str(row["code"]), int(row["line_no"] or 0)))

    write_csv(
        output_dir / "title_relation_manual_validation_flags.csv",
        flags,
        ["severity", "code", "line_no", "source_title_id", "mod_title_id", "mod_token_raw", "token_index", "message", "detail"],
    )
    write_csv(
        output_dir / "title_relation_manual_token_detail.csv",
        token_detail_rows,
        ["line_no", "source_title_id", "mod_title_id", "mod_token_raw", "token_index", "is_second", "is_same_title_id", "source_exists", "mod_exists", "tier_match"],
    )
    write_csv(
        output_dir / "title_relation_manual_duplicate_mod_usage.csv",
        duplicate_mod_rows,
        ["status", "mod_title_id", "source_title_id", "line_no", "is_second", "mod_token_raw", "all_sources"],
    )
    write_csv(
        output_dir / "title_relation_manual_parent_context_report.csv",
        parent_context_rows,
        ["status", "line_no", "source_title_id", "source_parent_id", "source_parent_mod_tokens", "mod_title_id", "mod_parent_id", "source_path", "mod_path"],
    )
    write_csv(
        output_dir / "title_relation_manual_same_id_context_report.csv",
        same_id_context_rows,
        ["line_no", "title_id", "status", "source_parent_id", "mod_parent_id", "source_path", "mod_path"],
    )
    write_csv(
        output_dir / "title_relation_manual_source_coverage.csv",
        coverage_rows,
        ["status", "source_title_id"],
    )
    write_csv(
        output_dir / "title_relation_manual_marked_bad_regression.csv",
        marked_bad_rows,
        ["before_line_no", "source_title_id", "bad_mod_title_id", "current_line_no", "current_mod_title_id", "current_is_same_title_id", "status", "before_raw_line"],
    )

    high_signal_codes = {
        "blank_is_same_title_id",
        "invalid_is_same_value",
        "is_same_token_count_mismatch",
        "is_same_value_incorrect",
        "mod_title_missing_in_leviathon_landed_titles",
        "source_title_missing_in_yusseter_landed_titles",
        "tier_mismatch",
    }
    high_signal_rows = [row for row in flags if row["code"] in high_signal_codes]
    write_csv(
        output_dir / "title_relation_manual_high_signal_errors.csv",
        high_signal_rows,
        ["severity", "code", "line_no", "source_title_id", "mod_title_id", "mod_token_raw", "token_index", "message", "detail"],
    )

    flag_counter = Counter((row["severity"], row["code"]) for row in flags)
    severity_counter = Counter(row["severity"] for row in flags)
    parent_status_counter = Counter(row["status"] for row in parent_context_rows)
    duplicate_status_counter = Counter(row["status"] for row in duplicate_mod_rows)
    marked_bad_status_counter = Counter(row["status"] for row in marked_bad_rows)

    lines = [
        "# Title Relation Manual Validation Summary",
        "",
        f"- manual rows: {len(manual_rows)}",
        f"- source landed title ids: {len(source_titles)}",
        f"- mod landed title ids: {len(mod_titles)}",
        f"- master source ids: {len(master_source_ids)}",
        "",
        "## Flag Totals",
        "",
        f"- errors: {severity_counter.get('error', 0)}",
        f"- warnings: {severity_counter.get('warning', 0)}",
        "",
        "## Flags By Code",
        "",
    ]
    if flag_counter:
        for (severity, code), count in sorted(flag_counter.items(), key=lambda item: (item[0][0], item[0][1])):
            lines.append(f"- {severity}:{code}: {count}")
    else:
        lines.append("- none")

    lines.extend(["", "## Parent Context", ""])
    if parent_status_counter:
        for status, count in sorted(parent_status_counter.items()):
            lines.append(f"- {status}: {count}")
    else:
        lines.append("- none")

    lines.extend(["", "## Duplicate Mod Usage", ""])
    if duplicate_status_counter:
        for status, count in sorted(duplicate_status_counter.items()):
            lines.append(f"- {status}: {count}")
    else:
        lines.append("- none")

    lines.extend(["", "## Marked Bad Regression", ""])
    if marked_bad_status_counter:
        for status, count in sorted(marked_bad_status_counter.items()):
            lines.append(f"- {status}: {count}")
    else:
        lines.append("- none")

    lines.extend(
        [
            "",
            "## Outputs",
            "",
            f"- flags: {output_dir / 'title_relation_manual_validation_flags.csv'}",
            f"- token detail: {output_dir / 'title_relation_manual_token_detail.csv'}",
            f"- duplicate mod usage: {output_dir / 'title_relation_manual_duplicate_mod_usage.csv'}",
            f"- parent context: {output_dir / 'title_relation_manual_parent_context_report.csv'}",
            f"- same-id context: {output_dir / 'title_relation_manual_same_id_context_report.csv'}",
            f"- source coverage: {output_dir / 'title_relation_manual_source_coverage.csv'}",
            f"- marked bad regression: {output_dir / 'title_relation_manual_marked_bad_regression.csv'}",
            f"- high-signal errors: {output_dir / 'title_relation_manual_high_signal_errors.csv'}",
        ]
    )

    summary_path = output_dir / "title_relation_manual_validation_summary.md"
    summary_path.write_text("\n".join(lines) + "\n", encoding="utf-8")

    print(f"manual_rows={len(manual_rows)}")
    print(f"errors={severity_counter.get('error', 0)}")
    print(f"warnings={severity_counter.get('warning', 0)}")
    print(f"summary={summary_path}")
    return 0 if severity_counter.get("error", 0) == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
