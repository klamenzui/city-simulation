extends SceneTree

const CitizenScene := preload("res://Entities/Citizens/CitizenNew.tscn")
const TaxiCarScene := preload("res://Scenes/Vehicles/CityPack/car.tscn")
const TaxiServiceScript := preload("res://Simulation/Transport/TaxiService.gd")
const WorldMapOverlayScript := preload("res://Simulation/UI/WorldMapOverlay.gd")
const WorldMapCanvasScript := preload("res://Simulation/UI/WorldMapCanvas.gd")

var _errors: Array[String] = []


func _initialize() -> void:
	await _check_taxi_requires_depot()
	await _check_taxi_exits_depot_parking_without_snap()
	await _check_taxi_request_route_and_fare()
	await _check_taxi_fleet_reserve()
	if not _errors.is_empty():
		for error in _errors:
			push_error(error)
		quit(FAILED)
		return
	print("TAXI_SERVICE_TEST OK")
	quit(OK)


func _check_taxi_requires_depot() -> void:
	var world := World.new()
	root.add_child(world)
	await process_frame
	_configure_test_roads(world)

	var taxi_car := TaxiCarScene.instantiate() as VehicleAgent
	root.add_child(taxi_car)
	await process_frame
	taxi_car.global_position = world.get_vehicle_road_access_point(Vector3(0.0, 0.0, 0.0))
	taxi_car.manual_drive_enabled = true
	world.register_vehicle(taxi_car)

	var player := CitizenScene.instantiate() as Citizen
	root.add_child(player)
	await process_frame
	player.set_world_ref(world)
	player.global_position = Vector3(20.0, 0.0, 0.0)
	world.register_citizen(player)

	var overlay := CanvasLayer.new()
	overlay.set_script(WorldMapOverlayScript)
	root.add_child(overlay)
	overlay.setup(world, player)
	var taxi_service := TaxiServiceScript.new()
	taxi_service.setup(root, world, overlay)

	var result: Dictionary = taxi_service.request_taxi(player)
	if bool(result.get("accepted", false)):
		_errors.append("Taxi request should be rejected when no TaxiVehicleDepot or TaxiDepot exists.")
	if taxi_service.get_state() != "idle":
		_errors.append("Taxi service should remain idle when depot resolution fails.")
	if not taxi_car.manual_drive_enabled:
		_errors.append("Taxi service should not reserve or modify a taxi car when no depot exists.")

	player.free()
	taxi_car.free()
	overlay.free()
	world.free()


func _check_taxi_exits_depot_parking_without_snap() -> void:
	var world := World.new()
	root.add_child(world)
	await process_frame
	_configure_test_roads(world)

	var depot_marker := Area3D.new()
	depot_marker.name = "TaxiVehicleDepot"
	root.add_child(depot_marker)
	depot_marker.global_position = Vector3(0.0, 0.0, 5.0)
	var depot_shape := CollisionShape3D.new()
	var depot_box := BoxShape3D.new()
	depot_box.size = Vector3(4.0, 1.0, 5.0)
	depot_shape.shape = depot_box
	depot_shape.position = Vector3(0.0, 0.0, 1.5)
	depot_marker.add_child(depot_shape)
	await process_frame

	var taxi_car := TaxiCarScene.instantiate() as VehicleAgent
	root.add_child(taxi_car)
	await process_frame
	taxi_car.global_position = depot_shape.global_position
	taxi_car.manual_drive_enabled = true
	world.register_vehicle(taxi_car)

	var player := CitizenScene.instantiate() as Citizen
	root.add_child(player)
	await process_frame
	player.set_world_ref(world)
	player.global_position = Vector3(20.0, 0.0, 0.0)
	world.register_citizen(player)

	var overlay := CanvasLayer.new()
	overlay.set_script(WorldMapOverlayScript)
	root.add_child(overlay)
	overlay.setup(world, player)
	var taxi_service := TaxiServiceScript.new()
	taxi_service.setup(root, world, overlay)

	var result: Dictionary = taxi_service.request_taxi(player)
	if not bool(result.get("accepted", false)):
		_errors.append("Taxi request should be accepted when the taxi is parked inside TaxiVehicleDepot.")
	if _planar_distance(taxi_car.global_position, depot_shape.global_position) > 0.2:
		_errors.append("Taxi should not snap from TaxiVehicleDepot parking area to the road when a pickup request starts.")
	if not taxi_car.is_driving():
		_errors.append("Taxi should start a local depot exit maneuver before the road pickup route.")

	player.free()
	taxi_car.free()
	overlay.free()
	depot_marker.free()
	world.free()


func _check_taxi_request_route_and_fare() -> void:
	var world := World.new()
	root.add_child(world)
	await process_frame
	_configure_test_roads(world)

	var taxi_car := TaxiCarScene.instantiate() as VehicleAgent
	root.add_child(taxi_car)
	await process_frame
	taxi_car.global_position = world.get_vehicle_road_access_point(Vector3(0.0, 0.0, 0.0))
	taxi_car.manual_drive_enabled = true
	world.register_vehicle(taxi_car)

	var depot_marker := Area3D.new()
	depot_marker.name = "TaxiVehicleDepot"
	root.add_child(depot_marker)
	depot_marker.global_position = Vector3(0.0, 0.0, 5.0)
	var depot_shape := CollisionShape3D.new()
	var depot_box := BoxShape3D.new()
	depot_box.size = Vector3(4.0, 1.0, 5.0)
	depot_shape.shape = depot_box
	depot_shape.position = Vector3(0.0, 0.0, 1.5)
	depot_marker.add_child(depot_shape)

	var player := CitizenScene.instantiate() as Citizen
	root.add_child(player)
	await process_frame
	player.set_world_ref(world)
	player.wallet.balance = 20
	player.global_position = Vector3(20.0, 0.0, 0.0)
	world.register_citizen(player)

	var overlay := CanvasLayer.new()
	overlay.set_script(WorldMapOverlayScript)
	root.add_child(overlay)
	overlay.setup(world, player)
	var taxi_service := TaxiServiceScript.new()
	taxi_service.setup(root, world, overlay)

	var result: Dictionary = taxi_service.request_taxi(player)
	if not bool(result.get("accepted", false)):
		_errors.append("Taxi request should be accepted in a simple road graph.")
	if taxi_service.get_taxi_vehicle() != taxi_car:
		_errors.append("Taxi service should reuse the existing CityPack car instead of spawning another car.")
	if taxi_car.manual_drive_enabled:
		_errors.append("Taxi service should disable manual driving while the taxi car is in taxi service.")

	_advance_vehicle_until_stopped(taxi_car, 240)
	if not player.is_inside_vehicle():
		_errors.append("Player should be inside the taxi after pickup route completes.")
	if taxi_service.get_state() != "ride":
		_errors.append("Taxi service should enter ride state after pickup.")
	if not overlay.visible:
		_errors.append("Taxi map should be visible while the player is inside the taxi.")
	if not is_equal_approx(overlay.get_zoom_level(), overlay.get_default_zoom_level()):
		_errors.append("Taxi map should open at its default zoom level.")
	await _check_world_map_canvas_orientation_and_pan(world, player)
	overlay.zoom_in()
	if overlay.get_zoom_level() <= overlay.get_default_zoom_level():
		_errors.append("Taxi map should support zooming in.")
	overlay.reset_zoom()
	if not is_equal_approx(overlay.get_zoom_level(), overlay.get_default_zoom_level()):
		_errors.append("Taxi map zoom reset should return to the default zoom level.")

	if not taxi_service.select_destination(Vector3(60.0, 0.0, 0.0)):
		_errors.append("Taxi should accept a reachable destination from the map.")
	if taxi_service.get_planned_fare() != 2:
		_errors.append("Taxi fare should be 2 EUR for a 40-unit route at 1 EUR per 20 units.")

	_advance_vehicle_until_player_exited(taxi_car, player, 360)
	if player.is_inside_vehicle():
		_errors.append("Player should automatically exit the taxi at destination.")
	if _planar_distance(player.global_position, Vector3(60.0, player.global_position.y, 0.0)) > 2.0:
		_errors.append("Player should exit near the taxi destination, not at the pickup/start position.")
	if player.wallet.balance != 18:
		_errors.append("Taxi fare should be deducted from the player's wallet on exit.")
	if taxi_service.get_state() != "return_to_depot":
		_errors.append("Taxi service should send the taxi back to the depot after drop-off.")
	if not taxi_car.is_driving():
		_errors.append("Taxi should keep driving after drop-off while returning to the depot.")
	if taxi_car.manual_drive_enabled:
		_errors.append("Taxi service should keep manual driving disabled during the depot return.")

	_advance_vehicle_until_stopped(taxi_car, 480)
	var depot_access := world.get_vehicle_road_access_point(depot_marker.global_position)
	if _planar_distance(taxi_car.global_position, depot_shape.global_position) > 2.0:
		_errors.append("Taxi should park inside the TaxiVehicleDepot collision area after finishing the ride.")
	if _planar_distance(taxi_car.global_position, depot_access) <= 2.0:
		_errors.append("Taxi should not remain on the road access point when TaxiVehicleDepot has a parking collision area.")
	if taxi_service.get_state() != "idle":
		_errors.append("Taxi service should become idle after the taxi reaches the depot.")
	if not taxi_car.manual_drive_enabled:
		_errors.append("Taxi service should restore manual driving after the depot return ends.")
	if overlay.visible:
		_errors.append("Taxi map should hide after the ride ends.")

	depot_marker.free()
	player.free()
	taxi_car.free()
	overlay.free()
	world.free()


# A second request while the first taxi is still returning to the depot must be served
# by a different free taxi from the pool, and the returning taxi must park on its own.
func _check_taxi_fleet_reserve() -> void:
	var world := World.new()
	root.add_child(world)
	await process_frame
	_configure_test_roads(world)

	var depot_marker := Area3D.new()
	depot_marker.name = "TaxiVehicleDepot"
	root.add_child(depot_marker)
	depot_marker.global_position = Vector3(0.0, 0.0, 5.0)
	var depot_shape := CollisionShape3D.new()
	var depot_box := BoxShape3D.new()
	depot_box.size = Vector3(4.0, 1.0, 5.0)
	depot_shape.shape = depot_box
	depot_shape.position = Vector3(0.0, 0.0, 1.5)
	depot_marker.add_child(depot_shape)
	await process_frame

	var car_a := TaxiCarScene.instantiate() as VehicleAgent
	root.add_child(car_a)
	var car_b := TaxiCarScene.instantiate() as VehicleAgent
	root.add_child(car_b)
	await process_frame
	car_a.global_position = depot_shape.global_position
	car_b.global_position = depot_shape.global_position
	car_a.manual_drive_enabled = true
	car_b.manual_drive_enabled = true
	# The trivial 1D test road has no lanes; disable head-on avoidance so the two taxis
	# do not deadlock passing each other. This isolates the dispatch logic under test.
	car_a.route_vehicle_avoidance_enabled = false
	car_b.route_vehicle_avoidance_enabled = false
	world.register_vehicle(car_a)
	world.register_vehicle(car_b)

	var player := CitizenScene.instantiate() as Citizen
	root.add_child(player)
	await process_frame
	player.set_world_ref(world)
	player.wallet.balance = 40
	player.global_position = Vector3(20.0, 0.0, 0.0)
	world.register_citizen(player)

	var overlay := CanvasLayer.new()
	overlay.set_script(WorldMapOverlayScript)
	root.add_child(overlay)
	overlay.setup(world, player)
	var taxi_service := TaxiServiceScript.new()
	taxi_service.setup(root, world, overlay)

	var fleet: Array = [car_a, car_b]
	var first_result: Dictionary = taxi_service.request_taxi(player)
	if not bool(first_result.get("accepted", false)):
		_errors.append("Fleet: first taxi request should be accepted.")
	var first_taxi: VehicleAgent = taxi_service.get_taxi_vehicle()
	if first_taxi == null:
		_errors.append("Fleet: first request should assign a taxi.")

	_advance_fleet_until_player_inside(taxi_service, player, fleet, 300)
	if not player.is_inside_vehicle():
		_errors.append("Fleet: player should be inside the first taxi after pickup.")
	if not taxi_service.select_destination(Vector3(60.0, 0.0, 0.0)):
		_errors.append("Fleet: first taxi should accept a destination.")
	_advance_fleet_until_player_exited(taxi_service, player, fleet, 400)
	if player.is_inside_vehicle():
		_errors.append("Fleet: player should exit the first taxi at the destination.")
	if taxi_service.get_state() != "return_to_depot":
		_errors.append("Fleet: first taxi should be returning to the depot after drop-off.")

	# Hail again immediately: a reserve taxi must serve while the first one still returns.
	player.global_position = Vector3(40.0, 0.0, 0.0)
	var second_result: Dictionary = taxi_service.request_taxi(player)
	if not bool(second_result.get("accepted", false)):
		_errors.append("Fleet: a reserve taxi should serve a new request while the first returns.")
	var second_taxi: VehicleAgent = taxi_service.get_taxi_vehicle()
	if second_taxi == null:
		_errors.append("Fleet: second request should assign a reserve taxi.")
	if second_taxi == first_taxi:
		_errors.append("Fleet: the reserve request should use a different taxi than the returning one.")
	if first_taxi != null and not taxi_service.is_taxi_vehicle(first_taxi):
		_errors.append("Fleet: the returning taxi should still count as a taxi vehicle.")

	_advance_fleet_until_player_inside(taxi_service, player, fleet, 400)
	if not player.is_inside_vehicle():
		_errors.append("Fleet: the reserve taxi should pick up the player.")
	# Let the handed-off taxi finish parking back at the depot.
	_advance_fleet(taxi_service, player, fleet, 200)
	if first_taxi != null and _planar_distance(first_taxi.global_position, depot_shape.global_position) > 3.5:
		_errors.append("Fleet: the returning taxi should park back near the depot.")

	player.free()
	car_a.free()
	car_b.free()
	overlay.free()
	depot_marker.free()
	world.free()


func _advance_fleet(taxi_service, player: Citizen, vehicles: Array, steps: int) -> void:
	for _i in range(steps):
		for vehicle in vehicles:
			if vehicle != null and is_instance_valid(vehicle):
				vehicle.advance_vehicle_simulation(0.2)
		taxi_service.update(0.2, player)


func _advance_fleet_until_player_inside(taxi_service, player: Citizen, vehicles: Array, max_steps: int) -> void:
	for _i in range(max_steps):
		if player != null and player.is_inside_vehicle():
			return
		_advance_fleet(taxi_service, player, vehicles, 1)


func _advance_fleet_until_player_exited(taxi_service, player: Citizen, vehicles: Array, max_steps: int) -> void:
	for _i in range(max_steps):
		if player != null and not player.is_inside_vehicle():
			return
		_advance_fleet(taxi_service, player, vehicles, 1)


func _configure_test_roads(world: World) -> void:
	var road_nodes: Array[Vector3] = [
		Vector3(0.0, 0.0, 0.0),
		Vector3(20.0, 0.0, 0.0),
		Vector3(40.0, 0.0, 0.0),
		Vector3(60.0, 0.0, 0.0),
	]
	world.road_graph.nodes = road_nodes
	world.road_graph.neighbors = {
		0: [1],
		1: [0, 2],
		2: [1, 3],
		3: [2],
	}
	world.road_graph._is_ready = true
	world.road_graph._rebuild_road_support_keys()


func _check_world_map_canvas_orientation_and_pan(world: World, player: Citizen) -> void:
	var canvas := Control.new()
	canvas.set_script(WorldMapCanvasScript)
	root.add_child(canvas)
	canvas.size = Vector2(400.0, 260.0)
	await process_frame
	canvas.set_world(world)
	canvas.set_target_node(player)
	canvas.reset_zoom()

	var rect: Rect2 = canvas.call("_map_rect")
	var sample_y := rect.position.y + rect.size.y * 0.5
	var left_world: Vector3 = canvas.call("_map_to_world", Vector2(rect.position.x + 4.0, sample_y))
	var right_world: Vector3 = canvas.call("_map_to_world", Vector2(rect.position.x + rect.size.x - 4.0, sample_y))
	if right_world.x >= left_world.x:
		_errors.append("WorldMapCanvas should mirror X so the visual right side maps to the city's right-facing layout.")

	var center_before: Vector3 = canvas.call("_current_view_center")
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	press.position = rect.get_center()
	canvas.call("_gui_input", press)

	var motion := InputEventMouseMotion.new()
	motion.position = rect.get_center() + Vector2(32.0, 0.0)
	motion.relative = Vector2(32.0, 0.0)
	motion.button_mask = MOUSE_BUTTON_MASK_RIGHT
	canvas.call("_gui_input", motion)

	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_RIGHT
	release.pressed = false
	release.position = motion.position
	canvas.call("_gui_input", release)

	var center_after: Vector3 = canvas.call("_current_view_center")
	if _planar_distance(center_before, center_after) <= 0.01:
		_errors.append("WorldMapCanvas right-button drag should pan the map view.")
	canvas.free()


func _advance_vehicle_until_stopped(vehicle: VehicleAgent, max_steps: int) -> void:
	for _i in range(max_steps):
		if not vehicle.is_driving():
			return
		vehicle.advance_vehicle_simulation(0.2)


func _advance_vehicle_until_player_exited(vehicle: VehicleAgent, player: Citizen, max_steps: int) -> void:
	for _i in range(max_steps):
		if player != null and not player.is_inside_vehicle():
			return
		vehicle.advance_vehicle_simulation(0.2)


func _planar_distance(a: Vector3, b: Vector3) -> float:
	var delta := a - b
	delta.y = 0.0
	return delta.length()
