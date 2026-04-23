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


func _init(context: NavigationContext) -> void:
	_ctx = context
	_probe_shape.radius = maxf(_ctx.config.local_astar_probe_radius, 0.03)


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

	_probe_shape.radius = maxf(_ctx.config.local_astar_probe_radius, 0.03)
	var owner_pos := _ctx.get_owner_position()
	var probe_base := owner_pos + flat_direction * (_ctx.config.local_astar_radius * 0.5)
	var space := _ctx.get_space_state()

	for probe_y_offset in _ctx.config.get_probe_heights():
		var probe_pos := probe_base
		probe_pos.y = owner_pos.y + probe_y_offset

		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = _probe_shape
		query.transform = Transform3D(Basis.IDENTITY, probe_pos)
		query.collision_mask = _ctx.get_owner_collision_mask()
		query.collide_with_areas = false
		query.collide_with_bodies = true
		query.exclude = [_ctx.get_owner_rid()]

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

	_probe_shape.radius = maxf(cfg.local_astar_probe_radius, 0.03)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _probe_shape
	query.transform = Transform3D(Basis.IDENTITY, probe_pos)
	query.collision_mask = _ctx.get_owner_collision_mask()
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [_ctx.get_owner_rid()]

	for hit in _ctx.get_space_state().intersect_shape(query, 4):
		if not SurfaceClassifier.is_walkable_probe_collider(hit.get("collider", null)):
			return false
	return true


## Full grid-style physics probe at `point`. Returns:
##   { blocked=true, hit_pos=Vector3, collider_name=String } or
##   { blocked=false, hit_pos=point, collider_name="" }
func get_probe_block_info(point: Vector3) -> Dictionary:
	if not _ctx.is_ready_for_physics():
		return {BLOCK_KEY_BLOCKED: true, BLOCK_KEY_HIT_POS: point, BLOCK_KEY_COLLIDER: "no_world"}

	var owner_pos := _ctx.get_owner_position()
	var mask := _ctx.get_owner_collision_mask()
	var space := _ctx.get_space_state()

	_probe_shape.radius = maxf(_ctx.config.local_astar_probe_radius, 0.03)

	for probe_y_offset in _ctx.config.get_probe_heights():
		var probe_position := point
		probe_position.y = owner_pos.y + probe_y_offset

		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = _probe_shape
		query.transform = Transform3D(Basis.IDENTITY, probe_position)
		query.collision_mask = mask
		query.collide_with_areas = false
		query.collide_with_bodies = true
		query.exclude = [_ctx.get_owner_rid()]

		for hit in space.intersect_shape(query, 8):
			var collider: Variant = hit.get("collider", null)
			var walkable := SurfaceClassifier.is_walkable_probe_collider(collider)
			_log_probe_hit("physics", probe_position, probe_y_offset, collider, walkable)
			if walkable:
				continue
			return {
				BLOCK_KEY_BLOCKED: true,
				BLOCK_KEY_HIT_POS: _get_probe_hit_debug_position(collider, probe_position),
				BLOCK_KEY_COLLIDER: _collider_path(collider),
			}
	return {BLOCK_KEY_BLOCKED: false, BLOCK_KEY_HIT_POS: point, BLOCK_KEY_COLLIDER: ""}


## Convenience: returns only the surface kind string for `point`.
func get_surface_kind(point: Vector3) -> String:
	var hit := probe_surface(point)
	return surface_kind_from_hit(hit, point)


## Raw surface ray (layers 1+2) at `point`. Returns the first non-citizen hit.
func probe_surface(point: Vector3) -> Dictionary:
	if not _ctx.is_ready_for_physics():
		return {}

	var cfg := _ctx.config
	var from := point + Vector3.UP * maxf(cfg.local_astar_surface_probe_up, 0.2)
	var to := point + Vector3.DOWN * maxf(cfg.local_astar_surface_probe_down, 0.2)
	var exclude: Array[RID] = [_ctx.get_owner_rid()]
	var attempts := maxi(cfg.local_astar_surface_probe_max_hits, 1)
	var space := _ctx.get_space_state()

	for _attempt in range(attempts):
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.collision_mask = cfg.local_astar_surface_collision_mask
		query.collide_with_areas = false
		query.exclude = exclude

		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return {}

		var collider: Variant = hit.get("collider", null)
		if collider is CharacterBody3D:
			if not hit.has("rid"):
				return {}
			exclude.append(hit["rid"])
			continue
		_log_probe_hit("surface", point, 0.0, collider, true, hit)
		return hit

	return {}


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
