extends CharacterBody3D
class_name VehicleAgent

signal trip_completed(vehicle: VehicleAgent, driver: Citizen, target_building: Building)
signal driver_entered(vehicle: VehicleAgent, driver: Citizen)
signal driver_exited(vehicle: VehicleAgent, driver: Citizen)

const BalanceConfig = preload("res://Simulation/Config/BalanceConfig.gd")

@export var delivery_vehicle: bool = true
@export var max_speed: float = 5.0
@export var acceleration: float = 2.8
@export var braking_acceleration: float = 5.5
@export var braking_distance: float = 2.2
@export var turn_speed: float = 5.0
@export var waypoint_reach_distance: float = 0.45
@export var forward_yaw_offset: float = 0.0
@export var manual_drive_enabled: bool = true
@export var manual_max_speed: float = 4.5
@export var manual_reverse_speed: float = 2.0
@export var manual_acceleration: float = 3.8
@export var manual_braking_acceleration: float = 6.5
@export var manual_coast_deceleration: float = 2.0
@export var manual_turn_speed: float = 1.7
@export var manual_min_turn_factor: float = 0.25
@export var collision_shape_size: Vector3 = Vector3(4.2, 2.8, 11.6)
@export var collision_shape_offset: Vector3 = Vector3(0.0, 1.55, -4.9)
@export var ground_snap_enabled: bool = true
@export var ground_probe_up: float = 2.0
@export var ground_probe_down: float = 8.0
@export var ground_height_offset: float = 0.0
@export var ground_snap_speed: float = 30.0
@export var ground_min_normal_y: float = 0.45
@export_flags_3d_physics var ground_collision_mask: int = 1

var current_driver: Citizen = null
var target_building: Building = null
var target_position: Vector3 = Vector3.ZERO
var last_vehicle_route: PackedVector3Array = PackedVector3Array()
var last_path_failed: bool = false

var _route_index: int = 0
var _current_speed: float = 0.0
var _is_driving: bool = false
var _arrival_exit_position: Vector3 = Vector3.ZERO

func _ready() -> void:
	add_to_group("vehicles")
	if delivery_vehicle:
		add_to_group("delivery_vehicles")
	_apply_balance_settings()
	_ensure_vehicle_collision_shape()
	_ensure_manual_drive_input_actions()
	_ensure_marker("EntryPoint", Vector3(2.45, 0.05, -0.65))
	_ensure_marker("SeatPoint", Vector3(0.8, 2.25, -0.55))
	set_physics_process(true)
	call_deferred("_snap_to_ground_now")

func _physics_process(delta: float) -> void:
	advance_vehicle_simulation(delta)

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
	driver_exited.emit(self, driver)
	return driver

func start_drive_to(destination: Vector3, world: World = null) -> bool:
	target_position = destination
	last_path_failed = false
	last_vehicle_route = _build_vehicle_route(destination, world)
	if last_vehicle_route.size() < 2:
		last_vehicle_route = PackedVector3Array([global_position, destination])
		last_path_failed = true
	_route_index = 1
	_current_speed = 0.0
	_is_driving = last_vehicle_route.size() >= 2
	if not _is_driving:
		_finish_trip(world)
	return _is_driving

func stop_vehicle() -> void:
	_current_speed = 0.0
	_is_driving = false
	_route_index = -1

func is_driving() -> bool:
	return _is_driving

func is_manual_driving() -> bool:
	return _should_process_manual_driver_input() and absf(_current_speed) > 0.05

func has_arrived() -> bool:
	return not _is_driving

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
	_snap_to_ground(delta, false)
	if _is_driving:
		_advance_route_drive(delta)
		_snap_to_ground(delta, false)
		return
	if _should_process_manual_driver_input():
		_advance_manual_drive(delta)
		_snap_to_ground(delta, false)
		return
	_snap_to_ground(delta, false)
	_pin_current_driver_to_seat()

func _advance_route_drive(delta: float) -> void:
	if _route_index < 0 or _route_index >= last_vehicle_route.size():
		_finish_trip(_resolve_world_from_tree())
		return

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
		_move_vehicle(arrival_motion, false)
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
	var accel := acceleration if desired_speed >= _current_speed else braking_acceleration
	_current_speed = move_toward(_current_speed, desired_speed, accel * delta)
	var step := minf(_current_speed * delta, distance)
	_move_vehicle(direction * step, false)
	_pin_current_driver_to_seat()

func _advance_manual_drive(delta: float) -> void:
	var throttle := _get_manual_throttle()
	var steer := _get_manual_steer()
	var target_speed := 0.0
	if throttle > 0.0:
		target_speed = manual_max_speed * throttle
	elif throttle < 0.0:
		target_speed = manual_reverse_speed * throttle

	var rate := manual_coast_deceleration
	if absf(throttle) > 0.001:
		var same_direction := absf(_current_speed) <= 0.01 or signf(target_speed) == signf(_current_speed)
		var speeding_up := absf(target_speed) > absf(_current_speed)
		rate = manual_acceleration if same_direction and speeding_up else manual_braking_acceleration
	_current_speed = move_toward(_current_speed, target_speed, rate * delta)

	if absf(steer) > 0.001 and absf(_current_speed) > 0.03:
		var speed_basis := maxf(manual_max_speed, manual_reverse_speed)
		var turn_factor := clampf(absf(_current_speed) / maxf(speed_basis, 0.01), manual_min_turn_factor, 1.0)
		var reverse_factor := -1.0 if _current_speed < 0.0 else 1.0
		rotation.y += steer * manual_turn_speed * turn_factor * reverse_factor * delta

	var forward := global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() > 0.0001:
		var previous_position := global_position
		_move_vehicle(forward.normalized() * _current_speed * delta)
		if previous_position.distance_squared_to(global_position) > 0.000001:
			last_vehicle_route = PackedVector3Array([previous_position, global_position])
	target_position = global_position
	_pin_current_driver_to_seat()

func _finish_trip(world: World = null) -> void:
	stop_vehicle()
	var driver := unboard_driver(world)
	trip_completed.emit(self, driver, target_building)

func _build_vehicle_route(destination: Vector3, world: World = null) -> PackedVector3Array:
	if world != null and world.has_method("get_vehicle_road_path"):
		var route: PackedVector3Array = world.get_vehicle_road_path(global_position, destination)
		if route.size() >= 2:
			return route
		push_warning("VehicleAgent: RoadGraph returned no vehicle path; using direct fallback.")
	last_path_failed = true
	return PackedVector3Array([global_position, destination])

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
		return world.get_pedestrian_access_point(fallback, building)
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

func _apply_balance_settings() -> void:
	max_speed = BalanceConfig.get_float("transport.vehicle.max_speed", max_speed)
	acceleration = BalanceConfig.get_float("transport.vehicle.acceleration", acceleration)
	braking_acceleration = BalanceConfig.get_float("transport.vehicle.braking_acceleration", braking_acceleration)
	braking_distance = BalanceConfig.get_float("transport.vehicle.braking_distance", braking_distance)
	turn_speed = BalanceConfig.get_float("transport.vehicle.turn_speed", turn_speed)
	waypoint_reach_distance = BalanceConfig.get_float("transport.vehicle.waypoint_reach_distance", waypoint_reach_distance)
	forward_yaw_offset = BalanceConfig.get_float("transport.vehicle.forward_yaw_offset", forward_yaw_offset)
	manual_drive_enabled = BalanceConfig.get_bool("transport.vehicle.manual_drive_enabled", manual_drive_enabled)
	manual_max_speed = BalanceConfig.get_float("transport.vehicle.manual_max_speed", manual_max_speed)
	manual_reverse_speed = BalanceConfig.get_float("transport.vehicle.manual_reverse_speed", manual_reverse_speed)
	manual_acceleration = BalanceConfig.get_float("transport.vehicle.manual_acceleration", manual_acceleration)
	manual_braking_acceleration = BalanceConfig.get_float("transport.vehicle.manual_braking_acceleration", manual_braking_acceleration)
	manual_coast_deceleration = BalanceConfig.get_float("transport.vehicle.manual_coast_deceleration", manual_coast_deceleration)
	manual_turn_speed = BalanceConfig.get_float("transport.vehicle.manual_turn_speed", manual_turn_speed)
	manual_min_turn_factor = BalanceConfig.get_float("transport.vehicle.manual_min_turn_factor", manual_min_turn_factor)
	ground_snap_enabled = BalanceConfig.get_bool("transport.vehicle.ground_snap_enabled", ground_snap_enabled)
	ground_probe_up = BalanceConfig.get_float("transport.vehicle.ground_probe_up", ground_probe_up)
	ground_probe_down = BalanceConfig.get_float("transport.vehicle.ground_probe_down", ground_probe_down)
	ground_height_offset = BalanceConfig.get_float("transport.vehicle.ground_height_offset", ground_height_offset)
	ground_snap_speed = BalanceConfig.get_float("transport.vehicle.ground_snap_speed", ground_snap_speed)
	ground_min_normal_y = BalanceConfig.get_float("transport.vehicle.ground_min_normal_y", ground_min_normal_y)
	ground_collision_mask = BalanceConfig.get_int("transport.vehicle.ground_collision_mask", ground_collision_mask)

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

func _move_vehicle(motion: Vector3, collide: bool = true) -> bool:
	if motion.length_squared() <= 0.000001:
		return false
	if not collide:
		global_position += motion
		return true
	var before := global_position
	var collision := move_and_collide(motion)
	if collision != null:
		_current_speed = 0.0
	return before.distance_squared_to(global_position) > 0.000001

func _snap_to_ground_now() -> void:
	_snap_to_ground(0.0, true)

func _snap_to_ground(delta: float, immediate: bool) -> bool:
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
	return true

func _pin_current_driver_to_seat() -> void:
	if current_driver == null or not is_instance_valid(current_driver):
		return
	if current_driver is Node3D:
		var driver_node := current_driver as Node3D
		driver_node.global_position = get_seat_point_global()
		driver_node.rotation.y = rotation.y

func _resolve_world_from_tree() -> World:
	var node: Node = self
	while node != null:
		if node is World:
			return node as World
		node = node.get_parent()
	return null

func _is_finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)

func _planar_distance(a: Vector3, b: Vector3) -> float:
	var delta := a - b
	delta.y = 0.0
	return delta.length()
