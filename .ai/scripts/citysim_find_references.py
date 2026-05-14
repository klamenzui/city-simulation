#!/usr/bin/env python
"""Find symbol or file references inside the City Simulation Godot project."""

from __future__ import annotations

import argparse
import re
from pathlib import Path

from citysim_common import TEXT_EXTENSIONS, iter_project_files, resolve_project_root, safe_read_text


def build_needles(root: Path, symbol: str) -> list[str]:
    needles = [symbol]
    possible_path = Path(symbol)

    if possible_path.exists():
        try:
            rel = possible_path.resolve().relative_to(root).as_posix()
            needles.append("res://" + rel)
            needles.append(rel)
            needles.append(possible_path.name)
            needles.append(possible_path.stem)
        except ValueError:
            pass
    elif "/" in symbol or "\\" in symbol:
        normalized = symbol.replace("\\", "/").lstrip("./")
        needles.append("res://" + normalized)
        needles.append(Path(normalized).name)
        needles.append(Path(normalized).stem)

    unique = []
    for needle in needles:
        if needle and needle not in unique:
            unique.append(needle)
    return unique


def find_matches(
    root: Path,
    needles: list[str],
    ignore_case: bool,
    max_results: int,
    context: int,
) -> list[tuple[str, int, str]]:
    flags = re.IGNORECASE if ignore_case else 0
    patterns = [re.compile(re.escape(needle), flags) for needle in needles]
    matches: list[tuple[str, int, str]] = []

    for project_file in iter_project_files(root, extensions=TEXT_EXTENSIONS, max_bytes=2_000_000):
        text = safe_read_text(project_file.path)
        if not text:
            continue
        lines = text.splitlines()
        for index, line in enumerate(lines, start=1):
            if any(pattern.search(line) for pattern in patterns):
                start = max(1, index - context)
                end = min(len(lines), index + context)
                if context:
                    snippet = " / ".join(lines[start - 1 : end]).strip()
                else:
                    snippet = line.strip()
                matches.append((project_file.rel, index, snippet[:500]))
                if len(matches) >= max_results:
                    return matches
    return matches


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=".", help="Project root or any path inside it.")
    parser.add_argument("--symbol", required=True, help="Symbol, filename, relative path, or absolute path to search.")
    parser.add_argument("--ignore-case", action="store_true")
    parser.add_argument("--max-results", type=int, default=120)
    parser.add_argument("--context", type=int, default=0)
    args = parser.parse_args()

    root = resolve_project_root(args.root)
    needles = build_needles(root, args.symbol)
    matches = find_matches(root, needles, args.ignore_case, args.max_results, args.context)

    print(f"Project root: {root}")
    print(f"Needles: {', '.join(needles)}")
    print(f"Matches: {len(matches)}")
    for rel, line, snippet in matches:
        print(f"{rel}:{line}: {snippet}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
