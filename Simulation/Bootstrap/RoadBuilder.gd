extends RefCounted

const ROAD_PARENT_NAME := "RoadNetwork"
const ROAD_WIDTH := 1.4
const ROAD_HEIGHT := 0.08

static func build_simple_roads(root: Node3D, world) -> void:
	if root == null or world == null:
		return

	var road_parent := root.get_node_or_null(ROAD_PARENT_NAME) as Node3D
	if road_parent == null:
		road_parent = Node3D.new()
		road_parent.name = ROAD_PARENT_NAME
		root.add_child(road_parent)

	_clear_children(road_parent)

	var points: Array[Vector3] = _collect_entrance_points(world.buildings)
	if points.size() < 2:
		return

	var hub: Vector3 = _compute_hub(points)
	var road_material := _create_road_material()

	for point in points:
		_add_segment(road_parent, point, hub, road_material)

	_add_hub_patch(road_parent, hub, road_material)

static func _collect_entrance_points(buildings: Array) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for building in buildings:
		if building == null:
			continue
		if not building.has_method("get_entrance_pos"):
			continue
		points.append(building.get_entrance_pos())
	return points

static func _compute_hub(points: Array[Vector3]) -> Vector3:
	var sum := Vector3.ZERO
	for point in points:
		sum += point
	var count: float = float(max(points.size(), 1))
	var hub := sum / count
	hub.y = points[0].y + 0.03
	return hub

static func _create_road_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.14, 0.14, 0.16, 1.0)
	mat.roughness = 0.9
	return mat

static func _add_segment(parent: Node3D, start: Vector3, finish: Vector3, mat: StandardMaterial3D) -> void:
	var diff: Vector3 = finish - start
	diff.y = 0.0
	var length: float = diff.length()
	if length < 0.1:
		return

	var center := (start + finish) * 0.5
	center.y = finish.y

	var mesh := BoxMesh.new()
	mesh.size = Vector3(ROAD_WIDTH, ROAD_HEIGHT, length)

	var road := MeshInstance3D.new()
	road.mesh = mesh
	road.material_override = mat
	road.position = center
	road.rotation.y = atan2(diff.x, diff.z)

	parent.add_child(road)

static func _add_hub_patch(parent: Node3D, hub: Vector3, mat: StandardMaterial3D) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(ROAD_WIDTH * 1.8, ROAD_HEIGHT, ROAD_WIDTH * 1.8)

	var patch := MeshInstance3D.new()
	patch.mesh = mesh
	patch.material_override = mat
	patch.position = hub

	parent.add_child(patch)

static func _clear_children(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()

