extends SceneTree

const SCENE_PATHS := [
	"res://Main.tscn",
]
const EXPECTED_SCATTER_NAMES := [
	"ForestScatter",
	"MeadowPlantsScatter",
	"PalmsScatter",
]


func _init() -> void:
	print("=== Main island scatter visibility test ===")
	var errors: Array[String] = []
	var total_items := 0
	var total_visible := 0
	for scene_path in SCENE_PATHS:
		var packed := load(scene_path) as PackedScene
		if packed == null:
			errors.append("Could not load %s." % scene_path)
			continue

		var scene_root := packed.instantiate()
		if scene_root == null:
			errors.append("Could not instantiate %s." % scene_path)
			continue
		root.add_child(scene_root)

		var stats := _check_scatter_visibility(scene_root, scene_path, errors)
		total_items += stats[0]
		total_visible += stats[1]
		scene_root.queue_free()
		await process_frame

	if errors.is_empty():
		print("MAIN_ISLAND_SCATTER_VISIBILITY OK: %d scene(s), %d item(s), %d visible instance(s)." % [SCENE_PATHS.size(), total_items, total_visible])
		quit(0)
		return

	for error in errors:
		printerr("FAIL: %s" % error)
	quit(1)


func _check_scatter_visibility(scene_root: Node, scene_path: String, errors: Array[String]) -> Array[int]:
	var item_count := 0
	var visible_instance_total := 0
	for scatter_name in EXPECTED_SCATTER_NAMES:
		var scatter := _find_descendant_by_name(scene_root, scatter_name)
		if scatter == null:
			errors.append("%s: missing scatter node '%s'." % [scene_path, scatter_name])
			continue
		for child in scatter.get_children():
			if not (child is MultiMeshInstance3D):
				continue
			item_count += 1
			var item := child as MultiMeshInstance3D
			var multimesh := item.multimesh
			if multimesh == null:
				errors.append("%s: %s has no MultiMesh." % [scene_path, item.get_path()])
				continue
			if multimesh.mesh == null:
				errors.append("%s: %s has no mesh." % [scene_path, item.get_path()])
			if multimesh.instance_count <= 0:
				errors.append("%s: %s has no instances." % [scene_path, item.get_path()])
				continue
			if multimesh.visible_instance_count == 0:
				errors.append("%s: %s has %d instances but visible_instance_count is 0." % [scene_path, item.get_path(), multimesh.instance_count])
			elif multimesh.visible_instance_count > 0:
				visible_instance_total += mini(multimesh.visible_instance_count, multimesh.instance_count)
			else:
				visible_instance_total += multimesh.instance_count

	if item_count == 0:
		errors.append("%s: no MultiMeshInstance3D items found under expected scatter nodes." % scene_path)
	return [item_count, visible_instance_total]


func _find_descendant_by_name(node: Node, node_name: String) -> Node:
	if node.name == node_name:
		return node
	for child in node.get_children():
		var found := _find_descendant_by_name(child, node_name)
		if found != null:
			return found
	return null
