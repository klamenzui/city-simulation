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

func begin_travel_to(citizen, target_pos: Vector3, world) -> void:
	if citizen == null:
		return
	citizen._setup_navigation()
	if world != null:
		citizen._ground_fallback_y = world.get_ground_fallback_y()
	citizen._travel_target = citizen._project_to_ground(target_pos)
	citizen._is_travelling = true
	citizen._repath_time_left = 0.0
	citizen._current_speed = 0.0
	citizen._nav_agent.target_position = citizen._travel_target

func has_reached_travel_target(citizen) -> bool:
	if citizen == null:
		return true
	if not citizen._is_travelling:
		return true
	var to_target: Vector3 = citizen._travel_target - citizen.global_position
	to_target.y = 0.0
	return to_target.length() <= citizen.arrival_distance

func stop_travel(citizen) -> void:
	if citizen == null:
		return
	citizen._is_travelling = false
	citizen._current_speed = 0.0
	if citizen._nav_agent != null:
		citizen._nav_agent.target_position = citizen.global_position