extends SceneTree

const CitizenScene := preload("res://Entities/Citizens/CitizenNew.tscn")
const TaxiCarScene := preload("res://Scenes/Vehicles/Synty/city_taxi_car.tscn")
const TaxiServiceScript := preload("res://Simulation/Transport/TaxiService.gd")
const TaxiToBuildingActionScript := preload("res://Actions/TaxiToBuildingAction.gd")
const WorldMapOverlayScript := preload("res://Simulation/UI/WorldMapOverlay.gd")
const WorldMapCanvasScript := preload("res://Simulation/UI/WorldMapCanvas.gd")

var _errors: Array[String] = []


func _initialize() -> void:
	await _check_vehicle_depot_spawns_typed_taxi_fleet()
	await _check_taxi_requires_depot()
	await _check_taxi_exits_depot_parking_without_snap()
	await _check_taxi_request_route_and_fare()
	await _check_direct_hospital_taxi_ride()
	await _check_taxi_fleet_reserve()
	if not _errors.is_empty():
		for error in _errors:
			push_error(error)
		quit(FAILED)
		return
	print("TAXI_SERVICE_TEST OK")
	quit(OK)


func _check_vehicle_depot_spawns_typed_taxi_fleet() -> void:
	var world := World.new()
	root.add_child(world)
	await process_frame

	var depot := VehicleDepot.new()
	depot.name = "TaxiVehicleDepot"
	depot.vehicle_scene = TaxiCarScene
	depot.vehicle_role = VehicleDepot.VehicleRole.TAXI

	var parking_area := MeshInstance3D.new()
	parking_area.name = "ParkingArea"
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(2.0, 2.0)
	parking_area.mesh = mesh
	depot.add_child(parking_area)

	var spots_root := Node3D.new()
	spots_root.name = "ParkingSpots"
	depot.add_child(spots_root)
	for index in 2:
		var spot := VehicleParkingSpot.new()
		spot.name = "GeneratedSpot_01_%02d" % (index + 1)
		spot.position = Vector3(float(index), 0.0, 0.0)
		spots_root.add_child(spot)

	root.add_child(depot)
	await process_frame
	await process_frame

	var vehicles_root := depot.get_node_or_null("GeneratedVehicles") as Node3D
	if vehicles_root == null or vehicles_root.get_child_count() != 2:
		_errors.append("VehicleDepot should spawn one taxi per parking spot.")
	else:
		var first_vehicle := vehicles_root.get_child(0) as VehicleAgent
		var first_spot := spots_root.get_child(0) as VehicleParkingSpot
		if first_vehicle == null or not first_vehicle.is_in_group("taxi_vehicle"):
			_errors.append("VehicleDepot taxi role should assign the taxi_vehicle group.")
		elif first_vehicle.delivery_vehicle:
			_errors.append("VehicleDepot taxi role must not mark taxis as delivery vehicles.")
		elif not first_vehicle.has_meta("vehicle_parking_spot"):
			_errors.append("Spawned depot taxi should track its occupied parking spot.")
		else:
			VehicleDepotAccess.release_vehicle_spot(first_vehicle)
			if not first_spot.is_free():
				_errors.append("Releasing a spawned depot taxi should free its parking spot.")

		depot.rebuild_generated_fleet()
		if vehicles_root.get_child_count() != 2:
			_errors.append("Rebuilding a depot fleet should replace vehicles without duplicates.")

		depot.vehicle_role = VehicleDepot.VehicleRole.GENERIC
		depot.rebuild_generated_fleet()
		var generic_vehicle := vehicles_root.get_child(0) as VehicleAgent
		if (
			generic_vehicle == null
			or generic_vehicle.delivery_vehicle
			or generic_vehicle.is_in_group("taxi_vehicle")
			or generic_vehicle.is_in_group("delivery_vehicles")
		):
			_errors.append("VehicleDepot generic role should create an unassigned standard vehicle.")

		depot.vehicle_role = VehicleDepot.VehicleRole.DELIVERY
		depot.rebuild_generated_fleet()
		var delivery_vehicle := vehicles_root.get_child(0) as VehicleAgent
		if (
			delivery_vehicle == null
			or not delivery_vehicle.delivery_vehicle
			or not delivery_vehicle.is_in_group("delivery_vehicles")
			or delivery_vehicle.is_in_group("taxi_vehicle")
		):
			_errors.append("VehicleDepot delivery role should assign the delivery vehicle contract.")

	depot.free()
	world.free()
	await process_frame


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
		_errors.append("Taxi service should reuse the existing Synty taxi instead of spawning another car.")
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
	var dropoff_route := taxi_car.get("last_vehicle_route") as PackedVector3Array
	if dropoff_route.size() < 2:
		_errors.append("Taxi drop-off route should be available after selecting a destination.")
	else:
		var dropoff_end := dropoff_route[dropoff_route.size() - 1]
		if absf(dropoff_end.z - 1.35) > 0.08:
			_errors.append("Taxi drop-off route should end at the curbside, not in the traffic lane.")

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


func _check_direct_hospital_taxi_ride() -> void:
	var world := World.new()
	root.add_child(world)
	await process_frame
	_configure_test_roads(world)

	var taxi_depot_marker := Area3D.new()
	taxi_depot_marker.name = "TaxiVehicleDepot"
	root.add_child(taxi_depot_marker)
	taxi_depot_marker.global_position = Vector3(0.0, 0.0, 5.0)
	var taxi_depot_shape := CollisionShape3D.new()
	var taxi_depot_box := BoxShape3D.new()
	taxi_depot_box.size = Vector3(4.0, 1.0, 5.0)
	taxi_depot_shape.shape = taxi_depot_box
	taxi_depot_shape.position = Vector3(0.0, 0.0, 1.5)
	taxi_depot_marker.add_child(taxi_depot_shape)

	var hospital_depot := _create_test_vehicle_depot("HospitalVehicleDepot", Vector3(60.0, 0.0, 5.0))
	root.add_child(hospital_depot)
	await process_frame

	var taxi_car := TaxiCarScene.instantiate() as VehicleAgent
	root.add_child(taxi_car)
	await process_frame
	taxi_car.global_position = taxi_depot_shape.global_position
	taxi_car.manual_drive_enabled = true
	world.register_vehicle(taxi_car)

	var hospital := Hospital.new()
	root.add_child(hospital)
	await process_frame
	hospital.global_position = Vector3(60.0, 0.0, 5.0)
	world.register_building(hospital)

	var patient := CitizenScene.instantiate() as Citizen
	root.add_child(patient)
	await process_frame
	patient.set_world_ref(world)
	patient.wallet.balance = 40
	patient.global_position = Vector3(20.0, 0.0, 0.0)
	world.register_citizen(patient)

	var taxi_service := TaxiServiceScript.new()
	taxi_service.setup(root, world, null)
	world.set_taxi_service(taxi_service)

	var action = TaxiToBuildingActionScript.new(hospital, "HospitalVehicleDepot", 5)
	patient.start_action(action, world)
	if patient.current_action != action:
		_errors.append("Hospital taxi action should become the patient's current action.")

	var saw_hospital_parking_dropoff := false
	var hospital_spot := _first_parking_spot_position(hospital_depot)
	for _i in range(700):
		taxi_car.advance_vehicle_simulation(0.2)
		taxi_service.update(0.2, null)
		if patient != null and not patient.is_inside_vehicle() and patient.current_location == null:
			if _planar_distance(patient.global_position, hospital_spot) <= 2.0:
				saw_hospital_parking_dropoff = true
		_tick_citizen_action(patient, world)
		if patient.current_location == hospital:
			break

	if not saw_hospital_parking_dropoff:
		_errors.append("Direct hospital taxi should drop the patient at HospitalVehicleDepot parking before final building entry.")
	if patient.current_location != hospital:
		_errors.append("Direct hospital taxi action should finish with the patient inside the hospital. state=%s action=%s failed=%s pos=%s taxi_state=%s taxi_pos=%s" % [
			str(action.get("_phase")),
			patient.current_action.label if patient.current_action != null else "none",
			str(action.get("_failed")),
			str(patient.global_position),
			str(taxi_service.get_state()),
			str(taxi_car.global_position),
		])
	if patient.is_inside_vehicle():
		_errors.append("Patient should not remain inside the taxi after hospital drop-off.")
	if patient.wallet.balance >= 40:
		_errors.append("Direct hospital taxi should charge a fare for the route.")
	if taxi_service.get_state() != "return_to_depot":
		_errors.append("Direct hospital taxi should return to depot after patient drop-off. state=%s taxi_pos=%s patient_pos=%s" % [
			str(taxi_service.get_state()),
			str(taxi_car.global_position),
			str(patient.global_position),
		])

	_advance_vehicle_until_stopped(taxi_car, 480)
	if taxi_service.get_state() != "idle":
		_errors.append("Direct hospital taxi should become idle after returning to the taxi depot.")
	if not taxi_car.manual_drive_enabled:
		_errors.append("Direct hospital taxi should restore manual driving after depot return.")

	patient.free()
	hospital.free()
	taxi_car.free()
	hospital_depot.free()
	taxi_depot_marker.free()
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


func _create_test_vehicle_depot(depot_name: String, global_pos: Vector3) -> VehicleDepot:
	var depot := VehicleDepot.new()
	depot.name = depot_name
	depot.position = global_pos

	var parking_area := MeshInstance3D.new()
	parking_area.name = "ParkingArea"
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(2.0, 2.0)
	parking_area.mesh = mesh
	depot.add_child(parking_area)

	var spots_root := Node3D.new()
	spots_root.name = "ParkingSpots"
	depot.add_child(spots_root)

	var spot := VehicleParkingSpot.new()
	spot.name = "GeneratedSpot_01_01"
	spot.position = Vector3.ZERO
	spots_root.add_child(spot)
	return depot


func _first_parking_spot_position(depot: VehicleDepot) -> Vector3:
	if depot == null:
		return Vector3.INF
	var spots_root := depot.get_node_or_null("ParkingSpots") as Node3D
	if spots_root == null:
		return depot.global_position
	for child in spots_root.get_children():
		if child is VehicleParkingSpot:
			return (child as VehicleParkingSpot).global_position
	return depot.global_position


func _tick_citizen_action(citizen: Citizen, world: World) -> void:
	if citizen == null or citizen.current_action == null:
		return
	var action := citizen.current_action
	action.tick(world, citizen, world.minutes_per_tick)
	if not action.is_done():
		return
	action.finish(world, citizen)
	if citizen.current_action == action:
		citizen.current_action = null


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
