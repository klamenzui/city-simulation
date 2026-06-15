extends RefCounted
class_name VehicleDepotAccess

const INVALID_POSITION := Vector3.INF
const DELIVERY_DEPOT_MARKER_NAME := "DeliveryVehicleDepot"
const DELIVERY_DEPOT_GROUP := "delivery_vehicle_depots"
const DELIVERY_LOADING_DEPOT_MARKER_NAME := "DeliveryLoadingDepot"
const DELIVERY_LOADING_DEPOT_GROUP := "delivery_loading_depots"
const DELIVERY_VEHICLE_ASSIGNED_GROUP := "delivery_vehicle_assigned"
const PREFERRED_DELIVERY_VEHICLE_SCENE_PATH := "res://scenes/vehicles/citypack/pickup_truck.tscn"
const DEPOT_PARKING_MARGIN := 0.75
const DEFAULT_DEPOT_PARKING_RADIUS := 2.0
# Spot a vehicle currently occupies is tracked on the vehicle itself, so spot
# ownership survives across service/return-trip objects (taxi fleet).
const PARKING_SPOT_META := "vehicle_parking_spot"


static func find_marker(owner_node: Node, marker_name: String) -> Node3D:
	if owner_node == null or marker_name.strip_edges().is_empty():
		return null
	var tree := owner_node.get_tree()
	if tree == null:
		return null
	var root := tree.root
	if root == null:
		return null
	var markers: Array[Node3D] = []
	_collect_marker_candidates(root, marker_name, markers)
	if markers.is_empty():
		return null
	if markers.size() == 1:
		return markers[0]
	var owner_position := _resolve_owner_anchor_position(owner_node)
	if not is_finite_vector(owner_position):
		return markers[0]
	return _find_nearest_marker(markers, owner_position)


static func resolve_marker_parking_position(owner_node: Node, marker_name: String) -> Vector3:
	var marker := find_marker(owner_node, marker_name)
	if marker == null:
		return INVALID_POSITION
	return get_marker_parking_position(marker)


static func get_marker_parking_position(marker: Node3D) -> Vector3:
	if marker == null:
		return INVALID_POSITION
	var shape := find_first_collision_shape(marker)
	if shape != null:
		return shape.global_position
	return marker.global_position


# Resolves the VehicleDepot instance behind a named depot marker. The marker node may
# carry the VehicleDepot script itself (delivery depot) or wrap it in a child node
# (taxi depot), so search self-then-descendants for the first VehicleDepot.
static func resolve_depot(owner_node: Node, marker_name: String = DELIVERY_DEPOT_MARKER_NAME) -> VehicleDepot:
	return find_depot_in(find_marker(owner_node, marker_name))


static func find_depot_in(node: Node) -> VehicleDepot:
	if node == null:
		return null
	if node is VehicleDepot:
		return node as VehicleDepot
	for child in node.get_children():
		var nested := find_depot_in(child)
		if nested != null:
			return nested
	return null


# Reserves the next free parking spot at the named depot for the given vehicle.
# Returns null when no depot or no free spot exists; callers then fall back to the
# marker-center parking position so the maneuver still completes.
static func reserve_free_parking_spot(
	owner_node: Node,
	vehicle: Node,
	marker_name: String = DELIVERY_DEPOT_MARKER_NAME
) -> VehicleParkingSpot:
	var depot := resolve_depot(owner_node, marker_name)
	if depot == null:
		return null
	return depot.reserve_next_parking_spot(vehicle)


# Marks the vehicle as occupying the spot and records it on the vehicle so any later
# departure can release it, regardless of which object parked it.
static func occupy_vehicle_spot(vehicle: Node, spot: VehicleParkingSpot) -> void:
	if vehicle == null or not is_instance_valid(vehicle):
		return
	if spot == null or not is_instance_valid(spot):
		return
	spot.occupy(vehicle)
	vehicle.set_meta(PARKING_SPOT_META, spot)


# Releases the spot the vehicle last occupied (tracked via meta). Safe to call when
# the vehicle holds no spot.
static func release_vehicle_spot(vehicle: Node) -> void:
	if vehicle == null or not is_instance_valid(vehicle):
		return
	if not vehicle.has_meta(PARKING_SPOT_META):
		return
	var spot: Variant = vehicle.get_meta(PARKING_SPOT_META)
	if spot is VehicleParkingSpot and is_instance_valid(spot):
		(spot as VehicleParkingSpot).release(vehicle)
	vehicle.remove_meta(PARKING_SPOT_META)


static func get_marker_parking_radius(marker: Node3D) -> float:
	if marker == null:
		return DEFAULT_DEPOT_PARKING_RADIUS
	var shape_node := find_first_collision_shape(marker)
	if shape_node == null or shape_node.shape == null:
		return _get_depot_parking_radius(marker)
	var shape := shape_node.shape
	if shape is BoxShape3D:
		var box := shape as BoxShape3D
		return maxf(maxf(box.size.x, box.size.z) * 0.5 + DEPOT_PARKING_MARGIN, 1.0)
	if shape is SphereShape3D:
		return maxf((shape as SphereShape3D).radius + DEPOT_PARKING_MARGIN, 1.0)
	if shape is CapsuleShape3D:
		return maxf((shape as CapsuleShape3D).radius + DEPOT_PARKING_MARGIN, 1.0)
	return _get_depot_parking_radius(marker)


static func find_first_collision_shape(node: Node) -> CollisionShape3D:
	if node == null:
		return null
	for child in node.get_children():
		if child is CollisionShape3D:
			return child as CollisionShape3D
		var nested := find_first_collision_shape(child)
		if nested != null:
			return nested
	return null


static func is_finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


static func planar_distance(a: Vector3, b: Vector3) -> float:
	var delta := a - b
	delta.y = 0.0
	return delta.length()


static func _collect_marker_candidates(node: Node, marker_name: String, markers: Array[Node3D]) -> void:
	if node == null:
		return
	if node is Node3D and _is_marker_candidate(node, marker_name):
		markers.append(node as Node3D)
	for child in node.get_children():
		_collect_marker_candidates(child, marker_name, markers)


static func _is_marker_candidate(node: Node, marker_name: String) -> bool:
	if node == null:
		return false
	var node_name := String(node.name)
	if node_name == marker_name:
		return true
	if marker_name == DELIVERY_DEPOT_MARKER_NAME:
		return node_name.begins_with(DELIVERY_DEPOT_MARKER_NAME) or node.is_in_group(DELIVERY_DEPOT_GROUP)
	if marker_name == DELIVERY_LOADING_DEPOT_MARKER_NAME:
		return node_name.begins_with(DELIVERY_LOADING_DEPOT_MARKER_NAME) or node.is_in_group(DELIVERY_LOADING_DEPOT_GROUP)
	return false


static func _resolve_owner_anchor_position(owner_node: Node) -> Vector3:
	var current := owner_node
	while current != null:
		if current is Node3D:
			return (current as Node3D).global_position
		current = current.get_parent()
	return INVALID_POSITION


static func _find_nearest_marker(markers: Array[Node3D], owner_position: Vector3) -> Node3D:
	var best_marker: Node3D = null
	var best_distance := INF
	for marker in markers:
		if marker == null or not is_instance_valid(marker):
			continue
		var marker_position := get_marker_parking_position(marker)
		if not is_finite_vector(marker_position):
			continue
		var distance := planar_distance(owner_position, marker_position)
		if best_marker == null or distance < best_distance:
			best_marker = marker
			best_distance = distance
	return best_marker if best_marker != null else markers[0]


static func _get_depot_parking_radius(marker: Node3D) -> float:
	var depot := find_depot_in(marker)
	if depot == null:
		return DEFAULT_DEPOT_PARKING_RADIUS
	var spots_root := depot.get_node_or_null(depot.parking_spots_root_path) as Node3D
	if spots_root == null:
		return DEFAULT_DEPOT_PARKING_RADIUS
	var max_distance := 0.0
	for child in spots_root.get_children():
		var spot := child as Node3D
		if spot == null:
			continue
		max_distance = maxf(max_distance, planar_distance(depot.global_position, spot.global_position))
	return maxf(max_distance + DEPOT_PARKING_MARGIN, DEFAULT_DEPOT_PARKING_RADIUS)


static func get_delivery_vehicle_load_capacity(vehicle: Node, fallback_capacity: int) -> int:
	var fallback := maxi(fallback_capacity, 1)
	if vehicle == null or not is_instance_valid(vehicle):
		return fallback
	var capacity_value: Variant = vehicle.get("delivery_load_capacity")
	if capacity_value is int or capacity_value is float:
		return maxi(int(capacity_value), 1)
	return fallback


# Picks a delivery-capable VehicleAgent already present in the depot fleet.
# Skips vehicles with a driver or already claimed by another building, so the
# fleet stays bounded to whatever the player placed in the scene.
static func find_available_delivery_vehicle(
	owner_node: Node,
	world: Node,
	marker_name: String = DELIVERY_DEPOT_MARKER_NAME
) -> VehicleAgent:
	var candidates: Array[Node] = []
	if world != null:
		var world_vehicles: Variant = world.get("vehicles")
		if world_vehicles is Array:
			for entry in world_vehicles:
				if entry is Node:
					candidates.append(entry as Node)
	if owner_node != null:
		var tree := owner_node.get_tree()
		if tree != null:
			for node in tree.get_nodes_in_group("vehicles"):
				if node is Node and not candidates.has(node):
					candidates.append(node as Node)
	var depot_marker := find_marker(owner_node, marker_name)
	var depot_position := get_marker_parking_position(depot_marker) if depot_marker != null else INVALID_POSITION
	var depot_radius := get_marker_parking_radius(depot_marker)
	var ranked: Array[Dictionary] = []
	for node in candidates:
		if node == null or not is_instance_valid(node):
			continue
		if node is not VehicleAgent:
			continue
		var vehicle := node as VehicleAgent
		if not _is_vehicle_available_for_delivery(vehicle):
			continue
		var depot_distance := 0.0
		if depot_marker != null:
			depot_distance = planar_distance(vehicle.global_position, depot_position)
			if depot_distance > depot_radius:
				continue
		ranked.append({
			"vehicle": vehicle,
			"distance": depot_distance,
			"priority": _delivery_vehicle_priority(vehicle),
		})
	if ranked.is_empty():
		return null
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var priority_a := int(a.get("priority", 0))
		var priority_b := int(b.get("priority", 0))
		if priority_a != priority_b:
			return priority_a < priority_b
		return float(a.get("distance", 0.0)) < float(b.get("distance", 0.0))
	)
	return ranked[0].get("vehicle", null) as VehicleAgent


static func _is_vehicle_available_for_delivery(vehicle: VehicleAgent) -> bool:
	if vehicle == null or not is_instance_valid(vehicle):
		return false
	if not vehicle.delivery_vehicle:
		return false
	if vehicle.is_in_group(DELIVERY_VEHICLE_ASSIGNED_GROUP):
		return false
	if vehicle.current_driver != null:
		return false
	return true


static func _delivery_vehicle_priority(vehicle: VehicleAgent) -> int:
	if vehicle == null:
		return 100
	var scene_path := vehicle.scene_file_path.to_lower()
	if scene_path == PREFERRED_DELIVERY_VEHICLE_SCENE_PATH:
		return 0
	if vehicle.name.to_lower().contains("pickup"):
		return 1
	if scene_path.ends_with("pickup_truck.tscn"):
		return 1
	return 10
