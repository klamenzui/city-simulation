#!/usr/bin/env python
"""Embed selected Obsidian project notes and upsert them into local Qdrant."""

from __future__ import annotations

import argparse
import re
import sys
import uuid
from pathlib import Path
from typing import Iterable


DEFAULT_VAULT = Path(r"C:\dev\projects\ai_brain")
DEFAULT_QDRANT_URL = "http://localhost:6333"
DEFAULT_COLLECTION = "city-sim-memory"
DEFAULT_MODEL = "sentence-transformers/all-MiniLM-L6-v2"
DEFAULT_VECTOR_NAME = "fast-all-minilm-l6-v2"
IMPORTANT_PREFIXES = ("10_Notes", "30_Projects", "_Maps")


def iter_notes(vault: Path, include_all: bool, limit: int | None) -> list[Path]:
    notes: list[Path] = []
    for path in sorted(vault.rglob("*.md")):
        rel = path.relative_to(vault)
        parts = {part.lower() for part in rel.parts}
        if ".obsidian" in parts:
            continue
        if path.stat().st_size > 512_000:
            continue
        if not include_all and not str(rel).startswith(IMPORTANT_PREFIXES):
            continue
        notes.append(path)
        if limit and len(notes) >= limit:
            break
    return notes


def first_heading(text: str, fallback: str) -> str:
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("#"):
            return stripped.lstrip("#").strip() or fallback
    return fallback


def build_memory_text(path: Path, vault: Path, max_chars: int) -> tuple[str, dict[str, object]]:
    rel = str(path.relative_to(vault)).replace("\\", "/")
    text = path.read_text(encoding="utf-8", errors="replace").strip()
    title = first_heading(text, path.stem)
    links = sorted(set(re.findall(r"\[\[([^\]]+)\]\]", text)))[:20]
    body = text[:max_chars].rstrip()
    if len(text) > max_chars:
        body += "\n\n[Truncated for safe semantic memory]"

    memory = (
        f"Title: {title}\n"
        f"Source: obsidian://{rel}\n"
        f"Links: {', '.join(links) if links else 'none'}\n\n"
        f"{body}"
    )
    payload = {
        "source": f"obsidian://{rel}",
        "path": rel,
        "title": title,
        "links": links,
        "kind": "project-memory",
    }
    payload["document"] = memory
    return memory, payload


def batched(items: list[Path], size: int) -> Iterable[list[Path]]:
    for index in range(0, len(items), size):
        yield items[index : index + size]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--vault", type=Path, default=DEFAULT_VAULT)
    parser.add_argument("--qdrant-url", default=DEFAULT_QDRANT_URL)
    parser.add_argument("--collection", default=DEFAULT_COLLECTION)
    parser.add_argument("--embedding-model", default=DEFAULT_MODEL)
    parser.add_argument("--vector-name", default=DEFAULT_VECTOR_NAME)
    parser.add_argument("--limit", type=int, default=50)
    parser.add_argument("--batch-size", type=int, default=16)
    parser.add_argument("--max-chars", type=int, default=12_000)
    parser.add_argument("--all-notes", action="store_true")
    parser.add_argument("--recreate", action="store_true", help="Delete and recreate the target collection first.")
    parser.add_argument("--execute", action="store_true", help="Actually write points to Qdrant.")
    args = parser.parse_args()

    vault = args.vault.resolve()
    if not vault.exists():
        print(f"Vault does not exist: {vault}", file=sys.stderr)
        return 2

    notes = iter_notes(vault, args.all_notes, args.limit)
    print(f"Selected {len(notes)} Markdown notes from {vault}")

    if not args.execute:
        for path in notes:
            print(f"DRY RUN: {path.relative_to(vault)}")
        print("Add --execute to embed and upsert these notes into Qdrant.")
        return 0

    try:
        from fastembed import TextEmbedding
        from qdrant_client import QdrantClient
        from qdrant_client.http.models import Distance, PointStruct, VectorParams
    except ImportError as exc:
        print(
            "Missing Python dependencies. Install them in your Python environment:\n"
            "  uv pip install fastembed qdrant-client\n"
            f"Import error: {exc}",
            file=sys.stderr,
        )
        return 3

    embedding_model = TextEmbedding(model_name=args.embedding_model)
    client = QdrantClient(url=args.qdrant_url)

    initialized = False
    collection_ready = False
    total = 0
    for batch in batched(notes, args.batch_size):
        memories: list[str] = []
        payloads: list[dict[str, object]] = []
        ids: list[str] = []
        for path in batch:
            memory, payload = build_memory_text(path, vault, args.max_chars)
            memories.append(memory)
            payloads.append(payload)
            ids.append(str(uuid.uuid5(uuid.NAMESPACE_URL, payload["source"])))

        vectors = list(embedding_model.embed(memories))
        if not vectors:
            continue

        if not initialized:
            if args.recreate:
                client.recreate_collection(
                    collection_name=args.collection,
                    vectors_config={
                        args.vector_name: VectorParams(size=len(vectors[0]), distance=Distance.COSINE)
                    },
                )
                collection_ready = True
            if not collection_ready:
                try:
                    client.get_collection(collection_name=args.collection)
                    collection_ready = True
                except Exception:
                    client.create_collection(
                        collection_name=args.collection,
                        vectors_config={
                            args.vector_name: VectorParams(size=len(vectors[0]), distance=Distance.COSINE)
                        },
                    )
                    collection_ready = True
            initialized = True

        points = [
            PointStruct(id=point_id, vector={args.vector_name: vector.tolist()}, payload=payload)
            for point_id, vector, payload in zip(ids, vectors, payloads)
        ]
        client.upsert(collection_name=args.collection, points=points)
        total += len(points)
        print(f"Upserted {total} notes into {args.collection}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
