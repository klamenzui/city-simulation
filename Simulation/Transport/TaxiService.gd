extends RefCounted
class_name TaxiService

signal status_changed(message: String, kind: String, duration_sec: float)
signal ride_started(vehicle: VehicleAgent, rider: Citizen)
signal ride_finished(vehicle: VehicleAgent, rider: Citizen, fare: int, paid: bool)

const BalanceConfig = preload("res://Simulation/Config/BalanceConfig.gd")
const SimLogger = preload("res://Simulation/Logging/SimLogger.gd")
const TaxiVehicleScene = preload("res://Entities/Transport/Vehicle_Minivan.tscn")

const STATE_IDLE := "idle"
const STATE_PICKUP := "pickup"
const STATE_RIDE := "ride"
const STATE_DESTINATION_DRIVE := "destination_drive"
const TAXI_GROUP := "taxi_vehicle"

var owner_node: Node = null
var world: World = null
var map_overlay = null

var _state: String = STATE_IDLE
var _taxi_vehicle: VehicleAgent = null
var _pickup_player: Citizen = null
var _rider: Citizen = null
var _taxi_account: Account = Account.new()
var _ride_origin: Vector3 = Vector3.ZERO
var _planned_destination: Vector3 = Vector3.INF
var _planned_route: PackedVector3Array = PackedVector3Array()
var _planned_trip_distance: float = 0.0
var _planned_fare: int = 0
var _billing_suppressed: bool = false
var _previous_manual_drive_enabled: bool = true


func setup(owner_ref: Node, world_ref: World, overlay_ref) -> void:
	owner_node = owner_ref
	world = world_ref
	map_overlay = overlay_ref
	_taxi_account.owner_name = "TaxiService"
	if map_overlay != null:
		var destination_cb := Callable(self, "_on_map_destination_selected")
		if not map_overlay.destination_selected.is_connected(destination_cb):
			map_overlay.destination_selected.connect(destination_cb)


func update(_delta: float, player: Citizen) -> void:
	if map_overlay == null:
		return
	if _state == STATE_RIDE or _state == STATE_DESTINATION_DRIVE:
		map_overlay.set_target_node(player if player != null else _rider)
		map_overlay.refresh()
		return
	if map_overlay.visible:
		map_overlay.hide_map()


func request_taxi(player: Citizen) -> Dictionary:
	if player == null or not is_instance_valid(player):
		return _result(false, "Kein Spieler fuer Taxi gefunden.", "warning")
	if world == null or owner_node == null:
		return _result(false, "Taxi-System ist noch nicht bereit.", "warning")
	if player.has_method("is_inside_building") and player.is_inside_building():
		return _result(false, "Taxi kann dich nur draussen abholen.", "warning")
	if player.has_method("is_inside_vehicle") and player.is_inside_vehicle():
		if _is_active_rider(player):
			_show_ride_map()
			return _result(true, "Taxi-Map geoeffnet.", "info")
		return _result(false, "Du bist bereits in einem Fahrzeug.", "warning")
	if player.current_action != null:
		return _result(false, "Beende erst deine laufende Aktion.", "warning")
	if _state == STATE_PICKUP:
		return _result(true, "Taxi ist bereits unterwegs.", "info")
	if _state == STATE_RIDE or _state == STATE_DESTINATION_DRIVE:
		if _is_active_rider(player):
			_show_ride_map()
			return _result(true, "Taxi-Map geoeffnet.", "info")
		return _result(false, "Das Taxi ist gerade belegt.", "warning")
	if not _ensure_taxi_vehicle(player.global_position):
		return _result(false, "Kein Vehicle_Minivan fuer Taxi verfuegbar.", "warning")
	if _taxi_vehicle.current_driver != null:
		return _result(false, "Das Taxi ist gerade belegt.", "warning")

	_pickup_player = player
	_prepare_taxi_for_service()
	var pickup_position := _vehicle_access_point(player.global_position)
	if _is_vehicle_near_position(pickup_position, _pickup_radius()):
		_board_pickup_player()
		return _result(true, "Taxi steht bereit. Ziel auf der Map waehlen.", "success")

	_state = STATE_PICKUP
	if not _start_empty_pickup_route(pickup_position):
		_place_taxi_at(pickup_position)
		_board_pickup_player()
		return _result(true, "Taxi steht bereit. Ziel auf der Map waehlen.", "success")
	return _result(true, "Taxi ist unterwegs.", "info")


func select_destination(world_position: Vector3) -> bool:
	if _state != STATE_RIDE or _taxi_vehicle == null or _rider == null:
		return false
	if not is_instance_valid(_taxi_vehicle) or not is_instance_valid(_rider):
		_reset_service()
		return false
	var destination := _vehicle_access_point(world_position)
	var route := _build_route(_taxi_vehicle.global_position, destination)
	if route.size() < 2:
		_emit_status("Taxi findet keine Strassenroute zum Ziel.", "warning", 2.4)
		return false
	_planned_destination = destination
	_planned_route = route
	_planned_trip_distance = _route_distance(route)
	_planned_fare = _calculate_fare(_planned_trip_distance)
	_billing_suppressed = false
	if map_overlay != null:
		map_overlay.set_selected_position(destination)
		map_overlay.set_route_points(route)
		map_overlay.set_selection_enabled(false)
		map_overlay.set_status_text("Fahrt laeuft. Preis beim Aussteigen: %d EUR." % _planned_fare)
	_state = STATE_DESTINATION_DRIVE
	_taxi_vehicle.target_building = null
	if not _taxi_vehicle.start_drive_to(destination, world):
		_billing_suppressed = true
		_state = STATE_RIDE
		_planned_route = PackedVector3Array()
		_planned_trip_distance = 0.0
		_planned_fare = 0
		if map_overlay != null:
			map_overlay.clear_route()
			map_overlay.set_selection_enabled(true)
			map_overlay.set_status_text("Route konnte nicht gestartet werden. Waehle ein anderes Ziel.")
		_emit_status("Taxi konnte die Fahrt nicht starten.", "warning", 2.4)
		return false
	_emit_status("Taxi faehrt zum Ziel. Preis: %d EUR." % _planned_fare, "info", 2.0)
	return true


func is_active() -> bool:
	return _state != STATE_IDLE


func is_active_rider(citizen: Citizen) -> bool:
	return _is_active_rider(citizen)


func is_taxi_vehicle(vehicle: Node) -> bool:
	return vehicle != null and vehicle == _taxi_vehicle


func get_state() -> String:
	return _state


func get_planned_fare() -> int:
	return _planned_fare


func get_taxi_vehicle() -> VehicleAgent:
	return _taxi_vehicle if _taxi_vehicle != null and is_instance_valid(_taxi_vehicle) else null


func _ensure_taxi_vehicle(request_origin: Vector3) -> bool:
	if _taxi_vehicle != null and is_instance_valid(_taxi_vehicle):
		return true
	_taxi_vehicle = _find_reusable_minivan()
	if _taxi_vehicle != null:
		_taxi_vehicle.add_to_group(TAXI_GROUP)
		_connect_vehicle_signals(_taxi_vehicle)
		return true

	var instance := TaxiVehicleScene.instantiate()
	if instance == null or instance is not VehicleAgent:
		if instance != null:
			instance.queue_free()
		return false
	_taxi_vehicle = instance as VehicleAgent
	_taxi_vehicle.name = "TaxiVehicle_Minivan"
	_taxi_vehicle.add_to_group(TAXI_GROUP)
	var parent: Node = world.get_parent() if world != null and world.get_parent() != null else owner_node
	if parent == null:
		return false
	parent.add_child(_taxi_vehicle)
	_place_taxi_at(_vehicle_access_point(request_origin))
	if world != null and world.has_method("register_vehicle"):
		world.register_vehicle(_taxi_vehicle)
	_connect_vehicle_signals(_taxi_vehicle)
	return true


func _find_reusable_minivan() -> VehicleAgent:
	var candidates: Array[Node] = []
	if world != null:
		for vehicle in world.vehicles:
			if vehicle is Node:
				candidates.append(vehicle as Node)
	if owner_node != null and owner_node.get_tree() != null:
		for node in owner_node.get_tree().get_nodes_in_group("vehicles"):
			if node is Node and not candidates.has(node):
				candidates.append(node as Node)
	for node in candidates:
		if node == null or not is_instance_valid(node):
			continue
		if node is not VehicleAgent:
			continue
		var vehicle := node as VehicleAgent
		if vehicle.is_in_group(TAXI_GROUP):
			return vehicle
	for node2 in candidates:
		if node2 == null or not is_instance_valid(node2):
			continue
		if node2 is not VehicleAgent:
			continue
		var vehicle2 := node2 as VehicleAgent
		if vehicle2.current_driver != null:
			continue
		if vehicle2.delivery_vehicle:
			continue
		if not vehicle2.scene_file_path.ends_with("Vehicle_Minivan.tscn") and not vehicle2.name.contains("Vehicle_Minivan"):
			continue
		return vehicle2
	return null


func _connect_vehicle_signals(vehicle: VehicleAgent) -> void:
	if vehicle == null:
		return
	var trip_cb := Callable(self, "_on_taxi_trip_completed")
	if not vehicle.trip_completed.is_connected(trip_cb):
		vehicle.trip_completed.connect(trip_cb)
	var exited_cb := Callable(self, "_on_taxi_driver_exited")
	if not vehicle.driver_exited.is_connected(exited_cb):
		vehicle.driver_exited.connect(exited_cb)


func _prepare_taxi_for_service() -> void:
	if _taxi_vehicle == null:
		return
	_previous_manual_drive_enabled = _taxi_vehicle.manual_drive_enabled
	_taxi_vehicle.manual_drive_enabled = false
	_taxi_vehicle.add_to_group(TAXI_GROUP)


func _restore_taxi_after_service() -> void:
	if _taxi_vehicle == null or not is_instance_valid(_taxi_vehicle):
		return
	_taxi_vehicle.manual_drive_enabled = _previous_manual_drive_enabled


func _start_empty_pickup_route(pickup_position: Vector3) -> bool:
	if _taxi_vehicle == null:
		return false
	var route := _build_route(_taxi_vehicle.global_position, pickup_position)
	if route.size() < 2:
		return false
	return _taxi_vehicle.start_drive_to(pickup_position, world)


func _board_pickup_player() -> void:
	if _pickup_player == null or not is_instance_valid(_pickup_player):
		_reset_service()
		_emit_status("Taxi-Auftrag abgebrochen: Spieler nicht mehr verfuegbar.", "warning", 2.2)
		return
	if _taxi_vehicle == null or not is_instance_valid(_taxi_vehicle):
		_reset_service()
		_emit_status("Taxi-Auftrag abgebrochen: Fahrzeug nicht mehr verfuegbar.", "warning", 2.2)
		return
	if not _taxi_vehicle.board_driver(_pickup_player):
		_reset_service()
		_emit_status("Taxi-Einstieg fehlgeschlagen.", "warning", 2.2)
		return
	_rider = _pickup_player
	_pickup_player = null
	_state = STATE_RIDE
	_ride_origin = _taxi_vehicle.global_position
	_planned_destination = Vector3.INF
	_planned_route = PackedVector3Array()
	_planned_trip_distance = 0.0
	_planned_fare = 0
	_billing_suppressed = false
	_show_ride_map()
	ride_started.emit(_taxi_vehicle, _rider)
	_emit_status("Taxi bereit. Ziel auf der Map waehlen.", "success", 2.2)


func _show_ride_map() -> void:
	if map_overlay == null:
		return
	map_overlay.setup(world, _rider)
	map_overlay.clear_selected_position()
	map_overlay.clear_route()
	map_overlay.set_extra_markers([])
	map_overlay.show_map("Taxi", "Klicke ein Ziel. Mausrad oder +/- zoomt, rechte Maustaste zieht die Map.", true)


func _on_map_destination_selected(world_position: Vector3) -> void:
	select_destination(world_position)


func _on_taxi_trip_completed(vehicle: VehicleAgent, driver: Citizen, _target_building: Building) -> void:
	if vehicle != _taxi_vehicle:
		return
	if _state == STATE_PICKUP and driver == null:
		_board_pickup_player()


func _on_taxi_driver_exited(vehicle: VehicleAgent, driver: Citizen) -> void:
	if vehicle != _taxi_vehicle:
		return
	if driver == null or driver != _rider:
		return
	var fare := _planned_fare
	var paid := _charge_fare(driver, fare)
	if _state == STATE_DESTINATION_DRIVE and vehicle.is_driving():
		vehicle.stop_vehicle()
	ride_finished.emit(vehicle, driver, fare, paid)
	if fare > 0:
		var status := "Taxi-Fahrt bezahlt: %d EUR." % fare if paid else "Taxi-Fahrt beendet, aber %d EUR konnten nicht bezahlt werden." % fare
		_emit_status(status, "success" if paid else "warning", 2.6)
	else:
		_emit_status("Taxi-Fahrt beendet.", "info", 2.0)
	_reset_service()


func _charge_fare(rider: Citizen, fare: int) -> bool:
	if _billing_suppressed or fare <= 0:
		return true
	if rider == null or rider.wallet == null:
		return false
	if world == null or world.economy == null:
		return false
	var before := rider.wallet.balance
	var paid := world.economy.transfer(rider.wallet, _taxi_account, fare)
	SimLogger.log("[Taxi] %s fare=%d paid=%s balance=%d->%d" % [
		rider.citizen_name,
		fare,
		str(paid),
		before,
		rider.wallet.balance,
	])
	return paid


func _reset_service(restore_vehicle: bool = true) -> void:
	_state = STATE_IDLE
	_pickup_player = null
	_rider = null
	_ride_origin = Vector3.ZERO
	_planned_destination = Vector3.INF
	_planned_route = PackedVector3Array()
	_planned_trip_distance = 0.0
	_planned_fare = 0
	_billing_suppressed = false
	if map_overlay != null:
		map_overlay.hide_map()
		map_overlay.clear_route()
		map_overlay.clear_selected_position()
	if restore_vehicle:
		_restore_taxi_after_service()


func _vehicle_access_point(position: Vector3) -> Vector3:
	if world != null and world.has_method("get_vehicle_road_access_point"):
		return world.get_vehicle_road_access_point(position)
	return position


func _build_route(start_pos: Vector3, end_pos: Vector3) -> PackedVector3Array:
	if world != null and world.has_method("get_vehicle_road_path"):
		return world.get_vehicle_road_path(start_pos, end_pos)
	return PackedVector3Array([start_pos, end_pos])


func _place_taxi_at(position: Vector3) -> void:
	if _taxi_vehicle == null or not is_instance_valid(_taxi_vehicle):
		return
	_taxi_vehicle.global_position = position
	if _taxi_vehicle.has_method("_snap_to_ground_now"):
		_taxi_vehicle.call("_snap_to_ground_now")


func _is_vehicle_near_position(position: Vector3, radius: float) -> bool:
	if _taxi_vehicle == null or not is_instance_valid(_taxi_vehicle):
		return false
	return _planar_distance(_taxi_vehicle.global_position, position) <= radius


func _route_distance(route: PackedVector3Array) -> float:
	var total := 0.0
	for i in range(route.size() - 1):
		total += _planar_distance(route[i], route[i + 1])
	return total


func _calculate_fare(distance: float) -> int:
	var units_per_euro := maxf(BalanceConfig.get_float("transport.taxi.fare_distance_per_euro", 20.0), 0.1)
	var min_fare := BalanceConfig.get_int("transport.taxi.min_fare", 1)
	if distance <= 0.01:
		return 0
	return maxi(int(ceil(distance / units_per_euro)), min_fare)


func _pickup_radius() -> float:
	return maxf(BalanceConfig.get_float("transport.taxi.pickup_radius", 2.5), 0.2)


func _is_active_rider(citizen: Citizen) -> bool:
	return citizen != null and _rider == citizen and _state != STATE_IDLE


func _planar_distance(a: Vector3, b: Vector3) -> float:
	var delta := a - b
	delta.y = 0.0
	return delta.length()


func _result(accepted: bool, message: String, kind: String) -> Dictionary:
	return {
		"accepted": accepted,
		"message": message,
		"kind": kind,
	}


func _emit_status(message: String, kind: String, duration_sec: float) -> void:
	status_changed.emit(message, kind, duration_sec)
