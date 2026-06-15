extends Node3D
class_name VehicleParkingSpot

var reserved_by: Node = null
var occupied_by: Node = null

func is_free() -> bool:
	return reserved_by == null and occupied_by == null

func reserve(vehicle: Node) -> bool:
	if not is_free():
		return false

	reserved_by = vehicle
	return true

func occupy(vehicle: Node) -> void:
	# Only the reserved vehicle may occupy this spot.
	if reserved_by != null and reserved_by != vehicle:
		return

	occupied_by = vehicle
	reserved_by = null

func release(vehicle: Node = null) -> void:
	# Passing null clears the spot completely.
	if vehicle == null or reserved_by == vehicle:
		reserved_by = null

	if vehicle == null or occupied_by == vehicle:
		occupied_by = null

func get_parking_transform() -> Transform3D:
	return global_transform
