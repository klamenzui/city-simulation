extends SceneTree

const TRUCK_SCENE_PATH := "res://Entities/Transport/Truck_NormalTrailler_001.tscn"
const VEHICLE_SCENE_PATHS := [
	TRUCK_SCENE_PATH,
	"res://Entities/Transport/Vehicle_Minivan.tscn",
	"res://Entities/Transport/Vehicle_TowTruck.tscn",
	"res://Entities/Transport/Vehicle_TrailerTruck.tscn",
]
const CitizenScene := preload("res://Entities/Citizens/CitizenNew.tscn")

var _errors: Array[String] = []


func _initialize() -> void:
	_check_vehicle_lane_path()
	await _check_vehicle_scene_catalog()
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


func _check_vehicle_scene_catalog() -> void:
	for scene_path in VEHICLE_SCENE_PATHS:
		var scene := _load_vehicle_scene(scene_path)
		if scene == null:
			_errors.append("Could not load vehicle scene %s." % scene_path)
			continue
		var vehicle := scene.instantiate()
		if vehicle == null:
			_errors.append("Could not instantiate vehicle scene %s." % scene_path)
			continue
		root.add_child(vehicle)
		await process_frame

		if vehicle is not VehicleBody3D:
			_errors.append("Vehicle scene %s should have a VehicleBody3D root." % scene_path)
		if not vehicle.is_in_group("vehicles"):
			_errors.append("Vehicle scene %s should join the vehicles group." % scene_path)
		if _count_vehicle_wheels(vehicle) < 4:
			_errors.append("Vehicle scene %s should expose at least four VehicleWheel3D nodes." % scene_path)
		if vehicle.get_node_or_null("EntryPoint") == null:
			_errors.append("Vehicle scene %s should expose EntryPoint." % scene_path)
		if vehicle.get_node_or_null("SeatPoint") == null:
			_errors.append("Vehicle scene %s should expose SeatPoint." % scene_path)
		if vehicle.get_node_or_null("VehicleCollisionShape") == null:
			_errors.append("Vehicle scene %s should expose VehicleCollisionShape." % scene_path)
		var engine_sound := vehicle.get_node_or_null("EngineSound") as AudioStreamPlayer3D
		if engine_sound == null:
			_errors.append("Vehicle scene %s should expose EngineSound." % scene_path)
		elif engine_sound.stream == null:
			_errors.append("Vehicle scene %s should have an engine audio stream." % scene_path)
		if not _has_mesh_instance(vehicle):
			_errors.append("Vehicle scene %s should include visible mesh geometry." % scene_path)
		if scene_path != TRUCK_SCENE_PATH:
			_check_truck_town_vehicle_visual_fit(scene_path, vehicle)

		vehicle.free()


func _check_vehicle_snaps_to_ground() -> void:
	var ground := _add_vehicle_test_ground("VehicleGroundSnapProbeGround")
	root.add_child(ground)

	var scene := _load_vehicle_scene(TRUCK_SCENE_PATH)
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
	var scene := _load_vehicle_scene(TRUCK_SCENE_PATH)
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
	if truck is not VehicleBody3D:
		_errors.append("Truck should use VehicleBody3D for wheel-based physics.")
	var visual_root := truck.get_node_or_null("VisualRoot") as Node3D
	if visual_root == null:
		_errors.append("Truck should keep imported model scale on a VisualRoot instead of scaling the physics root.")
	elif absf(visual_root.scale.x - 0.15) > 0.01 or absf(visual_root.scale.y - 0.15) > 0.01 or absf(visual_root.scale.z - 0.15) > 0.01:
		_errors.append("Truck VisualRoot should preserve the 0.15 model scale.")
	elif visual_root.position.y < 0.02:
		_errors.append("Truck VisualRoot should be lifted enough that visible wheels stay above the road plane.")
	if not _has_non_white_material(truck):
		_errors.append("Truck should have at least one non-white material assigned to the visible model.")
	if not _has_textured_material(truck):
		_errors.append("Truck should keep its assigned vehicle texture on a visible material.")
	if truck.get_node_or_null("EntryPoint") == null:
		_errors.append("Truck should expose EntryPoint marker.")
	if truck.get_node_or_null("SeatPoint") == null:
		_errors.append("Truck should expose SeatPoint marker.")
	if truck.get_node_or_null("VehicleCollisionShape") == null:
		_errors.append("Truck should expose a VehicleCollisionShape for physics blocking.")
	if _count_vehicle_wheels(truck) < 4:
		_errors.append("Truck should expose at least four VehicleWheel3D nodes.")
	if not _vehicle_wheels_match_visible_radius(truck):
		_errors.append("Truck VehicleWheel3D radius should match the scaled visible tires.")

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
	var scene := _load_vehicle_scene(TRUCK_SCENE_PATH)
	if scene == null:
		_errors.append("Could not load %s for manual drive check." % TRUCK_SCENE_PATH)
		return
	var truck := scene.instantiate()
	if truck == null:
		_errors.append("Could not instantiate delivery truck for manual drive check.")
		return
	var ground := _add_vehicle_test_ground("VehicleManualDriveGround")
	root.add_child(ground)
	root.add_child(truck)
	await process_frame
	await physics_frame

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
		ground.free()
		return

	var start_pos: Vector3 = (truck as Node3D).global_position
	Input.action_press("accelerate")
	for _i in range(90):
		await physics_frame
	Input.action_release("accelerate")

	if (truck as Node3D).global_position.distance_to(start_pos) <= 0.05:
		_errors.append("Player-driven truck should move when accelerate input is held.")
	if not bool(truck.call("is_manual_driving")):
		_errors.append("Truck should report manual driving after player input.")
	var seat_pos: Vector3 = truck.call("get_seat_point_global")
	if citizen.global_position.distance_to(seat_pos) > 0.05:
		_errors.append("Hidden driver should stay pinned to the moving truck seat.")

	Input.action_press("turn_right")
	for _i in range(20):
		await physics_frame
	Input.action_release("turn_right")
	if truck is VehicleBody3D and (truck as VehicleBody3D).steering >= -0.01:
		_errors.append("turn_right input should steer the truck to the right.")

	if truck.has_method("unboard_driver"):
		truck.call("unboard_driver", null, truck.call("get_entry_point_global"))
	_release_vehicle_inputs()
	truck.free()
	citizen.free()
	ground.free()
	await process_frame


func _check_manual_drive_blocks_static_collision() -> void:
	var scene := _load_vehicle_scene(TRUCK_SCENE_PATH)
	if scene == null:
		_errors.append("Could not load %s for collision check." % TRUCK_SCENE_PATH)
		return
	var truck := scene.instantiate()
	if truck == null:
		_errors.append("Could not instantiate delivery truck for collision check.")
		return
	var ground := _add_vehicle_test_ground("VehicleCollisionProbeGround")
	root.add_child(ground)
	root.add_child(truck)
	await process_frame
	await physics_frame

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
		ground.free()
		return

	Input.action_press("accelerate")
	for _i in range(120):
		await physics_frame
	Input.action_release("accelerate")

	if (truck as Node3D).global_position.z > 0.65:
		_errors.append("Player-driven truck should be blocked by static building/world collisions.")

	if truck.has_method("unboard_driver"):
		truck.call("unboard_driver", null, truck.call("get_entry_point_global"))
	_release_vehicle_inputs()
	truck.free()
	citizen.free()
	blocker.free()
	ground.free()
	await process_frame


func _release_vehicle_inputs() -> void:
	for action_name in ["accelerate", "reverse", "turn_left", "turn_right"]:
		if InputMap.has_action(action_name):
			Input.action_release(action_name)


func _load_vehicle_scene(scene_path: String) -> PackedScene:
	return ResourceLoader.load(scene_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene


func _add_vehicle_test_ground(ground_name: String) -> StaticBody3D:
	var ground := StaticBody3D.new()
	ground.name = ground_name
	ground.collision_layer = 1
	ground.collision_mask = 1
	ground.position = Vector3(0.0, -0.1, 0.0)
	var ground_shape_node := CollisionShape3D.new()
	var ground_shape := BoxShape3D.new()
	ground_shape.size = Vector3(20.0, 0.2, 20.0)
	ground_shape_node.shape = ground_shape
	ground.add_child(ground_shape_node)
	return ground


func _count_vehicle_wheels(vehicle: Node) -> int:
	var count := 0
	for child in vehicle.get_children():
		if child is VehicleWheel3D:
			count += 1
	return count


func _has_mesh_instance(node: Node) -> bool:
	if node is MeshInstance3D:
		return true
	for child in node.get_children():
		if _has_mesh_instance(child):
			return true
	return false


func _check_truck_town_vehicle_visual_fit(scene_path: String, vehicle: Node) -> void:
	var visual_root := vehicle.get_node_or_null("VisualRoot") as Node3D
	if visual_root == null:
		_errors.append("Vehicle scene %s should keep truck_town meshes under VisualRoot." % scene_path)
	elif visual_root.scale.x > 0.8 or visual_root.scale.y > 0.8 or visual_root.scale.z > 0.8:
		_errors.append("Vehicle scene %s should scale imported truck_town visuals down for the city world." % scene_path)

	var mesh_aabb := _get_mesh_aabb(vehicle)
	if mesh_aabb.size.x > 0.95 or mesh_aabb.size.y > 0.95 or mesh_aabb.size.z > 3.15:
		_errors.append("Vehicle scene %s should stay within city-scale visual bounds." % scene_path)
	if mesh_aabb.position.y < -0.04:
		_errors.append("Vehicle scene %s should not sink visible meshes deeply below the road plane." % scene_path)

	for child in vehicle.get_children():
		if child is VehicleWheel3D:
			var wheel := child as VehicleWheel3D
			if absf(wheel.position.y - wheel.wheel_radius) > 0.02:
				_errors.append("Vehicle scene %s should place wheel centers one radius above the road." % scene_path)

	if scene_path.ends_with("Vehicle_TrailerTruck.tscn"):
		if vehicle.get_node_or_null("VisualRoot/Trailer") == null:
			_errors.append("Trailer truck should include a separate visible trailer body.")
		if vehicle.get_node_or_null("VisualRoot/TrailerDrawbar") == null:
			_errors.append("Trailer truck should include a visible drawbar between cab and trailer.")
		var trailer := vehicle.get_node_or_null("VisualRoot/Trailer") as Node3D
		if trailer != null and trailer.position.z > -1.5:
			_errors.append("Trailer truck trailer body should sit clearly behind the cab instead of forming one monolithic car.")


func _get_mesh_aabb(node: Node) -> AABB:
	var result: Dictionary = {}
	_collect_mesh_aabb(node, result)
	if result.has("aabb"):
		return result["aabb"] as AABB
	return AABB()


func _collect_mesh_aabb(node: Node, result: Dictionary) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var global_aabb := mesh_instance.global_transform * mesh_instance.get_aabb()
		if result.has("aabb"):
			result["aabb"] = (result["aabb"] as AABB).merge(global_aabb)
		else:
			result["aabb"] = global_aabb
	for child in node.get_children():
		_collect_mesh_aabb(child, result)


func _vehicle_wheels_match_visible_radius(vehicle: Node) -> bool:
	var checked := 0
	for child in vehicle.get_children():
		if child is VehicleWheel3D:
			var wheel := child as VehicleWheel3D
			checked += 1
			if wheel.wheel_radius < 0.14:
				return false
	return checked >= 4


func _has_non_white_material(node: Node) -> bool:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if _is_non_white_material(mesh_instance.material_override):
			return true
		var mesh := mesh_instance.mesh
		if mesh != null:
			for surface_index in range(mesh.get_surface_count()):
				if _is_non_white_material(mesh.surface_get_material(surface_index)):
					return true
	for child in node.get_children():
		if _has_non_white_material(child):
			return true
	return false


func _is_non_white_material(material: Material) -> bool:
	if material is BaseMaterial3D:
		var albedo := (material as BaseMaterial3D).albedo_color
		return absf(albedo.r - 1.0) > 0.05 or absf(albedo.g - 1.0) > 0.05 or absf(albedo.b - 1.0) > 0.05
	return false


func _has_textured_material(node: Node) -> bool:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if _material_has_albedo_texture(mesh_instance.material_override):
			return true
		var mesh := mesh_instance.mesh
		if mesh != null:
			for surface_index in range(mesh.get_surface_count()):
				if _material_has_albedo_texture(mesh.surface_get_material(surface_index)):
					return true
	for child in node.get_children():
		if _has_textured_material(child):
			return true
	return false


func _material_has_albedo_texture(material: Material) -> bool:
	return material is BaseMaterial3D and (material as BaseMaterial3D).albedo_texture != null


func _advance_vehicle_until_stopped(vehicle: Node, max_steps: int = 240) -> void:
	for _i in range(max_steps):
		if not bool(vehicle.call("is_driving")):
			return
		vehicle.call("advance_vehicle_simulation", 0.2)
