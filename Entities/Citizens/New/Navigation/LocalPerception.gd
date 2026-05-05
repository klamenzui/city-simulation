class_name LocalPerception
extends RefCounted

## Layer 2 of the 4-layer navigation pipeline (Navigation.md §Local Perception).
##
## Answers: what is directly in front of / underneath / beside the citizen?
##
## Consists of two probe families:
##   1. Forward ShapeCast (intersect_shape with a small sphere) — detects
##      static walls and other citizens in the walk corridor.
##   2. Surface ray (intersect_ray, layers 1+2) — classifies the floor beneath
##      an arbitrary probe point as pedestrian / road / crosswalk / unknown.
##
## All expensive Shape3D / RayQueryParameters allocation happens once up front.

const BLOCK_KEY_BLOCKED: String = "blocked"
const BLOCK_KEY_HIT_POS: String = "hit_pos"
const BLOCK_KEY_COLLIDER: String = "collider_name"

var _ctx: NavigationContext
var _probe_shape: SphereShape3D = SphereShape3D.new()
## Set by the Controller after JumpController is built.  Perception needs it
## to run the close-range down-ray probe (the second half of the jumpable
## check).  Nullable — Perception still works without a jump system.
var _jump: JumpController = null

## Reusable physics-query objects. All probe calls reuse these instances and
## just reset `transform`/`exclude` per call. Allocating fresh
## PhysicsShapeQueryParameters3D / PhysicsRayQueryParameters3D inside
## `LocalGridPlanner.build_detour` was a measurable GC source — at ~50 cells
## × 4 probe heights per replan, every fresh allocation cost adds up.
var _shape_query: PhysicsShapeQueryParameters3D = null
var _ray_query: PhysicsRayQueryParameters3D = null
## Pre-allocated single-element exclude array — reused for every query.
## `_owner_rid_cache[0]` is filled lazily once the owner RID is valid.
var _exclude_owner: Array[RID] = []
## Pre-allocated multi-element exclude array used by `probe_surface` (which
## adds character-body RIDs as it iterates). Cleared and refilled per call.
var _exclude_buffer: Array[RID] = []
## Probe heights are recomputed lazily and cached. Invalidated when the
## relevant config knobs change. Today the config is built once at _ready;
## a runtime LOD profile would need to call `_invalidate_probe_heights()`.
var _cached_probe_heights: Array[float] = []
var _cached_probe_radius: float = -1.0


func _init(context: NavigationContext) -> void:
	_ctx = context
	_probe_shape.radius = maxf(_ctx.config.local_astar_probe_radius, 0.03)
	_shape_query = PhysicsShapeQueryParameters3D.new()
	_shape_query.shape = _probe_shape
	_shape_query.collide_with_areas = false
	_shape_query.collide_with_bodies = true
	_ray_query = PhysicsRayQueryParameters3D.new()
	_ray_query.collide_with_areas = false
	# Height scans can start inside thin/open concave props (park walls,
	# hydrants). Returning the exit hit is better than silently seeing through.
	_ray_query.hit_from_inside = true


## Lazy probe-heights cache — computed once, returned by reference.
func _get_probe_heights() -> Array[float]:
	if _cached_probe_heights.is_empty():
		_cached_probe_heights = _ctx.config.get_probe_heights()
	return _cached_probe_heights


## Reuses the cached single-RID exclude array. Owner RID may not be valid
## at construction time, so we set it lazily.
func _get_exclude_owner() -> Array[RID]:
	if _exclude_owner.is_empty():
		_exclude_owner.append(_ctx.get_owner_rid())
	else:
		_exclude_owner[0] = _ctx.get_owner_rid()
	return _exclude_owner


## Updates the shape-query members in-place. Returns the cached instance.
func _prepare_shape_query(transform: Transform3D, mask: int) -> PhysicsShapeQueryParameters3D:
	# Probe radius can change if config is rebuilt, keep shape in sync.
	var current_radius := maxf(_ctx.config.local_astar_probe_radius, 0.03)
	if not is_equal_approx(current_radius, _cached_probe_radius):
		_probe_shape.radius = current_radius
		_cached_probe_radius = current_radius
	_shape_query.transform = transform
	_shape_query.collision_mask = mask
	_shape_query.exclude = _get_exclude_owner()
	return _shape_query


func set_jump_controller(jump: JumpController) -> void:
	_jump = jump


## Front-ahead probe at half local-A* radius.  Returns true when a physics
## obstacle blocks the walk corridor at any of the configured probe heights
## (waist/chest) — unless the obstacle is low enough for the jump system.
##
## `flat_direction` must already be planar (y=0) and normalized.
func is_path_ahead_blocked(flat_direction: Vector3, jump_low_obstacles_enabled: bool) -> bool:
	if not _ctx.is_ready_for_physics():
		return false
	if flat_direction.length_squared() <= 0.0001:
		return false

	var owner_pos := _ctx.get_owner_position()
	var probe_base := owner_pos + flat_direction * (_ctx.config.local_astar_radius * 0.5)
	var space := _ctx.get_space_state()
	var mask := _ctx.get_owner_collision_mask()

	for probe_y_offset in _get_probe_heights():
		var probe_pos := probe_base
		probe_pos.y = owner_pos.y + probe_y_offset
		var query := _prepare_shape_query(Transform3D(Basis.IDENTITY, probe_pos), mask)

		for hit in space.intersect_shape(query, 4):
			if SurfaceClassifier.is_walkable_probe_collider(hit.get("collider", null)):
				continue

			# Skip curbs the jump system will handle.  Only applies to low probe
			# heights (waist) — chest hits are never jumpable.
			if probe_y_offset < 0.5 \
					and jump_low_obstacles_enabled \
					and is_obstacle_below_jump_height(flat_direction):
				_ctx.logger.trace("PERCEPTION", "PATH_AHEAD_SKIP_JUMPABLE", {
					"collider": _collider_name(hit.get("collider", null)),
					"dir": flat_direction,
				})
				continue

			_ctx.logger.debug("PERCEPTION", "PATH_AHEAD_BLOCKED", {
				"collider": _collider_name(hit.get("collider", null)),
				"probe_y": probe_y_offset,
				"pos": owner_pos,
				"dir": flat_direction,
			})
			return true
	return false


## Combines two probes to decide whether the obstacle directly ahead is short
## enough to jump over.  The two-probe scheme guards against the FALSE JUMPABLE
## bug where a foundation stoop in front of a tall building wall fools a
## single far probe.
##
##   Probe 1 (near, ~0.45 m): JumpController's down-ray.  If it sees an
##     obstacle ABOVE max jump height in the near corridor, NOT jumpable —
##     even if the far sphere thinks it is.
##   Probe 2 (far, half-A*-radius): sphere at (max_jump_height + 6 cm).
##     Clear here means the obstacle the ankle sphere hit at the same xz
##     is at most max_h tall.
func is_obstacle_below_jump_height(flat_direction: Vector3) -> bool:
	if not _ctx.is_ready_for_physics():
		return false
	var cfg := _ctx.config
	var max_h := maxf(cfg.max_jump_obstacle_height, 0.0)
	var owner_pos := _ctx.get_owner_position()

	# Probe 1: near-range down-ray via JumpController.
	if _jump != null and _jump.near_ray_blocks_above_height(flat_direction):
		return false  # tall wall in near corridor — must reroute

	# Probe 2: far-range sphere at jump-height + margin.
	var probe_pos := owner_pos + flat_direction * (cfg.local_astar_radius * 0.5)
	probe_pos.y = owner_pos.y + max_h + 0.06

	var query := _prepare_shape_query(
			Transform3D(Basis.IDENTITY, probe_pos),
			_ctx.get_owner_collision_mask())

	for hit in _ctx.get_space_state().intersect_shape(query, 4):
		if not SurfaceClassifier.is_walkable_probe_collider(hit.get("collider", null)):
			return false
	return true


## Full grid-style physics probe at `point`. Returns:
##   { blocked=true, hit_pos=Vector3, collider_name=String } or
##   { blocked=false, hit_pos=point, collider_name="" }
##
## `base_y_override` lets the caller pin the probe-height base to the cell's
## own ground level instead of the live citizen position. Default NAN means
## "use owner_pos.y", which is correct during normal avoidance runs (the
## citizen is always near the cells being scanned). The Coord-Picker's
## standalone scan_at uses the override so it can scan at any point on the
## map regardless of where the citizen currently stands.
##
## `probe_radius_override` (NAN = config) lets debug tools shrink the sphere
## to expose how aggressively the live config reaches into adjacent meshes.
func get_probe_block_info(point: Vector3, base_y_override: float = NAN,
		probe_radius_override: float = NAN) -> Dictionary:
	if not _ctx.is_ready_for_physics():
		return {BLOCK_KEY_BLOCKED: true, BLOCK_KEY_HIT_POS: point, BLOCK_KEY_COLLIDER: "no_world"}

	var base_y: float = base_y_override
	if is_nan(base_y):
		base_y = _ctx.get_owner_position().y
	var mask := _ctx.get_owner_collision_mask()
	var space := _ctx.get_space_state()
	# Optional radius override for debug tools.
	var saved_radius: float = -1.0
	if not is_nan(probe_radius_override):
		saved_radius = _probe_shape.radius
		_probe_shape.radius = maxf(probe_radius_override, 0.03)
		_cached_probe_radius = -1.0  # force re-sync next non-override call

	for probe_y_offset in _get_probe_heights():
		var probe_position := point
		probe_position.y = base_y + probe_y_offset
		var query := _prepare_shape_query(
				Transform3D(Basis.IDENTITY, probe_position), mask)

		for hit in space.intersect_shape(query, 8):
			var collider: Variant = hit.get("collider", null)
			var walkable := SurfaceClassifier.is_walkable_probe_collider(collider)
			_log_probe_hit("physics", probe_position, probe_y_offset, collider, walkable)
			if walkable:
				continue
			# Restore radius before returning.
			if saved_radius > 0.0:
				_probe_shape.radius = saved_radius
			return {
				BLOCK_KEY_BLOCKED: true,
				BLOCK_KEY_HIT_POS: _get_probe_hit_debug_position(collider, probe_position),
				BLOCK_KEY_COLLIDER: _collider_path(collider),
			}
	if saved_radius > 0.0:
		_probe_shape.radius = saved_radius
	return {BLOCK_KEY_BLOCKED: false, BLOCK_KEY_HIT_POS: point, BLOCK_KEY_COLLIDER: ""}


## Convenience: returns only the surface kind string for `point`.
func get_surface_kind(point: Vector3) -> String:
	var hit := probe_surface(point)
	return surface_kind_from_hit(hit, point)


## Single-hit top-most down-ray at `point`. Returns the FIRST collider the
## ray meets coming down from `local_astar_surface_probe_up` above (or a
## caller-provided override). Used by the user's "height-based block"
## strategy: if the top-most hit Y is well above the citizen's Y, there's an
## obstacle (post, hydrant, wall, awning). If hit is at the citizen's ground
## level, the cell is walkable.
##
## The ray excludes the owner CharacterBody3D so the citizen does not block
## its own scan. The collision mask defaults to the citizen's full mask so
## obstacles on any layer (props like lampposts, hydrants, signs) are
## detected — not just the narrow surface mask used for floor classification.
func probe_top_hit(point: Vector3, probe_up_override: float = NAN) -> Dictionary:
	if not _ctx.is_ready_for_physics():
		return {}

	var cfg := _ctx.config
	var probe_up := probe_up_override
	if is_nan(probe_up):
		probe_up = cfg.local_astar_surface_probe_up
	var from := point + Vector3.UP * maxf(probe_up, 0.2)
	var to := point + Vector3.DOWN * maxf(cfg.local_astar_surface_probe_down, 0.2)
	_exclude_buffer.clear()
	_exclude_buffer.append(_ctx.get_owner_rid())
	var space := _ctx.get_space_state()
	_ray_query.from = from
	_ray_query.to = to
	# Use full owner mask so lampposts / hydrants / fences (often on a "props"
	# layer outside `local_astar_surface_collision_mask` = layer 1+2) are seen.
	_ray_query.collision_mask = _ctx.get_owner_collision_mask()
	_ray_query.exclude = _exclude_buffer
	# Walk past character bodies (other citizens) but stop on the first
	# static hit. That static hit's Y is the obstacle/floor height.
	for _attempt in range(maxi(cfg.local_astar_surface_probe_max_hits, 1)):
		var hit: Dictionary = space.intersect_ray(_ray_query)
		if hit.is_empty():
			return {}
		var collider: Variant = hit.get("collider", null)
		if collider is CharacterBody3D and hit.has("rid"):
			_exclude_buffer.append(hit["rid"])
			continue
		_log_probe_hit("top_hit", point, 0.0, collider, true, hit)
		return hit
	return {}


## Single clearance sphere placed just ABOVE `max_step_height`.
##
## Why a second probe at all? Some imported props/walls use open or side-only
## concave collision. A top-down ray then falls through and only sees the
## ground below. This sphere catches those vertical blockers while staying
## high enough above flat road/crosswalk surfaces to avoid the legacy
## "everything near the curb turns red" problem.
func get_height_clearance_block_info(point: Vector3, base_y: float,
		max_step_height: float, probe_radius_override: float = NAN) -> Dictionary:
	if not _ctx.is_ready_for_physics():
		return {BLOCK_KEY_BLOCKED: true, BLOCK_KEY_HIT_POS: point, BLOCK_KEY_COLLIDER: "no_world"}
	if max_step_height <= 0.0:
		return {BLOCK_KEY_BLOCKED: false, BLOCK_KEY_HIT_POS: point, BLOCK_KEY_COLLIDER: ""}

	var radius := maxf(
			probe_radius_override if not is_nan(probe_radius_override) \
			else _ctx.config.local_astar_probe_radius,
			0.03)
	var saved_radius: float = -1.0
	if not is_nan(probe_radius_override):
		saved_radius = _probe_shape.radius
		_probe_shape.radius = radius
		_cached_probe_radius = -1.0  # force re-sync next non-override call

	var probe_position := point
	probe_position.y = base_y + max_step_height + radius + 0.01
	var query := _prepare_shape_query(
			Transform3D(Basis.IDENTITY, probe_position),
			_ctx.get_owner_collision_mask())

	for hit in _ctx.get_space_state().intersect_shape(query, 8):
		var collider: Variant = hit.get("collider", null)
		var walkable := SurfaceClassifier.is_walkable_probe_collider(collider)
		_log_probe_hit("clearance", probe_position, probe_position.y - base_y, collider, walkable)
		if walkable:
			continue
		if saved_radius > 0.0:
			_probe_shape.radius = saved_radius
		return {
			BLOCK_KEY_BLOCKED: true,
			BLOCK_KEY_HIT_POS: _get_probe_hit_debug_position(collider, probe_position),
			BLOCK_KEY_COLLIDER: _collider_path(collider),
		}

	if saved_radius > 0.0:
		_probe_shape.radius = saved_radius
	return {BLOCK_KEY_BLOCKED: false, BLOCK_KEY_HIT_POS: point, BLOCK_KEY_COLLIDER: ""}


## Raw surface ray (layers 1+2) at `point`. Walks up to `attempts` hits and
## **picks the highest-priority surface kind** (pedestrian > crosswalk > unknown
## > road) — needed because the map has overlapping colliders (pedzone meshes
## sharing layer with road_straight bodies). Returning the first hit unmodified
## would mis-classify pedzone positions as road whenever the road collider
## happens to be hit first.
func probe_surface(point: Vector3) -> Dictionary:
	if not _ctx.is_ready_for_physics():
		return {}

	var cfg := _ctx.config
	var from := point + Vector3.UP * maxf(cfg.local_astar_surface_probe_up, 0.2)
	var to := point + Vector3.DOWN * maxf(cfg.local_astar_surface_probe_down, 0.2)
	# Reuse the buffer; clear + seed with owner RID. Hits-as-citizens append.
	_exclude_buffer.clear()
	_exclude_buffer.append(_ctx.get_owner_rid())
	var attempts := maxi(cfg.local_astar_surface_probe_max_hits, 1)
	var space := _ctx.get_space_state()

	# Configure the cached ray query once; only `exclude` mutates per attempt.
	_ray_query.from = from
	_ray_query.to = to
	_ray_query.collision_mask = cfg.local_astar_surface_collision_mask

	var best_hit: Dictionary = {}
	var best_priority: int = -1

	for _attempt in range(attempts):
		_ray_query.exclude = _exclude_buffer

		var hit := space.intersect_ray(_ray_query)
		if hit.is_empty():
			break

		var collider: Variant = hit.get("collider", null)
		if collider is CharacterBody3D:
			if not hit.has("rid"):
				break
			_exclude_buffer.append(hit["rid"])
			continue

		var priority := _surface_kind_priority(collider)
		if priority > best_priority:
			best_priority = priority
			best_hit = hit
			# Pedestrian-grade hit found — stop early.
			if priority >= 3:
				_log_probe_hit("surface", point, 0.0, collider, true, hit)
				return best_hit

		# Continue searching: maybe a pedestrian-grade collider sits below this
		# road/unknown one (rare but happens with stacked map geometry). We
		# still need a way to advance the ray; exclude the current hit and
		# try again.
		if not hit.has("rid"):
			break
		_exclude_buffer.append(hit["rid"])

	if not best_hit.is_empty():
		_log_probe_hit("surface", point, 0.0,
				best_hit.get("collider", null), true, best_hit)
	return best_hit


## Maps a collider to a surface-classification priority. Higher = preferred.
##   3 = pedestrian (walkable_surface group, /only_people_nav/ path, parks)
##   2 = crosswalk
##   1 = road       ← important: must outrank unknown, otherwise the
##                    generic World-Terrain (StaticBody3D under World) acts
##                    as a "walkable veil" that hides actual road geometry.
##   0 = unknown
##
## Tie-breaking rationale: when a down-ray hits both a Road mesh AND the
## generic world terrain right below, the citizen is physically standing on
## the Road — that's the "no-go" answer we want, even if the terrain is
## present. Pedestrian/Crosswalk meshes still win because they sit ABOVE
## the road and represent the surface the citizen actually stands on.
static func _surface_kind_priority(collider: Variant) -> int:
	if not (collider is Node):
		return 0
	var kind := SurfaceClassifier.classify_node(collider as Node)
	match kind:
		SurfaceClassifier.KIND_PEDESTRIAN: return 3
		SurfaceClassifier.KIND_CROSSWALK: return 2
		SurfaceClassifier.KIND_ROAD: return 1
		SurfaceClassifier.KIND_UNKNOWN: return 0
	return 0


## Applies the pedzone-over-road fixup and pedestrian-graph fallback after a
## raw probe.  Extracted so the grid builder can reuse an already-fired hit.
func surface_kind_from_hit(hit: Dictionary, point: Vector3) -> String:
	var kind := SurfaceClassifier.classify_hit(hit)
	if kind == SurfaceClassifier.KIND_ROAD and not hit.is_empty():
		# Thin pedzone meshes (~2–4 cm above road) sit on a collision layer the
		# probe skips.  If the hit Y is >2.5 cm below the query point, the ray
		# passed through a pedzone — treat as unknown so surface-escape doesn't
		# fire while standing on the zone.
		var hit_y: float = (hit.get("position", point) as Vector3).y
		if point.y - hit_y > 0.025:
			kind = SurfaceClassifier.KIND_UNKNOWN
	if kind != "" and kind != SurfaceClassifier.KIND_UNKNOWN:
		return kind

	var world := _ctx.get_world_node()
	if world != null and world.has_method("get_pedestrian_path_point_kind"):
		var graph_kind := str(world.get_pedestrian_path_point_kind(point))
		if not graph_kind.is_empty():
			return graph_kind
	return kind


## Samples 5 points around `point` (center + 4 cardinals at `margin` m) and
## returns true if any samples a road surface.
func is_point_near_road(point: Vector3, margin: float) -> bool:
	if margin <= 0.0:
		return false
	var samples: Array[Vector3] = [
		Vector3.ZERO,
		Vector3.RIGHT * margin,
		Vector3.LEFT * margin,
		Vector3.FORWARD * margin,
		Vector3.BACK * margin,
	]
	for sample in samples:
		if get_surface_kind(point + sample) == SurfaceClassifier.KIND_ROAD:
			return true
	return false


## True when the citizen is walking close to — but not yet on — a road edge.
## Samples lateral `road_proximity_margin` + one forward sample.
func is_too_close_to_road(move_dir: Vector3) -> bool:
	var cfg := _ctx.config
	if not cfg.local_astar_avoid_road_cells:
		return false
	if cfg.local_astar_road_proximity_margin <= 0.0:
		return false
	if move_dir.length_squared() <= 0.0001:
		return false

	var right := _planar_right(move_dir)
	var margin := maxf(cfg.local_astar_road_proximity_margin, 0.1)
	var owner_pos := _ctx.get_owner_position()
	for side in [right * margin, -right * margin]:
		if get_surface_kind(owner_pos + side) == SurfaceClassifier.KIND_ROAD:
			return true
	var forward_check := maxf(cfg.local_astar_forward_road_check_distance, 0.0)
	if forward_check > 0.0:
		var forward_pt := owner_pos + move_dir.normalized() * forward_check
		if get_surface_kind(forward_pt) == SurfaceClassifier.KIND_ROAD:
			return true
	return false


## Hex-grid right vector perpendicular to `forward` on the XZ plane.
static func _planar_right(forward: Vector3) -> Vector3:
	var planar := forward
	planar.y = 0.0
	if planar.length_squared() <= 0.0001:
		return Vector3.RIGHT
	return planar.normalized().cross(Vector3.UP).normalized()


func _collider_name(collider: Variant) -> String:
	if collider is Node:
		return (collider as Node).name
	return "?"


func _collider_path(collider: Variant) -> String:
	if collider is Node:
		var n := collider as Node
		if n.is_inside_tree():
			return str(n.get_path())
		return n.name
	return ""


func _get_probe_hit_debug_position(collider: Variant, fallback: Vector3) -> Vector3:
	if collider is CollisionObject3D:
		return (collider as CollisionObject3D).global_position
	if collider is Node3D:
		return (collider as Node3D).global_position
	return fallback


## Deduplicated probe-hit log (one line per unique probe_kind + collider path,
## scoped to the current rebuild).  Controlled by config.debug_log_probe_hits.
func _log_probe_hit(probe_kind: String, probe_pos: Vector3, probe_height: float,
		collider: Variant, walkable: bool, surface_hit: Dictionary = {}) -> void:
	if not _ctx.config.debug_log_probe_hits:
		return
	if not (collider is Node):
		return
	var node := collider as Node
	var path_key = str(node.get_path()) if node.is_inside_tree() else node.name
	if not _ctx.logger.probe_hit_seen(probe_kind + "|" + path_key):
		return

	var hit_y := probe_pos.y
	var normal := Vector3.ZERO
	if not surface_hit.is_empty():
		hit_y = (surface_hit.get("position", probe_pos) as Vector3).y
		normal = surface_hit.get("normal", Vector3.ZERO) as Vector3

	_ctx.logger.trace("PERCEPTION", "PROBE_HIT", {
		"probe": probe_kind,
		"probe_pos": probe_pos,
		"probe_h": probe_height,
		"hit_y": hit_y,
		"n": normal,
		"walkable": walkable,
		"chain": SurfaceClassifier.fmt_collider_chain(node),
	})
