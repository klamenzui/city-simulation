#!/usr/bin/env python
"""Shared helpers for safe City Simulation project tooling."""

from __future__ import annotations

import os
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


SOURCE_EXTENSIONS = {
    ".cfg",
    ".gd",
    ".godot",
    ".json",
    ".md",
    ".ps1",
    ".tres",
    ".tscn",
}

TEXT_EXTENSIONS = SOURCE_EXTENSIONS | {".txt", ".toml", ".yml", ".yaml"}

IGNORED_DIR_NAMES = {
    ".cache",
    ".claude",
    ".codex",
    ".git",
    ".godot",
    ".idea",
    ".obsidian",
    ".pytest_cache",
    "__pycache__",
    "addons",
    "node_modules",
}

IGNORED_TOP_LEVEL_DIRS = {
    "AI",
    "AI_RuntimeTest",
}

IGNORED_REL_PREFIXES = {
    (".ai", ".cache"),
    (".ai", "lightrag", "inputs"),
    (".ai", "lightrag", "rag_storage"),
    (".ai", "qdrant_import"),
    (".ai", "qdrant_storage"),
    ("ImportedCitySource", "assets"),
}


@dataclass(frozen=True)
class ProjectFile:
    path: Path
    rel: str
    size: int
    extension: str


def die(message: str, exit_code: int = 2) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(exit_code)


def normalize_rel(path: Path, root: Path) -> str:
    return path.relative_to(root).as_posix()


def resolve_project_root(start: str | Path) -> Path:
    candidate = Path(start).expanduser()
    try:
        candidate = candidate.resolve()
    except OSError as exc:
        die(f"Cannot resolve root candidate {candidate}: {exc}")

    if candidate.is_file():
        candidate = candidate.parent

    for current in (candidate, *candidate.parents):
        if (current / "project.godot").is_file():
            validate_project_root(current)
            return current

    die(
        "No Godot project root found. Start inside the project or pass "
        "--root C:\\dev\\projects\\Godot\\city-simulation."
    )


def validate_project_root(root: Path) -> None:
    root = root.resolve()
    if root.parent == root:
        die(f"Refusing to use filesystem root as project root: {root}")
    if not (root / "project.godot").is_file():
        die(f"Missing project.godot in {root}")

    project_text = safe_read_text(root / "project.godot", max_bytes=128_000)
    if "config_version" not in project_text:
        die(f"project.godot does not look like a Godot project file: {root}")


def is_relative_to(path: Path, parent: Path) -> bool:
    try:
        path.relative_to(parent)
        return True
    except ValueError:
        return False


def has_prefix(parts: tuple[str, ...], prefix: tuple[str, ...]) -> bool:
    return len(parts) >= len(prefix) and parts[: len(prefix)] == prefix


def should_ignore(path: Path, root: Path, include_ai: bool = False) -> bool:
    rel_parts = path.relative_to(root).parts
    if not rel_parts:
        return False

    if rel_parts[0] in IGNORED_TOP_LEVEL_DIRS:
        return True

    for part in rel_parts:
        if part in IGNORED_DIR_NAMES:
            return True

    if rel_parts[0] == ".ai" and not include_ai:
        return True

    for prefix in IGNORED_REL_PREFIXES:
        if has_prefix(tuple(rel_parts), prefix):
            return True

    name = path.name
    if name.endswith(".import") or name.endswith(".uid"):
        return True

    return False


def iter_project_files(
    root: Path,
    extensions: set[str] | None = None,
    include_ai: bool = False,
    max_bytes: int | None = None,
) -> list[ProjectFile]:
    root = root.resolve()
    extensions = extensions or SOURCE_EXTENSIONS
    results: list[ProjectFile] = []

    for current_root, dir_names, file_names in os.walk(root):
        current = Path(current_root)
        if should_ignore(current, root, include_ai=include_ai):
            dir_names[:] = []
            continue

        kept_dirs = []
        for dir_name in dir_names:
            dir_path = current / dir_name
            if not should_ignore(dir_path, root, include_ai=include_ai):
                kept_dirs.append(dir_name)
        dir_names[:] = kept_dirs

        for file_name in file_names:
            path = current / file_name
            if should_ignore(path, root, include_ai=include_ai):
                continue
            extension = path.suffix.lower()
            if extension not in extensions:
                continue
            try:
                size = path.stat().st_size
            except OSError:
                continue
            if max_bytes is not None and size > max_bytes:
                continue
            results.append(
                ProjectFile(path=path, rel=normalize_rel(path, root), size=size, extension=extension)
            )

    return sorted(results, key=lambda item: item.rel.lower())


def safe_read_text(path: Path, max_bytes: int = 2_000_000) -> str:
    try:
        if path.stat().st_size > max_bytes:
            return ""
        return path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""


def count_lines(path: Path) -> int:
    text = safe_read_text(path)
    if not text:
        return 0
    return text.count("\n") + 1


def extract_gdscript_symbols(path: Path) -> dict[str, list[str]]:
    text = safe_read_text(path)
    class_names = re.findall(r"(?m)^\s*class_name\s+([A-Za-z_][A-Za-z0-9_]*)", text)
    extends = re.findall(r"(?m)^\s*extends\s+([A-Za-z_][A-Za-z0-9_\.]*)", text)
    funcs = re.findall(r"(?m)^\s*(?:static\s+)?func\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(", text)
    vars_ = re.findall(r"(?m)^\s*(?:@export\s+)?var\s+([A-Za-z_][A-Za-z0-9_]*)", text)
    return {
        "class_names": class_names,
        "extends": extends,
        "funcs": funcs,
        "vars": vars_,
    }


def load_text_corpus(root: Path, max_file_bytes: int = 2_000_000) -> dict[str, str]:
    corpus: dict[str, str] = {}
    for project_file in iter_project_files(root, extensions=TEXT_EXTENSIONS, max_bytes=max_file_bytes):
        text = safe_read_text(project_file.path, max_bytes=max_file_bytes)
        if text:
            corpus[project_file.rel] = text
    return corpus


def count_literal_references(corpus: dict[str, str], needle: str, exclude_rel: str | None = None) -> int:
    if not needle:
        return 0
    total = 0
    for rel, text in corpus.items():
        if exclude_rel and rel == exclude_rel:
            continue
        total += text.count(needle)
    return total


def markdown_table(headers: Iterable[str], rows: Iterable[Iterable[object]]) -> str:
    header_list = list(headers)
    lines = [
        "| " + " | ".join(header_list) + " |",
        "| " + " | ".join("---" for _ in header_list) + " |",
    ]
    for row in rows:
        lines.append("| " + " | ".join(str(value).replace("\n", " ") for value in row) + " |")
    return "\n".join(lines)


def write_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content.rstrip() + "\n", encoding="utf-8")
