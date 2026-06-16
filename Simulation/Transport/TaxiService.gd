extends RefCounted
class_name TaxiService

signal status_changed(message: String, kind: String, duration_sec: float)
signal ride_started(vehicle: VehicleAgent, rider: Citizen)
signal ride_finished(vehicle: VehicleAgent, rider: Citizen, fare: int, paid: bool)
signal ride_failed(rider: Citizen, message: String)

const BalanceConfig = preload("res://Simulation/Config/BalanceConfig.gd")
const SimLogger = preload("res://Simulation/Logging/SimLogger.gd")
const TaxiReturnTripScript = preload("res://Simulation/Transport/TaxiReturnTrip.gd")
const TAXI_VEHICLE_SCENE_PATH := "res://Scenes/Vehicles/CityPack/car.tscn"
const TaxiVehicleScene = preload("res://Scenes/Vehicles/CityPack/car.tscn")

const STATE_IDLE := "idle"
const STATE_PICKUP := "pickup"
const STATE_RIDE := "ride"
const STATE_DESTINATION_DRIVE := "destination_drive"
const STATE_RETURN_TO_DEPOT := "return_to_depot"
const TAXI_GROUP := "taxi_vehicle"
const TAXI_DEPOT_MARKER_NAME := "TaxiVehicleDepot"
const TAXI_DEPOT_PARKING_MAX_DIRECT_DISTANCE := 16.0

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
var _direct_destination_position: Vector3 = Vector3.INF
var _direct_destination_parking_position: Vector3 = Vector3.INF
var _direct_destination_parking_spot: VehicleParkingSpot = null
var _direct_destination_marker: Node3D = null
var _direct_destination_building: Building = null
var _direct_destination_parking_maneuver_active: bool = false
var _assigned_depot_position: Vector3 = Vector3.INF
var _assigned_depot_parking_position: Vector3 = Vector3.INF
var _assigned_parking_spot: VehicleParkingSpot = null
var _return_depot_position: Vector3 = Vector3.INF
var _return_access_position: Vector3 = Vector3.INF
var _pending_pickup_position: Vector3 = Vector3.INF
var _depot_exit_maneuver_active: bool = false
var _return_access_exit_maneuver_active: bool = false
var _depot_parking_maneuver_active: bool = false
var _billing_suppressed: bool = false
var _previous_manual_drive_enabled: bool = true
# Taxis handed off after drop-off that drive back to the depot and park on their own,
# so the active service slot is free for a reserve taxi to serve the next request.
var _returning_trips: Array = []


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
	_tick_returning_trips()
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
	if _state == STATE_RETURN_TO_DEPOT:
		# A taxi is still heading back. Hand it off so it parks itself, then dispatch a
		# free reserve taxi for this new request below.
		_handoff_active_return_to_trip()
	var depot_parking_position := _resolve_taxi_depot_parking_position(player.global_position)
	if not _is_finite_vector(depot_parking_position):
		return _result(false, "Kein TaxiVehicleDepot oder TaxiDepot fuer Taxi-Service gefunden.", "warning")
	_assigned_depot_parking_position = depot_parking_position
	_assigned_depot_position = _vehicle_access_point(depot_parking_position)
	if not _ensure_taxi_vehicle(player.global_position, _assigned_depot_parking_position):
		_clear_assigned_depot()
		return _result(false, "Kein Taxi-Fahrzeug verfuegbar.", "warning")
	if _taxi_vehicle.current_driver != null:
		_clear_assigned_depot()
		return _result(false, "Das Taxi ist gerade belegt.", "warning")

	_pickup_player = player
	_prepare_taxi_for_service()
	var pickup_position := _vehicle_access_point(player.global_position)
	if _is_vehicle_near_position(pickup_position, _pickup_radius()):
		_board_pickup_player()
		return _result(true, "Taxi steht bereit. Ziel auf der Map waehlen.", "success")

	_state = STATE_PICKUP
	if not _start_empty_pickup_route(pickup_position):
		_reset_service()
		return _result(false, "Taxi findet keine Strassenroute zur Abholung.", "warning")
	return _result(true, "Taxi ist unterwegs.", "info")


func request_direct_ride_to_building(
	rider: Citizen,
	destination_building: Building,
	destination_marker_name: String = ""
) -> Dictionary:
	if rider == null or not is_instance_valid(rider):
		return _result(false, "Kein Fahrgast fuer Taxi gefunden.", "warning")
	if destination_building == null or not is_instance_valid(destination_building):
		return _result(false, "Kein Taxi-Ziel gefunden.", "warning")
	if world == null or owner_node == null:
		return _result(false, "Taxi-System ist noch nicht bereit.", "warning")
	if rider.has_method("is_inside_building") and rider.is_inside_building():
		return _result(false, "Taxi kann Fahrgaeste nur draussen abholen.", "warning")
	if rider.has_method("is_inside_vehicle") and rider.is_inside_vehicle():
		if _is_active_rider(rider):
			return _result(true, "Taxi-Fahrt laeuft bereits.", "info")
		return _result(false, "Fahrgast ist bereits in einem Fahrzeug.", "warning")
	if _state == STATE_PICKUP:
		return _result(false, "Taxi ist bereits unterwegs.", "warning")
	if _state == STATE_RIDE or _state == STATE_DESTINATION_DRIVE:
		if _is_active_rider(rider):
			return _result(true, "Taxi-Fahrt laeuft bereits.", "info")
		return _result(false, "Das Taxi ist gerade belegt.", "warning")
	if _state == STATE_RETURN_TO_DEPOT:
		_handoff_active_return_to_trip()

	var destination_marker := _find_direct_destination_marker(destination_building, destination_marker_name)
	var destination_parking_position := _resolve_direct_destination_parking_position(destination_building, destination_marker)
	var destination_position := _vehicle_access_point(destination_parking_position)
	if not _is_finite_vector(destination_position):
		return _result(false, "Taxi-Ziel hat keine erreichbare Fahrzeugposition.", "warning")
	var depot_parking_position := _resolve_taxi_depot_parking_position(rider.global_position)
	if not _is_finite_vector(depot_parking_position):
		return _result(false, "Kein TaxiVehicleDepot oder TaxiDepot fuer Taxi-Service gefunden.", "warning")
	_assigned_depot_parking_position = depot_parking_position
	_assigned_depot_position = _vehicle_access_point(depot_parking_position)
	if not _ensure_taxi_vehicle(rider.global_position, _assigned_depot_parking_position):
		_clear_direct_destination()
		_clear_assigned_depot()
		return _result(false, "Kein Taxi-Fahrzeug verfuegbar.", "warning")
	if _taxi_vehicle.current_driver != null:
		_clear_direct_destination()
		_clear_assigned_depot()
		return _result(false, "Das Taxi ist gerade belegt.", "warning")

	_direct_destination_position = destination_position
	_direct_destination_parking_position = destination_parking_position if destination_marker != null else Vector3.INF
	_direct_destination_marker = destination_marker
	_direct_destination_building = destination_building
	_pickup_player = rider
	_prepare_taxi_for_service()
	var pickup_position := _vehicle_access_point(rider.global_position)
	if _is_vehicle_near_position(pickup_position, _pickup_radius()):
		_board_pickup_player()
		return _result(true, "Taxi steht bereit und faehrt zum Ziel.", "success")

	_state = STATE_PICKUP
	if not _start_empty_pickup_route(pickup_position):
		_reset_service()
		return _result(false, "Taxi findet keine Strassenroute zur Abholung.", "warning")
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
	if not _taxi_vehicle.start_drive_to_curbside(destination, world):
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
	if vehicle == null:
		return false
	if vehicle == _taxi_vehicle:
		return true
	return _is_in_returning_trips(vehicle)


func get_state() -> String:
	return _state


func get_planned_fare() -> int:
	return _planned_fare


func get_taxi_vehicle() -> VehicleAgent:
	return _taxi_vehicle if _taxi_vehicle != null and is_instance_valid(_taxi_vehicle) else null


func _ensure_taxi_vehicle(request_origin: Vector3, depot_position: Vector3 = Vector3.INF) -> bool:
	# Reuse the current taxi only while it is free (parked, no driver, not returning).
	if _taxi_vehicle != null and is_instance_valid(_taxi_vehicle) and not _is_vehicle_busy(_taxi_vehicle):
		return true
	var free_vehicle := _find_reusable_taxi_vehicle()
	if free_vehicle != null:
		_taxi_vehicle = free_vehicle
		_taxi_vehicle.add_to_group(TAXI_GROUP)
		_connect_vehicle_signals(_taxi_vehicle)
		return true
	# Every taxi in the scene is currently serving or returning: wait, never spawn extras.
	if _scene_has_taxi_candidate():
		return false

	var instance := TaxiVehicleScene.instantiate()
	if instance == null or instance is not VehicleAgent:
		if instance != null:
			instance.queue_free()
		return false
	_taxi_vehicle = instance as VehicleAgent
	_taxi_vehicle.name = "TaxiVehicle_Car"
	_taxi_vehicle.add_to_group(TAXI_GROUP)
	var parent: Node = world.get_parent() if world != null and world.get_parent() != null else owner_node
	if parent == null:
		_taxi_vehicle.queue_free()
		_taxi_vehicle = null
		return false
	parent.add_child(_taxi_vehicle)
	var spawn_position := depot_position if _is_finite_vector(depot_position) else _vehicle_access_point(request_origin)
	_place_taxi_at(spawn_position)
	if world != null and world.has_method("register_vehicle"):
		world.register_vehicle(_taxi_vehicle)
	_connect_vehicle_signals(_taxi_vehicle)
	return true


# Picks a free taxi from the scene pool, preferring already-tagged taxi vehicles.
# Excludes the active taxi, vehicles with a driver, driving ones, and taxis already
# heading back to the depot, so a reserve taxi serves while another one returns.
func _find_reusable_taxi_vehicle() -> VehicleAgent:
	var candidates := _collect_vehicle_candidates()
	for node in candidates:
		var vehicle := node as VehicleAgent
		if vehicle == null or not is_instance_valid(vehicle):
			continue
		if not vehicle.is_in_group(TAXI_GROUP):
			continue
		if _is_free_taxi_candidate(vehicle):
			return vehicle
	for node2 in candidates:
		var vehicle2 := node2 as VehicleAgent
		if vehicle2 == null or not is_instance_valid(vehicle2):
			continue
		if vehicle2.delivery_vehicle:
			continue
		if not _is_supported_taxi_scene(vehicle2):
			continue
		if _is_free_taxi_candidate(vehicle2):
			return vehicle2
	return null


func _collect_vehicle_candidates() -> Array[Node]:
	var candidates: Array[Node] = []
	if world != null:
		for vehicle in world.vehicles:
			if vehicle is Node:
				candidates.append(vehicle as Node)
	if owner_node != null and owner_node.get_tree() != null:
		for node in owner_node.get_tree().get_nodes_in_group("vehicles"):
			if node is Node and not candidates.has(node):
				candidates.append(node as Node)
	return candidates


func _is_free_taxi_candidate(vehicle: VehicleAgent) -> bool:
	if vehicle == null or not is_instance_valid(vehicle):
		return false
	if vehicle == _taxi_vehicle:
		return false
	return not _is_vehicle_busy(vehicle)


func _is_vehicle_busy(vehicle: VehicleAgent) -> bool:
	if vehicle == null or not is_instance_valid(vehicle):
		return true
	if vehicle.current_driver != null:
		return true
	if vehicle.is_driving():
		return true
	return _is_in_returning_trips(vehicle)


func _is_in_returning_trips(vehicle: Node) -> bool:
	for trip in _returning_trips:
		if trip != null and trip.get_vehicle() == vehicle:
			return true
	return false


func _scene_has_taxi_candidate() -> bool:
	for node in _collect_vehicle_candidates():
		var vehicle := node as VehicleAgent
		if vehicle == null or not is_instance_valid(vehicle):
			continue
		if vehicle.delivery_vehicle:
			continue
		if vehicle.is_in_group(TAXI_GROUP) or _is_supported_taxi_scene(vehicle):
			return true
	return false


func _is_supported_taxi_scene(vehicle: VehicleAgent) -> bool:
	if vehicle == null:
		return false
	if vehicle.scene_file_path == TAXI_VEHICLE_SCENE_PATH:
		return true
	if vehicle.scene_file_path.ends_with("/car.tscn"):
		return true
	return vehicle.name.contains("TaxiVehicle_Car") or vehicle.name == "Car"


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
	# Entering service frees the depot spot the taxi was parked on.
	_release_taxi_parking_spot()
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
	if _should_start_depot_exit_maneuver():
		_pending_pickup_position = pickup_position
		_depot_exit_maneuver_active = true
		return _taxi_vehicle.start_drive_to(_assigned_depot_position, null)
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
	_return_depot_position = Vector3.INF
	_depot_parking_maneuver_active = false
	_billing_suppressed = false
	ride_started.emit(_taxi_vehicle, _rider)
	if _is_finite_vector(_direct_destination_position):
		if _start_direct_destination_drive():
			return
		_emit_status("Taxi konnte die direkte Fahrt nicht starten.", "warning", 2.4)
		_abort_boarded_direct_ride("Direkte Taxi-Fahrt konnte nicht gestartet werden.")
		return
	_show_ride_map()
	_emit_status("Taxi bereit. Ziel auf der Map waehlen.", "success", 2.2)


func _start_direct_destination_drive() -> bool:
	if _taxi_vehicle == null or _rider == null:
		return false
	if not is_instance_valid(_taxi_vehicle) or not is_instance_valid(_rider):
		return false
	var destination := _direct_destination_position
	var route := _build_route(_taxi_vehicle.global_position, destination)
	if route.size() < 2:
		return false
	_planned_destination = destination
	_planned_route = route
	_planned_trip_distance = _route_distance(route)
	_planned_fare = _calculate_fare(_planned_trip_distance)
	_billing_suppressed = false
	_state = STATE_DESTINATION_DRIVE
	_taxi_vehicle.target_building = _direct_destination_building
	if _should_use_direct_destination_parking():
		_ensure_direct_destination_parking_spot()
		var parking_position := _direct_destination_parking_target()
		if _is_finite_vector(parking_position) \
				and _planar_distance(destination, parking_position) <= TAXI_DEPOT_PARKING_MAX_DIRECT_DISTANCE:
			_direct_destination_parking_maneuver_active = true
			_emit_status("Taxi faehrt zum Zielparkplatz. Preis: %d EUR." % _planned_fare, "info", 2.0)
			return _taxi_vehicle.start_drive_to_keep_driver(destination, world)
		_release_direct_destination_parking_spot()
	_direct_destination_parking_maneuver_active = false
	_emit_status("Taxi faehrt zum Ziel. Preis: %d EUR." % _planned_fare, "info", 2.0)
	return _taxi_vehicle.start_drive_to_curbside(destination, world)


func _should_use_direct_destination_parking() -> bool:
	return _direct_destination_marker != null \
		and is_instance_valid(_direct_destination_marker) \
		and _is_finite_vector(_direct_destination_parking_position)


func _ensure_direct_destination_parking_spot() -> void:
	if _direct_destination_parking_spot != null and is_instance_valid(_direct_destination_parking_spot):
		return
	if _direct_destination_marker == null or not is_instance_valid(_direct_destination_marker):
		return
	var depot := VehicleDepotAccess.find_depot_in(_direct_destination_marker)
	if depot == null:
		return
	_direct_destination_parking_spot = depot.reserve_next_parking_spot(_taxi_vehicle)


func _direct_destination_parking_target() -> Vector3:
	if _direct_destination_parking_spot != null and is_instance_valid(_direct_destination_parking_spot):
		return _direct_destination_parking_spot.get_parking_transform().origin
	return _direct_destination_parking_position


func _start_direct_destination_parking_maneuver() -> bool:
	if _taxi_vehicle == null or not is_instance_valid(_taxi_vehicle):
		return false
	var parking_position := _direct_destination_parking_target()
	if not _is_finite_vector(parking_position):
		return false
	var distance := _planar_distance(_taxi_vehicle.global_position, parking_position)
	if distance <= _pickup_radius():
		_taxi_vehicle.unboard_driver(world, parking_position)
		return true
	if distance > TAXI_DEPOT_PARKING_MAX_DIRECT_DISTANCE:
		return false
	_taxi_vehicle.target_building = _direct_destination_building
	return _taxi_vehicle.start_drive_to(parking_position, null)


func _release_direct_destination_parking_spot() -> void:
	if _direct_destination_parking_spot != null and is_instance_valid(_direct_destination_parking_spot):
		_direct_destination_parking_spot.release(_taxi_vehicle)
	_direct_destination_parking_spot = null


func _clear_direct_destination() -> void:
	_release_direct_destination_parking_spot()
	_direct_destination_position = Vector3.INF
	_direct_destination_parking_position = Vector3.INF
	_direct_destination_marker = null
	_direct_destination_building = null
	_direct_destination_parking_maneuver_active = false


func _abort_boarded_direct_ride(message: String) -> void:
	if _taxi_vehicle != null and is_instance_valid(_taxi_vehicle) and _rider != null and is_instance_valid(_rider):
		var failed_rider := _rider
		_rider = null
		_taxi_vehicle.unboard_driver(world, _taxi_vehicle.get_entry_point_global())
		ride_failed.emit(failed_rider, message)
	_reset_service()


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
		if _depot_exit_maneuver_active:
			_depot_exit_maneuver_active = false
			var pickup_position := _pending_pickup_position
			_pending_pickup_position = Vector3.INF
			if _is_finite_vector(pickup_position) and _start_empty_pickup_route(pickup_position):
				return
			_reset_service()
			_emit_status("Taxi findet keine Strassenroute zur Abholung.", "warning", 2.4)
		else:
			_board_pickup_player()
	elif _state == STATE_DESTINATION_DRIVE and _direct_destination_parking_maneuver_active and driver == _rider:
		if _start_direct_destination_parking_maneuver():
			return
		_direct_destination_parking_maneuver_active = false
		_release_direct_destination_parking_spot()
		if _taxi_vehicle != null and is_instance_valid(_taxi_vehicle):
			_taxi_vehicle.unboard_driver(world, _taxi_vehicle.get_entry_point_global())
	elif _state == STATE_RETURN_TO_DEPOT and driver == null:
		if _return_access_exit_maneuver_active:
			_return_access_exit_maneuver_active = false
			if _start_return_road_route():
				return
			_emit_status("Taxi findet keine Strassenroute zum Depot.", "warning", 2.6)
			_reset_service()
		elif _depot_parking_maneuver_active:
			_finish_return_to_depot()
		elif not _start_depot_parking_maneuver():
			_finish_return_to_depot()


func _on_taxi_driver_exited(vehicle: VehicleAgent, driver: Citizen) -> void:
	if vehicle != _taxi_vehicle:
		return
	if driver == null or driver != _rider:
		return
	var fare := _planned_fare
	var paid := _charge_fare(driver, fare)
	if _state == STATE_DESTINATION_DRIVE and vehicle.is_driving():
		vehicle.stop_vehicle()
	_release_direct_destination_parking_spot()
	ride_finished.emit(vehicle, driver, fare, paid)
	_clear_direct_destination()
	if fare > 0:
		var status := "Taxi-Fahrt bezahlt: %d EUR." % fare if paid else "Taxi-Fahrt beendet, aber %d EUR konnten nicht bezahlt werden." % fare
		_emit_status(status, "success" if paid else "warning", 2.6)
	else:
		_emit_status("Taxi-Fahrt beendet.", "info", 2.0)
	_begin_return_to_depot()


func _begin_return_to_depot() -> void:
	if _taxi_vehicle == null or not is_instance_valid(_taxi_vehicle):
		_reset_service()
		return
	_rider = null
	_pickup_player = null
	_planned_destination = Vector3.INF
	_planned_route = PackedVector3Array()
	_planned_trip_distance = 0.0
	_planned_fare = 0
	_billing_suppressed = false
	if map_overlay != null:
		map_overlay.hide_map()
		map_overlay.clear_route()
		map_overlay.clear_selected_position()

	var depot_parking_position := _assigned_depot_parking_position if _is_finite_vector(_assigned_depot_parking_position) else _resolve_taxi_depot_parking_position(_taxi_vehicle.global_position)
	if not _is_finite_vector(depot_parking_position):
		_emit_status("Taxi-Fahrt beendet. Kein TaxiVehicleDepot gefunden.", "warning", 2.6)
		_reset_service()
		return
	_assigned_depot_parking_position = depot_parking_position
	_assigned_depot_position = _vehicle_access_point(depot_parking_position)
	if _start_return_access_exit_if_needed():
		return
	if not _start_return_road_route():
		_emit_status("Taxi findet keine Strassenroute zum Depot.", "warning", 2.6)
		_reset_service()
		return
	_emit_status("Taxi faehrt zurueck zum Depot.", "info", 2.0)


func _start_return_access_exit_if_needed() -> bool:
	if _taxi_vehicle == null or not is_instance_valid(_taxi_vehicle):
		return false
	var current_access := _vehicle_access_point(_taxi_vehicle.global_position)
	if not _is_finite_vector(current_access):
		return false
	var distance_to_access := _planar_distance(_taxi_vehicle.global_position, current_access)
	if distance_to_access <= _pickup_radius():
		return false
	if distance_to_access > TAXI_DEPOT_PARKING_MAX_DIRECT_DISTANCE:
		return false
	_state = STATE_RETURN_TO_DEPOT
	_depot_parking_maneuver_active = false
	_return_access_exit_maneuver_active = true
	_return_access_position = current_access
	_return_depot_position = _assigned_depot_position
	_taxi_vehicle.target_building = null
	return _taxi_vehicle.start_drive_to(current_access, null)


func _start_return_road_route() -> bool:
	if _taxi_vehicle == null or not is_instance_valid(_taxi_vehicle):
		return false
	var route := _build_route(_taxi_vehicle.global_position, _assigned_depot_position)
	if route.size() < 2:
		return false
	_state = STATE_RETURN_TO_DEPOT
	_depot_parking_maneuver_active = false
	_return_access_exit_maneuver_active = false
	_return_access_position = Vector3.INF
	_return_depot_position = _assigned_depot_position
	_taxi_vehicle.target_building = null
	if not _taxi_vehicle.start_drive_to(_assigned_depot_position, world):
		return false
	return true


func _start_depot_parking_maneuver() -> bool:
	if _taxi_vehicle == null or not is_instance_valid(_taxi_vehicle):
		return false
	_ensure_taxi_parking_spot()
	var parking_position := _taxi_parking_position()
	if not _is_finite_vector(parking_position):
		return false
	_return_depot_position = parking_position
	var distance := _planar_distance(_taxi_vehicle.global_position, parking_position)
	if distance <= _pickup_radius():
		_place_taxi_at(parking_position)
		return false
	if distance > TAXI_DEPOT_PARKING_MAX_DIRECT_DISTANCE:
		_emit_status("Taxi-Depot-Parkflaeche ist zu weit von der Strasse entfernt.", "warning", 2.6)
		return false
	_depot_parking_maneuver_active = true
	_taxi_vehicle.target_building = null
	return _taxi_vehicle.start_drive_to(parking_position, null)


func _finish_return_to_depot() -> void:
	if _taxi_vehicle != null and is_instance_valid(_taxi_vehicle) and _is_finite_vector(_return_depot_position):
		if _planar_distance(_taxi_vehicle.global_position, _return_depot_position) > _pickup_radius():
			_place_taxi_at(_return_depot_position)
	_occupy_taxi_parking_spot()
	_emit_status("Taxi ist am Depot bereit.", "info", 1.8)
	_reset_service()


# Reserves a free VehicleDepot parking spot for the taxi. Falls back to the marker-center
# position when the depot exposes no VehicleParkingSpot.
func _ensure_taxi_parking_spot() -> void:
	if _assigned_parking_spot != null and is_instance_valid(_assigned_parking_spot):
		return
	_assigned_parking_spot = VehicleDepotAccess.reserve_free_parking_spot(
		owner_node, _taxi_vehicle, TAXI_DEPOT_MARKER_NAME
	)


func _taxi_parking_position() -> Vector3:
	if _assigned_parking_spot != null and is_instance_valid(_assigned_parking_spot):
		return _assigned_parking_spot.get_parking_transform().origin
	return _assigned_depot_parking_position


func _occupy_taxi_parking_spot() -> void:
	# Ownership moves onto the vehicle (meta), so the spot is released correctly even
	# if a different object (a return trip) later departs this taxi.
	VehicleDepotAccess.occupy_vehicle_spot(_taxi_vehicle, _assigned_parking_spot)
	_assigned_parking_spot = null


func _release_taxi_parking_spot() -> void:
	VehicleDepotAccess.release_vehicle_spot(_taxi_vehicle)
	if _assigned_parking_spot != null and is_instance_valid(_assigned_parking_spot):
		_assigned_parking_spot.release(_taxi_vehicle)
	_assigned_parking_spot = null


# Hands the active (returning) taxi to a self-driving return trip and frees the
# service slot so a reserve taxi can take the next request. Transfers any reserved
# spot to the trip without releasing or restoring the vehicle here.
func _handoff_active_return_to_trip() -> void:
	var vehicle := _taxi_vehicle
	if vehicle != null and is_instance_valid(vehicle):
		var trip = TaxiReturnTripScript.new()
		trip.start(
			world,
			owner_node,
			vehicle,
			TAXI_DEPOT_MARKER_NAME,
			_pickup_radius(),
			_previous_manual_drive_enabled,
			_assigned_parking_spot
		)
		if not trip.is_done():
			_returning_trips.append(trip)
	_taxi_vehicle = null
	_assigned_parking_spot = null
	_reset_service(false)


func _tick_returning_trips() -> void:
	if _returning_trips.is_empty():
		return
	var still_active: Array = []
	for trip in _returning_trips:
		if trip == null:
			continue
		trip.update()
		if not trip.is_done():
			still_active.append(trip)
	_returning_trips = still_active


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
	_pending_pickup_position = Vector3.INF
	_planned_destination = Vector3.INF
	_planned_route = PackedVector3Array()
	_planned_trip_distance = 0.0
	_planned_fare = 0
	_clear_direct_destination()
	_clear_assigned_depot()
	_return_depot_position = Vector3.INF
	_return_access_position = Vector3.INF
	_depot_exit_maneuver_active = false
	_return_access_exit_maneuver_active = false
	_depot_parking_maneuver_active = false
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


func _resolve_taxi_depot_access_point(from_pos: Vector3) -> Vector3:
	var parking_position := _resolve_taxi_depot_parking_position(from_pos)
	if _is_finite_vector(parking_position):
		return _vehicle_access_point(parking_position)
	return Vector3.INF


func _resolve_taxi_depot_parking_position(from_pos: Vector3) -> Vector3:
	var marker := _find_taxi_vehicle_depot_marker()
	if marker != null:
		return _get_depot_marker_parking_position(marker)
	var depot := _find_nearest_taxi_depot_building(from_pos)
	if depot != null:
		return _vehicle_access_point(depot.get_entrance_pos())
	return Vector3.INF


func _find_direct_destination_marker(destination_building: Building, marker_name: String) -> Node3D:
	var trimmed_name := marker_name.strip_edges()
	if trimmed_name.is_empty():
		return null
	if owner_node == null or owner_node.get_tree() == null:
		return null
	var root := owner_node.get_tree().root
	if root == null:
		return null
	var markers: Array[Node3D] = []
	_collect_named_markers(root, trimmed_name, markers)
	if markers.is_empty():
		return null
	if markers.size() == 1 or destination_building == null:
		return markers[0]
	var best_marker: Node3D = null
	var best_distance := INF
	var building_pos := destination_building.global_position
	for marker in markers:
		if marker == null or not is_instance_valid(marker):
			continue
		var marker_pos := VehicleDepotAccess.get_marker_parking_position(marker)
		if not _is_finite_vector(marker_pos):
			continue
		var distance := _planar_distance(building_pos, marker_pos)
		if best_marker == null or distance < best_distance:
			best_marker = marker
			best_distance = distance
	return best_marker if best_marker != null else markers[0]


func _collect_named_markers(node: Node, marker_name: String, out: Array[Node3D]) -> void:
	if node == null:
		return
	if node is Node3D and String(node.name) == marker_name:
		out.append(node as Node3D)
	for child in node.get_children():
		_collect_named_markers(child, marker_name, out)


func _resolve_direct_destination_parking_position(destination_building: Building, marker: Node3D) -> Vector3:
	if marker != null and is_instance_valid(marker):
		var marker_position := VehicleDepotAccess.get_marker_parking_position(marker)
		if _is_finite_vector(marker_position):
			return marker_position
	if destination_building != null:
		return destination_building.get_entrance_pos() if destination_building.has_method("get_entrance_pos") else destination_building.global_position
	return Vector3.INF


func _find_taxi_vehicle_depot_marker() -> Node3D:
	if owner_node == null or owner_node.get_tree() == null:
		return null
	var root := owner_node.get_tree().root
	if root == null:
		return null
	var marker := root.find_child(TAXI_DEPOT_MARKER_NAME, true, false)
	if marker is Node3D and is_instance_valid(marker):
		return marker as Node3D
	return null


func _get_depot_marker_parking_position(marker: Node3D) -> Vector3:
	var shape := _find_first_collision_shape(marker)
	if shape != null:
		return shape.global_position
	return marker.global_position


func _find_first_collision_shape(node: Node) -> CollisionShape3D:
	for child in node.get_children():
		if child is CollisionShape3D:
			return child as CollisionShape3D
		var nested := _find_first_collision_shape(child)
		if nested != null:
			return nested
	return null


func _find_nearest_taxi_depot_building(from_pos: Vector3) -> Building:
	if world == null:
		return null
	var best: Building = null
	var best_dist := INF
	for building in world.buildings:
		if building == null or not is_instance_valid(building):
			continue
		if building.building_type != Building.BuildingType.TAXI_DEPOT:
			continue
		var dist := _planar_distance(from_pos, building.global_position)
		if dist < best_dist:
			best_dist = dist
			best = building
	return best


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


func _should_start_depot_exit_maneuver() -> bool:
	if _taxi_vehicle == null or not is_instance_valid(_taxi_vehicle):
		return false
	if not _is_finite_vector(_assigned_depot_position) or not _is_finite_vector(_assigned_depot_parking_position):
		return false
	if _depot_exit_maneuver_active:
		return false
	var distance_to_road := _planar_distance(_taxi_vehicle.global_position, _assigned_depot_position)
	if distance_to_road <= _pickup_radius():
		return false
	if distance_to_road > TAXI_DEPOT_PARKING_MAX_DIRECT_DISTANCE:
		return false
	return _planar_distance(_taxi_vehicle.global_position, _assigned_depot_parking_position) <= TAXI_DEPOT_PARKING_MAX_DIRECT_DISTANCE


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


func _is_finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


func _clear_assigned_depot() -> void:
	_assigned_depot_position = Vector3.INF
	_assigned_depot_parking_position = Vector3.INF


func _result(accepted: bool, message: String, kind: String) -> Dictionary:
	return {
		"accepted": accepted,
		"message": message,
		"kind": kind,
	}


func _emit_status(message: String, kind: String, duration_sec: float) -> void:
	status_changed.emit(message, kind, duration_sec)
