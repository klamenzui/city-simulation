# Architecture Decisions

Purpose: compact decisions that should be checked before architectural edits.

## Current Decisions

- Keep `main.gd` thin; push bootstrap, runtime, UI, and debug work into dedicated controllers.
- Keep simulation systems separated: citizens, economy, navigation, buildings, UI, debug, and tooling.
- Prefer typed GDScript where practical.
- Use local files and `.ai/project_index/` before loading broad context.
- Use `.ai/scripts/citysim_project_scan.py`, `citysim_cleanup_check.py`, and `citysim_find_references.py` for repeatable project analysis; PowerShell should only launch them.
- Use Qdrant for short searchable facts, not full files.
- Use Obsidian for narrative decisions and architecture notes. Do not duplicate all project index data there.
- Use `C:\dev\projects\ai_brain\30_Projects\Godot City Sim` as the Obsidian project-memory folder.

## Citizen Ownership Rules

- `CitizenLocomotion` should own movement execution only.
- `CitizenPlanner` should own decisions and daily plan creation.
- Navigation helpers should not own schedule/economy decisions.
- Citizen debug/logging helpers should not affect spawn/runtime performance unless explicitly enabled.
- Population refill belongs to `World`: `Citizen.die()` cleans up and unregisters, but replacement Citizens are spawned later through the World refill queue and `CitizenFactory`.

## Navigation Ownership Rules

- `RoadGraph` and `PedestrianGraph` should not duplicate graph search logic blindly.
- Citizens should use pedestrian routing and crosswalk-aware transitions, not general road-surface routing.
- Surface classification and local perception should be allocation-conscious because they run frequently.

## Economy Ownership Rules

- `EconomySystem` owns transfers and daily financial resolution.
- Buildings store state, account, condition, jobs, and status.
- Public buildings and commercial buildings have different funding/closure behavior.
- World job offers must count assigned jobs as slot reservations, including trainee jobs that are not hired yet. Education completion promotes the reserved job into a real building worker.

## Multiplayer Ownership Rules

- Phase 1 uses Godot ENet in host-authoritative mode; Steam/Relay integration is deferred.
- `Simulation/Multiplayer/shared`, `client`, and `server` separate serialization, client replica state, and host authority.
- Host/server owns `World`, `TimeSystem`, `EconomySystem`, Citizen spawn, GOAP, building state, and money transfers.
- Clients are view/input layers: they do not tick world simulation, spawn authoritative citizens, or mutate economy/building/citizen state directly.
- Clients receive snapshots and may send command dictionaries; command execution must be validated on the host/server.
- Client-owned player replicas may use local prediction, but authoritative snapshots should reconcile softly and avoid hard per-snapshot correction unless drift is large.
- Controlled host/client player citizens use `CityBuilderCamera` controller-follow mode; normal selected-citizen follow remains the city follow camera.
- Server-authorized Citizen interactions must not depend only on a stale approach point; live direct range to moving Citizen targets can complete the interaction.

## Knowledge Storage Rule

- Obsidian is the readable long-term memory.
- Qdrant gets only short decisions, constraints, known bugs, and reusable patterns.
- LightRAG is optional and reserved for larger cross-system architecture questions.
