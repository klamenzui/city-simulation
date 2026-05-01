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
	# Reuse member buffers — clear keeps backing capacity, only contents reset.
	_point_ids.clear()
	_cell_surfaces.clear()
	_cell_hit_positions.clear()
	_candidates.clear()
	_astar.clear()
	var point_ids: Dictionary = _point_ids
	var cell_surfaces: Dictionary = _cell_surfaces
	var cell_hit_positions: Dictionary = _cell_hit_positions
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

	# Pass 2: physics probes + register navigable cells.
	for z in range(-cell_radius, cell_radius + 1):
		for x in range(-cell_radius, cell_radius + 1):
			_probe_and_register_cell(Vector2i(x * 2, z * 2), doubled_radius, step, radius,
					origin, right, forward, start_cell, start_needs_escape,
					point_ids, cell_surfaces, cell_hit_positions,
					astar, debug_cells, debug_hits)
		if z < cell_radius:
			for x in range(-cell_radius, cell_radius):
				_probe_and_register_cell(Vector2i(x * 2 + 1, z * 2 + 1), doubled_radius, step, radius,
						origin, right, forward, start_cell, start_needs_escape,
						point_ids, cell_surfaces, cell_hit_positions,
						astar, debug_cells, debug_hits)

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
## Returns a Dictionary:
##   { debug_cells, debug_hits, origin, forward, step, cell_size, cell_radius }
func scan_at(origin: Vector3, forward: Vector3) -> Dictionary:
	var planar_forward := forward
	planar_forward.y = 0.0
	if planar_forward.length_squared() <= 0.0001:
		planar_forward = Vector3.FORWARD
	planar_forward = planar_forward.normalized()

	var cfg := _ctx.config
	var right := LocalPerception._planar_right(planar_forward)
	var cell_size := maxf(cfg.local_astar_cell_size, 0.08)
	var radius := maxf(cfg.local_astar_radius, cell_size * 2.0)
	var step := cell_size / float(maxi(cfg.local_astar_grid_subdivisions, 1))
	var cell_radius := int(ceil(radius / step))
	var doubled_radius := cell_radius * 2

	# Reuse the same member buffers; build_detour always clears at start.
	_point_ids.clear()
	_cell_surfaces.clear()
	_cell_hit_positions.clear()
	_candidates.clear()
	_astar.clear()

	var debug_cells: Array[Dictionary] = []
	var debug_hits: Array[Dictionary] = []
	var start_cell := Vector2i.ZERO

	# Pass 1: surfaces
	for z in range(-cell_radius, cell_radius + 1):
		for x in range(-cell_radius, cell_radius + 1):
			_fill_cell_surface(Vector2i(x * 2, z * 2), step, radius,
					origin, right, planar_forward, _cell_surfaces, _cell_hit_positions)
		if z < cell_radius:
			for x in range(-cell_radius, cell_radius):
				_fill_cell_surface(Vector2i(x * 2 + 1, z * 2 + 1), step, radius,
						origin, right, planar_forward, _cell_surfaces, _cell_hit_positions)

	# Pass 2: physics + register (force debug-output via local override).
	var force_debug := true
	for z in range(-cell_radius, cell_radius + 1):
		for x in range(-cell_radius, cell_radius + 1):
			_scan_cell_for_debug(Vector2i(x * 2, z * 2), doubled_radius, step, radius,
					origin, right, planar_forward, start_cell, false, debug_cells, debug_hits)
		if z < cell_radius:
			for x in range(-cell_radius, cell_radius):
				_scan_cell_for_debug(Vector2i(x * 2 + 1, z * 2 + 1), doubled_radius, step, radius,
						origin, right, planar_forward, start_cell, false, debug_cells, debug_hits)

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


## Like `_probe_and_register_cell`, but always emits a debug entry
## (the original is gated by `debug_draw_avoidance`). Does not register
## the cell with AStar — debug-only.
func _scan_cell_for_debug(
		cell: Vector2i, doubled_radius: int, step: float, radius: float,
		origin: Vector3, right: Vector3, forward: Vector3,
		start_cell: Vector2i, start_needs_escape: bool,
		debug_cells: Array[Dictionary], debug_hits: Array[Dictionary]) -> void:
	var offset := Vector2(float(cell.x) * step * 0.5, float(cell.y) * step * 0.5)
	if offset.length() > radius:
		return
	var world_point := _world_from_offset(origin, right, forward, offset)
	var surface_kind: String = str(_cell_surfaces.get(cell, SurfaceClassifier.KIND_UNKNOWN))
	var physics_info := _perception.get_probe_block_info(world_point)
	var physics_blocked := bool(physics_info.get(LocalPerception.BLOCK_KEY_BLOCKED, false))
	var physics_hit_pos: Vector3 = physics_info.get(LocalPerception.BLOCK_KEY_HIT_POS, world_point) as Vector3
	var physics_collider_name := str(physics_info.get(LocalPerception.BLOCK_KEY_COLLIDER, ""))
	var surface_blocked := _is_surface_blocked(surface_kind)
	var near_road_buffer := _is_cell_within_road_buffer(cell, _cell_surfaces)
	var physics_near_road := false
	if physics_blocked and _ctx.config.local_astar_physics_near_road_margin > 0.0:
		physics_near_road = _perception.is_point_near_road(physics_hit_pos,
				_ctx.config.local_astar_physics_near_road_margin)

	var surface_hit_pos: Vector3 = _cell_hit_positions.get(cell, world_point) as Vector3
	var blocked := physics_blocked or surface_blocked or near_road_buffer or physics_near_road
	var reason := _blocked_reason(physics_blocked, surface_blocked, near_road_buffer, physics_near_road)

	debug_cells.append({
		"cell": cell,
		"world_pos": world_point,
		"surface_pos": surface_hit_pos,
		"physics_pos": physics_hit_pos,
		"blocked": blocked,
		"blocked_reason": reason,
		"surface": surface_kind,
		"collider": physics_collider_name,
	})
	if physics_blocked:
		debug_hits.append({
			"pos": physics_hit_pos,
			"collider_name": physics_collider_name,
			"near_road": physics_near_road,
		})


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
		cell_surfaces: Dictionary, cell_hit_positions: Dictionary) -> void:
	var offset := Vector2(float(cell.x) * step * 0.5, float(cell.y) * step * 0.5)
	if offset.length() > radius:
		return
	var world_point := _world_from_offset(origin, right, forward, offset)
	var surface_hit := _perception.probe_surface(world_point)
	cell_surfaces[cell] = _perception.surface_kind_from_hit(surface_hit, world_point)
	cell_hit_positions[cell] = (surface_hit.get("position", world_point) as Vector3) \
			if not surface_hit.is_empty() else world_point


func _probe_and_register_cell(
		cell: Vector2i, doubled_radius: int, step: float, radius: float,
		origin: Vector3, right: Vector3, forward: Vector3,
		start_cell: Vector2i, start_needs_escape: bool,
		point_ids: Dictionary, cell_surfaces: Dictionary,
		cell_hit_positions: Dictionary, astar: AStar2D,
		debug_cells: Array[Dictionary], debug_hits: Array[Dictionary]) -> void:
	var offset := Vector2(float(cell.x) * step * 0.5, float(cell.y) * step * 0.5)
	if offset.length() > radius:
		return
	var world_point := _world_from_offset(origin, right, forward, offset)
	var surface_kind: String = str(cell_surfaces.get(cell, SurfaceClassifier.KIND_UNKNOWN))
	var physics_info := _perception.get_probe_block_info(world_point)
	var physics_blocked := bool(physics_info.get(LocalPerception.BLOCK_KEY_BLOCKED, false))
	var physics_hit_pos: Vector3 = physics_info.get(LocalPerception.BLOCK_KEY_HIT_POS, world_point) as Vector3
	var physics_collider_name := str(physics_info.get(LocalPerception.BLOCK_KEY_COLLIDER, ""))
	var surface_blocked := _is_surface_blocked(surface_kind)
	var near_road_buffer := _is_cell_within_road_buffer(cell, cell_surfaces)
	var physics_near_road := false
	if physics_blocked and _ctx.config.local_astar_physics_near_road_margin > 0.0:
		physics_near_road = _perception.is_point_near_road(physics_hit_pos,
				_ctx.config.local_astar_physics_near_road_margin)

	if _ctx.config.debug_draw_avoidance:
		var surface_hit_pos: Vector3 = cell_hit_positions.get(cell, world_point) as Vector3
		debug_cells.append({
			"surface_pos": surface_hit_pos,
			"physics_pos": physics_hit_pos,
			"blocked": physics_blocked or surface_blocked or near_road_buffer or physics_near_road,
			"blocked_reason": _blocked_reason(physics_blocked, surface_blocked, near_road_buffer, physics_near_road),
			"surface": surface_kind,
		})
		if physics_blocked:
			debug_hits.append({
				"pos": physics_hit_pos,
				"collider_name": physics_collider_name,
				"near_road": physics_near_road,
			})

	if physics_blocked and cell != start_cell:
		return
	if surface_blocked and cell != start_cell and not start_needs_escape:
		return
	if (near_road_buffer or physics_near_road) and cell != start_cell and not start_needs_escape:
		return

	var point_id := _cell_id(cell, doubled_radius)
	point_ids[cell] = point_id
	astar.add_point(point_id, offset)


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
