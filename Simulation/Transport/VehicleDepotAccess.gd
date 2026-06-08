extends RefCounted
class_name VehicleDepotAccess

const INVALID_POSITION := Vector3.INF


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
