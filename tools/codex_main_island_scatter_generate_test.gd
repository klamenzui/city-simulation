extends SceneTree

const SCENE_PATHS := [
	"res://Main.tscn",
]
const GENERATE_AMOUNT := 16
const SCATTER_NAMES := [
	"ForestScatter",
	"MeadowPlantsScatter",
	"PalmsScatter",
]


func _init() -> void:
	print("=== Main island scatter generate test ===")
	var errors: Array[String] = []
	var total_generated := 0
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
		await process_frame
		await physics_frame

		for scatter_name in SCATTER_NAMES:
			var scatter := _find_descendant_by_name(scene_root, scatter_name) as MultiScatter
			if scatter == null:
				errors.append("%s: missing MultiScatter '%s'." % [scene_path, scatter_name])
				continue
			scatter.amount = GENERATE_AMOUNT
			scatter.do_generate()
			var stats := _collect_scatter_stats(scatter, scene_path, errors)
			total_generated += stats[1]
			total_visible += stats[2]

		scene_root.queue_free()
		await process_frame

	if errors.is_empty():
		print("MAIN_ISLAND_SCATTER_GENERATE OK: scenes=%d generated=%d visible=%d." % [SCENE_PATHS.size(), total_generated, total_visible])
		quit(0)
		return

	for error in errors:
		printerr("FAIL: %s" % error)
	quit(1)


func _collect_scatter_stats(scatter: Node, scene_path: String, errors: Array[String]) -> Array[int]:
	var item_count := 0
	var generated_count := 0
	var visible_count := 0
	for child in scatter.get_children():
		if not (child is MultiMeshInstance3D):
			continue
		item_count += 1
		var item := child as MultiMeshInstance3D
		var multimesh := item.multimesh
		if multimesh == null:
			errors.append("%s: %s has no MultiMesh after generate." % [scene_path, item.get_path()])
			continue
		if multimesh.instance_count <= 0:
			continue
		generated_count += multimesh.instance_count
		if multimesh.visible_instance_count == 0:
			errors.append("%s: %s generated %d instance(s), but visible_instance_count stayed 0." % [scene_path, item.get_path(), multimesh.instance_count])
			continue
		visible_count += multimesh.visible_instance_count if multimesh.visible_instance_count > 0 else multimesh.instance_count

	if item_count == 0:
		errors.append("%s: %s has no MultiMeshInstance3D children." % [scene_path, scatter.get_path()])
	if generated_count == 0:
		errors.append("%s: %s generated no instances." % [scene_path, scatter.get_path()])
	return [item_count, generated_count, visible_count]


func _find_descendant_by_name(node: Node, node_name: String) -> Node:
	if node.name == node_name:
		return node
	for child in node.get_children():
		var found := _find_descendant_by_name(child, node_name)
		if found != null:
			return found
	return null
