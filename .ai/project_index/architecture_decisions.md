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
- `World` creates the simulation timer but `SceneRuntimeController` starts it only after initial Citizens are spawned and the population floor is captured. The world must not tick target-refill logic while the main menu/runtime setup is still pending.
- Citizen visibility has independent interior and LOD reasons. Building exit/entry must apply the combined visibility state so interior logic cannot reveal coarse hidden LOD Citizens.
- Citizen LOD anti-pop transitions must count against the visible budget. Do not materialize hidden outdoor Citizens or dematerialize visible Citizens inside the active camera view; keep temporary visible coarse holds moving until they leave view.

## Navigation Ownership Rules

- `RoadGraph` and `PedestrianGraph` should not duplicate graph search logic blindly.
- Citizens should use pedestrian routing and crosswalk-aware transitions, not general road-surface routing.
- Surface classification and local perception should be allocation-conscious because they run frequently.
- Building travel treats Citizens already inside direct planar arrival tolerance of a building access point as arrived. Do not emit route failures for sub-meter entrance hops; keep this limited to building destinations.

## Economy Ownership Rules

- `EconomySystem` owns transfers and daily financial resolution.
- Buildings store state, account, condition, jobs, and status.
- Mixed-use structures use composition: a `ResidentialBuilding` owns housing only, while nested `Shop`, `Cafe`, or `Restaurant` nodes represent independent ground-floor businesses with their own entrance, occupancy, jobs, inventory, and finances. `BuildingUseBinder` may generate these units from plain scene tags/metadata such as `building_uses=residential,shop`, but generated units are still real `Building` nodes. Recursive click, mesh, physics, and navigation ownership must stop at nested `Building` boundaries.
- Public buildings and commercial buildings have different funding/closure behavior.
- World job offers must count assigned jobs as slot reservations, including trainee jobs that are not hired yet. Education completion promotes the reserved job into a real building worker.
- Restaurants require at least one employed worker to operate. Supermarket and Cafe remain food-access fallbacks until supply chains and starvation balance are mature.
- First commercial ownership slice: cafes, restaurants, shops, supermarkets, cinemas, farms, and factories can be citizen-owned. Unowned buildings are bought from the city account; positive daily net profit pays from the building account to the citizen owner wallet after obligations. Simple non-manual Citizens can buy at most one unowned property per Payday only if their business aptitude, health/hunger state, and post-purchase living reserve allow it; wealth alone must not trigger purchases.

## Player Gameplay Roadmap

- Keep the near-term career model two-stage: employee and owner. Do not add a manager rank until manager gameplay has distinct decisions.
- Workplace gameplay should become 3D, state-driven activity inside the workplace, not abstract random button events. Activities should come from real building/customer state.
- Future player work gameplay should have three large job-game pillars: Farm, Delivery/Logistics, and Taxi/Rideservice. Smaller jobs can remain compact minigames, but still must be driven by real simulation state.
- Farm gameplay should be a bounded job scene, not a second independent farm simulator. Player work produces shift results such as harvested amount, quality, delivered crates, mistakes, and time bonus; the existing Farm/Economy systems remain authoritative.
- Farm player work should run in a separate WorkScene/overlay because field plots, tools, carry limits, and crop interactions need their own dense interaction space. The main world starts the job and remains the source of truth; the WorkScene returns a validated result to the real Farm.
- When no player is actively working a Farm WorkScene, NPC farm workers and the normal economy/delivery loops must continue unchanged. A player Farm WorkScene may reserve only the same farm's harvest activity while active; it must not stop city time, delivery drivers, or unrelated farms.
- Delivery/Logistics gameplay should use real production, stock, demand, route, vehicle capacity, fragile/cold goods, and time-window state. It should connect Farm/Factory/Warehouse producers to Shop/Supermarket/Restaurant consumers.
- Taxi/Rideservice gameplay should use real citizen trip needs when possible, such as work, home, leisure, hospital, or shopping destinations. Scoring should consider time, route quality, comfort, mistakes, customer satisfaction, and money earned.
- Taxi service is depot-based, not MVP teleport behavior: requests require `TaxiVehicleDepot` or a real `TaxiDepot`; pickup/drop-off/return use RoadGraph vehicle routes, while `TaxiVehicleDepot` parking and exit use short local maneuvers between road access and the depot.
- Vehicle depot parking targets a free `VehicleParkingSpot` from the `VehicleDepot` node (`reserve_next_parking_spot`/`occupy`/`release`), not a single marker center. Both `DeliveryVehicleDepot` and `TaxiVehicleDepot` carry the `VehicleDepot` script directly on the named node; `VehicleDepotAccess.resolve_depot`/`find_depot_in` still locate it self-or-descendant so a wrapped layout keeps working. Taxi (`TaxiService`) and delivery (`Factory`/`Farm`) reserve on arrival, occupy when parked, release on departure, and fall back to the marker `CollisionShape3D` center when no depot/free spot exists.
- Delivery vehicles use a `DeliveryVehicleDepot` as their fleet/home depot and must claim pre-placed free depot vehicles instead of instantiating dynamic delivery cars. Farm deliveries then drive empty from the home depot to the nearest `DeliveryLoadingDepot`/`delivery_loading_depots` parking area, perform a short local parking/loading stop, calculate load quantity there, and only then drive to the target. Cargo visuals must become visible at the loading depot before the truck exits back to the road. If nothing can be loaded at the loading stop, the vehicle returns to the home depot. Vehicle load quantity is capped by `VehicleAgent.delivery_load_capacity`; the current depot setup uses a 4-unit pickup and an 8-unit truck. VehicleDepot nodes are parking destinations, not RoadGraph road nodes; RoadGraph access should resolve to the nearest real connected road and local depot maneuvers handle parking. Delivery cleanup must remove `delivery_vehicle_assigned` when an order finishes or aborts so parked fleet vehicles become claimable again. Explicit service destination stops such as taxi drop-off and deliveries to shops/businesses/supermarkets use `VehicleAgent` curbside pullout routes; depot approaches and local parking maneuvers must remain normal road-access/parking routes.
- Delivery/Logistics and Taxi/Rideservice should run in the main world because their gameplay depends on live roads, buildings, citizens, vehicles, and city routes.
- Multiplayer competition should be considered at data-contract level for every job-game: record comparable score outputs such as earned_money, time_used, quality_score, mistakes, customer_satisfaction, goods_produced, goods_delivered, and reputation_gain. Host/server remains authoritative for economy and job results.
- Commercial ownership should grow from the first buy/profit/personality-gated AI slice into resale, insolvency sale, richer AI purchase criteria, and owner controls for prices/wages/stock.
- Social invitations must become commitments: when dialog agrees on restaurant, park, cinema, or similar, both participants should get a shared destination/action plan instead of just flavor text.
- First social invitation slice: clear phrases such as "lass uns essen gehen" create a `SocialVisitAction` for player and NPC. The action sequences existing GoTo + restaurant/park/cinema activity actions and only chooses real usable targets.
- Wardrobe/clothing is a good early home interaction because it does not require apartment interiors. Store owned clothes on the Citizen/player inventory and apply a selected outfit.

## Vehicle Scene Contract

- Four-wheel CityPack vehicle scenes should follow the taxi `VehicleAgent` contract: `VehicleBody3D` root, `VisualRoot`, enabled `CollisionShape3D`, four direct `VehicleWheel3D` nodes, `EntryPoint`, `SeatPoint`, and `EngineSound`. The adapted CityPack four-wheel scenes are `bus`, `van`, `suv`, `police_car`, `sports_car`, `sports_car_gzj704_d_xdr`, and `car_unqqk_u_lt_ru`; keep `bicycle` and `motorcycle` out of this contract until two-wheel physics is defined.

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

## Environment Ownership Rules

- Grass is part of the generated biome/YAMMS scatter system (`MeadowPlantsScatter` with `GrassItem` and `Scenes/Plants/Biomes/Stylized3DGrass.tres`). Do not reintroduce runtime `ExteriorGrassDecorator` bootstrap grass; keep grass visual-only with no collision or walkable/building groups.

## Knowledge Storage Rule

- Obsidian is the readable long-term memory.
- Qdrant gets only short decisions, constraints, known bugs, and reusable patterns.
- LightRAG is optional and reserved for larger cross-system architecture questions.
- If Qdrant is unreachable, start Docker Desktop if needed, run `.ai/scripts/start-ai-stack.ps1`, then retry. The `city-sim-memory` collection must use named vector `fast-all-minilm-l6-v2` and payload field `document`; repair with `.ai/scripts/sync-important-notes-to-qdrant.py --execute --recreate`.
