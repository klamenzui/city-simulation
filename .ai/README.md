# City Simulation AI Memory Stack

This folder contains local-only support files for project memory.

## Components

- `docker-compose.ai.yml` starts Qdrant on localhost ports `6333` and `6334`.
- `qdrant_storage/` persists the local Qdrant database and is ignored by Git.
- `lightrag/` contains the LightRAG environment template and local runtime notes.
- `scripts/` contains safe helper scripts for starting, checking, and syncing memory.

## Useful Commands

PowerShell script execution is restricted on this machine, so call scripts through an explicit bypass:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\.ai\scripts\check-ai-stack.ps1
powershell.exe -ExecutionPolicy Bypass -File .\.ai\scripts\start-ai-stack.ps1
powershell.exe -ExecutionPolicy Bypass -File .\.ai\scripts\stop-ai-stack.ps1
```

Dry-run the vault sync scripts before writing anything:

```powershell
python .\.ai\scripts\index-obsidian-to-lightrag.py --limit 5
python .\.ai\scripts\sync-important-notes-to-qdrant.py --limit 5
```

Use Python for project analysis. PowerShell should only start these scripts:

```powershell
python .\.ai\scripts\citysim_project_scan.py --root .
python .\.ai\scripts\citysim_cleanup_check.py --root .
python .\.ai\scripts\citysim_find_references.py --root . --symbol Citizen
```

The Qdrant sync script needs Python packages when run with `--execute`:

```powershell
python -m pip install --user fastembed qdrant-client
```

## Safety Rules

- Do not index `.obsidian` internals.
- Do not bulk-store whole source trees or large notes.
- Store summaries, decisions, patterns, known bugs, and short code snippets.
- Keep local secrets in `.ai/lightrag/.env`; never commit that file.
