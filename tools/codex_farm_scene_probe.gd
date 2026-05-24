extends SceneTree

const FARM_SCENE_PATH := "res://Scenes/Farm.tscn"


func _initialize() -> void:
	var errors: Array[String] = []
	var scene := load(FARM_SCENE_PATH) as PackedScene
	if scene == null:
		push_error("Could not load %s." % FARM_SCENE_PATH)
		quit(FAILED)
		return

	var farm := scene.instantiate()
	if farm == null:
		push_error("Could not instantiate %s." % FARM_SCENE_PATH)
		quit(FAILED)
		return
	root.add_child(farm)
	await process_frame

	var multimesh_count := _count_nodes_of_type(farm, MultiMeshInstance3D)
	var collision_count := _count_nodes_of_type(farm, CollisionShape3D)
	_check_scene_contract(farm, errors)
	_check_crop_multimeshes(farm, errors)

	if not errors.is_empty():
		for error in errors:
			push_error(error)
		farm.free()
		quit(FAILED)
		return

	print("Farm probe passed: multimeshes=%d collisions=%d groups=%s" % [
		multimesh_count,
		collision_count,
		farm.get_groups(),
	])

	farm.free()
	quit(OK)


func _check_scene_contract(farm: Node, errors: Array[String]) -> void:
	if farm.name != "Farm":
		errors.append("Farm root should be named Farm.")
	if not farm.is_in_group("buildings"):
		errors.append("Farm root must stay in the buildings group.")
	if _count_nodes_of_type(farm, Camera3D) > 0:
		errors.append("Farm prefab must not contain a Camera3D; city cameras own rendering.")

	var required_nodes := [
		"Entrance",
		"ClickArea/CollisionShape3D",
		"Obstacles/HouseShape",
		"Obstacles/BarnShape",
		"Obstacles/SiloShape",
		"Obstacles/TractorShape",
	]
	for node_path in required_nodes:
		if farm.get_node_or_null(NodePath(node_path)) == null:
			errors.append("Missing required Farm node: %s" % node_path)


func _check_crop_multimeshes(farm: Node, errors: Array[String]) -> void:
	var crop_paths := [
		"Fields/FieldWest/CropStemInstances",
		"Fields/FieldWest/CropLeafAInstances",
		"Fields/FieldWest/CropLeafBInstances",
		"Fields/FieldEast/CropStemInstances",
		"Fields/FieldEast/CropLeafAInstances",
		"Fields/FieldEast/CropLeafBInstances",
	]
	for node_path in crop_paths:
		var node := farm.get_node_or_null(NodePath(node_path))
		if node == null:
			errors.append("Missing crop MultiMesh node: %s" % node_path)
			continue
		if node is not MultiMeshInstance3D:
			errors.append("Crop node is not a MultiMeshInstance3D: %s" % node_path)
			continue

		var crop_node := node as MultiMeshInstance3D
		if crop_node.multimesh == null:
			errors.append("Crop MultiMesh node has no MultiMesh resource: %s" % node_path)
			continue
		if crop_node.multimesh.instance_count != 16:
			errors.append("Expected 16 crop instances in %s, found %d." % [
				node_path,
				crop_node.multimesh.instance_count,
			])
		if crop_node.multimesh.buffer.size() != 192:
			errors.append("Expected serialized 3D transform buffer size 192 in %s, found %d." % [
				node_path,
				crop_node.multimesh.buffer.size(),
			])


func _count_nodes_of_type(node: Node, type_ref: Variant) -> int:
	var count := 0
	if is_instance_of(node, type_ref):
		count += 1
	for child in node.get_children():
		count += _count_nodes_of_type(child, type_ref)
	return count
