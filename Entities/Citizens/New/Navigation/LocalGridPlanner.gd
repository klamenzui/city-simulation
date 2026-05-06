class_name LocalGridPlanner
extends RefCounted

## Layer 3 of the 4-layer navigation pipeline (Navigation.md §Local Planner).
##
## Builds a small dual-subdivided 8-connect A* grid around the citizen, marks
## cells by (physics_blocked, surface_kind, road_buffer) and finds the best
## reachable goal candidate that lies in the forward half-circle.
##
## Doubled-coordinate grid layout (dual-subdivided 8-connect grid):
##   Normal cells     Vector2i(x*2,   z*2)   at world offset (x*step,       z*step)
##   Staggered cells  Vector2i(x*2+1, z*2+1) at world offset ((x+0.5)*step, (z+0.5)*step)
## World offset from any cell: Vector2(cell.x * step * 0.5, cell.y * step * 0.5)
##
## NOTE: this is NOT a true hex grid (despite the original "hex" naming). It
## is a dual-subdivided grid where the staggered cells fill the diagonals
## between the four corners of each square. The `_GRID_NEIGHBORS` list keeps
## both diagonal connections (±1,±1) AND axial connections (±2,0)+(0,±2) on
## purpose: removing the axial connections forces A* to zig-zag between
## diagonals on long straight runs. Measured by `tools/codex_local_grid_topology_test.gd`:
##   8-NEIGHBOUR (current):  forward path length 1.165 m, 2 dir changes
##   6-NEIGHBOUR (pure-hex): forward path length 1.612 m, 6 dir changes (38% worse)
##
## Output: `BuildResult`-shaped Dictionary (see RESULT_KEY_* constants).

const RESULT_KEY_SUCCESS: String = "success"
const RESULT_KEY_PATH: String = "path"               # PackedVector3Array (world-space waypoints)
const RESULT_KEY_GOAL: String = "goal"               # Vector3 (last waypoint, ZERO if none)
const RESULT_KEY_STATUS: String = "status"           # human-readable summary
const RESULT_KEY_FOLLOW_GLOBAL: String = "follow_global"  # bool — abandon avoidance, trust global
const RESULT_KEY_SURFACE_ESCAPE: String = "surface_escape_cooldown"  # float secs to suppress surface-escape
const RESULT_KEY_DEBUG_CELLS: String = "debug_cells"
const RESULT_KEY_DEBUG_HITS: String = "debug_physics_hits"

## Connectivity for the dual-subdivided grid. 4 diagonals connect each cell
## to its 4 surrounding "fill" cells; 4 axial connections (±2,0)+(0,±2) keep
## long straight runs from zig-zagging through the diagonals (see class doc).
## Do NOT remove the axial entries — `tools/codex_local_grid_topology_test.gd`
## guards this and will fail if you do.
const _GRID_NEIGHBORS: Array[Vector2i] = [
	Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1),
	Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2),
]

var _ctx: NavigationContext
var _perception: LocalPerception

# ---------------------------------------------------------- Reusable buffers
# Replan runs ~0.5–1× per second per citizen during avoidance. Allocating a
# fresh AStar2D + 3 working dicts + a candidates array each time was the
# largest remaining GC source in the navigation stack. All five containers
# below are member-scoped: `clear()` at the start of `build_detour` keeps
# the backing capacity, only the contents reset.
var _astar: AStar2D = AStar2D.new()
var _point_ids: Dictionary = {}
var _cell_surfaces: Dictionary = {}
var _cell_hit_positions: Dictionary = {}
## Maps cell → top-hit world position for the height/clearance planner mode.
## Separate from `_cell_hit_positions` because live planning keeps surface-ray
## floor hits for road/crosswalk classification and stores top-hit obstacle
## samples independently.
var _cell_top_hit_positions: Dictionary = {}
## Maps cell → top-hit collider path string (only populated when scan_at runs
## with `use_top_hit=true` or live height-planning is enabled). Lets the
## debug log identify *what* the ray / clearance sphere hit even when the
## legacy multi-height physics stack is disabled.
var _cell_top_colliders: Dictionary = {}
## Maps cell → height_blocked bool. Used in scan_at for the post-pass that
## adds a 1-cell wall_buffer around vertically-tall obstacles (posts /
## hydrants / wall-tops): the citizen capsule can't physically squeeze
## right next to a wall, so neighbour-cells of a height-blocked cell are
## marked unwalkable too.
var _cell_height_blocked: Dictionary = {}
## Maps cell → probe verdict dictionary. Reused by live `build_detour` so
## obstacle analysis and registration happen in separate passes without
## reallocating a fresh Dictionary per cell every replan.
var _cell_probe_infos: Dictionary = {}
var _candidates: Array[Dictionary] = []

# Cache for `_neighbor_offsets_in_radius(N)` — depends only on N (config-stable),
# but used to be recomputed once per cell × replan via `_is_cell_within_road_buffer`.
# Maps radius (int) → frozen offsets list.
var _neighbor_offsets_cache: Dictionary = {}


func _init(context: NavigationContext, perception: LocalPerception) -> void:
	_ctx = context
	_perception = perception


## Builds the detour grid and picks the best candidate.  `desired_direction`
## must be planar + non-zero; `global_path_context` is used to score candidate
## cells by how close they stay to the global route.
func build_detour(desired_direction: Vector3,
		global_path: PackedVector3Array,
		path_index: int,
		target_position: Vector3) -> Dictionary:
	var logger := _ctx.logger
	_ctx.logger.clear_probe_hit_dedup()

	var result := {
		RESULT_KEY_SUCCESS: false,
		RESULT_KEY_PATH: PackedVector3Array(),
		RESULT_KEY_GOAL: Vector3.ZERO,
		RESULT_KEY_STATUS: "planning",
		RESULT_KEY_FOLLOW_GLOBAL: false,
		RESULT_KEY_SURFACE_ESCAPE: 0.0,
		RESULT_KEY_DEBUG_CELLS: [],
		RESULT_KEY_DEBUG_HITS: [],
	}

	if not _ctx.is_ready_for_physics():
		result[RESULT_KEY_STATUS] = "no world"
		logger.warn("LOCAL_GRID", "BUILD_ABORT", {"reason": "no_world"})
		return result

	var forward := desired_direction
	forward.y = 0.0
	if forward.length_squared() <= 0.0001:
		result[RESULT_KEY_STATUS] = "no forward"
		logger.warn("LOCAL_GRID", "BUILD_ABORT", {"reason": "no_forward"})
		return result
	forward = forward.normalized()

	var cfg := _ctx.config
	var right := LocalPerception._planar_right(forward)
	var cell_size := maxf(cfg.local_astar_cell_size, 0.08)
	var radius := maxf(cfg.local_astar_radius, cell_size * 2.0)
	var step := cell_size / float(maxi(cfg.local_astar_grid_subdivisions, 1))
	var cell_radius := int(ceil(radius / step))
	var doubled_radius := cell_radius * 2
	var origin := _ctx.get_owner_position()

	var start_cell := Vector2i.ZERO
	var start_id := _cell_id(start_cell, doubled_radius)
	var start_surface_kind := _perception.get_surface_kind(origin)
	var start_needs_escape := _is_surface_blocked(start_surface_kind)
	var max_step_height := maxf(cfg.local_astar_height_block_threshold, 0.0)
	var use_height_clearance := max_step_height > 0.0
	var height_probe_radius := maxf(cfg.local_astar_height_clearance_probe_radius, 0.03)
	var top_hit_probe_up := maxf(
			cfg.local_astar_surface_probe_up,
			cfg.local_astar_probe_max_height + max_step_height + height_probe_radius + 0.05)
	# Reuse member buffers — clear keeps backing capacity, only contents reset.
	_point_ids.clear()
	_cell_surfaces.clear()
	_cell_hit_positions.clear()
	_cell_top_hit_positions.clear()
	_cell_top_colliders.clear()
	_cell_height_blocked.clear()
	_cell_probe_infos.clear()
	_candidates.clear()
	_astar.clear()
	var point_ids: Dictionary = _point_ids
	var cell_surfaces: Dictionary = _cell_surfaces
	var cell_hit_positions: Dictionary = _cell_hit_positions
	var cell_probe_infos: Dictionary = _cell_probe_infos
	var astar: AStar2D = _astar

	# debug_cells/debug_hits are returned to the caller and held until the
	# next replan — cannot share a member buffer without corrupting the
	# caller's view. Fresh allocation per replan is fine, they're small.
	var debug_cells: Array[Dictionary] = []
	var debug_hits: Array[Dictionary] = []

	# Pass 1: surface probe for ALL cells so road-buffer in Pass 2 can read any
	# neighbour regardless of iteration order.
	for z in range(-cell_radius, cell_radius + 1):
		for x in range(-cell_radius, cell_radius + 1):
			_fill_cell_surface(Vector2i(x * 2, z * 2), step, radius,
					origin, right, forward, cell_surfaces, cell_hit_positions)
		if z < cell_radius:
			for x in range(-cell_radius, cell_radius):
				_fill_cell_surface(Vector2i(x * 2 + 1, z * 2 + 1), step, radius,
						origin, right, forward, cell_surfaces, cell_hit_positions)

	# Pass 1b: top-hit obstacle samples for the live height/clearance planner.
	if use_height_clearance:
		for z in range(-cell_radius, cell_radius + 1):
			for x in range(-cell_radius, cell_radius + 1):
				_fill_cell_top_hit(Vector2i(x * 2, z * 2), step, radius,
						origin, right, forward, top_hit_probe_up)
			if z < cell_radius:
				for x in range(-cell_radius, cell_radius):
					_fill_cell_top_hit(Vector2i(x * 2 + 1, z * 2 + 1), step, radius,
							origin, right, forward, top_hit_probe_up)

	# Pass 2: collect per-cell probe verdicts.
	for z in range(-cell_radius, cell_radius + 1):
		for x in range(-cell_radius, cell_radius + 1):
			_collect_live_cell_probe_info(Vector2i(x * 2, z * 2), step, radius,
					origin, right, forward, cell_surfaces, cell_hit_positions,
					cell_probe_infos, use_height_clearance, max_step_height, height_probe_radius)
		if z < cell_radius:
			for x in range(-cell_radius, cell_radius):
				_collect_live_cell_probe_info(Vector2i(x * 2 + 1, z * 2 + 1), step, radius,
						origin, right, forward, cell_surfaces, cell_hit_positions,
						cell_probe_infos, use_height_clearance, max_step_height, height_probe_radius)

	# Pass 3: register navigable cells. Height blockers gain a 1-ring
	# wall_buffer so the capsule does not scrape directly past tall props.
	for z in range(-cell_radius, cell_radius + 1):
		for x in range(-cell_radius, cell_radius + 1):
			_register_live_cell(Vector2i(x * 2, z * 2), doubled_radius, step, radius,
					start_cell, start_needs_escape, point_ids, astar,
					cell_probe_infos, debug_cells, debug_hits, use_height_clearance)
		if z < cell_radius:
			for x in range(-cell_radius, cell_radius):
				_register_live_cell(Vector2i(x * 2 + 1, z * 2 + 1), doubled_radius, step, radius,
						start_cell, start_needs_escape, point_ids, astar,
						cell_probe_infos, debug_cells, debug_hits, use_height_clearance)

	result[RESULT_KEY_DEBUG_CELLS] = debug_cells
	result[RESULT_KEY_DEBUG_HITS] = debug_hits

	if not point_ids.has(start_cell):
		result[RESULT_KEY_STATUS] = "blocked start"
		logger.warn("LOCAL_GRID", "BUILD_FAIL", {
			"reason": "blocked_start",
			"pos": origin,
			"surface": start_surface_kind,
		})
		return result

	# Connect neighbours (bidirectional).
	for cell_key in point_ids.keys():
		var cell: Vector2i = cell_key
		var point_id: int = point_ids[cell]
		for neighbor_offset: Vector2i in _GRID_NEIGHBORS:
			var neighbor_cell := cell + neighbor_offset
			if not point_ids.has(neighbor_cell):
				continue
			var neighbor_id: int = point_ids[neighbor_cell]
			if point_id < neighbor_id:
				astar.connect_points(point_id, neighbor_id, true)

	# Gather candidate cells in the forward half-circle. Member buffer reused.
	var candidates: Array[Dictionary] = _candidates
	var front_y := -INF
	var left_open := false
	for cell_key in point_ids.keys():
		var cell: Vector2i = cell_key
		if cell == start_cell:
			continue

		var candidate_surface := str(cell_surfaces.get(cell, SurfaceClassifier.KIND_UNKNOWN))
		if _is_surface_blocked(candidate_surface):
			continue

		var candidate_offset := Vector2(float(cell.x) * step * 0.5, float(cell.y) * step * 0.5)
		if start_needs_escape:
			if candidate_offset.length() <= cell_size * 0.5:
				continue
		else:
			if candidate_offset.y <= 0.0:
				continue
			if candidate_offset.length() < radius - cell_size * 1.5:
				continue

		var goal_id: int = point_ids[cell]
		var candidate_path := astar.get_point_path(start_id, goal_id)
		if candidate_path.size() < 2:
			continue

		var candidate_world := _world_from_offset(origin, right, forward, candidate_offset)
		var reference_distance := _distance_to_global_path_ahead(candidate_world,
				global_path, path_index, target_position)
		var path_length := _path_length_2d(candidate_path)
		var near_road := false
		for nb_off in _GRID_NEIGHBORS:
			if _is_surface_blocked(str(cell_surfaces.get(cell + nb_off, ""))):
				near_road = true
				break

		candidates.append({
			"path": candidate_path,
			"offset": candidate_offset,
			"reference_distance": reference_distance,
			"path_length": path_length,
			"surface": candidate_surface,
			"near_road": near_road,
		})
		front_y = maxf(front_y, candidate_offset.y)
		if candidate_offset.x < -cell_size:
			left_open = true

	if candidates.is_empty():
		result[RESULT_KEY_STATUS] = "all x red global"
		result[RESULT_KEY_FOLLOW_GLOBAL] = true
		# Back off 2s — see original monolith; prevents spin-in-place on
		# pedzones whose probe momentarily reads as road.
		result[RESULT_KEY_SURFACE_ESCAPE] = 2.0
		logger.warn("LOCAL_GRID", "NO_CANDIDATES", {
			"reason": "all_blocked",
			"pos": origin,
			"cells_total": point_ids.size(),
		})
		return result

	# Two-tier selection: road-free cells strongly preferred over near-road.
	var has_road_free_front := false
	if not start_needs_escape:
		for candidate in candidates:
			if candidate.get("near_road", false):
				continue
			var off: Vector2 = candidate.get("offset", Vector2.ZERO)
			if off.y >= front_y - maxf(cfg.local_astar_front_row_tolerance, cell_size):
				has_road_free_front = true
				break

	var prefer_right := cfg.local_astar_prefer_right_when_left_open and left_open
	var has_right_front := false
	if prefer_right and not start_needs_escape:
		for candidate in candidates:
			if has_road_free_front and candidate.get("near_road", false):
				continue
			var off: Vector2 = candidate.get("offset", Vector2.ZERO)
			if off.y >= front_y - maxf(cfg.local_astar_front_row_tolerance, cell_size) \
					and off.x >= 0.0:
				has_right_front = true
				break

	var best_path := PackedVector2Array()
	var best_score := INF
	var selection_label := "surface escape" if start_needs_escape else "front row"
	var front_tolerance := maxf(cfg.local_astar_front_row_tolerance, cell_size)

	for candidate in candidates:
		var candidate_offset: Vector2 = candidate.get("offset", Vector2.ZERO)
		if not start_needs_escape:
			if candidate_offset.y < front_y - front_tolerance:
				continue
			if prefer_right and has_right_front and candidate_offset.x < 0.0:
				continue
			if has_road_free_front and candidate.get("near_road", false):
				continue

		var reference_distance: float = candidate.get("reference_distance", INF)
		var path_length: float = candidate.get("path_length", 0.0)
		var score := reference_distance + path_length * (0.25 if start_needs_escape else 0.1)
		if candidate.get("near_road", false):
			score += cfg.local_astar_near_road_penalty
		if prefer_right and not start_needs_escape:
			score -= candidate_offset.x * 0.05
			selection_label = "front row right"
		if score < best_score:
			best_score = score
			best_path = candidate.get("path", PackedVector2Array())

	if best_path.size() < 2:
		result[RESULT_KEY_STATUS] = "no reachable edge"
		logger.warn("LOCAL_GRID", "BUILD_FAIL", {
			"reason": "no_reachable_edge",
			"pos": origin,
			"candidates": candidates.size(),
		})
		return result

	var world_path := PackedVector3Array()
	for idx in range(1, best_path.size()):
		world_path.append(_world_from_offset(origin, right, forward, best_path[idx]))

	result[RESULT_KEY_SUCCESS] = true
	result[RESULT_KEY_PATH] = world_path
	result[RESULT_KEY_GOAL] = world_path[world_path.size() - 1]
	result[RESULT_KEY_STATUS] = "%s %d" % [selection_label, world_path.size()]

	logger.info("LOCAL_GRID", "BUILD_OK", {
		"status": selection_label,
		"waypoints": world_path.size(),
		"goal": world_path[world_path.size() - 1],
		"candidates": candidates.size(),
		"cells_total": point_ids.size(),
		"start_surface": start_surface_kind,
		"pos": origin,
	})
	return result


## Standalone debug scan — runs Pass 1 + Pass 2 at an arbitrary `origin`
## (instead of the Citizen's own position) and returns the debug cell/hit
## arrays. Used by the Coord-Picker "Scan Grid" mode.
##
## Does NOT register cells in AStar / pick candidates / build a path —
## purpose is purely to visualize what the grid would see.
##
## `radius_override` and `cell_size_override` (NAN = use config) let the
## debug tool experiment with different scan extents without editing the
## live citizen's tunables.
##
## `skip_physics_probe = true` disables Pass 2's sphere check, so cells
## are blocked only if the surface probe (down-ray) classifies them as
## road / road-buffer. The supplemental height-clearance sphere still runs
## when `max_step_height` is enabled — it replaces the aggressive legacy
## sphere stack with one targeted "can the capsule fit here?" check.
##
## `max_step_height` (NAN = disabled) enables the user's height-based
## block strategy: a cell is blocked if its detected ground-Y differs
## from the scan origin by more than this threshold. Captures walls,
## stairs, cliffs without any sphere probing.
##
## `probe_radius_override` (NAN = config) shrinks the sphere probe radius
## to expose tight squeezes — useful when the live config reaches too far
## into adjacent meshes (e.g. fat park-wall colliders).
##
## Returns a Dictionary:
##   { debug_cells, debug_hits, origin, forward, step, cell_size, cell_radius }
func scan_at(origin: Vector3, forward: Vector3,
		radius_override: float = NAN, cell_size_override: float = NAN,
		skip_physics_probe: bool = false, max_step_height: float = NAN,
		probe_radius_override: float = NAN) -> Dictionary:
	var planar_forward := forward
	planar_forward.y = 0.0
	if planar_forward.length_squared() <= 0.0001:
		planar_forward = Vector3.FORWARD
	planar_forward = planar_forward.normalized()

	var cfg := _ctx.config
	var right := LocalPerception._planar_right(planar_forward)
	var base_cell_size: float = cell_size_override if not is_nan(cell_size_override) \
			else cfg.local_astar_cell_size
	var cell_size := maxf(base_cell_size, 0.08)
	var base_radius: float = radius_override if not is_nan(radius_override) \
			else cfg.local_astar_radius
	var radius := maxf(base_radius, cell_size * 2.0)
	var step := cell_size / float(maxi(cfg.local_astar_grid_subdivisions, 1))
	var cell_radius := int(ceil(radius / step))
	var doubled_radius := cell_radius * 2

	# Reuse the same member buffers; build_detour always clears at start.
	_point_ids.clear()
	_cell_surfaces.clear()
	_cell_hit_positions.clear()
	_cell_top_hit_positions.clear()
	_cell_top_colliders.clear()
	_cell_height_blocked.clear()
	_cell_probe_infos.clear()
	_candidates.clear()
	_astar.clear()

	var debug_cells: Array[Dictionary] = []
	var debug_hits: Array[Dictionary] = []
	var start_cell := Vector2i.ZERO

	# Use top-hit probe when height-strategy is requested. The ray start is
	# lifted above the normal floor-probe origin so overhangs / wall-tops are
	# reachable, while Pass 2 supplements it with one small clearance sphere
	# just above `max_step_height`.
	var use_top_hit := not is_nan(max_step_height) and max_step_height > 0.0
	var height_probe_radius_override: float = NAN
	var top_hit_probe_up_override: float = NAN
	if use_top_hit:
		height_probe_radius_override = probe_radius_override
		if is_nan(height_probe_radius_override):
			# Keep the clearance probe inside roughly one debug-cell footprint.
			height_probe_radius_override = minf(cfg.local_astar_probe_radius, step * 1.6)
		var clearance_radius := maxf(height_probe_radius_override, 0.03)
		top_hit_probe_up_override = maxf(
				cfg.local_astar_surface_probe_up,
				cfg.local_astar_probe_max_height + max_step_height + clearance_radius + 0.05)

	# Pass 1: surfaces
	for z in range(-cell_radius, cell_radius + 1):
		for x in range(-cell_radius, cell_radius + 1):
			_fill_cell_surface(Vector2i(x * 2, z * 2), step, radius,
					origin, right, planar_forward, _cell_surfaces, _cell_hit_positions,
					use_top_hit, top_hit_probe_up_override)
		if z < cell_radius:
			for x in range(-cell_radius, cell_radius):
				_fill_cell_surface(Vector2i(x * 2 + 1, z * 2 + 1), step, radius,
						origin, right, planar_forward, _cell_surfaces, _cell_hit_positions,
						use_top_hit, top_hit_probe_up_override)

	# Pass 2: physics + register.
	for z in range(-cell_radius, cell_radius + 1):
		for x in range(-cell_radius, cell_radius + 1):
			_scan_cell_for_debug(Vector2i(x * 2, z * 2), doubled_radius, step, radius,
					origin, right, planar_forward, start_cell, false, debug_cells, debug_hits,
					skip_physics_probe, max_step_height,
					probe_radius_override, height_probe_radius_override)
		if z < cell_radius:
			for x in range(-cell_radius, cell_radius):
				_scan_cell_for_debug(Vector2i(x * 2 + 1, z * 2 + 1), doubled_radius, step, radius,
						origin, right, planar_forward, start_cell, false, debug_cells, debug_hits,
						skip_physics_probe, max_step_height,
						probe_radius_override, height_probe_radius_override)

	# Pass 3: wall-buffer — cells that are directly walkable but neighbour a
	# height-blocked cell get marked as wall_buffer. Captures the case where
	# a thin vertical obstacle (post, hydrant, wall) is hit by the down-ray
	# only on a few cells; the citizen capsule still can't squeeze past it
	# from the adjacent cells.
	if use_top_hit and not _cell_height_blocked.is_empty():
		_apply_wall_buffer(debug_cells)

	return {
		"debug_cells": debug_cells,
		"debug_hits": debug_hits,
		"origin": origin,
		"forward": planar_forward,
		"right": right,
		"step": step,
		"cell_size": cell_size,
		"cell_radius": cell_radius,
		"radius_world": radius,
	}


## Shared per-cell probe verdict used by both the live local planner and the
## debug scan. `surface_hit_pos` is always the floor-classification hit
## (`probe_surface` in live mode, `probe_top_hit` in debug top-hit mode).
## `top_hit_pos` / `top_hit_collider_name` optionally carry the dedicated
## top-most obstacle sample used by the height/clearance planner.
func _collect_cell_probe_info(
		cell: Vector2i, world_point: Vector3, origin_y: float,
		surface_kind: String, surface_hit_pos: Vector3,
		top_hit_pos: Vector3, has_top_hit: bool, top_hit_collider_name: String,
		use_legacy_physics: bool, max_step_height: float = NAN,
		probe_radius_override: float = NAN,
		height_probe_radius_override: float = NAN,
		allow_low_obstacle_fallback: bool = false) -> Dictionary:
	var physics_blocked: bool = false
	var physics_hit_pos: Vector3 = world_point
	var physics_collider_name: String = top_hit_collider_name if not use_legacy_physics else ""
	if use_legacy_physics:
		var physics_info := _perception.get_probe_block_info(
				world_point, origin_y, probe_radius_override)
		physics_blocked = bool(physics_info.get(LocalPerception.BLOCK_KEY_BLOCKED, false))
		physics_hit_pos = physics_info.get(
				LocalPerception.BLOCK_KEY_HIT_POS, world_point) as Vector3
		physics_collider_name = str(physics_info.get(
				LocalPerception.BLOCK_KEY_COLLIDER, ""))

	var surface_blocked := _is_surface_blocked(surface_kind)
	var near_road_buffer := _is_cell_within_road_buffer(cell, _cell_surfaces)
	var physics_near_road := false

	var top_height_blocked: bool = false
	var clearance_blocked: bool = false
	var height_diff: float = 0.0
	if not is_nan(max_step_height) and max_step_height > 0.0:
		if has_top_hit:
			height_diff = top_hit_pos.y - origin_y
			if absf(height_diff) > max_step_height:
				top_height_blocked = true
		if not top_height_blocked:
			var clearance_info := _perception.get_height_clearance_block_info(
					world_point, origin_y, max_step_height, height_probe_radius_override)
			clearance_blocked = bool(clearance_info.get(
					LocalPerception.BLOCK_KEY_BLOCKED, false))
			if clearance_blocked and not physics_blocked:
				physics_hit_pos = clearance_info.get(
						LocalPerception.BLOCK_KEY_HIT_POS, world_point) as Vector3
				physics_collider_name = str(clearance_info.get(
						LocalPerception.BLOCK_KEY_COLLIDER, physics_collider_name))
		if top_height_blocked and not physics_blocked and not clearance_blocked:
			physics_hit_pos = top_hit_pos
			if physics_collider_name.is_empty():
				physics_collider_name = top_hit_collider_name
		if clearance_blocked and not top_height_blocked:
			height_diff = max_step_height + 0.01
		var ambiguous_surface := surface_kind != SurfaceClassifier.KIND_PEDESTRIAN \
				and surface_kind != SurfaceClassifier.KIND_CROSSWALK \
				and surface_kind != SurfaceClassifier.KIND_ROAD
		if allow_low_obstacle_fallback and ambiguous_surface \
				and not top_height_blocked and not clearance_blocked:
			var low_info := _perception.get_low_obstacle_block_info(
					world_point, origin_y,
					_ctx.config.local_astar_probe_min_height,
					height_probe_radius_override)
			if bool(low_info.get(LocalPerception.BLOCK_KEY_BLOCKED, false)):
				physics_blocked = true
				physics_hit_pos = low_info.get(
						LocalPerception.BLOCK_KEY_HIT_POS, world_point) as Vector3
				physics_collider_name = str(low_info.get(
						LocalPerception.BLOCK_KEY_COLLIDER, physics_collider_name))

	var height_blocked := top_height_blocked or clearance_blocked
	if physics_blocked and _ctx.config.local_astar_physics_near_road_margin > 0.0:
		physics_near_road = _perception.is_point_near_road(
				physics_hit_pos, _ctx.config.local_astar_physics_near_road_margin)
	var blocked := physics_blocked or surface_blocked or near_road_buffer \
			or physics_near_road or height_blocked
	var reason := _blocked_reason_with_height(
			physics_blocked, surface_blocked, near_road_buffer,
			physics_near_road, height_blocked)

	return {
		"cell": cell,
		"world_pos": world_point,
		"surface_pos": surface_hit_pos,
		"physics_pos": physics_hit_pos,
		"blocked": blocked,
		"blocked_reason": reason,
		"surface": surface_kind,
		"collider": physics_collider_name,
		"height_diff": height_diff,
		"physics_blocked": physics_blocked,
		"surface_blocked": surface_blocked,
		"near_road_buffer": near_road_buffer,
		"physics_near_road": physics_near_road,
		"height_blocked": height_blocked,
	}


## Like `_probe_and_register_cell`, but always emits a debug entry
## (the original is gated by `debug_draw_avoidance`). Does not register
## the cell with AStar — debug-only.
##
## Uses `origin.y` as the probe-height base so the sphere stack sits
## relative to the scan position, not relative to wherever the citizen
## happens to stand right now. Without this, a scan far from the citizen
## reports every cell as physics-blocked (the spheres land in air or
## inside arbitrary mesh).
##
## `skip_physics_probe = true` skips the legacy multi-height sphere stack.
## The height strategy may still run its one-shot clearance sphere.
##
## `max_step_height` (NAN = disabled) blocks cells whose ground-Y differs
## from `origin.y` by more than this threshold. A small clearance sphere
## just above this threshold supplements the down-ray and catches open-top /
## side-only colliders that the ray can miss.
func _scan_cell_for_debug(
		cell: Vector2i, doubled_radius: int, step: float, radius: float,
		origin: Vector3, right: Vector3, forward: Vector3,
		start_cell: Vector2i, start_needs_escape: bool,
		debug_cells: Array[Dictionary], debug_hits: Array[Dictionary],
		skip_physics_probe: bool = false,
		max_step_height: float = NAN,
		probe_radius_override: float = NAN,
		height_probe_radius_override: float = NAN) -> void:
	var offset := Vector2(float(cell.x) * step * 0.5, float(cell.y) * step * 0.5)
	if offset.length() > radius:
		return
	var world_point := _world_from_offset(origin, right, forward, offset)
	var surface_kind: String = str(_cell_surfaces.get(cell, SurfaceClassifier.KIND_UNKNOWN))
	var surface_hit_pos: Vector3 = _cell_hit_positions.get(cell, world_point) as Vector3
	var top_hit_collider_name := str(_cell_top_colliders.get(cell, ""))
	var has_top_hit := _cell_top_colliders.has(cell)
	var info := _collect_cell_probe_info(
			cell, world_point, origin.y,
			surface_kind, surface_hit_pos,
			surface_hit_pos, has_top_hit, top_hit_collider_name,
			not skip_physics_probe, max_step_height,
			probe_radius_override, height_probe_radius_override, false)

	# Remember height-block decisions so Pass 3 can dilate them into a buffer.
	if bool(info.get("height_blocked", false)):
		_cell_height_blocked[cell] = true

	debug_cells.append(info)
	if bool(info.get("physics_blocked", false)) or bool(info.get("height_blocked", false)):
		debug_hits.append({
			"pos": info.get("physics_pos", world_point) as Vector3,
			"collider_name": str(info.get("collider", "")),
			"near_road": bool(info.get("physics_near_road", false)),
			"reason": str(info.get("blocked_reason", "")),
		})


## Extends `_blocked_reason` with the new "height" tag.
static func _blocked_reason_with_height(physics_blocked: bool, surface_blocked: bool,
		near_road_buffer: bool, physics_near_road: bool, height_blocked: bool) -> String:
	if height_blocked and (physics_blocked or surface_blocked):
		return "height+other"
	if height_blocked:
		return "height"
	return _blocked_reason(physics_blocked, surface_blocked, near_road_buffer, physics_near_road)


## Pass 3: dilate height-blocked cells into their immediate neighbours.
## Iterates `debug_cells` and marks any cell that (a) is currently walkable
## and (b) has at least one neighbour in `_cell_height_blocked` as
## `reason="wall_buffer"`. Works in-place; does NOT re-block already-blocked
## cells (their reason stays whatever the original Pass-2 verdict was).
func _apply_wall_buffer(debug_cells: Array[Dictionary]) -> void:
	for entry in debug_cells:
		var cell: Vector2i = entry.get("cell", Vector2i.ZERO)
		# Skip cells already blocked — keep their original reason.
		if bool(entry.get("blocked", false)):
			continue
		# Skip the height-blocked cells themselves.
		if _cell_height_blocked.has(cell):
			continue
		var has_height_neighbor := false
		for offset in _GRID_NEIGHBORS:
			if _cell_height_blocked.has(cell + offset):
				has_height_neighbor = true
				break
		if has_height_neighbor:
			entry["blocked"] = true
			entry["blocked_reason"] = "wall_buffer"


static func _cell_id(cell: Vector2i, cell_radius: int) -> int:
	var width := cell_radius * 2 + 1
	return (cell.y + cell_radius) * width + cell.x + cell_radius + 1


static func _world_from_offset(origin: Vector3, right: Vector3, forward: Vector3,
		offset: Vector2) -> Vector3:
	var point := origin + right * offset.x + forward * offset.y
	point.y = origin.y
	return point


static func _path_length_2d(path: PackedVector2Array) -> float:
	var total := 0.0
	for idx in range(path.size() - 1):
		total += path[idx].distance_to(path[idx + 1])
	return total


static func _distance_to_global_path_ahead(point: Vector3,
		global_path: PackedVector3Array, path_index: int,
		target_position: Vector3) -> float:
	if global_path.size() < 2:
		return _planar_distance(point, target_position)
	var best := INF
	var start_index := clampi(path_index - 1, 0, global_path.size() - 2)
	for idx in range(start_index, global_path.size() - 1):
		best = minf(best, _planar_distance_to_segment(point,
				global_path[idx], global_path[idx + 1]))
	return best


static func _planar_distance(a: Vector3, b: Vector3) -> float:
	var offset := a - b
	offset.y = 0.0
	return offset.length()


static func _planar_distance_to_segment(point: Vector3, from: Vector3, to: Vector3) -> float:
	var planar_point := point
	var planar_from := from
	var planar_to := to
	planar_point.y = 0.0
	planar_from.y = 0.0
	planar_to.y = 0.0
	var segment := planar_to - planar_from
	var segment_length_squared := segment.length_squared()
	if segment_length_squared <= 0.0001:
		return planar_point.distance_to(planar_from)
	var t := clampf((planar_point - planar_from).dot(segment) / segment_length_squared, 0.0, 1.0)
	var closest := planar_from + segment * t
	return planar_point.distance_to(closest)


func _is_surface_blocked(surface_kind: String) -> bool:
	if not _ctx.config.local_astar_avoid_road_cells:
		return false
	return surface_kind == SurfaceClassifier.KIND_ROAD


func _fill_cell_surface(
		cell: Vector2i, step: float, radius: float,
		origin: Vector3, right: Vector3, forward: Vector3,
		cell_surfaces: Dictionary, cell_hit_positions: Dictionary,
		use_top_hit: bool = false,
		top_hit_probe_up_override: float = NAN) -> void:
	var offset := Vector2(float(cell.x) * step * 0.5, float(cell.y) * step * 0.5)
	if offset.length() > radius:
		return
	var world_point := _world_from_offset(origin, right, forward, offset)
	var surface_hit: Dictionary
	if use_top_hit:
		# User's height-based strategy: top-most non-citizen hit. The Y of
		# this hit is the first half of the clearance decision; Pass 2 adds
		# one small sphere just above `max_step_height` for open-top colliders.
		surface_hit = _perception.probe_top_hit(world_point, top_hit_probe_up_override)
	else:
		# Walkable-priority multi-hit (legacy live-avoidance behavior).
		surface_hit = _perception.probe_surface(world_point)
	cell_surfaces[cell] = _perception.surface_kind_from_hit(surface_hit, world_point)
	cell_hit_positions[cell] = (surface_hit.get("position", world_point) as Vector3) \
			if not surface_hit.is_empty() else world_point
	# Capture the collider for debug logging — only meaningful in top-hit
	# mode (skip_physics_probe path), where Pass 2 doesn't fill it in.
	if use_top_hit and not surface_hit.is_empty():
		var col: Variant = surface_hit.get("collider", null)
		if col is Node:
			var n := col as Node
			_cell_top_colliders[cell] = str(n.get_path()) if n.is_inside_tree() else n.name
		else:
			_cell_top_colliders.erase(cell)

func _fill_cell_top_hit(
		cell: Vector2i, step: float, radius: float,
		origin: Vector3, right: Vector3, forward: Vector3,
		top_hit_probe_up_override: float) -> void:
	var offset := Vector2(float(cell.x) * step * 0.5, float(cell.y) * step * 0.5)
	if offset.length() > radius:
		return
	var world_point := _world_from_offset(origin, right, forward, offset)
	var top_hit := _perception.probe_top_hit(world_point, top_hit_probe_up_override)
	if top_hit.is_empty():
		_cell_top_hit_positions.erase(cell)
		_cell_top_colliders.erase(cell)
		return
	_cell_top_hit_positions[cell] = top_hit.get("position", world_point) as Vector3
	var collider: Variant = top_hit.get("collider", null)
	if collider is Node:
		var node := collider as Node
		_cell_top_colliders[cell] = str(node.get_path()) if node.is_inside_tree() else node.name
	else:
		_cell_top_colliders.erase(cell)


func _collect_live_cell_probe_info(
		cell: Vector2i, step: float, radius: float,
		origin: Vector3, right: Vector3, forward: Vector3,
		cell_surfaces: Dictionary, cell_hit_positions: Dictionary,
		cell_probe_infos: Dictionary, use_height_clearance: bool,
		max_step_height: float, height_probe_radius: float) -> void:
	var offset := Vector2(float(cell.x) * step * 0.5, float(cell.y) * step * 0.5)
	if offset.length() > radius:
		return
	var world_point := _world_from_offset(origin, right, forward, offset)
	var surface_kind: String = str(cell_surfaces.get(cell, SurfaceClassifier.KIND_UNKNOWN))
	var surface_hit_pos: Vector3 = cell_hit_positions.get(cell, world_point) as Vector3
	var top_hit_pos: Vector3 = _cell_top_hit_positions.get(cell, surface_hit_pos) as Vector3
	var has_top_hit := _cell_top_hit_positions.has(cell)
	var top_hit_collider_name := str(_cell_top_colliders.get(cell, ""))
	var info := _collect_cell_probe_info(
			cell, world_point, origin.y,
			surface_kind, surface_hit_pos,
			top_hit_pos, has_top_hit, top_hit_collider_name,
			not use_height_clearance,
			max_step_height if use_height_clearance else NAN,
			NAN,
			height_probe_radius if use_height_clearance else NAN,
			use_height_clearance)
	if bool(info.get("height_blocked", false)):
		_cell_height_blocked[cell] = true
	cell_probe_infos[cell] = info


func _register_live_cell(
		cell: Vector2i, doubled_radius: int, step: float, radius: float,
		start_cell: Vector2i, start_needs_escape: bool,
		point_ids: Dictionary, astar: AStar2D,
		cell_probe_infos: Dictionary, debug_cells: Array[Dictionary],
		debug_hits: Array[Dictionary], use_height_clearance: bool) -> void:
	if not cell_probe_infos.has(cell):
		return
	var info: Dictionary = cell_probe_infos[cell]
	var world_point: Vector3 = info.get("world_pos", Vector3.ZERO) as Vector3
	var wall_buffer_blocked := false
	if use_height_clearance \
			and not bool(info.get("blocked", false)) \
			and _cell_has_height_neighbor(cell):
		wall_buffer_blocked = true
		info["blocked"] = true
		info["blocked_reason"] = "wall_buffer"

	if _ctx.config.debug_draw_avoidance:
		debug_cells.append(info)
		if bool(info.get("physics_blocked", false)) or bool(info.get("height_blocked", false)):
			debug_hits.append({
				"pos": info.get("physics_pos", world_point) as Vector3,
				"collider_name": str(info.get("collider", "")),
				"near_road": bool(info.get("physics_near_road", false)),
				"reason": str(info.get("blocked_reason", "")),
			})

	var physics_like_blocked := bool(info.get("physics_blocked", false)) \
			or bool(info.get("height_blocked", false)) \
			or wall_buffer_blocked
	if physics_like_blocked and cell != start_cell:
		return
	var surface_blocked := bool(info.get("surface_blocked", false))
	if surface_blocked and cell != start_cell and not start_needs_escape:
		return
	var near_road_blocked := bool(info.get("near_road_buffer", false)) \
			or bool(info.get("physics_near_road", false))
	if near_road_blocked and cell != start_cell and not start_needs_escape:
		return

	var point_id := _cell_id(cell, doubled_radius)
	point_ids[cell] = point_id
	var offset := Vector2(float(cell.x) * step * 0.5, float(cell.y) * step * 0.5)
	if offset.length() > radius:
		return
	astar.add_point(point_id, offset)


func _cell_has_height_neighbor(cell: Vector2i) -> bool:
	if _cell_height_blocked.has(cell):
		return false
	for offset in _GRID_NEIGHBORS:
		if _cell_height_blocked.has(cell + offset):
			return true
	return false


func _is_cell_within_road_buffer(cell: Vector2i, cell_surfaces: Dictionary) -> bool:
	if not _ctx.config.local_astar_avoid_road_cells:
		return false
	var buffer_cells := maxi(_ctx.config.local_astar_road_buffer_cells, 0)
	if buffer_cells <= 0:
		return false
	for offset in _get_cached_neighbor_offsets(buffer_cells):
		if offset == Vector2i.ZERO:
			continue
		if _is_surface_blocked(str(cell_surfaces.get(cell + offset, ""))):
			return true
	return false


## Returns the BFS offsets within `radius_cells`, computed once per radius and
## cached. Result is owned by this component — callers MUST NOT mutate.
func _get_cached_neighbor_offsets(radius_cells: int) -> Array[Vector2i]:
	var key := radius_cells
	if _neighbor_offsets_cache.has(key):
		return _neighbor_offsets_cache[key]
	var offsets := _neighbor_offsets_in_radius(radius_cells)
	_neighbor_offsets_cache[key] = offsets
	return offsets


static func _neighbor_offsets_in_radius(radius_cells: int) -> Array[Vector2i]:
	var offsets: Array[Vector2i] = []
	var frontier: Array[Vector2i] = [Vector2i.ZERO]
	var visited := {Vector2i.ZERO: true}
	var steps := 0
	while steps < radius_cells and not frontier.is_empty():
		var next_frontier: Array[Vector2i] = []
		for current in frontier:
			for off in _GRID_NEIGHBORS:
				var nxt := current + off
				if visited.has(nxt):
					continue
				visited[nxt] = true
				offsets.append(nxt)
				next_frontier.append(nxt)
		frontier = next_frontier
		steps += 1
	return offsets


static func _blocked_reason(physics_blocked: bool, surface_blocked: bool,
		near_road_buffer: bool, physics_near_road: bool) -> String:
	if physics_blocked and surface_blocked:
		return "physics+road"
	if physics_blocked and (near_road_buffer or physics_near_road):
		return "physics+road_buffer"
	if surface_blocked:
		return "road"
	if near_road_buffer or physics_near_road:
		return "road_buffer"
	if physics_blocked:
		return "physics"
	return ""
