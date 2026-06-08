extends RefCounted
class_name VehicleDepotAccess

const INVALID_POSITION := Vector3.INF
const DELIVERY_DEPOT_MARKER_NAME := "DeliveryVehicleDepot"
const DELIVERY_VEHICLE_ASSIGNED_GROUP := "delivery_vehicle_assigned"
const PREFERRED_DELIVERY_VEHICLE_SCENE_PATH := "res://scenes/vehicles/citypack/pickup_truck.tscn"
const DEPOT_PARKING_MARGIN := 0.75
const DEFAULT_DEPOT_PARKING_RADIUS := 2.0


static func find_marker(owner_node: Node, marker_name: String) -> Node3D:
	if owner_node == null or marker_name.strip_edges().is_empty():
		return null
	var tree := owner_node.get_tree()
	if tree == null:
		return null
	var root := tree.root
	if root == null:
		return null
	var marker := root.find_child(marker_name, true, false)
	if marker is Node3D and is_instance_valid(marker):
		return marker as Node3D
	return null


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


static func get_marker_parking_radius(marker: Node3D) -> float:
	if marker == null:
		return DEFAULT_DEPOT_PARKING_RADIUS
	var shape_node := find_first_collision_shape(marker)
	if shape_node == null or shape_node.shape == null:
		return DEFAULT_DEPOT_PARKING_RADIUS
	var shape := shape_node.shape
	if shape is BoxShape3D:
		var box := shape as BoxShape3D
		return maxf(maxf(box.size.x, box.size.z) * 0.5 + DEPOT_PARKING_MARGIN, 1.0)
	if shape is SphereShape3D:
		return maxf((shape as SphereShape3D).radius + DEPOT_PARKING_MARGIN, 1.0)
	if shape is CapsuleShape3D:
		return maxf((shape as CapsuleShape3D).radius + DEPOT_PARKING_MARGIN, 1.0)
	return DEFAULT_DEPOT_PARKING_RADIUS


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
