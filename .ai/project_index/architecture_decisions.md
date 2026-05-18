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
- Citizen LOD is a configurable hard render budget: `focus_citizens` defaults to 15 visible/full-sim Citizens, `active_citizens` defaults to 0 additional visible cheaper Citizens, and the remaining Citizens are coarse hidden/background-sim unless protected by explicit commitments such as player/dialog/meeting.
- With `rotation.enforce_background_budget=true`, LOD hold/hysteresis must not exceed `focus_citizens + active_citizens`; local player and selected/dialog Citizens count inside the visible budget where possible.
- Runtime must auto-start `CitizenSimulationLodController` once World, selection state, and a camera are available. A missing LOD controller must not silently leave every Citizen rendered.
- Citizen visibility has independent interior and LOD reasons. Building exit/entry must apply the combined visibility state so interior logic cannot reveal coarse hidden LOD Citizens.
- Citizen LOD anti-pop transitions must count against the visible budget. Do not materialize hidden outdoor Citizens or dematerialize visible Citizens inside the active camera view; keep temporary visible coarse holds moving until they leave view.

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
- Server-authorized Citizen interactions must not depend only on a stale approach point; live direct range to moving Citizen targets can complete the interaction.

## Camera Ownership Rules

- `CameraModeManager` (RefCounted, `Simulation/Camera/`) is the single owner of which camera is `current`; never set `Camera3D.current` for the player/builder cameras anywhere else. Modes: `PLAYER_THIRD_PERSON` (default) and `CITY_BUILDER`.
- `PlayerThirdPersonCamera` is a decoupled rig (Node3D → SpringArm3D → Camera3D) that follows only the player's position and owns its own yaw/pitch — it is NOT a child of the citizen body (the body's per-frame `look_at` would otherwise spin it).
- `PlayerThirdPersonCamera.follow_distance` is the initial SpringArm distance, clamped by `min_distance`/`max_distance`; if close camera tuning is wanted, lower `min_distance` too.
- `CityBuilderCamera` stays as the builder/admin camera only. It is the safe fallback whenever there is no player target (pre-game menu, bootstrap).
- Clients are locked to `PLAYER_THIRD_PERSON`; `toggle()`/`set_mode(CITY_BUILDER)` are no-ops for clients. Host/offline may toggle via the HUD bottom-bar button (hidden for clients).
- Host/client player-follow and the offline ControlledCitizen route through the manager (`set_follow_target`/`set_player_target`), never by poking `get_viewport().get_camera_3d()`.
- Direct WASD/click control of an arbitrary selected citizen was removed; only the real local player avatar (networked player or offline ControlledCitizen) is controllable.

## Knowledge Storage Rule

- Obsidian is the readable long-term memory.
- Qdrant gets only short decisions, constraints, known bugs, and reusable patterns.
- LightRAG is optional and reserved for larger cross-system architecture questions.
- If Qdrant is unreachable, start Docker Desktop if needed, run `.ai/scripts/start-ai-stack.ps1`, then retry. The `city-sim-memory` collection must use named vector `fast-all-minilm-l6-v2` and payload field `document`; repair with `.ai/scripts/sync-important-notes-to-qdrant.py --execute --recreate`.
