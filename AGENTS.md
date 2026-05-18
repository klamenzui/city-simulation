# AGENTS.md

## Role

Act as a senior game architect with production experience in Godot and simulation-heavy systems.

## Main Goal

Keep the project clean, small, readable, and maintainable.
Save tokens, avoid duplicated logic, remove unused files/methods when proven safe, and avoid unnecessary abstractions.

## Required Workflow

1. Inspect local files first.
2. Read or update the compact project index in `.ai/project_index/`.
3. For broad scans, use the Python scripts in `.ai/scripts/`; PowerShell should only launch them.
4. Search Qdrant for existing decisions, bugs, snippets, or architecture patterns before repeating work.
   - If Qdrant is unreachable, start Docker Desktop if needed, then run `.ai/scripts/start-ai-stack.ps1` and retry the Qdrant search.
   - If the `city-sim-memory` collection schema is incompatible with the MCP vector name, run `.ai/scripts/sync-important-notes-to-qdrant.py --execute --recreate` and retry.
5. Check Obsidian only for human-readable architecture decisions and design notes that are relevant to the task.
6. Use Context7 only when current Godot or external API documentation matters.
7. Use LightRAG only for larger architecture questions spanning multiple systems.
8. Change code only after the relevant local files and project memory have been checked.

## Project Context

- This is a Godot 4.6.1 or later city simulation project.
- Use typed GDScript wherever practical.
- Do not load unnecessary context.
- Do not improvise whole-project PowerShell or `rg` scans when a project script can answer the question.
- Keep systems separated: simulation, economy, navigation, citizens, UI, logging, and tooling should not bleed into each other.
- Prefer small, testable changes over broad rewrites.
- Reuse or refactor existing code instead of creating another version.

## Knowledge System

- Project index lives in `.ai/project_index/` and should stay compact.
- Repeatable project tools live in `.ai/scripts/`:
  - `citysim_project_scan.py` refreshes the compact project index.
  - `citysim_cleanup_check.py` finds cleanup candidates safely.
  - `citysim_find_references.py` searches references without leaving the project root.
- Use the Obsidian vault at `C:\dev\projects\ai_brain` for human-readable project decisions and architecture notes.
- The project memory folder is `C:\dev\projects\ai_brain\30_Projects\Godot City Sim`.
- Do not index `.obsidian` internal settings.
- Do not store everything twice: Obsidian is for narrative decisions; Qdrant is for short searchable facts.
- Store only concise summaries, architecture decisions, known bugs, reusable snippets, and important Godot simulation patterns in Qdrant.
- Good Qdrant entry style: `CitizenLocomotion handles movement execution only. Do not add daily planning logic here.`

## Coding Rules

- Comments in code must be English.
- Keep code clear, maintainable, and production-oriented.
- Avoid unnecessary complexity and speculative abstractions.
- Prefer existing project patterns unless there is a concrete reason to change them.
- Delete code only when references, scenes, tests, and project memory indicate it is unused or obsolete.
- Validate behavior with the existing test scripts when changes touch runtime logic.

## Communication

- Explain final results to the user in German.
- If requirements are ambiguous or risky, ask targeted questions before changing code.
