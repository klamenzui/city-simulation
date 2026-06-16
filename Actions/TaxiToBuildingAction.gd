extends Action
class_name TaxiToBuildingAction

const GoToBuildingActionScript = preload("res://Actions/GoToBuildingAction.gd")
const SimLogger = preload("res://Simulation/Logging/SimLogger.gd")

const PHASE_TAXI := "taxi"
const PHASE_WALK := "walk"
const PHASE_DONE := "done"
const MAX_WAIT_MINUTES := 180
const DIRECT_ENTER_MIN_DISTANCE := 1.0
const DIRECT_ENTER_EXTRA_TOLERANCE := 0.15

var target: Building = null
var destination_marker_name: String = ""
var final_walk_minutes: int = 5

var _taxi_service = null
var _rider: Citizen = null
var _walk_action: Action = null
var _phase: String = PHASE_DONE
var _ride_finished: bool = false
var _failed: bool = false
var _connected: bool = false


func _init(_target: Building = null, _destination_marker_name: String = "", _final_walk_minutes: int = 5) -> void:
	super()
	label = "TaxiTo"
	target = _target
	destination_marker_name = _destination_marker_name
	final_walk_minutes = maxi(_final_walk_minutes, 1)


func start(world, citizen) -> void:
	super.start(world, citizen)
	_rider = citizen
	_phase = PHASE_TAXI
	_ride_finished = false
	_failed = false
	remaining_minutes = 0
	if world == null or citizen == null or target == null:
		_fail("TaxiToBuilding blocked: missing world, citizen, or target.")
		return
	if citizen.current_location == target:
		_phase = PHASE_DONE
		finished = true
		return
	if citizen.has_method("is_inside_vehicle") and citizen.is_inside_vehicle():
		_fail("TaxiToBuilding blocked: citizen already inside a vehicle.")
		return
	_leave_current_location_for_pickup(world, citizen)
	_taxi_service = _resolve_taxi_service(world)
	if _taxi_service == null:
		_fail("TaxiToBuilding blocked: no TaxiService registered on World.")
		return
	_connect_taxi_signals()
	var result: Dictionary = _taxi_service.request_direct_ride_to_building(
		citizen,
		target,
		destination_marker_name
	)
	if not bool(result.get("accepted", false)):
		_fail("TaxiToBuilding request refused: %s" % str(result.get("message", "")))


func tick(world, citizen, dt: int) -> void:
	super.tick(world, citizen, dt)
	if _failed:
		finished = true
		return
	match _phase:
		PHASE_TAXI:
			if _ride_finished:
				_start_final_walk(world, citizen)
				return
			if elapsed_minutes >= MAX_WAIT_MINUTES:
				_fail("TaxiToBuilding timed out waiting for taxi ride.")
		PHASE_WALK:
			_tick_final_walk(world, citizen, dt)
		PHASE_DONE:
			finished = true


func finish(world, citizen) -> void:
	_disconnect_taxi_signals()
	_walk_action = null
	_phase = PHASE_DONE
	if citizen != null and citizen.current_location == target:
		citizen.decision_cooldown_left = 0


func _start_final_walk(world, citizen) -> void:
	if citizen == null or target == null:
		_fail("TaxiToBuilding final walk blocked: missing citizen or target.")
		return
	if citizen.current_location == target:
		_phase = PHASE_DONE
		finished = true
		return
	if _try_direct_enter_target(world, citizen):
		_phase = PHASE_DONE
		finished = true
		return
	_walk_action = GoToBuildingActionScript.new(target, final_walk_minutes, false)
	_phase = PHASE_WALK
	_walk_action.start(world, citizen)
	if _walk_action.is_done():
		_finish_final_walk(world, citizen)


func _tick_final_walk(world, citizen, dt: int) -> void:
	if _walk_action == null:
		_fail("TaxiToBuilding final walk missing action.")
		return
	_walk_action.tick(world, citizen, dt)
	if not _walk_action.is_done():
		return
	_finish_final_walk(world, citizen)


func _finish_final_walk(world, citizen) -> void:
	if _walk_action != null:
		_walk_action.finish(world, citizen)
	_walk_action = null
	if citizen != null and citizen.current_location != target:
		_try_direct_enter_target(world, citizen)
	_phase = PHASE_DONE
	finished = true
	if citizen != null and citizen.current_location != target:
		_failed = true


func _try_direct_enter_target(world, citizen) -> bool:
	if citizen == null or target == null:
		return false
	if citizen.current_location == target:
		return true
	if not citizen.has_method("enter_building"):
		return false
	var tolerance := _direct_enter_tolerance(citizen)
	var can_enter := false
	for entry_point in _resolve_final_entry_points(world, citizen):
		var offset: Vector3 = citizen.global_position - entry_point
		offset.y = 0.0
		if offset.length() <= tolerance:
			can_enter = true
			break
	if not can_enter:
		return false
	if citizen.has_method("stop_travel"):
		citizen.stop_travel()
	citizen.enter_building(target, world)
	citizen.decision_cooldown_left = 0
	return citizen.current_location == target


func _resolve_final_entry_points(world, citizen) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var entrance := target.get_entrance_pos()
	points.append(entrance)
	if citizen != null and citizen.has_method("get_navigation_points_for_building"):
		var nav_points: Dictionary = citizen.get_navigation_points_for_building(target, world)
		if nav_points.has("entrance"):
			_append_unique_entry_point(points, nav_points["entrance"])
		if nav_points.has("access"):
			_append_unique_entry_point(points, nav_points["access"])
	if world != null and world.has_method("get_pedestrian_access_point"):
		_append_unique_entry_point(points, world.get_pedestrian_access_point(entrance, target))
	return points


func _append_unique_entry_point(points: Array[Vector3], point_value) -> void:
	if not point_value is Vector3:
		return
	var point: Vector3 = point_value
	for existing in points:
		if existing.distance_squared_to(point) <= 0.01:
			return
	points.append(point)


func _direct_enter_tolerance(citizen) -> float:
	var arrival_tolerance := 0.0
	if citizen != null:
		var configured_tolerance = citizen.get("final_arrival_distance")
		if typeof(configured_tolerance) == TYPE_FLOAT or typeof(configured_tolerance) == TYPE_INT:
			arrival_tolerance = float(configured_tolerance)
	return maxf(DIRECT_ENTER_MIN_DISTANCE, arrival_tolerance + DIRECT_ENTER_EXTRA_TOLERANCE)


func _leave_current_location_for_pickup(world, citizen) -> void:
	if citizen == null:
		return
	if citizen.has_method("is_inside_building") and citizen.is_inside_building():
		citizen.exit_current_building(world)
	elif citizen.current_location != null and citizen.has_method("leave_current_location"):
		citizen.leave_current_location(world)


func _resolve_taxi_service(world):
	if world != null and world.has_method("get_taxi_service"):
		return world.get_taxi_service()
	return null


func _connect_taxi_signals() -> void:
	if _taxi_service == null or _connected:
		return
	var finished_cb := Callable(self, "_on_taxi_ride_finished")
	if not _taxi_service.ride_finished.is_connected(finished_cb):
		_taxi_service.ride_finished.connect(finished_cb)
	var failed_cb := Callable(self, "_on_taxi_ride_failed")
	if not _taxi_service.ride_failed.is_connected(failed_cb):
		_taxi_service.ride_failed.connect(failed_cb)
	_connected = true


func _disconnect_taxi_signals() -> void:
	if _taxi_service == null or not _connected:
		return
	var finished_cb := Callable(self, "_on_taxi_ride_finished")
	if _taxi_service.ride_finished.is_connected(finished_cb):
		_taxi_service.ride_finished.disconnect(finished_cb)
	var failed_cb := Callable(self, "_on_taxi_ride_failed")
	if _taxi_service.ride_failed.is_connected(failed_cb):
		_taxi_service.ride_failed.disconnect(failed_cb)
	_connected = false


func _on_taxi_ride_finished(_vehicle: VehicleAgent, rider: Citizen, _fare: int, _paid: bool) -> void:
	if rider == _rider:
		_ride_finished = true


func _on_taxi_ride_failed(rider: Citizen, message: String) -> void:
	if rider == _rider:
		_fail(message)


func _fail(message: String) -> void:
	_failed = true
	finished = true
	_phase = PHASE_DONE
	if _rider != null:
		SimLogger.log("[Citizen %s] %s" % [_rider.citizen_name, message])
