extends VehicleBody3D
class_name VehicleAgent

signal trip_completed(vehicle: VehicleAgent, driver: Citizen, target_building: Building)
signal driver_entered(vehicle: VehicleAgent, driver: Citizen)
signal driver_exited(vehicle: VehicleAgent, driver: Citizen)

const BalanceConfig = preload("res://Simulation/Config/BalanceConfig.gd")
const DEFAULT_ENGINE_AUDIO_PATH := "res://environment/audio/vehicles/engine.wav"
const DEFAULT_IMPACT_AUDIO_PATH := "res://environment/audio/vehicles/impact_1.wav"
const TRAFFIC_LIGHT_GROUP := "traffic_lights"
const VEHICLE_COLLISION_LAYER := 4
const VEHICLE_WORLD_AND_VEHICLE_MASK := 5
const ARRIVAL_EXIT_MAX_ACCESS_DISTANCE := 8.0

@export var delivery_vehicle: bool = true
@export var max_speed: float = 5.0
@export var acceleration: float = 2.8
@export var braking_acceleration: float = 5.5
@export var braking_distance: float = 2.2
@export var turn_speed: float = 5.0
@export var waypoint_reach_distance: float = 0.45
@export var forward_yaw_offset: float = 0.0
@export var use_balance_vehicle_geometry: bool = true
@export var vehicle_mass: float = 35.0
@export var center_of_mass_offset: Vector3 = Vector3(0.0, 0.12, -0.45)
@export var manual_drive_enabled: bool = true
@export var manual_engine_force: float = 40.0
@export var manual_reverse_force_multiplier: float = 1.7
@export var manual_brake_strength: float = 2.2
@export var manual_parking_brake: float = 6.0
@export var manual_steer_speed: float = 1.5
@export var manual_steer_limit: float = 0.42
@export var manual_max_speed: float = 4.5
@export var manual_reverse_speed: float = 2.0
@export var manual_low_speed_force_boost: float = 2.5
@export var manual_forward_engine_sign: float = 1.0
@export var wheel_track_half_width: float = 0.26
@export var wheel_front_z: float = 0.04
@export var wheel_rear_z: float = -1.0
@export var wheel_mount_y: float = 0.16
@export var wheel_radius: float = 0.155
@export var wheel_roll_influence: float = 0.28
@export var wheel_friction_slip: float = 1.25
@export var suspension_stiffness: float = 20.0
@export var suspension_travel: float = 0.16
@export var damping_compression: float = 1.0
@export var damping_relaxation: float = 1.8
@export var collision_shape_size: Vector3 = Vector3(0.63, 0.42, 1.74)
@export var collision_shape_offset: Vector3 = Vector3(0.0, 0.2325, -0.735)
@export var ground_snap_enabled: bool = true
@export var ground_probe_up: float = 2.0
@export var ground_probe_down: float = 8.0
@export var ground_height_offset: float = 0.0
@export var ground_snap_speed: float = 30.0
@export var ground_min_normal_y: float = 0.45
@export_flags_3d_physics var ground_collision_mask: int = 1
@export_flags_3d_physics var vehicle_collision_layer: int = VEHICLE_COLLISION_LAYER
@export_flags_3d_physics var vehicle_collision_mask: int = VEHICLE_WORLD_AND_VEHICLE_MASK
@export var route_vehicle_avoidance_enabled: bool = true
@export var route_vehicle_detection_distance: float = 4.5
@export var route_vehicle_lateral_tolerance: float = 0.9
@export var route_vehicle_stop_distance: float = 1.7
@export var route_vehicle_slowdown_distance: float = 3.2
@export var obey_traffic_lights: bool = true
@export var traffic_light_detection_distance: float = 6.0
@export var traffic_light_lateral_tolerance: float = 0.85
@export var traffic_light_stop_distance: float = 0.95
@export var traffic_light_slowdown_distance: float = 3.0
@export var vehicle_audio_enabled: bool = true
@export var engine_audio_path: String = DEFAULT_ENGINE_AUDIO_PATH
@export var impact_audio_path: String = DEFAULT_IMPACT_AUDIO_PATH
@export var engine_audio_min_pitch: float = 0.05
@export var engine_audio_pitch_per_speed: float = 0.08
@export var engine_audio_idle_volume_db: float = -28.0
@export var engine_audio_drive_volume_db: float = -11.0
@export var engine_audio_lerp_speed: float = 8.0
@export var impact_speed_delta_threshold: float = 1.8
@export var impact_min_interval: float = 0.35
@export var impact_contact_linger_sec: float = 0.18
@export var impact_side_normal_max_y: float = 0.45

var current_driver: Citizen = null
var target_building: Building = null
var target_position: Vector3 = Vector3.ZERO
var last_vehicle_route: PackedVector3Array = PackedVector3Array()
var last_path_failed: bool = false

var _route_index: int = 0
var _current_speed: float = 0.0
var _is_driving: bool = false
var _arrival_exit_position: Vector3 = Vector3.INF
var _manual_physics_active: bool = false
var _steer_target: float = 0.0
var _engine_sound_player: AudioStreamPlayer3D = null
var _impact_sound_player: AudioStreamPlayer3D = null
var _previous_audio_speed: float = 0.0
var _impact_audio_cooldown: float = 0.0
var _impact_contact_linger: float = 0.0
var _registered_world: World = null
var _waiting_for_traffic_light: bool = false
var _waiting_for_vehicle: bool = false
var _unboard_driver_on_trip_finish: bool = true


func _ready() -> void:
	add_to_group("vehicles")
	if delivery_vehicle:
		add_to_group("delivery_vehicles")
	_apply_balance_settings()
	_configure_rigid_body()
	_ensure_vehicle_collision_shape()
	_ensure_vehicle_wheels()
	_ensure_manual_drive_input_actions()
	_ensure_vehicle_audio()
	_ensure_marker("EntryPoint", Vector3(0.3675, 0.0075, -0.0975))
	_ensure_marker("SeatPoint", Vector3(0.12, 0.3375, -0.0825))
	_set_manual_physics_active(false)
	set_physics_process(true)
	call_deferred("_register_with_world")
	call_deferred("_snap_to_ground_now")


func _exit_tree() -> void:
	_unregister_from_world()
	if _engine_sound_player != null:
		_engine_sound_player.stop()
		_engine_sound_player.stream = null
	if _impact_sound_player != null:
		_impact_sound_player.stop()
		_impact_sound_player.stream = null
	_engine_sound_player = null
	_impact_sound_player = null


func _physics_process(delta: float) -> void:
	advance_vehicle_simulation(delta)
	_update_vehicle_audio(delta)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	_record_impact_contacts(state)
	_pin_current_driver_to_vehicle_transform(state.transform)


func assign_delivery_driver(citizen: Citizen, delivery_target: Building, world: World = null) -> bool:
	if delivery_target == null:
		return false
	return assign_delivery_driver_to_position(citizen, delivery_target.get_entrance_pos(), world, delivery_target)


func assign_delivery_driver_to_position(
	citizen: Citizen,
	delivery_target_pos: Vector3,
	world: World = null,
	delivery_target: Building = null
) -> bool:
	if citizen == null:
		return false
	if current_driver != null and current_driver != citizen:
		return false
	if not board_driver(citizen):
		return false
	target_building = delivery_target
	target_position = delivery_target_pos
	_arrival_exit_position = _resolve_arrival_exit_position(world, delivery_target_pos, delivery_target)
	return start_drive_to(delivery_target_pos, world)


func board_driver(citizen: Citizen) -> bool:
	if citizen == null:
		return false
	if current_driver != null and current_driver != citizen:
		return false
	current_driver = citizen
	if citizen.has_method("enter_vehicle"):
		citizen.enter_vehicle(self, get_seat_point_global())
	else:
		citizen.stop_travel()
		citizen.hide()
		citizen.collision_layer = 0
		citizen.collision_mask = 0
	_pin_current_driver_to_seat()
	if _should_process_manual_driver_input():
		_set_manual_physics_active(true)
	driver_entered.emit(self, citizen)
	return true


func unboard_driver(world: World = null, exit_pos: Vector3 = Vector3.INF) -> Citizen:
	var driver := current_driver
	if driver == null:
		return null
	var resolved_exit := exit_pos
	if not _is_finite_vector(resolved_exit):
		resolved_exit = _arrival_exit_position if _is_finite_vector(_arrival_exit_position) else get_entry_point_global()
	if driver.has_method("exit_vehicle"):
		driver.exit_vehicle(resolved_exit, world)
	else:
		driver.show()
		if driver.has_method("set_position_grounded"):
			driver.set_position_grounded(resolved_exit)
		else:
			driver.global_position = resolved_exit
	current_driver = null
	_current_speed = 0.0
	_set_manual_physics_active(false)
	driver_exited.emit(self, driver)
	return driver


func start_drive_to(destination: Vector3, world: World = null) -> bool:
	return _start_drive_to(destination, world, true)


func start_drive_to_keep_driver(destination: Vector3, world: World = null) -> bool:
	return _start_drive_to(destination, world, false)


func _start_drive_to(destination: Vector3, world: World = null, unboard_driver_on_finish: bool = true) -> bool:
	target_position = destination
	last_path_failed = false
	_unboard_driver_on_trip_finish = unboard_driver_on_finish
	if current_driver != null:
		_arrival_exit_position = _resolve_arrival_exit_position(world, destination, target_building)
	last_vehicle_route = _build_vehicle_route(destination, world)
	if last_vehicle_route.size() < 2:
		last_path_failed = true
		_route_index = -1
		_current_speed = 0.0
		_is_driving = false
		_waiting_for_traffic_light = false
		_waiting_for_vehicle = false
		_set_manual_physics_active(false)
		_unboard_driver_on_trip_finish = true
		if current_driver != null:
			unboard_driver(world, get_entry_point_global())
		return false
	_snap_to_route_start_if_needed(last_vehicle_route)
	_route_index = 1
	_current_speed = 0.0
	_is_driving = last_vehicle_route.size() >= 2
	_waiting_for_traffic_light = false
	_waiting_for_vehicle = false
	_set_manual_physics_active(false)
	if not _is_driving:
		_finish_trip(world)
	return _is_driving


func stop_vehicle() -> void:
	_current_speed = 0.0
	_is_driving = false
	_route_index = -1
	_waiting_for_traffic_light = false
	_waiting_for_vehicle = false
	engine_force = 0.0
	brake = manual_parking_brake


func is_driving() -> bool:
	return _is_driving


func is_manual_driving() -> bool:
	return _should_process_manual_driver_input() and (linear_velocity.length() > 0.05 or absf(engine_force) > 0.01)


func has_arrived() -> bool:
	return not _is_driving


func is_waiting_at_traffic_light() -> bool:
	return _waiting_for_traffic_light


func is_waiting_for_vehicle() -> bool:
	return _waiting_for_vehicle


func get_entry_point_global() -> Vector3:
	var point := get_node_or_null("EntryPoint") as Node3D
	if point != null:
		return point.global_position
	return global_position


func get_seat_point_global() -> Vector3:
	var point := get_node_or_null("SeatPoint") as Node3D
	if point != null:
		return point.global_position
	return global_position


func advance_vehicle_simulation(delta: float) -> void:
	if delta <= 0.0:
		return
	if _is_driving:
		_set_manual_physics_active(false)
		_snap_to_ground(delta, false)
		_advance_route_drive(delta)
		_snap_to_ground(delta, false)
		return
	if _should_process_manual_driver_input():
		_set_manual_physics_active(true)
		_advance_manual_drive(delta)
		_pin_current_driver_to_seat()
		return
	_set_manual_physics_active(false)
	_snap_to_ground(delta, false)
	_pin_current_driver_to_seat()


func _advance_route_drive(delta: float) -> void:
	if _route_index < 0 or _route_index >= last_vehicle_route.size():
		_finish_trip(_resolve_world_from_tree())
		return
	_waiting_for_traffic_light = false
	_waiting_for_vehicle = false

	var waypoint := last_vehicle_route[_route_index]
	var to_waypoint := waypoint - global_position
	to_waypoint.y = 0.0
	var distance := to_waypoint.length()
	while distance <= waypoint_reach_distance and _route_index < last_vehicle_route.size() - 1:
		_route_index += 1
		waypoint = last_vehicle_route[_route_index]
		to_waypoint = waypoint - global_position
		to_waypoint.y = 0.0
		distance = to_waypoint.length()

	if _route_index >= last_vehicle_route.size() - 1 and distance <= waypoint_reach_distance:
		var arrival_motion := Vector3(waypoint.x - global_position.x, 0.0, waypoint.z - global_position.z)
		_move_vehicle_kinematic(arrival_motion)
		if _planar_distance(global_position, waypoint) <= waypoint_reach_distance:
			_finish_trip(_resolve_world_from_tree())
		return
	if distance <= 0.001:
		return

	var direction := to_waypoint.normalized()
	_rotate_towards(direction, delta)

	var remaining := _remaining_route_distance(distance)
	var desired_speed := max_speed
	if remaining <= braking_distance:
		desired_speed = max_speed * clampf(remaining / maxf(braking_distance, 0.01), 0.18, 1.0)
	var blocking_light := _find_blocking_traffic_light(direction)
	var stop_line_distance := INF
	if blocking_light != null:
		stop_line_distance = _get_traffic_light_stop_line_distance(blocking_light, direction)
		desired_speed = minf(desired_speed, _get_traffic_light_speed_cap(stop_line_distance))
		if stop_line_distance <= 0.02:
			_current_speed = 0.0
			_waiting_for_traffic_light = true
			_pin_current_driver_to_seat()
			return
	var blocking_vehicle := _find_blocking_vehicle(direction)
	var vehicle_stop_distance := INF
	if blocking_vehicle != null:
		vehicle_stop_distance = _get_vehicle_stop_line_distance(blocking_vehicle, direction)
		desired_speed = minf(desired_speed, _get_vehicle_speed_cap(vehicle_stop_distance))
		if vehicle_stop_distance <= 0.02:
			_current_speed = 0.0
			_waiting_for_vehicle = true
			_pin_current_driver_to_seat()
			return
	var accel := acceleration if desired_speed >= _current_speed else braking_acceleration
	_current_speed = move_toward(_current_speed, desired_speed, accel * delta)
	var max_step := distance
	if blocking_light != null:
		max_step = minf(max_step, maxf(stop_line_distance, 0.0))
	if blocking_vehicle != null:
		max_step = minf(max_step, maxf(vehicle_stop_distance, 0.0))
	var step := minf(_current_speed * delta, max_step)
	_move_vehicle_kinematic(direction * step)
	_pin_current_driver_to_seat()


func _advance_manual_drive(delta: float) -> void:
	var throttle := _get_manual_throttle()
	_steer_target = _get_manual_steer() * manual_steer_limit
	if absf(throttle) > 0.001 or absf(_steer_target) > 0.001:
		sleeping = false
	steering = move_toward(steering, _steer_target, manual_steer_speed * delta)

	var planar_velocity := linear_velocity
	planar_velocity.y = 0.0
	var speed := planar_velocity.length()
	var target_force := 0.0
	if throttle > 0.001 and speed < manual_max_speed:
		target_force = manual_engine_force * throttle * _get_low_speed_force_scale(speed)
	elif throttle < -0.001 and speed < manual_reverse_speed:
		target_force = manual_engine_force * manual_reverse_force_multiplier * throttle * _get_low_speed_force_scale(speed)
	engine_force = target_force * signf(manual_forward_engine_sign)

	if absf(throttle) <= 0.001:
		brake = 0.0
	elif _is_manual_input_braking(throttle):
		brake = manual_brake_strength
	else:
		brake = 0.0

	_current_speed = speed
	if speed > 0.02:
		last_vehicle_route = PackedVector3Array([global_position - planar_velocity.normalized() * minf(speed * delta, 0.5), global_position])
	target_position = global_position


func _finish_trip(world: World = null) -> void:
	stop_vehicle()
	var driver := current_driver
	if _unboard_driver_on_trip_finish:
		driver = unboard_driver(world)
	else:
		_pin_current_driver_to_seat()
	_unboard_driver_on_trip_finish = true
	trip_completed.emit(self, driver, target_building)


func _build_vehicle_route(destination: Vector3, world: World = null) -> PackedVector3Array:
	if world != null and world.has_method("get_vehicle_road_path"):
		var route: PackedVector3Array = world.get_vehicle_road_path(global_position, destination)
		if route.size() >= 2:
			return route
		push_warning("VehicleAgent: RoadGraph returned no vehicle path; refusing direct vehicle fallback.")
		last_path_failed = true
		return PackedVector3Array()
	if world == null:
		return PackedVector3Array([global_position, destination])
	last_path_failed = true
	return PackedVector3Array()

func _snap_to_route_start_if_needed(route: PackedVector3Array) -> void:
	if route.is_empty():
		return
	var route_start := route[0]
	if _planar_distance(global_position, route_start) <= waypoint_reach_distance:
		return
	global_position = Vector3(route_start.x, global_position.y, route_start.z)
	_snap_to_ground_now()
	_pin_current_driver_to_seat()


func _remaining_route_distance(current_segment_distance: float) -> float:
	var total := current_segment_distance
	for i in range(_route_index, last_vehicle_route.size() - 1):
		total += _planar_distance(last_vehicle_route[i], last_vehicle_route[i + 1])
	return total


func _rotate_towards(direction: Vector3, delta: float) -> void:
	if direction.length_squared() <= 0.0001:
		return
	var target_yaw := atan2(direction.x, direction.z) + forward_yaw_offset
	rotation.y = lerp_angle(rotation.y, target_yaw, clampf(turn_speed * delta, 0.0, 1.0))


func _resolve_arrival_exit_position(world: World, fallback: Vector3, building: Building = null) -> Vector3:
	if world != null and world.has_method("get_pedestrian_access_point"):
		var access_point: Vector3 = world.get_pedestrian_access_point(fallback, building)
		if _is_finite_vector(access_point) and _planar_distance(access_point, fallback) <= ARRIVAL_EXIT_MAX_ACCESS_DISTANCE:
			return access_point
	if building != null and building.has_method("get_entrance_pos"):
		return building.get_entrance_pos()
	return fallback


func _ensure_marker(marker_name: String, local_position: Vector3) -> void:
	if get_node_or_null(marker_name) != null:
		return
	var marker := Node3D.new()
	marker.name = marker_name
	marker.position = local_position
	add_child(marker)


func _configure_rigid_body() -> void:
	collision_layer = vehicle_collision_layer
	collision_mask = vehicle_collision_mask
	mass = maxf(vehicle_mass, 0.01)
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = center_of_mass_offset
	can_sleep = true
	contact_monitor = true
	max_contacts_reported = max_contacts_reported if max_contacts_reported > 0 else 4


func _apply_balance_settings() -> void:
	max_speed = BalanceConfig.get_float("transport.vehicle.max_speed", max_speed)
	acceleration = BalanceConfig.get_float("transport.vehicle.acceleration", acceleration)
	braking_acceleration = BalanceConfig.get_float("transport.vehicle.braking_acceleration", braking_acceleration)
	braking_distance = BalanceConfig.get_float("transport.vehicle.braking_distance", braking_distance)
	turn_speed = BalanceConfig.get_float("transport.vehicle.turn_speed", turn_speed)
	waypoint_reach_distance = BalanceConfig.get_float("transport.vehicle.waypoint_reach_distance", waypoint_reach_distance)
	forward_yaw_offset = BalanceConfig.get_float("transport.vehicle.forward_yaw_offset", forward_yaw_offset)
	if use_balance_vehicle_geometry:
		vehicle_mass = BalanceConfig.get_float("transport.vehicle.mass", vehicle_mass)
		center_of_mass_offset = Vector3(
			BalanceConfig.get_float("transport.vehicle.center_of_mass_x", center_of_mass_offset.x),
			BalanceConfig.get_float("transport.vehicle.center_of_mass_y", center_of_mass_offset.y),
			BalanceConfig.get_float("transport.vehicle.center_of_mass_z", center_of_mass_offset.z)
		)
	manual_drive_enabled = BalanceConfig.get_bool("transport.vehicle.manual_drive_enabled", manual_drive_enabled)
	manual_engine_force = BalanceConfig.get_float("transport.vehicle.manual_engine_force", manual_engine_force)
	manual_reverse_force_multiplier = BalanceConfig.get_float("transport.vehicle.manual_reverse_force_multiplier", manual_reverse_force_multiplier)
	manual_brake_strength = BalanceConfig.get_float("transport.vehicle.manual_brake_strength", manual_brake_strength)
	manual_parking_brake = BalanceConfig.get_float("transport.vehicle.manual_parking_brake", manual_parking_brake)
	manual_steer_speed = BalanceConfig.get_float("transport.vehicle.manual_steer_speed", manual_steer_speed)
	manual_steer_limit = BalanceConfig.get_float("transport.vehicle.manual_steer_limit", manual_steer_limit)
	manual_max_speed = BalanceConfig.get_float("transport.vehicle.manual_max_speed", manual_max_speed)
	manual_reverse_speed = BalanceConfig.get_float("transport.vehicle.manual_reverse_speed", manual_reverse_speed)
	manual_low_speed_force_boost = BalanceConfig.get_float("transport.vehicle.manual_low_speed_force_boost", manual_low_speed_force_boost)
	manual_forward_engine_sign = BalanceConfig.get_float("transport.vehicle.manual_forward_engine_sign", manual_forward_engine_sign)
	if use_balance_vehicle_geometry:
		wheel_track_half_width = BalanceConfig.get_float("transport.vehicle.wheel_track_half_width", wheel_track_half_width)
		wheel_front_z = BalanceConfig.get_float("transport.vehicle.wheel_front_z", wheel_front_z)
		wheel_rear_z = BalanceConfig.get_float("transport.vehicle.wheel_rear_z", wheel_rear_z)
		wheel_mount_y = BalanceConfig.get_float("transport.vehicle.wheel_mount_y", wheel_mount_y)
		wheel_radius = BalanceConfig.get_float("transport.vehicle.wheel_radius", wheel_radius)
		wheel_roll_influence = BalanceConfig.get_float("transport.vehicle.wheel_roll_influence", wheel_roll_influence)
		wheel_friction_slip = BalanceConfig.get_float("transport.vehicle.wheel_friction_slip", wheel_friction_slip)
		suspension_stiffness = BalanceConfig.get_float("transport.vehicle.suspension_stiffness", suspension_stiffness)
		suspension_travel = BalanceConfig.get_float("transport.vehicle.suspension_travel", suspension_travel)
		damping_compression = BalanceConfig.get_float("transport.vehicle.damping_compression", damping_compression)
		damping_relaxation = BalanceConfig.get_float("transport.vehicle.damping_relaxation", damping_relaxation)
	ground_snap_enabled = BalanceConfig.get_bool("transport.vehicle.ground_snap_enabled", ground_snap_enabled)
	ground_probe_up = BalanceConfig.get_float("transport.vehicle.ground_probe_up", ground_probe_up)
	ground_probe_down = BalanceConfig.get_float("transport.vehicle.ground_probe_down", ground_probe_down)
	ground_height_offset = BalanceConfig.get_float("transport.vehicle.ground_height_offset", ground_height_offset)
	ground_snap_speed = BalanceConfig.get_float("transport.vehicle.ground_snap_speed", ground_snap_speed)
	ground_min_normal_y = BalanceConfig.get_float("transport.vehicle.ground_min_normal_y", ground_min_normal_y)
	ground_collision_mask = BalanceConfig.get_int("transport.vehicle.ground_collision_mask", ground_collision_mask)
	vehicle_collision_layer = BalanceConfig.get_int("transport.vehicle.physics_collision_layer", vehicle_collision_layer)
	vehicle_collision_mask = BalanceConfig.get_int("transport.vehicle.physics_collision_mask", vehicle_collision_mask)
	route_vehicle_avoidance_enabled = BalanceConfig.get_bool("transport.vehicle.route_vehicle_avoidance_enabled", route_vehicle_avoidance_enabled)
	route_vehicle_detection_distance = BalanceConfig.get_float("transport.vehicle.route_vehicle_detection_distance", route_vehicle_detection_distance)
	route_vehicle_lateral_tolerance = BalanceConfig.get_float("transport.vehicle.route_vehicle_lateral_tolerance", route_vehicle_lateral_tolerance)
	route_vehicle_stop_distance = BalanceConfig.get_float("transport.vehicle.route_vehicle_stop_distance", route_vehicle_stop_distance)
	route_vehicle_slowdown_distance = BalanceConfig.get_float("transport.vehicle.route_vehicle_slowdown_distance", route_vehicle_slowdown_distance)
	vehicle_audio_enabled = BalanceConfig.get_bool("transport.vehicle.audio_enabled", vehicle_audio_enabled)
	engine_audio_path = BalanceConfig.get_string("transport.vehicle.engine_audio_path", engine_audio_path)
	impact_audio_path = BalanceConfig.get_string("transport.vehicle.impact_audio_path", impact_audio_path)
	engine_audio_min_pitch = BalanceConfig.get_float("transport.vehicle.engine_audio_min_pitch", engine_audio_min_pitch)
	engine_audio_pitch_per_speed = BalanceConfig.get_float("transport.vehicle.engine_audio_pitch_per_speed", engine_audio_pitch_per_speed)
	engine_audio_idle_volume_db = BalanceConfig.get_float("transport.vehicle.engine_audio_idle_volume_db", engine_audio_idle_volume_db)
	engine_audio_drive_volume_db = BalanceConfig.get_float("transport.vehicle.engine_audio_drive_volume_db", engine_audio_drive_volume_db)
	engine_audio_lerp_speed = BalanceConfig.get_float("transport.vehicle.engine_audio_lerp_speed", engine_audio_lerp_speed)
	impact_speed_delta_threshold = BalanceConfig.get_float("transport.vehicle.impact_speed_delta_threshold", impact_speed_delta_threshold)
	impact_min_interval = BalanceConfig.get_float("transport.vehicle.impact_min_interval", impact_min_interval)
	impact_contact_linger_sec = BalanceConfig.get_float("transport.vehicle.impact_contact_linger_sec", impact_contact_linger_sec)
	impact_side_normal_max_y = BalanceConfig.get_float("transport.vehicle.impact_side_normal_max_y", impact_side_normal_max_y)
	obey_traffic_lights = BalanceConfig.get_bool("transport.vehicle.obey_traffic_lights", obey_traffic_lights)
	traffic_light_detection_distance = BalanceConfig.get_float("transport.vehicle.traffic_light_detection_distance", traffic_light_detection_distance)
	traffic_light_lateral_tolerance = BalanceConfig.get_float("transport.vehicle.traffic_light_lateral_tolerance", traffic_light_lateral_tolerance)
	traffic_light_stop_distance = BalanceConfig.get_float("transport.vehicle.traffic_light_stop_distance", traffic_light_stop_distance)
	traffic_light_slowdown_distance = BalanceConfig.get_float("transport.vehicle.traffic_light_slowdown_distance", traffic_light_slowdown_distance)


func _find_blocking_traffic_light(direction: Vector3) -> Node3D:
	if not obey_traffic_lights or not is_inside_tree():
		return null
	var tree := get_tree()
	if tree == null:
		return null
	var planar_direction := _normalize_planar(direction)
	if planar_direction == Vector3.ZERO:
		return null

	var best_light: Node3D = null
	var best_forward_distance := INF
	var max_forward := maxf(traffic_light_detection_distance, traffic_light_stop_distance)
	var max_lateral := maxf(traffic_light_lateral_tolerance, 0.01)
	for candidate in tree.get_nodes_in_group(TRAFFIC_LIGHT_GROUP):
		if candidate is not Node3D:
			continue
		var traffic_light := candidate as Node3D
		if not is_instance_valid(traffic_light):
			continue
		if _is_traffic_light_passable(traffic_light):
			continue

		var to_signal := traffic_light.global_position - global_position
		to_signal.y = 0.0
		var forward_distance := to_signal.dot(planar_direction)
		if forward_distance <= 0.05 or forward_distance > max_forward:
			continue
		var lateral_offset := to_signal - planar_direction * forward_distance
		if lateral_offset.length() > max_lateral:
			continue
		if forward_distance < best_forward_distance:
			best_forward_distance = forward_distance
			best_light = traffic_light
	return best_light


func _is_traffic_light_passable(traffic_light: Node3D) -> bool:
	if traffic_light == null:
		return true
	if traffic_light.has_method("is_vehicle_passage_allowed"):
		return bool(traffic_light.call("is_vehicle_passage_allowed"))
	if traffic_light.has_method("get_current_light_name"):
		return str(traffic_light.call("get_current_light_name")) == "green"
	if traffic_light.has_method("get_current_light_color"):
		return int(traffic_light.call("get_current_light_color")) == 0
	return true


func _get_traffic_light_stop_line_distance(traffic_light: Node3D, direction: Vector3) -> float:
	if traffic_light == null:
		return INF
	var planar_direction := _normalize_planar(direction)
	if planar_direction == Vector3.ZERO:
		return INF
	var to_signal := traffic_light.global_position - global_position
	to_signal.y = 0.0
	return to_signal.dot(planar_direction) - maxf(traffic_light_stop_distance, 0.0)


func _get_traffic_light_speed_cap(stop_line_distance: float) -> float:
	if stop_line_distance <= 0.02:
		return 0.0
	var slowdown_distance := maxf(traffic_light_slowdown_distance, 0.05)
	return max_speed * clampf(stop_line_distance / slowdown_distance, 0.0, 1.0)


func _find_blocking_vehicle(direction: Vector3) -> Node3D:
	if not route_vehicle_avoidance_enabled or not is_inside_tree():
		return null
	var tree := get_tree()
	if tree == null:
		return null
	var planar_direction := _normalize_planar(direction)
	if planar_direction == Vector3.ZERO:
		return null

	var best_vehicle: Node3D = null
	var best_forward_distance := INF
	var max_forward := maxf(route_vehicle_detection_distance, route_vehicle_stop_distance)
	var max_lateral := maxf(route_vehicle_lateral_tolerance, 0.01)
	for candidate in tree.get_nodes_in_group("vehicles"):
		if candidate == self or candidate is not Node3D:
			continue
		var other_vehicle := candidate as Node3D
		if not is_instance_valid(other_vehicle):
			continue
		if _should_ignore_vehicle_for_route_spacing(other_vehicle):
			continue

		var to_vehicle := other_vehicle.global_position - global_position
		to_vehicle.y = 0.0
		var forward_distance := to_vehicle.dot(planar_direction)
		if forward_distance <= 0.05 or forward_distance > max_forward:
			continue
		var lateral_offset := to_vehicle - planar_direction * forward_distance
		if lateral_offset.length() > max_lateral:
			continue
		if forward_distance < best_forward_distance:
			best_forward_distance = forward_distance
			best_vehicle = other_vehicle
	return best_vehicle


func _should_ignore_vehicle_for_route_spacing(other_vehicle: Node3D) -> bool:
	if other_vehicle == null:
		return true
	if other_vehicle is VehicleAgent:
		var vehicle_agent := other_vehicle as VehicleAgent
		if vehicle_agent._is_driving or vehicle_agent.current_driver != null:
			return false
	if other_vehicle.has_method("is_driving") and bool(other_vehicle.call("is_driving")):
		return false
	if other_vehicle.has_method("is_manual_driving") and bool(other_vehicle.call("is_manual_driving")):
		return false
	if other_vehicle is VehicleBody3D:
		var body := other_vehicle as VehicleBody3D
		var planar_velocity := body.linear_velocity
		planar_velocity.y = 0.0
		if planar_velocity.length_squared() > 0.0025:
			return false
	return true


func _get_vehicle_stop_line_distance(other_vehicle: Node3D, direction: Vector3) -> float:
	if other_vehicle == null:
		return INF
	var planar_direction := _normalize_planar(direction)
	if planar_direction == Vector3.ZERO:
		return INF
	var to_vehicle := other_vehicle.global_position - global_position
	to_vehicle.y = 0.0
	return to_vehicle.dot(planar_direction) - maxf(route_vehicle_stop_distance, 0.0)


func _get_vehicle_speed_cap(stop_line_distance: float) -> float:
	if stop_line_distance <= 0.02:
		return 0.0
	var slowdown_distance := maxf(route_vehicle_slowdown_distance, 0.05)
	return max_speed * clampf(stop_line_distance / slowdown_distance, 0.0, 1.0)


func _should_process_manual_driver_input() -> bool:
	if not manual_drive_enabled or _is_driving:
		return false
	if current_driver == null or not is_instance_valid(current_driver):
		return false
	if current_driver.has_method("is_inside_vehicle") and not current_driver.is_inside_vehicle():
		return false
	if current_driver.has_method("is_keyboard_control_enabled") and current_driver.is_keyboard_control_enabled():
		return true
	if current_driver.has_method("is_manual_control_enabled") and current_driver.is_manual_control_enabled():
		return true
	if current_driver.has_method("is_network_manual_controlled") and current_driver.is_network_manual_controlled():
		return true
	return false


func _get_manual_throttle() -> float:
	return clampf(_get_action_strength("accelerate") - _get_action_strength("reverse"), -1.0, 1.0)


func _get_manual_steer() -> float:
	return clampf(_get_action_strength("turn_left") - _get_action_strength("turn_right"), -1.0, 1.0)


func _get_action_strength(action_name: String) -> float:
	if not InputMap.has_action(action_name):
		return 0.0
	return Input.get_action_strength(action_name)


func _ensure_manual_drive_input_actions() -> void:
	_ensure_key_action("accelerate", KEY_W)
	_ensure_key_action("accelerate", KEY_UP)
	_ensure_key_action("reverse", KEY_S)
	_ensure_key_action("reverse", KEY_DOWN)
	_ensure_key_action("turn_left", KEY_A)
	_ensure_key_action("turn_left", KEY_LEFT)
	_ensure_key_action("turn_right", KEY_D)
	_ensure_key_action("turn_right", KEY_RIGHT)


func _ensure_key_action(action_name: String, keycode: int) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	for event in InputMap.action_get_events(action_name):
		if event is InputEventKey:
			var key_event := event as InputEventKey
			if int(key_event.keycode) == keycode or int(key_event.physical_keycode) == keycode:
				return
	var new_event := InputEventKey.new()
	new_event.keycode = keycode
	new_event.physical_keycode = keycode
	InputMap.action_add_event(action_name, new_event)


func _ensure_vehicle_collision_shape() -> void:
	if get_node_or_null("VehicleCollisionShape") != null:
		return
	for child in get_children():
		if child is CollisionShape3D:
			return
	var shape_node := CollisionShape3D.new()
	shape_node.name = "VehicleCollisionShape"
	var shape := BoxShape3D.new()
	shape.size = collision_shape_size
	shape_node.shape = shape
	shape_node.position = collision_shape_offset
	add_child(shape_node)


func _ensure_vehicle_wheels() -> void:
	var wheels := _get_vehicle_wheels()
	if wheels.is_empty():
		_create_vehicle_wheel("FrontLeftWheel", Vector3(-wheel_track_half_width, wheel_mount_y, wheel_front_z), true)
		_create_vehicle_wheel("FrontRightWheel", Vector3(wheel_track_half_width, wheel_mount_y, wheel_front_z), true)
		_create_vehicle_wheel("RearLeftWheel", Vector3(-wheel_track_half_width, wheel_mount_y, wheel_rear_z), false)
		_create_vehicle_wheel("RearRightWheel", Vector3(wheel_track_half_width, wheel_mount_y, wheel_rear_z), false)
		wheels = _get_vehicle_wheels()
	for wheel in wheels:
		_configure_vehicle_wheel(wheel)


func _create_vehicle_wheel(wheel_name: String, wheel_position: Vector3, steering_wheel: bool) -> void:
	var wheel := VehicleWheel3D.new()
	wheel.name = wheel_name
	wheel.position = wheel_position
	wheel.use_as_steering = steering_wheel
	wheel.use_as_traction = true
	_configure_vehicle_wheel(wheel)
	add_child(wheel)


func _configure_vehicle_wheel(wheel: VehicleWheel3D) -> void:
	if wheel == null:
		return
	wheel.use_as_traction = true
	wheel.wheel_roll_influence = wheel_roll_influence
	wheel.wheel_radius = wheel_radius
	wheel.wheel_friction_slip = wheel_friction_slip
	wheel.suspension_stiffness = suspension_stiffness
	wheel.suspension_travel = suspension_travel
	wheel.damping_compression = damping_compression
	wheel.damping_relaxation = damping_relaxation


func _get_vehicle_wheels() -> Array[VehicleWheel3D]:
	var wheels: Array[VehicleWheel3D] = []
	for child in get_children():
		if child is VehicleWheel3D:
			wheels.append(child as VehicleWheel3D)
	return wheels


func _ensure_vehicle_audio() -> void:
	_engine_sound_player = get_node_or_null("EngineSound") as AudioStreamPlayer3D
	_impact_sound_player = get_node_or_null("ImpactSound") as AudioStreamPlayer3D
	if not vehicle_audio_enabled:
		return
	if _engine_sound_player == null:
		_engine_sound_player = AudioStreamPlayer3D.new()
		_engine_sound_player.name = "EngineSound"
		add_child(_engine_sound_player)
	if _engine_sound_player != null:
		if _engine_sound_player.stream == null:
			_engine_sound_player.stream = _load_audio_stream(engine_audio_path)
		_engine_sound_player.autoplay = false
		_engine_sound_player.pitch_scale = engine_audio_min_pitch
		_engine_sound_player.volume_db = engine_audio_idle_volume_db
		_engine_sound_player.attenuation_filter_cutoff_hz = 20500.0
	if _impact_sound_player == null:
		_impact_sound_player = AudioStreamPlayer3D.new()
		_impact_sound_player.name = "ImpactSound"
		add_child(_impact_sound_player)
	if _impact_sound_player != null:
		if _impact_sound_player.stream == null:
			_impact_sound_player.stream = _load_audio_stream(impact_audio_path)
		_impact_sound_player.volume_db = -9.0
		_impact_sound_player.max_polyphony = 3
		_impact_sound_player.attenuation_filter_cutoff_hz = 20500.0


func _load_audio_stream(path: String) -> AudioStream:
	var trimmed_path := path.strip_edges()
	if trimmed_path.is_empty():
		return null
	if not ResourceLoader.exists(trimmed_path):
		return null
	return load(trimmed_path) as AudioStream


func _update_vehicle_audio(delta: float) -> void:
	if not vehicle_audio_enabled:
		return
	if DisplayServer.get_name() == "headless":
		return
	var speed := _get_audio_speed()
	_update_engine_audio(delta, speed)
	_update_impact_audio(delta, speed)
	_previous_audio_speed = speed


func _get_audio_speed() -> float:
	var planar_velocity := linear_velocity
	planar_velocity.y = 0.0
	return maxf(planar_velocity.length(), absf(_current_speed))


func _update_engine_audio(delta: float, speed: float) -> void:
	if _engine_sound_player == null or _engine_sound_player.stream == null:
		return
	var active := current_driver != null or _is_driving or speed > 0.05
	if active and not _engine_sound_player.playing:
		_engine_sound_player.play()
	elif not active and _engine_sound_player.playing:
		_engine_sound_player.stop()
	var target_pitch := engine_audio_min_pitch + speed * engine_audio_pitch_per_speed
	var target_volume := engine_audio_drive_volume_db if speed > 0.15 or _is_driving else engine_audio_idle_volume_db
	var lerp_weight := clampf(engine_audio_lerp_speed * delta, 0.0, 1.0)
	_engine_sound_player.pitch_scale = lerpf(_engine_sound_player.pitch_scale, target_pitch, lerp_weight)
	_engine_sound_player.volume_db = lerpf(_engine_sound_player.volume_db, target_volume, lerp_weight)


func _update_impact_audio(delta: float, speed: float) -> void:
	if _impact_sound_player == null or _impact_sound_player.stream == null:
		return
	_impact_audio_cooldown = maxf(_impact_audio_cooldown - delta, 0.0)
	_impact_contact_linger = maxf(_impact_contact_linger - delta, 0.0)
	if not _should_play_impact_audio(speed):
		return
	_impact_audio_cooldown = impact_min_interval
	_impact_sound_player.play()


func _should_play_impact_audio(speed: float) -> bool:
	if _impact_audio_cooldown > 0.0:
		return false
	if _impact_contact_linger <= 0.0:
		return false
	return absf(speed - _previous_audio_speed) >= impact_speed_delta_threshold


func _record_impact_contacts(state: PhysicsDirectBodyState3D) -> void:
	if not _manual_physics_active:
		return
	for contact_index in range(state.get_contact_count()):
		var local_normal := state.get_contact_local_normal(contact_index)
		if local_normal.length_squared() <= 0.0001:
			continue
		var world_normal := (state.transform.basis * local_normal).normalized()
		if absf(world_normal.y) <= impact_side_normal_max_y:
			_impact_contact_linger = maxf(_impact_contact_linger, impact_contact_linger_sec)
			return


func _set_manual_physics_active(active: bool) -> void:
	var desired_freeze := not active
	if active == _manual_physics_active and freeze == desired_freeze:
		return
	_manual_physics_active = active
	if active:
		freeze = false
		can_sleep = false
		sleeping = false
		brake = 0.0
		return
	engine_force = 0.0
	brake = manual_parking_brake
	steering = 0.0
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_impact_contact_linger = 0.0
	freeze = true
	can_sleep = true
	sleeping = true


func _get_low_speed_force_scale(speed: float) -> float:
	if manual_low_speed_force_boost <= 1.0:
		return 1.0
	if speed >= 1.0:
		return 1.0
	return lerpf(manual_low_speed_force_boost, 1.0, clampf(speed, 0.0, 1.0))


func _is_manual_input_braking(throttle: float) -> bool:
	if linear_velocity.length_squared() <= 0.04:
		return false
	var forward := global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() <= 0.0001:
		return false
	var signed_speed := linear_velocity.dot(forward.normalized())
	return signed_speed * throttle < -0.1


func _move_vehicle_kinematic(motion: Vector3) -> bool:
	if motion.length_squared() <= 0.000001:
		return false
	var before := global_position
	global_position += motion
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	return before.distance_squared_to(global_position) > 0.000001


func _snap_to_ground_now() -> void:
	_snap_to_ground(0.0, true)


func _snap_to_ground(delta: float, immediate: bool) -> bool:
	if _manual_physics_active:
		return false
	if not ground_snap_enabled or not is_inside_tree():
		return false
	var world_3d := get_world_3d()
	if world_3d == null:
		return false
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * maxf(ground_probe_up, 0.0),
		global_position - Vector3.UP * maxf(ground_probe_down, 0.0),
		ground_collision_mask
	)
	query.exclude = [get_rid()]
	var hit := world_3d.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	var normal: Vector3 = hit.get("normal", Vector3.UP) as Vector3
	if normal.y < ground_min_normal_y:
		return false
	var hit_position: Vector3 = hit.get("position", global_position) as Vector3
	var target_y := hit_position.y + ground_height_offset
	if immediate or delta <= 0.0 or ground_snap_speed <= 0.0:
		global_position.y = target_y
	else:
		global_position.y = lerpf(global_position.y, target_y, clampf(ground_snap_speed * delta, 0.0, 1.0))
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	return true


func _pin_current_driver_to_seat() -> void:
	_pin_current_driver_to_vehicle_transform(global_transform)


func _pin_current_driver_to_vehicle_transform(vehicle_transform: Transform3D) -> void:
	if current_driver == null or not is_instance_valid(current_driver):
		return
	if current_driver is Node3D:
		var driver_node := current_driver as Node3D
		var seat := get_node_or_null("SeatPoint") as Node3D
		var seat_transform := seat.transform if seat != null else Transform3D.IDENTITY
		var target_transform := vehicle_transform * seat_transform
		driver_node.global_position = target_transform.origin
		driver_node.global_rotation = Vector3(0.0, target_transform.basis.get_euler().y, 0.0)


func _resolve_world_from_tree() -> World:
	var node: Node = self
	while node != null:
		if node is World:
			return node as World
		node = node.get_parent()
	if is_inside_tree():
		for candidate in get_tree().get_nodes_in_group("world"):
			if candidate is World:
				return candidate as World
	return null


func _is_finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


func _register_with_world() -> void:
	var world := _resolve_world_from_tree()
	if world != null and world.has_method("register_vehicle"):
		world.register_vehicle(self)
		_registered_world = world


func _unregister_from_world() -> void:
	var world := _registered_world if _registered_world != null and is_instance_valid(_registered_world) else _resolve_world_from_tree()
	if world != null and world.has_method("unregister_vehicle"):
		world.unregister_vehicle(self)
	_registered_world = null


func _planar_distance(a: Vector3, b: Vector3) -> float:
	var delta := a - b
	delta.y = 0.0
	return delta.length()


func _normalize_planar(direction: Vector3) -> Vector3:
	var planar := direction
	planar.y = 0.0
	if planar.length_squared() <= 0.0001:
		return Vector3.ZERO
	return planar.normalized()
