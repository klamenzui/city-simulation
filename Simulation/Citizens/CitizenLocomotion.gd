extends RefCounted
class_name CitizenLocomotion

const SimLogger = preload("res://Simulation/Logging/SimLogger.gd")

func setup(citizen) -> void:
	if citizen == null:
		return
	citizen._setup_navigation()

func physics_step(citizen, delta: float, world) -> void:
	if citizen == null:
		return
	if world != null and world.is_paused:
		return
	if citizen.has_method("has_active_rest_pose") and citizen.has_active_rest_pose():
		citizen.apply_rest_pose()
		return
	if citizen.has_method("is_inside_building") and citizen.is_inside_building():
		citizen.velocity = Vector3.ZERO
		return
	if citizen._is_travelling:
		citizen._move_along_path(delta)
	else:
		citizen.velocity.x = 0.0
		citizen.velocity.z = 0.0
		if citizen.is_on_floor():
			if citizen.velocity.y < 0.0:
				citizen.velocity.y = 0.0
		else:
			citizen.velocity.y = maxf(citizen.velocity.y - citizen.gravity_strength * delta, -citizen.max_fall_speed)
		citizen.move_and_slide()

func set_position_grounded(citizen, pos: Vector3, world) -> void:
	if citizen == null:
		return
	citizen._vertical_speed = 0.0
	citizen._stuck_timer = 0.0
	citizen.velocity = Vector3.ZERO
	citizen.global_position = citizen._project_to_ground(pos)
	citizen._last_move_position = citizen.global_position
	if world != null:
		citizen._ground_fallback_y = world.get_ground_fallback_y()
	else:
		citizen._ground_fallback_y = citizen.global_position.y

func begin_travel_to(citizen, target_pos: Vector3, target_building, world) -> bool:
	if citizen == null:
		return false

	citizen._setup_navigation()
	citizen._travel_target_building = target_building
	citizen._arrived_via_entrance_contact = false
	if world != null:
		citizen._ground_fallback_y = world.get_ground_fallback_y()

	var route_start = citizen.global_position
	var grounded_start = citizen._project_to_ground(route_start)
	var route_target := target_pos
	var internal_route := PackedVector3Array()
	if target_building != null and citizen.has_method("get_navigation_points_for_building"):
		var nav_points: Dictionary = citizen.get_navigation_points_for_building(target_building, world)
		if target_building.has_method("get_internal_navigation_route"):
			internal_route = target_building.get_internal_navigation_route(nav_points)
			if not internal_route.is_empty():
				route_target = nav_points.get("access", target_pos)
	var grounded_target = citizen._project_to_ground(route_target)

	citizen._debug_last_travel_route = PackedVector3Array()
	citizen._debug_last_travel_failed = false

	var route := PackedVector3Array()
	var used_pedestrian_path := false
	if world != null and world.has_method("get_pedestrian_path"):
		used_pedestrian_path = true
		if world.has_method("has_pedestrian_route") and not world.has_pedestrian_route(route_start, route_target, citizen.current_location, target_building):
			route = PackedVector3Array()
		else:
			route = world.get_pedestrian_path(route_start, route_target, citizen.current_location, target_building)
		if route.size() < 2 and world.has_method("get_navigation_path"):
			route = world.get_navigation_path(route_start, route_target)
	elif world != null and world.has_method("get_road_path"):
		route = world.get_road_path(route_start, route_target)

	if route.size() < 2:
		if used_pedestrian_path:
			citizen._is_travelling = false
			citizen._travel_route = PackedVector3Array()
			citizen._travel_route_index = -1
			citizen._travel_target = grounded_start
			citizen._repath_time_left = 0.0
			citizen._current_speed = 0.0
			citizen._debug_last_travel_route = PackedVector3Array([grounded_start, citizen._project_to_ground(target_pos)])
			citizen._debug_last_travel_failed = true
			if citizen._nav_agent != null:
				citizen._nav_agent.target_position = citizen.global_position
			return false
		else:
			var fallback_start = route_start
			var fallback_end := route_target
			if world != null and world.has_method("get_pedestrian_access_point"):
				fallback_start = world.get_pedestrian_access_point(route_start)
				fallback_end = world.get_pedestrian_access_point(route_target)
			route.append(fallback_start)
			route.append(fallback_end)

	route = _append_internal_route_points(route, internal_route)
	if not internal_route.is_empty():
		grounded_target = citizen._project_to_ground(internal_route[internal_route.size() - 1])

	citizen._travel_route = route
	citizen._travel_route_index = 0
	citizen._is_travelling = true
	citizen._repath_time_left = 0.0
	citizen._current_speed = 0.0
	citizen._debug_last_travel_route = route

	if not citizen._advance_travel_route():
		citizen._travel_target = citizen._project_to_ground(target_pos)
		if citizen._nav_agent != null:
			citizen._nav_agent.target_position = citizen._travel_target
		return false

	return true

func _append_internal_route_points(route: PackedVector3Array, internal_route: PackedVector3Array) -> PackedVector3Array:
	if internal_route.is_empty():
		return route

	var combined := PackedVector3Array(route)
	for point in internal_route:
		if combined.is_empty() or combined[combined.size() - 1].distance_to(point) > 0.18:
			combined.append(point)
	return combined

func repath_current_travel(citizen, world) -> bool:
	if citizen == null or not citizen._is_travelling:
		return false
	if citizen._repath_time_left > 0.0:
		return false

	var final_target: Vector3 = citizen._travel_target
	if not citizen._travel_route.is_empty():
		final_target = citizen._travel_route[citizen._travel_route.size() - 1]

	var old_is_travelling: bool = citizen._is_travelling
	var old_route: PackedVector3Array = citizen._travel_route
	var old_route_index: int = citizen._travel_route_index
	var old_target: Vector3 = citizen._travel_target
	var old_debug_route: PackedVector3Array = citizen._debug_last_travel_route
	var old_debug_failed: bool = citizen._debug_last_travel_failed
	var old_current_speed: float = citizen._current_speed
	var old_arrived: bool = citizen._arrived_via_entrance_contact
	var old_target_building = citizen._travel_target_building

	if not begin_travel_to(citizen, final_target, old_target_building, world):
		citizen._is_travelling = old_is_travelling
		citizen._travel_route = old_route
		citizen._travel_route_index = old_route_index
		citizen._travel_target = old_target
		citizen._debug_last_travel_route = old_debug_route
		citizen._debug_last_travel_failed = old_debug_failed
		citizen._current_speed = old_current_speed
		citizen._arrived_via_entrance_contact = old_arrived
		citizen._travel_target_building = old_target_building
		citizen._repath_time_left = citizen.repath_interval_sec
		if citizen._nav_agent != null:
			citizen._nav_agent.target_position = old_target
		return false

	citizen._stuck_timer = 0.0
	citizen._last_move_position = citizen.global_position
	citizen._repath_time_left = citizen.repath_interval_sec
	citizen._current_speed = minf(citizen._current_speed, citizen._walk_speed * 0.5)
	SimLogger.log("[Citizen %s] Repath current travel from %s to %s" % [
		citizen.citizen_name,
		citizen._trace_fmt_vec3(citizen.global_position),
		citizen._trace_fmt_vec3(final_target)
	])
	return true

func has_reached_travel_target(citizen) -> bool:
	if citizen == null:
		return true
	if citizen._arrived_via_entrance_contact:
		return true
	if citizen._is_travelling and citizen._travel_route_index < citizen._travel_route.size() - 1:
		return false
	var to_target: Vector3 = citizen._travel_target - citizen.global_position
	to_target.y = 0.0
	return to_target.length() <= citizen.final_arrival_distance

func stop_travel(citizen) -> void:
	if citizen == null:
		return
	if citizen.is_inside_tree() and citizen._inside_building == null:
		citizen.global_position = citizen._project_to_ground(citizen.global_position)
		citizen._last_move_position = citizen.global_position
	citizen._is_travelling = false
	citizen._current_speed = 0.0
	citizen._arrived_via_entrance_contact = false
	citizen._travel_target_building = null
	citizen._stuck_timer = 0.0
	citizen._last_move_position = citizen.global_position
	citizen._vertical_speed = 0.0
	citizen.velocity = Vector3.ZERO
	citizen._travel_route = PackedVector3Array()
	citizen._travel_route_index = -1
	citizen._repath_time_left = 0.0
	if citizen._nav_agent != null:
		citizen._nav_agent.target_position = citizen.global_position
