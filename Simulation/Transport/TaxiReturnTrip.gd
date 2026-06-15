extends RefCounted
class_name TaxiReturnTrip

# Independent "drive back to depot and park" task for a single taxi. The active
# TaxiService hands a finished taxi to one of these so the service slot frees up
# immediately and a reserve taxi can serve the next request while this one parks.
# Driven by polling is_driving() each frame; the vehicle moves itself in physics.

const STATE_TO_ACCESS := "to_access"
const STATE_PARKING := "parking"
const STATE_DONE := "done"
const MAX_LOCAL_MANEUVER_DISTANCE := 16.0

var _world: World = null
var _owner: Node = null
var _vehicle: VehicleAgent = null
var _marker_name: String = "TaxiVehicleDepot"
var _pickup_radius: float = 2.5
var _restore_manual_drive: bool = true
var _state: String = STATE_DONE
var _depot_access: Vector3 = Vector3.INF
var _parking_position: Vector3 = Vector3.INF
var _parking_spot: VehicleParkingSpot = null


# Begins the return. Continues from wherever the taxi currently is, so it is safe to
# hand off a taxi that is already mid-return. Returns false (and parks in place) when
# no depot or no road route exists.
func start(
	world: World,
	owner: Node,
	vehicle: VehicleAgent,
	marker_name: String,
	pickup_radius: float,
	restore_manual_drive: bool,
	reserved_spot: VehicleParkingSpot = null
) -> bool:
	_world = world
	_owner = owner
	_vehicle = vehicle
	_marker_name = marker_name
	_pickup_radius = maxf(pickup_radius, 0.2)
	_restore_manual_drive = restore_manual_drive
	_parking_spot = reserved_spot
	if _vehicle == null or not is_instance_valid(_vehicle):
		_state = STATE_DONE
		return false
	var parking := VehicleDepotAccess.resolve_marker_parking_position(_owner, _marker_name)
	if not VehicleDepotAccess.is_finite_vector(parking):
		_finish()
		return false
	_parking_position = parking
	_depot_access = _access_point(parking)
	_vehicle.target_building = null
	_state = STATE_TO_ACCESS
	if not _vehicle.start_drive_to(_depot_access, _world):
		return _begin_parking()
	return true


func update() -> void:
	if _state == STATE_DONE:
		return
	if _vehicle == null or not is_instance_valid(_vehicle):
		_state = STATE_DONE
		return
	if _vehicle.is_driving():
		return
	match _state:
		STATE_TO_ACCESS:
			_begin_parking()
		STATE_PARKING:
			_finish()


func is_done() -> bool:
	return _state == STATE_DONE


func get_vehicle() -> VehicleAgent:
	return _vehicle


func _begin_parking() -> bool:
	if _parking_spot == null or not is_instance_valid(_parking_spot):
		_parking_spot = VehicleDepotAccess.reserve_free_parking_spot(_owner, _vehicle, _marker_name)
	var target := _parking_target()
	var distance := _planar_distance(_vehicle.global_position, target)
	if distance <= _pickup_radius or distance > MAX_LOCAL_MANEUVER_DISTANCE:
		_finish()
		return false
	_state = STATE_PARKING
	_vehicle.target_building = null
	if not _vehicle.start_drive_to(target, null):
		_finish()
		return false
	return true


func _finish() -> void:
	if _vehicle != null and is_instance_valid(_vehicle):
		var target := _parking_target()
		if VehicleDepotAccess.is_finite_vector(target) and _planar_distance(_vehicle.global_position, target) > _pickup_radius:
			_vehicle.global_position = target
			if _vehicle.has_method("_snap_to_ground_now"):
				_vehicle.call("_snap_to_ground_now")
		VehicleDepotAccess.occupy_vehicle_spot(_vehicle, _parking_spot)
		_vehicle.manual_drive_enabled = _restore_manual_drive
	_state = STATE_DONE


func _parking_target() -> Vector3:
	if _parking_spot != null and is_instance_valid(_parking_spot):
		return _parking_spot.get_parking_transform().origin
	return _parking_position


func _access_point(position: Vector3) -> Vector3:
	if _world != null and _world.has_method("get_vehicle_road_access_point"):
		return _world.get_vehicle_road_access_point(position)
	return position


func _planar_distance(a: Vector3, b: Vector3) -> float:
	var delta := a - b
	delta.y = 0.0
	return delta.length()
