extends RefCounted
class_name CitizenLocomotion

func setup(citizen) -> void:
	if citizen == null:
		return
	citizen._setup_navigation()

func physics_step(citizen, delta: float, world) -> void:
	if citizen == null:
		return
	if world != null and world.is_paused:
		return
	if citizen._is_travelling:
		citizen._move_along_path(delta)
	else:
		citizen.global_position = citizen._apply_grounding(citizen.global_position, delta)

func set_position_grounded(citizen, pos: Vector3, world) -> void:
	if citizen == null:
		return
	citizen._vertical_speed = 0.0
	citizen.global_position = citizen._project_to_ground(pos)
	if world != null:
		citizen._ground_fallback_y = world.get_ground_fallback_y()
	else:
		citizen._ground_fallback_y = citizen.global_position.y

func begin_travel_to(citizen, target_pos: Vector3, target_building, world) -> bool:
	if citizen == null:
		return false

	citizen._setup_navigation()
	if world != null:
		citizen._ground_fallback_y = world.get_ground_fallback_y()

	var route_start = citizen.global_position
	var grounded_start = citizen._project_to_ground(route_start)
	var grounded_target = citizen._project_to_ground(target_pos)

	citizen._debug_last_travel_route = PackedVector3Array()
	citizen._debug_last_travel_failed = false

	var route := PackedVector3Array()
	var used_pedestrian_path := false
	if world != null and world.has_method("get_pedestrian_path"):
		used_pedestrian_path = true
		if world.has_method("has_pedestrian_route") and not world.has_pedestrian_route(route_start, target_pos, citizen.current_location, target_building):
			route = PackedVector3Array()
		else:
			route = world.get_pedestrian_path(route_start, target_pos, citizen.current_location, target_building)
		if route.size() < 2 and world.has_method("get_navigation_path"):
			route = world.get_navigation_path(route_start, target_pos)
	elif world != null and world.has_method("get_road_path"):
		route = world.get_road_path(route_start, target_pos)

	if route.size() < 2:
		if used_pedestrian_path:
			citizen._is_travelling = false
			citizen._travel_route = PackedVector3Array()
			citizen._travel_route_index = -1
			citizen._travel_target = grounded_start
			citizen._repath_time_left = 0.0
			citizen._current_speed = 0.0
			citizen._debug_last_travel_route = PackedVector3Array([grounded_start, grounded_target])
			citizen._debug_last_travel_failed = true
			if citizen._nav_agent != null:
				citizen._nav_agent.target_position = citizen.global_position
			return false
		else:
			var fallback_start = route_start
			var fallback_end := target_pos
			if world != null and world.has_method("get_pedestrian_access_point"):
				fallback_start = world.get_pedestrian_access_point(route_start)
				fallback_end = world.get_pedestrian_access_point(target_pos)
			route.append(fallback_start)
			route.append(fallback_end)

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

func has_reached_travel_target(citizen) -> bool:
	if citizen == null:
		return true
	if citizen._is_travelling and citizen._travel_route_index < citizen._travel_route.size() - 1:
		return false
	var to_target: Vector3 = citizen._travel_target - citizen.global_position
	to_target.y = 0.0
	return to_target.length() <= citizen.final_arrival_distance

func stop_travel(citizen) -> void:
	if citizen == null:
		return
	citizen._is_travelling = false
	citizen._current_speed = 0.0
	citizen._travel_route = PackedVector3Array()
	citizen._travel_route_index = -1
	if citizen._nav_agent != null:
		citizen._nav_agent.target_position = citizen.global_position
