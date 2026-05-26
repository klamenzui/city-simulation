extends SceneTree

const FOREST_SCENE_PATH := "res://Scenes/Plants/ForestMultiMesh.tscn"
const MAIN_SCENE_PATH := "res://Main.tscn"
const EXPECTED_MULTIMESH_VARIANTS := 24
const MIN_TOTAL_INSTANCES := 700
const CITY_EXCLUSION := Rect2(Vector2(-12.0, -46.0), Vector2(58.0, 94.0))
const ISLAND_RADIUS := Vector2(122.0, 118.0)
const CATEGORY_MIN_COUNTS := {
	"Trees": 180,
	"Understory": 170,
	"GroundPlants": 300,
	"Flowers": 100,
}


func _initialize() -> void:
	var errors: Array[String] = []
	var total_instances := _check_forest_scene(errors)
	_check_main_scene_reference(errors)
	await process_frame

	if errors.is_empty():
		print("Forest MultiMesh probe passed: instances=%d, variants=%d." % [
			total_instances,
			EXPECTED_MULTIMESH_VARIANTS,
		])
		quit(OK)
		return

	for error in errors:
		push_error(error)
	quit(FAILED)


func _check_forest_scene(errors: Array[String]) -> int:
	var forest_scene := load(FOREST_SCENE_PATH) as PackedScene
	if forest_scene == null:
		errors.append("Could not load %s." % FOREST_SCENE_PATH)
		return 0

	var forest_root := forest_scene.instantiate()
	if forest_root == null:
		errors.append("Could not instantiate %s." % FOREST_SCENE_PATH)
		return 0
	if forest_root.name != "ForestMultiMesh":
		errors.append("Forest scene root must be named ForestMultiMesh.")

	var category_counts: Dictionary = {}
	for category in CATEGORY_MIN_COUNTS.keys():
		category_counts[category] = 0
		if forest_root.get_node_or_null(NodePath(category)) == null:
			errors.append("Forest scene is missing category node %s." % category)

	var multi_mesh_count := 0
	var total_instances := 0
	var invalid_placement_count := 0
	var stack: Array[Node] = []
	stack.append(forest_root)
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is StaticBody3D or node is CollisionShape3D or node is Area3D:
			errors.append("Forest scene must stay visual-only; found %s at %s." % [node.get_class(), node.get_path()])
		if node.is_in_group("buildings") or node.is_in_group("walkable_surface"):
			errors.append("Forest scene must not use gameplay groups at %s." % node.get_path())

		if node is MultiMeshInstance3D:
			var mesh_instance := node as MultiMeshInstance3D
			var multi_mesh := mesh_instance.multimesh
			if multi_mesh == null:
				errors.append("%s has no MultiMesh." % mesh_instance.name)
			else:
				multi_mesh_count += 1
				total_instances += multi_mesh.instance_count
				if multi_mesh.mesh == null:
					errors.append("%s MultiMesh has no mesh." % mesh_instance.name)
				if multi_mesh.instance_count <= 0:
					errors.append("%s should contain visible instances." % mesh_instance.name)
				if multi_mesh.visible_instance_count != multi_mesh.instance_count:
					errors.append("%s visible_instance_count should match instance_count." % mesh_instance.name)
				if multi_mesh.buffer.size() != multi_mesh.instance_count * 12:
					errors.append("%s should serialize one 3D transform buffer per instance." % mesh_instance.name)
				var parent_name := mesh_instance.get_parent().name
				if category_counts.has(parent_name):
					category_counts[parent_name] = int(category_counts[parent_name]) + multi_mesh.instance_count
				invalid_placement_count += _count_invalid_placements(mesh_instance)

		for child in node.get_children():
			stack.append(child)

	if multi_mesh_count != EXPECTED_MULTIMESH_VARIANTS:
		errors.append("Forest scene should contain %d MultiMesh variants, got %d." % [
			EXPECTED_MULTIMESH_VARIANTS,
			multi_mesh_count,
		])
	if total_instances < MIN_TOTAL_INSTANCES:
		errors.append("Forest scene should contain at least %d instances, got %d." % [
			MIN_TOTAL_INSTANCES,
			total_instances,
		])
	for category in CATEGORY_MIN_COUNTS.keys():
		var actual_count := int(category_counts.get(category, 0))
		var min_count := int(CATEGORY_MIN_COUNTS[category])
		if actual_count < min_count:
			errors.append("%s should contain at least %d instances, got %d." % [
				category,
				min_count,
				actual_count,
			])
	if invalid_placement_count > 0:
		errors.append("Forest scene has %d placements inside city exclusion or outside island bounds." % invalid_placement_count)

	forest_root.free()
	return total_instances


func _count_invalid_placements(mesh_instance: MultiMeshInstance3D) -> int:
	var invalid_count := 0
	var multi_mesh := mesh_instance.multimesh
	if multi_mesh == null:
		return invalid_count
	var local_to_scene := _get_local_to_scene_transform(mesh_instance)
	var buffer := multi_mesh.buffer
	for index in range(multi_mesh.instance_count):
		var offset := index * 12
		if offset + 11 >= buffer.size():
			invalid_count += 1
			continue
		var transform := Transform3D(
			Basis(
				Vector3(buffer[offset], buffer[offset + 4], buffer[offset + 8]),
				Vector3(buffer[offset + 1], buffer[offset + 5], buffer[offset + 9]),
				Vector3(buffer[offset + 2], buffer[offset + 6], buffer[offset + 10])
			),
			Vector3(buffer[offset + 3], buffer[offset + 7], buffer[offset + 11])
		)
		transform = local_to_scene * transform
		var point := Vector2(transform.origin.x, transform.origin.z)
		if CITY_EXCLUSION.has_point(point) or not _is_inside_playable_island(point):
			invalid_count += 1
	return invalid_count


func _get_local_to_scene_transform(node: Node3D) -> Transform3D:
	var transform := node.transform
	var parent := node.get_parent()
	while parent is Node3D:
		var parent_3d := parent as Node3D
		transform = parent_3d.transform * transform
		parent = parent.get_parent()
	return transform


func _is_inside_playable_island(point: Vector2) -> bool:
	var normalized := Vector2(point.x / ISLAND_RADIUS.x, point.y / ISLAND_RADIUS.y)
	return normalized.length_squared() <= 1.0


func _check_main_scene_reference(errors: Array[String]) -> void:
	var main_scene := load(MAIN_SCENE_PATH) as PackedScene
	if main_scene == null:
		errors.append("Could not load %s." % MAIN_SCENE_PATH)
		return

	var main := main_scene.instantiate()
	var forest := main.get_node_or_null(NodePath("World/ForestMultiMesh"))
	if forest == null:
		errors.append("Main scene is missing World/ForestMultiMesh.")
	elif forest.scene_file_path != FOREST_SCENE_PATH:
		errors.append("World/ForestMultiMesh should instance %s." % FOREST_SCENE_PATH)
	if main.get_node_or_null(NodePath("World/City/ForestMultiMesh")) != null:
		errors.append("ForestMultiMesh must stay outside World/City.")
	main.free()
