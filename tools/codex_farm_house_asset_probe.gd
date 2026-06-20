extends SceneTree

const HOUSE_SCENES := {
	"res://Scenes/FarmAssets/LowPolyCityDiorama/FarmHouse1.tscn": Vector3(2.31, 1.99, 2.29),
	"res://Scenes/FarmAssets/LowPolyCityDiorama/FarmHouse2.tscn": Vector3(2.33, 2.23, 2.73),
}
const FARM_HOUSE_NODES := {
	"res://Scenes/Farm.tscn": "Buildings/SmallBarnModel",
	"res://Scenes/Farm_Windmill.tscn": "Buildings/SmallBarnModel",
}


func _initialize() -> void:
	var errors: Array[String] = []

	for scene_path: String in HOUSE_SCENES:
		var house := _instantiate_scene(scene_path, errors)
		if house == null:
			continue
		root.add_child(house)
		await process_frame

		var bounds := _calculate_mesh_bounds(house)
		var expected_size: Vector3 = HOUSE_SCENES[scene_path]
		if (bounds.size - expected_size).length() > 0.08:
			errors.append("%s has unexpected bounds size %s; expected about %s." % [
				scene_path,
				bounds.size,
				expected_size,
			])
		if absf(bounds.position.y) > 0.03:
			errors.append("%s is not grounded; minimum Y is %.3f." % [scene_path, bounds.position.y])
		print("%s bounds=%s" % [scene_path, bounds])
		house.free()

	for scene_path: String in FARM_HOUSE_NODES:
		var farm := _instantiate_scene(scene_path, errors)
		if farm == null:
			continue
		var node_path := NodePath(FARM_HOUSE_NODES[scene_path])
		var house_node := farm.get_node_or_null(node_path)
		if house_node == null:
			errors.append("%s is missing %s." % [scene_path, node_path])
		elif _count_meshes(house_node) == 0:
			errors.append("%s node %s has no mesh descendants." % [scene_path, node_path])
		farm.free()

	if not errors.is_empty():
		for error in errors:
			push_error(error)
		quit(FAILED)
		return

	print("Farm house asset probe passed: houses=%d farms=%d" % [
		HOUSE_SCENES.size(),
		FARM_HOUSE_NODES.size(),
	])
	quit(OK)


func _instantiate_scene(scene_path: String, errors: Array[String]) -> Node:
	var scene := load(scene_path) as PackedScene
	if scene == null:
		errors.append("Could not load %s." % scene_path)
		return null
	var instance := scene.instantiate()
	if instance == null:
		errors.append("Could not instantiate %s." % scene_path)
	return instance


func _calculate_mesh_bounds(scene_root: Node) -> AABB:
	var bounds := AABB()
	var has_bounds := false
	for node in scene_root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var local_transform := (scene_root as Node3D).global_transform.affine_inverse() * mesh_instance.global_transform
		var mesh_bounds := local_transform * mesh_instance.mesh.get_aabb()
		bounds = mesh_bounds if not has_bounds else bounds.merge(mesh_bounds)
		has_bounds = true
	return bounds


func _count_meshes(node: Node) -> int:
	var count := 1 if node is MeshInstance3D else 0
	for child in node.get_children():
		count += _count_meshes(child)
	return count
