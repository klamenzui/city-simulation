extends SceneTree

const CitizenScene := preload("res://Entities/Citizens/CitizenNew.tscn")
const MinivanScene := preload("res://Entities/Transport/Vehicle_Minivan.tscn")
const TaxiServiceScript := preload("res://Simulation/Transport/TaxiService.gd")
const WorldMapOverlayScript := preload("res://Simulation/UI/WorldMapOverlay.gd")
const WorldMapCanvasScript := preload("res://Simulation/UI/WorldMapCanvas.gd")

var _errors: Array[String] = []


func _initialize() -> void:
	await _check_taxi_request_route_and_fare()
	if not _errors.is_empty():
		for error in _errors:
			push_error(error)
		quit(FAILED)
		return
	print("TAXI_SERVICE_TEST OK")
	quit(OK)


func _check_taxi_request_route_and_fare() -> void:
	var world := World.new()
	root.add_child(world)
	await process_frame
	_configure_test_roads(world)

	var minivan := MinivanScene.instantiate() as VehicleAgent
	root.add_child(minivan)
	await process_frame
	minivan.global_position = world.get_vehicle_road_access_point(Vector3(0.0, 0.0, 0.0))
	minivan.manual_drive_enabled = true
	world.register_vehicle(minivan)

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
	if taxi_service.get_taxi_vehicle() != minivan:
		_errors.append("Taxi service should reuse the existing Vehicle_Minivan instead of spawning another car.")
	if minivan.manual_drive_enabled:
		_errors.append("Taxi service should disable manual driving while the minivan is in taxi service.")

	_advance_vehicle_until_stopped(minivan, 240)
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

	_advance_vehicle_until_stopped(minivan, 360)
	if player.is_inside_vehicle():
		_errors.append("Player should automatically exit the taxi at destination.")
	if _planar_distance(player.global_position, Vector3(60.0, player.global_position.y, 0.0)) > 2.0:
		_errors.append("Player should exit near the taxi destination, not at the pickup/start position.")
	if player.wallet.balance != 18:
		_errors.append("Taxi fare should be deducted from the player's wallet on exit.")
	if not minivan.manual_drive_enabled:
		_errors.append("Taxi service should restore manual driving after the ride ends.")
	if overlay.visible:
		_errors.append("Taxi map should hide after the ride ends.")

	player.free()
	minivan.free()
	overlay.free()
	world.free()


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


func _planar_distance(a: Vector3, b: Vector3) -> float:
	var delta := a - b
	delta.y = 0.0
	return delta.length()
