extends CharacterBody3D

@export var move_speed: float = 0.5
@export var waypoint_reach_distance: float = 0.35
@export var final_waypoint_reach_distance: float = 0.18
@export var waypoint_pass_distance: float = 0.55
@export var corner_blend_distance: float = 0.8
@export var corner_blend_strength: float = 0.45
@export var click_ray_distance: float = 1000.0
@export var ignore_ui_clicks: bool = true
@export_flags_3d_physics var click_collision_mask: int = 0xFFFFFFFF

@export_group("Local Avoidance")
## How often (seconds) the forward probe runs to detect blocking obstacles.
@export var obstacle_check_interval: float = 0.08
## Speed multiplier applied while the citizen follows a local A* detour path.
@export var avoidance_slowdown_factor: float = 0.65
@export var steering_smoothing: float = 5.0
@export var debug_draw_avoidance: bool = true

@export_group("Local AStar Avoidance")
@export var use_local_astar_avoidance: bool = true
@export var local_astar_radius: float = 1.2
@export var local_astar_cell_size: float = 0.24
## Subdivisions per cell: 1 = original grid, 2 = adds midpoints between each pair
## (step = cell_size / subdivisions). Higher values find narrow gaps but cost more probes.
@export var local_astar_grid_subdivisions: int = 2
@export var local_astar_probe_radius: float = 0.16
@export var local_astar_replan_interval: float = 0.18
@export var local_astar_goal_reach_distance: float = 0.12
@export var local_astar_front_row_tolerance: float = 0.24
@export var local_astar_prefer_right_when_left_open: bool = true
@export var local_astar_avoid_road_cells: bool = true
@export_flags_3d_physics var local_astar_surface_collision_mask: int = 3
@export var local_astar_surface_probe_up: float = 1.4
@export var local_astar_surface_probe_down: float = 2.2
@export var local_astar_surface_probe_max_hits: int = 8

@export_group("Low Obstacle Jump")
@export var jump_low_obstacles: bool = true
@export_node_path("RayCast3D") var obstacle_down_ray_path: NodePath
@export var max_jump_obstacle_height: float = 0.14
@export var min_jump_obstacle_height: float = 0.005
@export var jump_probe_distance: float = 0.45
@export var jump_velocity: float = 1.8
@export var jump_cooldown: float = 0.35

var global_path: PackedVector3Array = PackedVector3Array()
var path_index: int = 0
var target_position: Vector3 = Vector3.ZERO
var _is_travelling: bool = false

var _gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
var _obstacle_down_ray: RayCast3D = null
var _obstacle_check_timer: float = 0.0
var _jump_cooldown_timer: float = 0.0
var _cached_avoidance_blocked: bool = false
var _smoothed_move_direction: Vector3 = Vector3.ZERO
var _local_avoidance_path: PackedVector3Array = PackedVector3Array()
var _local_avoidance_path_index: int = 0
var _local_astar_replan_timer: float = 0.0
var _local_astar_follow_global_on_fail: bool = false
var _local_astar_probe_shape: SphereShape3D = SphereShape3D.new()
var _cached_world_node: Node = null
var _debug_avoidance_status: String = "idle"
var _debug_avoidance_mesh: ImmediateMesh = ImmediateMesh.new()
var _debug_avoidance_visual: MeshInstance3D = null
var _debug_avoidance_material: StandardMaterial3D = null
var _debug_avoidance_label: Label3D = null
var _debug_jump_status: String = "-"
var _debug_local_astar_cells: Array[Dictionary] = []
var _debug_local_astar_status: String = "-"
var _debug_local_astar_goal: Vector3 = Vector3.ZERO
var _debug_local_astar_has_goal: bool = false

@export_group("Stuck Recovery")
## How often (seconds) to check whether the citizen has made progress.
@export var stuck_detection_interval: float = 1.5
## Minimum planar distance that counts as "making progress" per check interval.
@export var stuck_detection_min_distance: float = 0.25
## How many replan attempts before giving up and emitting stuck.
@export var stuck_max_recovery_attempts: int = 3

## Emitted when the citizen reaches its target normally.
signal target_reached()
## Emitted when all replan recovery attempts are exhausted.
signal stuck()

var _stuck_check_timer: float = 0.0
var _stuck_last_pos: Vector3 = Vector3.ZERO
var _stuck_recovery_attempts: int = 0
## Grace window (seconds) after leaving the floor during which jumps are still allowed.
## Prevents the 1-2 frame floor-gap at step transitions from blocking the jump.
var _coyote_time: float = 0.0
## Grace period (seconds) during which surface-escape avoidance is suppressed after
## a stuck-recovery replan. Prevents the citizen from immediately re-entering a
## surface-escape loop on the same road section it just replanned from.
var _surface_escape_cooldown: float = 0.0

@export_group("Logging")
## Write movement, avoidance and stuck events to a log file for stuck diagnosis.
## Windows path: %APPDATA%\Godot\app_userdata\<project name>\citizen.log
@export var enable_file_log: bool = false
## Also log verbose per-check detail (avoidance probes, jump ray, A* results). Can be noisy.
@export var log_verbose: bool = false
## Override log path. Empty = user://citizen.log (Godot user-data folder).
@export var log_file_path: String = "user://citizen.log"

func _ready() -> void:
	if obstacle_down_ray_path != NodePath():
		_obstacle_down_ray = get_node_or_null(obstacle_down_ray_path) as RayCast3D
	else:
		_obstacle_down_ray = get_node_or_null("ObstacleSensorPivot/ObstacleRayCastDown") as RayCast3D
	if jump_low_obstacles and _obstacle_down_ray == null:
		push_warning("Citizen: jump_low_obstacles is enabled, but ObstacleRayCastDown was not found.")
	elif jump_low_obstacles:
		_obstacle_down_ray.enabled = true
	# Truncate the log file at the start of each run so old entries don't
	# accumulate across play-mode sessions.
	if enable_file_log:
		var path := log_file_path if not log_file_path.is_empty() else "user://citizen.log"
		var file := FileAccess.open(path, FileAccess.WRITE)  # WRITE truncates
		if file != null:
			file.store_string("[%s] === session start ===\n" % Time.get_datetime_string_from_system())
			file.close()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_RIGHT \
			and event.pressed:
		if ignore_ui_clicks and get_viewport().gui_get_hovered_control() != null:
			return
		var click_pos: Variant = _get_click_world_position(event.position)
		if click_pos != null:
			set_global_target(click_pos as Vector3)

func set_global_target(target: Vector3) -> bool:
	target_position = target
	global_path = _build_global_path(global_position, target_position)
	path_index = 0
	_is_travelling = global_path.size() >= 2
	_cached_avoidance_blocked = false
	_smoothed_move_direction = Vector3.ZERO
	# Start the timer at a full interval so the stuck check does not fire before
	# the citizen has had any chance to move toward the new target.
	_stuck_check_timer = maxf(stuck_detection_interval, 0.5)
	_stuck_recovery_attempts = 0
	_stuck_last_pos = global_position
	_surface_escape_cooldown = 0.0
	_clear_local_avoidance_path()
	_obstacle_check_timer = 0.0
	if _is_travelling:
		_is_travelling = _advance_path_progress()
	_update_global_path_visual()
	_log("TARGET_SET", "from=%s to=%s waypoints=%d travelling=%s" % [
		_fmt_v3(global_position), _fmt_v3(target_position),
		global_path.size(), str(_is_travelling)])
	return _is_travelling

func _physics_process(delta: float) -> void:
	_update_jump_cooldown(delta)
	_update_stuck_detection(delta)
	# Track coyote time: is_on_floor() reflects last frame's move_and_slide result,
	# so we read it here (before this frame's move_and_slide) to keep a grace window
	# that allows jumping for a few frames after briefly leaving the floor at step edges.
	if is_on_floor():
		_coyote_time = 0.1
	else:
		_coyote_time = maxf(_coyote_time - delta, 0.0)
	if _surface_escape_cooldown > 0.0:
		_surface_escape_cooldown = maxf(_surface_escape_cooldown - delta, 0.0)

	if not _is_travelling:
		_clear_avoidance_debug_visual()
		_apply_idle_gravity(delta)
		move_and_slide()
		return

	if path_index >= global_path.size():
		_clear_avoidance_debug_visual()
		_stop_at_target()
		_apply_idle_gravity(delta)
		move_and_slide()
		return

	if not _advance_path_progress():
		_clear_avoidance_debug_visual()
		_stop_at_target()
		_apply_idle_gravity(delta)
		move_and_slide()
		return

	var move_target := _get_path_move_target()
	var direction := move_target - global_position
	direction.y = 0.0
	if direction.length_squared() > 0.0001:
		var desired_direction := direction.normalized()
		var steered_direction := _get_steered_direction(desired_direction, delta)
		var final_direction := _smooth_move_direction(steered_direction, desired_direction, delta)
		var final_speed := move_speed
		if _cached_avoidance_blocked:
			final_speed *= avoidance_slowdown_factor
		velocity.x = final_direction.x * final_speed
		velocity.z = final_direction.z * final_speed
		# Always probe in the direct-to-waypoint direction so the ray faces the
		# obstacle regardless of which way the avoidance system is currently steering.
		if _try_jump_low_obstacle(desired_direction):
			# Jump was triggered: cancel any active avoidance so the citizen
			# continues straight through the obstacle it just jumped over instead
			# of being rerouted around it mid-air.
			_clear_local_avoidance_path()
			_cached_avoidance_blocked = false
			_obstacle_check_timer = jump_cooldown
		look_at(global_position + final_direction, Vector3.UP)
		_update_avoidance_debug_visual(desired_direction, final_direction)
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		_smoothed_move_direction = Vector3.ZERO
		_clear_avoidance_debug_visual()

	_apply_idle_gravity(delta)
	move_and_slide()

func stop_travel() -> void:
	global_path = PackedVector3Array()
	path_index = 0
	_is_travelling = false
	_cached_avoidance_blocked = false
	_local_astar_follow_global_on_fail = false
	_smoothed_move_direction = Vector3.ZERO
	_stuck_check_timer = 0.0
	_stuck_recovery_attempts = 0
	_surface_escape_cooldown = 0.0
	_clear_local_avoidance_path()
	velocity = Vector3.ZERO
	_clear_global_path_visual()
	_clear_avoidance_debug_visual()

func is_travelling() -> bool:
	return _is_travelling

func _get_steered_direction(desired_direction: Vector3, delta: float) -> Vector3:
	if not use_local_astar_avoidance:
		_cached_avoidance_blocked = false
		_clear_local_avoidance_path()
		return desired_direction

	_local_astar_replan_timer -= delta

	# Follow active local A* path.
	var local_dir := _get_local_avoidance_path_direction()
	if local_dir != Vector3.ZERO:
		_cached_avoidance_blocked = true
		_debug_avoidance_status = "local path"
		return local_dir

	# Forward probe: detect whether the path ahead is physically blocked or surface must be escaped.
	_obstacle_check_timer -= delta
	if _obstacle_check_timer <= 0.0:
		_obstacle_check_timer = obstacle_check_interval
		var surface_kind := _get_local_astar_surface_kind(global_position)
		var _prev_blocked := _cached_avoidance_blocked
		_cached_avoidance_blocked = _is_path_ahead_blocked(desired_direction) \
				or _should_local_astar_escape_surface(surface_kind)
		_debug_avoidance_status = "blocked" if _cached_avoidance_blocked else "clear"
		if _cached_avoidance_blocked and not _prev_blocked:
			_log("AVOIDANCE_BLOCKED", "surface='%s' y=%.3f pos=%s dir=%s" % [
				surface_kind, global_position.y, _fmt_v3(global_position), _fmt_v3(desired_direction)])

	if _cached_avoidance_blocked and _local_astar_replan_timer <= 0.0:
		_local_astar_replan_timer = maxf(local_astar_replan_interval, 0.02)
		if _try_build_local_astar_path(desired_direction):
			local_dir = _get_local_avoidance_path_direction()
			if local_dir != Vector3.ZERO:
				_cached_avoidance_blocked = true
				_debug_avoidance_status = "local path"
				return local_dir
		if _local_astar_follow_global_on_fail:
			_cached_avoidance_blocked = false
			_debug_avoidance_status = "global fallback"
			_log_v("AVOIDANCE_FALLBACK", "A* gave up — resuming global path | pos=%s dir=%s" % [
				_fmt_v3(global_position), _fmt_v3(desired_direction)])
	elif not _cached_avoidance_blocked:
		_clear_local_avoidance_path()

	return desired_direction

## Returns true when a physics obstacle blocks the path at roughly half the local A* radius ahead.
func _is_path_ahead_blocked(direction: Vector3) -> bool:
	if not is_inside_tree() or get_world_3d() == null:
		return false
	var flat_dir := direction
	flat_dir.y = 0.0
	if flat_dir.length_squared() <= 0.0001:
		return false
	_local_astar_probe_shape.radius = maxf(local_astar_probe_radius, 0.03)
	var probe_pos := global_position + flat_dir.normalized() * (local_astar_radius * 0.5)
	probe_pos.y = global_position.y + 0.35
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _local_astar_probe_shape
	query.transform = Transform3D(Basis.IDENTITY, probe_pos)
	query.collision_mask = collision_mask
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [get_rid()]
	var flat_dir_norm := flat_dir.normalized()
	for hit in get_world_3d().direct_space_state.intersect_shape(query, 4):
		if _is_local_astar_probe_hit_blocking(hit):
			# Don't flag low jumpable obstacles as blocked — the jump system
			# handles those directly, and avoidance rerouting around a curb
			# would prevent the jump from ever firing.
			if jump_low_obstacles and _is_obstacle_below_jump_height(flat_dir_norm):
				var c = hit.get("collider", null)
				_log_v("AVOIDANCE_SKIP_JUMPABLE", "low obstacle '%s' pos=%s dir=%s" % [
					c.name if c is Node else "?", _fmt_v3(global_position), _fmt_v3(flat_dir_norm)])
				continue
			var c = hit.get("collider", null)
			_log_v("PATH_BLOCKED", "collider='%s' pos=%s dir=%s" % [
				c.name if c is Node else "?", _fmt_v3(global_position), _fmt_v3(flat_dir_norm)])
			return true
	return false

## Returns true when the obstacle directly ahead is low enough to be jumped over.
## Probes at (max_jump_obstacle_height + margin) — if that level is clear the
## obstacle sits entirely within the jump-height window and avoidance should not
## treat it as a wall.
func _is_obstacle_below_jump_height(flat_direction: Vector3) -> bool:
	if not is_inside_tree() or get_world_3d() == null:
		return false
	var probe_pos := global_position + flat_direction * (local_astar_radius * 0.5)
	probe_pos.y = global_position.y + maxf(max_jump_obstacle_height, 0.0) + 0.06
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _local_astar_probe_shape
	query.transform = Transform3D(Basis.IDENTITY, probe_pos)
	query.collision_mask = collision_mask
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [get_rid()]
	for hit in get_world_3d().direct_space_state.intersect_shape(query, 4):
		if _is_local_astar_probe_hit_blocking(hit):
			return false  # Something above jump height — treat as real wall
	return true  # Only blocked below jump height — jumpable

func _smooth_move_direction(target_direction: Vector3, fallback_direction: Vector3, delta: float) -> Vector3:
	var target := target_direction
	target.y = 0.0
	if target.length_squared() <= 0.0001:
		target = fallback_direction
		target.y = 0.0
	if target.length_squared() <= 0.0001:
		return Vector3.ZERO

	target = target.normalized()
	if _smoothed_move_direction.length_squared() <= 0.0001:
		_smoothed_move_direction = target
		return target

	if steering_smoothing <= 0.0:
		_smoothed_move_direction = target
		return target

	var blend := 1.0 - exp(-maxf(steering_smoothing, 0.0) * delta)
	_smoothed_move_direction = _smoothed_move_direction.lerp(target, blend)
	_smoothed_move_direction.y = 0.0
	if _smoothed_move_direction.length_squared() <= 0.0001:
		_smoothed_move_direction = target
	else:
		_smoothed_move_direction = _smoothed_move_direction.normalized()
	return _smoothed_move_direction

func _try_build_local_astar_path(desired_direction: Vector3) -> bool:
	_clear_local_avoidance_path()
	_debug_local_astar_status = "planning"
	_local_astar_follow_global_on_fail = false

	if not is_inside_tree() or get_world_3d() == null:
		_debug_local_astar_status = "no world"
		return false

	var forward := desired_direction
	forward.y = 0.0
	if forward.length_squared() <= 0.0001:
		_debug_local_astar_status = "no forward"
		return false
	forward = forward.normalized()

	var right := _get_planar_right(forward)
	var cell_size := maxf(local_astar_cell_size, 0.08)
	var radius := maxf(local_astar_radius, cell_size * 2.0)
	# step is the probe spacing; cell_size is kept for world-space margins below.
	var step := cell_size / float(maxi(local_astar_grid_subdivisions, 1))
	var cell_radius := int(ceil(radius / step))
	# Doubled coordinate space so normal and staggered cells share one ID scheme.
	#   Normal cells:   Vector2i(x*2,   z*2)   → world offset (x*step,       z*step)
	#   Staggered cells:Vector2i(x*2+1, z*2+1) → world offset ((x+0.5)*step, (z+0.5)*step)
	# World offset from any cell: Vector2(cell.x * step * 0.5, cell.y * step * 0.5)
	var doubled_radius := cell_radius * 2
	var origin := global_position
	var start_cell := Vector2i.ZERO
	var start_id := _local_astar_cell_id(start_cell, doubled_radius)
	var start_surface_kind := _get_local_astar_surface_kind(origin)
	var start_needs_surface_escape := _should_local_astar_escape_surface(start_surface_kind)
	var point_ids: Dictionary = {}
	var cell_surfaces: Dictionary = {}
	var astar := AStar2D.new()

	_debug_local_astar_cells.clear()
	_local_astar_probe_shape.radius = maxf(local_astar_probe_radius, 0.03)

	for z in range(-cell_radius, cell_radius + 1):
		# Normal row at z * step
		for x in range(-cell_radius, cell_radius + 1):
			_probe_and_register_cell(Vector2i(x * 2, z * 2), doubled_radius, step, radius,
					origin, right, forward, start_cell, start_needs_surface_escape,
					point_ids, cell_surfaces, astar)
		# Staggered row between z and z+1, shifted by (0.5*step, 0.5*step)
		if z < cell_radius:
			for x in range(-cell_radius, cell_radius):
				_probe_and_register_cell(Vector2i(x * 2 + 1, z * 2 + 1), doubled_radius, step, radius,
						origin, right, forward, start_cell, start_needs_surface_escape,
						point_ids, cell_surfaces, astar)

	if not point_ids.has(start_cell):
		_debug_local_astar_status = "blocked start"
		_log_v("ASTAR_FAIL", "blocked_start | pos=%s" % _fmt_v3(global_position))
		return false

	# Cross-type diagonals (normal↔staggered) are the primary hex edges.
	# Same-type direct connections handle row-to-row routing in open areas.
	# No corner-cut validation needed: diagonals are always valid hex transitions.
	var neighbors: Array[Vector2i] = [
		Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1),
		Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2),
	]
	for cell_key in point_ids.keys():
		var cell: Vector2i = cell_key
		var point_id: int = point_ids[cell]
		for neighbor_offset: Vector2i in neighbors:
			var neighbor_cell := cell + neighbor_offset
			if not point_ids.has(neighbor_cell):
				continue
			var neighbor_id: int = point_ids[neighbor_cell]
			if point_id < neighbor_id:
				astar.connect_points(point_id, neighbor_id, true)

	var candidates: Array[Dictionary] = []
	var front_y := -INF
	var left_open := false
	for cell_key in point_ids.keys():
		var cell: Vector2i = cell_key
		if cell == start_cell:
			continue

		var candidate_surface := str(cell_surfaces.get(cell, "unknown"))
		if _is_local_astar_surface_blocked(candidate_surface):
			continue

		var candidate_offset := Vector2(float(cell.x) * step * 0.5, float(cell.y) * step * 0.5)
		if start_needs_surface_escape:
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

		var candidate_world := _local_astar_world_from_offset(origin, right, forward, candidate_offset)
		var reference_distance := _distance_to_global_path_ahead(candidate_world)
		var path_length := _local_astar_path_length(candidate_path)
		# Penalise cells that share an edge with a road cell so the citizen
		# keeps a one-cell buffer from the pedestrian-zone boundary.  The cell
		# is still added as a candidate so it acts as a fallback when no
		# road-free front-row cell exists (e.g. very narrow walkway).
		var near_road := false
		for nb_off in neighbors:
			if _is_local_astar_surface_blocked(str(cell_surfaces.get(cell + nb_off, ""))):
				near_road = true
				break
		candidates.append({
			"path": candidate_path,
			"offset": candidate_offset,
			"reference_distance": reference_distance,
			"path_length": path_length,
			"surface": candidate_surface,
			"near_road": near_road
		})
		front_y = maxf(front_y, candidate_offset.y)
		if candidate_offset.x < -cell_size:
			left_open = true

	if candidates.is_empty():
		_debug_local_astar_status = "all x red global"
		_local_astar_follow_global_on_fail = true
		# Back off for 2 s so the 80 ms replan-interval doesn't spin the citizen
		# in place while the grid keeps returning no viable cells (e.g. right
		# after landing on a pedestrian zone whose probe reads as road).
		_surface_escape_cooldown = maxf(_surface_escape_cooldown, 2.0)
		_log("ASTAR_NO_CANDIDATES", "all cells blocked — follow global path | pos=%s" % _fmt_v3(global_position))
		return false

	var front_tolerance := maxf(local_astar_front_row_tolerance, cell_size)
	var prefer_right := local_astar_prefer_right_when_left_open and left_open
	var has_right_front_candidate := false
	if prefer_right and not start_needs_surface_escape:
		for candidate_value in candidates:
			var candidate: Dictionary = candidate_value
			var candidate_offset: Vector2 = candidate.get("offset", Vector2.ZERO)
			if candidate_offset.y >= front_y - front_tolerance and candidate_offset.x >= 0.0:
				has_right_front_candidate = true
				break

	var best_path := PackedVector2Array()
	var best_score := INF
	var selection_label := "surface escape" if start_needs_surface_escape else "front row"
	for candidate_value in candidates:
		var candidate: Dictionary = candidate_value
		var candidate_offset: Vector2 = candidate.get("offset", Vector2.ZERO)
		if not start_needs_surface_escape:
			if candidate_offset.y < front_y - front_tolerance:
				continue
			if prefer_right and has_right_front_candidate and candidate_offset.x < 0.0:
				continue

		var reference_distance: float = candidate.get("reference_distance", INF)
		var path_length: float = candidate.get("path_length", 0.0)
		var score := reference_distance + path_length * (0.25 if start_needs_surface_escape else 0.1)
		# Steer away from the road edge: cells adjacent to road get a large
		# penalty so they are only picked when no cleaner alternative exists.
		if candidate.get("near_road", false):
			score += 3.0
		if prefer_right and not start_needs_surface_escape:
			score -= candidate_offset.x * 0.05
			selection_label = "front row right"
		if score < best_score:
			best_score = score
			best_path = candidate.get("path", PackedVector2Array())

	if best_path.size() < 2:
		_debug_local_astar_status = "no reachable edge"
		_log_v("ASTAR_FAIL", "no_reachable_edge | pos=%s" % _fmt_v3(global_position))
		return false

	for idx in range(1, best_path.size()):
		_local_avoidance_path.append(_local_astar_world_from_offset(origin, right, forward, best_path[idx]))
	_local_avoidance_path_index = 0
	_debug_local_astar_goal = _local_avoidance_path[_local_avoidance_path.size() - 1]
	_debug_local_astar_has_goal = true
	_debug_local_astar_status = "%s %d" % [selection_label, _local_avoidance_path.size()]
	_log_v("ASTAR_OK", "status='%s' waypoints=%d goal=%s | pos=%s" % [
		_debug_local_astar_status, _local_avoidance_path.size(),
		_fmt_v3(_debug_local_astar_goal), _fmt_v3(global_position)])
	return true

func _get_local_avoidance_path_direction() -> Vector3:
	while _local_avoidance_path_index < _local_avoidance_path.size():
		var target := _local_avoidance_path[_local_avoidance_path_index]
		var to_target := target - global_position
		to_target.y = 0.0
		if to_target.length() > maxf(local_astar_goal_reach_distance, 0.04):
			return to_target.normalized()
		_local_avoidance_path_index += 1

	_clear_local_avoidance_path()
	# Path fully consumed: force a fresh obstacle check so we don't immediately
	# re-trigger another local plan while the way ahead may now be clear.
	_cached_avoidance_blocked = false
	_obstacle_check_timer = 0.0
	return Vector3.ZERO

func _clear_local_avoidance_path() -> void:
	_local_avoidance_path = PackedVector3Array()
	_local_avoidance_path_index = 0
	_debug_local_astar_goal = Vector3.ZERO
	_debug_local_astar_has_goal = false
	if _debug_local_astar_status != "planning":
		_debug_local_astar_status = "-"

func _probe_and_register_cell(
		cell: Vector2i, doubled_radius: int, step: float, radius: float,
		origin: Vector3, right: Vector3, forward: Vector3,
		start_cell: Vector2i, start_needs_surface_escape: bool,
		point_ids: Dictionary, cell_surfaces: Dictionary, astar: AStar2D) -> void:
	var offset := Vector2(float(cell.x) * step * 0.5, float(cell.y) * step * 0.5)
	if offset.length() > radius:
		return
	var world_point := _local_astar_world_from_offset(origin, right, forward, offset)
	var surface_kind := _get_local_astar_surface_kind(world_point)
	var physics_blocked := _is_local_astar_probe_blocked(world_point)
	var surface_blocked := _is_local_astar_surface_blocked(surface_kind)
	if debug_draw_avoidance:
		_debug_local_astar_cells.append({
			"point": world_point,
			"blocked": physics_blocked or surface_blocked,
			"blocked_reason": _get_local_astar_blocked_reason(physics_blocked, surface_blocked),
			"surface": surface_kind
		})
	# Always record the surface so neighbour-adjacency checks (near_road penalty)
	# can see road cells even when they are excluded from the A* graph.
	cell_surfaces[cell] = surface_kind
	# Back-cells are kept as intermediate graph nodes for routing around corners,
	# but excluded from goal candidates below.
	if physics_blocked and cell != start_cell:
		return
	if surface_blocked and cell != start_cell and not start_needs_surface_escape:
		return
	var point_id := _local_astar_cell_id(cell, doubled_radius)
	point_ids[cell] = point_id
	astar.add_point(point_id, offset)

func _local_astar_cell_id(cell: Vector2i, cell_radius: int) -> int:
	var width := cell_radius * 2 + 1
	return (cell.y + cell_radius) * width + cell.x + cell_radius + 1

func _local_astar_world_from_offset(origin: Vector3, right: Vector3, forward: Vector3, offset: Vector2) -> Vector3:
	var point := origin + right * offset.x + forward * offset.y
	point.y = origin.y
	return point

func _get_planar_right(forward: Vector3) -> Vector3:
	var planar_forward := forward
	planar_forward.y = 0.0
	if planar_forward.length_squared() <= 0.0001:
		return Vector3.RIGHT
	return planar_forward.normalized().cross(Vector3.UP).normalized()

func _is_local_astar_probe_blocked(point: Vector3) -> bool:
	if get_world_3d() == null:
		return true

	var probe_position := point
	probe_position.y = global_position.y + 0.35

	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _local_astar_probe_shape
	query.transform = Transform3D(Basis.IDENTITY, probe_position)
	query.collision_mask = _get_local_astar_collision_mask()
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [get_rid()]

	var hits := get_world_3d().direct_space_state.intersect_shape(query, 8)
	for hit in hits:
		if _is_local_astar_probe_hit_blocking(hit):
			return true
	return false

func _is_local_astar_probe_hit_blocking(hit: Dictionary) -> bool:
	return not _is_local_astar_walkable_probe_collider(hit.get("collider", null))

func _is_local_astar_walkable_probe_collider(collider: Variant) -> bool:
	if not (collider is Node):
		return false

	var current := collider as Node
	while current != null:
		if current.is_in_group("road_group"):
			return true

		var current_path := ""
		if current.is_inside_tree():
			current_path = str(current.get_path()).to_lower()
		var current_name := current.name.to_lower()

		if current_path.contains("/only_transport/"):
			return true
		if current_name.begins_with("park_road"):
			return true
		# Crosswalk / zebra-crossing mesh is walkable — don't treat its raised
		# markings as a wall that triggers avoidance or jump.
		if current_path.contains("/road_straight_crossing/") \
				or current_name.contains("crosswalk") \
				or current_name.contains("crossing"):
			return true

		current = current.get_parent()

	return false

func _is_local_astar_surface_blocked(surface_kind: String) -> bool:
	if not local_astar_avoid_road_cells:
		return false
	return surface_kind == "road"

func _should_local_astar_escape_surface(surface_kind: String) -> bool:
	# Suppressed after a stuck-recovery replan so the citizen can follow the
	# global path through the road instead of looping in surface-escape mode.
	if _surface_escape_cooldown > 0.0:
		return false
	# Don't trigger surface-escape mid-jump — the probe may read road beneath
	# a pedestrian zone (thin mesh) and cause spinning right after landing.
	if _jump_cooldown_timer > 0.0:
		return false
	# Only escape confirmed road surfaces.  "" and "unknown" mean the probe
	# couldn't classify the surface (e.g. probe under a thin pedzone mesh) —
	# treating those as "road" caused constant escape-looping on pedestrian zones.
	return _is_local_astar_surface_blocked(surface_kind)

func _get_local_astar_blocked_reason(physics_blocked: bool, surface_blocked: bool) -> String:
	if physics_blocked and surface_blocked:
		return "physics+road"
	if physics_blocked:
		return "physics"
	if surface_blocked:
		return "road"
	return ""

func _get_local_astar_surface_kind(point: Vector3) -> String:
	var hit := _probe_local_astar_surface(point)
	var kind := _classify_surface_hit(hit)
	if kind == "road" and not hit.is_empty():
		# If the probe hit road but the query point is clearly above the hit,
		# the ray passed through a thin elevated surface (pedestrian zone mesh
		# on a collision layer the probe skips) and hit the road below.
		# Pedzone is typically 2–4 cm above road, so 0.025 m is a safe threshold.
		# Downgrading to "unknown" prevents surface-escape from firing while the
		# citizen is standing on the pedzone.
		var hit_y: float = (hit.get("position", point) as Vector3).y
		if point.y - hit_y > 0.025:
			kind = "unknown"
	if kind != "" and kind != "unknown":
		return kind

	# Lazily cache world node — traversing the scene tree per cell is expensive.
	if not is_instance_valid(_cached_world_node):
		_cached_world_node = _get_world_node()
	if _cached_world_node != null and _cached_world_node.has_method("get_pedestrian_path_point_kind"):
		var graph_kind := str(_cached_world_node.get_pedestrian_path_point_kind(point))
		if not graph_kind.is_empty():
			return graph_kind
	return kind

func _probe_local_astar_surface(point: Vector3) -> Dictionary:
	if not is_inside_tree() or get_world_3d() == null:
		return {}

	var from := point + Vector3.UP * maxf(local_astar_surface_probe_up, 0.2)
	var to := point + Vector3.DOWN * maxf(local_astar_surface_probe_down, 0.2)
	var exclude: Array[RID] = [get_rid()]
	var attempts := maxi(local_astar_surface_probe_max_hits, 1)

	for _attempt in range(attempts):
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.collision_mask = local_astar_surface_collision_mask
		query.collide_with_areas = false
		query.exclude = exclude

		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			return {}

		var collider: Variant = hit.get("collider", null)
		if collider is CharacterBody3D:
			if not hit.has("rid"):
				return {}
			exclude.append(hit["rid"])
			continue
		return hit

	return {}

func _classify_surface_hit(hit: Dictionary) -> String:
	if hit.is_empty():
		return "unknown"

	var collider: Variant = hit.get("collider", null)
	if collider is Node:
		return _classify_surface_node(collider as Node)
	return "unknown"

func _classify_surface_node(node: Node) -> String:
	var current := node
	while current != null:
		var current_path := ""
		if current.is_inside_tree():
			current_path = str(current.get_path()).to_lower()
		var current_name := current.name.to_lower()

		if current_path.contains("/road_straight_crossing/") \
				or current_name.contains("crosswalk") \
				or current_name.contains("crossing"):
			return "crosswalk"
		if current.is_in_group("road_group"):
			return "road"
		if current_path.contains("/only_transport/"):
			return "road"
		if current_path.contains("/only_people_nav/"):
			return "pedestrian"

		current = current.get_parent()

	return "unknown"

func _get_local_astar_collision_mask() -> int:
	return collision_mask

func _local_astar_path_length(path: PackedVector2Array) -> float:
	var total := 0.0
	for idx in range(path.size() - 1):
		total += path[idx].distance_to(path[idx + 1])
	return total

func _planar_distance(a: Vector3, b: Vector3) -> float:
	var offset := a - b
	offset.y = 0.0
	return offset.length()

func _distance_to_global_path_ahead(point: Vector3) -> float:
	if global_path.size() < 2:
		return _planar_distance(point, target_position)

	var best_distance := INF
	var start_index := clampi(path_index - 1, 0, global_path.size() - 2)
	for idx in range(start_index, global_path.size() - 1):
		best_distance = minf(best_distance, _planar_distance_to_segment(point, global_path[idx], global_path[idx + 1]))
	return best_distance

func _planar_distance_to_segment(point: Vector3, from: Vector3, to: Vector3) -> float:
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

func _build_global_path(start: Vector3, target: Vector3) -> PackedVector3Array:
	var world_path := _build_world_pedestrian_path(start, target)
	if world_path.size() >= 2:
		return world_path

	var route := PackedVector3Array()
	var navigation_map := _get_navigation_map()
	if not navigation_map.is_valid() or NavigationServer3D.map_get_iteration_id(navigation_map) <= 0:
		route.append(start)
		route.append(target)
		return route

	var nav_start := NavigationServer3D.map_get_closest_point(navigation_map, start)
	var nav_target := NavigationServer3D.map_get_closest_point(navigation_map, target)
	var nav_path := NavigationServer3D.map_get_path(navigation_map, nav_start, nav_target, true)
	if nav_path.is_empty():
		route.append(start)
		route.append(target)
		return route

	_append_path_point(route, start)
	for point in nav_path:
		_append_path_point(route, point)
	_append_path_point(route, target)
	return route

func _build_world_pedestrian_path(start: Vector3, target: Vector3) -> PackedVector3Array:
	var world := _get_world_node()
	if world != null and world.has_method("get_pedestrian_path"):
		var route: PackedVector3Array = world.get_pedestrian_path(start, target)
		if route.size() >= 2:
			return route
	return PackedVector3Array()

func _get_click_world_position(screen_pos: Vector2) -> Variant:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return null

	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * click_ray_distance
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = click_collision_mask
	query.collide_with_areas = false
	query.exclude = [get_rid()]

	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		return hit.get("position", Vector3.ZERO) as Vector3

	var ground_plane := Plane(Vector3.UP, global_position.y)
	var plane_hit: Variant = ground_plane.intersects_ray(from, camera.project_ray_normal(screen_pos))
	return plane_hit

func _get_navigation_map() -> RID:
	if not is_inside_tree():
		return RID()
	var world_3d := get_world_3d()
	if world_3d == null:
		return RID()
	if world_3d.has_method("get_navigation_map"):
		return world_3d.get_navigation_map()
	return world_3d.navigation_map

func _get_world_node() -> Node:
	var current: Node = self
	while current != null:
		if current.has_method("get_pedestrian_path"):
			return current
		current = current.get_parent()
	var world_nodes := get_tree().get_nodes_in_group("world") if is_inside_tree() else []
	for world in world_nodes:
		if world != null and world.has_method("get_pedestrian_path"):
			return world
	return null

func _append_path_point(route: PackedVector3Array, point: Vector3) -> void:
	if route.is_empty() or route[route.size() - 1].distance_to(point) > 0.05:
		route.append(point)

func _advance_path_progress() -> bool:
	var old_index := path_index
	while path_index < global_path.size():
		if not _is_at_path_index(path_index) and not _has_passed_path_index(path_index):
			break
		path_index += 1
		_reset_path_following_state_for_next_waypoint()
	if path_index != old_index:
		_update_global_path_visual()
	return path_index < global_path.size()

func _reset_path_following_state_for_next_waypoint() -> void:
	_cached_avoidance_blocked = false
	_local_astar_replan_timer = 0.0
	_obstacle_check_timer = 0.0
	_local_astar_follow_global_on_fail = false
	_clear_local_avoidance_path()

func _is_at_path_index(index: int) -> bool:
	if index < 0 or index >= global_path.size():
		return false
	return _planar_distance(global_position, global_path[index]) <= _get_path_reach_distance(index)

func _has_passed_path_index(index: int) -> bool:
	if index <= 0 or index >= global_path.size() - 1:
		return false

	var previous := global_path[index - 1]
	var waypoint := global_path[index]
	var segment := waypoint - previous
	segment.y = 0.0
	var segment_length_squared := segment.length_squared()
	if segment_length_squared <= 0.0001:
		return false

	var to_position := global_position - previous
	to_position.y = 0.0
	var progress := to_position.dot(segment) / segment_length_squared
	if progress < 1.0:
		return false

	var pass_distance := maxf(waypoint_pass_distance, _get_path_reach_distance(index))
	return _planar_distance(global_position, waypoint) <= pass_distance

func _get_path_reach_distance(index: int) -> float:
	if index >= global_path.size() - 1:
		return maxf(final_waypoint_reach_distance, 0.02)
	return maxf(waypoint_reach_distance, 0.02)

func _get_path_move_target() -> Vector3:
	if global_path.is_empty() or path_index < 0 or path_index >= global_path.size():
		return target_position

	var move_target := global_path[path_index]
	if path_index >= global_path.size() - 1:
		return move_target

	var current_delta := move_target - global_position
	current_delta.y = 0.0
	var current_distance := current_delta.length()
	var blend_distance := maxf(corner_blend_distance, 0.05)
	if current_distance >= blend_distance:
		return move_target

	var next_point := global_path[path_index + 1]
	var blend_t := 1.0 - clampf(current_distance / blend_distance, 0.0, 1.0)
	var blend_weight := clampf(blend_t * corner_blend_strength, 0.0, 0.8)
	var blended_target := move_target.lerp(next_point, blend_weight)
	blended_target.y = lerpf(move_target.y, next_point.y, blend_weight)
	return blended_target

func _stop_at_target() -> void:
	var was_travelling := _is_travelling
	_is_travelling = false
	_cached_avoidance_blocked = false
	_smoothed_move_direction = Vector3.ZERO
	_stuck_check_timer = 0.0
	_stuck_recovery_attempts = 0
	velocity.x = 0.0
	velocity.z = 0.0
	if clear_global_path_on_arrival:
		_clear_global_path_visual()
	_clear_avoidance_debug_visual()
	if was_travelling:
		_log("ARRIVED", "pos=%s target=%s" % [_fmt_v3(global_position), _fmt_v3(target_position)])
		target_reached.emit()

func _apply_idle_gravity(delta: float) -> void:
	if is_on_floor():
		if velocity.y < 0.0:
			velocity.y = 0.0
	else:
		velocity.y -= _gravity * delta

func _update_jump_cooldown(delta: float) -> void:
	if _jump_cooldown_timer > 0.0:
		_jump_cooldown_timer = maxf(_jump_cooldown_timer - delta, 0.0)

func _update_stuck_detection(delta: float) -> void:
	if not _is_travelling:
		_stuck_check_timer = 0.0
		_stuck_recovery_attempts = 0
		_stuck_last_pos = global_position
		return
	# Skip stuck detection when already within arrival distance of the target.
	# At this range the normal arrival logic will fire before the next interval.
	var dist_to_target := _planar_distance(global_position, target_position)
	if dist_to_target <= maxf(stuck_detection_min_distance * 2.0, final_waypoint_reach_distance * 2.0):
		return
	_stuck_check_timer -= delta
	if _stuck_check_timer > 0.0:
		return
	_stuck_check_timer = maxf(stuck_detection_interval, 0.5)
	var dist := _planar_distance(global_position, _stuck_last_pos)
	_stuck_last_pos = global_position
	if dist < maxf(stuck_detection_min_distance, 0.05):
		_log("STUCK_CHECK", "moved=%.3f < %.3f | pos=%s avoidance='%s' local='%s' jump='%s'" % [
			dist, stuck_detection_min_distance, _fmt_v3(global_position),
			_debug_avoidance_status, _debug_local_astar_status, _debug_jump_status])
		_try_recover_from_stuck()

func _try_recover_from_stuck() -> void:
	# If we're already very close to the destination, just arrive rather than replan.
	var dist_to_target := _planar_distance(global_position, target_position)
	if dist_to_target <= maxf(stuck_detection_min_distance * 2.0, final_waypoint_reach_distance * 2.0):
		_stop_at_target()
		return
	_stuck_recovery_attempts += 1
	if _stuck_recovery_attempts > maxi(stuck_max_recovery_attempts, 1):
		_log("STUCK_FINAL", "pos=%s target=%s | all %d attempts exhausted | avoidance='%s' local='%s'" % [
			_fmt_v3(global_position), _fmt_v3(target_position),
			stuck_max_recovery_attempts, _debug_avoidance_status, _debug_local_astar_status])
		stop_travel()
		stuck.emit()
		return
	_log("STUCK_REPLAN", "attempt=%d/%d | pos=%s target=%s | avoidance='%s' local='%s'" % [
		_stuck_recovery_attempts, stuck_max_recovery_attempts,
		_fmt_v3(global_position), _fmt_v3(target_position),
		_debug_avoidance_status, _debug_local_astar_status])
	# Suppress surface-escape for a few seconds after replan so the citizen
	# can follow the rebuilt global path through the road without immediately
	# re-entering the same surface-escape loop that caused the blockage.
	_surface_escape_cooldown = 4.0
	# Replan from the current position so the path avoids whatever caused
	# the blockage. This handles cases where navigation geometry shifted or
	# the original route led into an impassable corner.
	var rebuilt := _build_global_path(global_position, target_position)
	if rebuilt.size() < 2:
		_log("STUCK_FINAL", "pos=%s target=%s | replan returned empty path" % [
			_fmt_v3(global_position), _fmt_v3(target_position)])
		stop_travel()
		stuck.emit()
		return
	global_path = rebuilt
	path_index = 0
	_clear_local_avoidance_path()
	_cached_avoidance_blocked = false
	_smoothed_move_direction = Vector3.ZERO
	_obstacle_check_timer = 0.0
	_local_astar_replan_timer = 0.0
	_advance_path_progress()
	_update_global_path_visual()

func _try_jump_low_obstacle(move_direction: Vector3) -> bool:
	if not jump_low_obstacles:
		_debug_jump_status = "off"
		return false
	if _obstacle_down_ray == null or not _obstacle_down_ray.enabled:
		_debug_jump_status = "no ray"
		return false

	var planar_move_direction := move_direction
	planar_move_direction.y = 0.0
	if planar_move_direction.length_squared() <= 0.0001:
		_debug_jump_status = "no move"
		return false
	planar_move_direction = planar_move_direction.normalized()

	if _jump_cooldown_timer > 0.0:
		_debug_jump_status = "cooldown %.2f" % _jump_cooldown_timer
		return false
	if not is_on_floor() and _coyote_time <= 0.0:
		_debug_jump_status = "air"
		return false

	_update_obstacle_down_ray_target(planar_move_direction)
	_obstacle_down_ray.force_raycast_update()
	if not _obstacle_down_ray.is_colliding():
		_debug_jump_status = "no hit"
		_log_v("JUMP_MISS", "ray fired no hit | pos=%s dir=%s" % [
			_fmt_v3(global_position), _fmt_v3(planar_move_direction)])
		return false

	var collider := _obstacle_down_ray.get_collider()
	if collider == self:
		_debug_jump_status = "self"
		return false
	# Don't jump over zebra crossings — the raised stripe geometry sits within
	# the jump-height window but crossing it on foot is always valid.
	if collider is Node and _classify_surface_node(collider as Node) == "crosswalk":
		_debug_jump_status = "crosswalk"
		return false

	var hit_point := _obstacle_down_ray.get_collision_point()
	var to_hit := hit_point - global_position
	to_hit.y = 0.0
	if to_hit.length_squared() > 0.0001 and planar_move_direction.dot(to_hit.normalized()) <= 0.0:
		_debug_jump_status = "behind"
		_log_v("JUMP_BEHIND", "hit behind citizen | hit=%s pos=%s" % [
			_fmt_v3(hit_point), _fmt_v3(global_position)])
		return false

	var obstacle_height := hit_point.y - global_position.y
	var min_height := maxf(min_jump_obstacle_height, 0.0)
	var max_height := maxf(max_jump_obstacle_height, min_height)
	if obstacle_height < min_height or obstacle_height > max_height:
		_debug_jump_status = "h %.3f" % obstacle_height
		# Only log when the height is at least half the minimum threshold —
		# values below that are floor-surface noise and would spam the log.
		if obstacle_height >= min_height * 0.5:
			_log_v("JUMP_H_OOB", "h=%.3f outside [%.3f,%.3f] collider='%s' | pos=%s" % [
				obstacle_height, min_height, max_height,
				collider.name if collider is Node else "?", _fmt_v3(global_position)])
		return false

	velocity.y = maxf(jump_velocity, 0.0)
	_jump_cooldown_timer = maxf(jump_cooldown, 0.0)
	_debug_jump_status = "jump h %.3f" % obstacle_height
	_log("JUMP_OK", "h=%.3f collider='%s' | pos=%s dir=%s" % [
		obstacle_height, collider.name if collider is Node else "?",
		_fmt_v3(global_position), _fmt_v3(planar_move_direction)])
	return true

func _update_obstacle_down_ray_target(planar_move_direction: Vector3) -> void:
	var probe_distance := maxf(jump_probe_distance, 0.05)
	var drop_distance := maxf(max_jump_obstacle_height + 0.25, 0.3)
	var target_world := _obstacle_down_ray.global_position \
			+ planar_move_direction * probe_distance \
			+ Vector3.DOWN * drop_distance
	_obstacle_down_ray.target_position = _obstacle_down_ray.to_local(target_world)

func _update_avoidance_debug_visual(desired_direction: Vector3, final_direction: Vector3) -> void:
	if not debug_draw_avoidance:
		_clear_avoidance_debug_visual()
		return

	_ensure_avoidance_debug_visual()
	_debug_avoidance_visual.visible = true
	_debug_avoidance_label.visible = true
	_debug_avoidance_mesh.clear_surfaces()
	_debug_avoidance_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _debug_avoidance_material)

	var base := global_position + Vector3.UP * 0.35
	_add_avoidance_debug_line(base, base + desired_direction * 1.1, Color(0.824, 0.122, 0.953, 1.0))
	_add_avoidance_debug_line(base + Vector3.UP * 0.05, base + final_direction * 1.1 + Vector3.UP * 0.05, Color(1.0, 0.85, 0.1, 1.0))
	_draw_local_astar_debug()

	_debug_avoidance_mesh.surface_end()
	_update_avoidance_debug_label()

func _clear_avoidance_debug_visual() -> void:
	if _debug_avoidance_mesh != null:
		_debug_avoidance_mesh.clear_surfaces()
	if _debug_avoidance_visual != null:
		_debug_avoidance_visual.visible = false
	if _debug_avoidance_label != null:
		_debug_avoidance_label.visible = false

func _ensure_avoidance_debug_visual() -> void:
	if _debug_avoidance_material == null:
		_debug_avoidance_material = StandardMaterial3D.new()
		_debug_avoidance_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_debug_avoidance_material.vertex_color_use_as_albedo = true

	if _debug_avoidance_visual == null:
		_debug_avoidance_visual = MeshInstance3D.new()
		_debug_avoidance_visual.name = "AvoidanceDebugVisual"
		_debug_avoidance_visual.mesh = _debug_avoidance_mesh
		add_child(_debug_avoidance_visual)

	if _debug_avoidance_label == null:
		_debug_avoidance_label = Label3D.new()
		_debug_avoidance_label.name = "AvoidanceDebugLabel"
		_debug_avoidance_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_debug_avoidance_label.font_size = 16
		_debug_avoidance_label.pixel_size = 0.01
		add_child(_debug_avoidance_label)

func _add_avoidance_debug_line(from: Vector3, to: Vector3, color: Color) -> void:
	_debug_avoidance_mesh.surface_set_color(color)
	_debug_avoidance_mesh.surface_add_vertex(to_local(from))
	_debug_avoidance_mesh.surface_set_color(color)
	_debug_avoidance_mesh.surface_add_vertex(to_local(to))

func _add_avoidance_debug_cross(center: Vector3, size: float, color: Color) -> void:
	_add_avoidance_debug_line(center - Vector3.RIGHT * size, center + Vector3.RIGHT * size, color)
	_add_avoidance_debug_line(center - Vector3.FORWARD * size, center + Vector3.FORWARD * size, color)
	_add_avoidance_debug_line(center - Vector3.UP * size, center + Vector3.UP * size, color)

func _draw_local_astar_debug() -> void:
	var effective_step := maxf(local_astar_cell_size, 0.08) / float(maxi(local_astar_grid_subdivisions, 1))
	var cell_mark_size := maxf(effective_step * 0.18, 0.012)
	for cell in _debug_local_astar_cells:
		var cell_point: Vector3 = cell.get("point", Vector3.ZERO)
		var cell_blocked := bool(cell.get("blocked", false))
		var blocked_reason := str(cell.get("blocked_reason", ""))
		var cell_color := _get_local_astar_debug_cell_color(cell_blocked, blocked_reason)
		_add_avoidance_debug_cross(cell_point + Vector3.UP * 0.1, cell_mark_size, cell_color)

	if not _local_avoidance_path.is_empty():
		var previous := global_position + Vector3.UP * 0.18
		for point in _local_avoidance_path:
			var next := point + Vector3.UP * 0.18
			_add_avoidance_debug_line(previous, next, Color(0.1, 0.45, 1.0, 1.0))
			previous = next

	if _debug_local_astar_has_goal:
		_add_avoidance_debug_cross(_debug_local_astar_goal + Vector3.UP * 0.22, 0.12, Color(1.0, 1.0, 1.0, 1.0))

func _get_local_astar_debug_cell_color(blocked: bool, blocked_reason: String) -> Color:
	if not blocked:
		return Color(0.0, 0.7, 0.25, 1.0)
	if blocked_reason == "physics":
		return Color(1.0, 0.55, 0.0, 1.0)
	return Color(1.0, 0.0, 0.0, 1.0)

func _update_avoidance_debug_label() -> void:
	var path_label := "-"
	if _is_travelling and not global_path.is_empty():
		path_label = "%d/%d" % [path_index, global_path.size() - 1]

	_debug_avoidance_label.position = Vector3.UP * 1.3
	_debug_avoidance_label.text = "path: %s\navoid: %s\nlocal: %s\njump: %s" % [
		path_label,
		_debug_avoidance_status,
		_debug_local_astar_status,
		_debug_jump_status,
	]
		
# --- Logging helpers ---

## Writes a timestamped log line to the file.
## Format: [HH:MM:SS.mmm] [NodeName] EVENT | details
func _log(event: String, details: String = "") -> void:
	if not enable_file_log:
		return
	var ms := Time.get_ticks_msec()
	var line := "[%02d:%02d:%02d.%03d] [%s] %s%s\n" % [
		(ms / 3600000) % 24,
		(ms / 60000) % 60,
		(ms / 1000) % 60,
		ms % 1000,
		name,
		event,
		(" | " + details) if not details.is_empty() else "",
	]
	var path := log_file_path if not log_file_path.is_empty() else "user://citizen.log"
	var file: FileAccess
	if FileAccess.file_exists(path):
		file = FileAccess.open(path, FileAccess.READ_WRITE)
		if file != null:
			file.seek_end(0)
	else:
		file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("CitizenLog: cannot open '%s' (err %d) — logging disabled" % [
			path, FileAccess.get_open_error()])
		enable_file_log = false
		return
	file.store_string(line)
	file.close()

## Log only when log_verbose is enabled (per-check avoidance, jump ray detail).
func _log_v(event: String, details: String = "") -> void:
	if log_verbose:
		_log(event, details)

## Compact Vector3 → "(x.xx, y.yy, z.zz)" for log lines.
func _fmt_v3(v: Vector3) -> String:
	return "(%.2f,%.2f,%.2f)" % [v.x, v.y, v.z]

# -------------------------------------

@export var show_global_path: bool = true
@export var clear_global_path_on_arrival: bool = false
@export var global_path_line_color: Color = Color(0.1, 0.85, 1.0, 1.0)
@export var global_path_line_y_offset: float = 0.2
@export var global_path_line_width: float = 0.08

var _global_path_mesh: ImmediateMesh = ImmediateMesh.new()
var _global_path_visual: MeshInstance3D = null
var _global_path_material: StandardMaterial3D = null

func _update_global_path_visual() -> void:
	if not show_global_path:
		_clear_global_path_visual()
		return
	if global_path.size() < 2:
		_clear_global_path_visual()
		return

	_ensure_global_path_visual()
	_global_path_mesh.clear_surfaces()
	_global_path_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _global_path_material)
	var draw_from := maxi(path_index, 0)
	for idx in range(draw_from, global_path.size() - 1):
		_add_global_path_segment(global_path[idx], global_path[idx + 1])
	_global_path_mesh.surface_end()

func _clear_global_path_visual() -> void:
	if _global_path_mesh != null:
		_global_path_mesh.clear_surfaces()

func _ensure_global_path_visual() -> void:
	if _global_path_material == null:
		_global_path_material = StandardMaterial3D.new()
		_global_path_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_global_path_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_global_path_material.albedo_color = global_path_line_color

	if _global_path_visual == null:
		_global_path_visual = MeshInstance3D.new()
		_global_path_visual.name = "GlobalPathVisual"
		_global_path_visual.top_level = true
		_global_path_visual.mesh = _global_path_mesh
		add_child(_global_path_visual)
	_global_path_visual.global_transform = Transform3D.IDENTITY

func _path_visual_point(point: Vector3) -> Vector3:
	return point + Vector3.UP * global_path_line_y_offset

func _add_global_path_segment(from: Vector3, to: Vector3) -> void:
	var start := _path_visual_point(from)
	var end := _path_visual_point(to)
	var segment := end - start
	segment.y = 0.0
	if segment.length_squared() <= 0.0001:
		return

	var half_width := maxf(global_path_line_width * 0.5, 0.005)
	var side := segment.normalized().cross(Vector3.UP).normalized() * half_width
	var a := start - side
	var b := start + side
	var c := end + side
	var d := end - side

	_global_path_mesh.surface_add_vertex(a)
	_global_path_mesh.surface_add_vertex(b)
	_global_path_mesh.surface_add_vertex(c)
	_global_path_mesh.surface_add_vertex(a)
	_global_path_mesh.surface_add_vertex(c)
	_global_path_mesh.surface_add_vertex(d)
