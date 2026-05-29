extends SceneTree

# Validates the baked forest scene against the data-driven recipe in
# config/forest_scatter.json: variant count, per-category instance counts,
# visual-only contract, well-formed MultiMesh buffers, and that placements did
# not collapse to the origin (the symptom of generating under --headless).

const CONFIG_PATH := "res://config/forest_scatter.json"
const MAIN_SCENE_PATH := "res://Main.tscn"
const COUNT_TOLERANCE := 0.9      # allow placement misses / percentage rounding
const ORIGIN_EPSILON_SQ := 0.0001 # instance treated as "at origin" below this
const MAX_ORIGIN_FRACTION := 0.02 # >2% at origin => generation collapsed
const AABB_MARGIN := 1.0


func _initialize() -> void:
	var config := _load_config()
	var errors: Array[String] = []
	if config.is_empty():
		errors.append("Could not load %s." % CONFIG_PATH)
		_finish(errors, 0)
		return

	var total_instances := _check_forest_scene(config, errors)
	_check_main_scene_reference(config, errors)
	await process_frame
	_finish(errors, total_instances)


func _finish(errors: Array[String], total_instances: int) -> void:
	if errors.is_empty():
		print("Forest MultiMesh probe passed: instances=%d." % total_instances)
		quit(0)
		return
	for error in errors:
		push_error(error)
	quit(1)


func _load_config() -> Dictionary:
	if not FileAccess.file_exists(CONFIG_PATH):
		return {}
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return parsed as Dictionary
	return {}


# Resolve expected counts from the config (count * density_multiplier).
func _expected(config: Dictionary) -> Dictionary:
	var items: Array = config.get("items", [])
	var density := float(config.get("global", {}).get("density_multiplier", 1.0))
	var per_category := {}
	var order: Array = []
	var total := 0
	for it in items:
		var cat := str(it.get("category", "Uncategorized"))
		if not order.has(cat):
			order.append(cat)
		var c := int(round(float(it.get("count", 0)) * density))
		per_category[cat] = int(per_category.get(cat, 0)) + c
		total += c
	return {
		"variants": items.size(),
		"categories": order,
		"per_category": per_category,
		"total": total,
	}


func _check_forest_scene(config: Dictionary, errors: Array[String]) -> int:
	var forest_path := str(config.get("output", {}).get("baked_scene", ""))
	var root_name := str(config.get("output", {}).get("root_name", "ForestMultiMesh"))
	var expected := _expected(config)
	var aabb := _custom_aabb(config)

	var forest_scene := load(forest_path) as PackedScene
	if forest_scene == null:
		errors.append("Could not load %s." % forest_path)
		return 0
	var forest_root := forest_scene.instantiate()
	if forest_root == null:
		errors.append("Could not instantiate %s." % forest_path)
		return 0
	if forest_root.name != root_name:
		errors.append("Forest scene root must be named %s." % root_name)

	var category_counts := {}
	for category in expected["categories"]:
		category_counts[category] = 0
		if forest_root.get_node_or_null(NodePath(category)) == null:
			errors.append("Forest scene is missing category node %s." % category)

	var multi_mesh_count := 0
	var total_instances := 0
	var origin_instances := 0
	var outside_aabb := 0
	var stack: Array[Node] = [forest_root]
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
				var stats := _placement_stats(mesh_instance, aabb)
				origin_instances += stats[0]
				outside_aabb += stats[1]

		for child in node.get_children():
			stack.append(child)

	if multi_mesh_count != int(expected["variants"]):
		errors.append("Forest scene should contain %d MultiMesh variants, got %d." % [expected["variants"], multi_mesh_count])

	var min_total := int(floor(float(expected["total"]) * COUNT_TOLERANCE))
	if total_instances < min_total:
		errors.append("Forest scene should contain at least %d instances, got %d." % [min_total, total_instances])

	for category in expected["categories"]:
		var actual := int(category_counts.get(category, 0))
		var min_count := int(floor(float(expected["per_category"][category]) * COUNT_TOLERANCE))
		if actual < min_count:
			errors.append("%s should contain at least %d instances, got %d." % [category, min_count, actual])

	if total_instances > 0:
		var origin_fraction := float(origin_instances) / float(total_instances)
		if origin_fraction > MAX_ORIGIN_FRACTION:
			errors.append("%.0f%% of instances are at the origin (generator likely ran headless / raycast failed)." % (origin_fraction * 100.0))
	if outside_aabb > 0:
		errors.append("%d instances are outside the configured custom_aabb." % outside_aabb)

	forest_root.free()
	return total_instances


# Returns [origin_instances, outside_aabb_instances] for one MultiMeshInstance3D.
func _placement_stats(mesh_instance: MultiMeshInstance3D, aabb: AABB) -> Array:
	var origin_count := 0
	var outside_count := 0
	var multi_mesh := mesh_instance.multimesh
	if multi_mesh == null:
		return [0, 0]
	var local_to_scene := _get_local_to_scene_transform(mesh_instance)
	var buffer := multi_mesh.buffer
	var grown := aabb.grow(AABB_MARGIN)
	for index in range(multi_mesh.instance_count):
		var offset := index * 12
		if offset + 11 >= buffer.size():
			origin_count += 1
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
		if transform.origin.length_squared() < ORIGIN_EPSILON_SQ:
			origin_count += 1
		if not grown.has_point(transform.origin):
			outside_count += 1
	return [origin_count, outside_count]


func _get_local_to_scene_transform(node: Node3D) -> Transform3D:
	var transform := node.transform
	var parent := node.get_parent()
	while parent is Node3D:
		transform = (parent as Node3D).transform * transform
		parent = parent.get_parent()
	return transform


func _custom_aabb(config: Dictionary) -> AABB:
	var c: Dictionary = config.get("global", {}).get("custom_aabb", {})
	var pos := _to_vec3(c.get("position"), Vector3(-124.0, -6.0, -124.0))
	var size := _to_vec3(c.get("size"), Vector3(248.0, 22.0, 248.0))
	return AABB(pos, size)


func _to_vec3(value: Variant, default_value: Vector3) -> Vector3:
	if value is Array and (value as Array).size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return default_value


func _check_main_scene_reference(config: Dictionary, errors: Array[String]) -> void:
	var forest_path := str(config.get("output", {}).get("baked_scene", ""))
	var root_name := str(config.get("output", {}).get("root_name", "ForestMultiMesh"))
	var main_scene := load(MAIN_SCENE_PATH) as PackedScene
	if main_scene == null:
		errors.append("Could not load %s." % MAIN_SCENE_PATH)
		return
	var main := main_scene.instantiate()
	var forest := main.get_node_or_null(NodePath("World/%s" % root_name))
	if forest == null:
		errors.append("Main scene is missing World/%s." % root_name)
	elif forest.scene_file_path != forest_path:
		errors.append("World/%s should instance %s." % [root_name, forest_path])
	if main.get_node_or_null(NodePath("World/City/%s" % root_name)) != null:
		errors.append("%s must stay outside World/City." % root_name)
	main.free()
