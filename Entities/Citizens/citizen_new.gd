extends CharacterBody3D

@export var move_speed: float = 0.5
@export var waypoint_reach_distance: float = 0.18
@export var click_ray_distance: float = 1000.0
@export var ignore_ui_clicks: bool = true
@export_flags_3d_physics var click_collision_mask: int = 0xFFFFFFFF

@export_group("Local Avoidance")
@export var use_obstacle_cast: bool = true
@export_node_path("ShapeCast3D") var obstacle_cast_path: NodePath
@export var obstacle_cast_distance: float = 1.2
@export var obstacle_check_interval: float = 0.08
@export var avoidance_strength: float = 0.9
@export var avoidance_min_hit_distance: float = 0.1
@export var avoidance_slowdown_factor: float = 0.65
@export var steering_smoothing: float = 5.0
@export var avoidance_side_switch_margin: float = 0.12
@export var debug_draw_avoidance: bool = true

@export_group("Local AStar Avoidance")
@export var use_local_astar_avoidance: bool = true
@export var local_astar_radius: float = 1.2
@export var local_astar_cell_size: float = 0.24
@export var local_astar_probe_radius: float = 0.16
@export var local_astar_replan_interval: float = 0.18
@export var local_astar_goal_reach_distance: float = 0.12

@export_group("Low Obstacle Jump")
@export var jump_low_obstacles: bool = true
@export_node_path("RayCast3D") var obstacle_down_ray_path: NodePath
@export var max_jump_obstacle_height: float = 0.1
@export var min_jump_obstacle_height: float = 0.015
@export var jump_velocity: float = 1.8
@export var jump_cooldown: float = 0.35

var global_path: PackedVector3Array = PackedVector3Array()
var path_index: int = 0
var target_position: Vector3 = Vector3.ZERO
var _is_travelling: bool = false

var _gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
var _obstacle_cast: ShapeCast3D = null
var _obstacle_down_ray: RayCast3D = null
var _obstacle_check_timer: float = 0.0
var _jump_cooldown_timer: float = 0.0
var _cached_avoidance_dir: Vector3 = Vector3.ZERO
var _cached_avoidance_blocked: bool = false
var _smoothed_move_direction: Vector3 = Vector3.ZERO
var _last_avoidance_side_bias: int = 0
var _local_avoidance_path: PackedVector3Array = PackedVector3Array()
var _local_avoidance_path_index: int = 0
var _local_astar_replan_timer: float = 0.0
var _local_astar_probe_shape: SphereShape3D = SphereShape3D.new()
var _debug_avoidance_hits: Array[Dictionary] = []
var _debug_avoidance_status: String = "idle"
var _debug_avoidance_side_bias: String = "-"
var _debug_avoidance_left_pressure: float = 0.0
var _debug_avoidance_right_pressure: float = 0.0
var _debug_avoidance_cast_from: Vector3 = Vector3.ZERO
var _debug_avoidance_cast_to: Vector3 = Vector3.ZERO
var _debug_avoidance_has_cast: bool = false
var _debug_avoidance_mesh: ImmediateMesh = ImmediateMesh.new()
var _debug_avoidance_visual: MeshInstance3D = null
var _debug_avoidance_material: StandardMaterial3D = null
var _debug_avoidance_label: Label3D = null
var _debug_local_astar_cells: Array[Dictionary] = []
var _debug_local_astar_status: String = "-"
var _debug_local_astar_goal: Vector3 = Vector3.ZERO
var _debug_local_astar_has_goal: bool = false

func _ready() -> void:
	if obstacle_cast_path != NodePath():
		_obstacle_cast = get_node_or_null(obstacle_cast_path) as ShapeCast3D
	else:
		_obstacle_cast = get_node_or_null("ShapeCast3D") as ShapeCast3D
	if use_obstacle_cast and _obstacle_cast == null:
		push_warning("Citizen: use_obstacle_cast is enabled, but no ShapeCast3D was found.")

	if obstacle_down_ray_path != NodePath():
		_obstacle_down_ray = get_node_or_null(obstacle_down_ray_path) as RayCast3D
	else:
		_obstacle_down_ray = get_node_or_null("ObstacleSensorPivot/ObstacleRayCastDown") as RayCast3D
	if jump_low_obstacles and _obstacle_down_ray == null:
		push_warning("Citizen: jump_low_obstacles is enabled, but ObstacleRayCastDown was not found.")
	elif jump_low_obstacles:
		_obstacle_down_ray.enabled = true

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
	_cached_avoidance_dir = Vector3.ZERO
	_cached_avoidance_blocked = false
	_smoothed_move_direction = Vector3.ZERO
	_last_avoidance_side_bias = 0
	_clear_local_avoidance_path()
	_obstacle_check_timer = 0.0
	if _is_travelling and _is_at_point(global_path[path_index]):
		path_index += 1
	_update_global_path_visual()
	return _is_travelling

func _physics_process(delta: float) -> void:
	_update_jump_cooldown(delta)

	if not _is_travelling:
		_clear_avoidance_debug_visual()
		_apply_idle_gravity(delta)
		move_and_slide()
		return

	if path_index >= global_path.size():
		_clear_avoidance_debug_visual()
		_stop_at_target()
		move_and_slide()
		return

	var waypoint := global_path[path_index]
	if _is_at_point(waypoint):
		path_index += 1
		_clear_local_avoidance_path()
		if path_index >= global_path.size():
			_clear_avoidance_debug_visual()
			_stop_at_target()
			move_and_slide()
			return
		waypoint = global_path[path_index]

	var direction := waypoint - global_position
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
		_try_jump_low_obstacle(final_direction)
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
	_cached_avoidance_dir = Vector3.ZERO
	_cached_avoidance_blocked = false
	_smoothed_move_direction = Vector3.ZERO
	_last_avoidance_side_bias = 0
	_clear_local_avoidance_path()
	velocity = Vector3.ZERO
	_clear_global_path_visual()
	_clear_avoidance_debug_visual()

func is_travelling() -> bool:
	return _is_travelling

func _get_steered_direction(desired_direction: Vector3, delta: float) -> Vector3:
	if not use_obstacle_cast:
		_reset_avoidance_debug_sample("avoidance disabled")
		_last_avoidance_side_bias = 0
		_clear_local_avoidance_path()
		return desired_direction
	if _obstacle_cast == null:
		_reset_avoidance_debug_sample("missing ShapeCast3D")
		_last_avoidance_side_bias = 0
		_clear_local_avoidance_path()
		return desired_direction

	_local_astar_replan_timer -= delta
	var local_path_direction := _get_local_avoidance_path_direction()
	if local_path_direction != Vector3.ZERO:
		_cached_avoidance_blocked = true
		_cached_avoidance_dir = local_path_direction
		_debug_avoidance_status = "local path"
		return local_path_direction

	_obstacle_check_timer -= delta
	if _obstacle_check_timer <= 0.0:
		_update_obstacle_avoidance(desired_direction)
		_obstacle_check_timer = obstacle_check_interval

	if _cached_avoidance_blocked and use_local_astar_avoidance and _local_astar_replan_timer <= 0.0:
		_local_astar_replan_timer = maxf(local_astar_replan_interval, 0.02)
		if _try_build_local_astar_path(desired_direction):
			local_path_direction = _get_local_avoidance_path_direction()
			if local_path_direction != Vector3.ZERO:
				_cached_avoidance_dir = local_path_direction
				_debug_avoidance_status = "local path"
				return local_path_direction
	elif not _cached_avoidance_blocked:
		_clear_local_avoidance_path()

	if _cached_avoidance_dir.length_squared() <= 0.0001:
		return desired_direction
	return _cached_avoidance_dir

func _update_obstacle_avoidance(desired_direction: Vector3) -> void:
	_cached_avoidance_dir = desired_direction
	_cached_avoidance_blocked = false
	_reset_avoidance_debug_sample("checking")

	#_obstacle_cast.target_position = desired_direction * obstacle_cast_distance
	_debug_avoidance_cast_from = _obstacle_cast.global_position
	_debug_avoidance_cast_to = _obstacle_cast.to_global(_obstacle_cast.target_position)
	_debug_avoidance_has_cast = true
	_obstacle_cast.force_shapecast_update()

	if not _obstacle_cast.is_colliding():
		_debug_avoidance_status = "clear"
		_last_avoidance_side_bias = 0
		return

	var left := desired_direction.cross(Vector3.UP).normalized()
	var right := -left
	var repel := Vector3.ZERO
	var left_pressure := 0.0
	var right_pressure := 0.0

	for i in range(_obstacle_cast.get_collision_count()):
		var collider := _obstacle_cast.get_collider(i)
		if collider == self:
			continue

		var hit_point := _obstacle_cast.get_collision_point(i)
		var to_hit := hit_point - global_position
		to_hit.y = 0.0
		var hit_distance = max(to_hit.length(), avoidance_min_hit_distance)
		if hit_distance <= 0.0001:
			continue

		var hit_dir = to_hit / hit_distance
		var forward_dot := desired_direction.dot(hit_dir)
		var side := right.dot(hit_dir)
		var hit_side := "right" if side > 0.0 else "left"
		var hit_record := {
			"point": hit_point,
			"collider": _debug_collider_label(collider),
			"distance": hit_distance,
			"forward": forward_dot,
			"side": hit_side,
			"accepted": false,
			"reason": "behind"
		}
		if forward_dot <= 0.0:
			_debug_avoidance_hits.append(hit_record)
			continue

		_cached_avoidance_blocked = true
		var weight = (1.0 / hit_distance) * forward_dot
		repel -= hit_dir * weight

		if side > 0.0:
			right_pressure += abs(side) * weight
		else:
			left_pressure += abs(side) * weight
		hit_record["accepted"] = true
		hit_record["reason"] = "blocking"
		_debug_avoidance_hits.append(hit_record)

	_debug_avoidance_left_pressure = left_pressure
	_debug_avoidance_right_pressure = right_pressure
	if not _cached_avoidance_blocked:
		_debug_avoidance_status = "hits ignored"
		_last_avoidance_side_bias = 0
		return

	var side_bias := Vector3.ZERO
	var pressure_delta := absf(left_pressure - right_pressure)
	var switch_margin := maxf(avoidance_side_switch_margin, 0.0)
	if pressure_delta <= switch_margin and _last_avoidance_side_bias != 0:
		if _last_avoidance_side_bias < 0:
			side_bias = left
			_debug_avoidance_side_bias = "left (held)"
		else:
			side_bias = right
			_debug_avoidance_side_bias = "right (held)"
	elif left_pressure < right_pressure:
		side_bias = left
		_debug_avoidance_side_bias = "left"
		_last_avoidance_side_bias = -1
	elif right_pressure < left_pressure:
		side_bias = right
		_debug_avoidance_side_bias = "right"
		_last_avoidance_side_bias = 1
	else:
		# Prefer a stable default if both sides are equally blocked.
		side_bias = left
		_debug_avoidance_side_bias = "left (tie)"
		_last_avoidance_side_bias = -1
	_debug_avoidance_status = "blocked"

	var steered := desired_direction + repel + side_bias * avoidance_strength
	steered.y = 0.0
	if steered.length_squared() > 0.0001:
		_cached_avoidance_dir = steered.normalized()
	else:
		_cached_avoidance_dir = desired_direction

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

	if not is_inside_tree() or get_world_3d() == null:
		_debug_local_astar_status = "no world"
		return false

	var forward := desired_direction
	forward.y = 0.0
	if forward.length_squared() <= 0.0001:
		_debug_local_astar_status = "no forward"
		return false
	forward = forward.normalized()

	var right := -forward.cross(Vector3.UP).normalized()
	var cell_size := maxf(local_astar_cell_size, 0.08)
	var radius := maxf(local_astar_radius, cell_size * 2.0)
	var cell_radius := int(ceil(radius / cell_size))
	var origin := global_position
	var start_cell := Vector2i.ZERO
	var start_id := _local_astar_cell_id(start_cell, cell_radius)
	var point_ids: Dictionary = {}
	var astar := AStar2D.new()
	var reference_point := _get_local_astar_global_reference_point(radius)
	var current_reference_distance := _planar_distance(origin, reference_point)

	_debug_local_astar_cells.clear()
	_local_astar_probe_shape.radius = maxf(local_astar_probe_radius, 0.03)

	for z in range(-cell_radius, cell_radius + 1):
		for x in range(-cell_radius, cell_radius + 1):
			var cell := Vector2i(x, z)
			var offset := Vector2(float(x) * cell_size, float(z) * cell_size)
			if offset.length() > radius:
				continue
			if offset.y < -cell_size:
				continue

			var world_point := _local_astar_world_from_offset(origin, right, forward, offset)
			var blocked := _is_local_astar_probe_blocked(world_point)
			if debug_draw_avoidance:
				_debug_local_astar_cells.append({
					"point": world_point,
					"blocked": blocked
				})
			if blocked and cell != start_cell:
				continue

			var point_id := _local_astar_cell_id(cell, cell_radius)
			point_ids[cell] = point_id
			astar.add_point(point_id, offset)

	if not point_ids.has(start_cell):
		_debug_local_astar_status = "blocked start"
		return false

	var neighbors := [
		Vector2i(1, 0),
		Vector2i(-1, 0),
		Vector2i(0, 1),
		Vector2i(0, -1),
		Vector2i(1, 1),
		Vector2i(1, -1),
		Vector2i(-1, 1),
		Vector2i(-1, -1)
	]
	for cell_key in point_ids.keys():
		var cell: Vector2i = cell_key
		var point_id: int = point_ids[cell]
		for neighbor_offset_value in neighbors:
			var neighbor_offset: Vector2i = neighbor_offset_value
			var neighbor_cell := cell + neighbor_offset
			if not point_ids.has(neighbor_cell):
				continue
			if neighbor_offset.x != 0 and neighbor_offset.y != 0:
				if not point_ids.has(Vector2i(cell.x + neighbor_offset.x, cell.y)):
					continue
				if not point_ids.has(Vector2i(cell.x, cell.y + neighbor_offset.y)):
					continue
			var neighbor_id: int = point_ids[neighbor_cell]
			if point_id < neighbor_id:
				astar.connect_points(point_id, neighbor_id, false)

	var best_path := PackedVector2Array()
	var best_score := INF
	for cell_key in point_ids.keys():
		var cell: Vector2i = cell_key
		if cell == start_cell:
			continue

		var candidate_offset := Vector2(float(cell.x) * cell_size, float(cell.y) * cell_size)
		if candidate_offset.y <= 0.0:
			continue
		if candidate_offset.length() < radius - cell_size * 1.5:
			continue

		var goal_id: int = point_ids[cell]
		var candidate_path := astar.get_point_path(start_id, goal_id)
		if candidate_path.size() < 2:
			continue

		var candidate_world := _local_astar_world_from_offset(origin, right, forward, candidate_offset)
		var reference_distance := _planar_distance(candidate_world, reference_point)
		if reference_distance > current_reference_distance + cell_size * 0.25:
			continue

		var path_length := _local_astar_path_length(candidate_path)
		var forward_progress := candidate_offset.y / radius
		var score := reference_distance + path_length * 0.2 - forward_progress * 0.15
		if score < best_score:
			best_score = score
			best_path = candidate_path

	if best_path.size() < 2:
		_debug_local_astar_status = "no reachable edge"
		return false

	for idx in range(1, best_path.size()):
		_local_avoidance_path.append(_local_astar_world_from_offset(origin, right, forward, best_path[idx]))
	_local_avoidance_path_index = 0
	_debug_local_astar_goal = _local_avoidance_path[_local_avoidance_path.size() - 1]
	_debug_local_astar_has_goal = true
	_debug_local_astar_status = "path %d" % _local_avoidance_path.size()
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
	return Vector3.ZERO

func _clear_local_avoidance_path() -> void:
	_local_avoidance_path = PackedVector3Array()
	_local_avoidance_path_index = 0
	_debug_local_astar_goal = Vector3.ZERO
	_debug_local_astar_has_goal = false
	if _debug_local_astar_status != "planning":
		_debug_local_astar_status = "-"

func _local_astar_cell_id(cell: Vector2i, cell_radius: int) -> int:
	var width := cell_radius * 2 + 1
	return (cell.y + cell_radius) * width + cell.x + cell_radius + 1

func _local_astar_world_from_offset(origin: Vector3, right: Vector3, forward: Vector3, offset: Vector2) -> Vector3:
	var point := origin + right * offset.x + forward * offset.y
	point.y = origin.y
	return point

func _is_local_astar_probe_blocked(point: Vector3) -> bool:
	if get_world_3d() == null:
		return true

	var probe_position := point
	if _obstacle_cast != null:
		probe_position.y = _obstacle_cast.global_position.y
	else:
		probe_position.y = global_position.y + 0.35

	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _local_astar_probe_shape
	query.transform = Transform3D(Basis.IDENTITY, probe_position)
	query.collision_mask = _get_local_astar_collision_mask()
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [get_rid()]

	return not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _get_local_astar_collision_mask() -> int:
	if _obstacle_cast != null and _obstacle_cast.collision_mask != 0:
		return _obstacle_cast.collision_mask
	return collision_mask

func _get_local_astar_global_reference_point(radius: float) -> Vector3:
	if global_path.is_empty():
		return target_position
	var reference_index := clampi(path_index, 0, global_path.size() - 1)
	var min_distance := maxf(radius, waypoint_reach_distance)
	while reference_index < global_path.size() - 1:
		if _planar_distance(global_position, global_path[reference_index]) >= min_distance:
			break
		reference_index += 1
	return global_path[reference_index]

func _local_astar_path_length(path: PackedVector2Array) -> float:
	var total := 0.0
	for idx in range(path.size() - 1):
		total += path[idx].distance_to(path[idx + 1])
	return total

func _planar_distance(a: Vector3, b: Vector3) -> float:
	var offset := a - b
	offset.y = 0.0
	return offset.length()

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

func _is_at_point(point: Vector3) -> bool:
	var offset := point - global_position
	offset.y = 0.0
	return offset.length() <= waypoint_reach_distance

func _stop_at_target() -> void:
	_is_travelling = false
	_cached_avoidance_dir = Vector3.ZERO
	_cached_avoidance_blocked = false
	_smoothed_move_direction = Vector3.ZERO
	_last_avoidance_side_bias = 0
	velocity.x = 0.0
	velocity.z = 0.0
	if clear_global_path_on_arrival:
		_clear_global_path_visual()
	_clear_avoidance_debug_visual()

func _apply_idle_gravity(delta: float) -> void:
	if is_on_floor():
		if velocity.y < 0.0:
			velocity.y = 0.0
	else:
		velocity.y -= _gravity * delta

func _update_jump_cooldown(delta: float) -> void:
	if _jump_cooldown_timer > 0.0:
		_jump_cooldown_timer = maxf(_jump_cooldown_timer - delta, 0.0)

func _try_jump_low_obstacle(move_direction: Vector3) -> bool:
	if not jump_low_obstacles:
		return false
	if _obstacle_down_ray == null or not _obstacle_down_ray.enabled:
		return false
	if _jump_cooldown_timer > 0.0 or not is_on_floor():
		return false
	if not _obstacle_down_ray.is_colliding():
		return false

	var collider := _obstacle_down_ray.get_collider()
	if collider == self:
		return false

	var hit_point := _obstacle_down_ray.get_collision_point()
	var to_hit := hit_point - global_position
	to_hit.y = 0.0
	var planar_move_direction := move_direction
	planar_move_direction.y = 0.0
	if planar_move_direction.length_squared() > 0.0001 and to_hit.length_squared() > 0.0001:
		if planar_move_direction.normalized().dot(to_hit.normalized()) <= 0.0:
			return false

	var obstacle_height := hit_point.y - global_position.y
	var min_height := maxf(min_jump_obstacle_height, 0.0)
	var max_height := maxf(max_jump_obstacle_height, min_height)
	if obstacle_height < min_height or obstacle_height > max_height:
		return false

	velocity.y = maxf(jump_velocity, 0.0)
	_jump_cooldown_timer = maxf(jump_cooldown, 0.0)
	return true

func _reset_avoidance_debug_sample(status: String) -> void:
	_debug_avoidance_hits.clear()
	_debug_avoidance_status = status
	_debug_avoidance_side_bias = "-"
	_debug_avoidance_left_pressure = 0.0
	_debug_avoidance_right_pressure = 0.0
	_debug_avoidance_cast_from = Vector3.ZERO
	_debug_avoidance_cast_to = Vector3.ZERO
	_debug_avoidance_has_cast = false
	if _local_avoidance_path.is_empty():
		_debug_local_astar_cells.clear()
		_debug_local_astar_status = "-"
		_debug_local_astar_goal = Vector3.ZERO
		_debug_local_astar_has_goal = false

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
	if _debug_avoidance_has_cast:
		var cast_color := Color(1.0, 0.2, 0.1, 1.0) if _cached_avoidance_blocked else Color(0.1, 1.0, 0.25, 1.0)
		_add_avoidance_debug_line(_debug_avoidance_cast_from, _debug_avoidance_cast_to, cast_color)

	for hit in _debug_avoidance_hits:
		var hit_point: Vector3 = hit.get("point", Vector3.ZERO)
		var hit_color := Color(1.0, 0.1, 0.1, 1.0) if bool(hit.get("accepted", false)) else Color(0.55, 0.55, 0.55, 1.0)
		_add_avoidance_debug_cross(hit_point + Vector3.UP * 0.06, 0.08, hit_color)
	_draw_local_astar_debug()

	_debug_avoidance_mesh.surface_end()
	_debug_avoidance_visual.global_transform = Transform3D.IDENTITY
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
		_debug_avoidance_visual.top_level = true
		_debug_avoidance_visual.mesh = _debug_avoidance_mesh
		add_child(_debug_avoidance_visual)

	if _debug_avoidance_label == null:
		_debug_avoidance_label = Label3D.new()
		_debug_avoidance_label.name = "AvoidanceDebugLabel"
		_debug_avoidance_label.top_level = true
		_debug_avoidance_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_debug_avoidance_label.font_size = 16
		_debug_avoidance_label.pixel_size = 0.01
		add_child(_debug_avoidance_label)

func _add_avoidance_debug_line(from: Vector3, to: Vector3, color: Color) -> void:
	_debug_avoidance_mesh.surface_set_color(color)
	_debug_avoidance_mesh.surface_add_vertex(from)
	_debug_avoidance_mesh.surface_set_color(color)
	_debug_avoidance_mesh.surface_add_vertex(to)

func _add_avoidance_debug_cross(center: Vector3, size: float, color: Color) -> void:
	_add_avoidance_debug_line(center - Vector3.RIGHT * size, center + Vector3.RIGHT * size, color)
	_add_avoidance_debug_line(center - Vector3.FORWARD * size, center + Vector3.FORWARD * size, color)
	_add_avoidance_debug_line(center - Vector3.UP * size, center + Vector3.UP * size, color)

func _draw_local_astar_debug() -> void:
	var cell_mark_size := maxf(local_astar_cell_size * 0.18, 0.025)
	for cell in _debug_local_astar_cells:
		var cell_point: Vector3 = cell.get("point", Vector3.ZERO)
		var cell_blocked := bool(cell.get("blocked", false))
		var cell_color := Color(1.0, 0.0, 0.0, 1.0) if cell_blocked else Color(0.0, 0.7, 0.25, 1.0)
		_add_avoidance_debug_cross(cell_point + Vector3.UP * 0.1, cell_mark_size, cell_color)

	if not _local_avoidance_path.is_empty():
		var previous := global_position + Vector3.UP * 0.18
		for point in _local_avoidance_path:
			var next := point + Vector3.UP * 0.18
			_add_avoidance_debug_line(previous, next, Color(0.1, 0.45, 1.0, 1.0))
			previous = next

	if _debug_local_astar_has_goal:
		_add_avoidance_debug_cross(_debug_local_astar_goal + Vector3.UP * 0.22, 0.12, Color(1.0, 1.0, 1.0, 1.0))

func _update_avoidance_debug_label() -> void:
	var accepted_hits := 0
	for hit in _debug_avoidance_hits:
		if bool(hit.get("accepted", false)):
			accepted_hits += 1

	_debug_avoidance_label.global_position = global_position + Vector3.UP * 1.3
	_debug_avoidance_label.text = "avoid: %s\nturn: %s\nlocal: %s\npressure L %.2f R %.2f\nhits %d/%d" % [
		_debug_avoidance_status,
		_debug_avoidance_side_bias,
		_debug_local_astar_status,
		_debug_avoidance_left_pressure,
		_debug_avoidance_right_pressure,
		accepted_hits,
		_debug_avoidance_hits.size()
	]

func _debug_collider_label(collider: Variant) -> String:
	if collider is Node:
		return str((collider as Node).name)
	return str(collider)
		
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
	for idx in range(global_path.size() - 1):
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
