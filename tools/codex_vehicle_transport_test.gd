extends SceneTree

const TRUCK_SCENE_PATH := "res://Entities/Transport/Truck_NormalTrailler_001.tscn"
const CitizenScene := preload("res://Entities/Citizens/CitizenNew.tscn")

var _errors: Array[String] = []


func _initialize() -> void:
	_check_vehicle_lane_path()
	await _check_vehicle_snaps_to_ground()
	await _check_truck_board_drive_exit()
	await _check_manual_player_drive()
	await _check_manual_drive_blocks_static_collision()

	if not _errors.is_empty():
		for error in _errors:
			push_error(error)
		quit(FAILED)
		return

	print("VEHICLE_TRANSPORT_TEST OK")
	quit(OK)


func _check_vehicle_lane_path() -> void:
	var graph := RoadGraph.new()
	graph.nodes = [Vector3(0.0, 0.0, 0.0), Vector3(10.0, 0.0, 0.0)]
	graph.neighbors = {0: [1], 1: [0]}
	graph._is_ready = true

	var route := graph.find_vehicle_path_points(Vector3(0.0, 0.0, 0.0), Vector3(10.0, 0.0, 0.0), 0.5)
	if route.size() < 2:
		_errors.append("Vehicle road path should contain at least start and target points.")
		return

	var has_lane_offset := false
	for point in route:
		if absf(point.z - 0.5) <= 0.05:
			has_lane_offset = true
			break
	if not has_lane_offset:
		_errors.append("Vehicle road path should offset center road points onto the right lane.")


func _check_vehicle_snaps_to_ground() -> void:
	var ground := StaticBody3D.new()
	ground.name = "VehicleGroundSnapProbeGround"
	ground.collision_layer = 1
	ground.collision_mask = 1
	ground.position = Vector3(0.0, -0.1, 0.0)
	var ground_shape_node := CollisionShape3D.new()
	var ground_shape := BoxShape3D.new()
	ground_shape.size = Vector3(12.0, 0.2, 12.0)
	ground_shape_node.shape = ground_shape
	ground.add_child(ground_shape_node)
	root.add_child(ground)

	var scene := load(TRUCK_SCENE_PATH) as PackedScene
	if scene == null:
		_errors.append("Could not load %s for ground snap check." % TRUCK_SCENE_PATH)
		ground.free()
		return
	var truck := scene.instantiate()
	if truck == null:
		_errors.append("Could not instantiate delivery truck for ground snap check.")
		ground.free()
		return
	(truck as Node3D).position = Vector3(0.0, 2.0, 0.0)
	root.add_child(truck)
	await process_frame
	await physics_frame
	truck.call("advance_vehicle_simulation", 0.1)

	if absf((truck as Node3D).global_position.y) > 0.08:
		_errors.append("Vehicle should snap down to the static ground surface instead of floating.")

	truck.free()
	ground.free()


func _check_truck_board_drive_exit() -> void:
	var scene := load(TRUCK_SCENE_PATH) as PackedScene
	if scene == null:
		_errors.append("Could not load %s." % TRUCK_SCENE_PATH)
		return
	var truck := scene.instantiate()
	if truck == null:
		_errors.append("Could not instantiate delivery truck scene.")
		return
	truck.scale = Vector3.ONE * 0.12
	root.add_child(truck)
	await process_frame

	if absf(truck.scale.x - 0.12) > 0.01 or absf(truck.scale.y - 0.12) > 0.01 or absf(truck.scale.z - 0.12) > 0.01:
		_errors.append("VehicleAgent should preserve scene and instance scale at runtime.")
	if not truck.is_in_group("vehicles"):
		_errors.append("Truck should be in vehicles group.")
	if not truck.is_in_group("delivery_vehicles"):
		_errors.append("Truck should be in delivery_vehicles group.")
	if truck is not CharacterBody3D:
		_errors.append("Truck should use CharacterBody3D so it can collide with buildings.")
	if truck.get_node_or_null("EntryPoint") == null:
		_errors.append("Truck should expose EntryPoint marker.")
	if truck.get_node_or_null("SeatPoint") == null:
		_errors.append("Truck should expose SeatPoint marker.")
	if truck.get_node_or_null("VehicleCollisionShape") == null:
		_errors.append("Truck should expose a VehicleCollisionShape for physics blocking.")

	var citizen := CitizenScene.instantiate() as Citizen
	var target := Supermarket.new()
	target.name = "VehicleProbeSupermarket"
	target.position = Vector3(7.0, 0.0, 0.0)
	root.add_child(target)
	root.add_child(citizen)
	await process_frame

	citizen.global_position = truck.call("get_entry_point_global") as Vector3
	var assigned := bool(truck.call("assign_delivery_driver", citizen, target, null))
	if not assigned:
		_errors.append("Truck should accept a delivery driver assignment.")
	if not citizen.has_method("is_inside_vehicle") or not citizen.is_inside_vehicle():
		_errors.append("Citizen should be marked inside vehicle after boarding.")
	if citizen.visible:
		_errors.append("Citizen should be hidden while driving the truck.")
	if not bool(truck.call("is_driving")):
		_errors.append("Truck should start driving after delivery assignment.")

	_advance_vehicle_until_stopped(truck)

	if bool(truck.call("is_driving")):
		_errors.append("Truck should stop after reaching its target.")
	if citizen.has_method("is_inside_vehicle") and citizen.is_inside_vehicle():
		_errors.append("Citizen should leave the vehicle when the truck arrives.")
	if not citizen.visible:
		_errors.append("Citizen should become visible again after exiting the truck.")
	if (truck.get("last_vehicle_route") as PackedVector3Array).size() < 2:
		_errors.append("Truck should keep its last vehicle route for debugging.")

	truck.free()
	citizen.free()
	target.free()


func _check_manual_player_drive() -> void:
	var scene := load(TRUCK_SCENE_PATH) as PackedScene
	if scene == null:
		_errors.append("Could not load %s for manual drive check." % TRUCK_SCENE_PATH)
		return
	var truck := scene.instantiate()
	if truck == null:
		_errors.append("Could not instantiate delivery truck for manual drive check.")
		return
	root.add_child(truck)
	await process_frame

	var citizen := CitizenScene.instantiate() as Citizen
	root.add_child(citizen)
	await process_frame
	if citizen.has_method("enter_keyboard_control_mode"):
		citizen.enter_keyboard_control_mode(false)
	else:
		citizen.keyboard_control_enabled = true

	var entered := bool(truck.call("board_driver", citizen))
	if not entered:
		_errors.append("Manual player should be able to board the truck.")
		truck.free()
		citizen.free()
		return

	var start_pos: Vector3 = (truck as Node3D).global_position
	Input.action_press("accelerate")
	for _i in range(20):
		truck.call("advance_vehicle_simulation", 0.1)
	Input.action_release("accelerate")

	if (truck as Node3D).global_position.distance_to(start_pos) <= 0.25:
		_errors.append("Player-driven truck should move when accelerate input is held.")
	if not bool(truck.call("is_manual_driving")):
		_errors.append("Truck should report manual driving after player input.")
	var seat_pos: Vector3 = truck.call("get_seat_point_global")
	if citizen.global_position.distance_to(seat_pos) > 0.05:
		_errors.append("Hidden driver should stay pinned to the moving truck seat.")

	var start_yaw: float = (truck as Node3D).rotation.y
	Input.action_press("turn_right")
	for _i in range(8):
		truck.call("advance_vehicle_simulation", 0.1)
	Input.action_release("turn_right")
	if (truck as Node3D).rotation.y >= start_yaw - 0.01:
		_errors.append("turn_right input should steer the truck to the right.")

	if truck.has_method("unboard_driver"):
		truck.call("unboard_driver", null, truck.call("get_entry_point_global"))
	_release_vehicle_inputs()
	truck.free()
	citizen.free()


func _check_manual_drive_blocks_static_collision() -> void:
	var scene := load(TRUCK_SCENE_PATH) as PackedScene
	if scene == null:
		_errors.append("Could not load %s for collision check." % TRUCK_SCENE_PATH)
		return
	var truck := scene.instantiate()
	if truck == null:
		_errors.append("Could not instantiate delivery truck for collision check.")
		return
	root.add_child(truck)
	await process_frame

	var blocker := StaticBody3D.new()
	blocker.name = "VehicleCollisionProbeBlocker"
	blocker.collision_layer = 1
	blocker.collision_mask = 1
	blocker.position = Vector3(0.0, 0.35, 0.85)
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.0, 1.0, 0.35)
	shape_node.shape = shape
	blocker.add_child(shape_node)
	root.add_child(blocker)
	await process_frame

	var citizen := CitizenScene.instantiate() as Citizen
	root.add_child(citizen)
	await process_frame
	if citizen.has_method("enter_keyboard_control_mode"):
		citizen.enter_keyboard_control_mode(false)
	else:
		citizen.keyboard_control_enabled = true
	if not bool(truck.call("board_driver", citizen)):
		_errors.append("Manual collision check should be able to board the truck.")
		truck.free()
		citizen.free()
		blocker.free()
		return

	Input.action_press("accelerate")
	for _i in range(40):
		truck.call("advance_vehicle_simulation", 0.1)
	Input.action_release("accelerate")

	if (truck as Node3D).global_position.z > 0.65:
		_errors.append("Player-driven truck should be blocked by static building/world collisions.")

	if truck.has_method("unboard_driver"):
		truck.call("unboard_driver", null, truck.call("get_entry_point_global"))
	_release_vehicle_inputs()
	truck.free()
	citizen.free()
	blocker.free()


func _release_vehicle_inputs() -> void:
	for action_name in ["accelerate", "reverse", "turn_left", "turn_right"]:
		if InputMap.has_action(action_name):
			Input.action_release(action_name)


func _advance_vehicle_until_stopped(vehicle: Node, max_steps: int = 240) -> void:
	for _i in range(max_steps):
		if not bool(vehicle.call("is_driving")):
			return
		vehicle.call("advance_vehicle_simulation", 0.2)
