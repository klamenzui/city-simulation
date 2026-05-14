#!/usr/bin/env python
"""Index selected Obsidian Markdown notes into a running LightRAG API server."""

from __future__ import annotations

import argparse
import json
import sys
import urllib.error
import urllib.request
from pathlib import Path


DEFAULT_VAULT = Path(r"C:\dev\projects\ai_brain")
DEFAULT_SERVER_URL = "http://localhost:9621"


def iter_markdown_files(vault: Path, limit: int | None) -> list[Path]:
    files: list[Path] = []
    for path in sorted(vault.rglob("*.md")):
        parts = {part.lower() for part in path.parts}
        if ".obsidian" in parts:
            continue
        if path.stat().st_size > 512_000:
            continue
        files.append(path)
        if limit and len(files) >= limit:
            break
    return files


def read_note(path: Path, max_chars: int) -> str:
    text = path.read_text(encoding="utf-8", errors="replace").strip()
    if len(text) > max_chars:
        text = text[:max_chars].rstrip() + "\n\n[Truncated for safe indexing]"
    return text


def post_json(url: str, payload: dict[str, str], api_key: str | None) -> tuple[int, str]:
    data = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=data,
        headers={"Content-Type": "application/json", "Accept": "application/json"},
        method="POST",
    )
    if api_key:
        request.add_header("X-API-Key", api_key)

    with urllib.request.urlopen(request, timeout=60) as response:
        return response.status, response.read().decode("utf-8", errors="replace")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--vault", type=Path, default=DEFAULT_VAULT)
    parser.add_argument("--server-url", default=DEFAULT_SERVER_URL)
    parser.add_argument("--api-key", default=None)
    parser.add_argument("--limit", type=int, default=20)
    parser.add_argument("--max-chars", type=int, default=24_000)
    parser.add_argument("--endpoint", default="/documents/insert")
    parser.add_argument("--fallback-endpoint", default="/documents/text")
    parser.add_argument("--execute", action="store_true", help="Actually send notes to LightRAG.")
    args = parser.parse_args()

    vault = args.vault.resolve()
    if not vault.exists():
        print(f"Vault does not exist: {vault}", file=sys.stderr)
        return 2

    files = iter_markdown_files(vault, args.limit)
    print(f"Found {len(files)} Markdown files to process from {vault}")

    if not args.execute:
        for path in files:
            print(f"DRY RUN: {path.relative_to(vault)}")
        print("Add --execute to send these notes to LightRAG.")
        return 0

    server_url = args.server_url.rstrip("/")
    endpoint_url = server_url + args.endpoint
    fallback_url = server_url + args.fallback_endpoint

    for path in files:
        rel_path = str(path.relative_to(vault)).replace("\\", "/")
        text = read_note(path, args.max_chars)
        payload = {
            "text": f"Source: obsidian://{rel_path}\n\n{text}",
            "file_source": rel_path,
            "description": rel_path,
        }

        try:
            status, body = post_json(endpoint_url, payload, args.api_key)
        except urllib.error.HTTPError as exc:
            if exc.code == 404 and args.fallback_endpoint:
                status, body = post_json(fallback_url, payload, args.api_key)
            else:
                raise

        print(f"Indexed {rel_path}: HTTP {status}")
        if body:
            print(body[:500])

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
