extends SceneTree

const TRUCK_SCENE_PATH := "res://Entities/Transport/Truck_NormalTrailler_001.tscn"
const TRAFFIC_LIGHT_SCENE_PATH := "res://ImportedCitySource/scenes/trafficlight_c_active.tscn"
const VEHICLE_SCENE_PATHS := [
	TRUCK_SCENE_PATH,
	"res://Scenes/Vehicles/CityPack/bus.tscn",
	"res://Scenes/Vehicles/CityPack/car.tscn",
	"res://Scenes/Vehicles/CityPack/car_unqqk_u_lt_ru.tscn",
	"res://Scenes/Vehicles/CityPack/pickup_truck.tscn",
	"res://Scenes/Vehicles/CityPack/police_car.tscn",
	"res://Scenes/Vehicles/CityPack/sports_car.tscn",
	"res://Scenes/Vehicles/CityPack/sports_car_gzj704_d_xdr.tscn",
	"res://Scenes/Vehicles/CityPack/suv.tscn",
	"res://Scenes/Vehicles/CityPack/van.tscn",
	"res://Entities/Transport/Vehicle_TowTruck.tscn",
	"res://Entities/Transport/Vehicle_TrailerTruck.tscn",
]
const CitizenScene := preload("res://Entities/Citizens/CitizenNew.tscn")

var _errors: Array[String] = []


func _initialize() -> void:
	_check_vehicle_lane_path()
	_check_vehicle_route_contract()
	await _check_vehicle_refuses_large_world_route_snap()
	await _check_vehicle_curbside_arrival_is_explicit()
	await _check_route_drive_blocks_static_building_collision()
	_check_vehicle_impact_audio_contract()
	await _check_vehicle_waits_at_red_traffic_light()
	await _check_route_vehicle_keeps_vehicle_gap()
	await _check_route_vehicle_opposite_direction_breaks_deadlock()
	await _check_vehicle_scene_catalog()
	await _check_vehicle_snaps_to_ground()
	await _check_truck_board_drive_exit()
	await _check_manual_player_drive()
	await _check_manual_drive_blocks_static_collision()
	await _check_manual_drive_blocks_parked_vehicle()

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


func _check_vehicle_route_contract() -> void:
	var empty_graph := RoadGraph.new()
	var missing_route := empty_graph.find_vehicle_path_points(Vector3.ZERO, Vector3(10.0, 0.0, 0.0), 0.5)
	if not missing_route.is_empty():
		_errors.append("Vehicle road path should be empty when the RoadGraph has no usable road graph.")

	var graph := RoadGraph.new()
	graph.nodes = [Vector3(0.0, 0.0, 0.0), Vector3(10.0, 0.0, 0.0)]
	graph.neighbors = {0: [1], 1: [0]}
	graph._is_ready = true
	var offroad_start := Vector3(0.0, 0.0, 3.0)
	var offroad_end := Vector3(10.0, 0.0, 3.0)
	var road_only_route := graph.find_vehicle_path_points(offroad_start, offroad_end, 0.5)
	if road_only_route.size() < 2:
		_errors.append("Vehicle road path should route between nearest road nodes when a graph exists.")
	elif _planar_distance(road_only_route[0], offroad_start) <= 0.1 \
			or _planar_distance(road_only_route[road_only_route.size() - 1], offroad_end) <= 0.1:
		_errors.append("Vehicle road path should not include off-road start/end points as drive waypoints.")

	var diagonal_graph := RoadGraph.new()
	diagonal_graph.nodes = [Vector3(0.0, 0.0, 0.0), Vector3(8.0, 0.0, 8.0)]
	diagonal_graph._build_links()
	var first_neighbors := diagonal_graph.neighbors.get(0, []) as Array
	if first_neighbors.has(1):
		_errors.append("Vehicle RoadGraph should not connect diagonal road nodes as a driveable shortcut.")

	var unsupported_gap_graph := RoadGraph.new()
	unsupported_gap_graph.nodes = [Vector3(0.0, 0.0, 0.0), Vector3(10.0, 0.0, 0.0)]
	unsupported_gap_graph._build_links()
	var gap_neighbors := unsupported_gap_graph.neighbors.get(0, []) as Array
	if gap_neighbors.has(1):
		_errors.append("Vehicle RoadGraph should not connect same-axis road nodes across unsupported gaps.")

	var adjacent_tile_graph := RoadGraph.new()
	adjacent_tile_graph.nodes = [Vector3(0.0, 0.0, 0.0), Vector3(4.0, 0.0, 0.0)]
	adjacent_tile_graph._build_links()
	var adjacent_neighbors := adjacent_tile_graph.neighbors.get(0, []) as Array
	if not adjacent_neighbors.has(1):
		_errors.append("Vehicle RoadGraph should connect adjacent road tiles whose mesh support covers the sampled edge.")

	var supported_road_graph := RoadGraph.new()
	supported_road_graph.nodes = [
		Vector3(0.0, 0.0, 0.0),
		Vector3(2.0, 0.0, 0.0),
		Vector3(4.0, 0.0, 0.0),
	]
	supported_road_graph._build_links()
	var supported_neighbors := supported_road_graph.neighbors.get(0, []) as Array
	if not supported_neighbors.has(1):
		_errors.append("Vehicle RoadGraph should connect road nodes when intermediate samples stay on road support.")


func _check_vehicle_impact_audio_contract() -> void:
	var vehicle := VehicleAgent.new()
	vehicle.impact_speed_delta_threshold = 1.8
	vehicle.impact_min_interval = 0.35
	vehicle._previous_audio_speed = 4.0
	vehicle._impact_audio_cooldown = 0.0
	vehicle._impact_contact_linger = 0.0
	if vehicle._should_play_impact_audio(0.0):
		_errors.append("Vehicle impact audio should not play from speed drop alone without a confirmed collision contact.")

	vehicle._impact_contact_linger = 0.1
	if not vehicle._should_play_impact_audio(0.0):
		_errors.append("Vehicle impact audio should play when a large speed drop has a recent collision contact.")

	vehicle._impact_audio_cooldown = 0.2
	if vehicle._should_play_impact_audio(0.0):
		_errors.append("Vehicle impact audio should respect the impact cooldown.")
	vehicle.free()


func _check_vehicle_refuses_large_world_route_snap() -> void:
	var world := World.new()
	var graph := RoadGraph.new()
	graph.nodes = [Vector3(10.0, 0.0, 0.0), Vector3(20.0, 0.0, 0.0)]
	graph.neighbors = {0: [1], 1: [0]}
	graph._is_ready = true
	world.road_graph = graph

	var vehicle := VehicleAgent.new()
	root.add_child(vehicle)
	await process_frame
	vehicle.global_position = Vector3.ZERO
	vehicle.route_start_snap_max_distance = 2.0

	var started := vehicle.start_drive_to(Vector3(20.0, 0.0, 0.0), world)
	if started:
		_errors.append("Vehicle should refuse a RoadGraph route whose first waypoint requires a large start snap.")
	if not vehicle.last_path_failed:
		_errors.append("Vehicle should mark large route-start snap refusals as path failures.")
	if _planar_distance(vehicle.global_position, Vector3.ZERO) > 0.1:
		_errors.append("Vehicle should not teleport toward a far RoadGraph route start.")

	vehicle.free()
	world.free()


func _check_vehicle_curbside_arrival_is_explicit() -> void:
	var world := World.new()
	root.add_child(world)
	await process_frame
	var graph := RoadGraph.new()
	graph.nodes = [Vector3(0.0, 0.0, 0.0), Vector3(20.0, 0.0, 0.0)]
	graph.neighbors = {0: [1], 1: [0]}
	graph._is_ready = true
	world.road_graph = graph

	var normal_vehicle := VehicleAgent.new()
	var curb_vehicle := VehicleAgent.new()
	var left_curb_vehicle := VehicleAgent.new()
	root.add_child(normal_vehicle)
	root.add_child(curb_vehicle)
	root.add_child(left_curb_vehicle)
	await process_frame

	var start := world.get_vehicle_road_access_point(Vector3.ZERO)
	normal_vehicle.global_position = start
	curb_vehicle.global_position = start
	left_curb_vehicle.global_position = start
	for vehicle in [normal_vehicle, curb_vehicle, left_curb_vehicle]:
		vehicle.route_curbside_pullout_offset = 0.9
		vehicle.route_curbside_pullout_length = 2.0

	if not normal_vehicle.start_drive_to(Vector3(20.0, 0.0, 0.0), world):
		_errors.append("Normal vehicle route should start on a simple RoadGraph.")
	else:
		var normal_route := normal_vehicle.get("last_vehicle_route") as PackedVector3Array
		var normal_end := normal_route[normal_route.size() - 1]
		if absf(normal_end.z - 0.45) > 0.05:
			_errors.append("Normal vehicle route should end on the lane, not at the curbside pullout.")

	if not curb_vehicle.start_drive_to_curbside(Vector3(20.0, 0.0, 0.0), world):
		_errors.append("Curbside vehicle route should start on a simple RoadGraph.")
	else:
		var curb_route := curb_vehicle.get("last_vehicle_route") as PackedVector3Array
		var curb_end := curb_route[curb_route.size() - 1]
		if absf(curb_end.z - 1.35) > 0.08:
			_errors.append("Curbside vehicle route should stop right of the lane at the destination.")
		if curb_route.size() < 4:
			_errors.append("Curbside vehicle route should include a merge and a short parallel curb segment.")

	if not left_curb_vehicle.start_drive_to_curbside(Vector3(20.0, 0.0, -4.0), world):
		_errors.append("Curbside vehicle route should support targets on the left side of the lane.")
	else:
		var left_curb_route := left_curb_vehicle.get("last_vehicle_route") as PackedVector3Array
		var left_curb_end := left_curb_route[left_curb_route.size() - 1]
		if left_curb_end.z >= -0.05:
			_errors.append("Curbside vehicle route should pull out toward the target side, not always to the route's right side.")

	normal_vehicle.free()
	curb_vehicle.free()
	left_curb_vehicle.free()
	world.free()


func _check_route_drive_blocks_static_building_collision() -> void:
	var vehicle := VehicleAgent.new()
	root.add_child(vehicle)
	await process_frame
	vehicle.global_position = Vector3.ZERO
	vehicle.max_speed = 5.0
	vehicle.acceleration = 20.0
	vehicle.braking_acceleration = 20.0

	var blocker := StaticBody3D.new()
	blocker.name = "RouteVehicleBuildingBlocker"
	blocker.collision_layer = 1
	blocker.collision_mask = 1
	blocker.position = Vector3(3.0, 0.45, 0.0)
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.4, 0.9, 2.0)
	shape_node.shape = shape
	blocker.add_child(shape_node)
	root.add_child(blocker)
	await process_frame

	if not vehicle.start_drive_to(Vector3(8.0, 0.0, 0.0), null):
		_errors.append("Route vehicle should start a direct route for static building collision regression.")
		vehicle.free()
		blocker.free()
		return

	for _i in range(80):
		vehicle.advance_vehicle_simulation(0.1)

	if vehicle.global_position.x > 2.15:
		_errors.append("Route-driven vehicle should stop before static building/world collisions instead of driving into them.")

	vehicle.free()
	blocker.free()


func _check_vehicle_waits_at_red_traffic_light() -> void:
	var traffic_scene := load(TRAFFIC_LIGHT_SCENE_PATH) as PackedScene
	if traffic_scene == null:
		_errors.append("Could not load traffic light scene for vehicle signal check.")
		return
	var traffic_light := traffic_scene.instantiate() as Node3D
	if traffic_light == null:
		_errors.append("Could not instantiate traffic light scene for vehicle signal check.")
		return
	root.add_child(traffic_light)
	await process_frame
	traffic_light.global_position = Vector3(3.0, 0.0, 0.45)
	traffic_light.set("auto_switch", false)
	traffic_light.set("light_color", 2)
	if not traffic_light.has_method("is_vehicle_passage_allowed"):
		_errors.append("Traffic lights should expose vehicle passage state.")
	elif bool(traffic_light.call("is_vehicle_passage_allowed")):
		_errors.append("Red traffic lights should block vehicle passage.")

	var vehicle := VehicleAgent.new()
	root.add_child(vehicle)
	await process_frame
	vehicle.vehicle_audio_enabled = false
	vehicle.max_speed = 5.0
	vehicle.acceleration = 20.0
	vehicle.braking_acceleration = 20.0
	vehicle.traffic_light_detection_distance = 5.0
	vehicle.traffic_light_lateral_tolerance = 0.75
	vehicle.traffic_light_stop_distance = 0.8
	vehicle.traffic_light_slowdown_distance = 2.0

	vehicle.global_position = Vector3.ZERO
	var started := vehicle.start_drive_to(Vector3(8.0, 0.0, 0.0), null)
	if not started:
		_errors.append("Vehicle should start a direct route for traffic-light regression.")
		vehicle.free()
		traffic_light.free()
		return

	for _i in range(60):
		vehicle.advance_vehicle_simulation(0.1)
	if vehicle.global_position.x > 2.35:
		_errors.append("Vehicle should stop before a red traffic light instead of crossing the stop line.")
	if not vehicle.is_waiting_at_traffic_light():
		_errors.append("Vehicle should report that it is waiting at the red traffic light.")
	if not vehicle.is_driving():
		_errors.append("Vehicle should keep its route active while waiting at a red traffic light.")

	traffic_light.set("light_color", 0)
	if not bool(traffic_light.call("is_vehicle_passage_allowed")):
		_errors.append("Green traffic lights should allow vehicle passage.")
	for _i in range(90):
		if not vehicle.is_driving():
			break
		vehicle.advance_vehicle_simulation(0.1)

	if vehicle.is_driving():
		_errors.append("Vehicle should resume and complete its route once the traffic light turns green.")
	if vehicle.global_position.x < 7.5:
		_errors.append("Vehicle should pass the traffic light after it turns green.")

	vehicle.free()
	traffic_light.free()


func _check_route_vehicle_keeps_vehicle_gap() -> void:
	var blocker := VehicleAgent.new()
	var follower := VehicleAgent.new()
	root.add_child(blocker)
	root.add_child(follower)
	await process_frame

	blocker.global_position = Vector3(3.0, 0.0, 0.0)
	follower.global_position = Vector3.ZERO
	follower.max_speed = 5.0
	follower.acceleration = 20.0
	follower.braking_acceleration = 20.0
	follower.route_vehicle_detection_distance = 5.0
	follower.route_vehicle_lateral_tolerance = 0.75
	follower.route_vehicle_stop_distance = 1.8
	follower.route_vehicle_slowdown_distance = 2.2

	if ((follower as CollisionObject3D).collision_mask & 4) == 0:
		_errors.append("Vehicle physics mask should include the vehicle collision layer.")
	blocker.start_drive_to(Vector3(6.0, 0.0, 0.0), null)

	var started := follower.start_drive_to(Vector3(8.0, 0.0, 0.0), null)
	if not started:
		_errors.append("Follower vehicle should start a direct route for vehicle-spacing regression.")
		blocker.free()
		follower.free()
		return

	for _i in range(70):
		follower.advance_vehicle_simulation(0.1)
	if follower.global_position.x > 1.35:
		_errors.append("Route-driven vehicle should stop behind another vehicle instead of overlapping it.")
	if not follower.is_waiting_for_vehicle():
		_errors.append("Route-driven vehicle should report that it is waiting behind another vehicle.")
	if not follower.is_driving():
		_errors.append("Route-driven vehicle should keep its route active while waiting behind another vehicle.")

	blocker.global_position = Vector3(8.0, 0.0, 4.0)
	for _i in range(90):
		if not follower.is_driving():
			break
		follower.advance_vehicle_simulation(0.1)

	if follower.is_driving():
		_errors.append("Route-driven vehicle should resume once the vehicle ahead clears the lane.")
	if follower.global_position.x < 7.5:
		_errors.append("Route-driven vehicle should pass the cleared vehicle obstruction.")

	blocker.free()
	follower.free()


func _check_route_vehicle_opposite_direction_breaks_deadlock() -> void:
	var westbound := VehicleAgent.new()
	var eastbound := VehicleAgent.new()
	root.add_child(westbound)
	root.add_child(eastbound)
	await process_frame

	westbound.global_position = Vector3(3.0, 0.0, 0.0)
	eastbound.global_position = Vector3.ZERO
	for vehicle in [westbound, eastbound]:
		vehicle.max_speed = 5.0
		vehicle.acceleration = 20.0
		vehicle.braking_acceleration = 20.0
		vehicle.route_vehicle_detection_distance = 5.0
		vehicle.route_vehicle_lateral_tolerance = 0.75
		vehicle.route_vehicle_stop_distance = 1.8
		vehicle.route_vehicle_slowdown_distance = 2.2

	westbound.start_drive_to(Vector3(-3.0, 0.0, 0.0), null)
	eastbound.start_drive_to(Vector3(6.0, 0.0, 0.0), null)

	for _i in range(160):
		if not westbound.is_driving() and not eastbound.is_driving():
			break
		westbound.advance_vehicle_simulation(0.1)
		eastbound.advance_vehicle_simulation(0.1)

	if westbound.is_waiting_for_vehicle() and eastbound.is_waiting_for_vehicle():
		_errors.append("Opposite-direction route vehicles should not both wait forever nose-to-nose.")
	if westbound.global_position.x > 0.5 and eastbound.global_position.x < 4.5:
		_errors.append("At least one opposite-direction route vehicle should clear the conflict instead of deadlocking.")

	westbound.free()
	eastbound.free()


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
		if vehicle is CollisionObject3D:
			var collision_object := vehicle as CollisionObject3D
			if (collision_object.collision_layer & 4) == 0:
				_errors.append("Vehicle scene %s should live on the vehicle collision layer." % scene_path)
			if (collision_object.collision_mask & 4) == 0:
				_errors.append("Vehicle scene %s should collide with other vehicles." % scene_path)
		if _count_vehicle_wheels(vehicle) < 4:
			_errors.append("Vehicle scene %s should expose at least four VehicleWheel3D nodes." % scene_path)
		if vehicle.get_node_or_null("EntryPoint") == null:
			_errors.append("Vehicle scene %s should expose EntryPoint." % scene_path)
		if vehicle.get_node_or_null("SeatPoint") == null:
			_errors.append("Vehicle scene %s should expose SeatPoint." % scene_path)
		if not _has_vehicle_collision_shape(vehicle):
			_errors.append("Vehicle scene %s should expose at least one enabled CollisionShape3D." % scene_path)
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
	if not _has_vehicle_collision_shape(truck):
		_errors.append("Truck should expose at least one enabled CollisionShape3D for physics blocking.")
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


func _check_manual_drive_blocks_parked_vehicle() -> void:
	var scene := _load_vehicle_scene(TRUCK_SCENE_PATH)
	if scene == null:
		_errors.append("Could not load %s for vehicle collision check." % TRUCK_SCENE_PATH)
		return
	var truck := scene.instantiate()
	var parked := scene.instantiate()
	if truck == null or parked == null:
		_errors.append("Could not instantiate trucks for vehicle collision check.")
		if truck != null:
			truck.free()
		if parked != null:
			parked.free()
		return
	var ground := _add_vehicle_test_ground("VehicleParkedCollisionProbeGround")
	root.add_child(ground)
	root.add_child(truck)
	root.add_child(parked)
	await process_frame
	await physics_frame

	(truck as Node3D).global_position = Vector3.ZERO
	(parked as Node3D).global_position = Vector3(0.0, 0.0, 1.25)
	await physics_frame

	var truck_collision := truck as CollisionObject3D
	var parked_collision := parked as CollisionObject3D
	if truck_collision != null and (truck_collision.collision_mask & 4) == 0:
		_errors.append("Player-driven truck should include parked vehicles in its collision mask.")
	if parked_collision != null and (parked_collision.collision_layer & 4) == 0:
		_errors.append("Parked truck should expose the vehicle collision layer.")

	var citizen := CitizenScene.instantiate() as Citizen
	root.add_child(citizen)
	await process_frame
	if citizen.has_method("enter_keyboard_control_mode"):
		citizen.enter_keyboard_control_mode(false)
	else:
		citizen.keyboard_control_enabled = true
	if not bool(truck.call("board_driver", citizen)):
		_errors.append("Manual parked-vehicle collision check should be able to board the truck.")
		truck.free()
		parked.free()
		citizen.free()
		ground.free()
		return

	Input.action_press("accelerate")
	for _i in range(120):
		await physics_frame
	Input.action_release("accelerate")

	if (truck as Node3D).global_position.z > 0.75:
		_errors.append("Player-driven truck should be blocked by parked vehicle collisions.")

	if truck.has_method("unboard_driver"):
		truck.call("unboard_driver", null, truck.call("get_entry_point_global"))
	_release_vehicle_inputs()
	truck.free()
	parked.free()
	citizen.free()
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


func _has_vehicle_collision_shape(node: Node) -> bool:
	if node is CollisionShape3D:
		var shape_node := node as CollisionShape3D
		if not shape_node.disabled and shape_node.shape != null:
			return true
	for child in node.get_children():
		if _has_vehicle_collision_shape(child):
			return true
	return false


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


func _planar_distance(a: Vector3, b: Vector3) -> float:
	var delta := a - b
	delta.y = 0.0
	return delta.length()
