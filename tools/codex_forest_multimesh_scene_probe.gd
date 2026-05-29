extends SceneTree

# Validates the generated per-biome Yamms scatter scenes against the recipe in
# config/forest_scatter.json. Structural only (no live generation): each biome
# scene must exist, be a MultiScatter with a >=3 point polygon, expose exactly
# the configured items, and each item must have a MultiMesh+mesh and a placement
# mode child. Runs headless.

const CONFIG_PATH := "res://config/forest_scatter.json"


func _initialize() -> void:
	var config := _load_config()
	var errors: Array[String] = []
	var biome_count := 0
	var item_count := 0
	if config.is_empty():
		errors.append("Could not load %s." % CONFIG_PATH)
	else:
		var stats := _check_biomes(config, errors)
		biome_count = stats[0]
		item_count = stats[1]
	await process_frame
	if errors.is_empty():
		print("Biome scatter probe passed: %d biome(s), %d items." % [biome_count, item_count])
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


# Returns [biome_count, total_item_count].
func _check_biomes(config: Dictionary, errors: Array[String]) -> Array:
	var biomes: Array = config.get("biomes", [])
	if biomes.is_empty():
		errors.append("Config defines no biomes.")
		return [0, 0]

	var dir := str(config.get("output", {}).get("biome_scene_dir", "res://Scenes/Plants/Biomes/"))
	var suffix := str(config.get("output", {}).get("root_suffix", "Scatter"))
	var total_items := 0

	for biome in biomes:
		var biome_name := str(biome.get("name", "Biome"))
		var expected_items: Array = biome.get("items", [])
		var scene_path := "%s%s.tscn" % [dir, biome_name]

		if not ResourceLoader.exists(scene_path):
			errors.append("Biome '%s': scene %s does not exist (run the generator)." % [biome_name, scene_path])
			continue
		var packed := load(scene_path) as PackedScene
		if packed == null:
			errors.append("Biome '%s': could not load %s." % [biome_name, scene_path])
			continue
		var root := packed.instantiate()
		if root == null:
			errors.append("Biome '%s': could not instantiate %s." % [biome_name, scene_path])
			continue

		if not (root is MultiScatter):
			errors.append("Biome '%s': root is %s, expected MultiScatter." % [biome_name, root.get_class()])
		var expected_root := "%s%s" % [biome_name, suffix]
		if root.name != expected_root:
			errors.append("Biome '%s': root node should be named %s, got %s." % [biome_name, expected_root, root.name])

		var path := root as Path3D
		if path != null:
			if path.curve == null or path.curve.get_point_count() < 3:
				errors.append("Biome '%s': polygon needs at least 3 points." % biome_name)

		var items: Array = []
		for child in root.get_children():
			if child is MultiScatterItem:
				items.append(child)
		if items.size() != expected_items.size():
			errors.append("Biome '%s': expected %d items, scene has %d." % [biome_name, expected_items.size(), items.size()])

		for item in items:
			var mm: MultiMesh = item.multimesh
			if mm == null or mm.mesh == null:
				errors.append("Biome '%s': item %s has no MultiMesh/mesh." % [biome_name, item.name])
			var has_placement := false
			for child in item.get_children():
				if child is PlacementMode:
					has_placement = true
					break
			if not has_placement:
				errors.append("Biome '%s': item %s has no placement mode." % [biome_name, item.name])

		total_items += expected_items.size()
		root.free()

	return [biomes.size(), total_items]
