extends SceneTree

const SOURCE_DIR := "res://ImportedCitySource/assets/city2"
const ROOT_SCALE := 0.2

const TARGET_DIR_BY_ASSET := {
	"Bench": "res://Scenes/Environment/CityProps",
	"Birchtree": "res://Scenes/Plants/City2",
	"Chair": "res://Scenes/Environment/CityProps",
	"Church": "res://Scenes/CityBuildings/landmarks",
	"Fence": "res://Scenes/Environment/CityProps",
	"FenceEnd": "res://Scenes/Environment/CityProps",
	"Foliage": "res://Scenes/Plants/City2",
	"Foliage2": "res://Scenes/Plants/City2",
	"Foliage3": "res://Scenes/Plants/City2",
	"House-1-1": "res://Scenes/CityBuildings/multi_building",
	"House-1-2": "res://Scenes/CityBuildings/multi_building",
	"House-1-3": "res://Scenes/CityBuildings/multi_building",
	"House-1-4": "res://Scenes/CityBuildings/multi_building",
	"House-1-5": "res://Scenes/CityBuildings/multi_building",
	"House-2-1": "res://Scenes/CityBuildings/multi_building",
	"House-2-2": "res://Scenes/CityBuildings/multi_building",
	"Lamppost": "res://Scenes/Environment/CityProps",
	"Lighthouse": "res://Scenes/CityBuildings/landmarks",
	"Parasol": "res://Scenes/Environment/CityProps",
	"RiverBridge": "res://Scenes/Environment/River",
	"RiverLand": "res://Scenes/Environment/River",
	"RiverWall": "res://Scenes/Environment/River",
	"RiverWallCorner": "res://Scenes/Environment/River",
	"RiverWallOpen": "res://Scenes/Environment/River",
	"RiverWallStairs": "res://Scenes/Environment/River",
	"Ship": "res://Scenes/Environment/Watercraft",
	"ShoreRock": "res://Scenes/Environment/River",
	"Table": "res://Scenes/Environment/CityProps",
}

func _init() -> void:
	var overwrite_existing := _has_arg("--overwrite")
	var generated_count := 0
	var skipped_count := 0
	var failed_count := 0

	var assets := TARGET_DIR_BY_ASSET.keys()
	assets.sort()
	for asset_name in assets:
		var source_path := "%s/%s.glb" % [SOURCE_DIR, asset_name]
		var target_path := "%s/%s.tscn" % [TARGET_DIR_BY_ASSET[asset_name], _to_snake_case(asset_name)]
		var result := _generate_scene(asset_name, source_path, target_path, overwrite_existing)
		if result == OK:
			generated_count += 1
		elif result == ERR_ALREADY_EXISTS:
			skipped_count += 1
		else:
			failed_count += 1

	print("CITY2_SCENE_GENERATOR generated=%d skipped=%d failed=%d overwrite=%s" % [
		generated_count,
		skipped_count,
		failed_count,
		str(overwrite_existing),
	])
	quit(1 if failed_count > 0 else 0)

func _generate_scene(asset_name: String, source_path: String, target_path: String, overwrite_existing: bool) -> Error:
	if not ResourceLoader.exists(source_path):
		push_error("Missing source GLB: %s" % source_path)
		return ERR_FILE_NOT_FOUND
	if ResourceLoader.exists(target_path) and not overwrite_existing:
		print("skip existing: ", target_path)
		return ERR_ALREADY_EXISTS

	var source_scene := ResourceLoader.load(source_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	if source_scene == null:
		push_error("Failed to load source GLB: %s" % source_path)
		return ERR_CANT_OPEN

	var imported_root := source_scene.instantiate()
	if imported_root == null:
		push_error("Failed to instantiate source GLB: %s" % source_path)
		return ERR_CANT_CREATE

	var local_root := _extract_content_root(imported_root)
	if local_root == null:
		imported_root.free()
		push_error("No content root found in source GLB: %s" % source_path)
		return ERR_INVALID_DATA

	if local_root.get_parent() != null:
		local_root.get_parent().remove_child(local_root)
	if imported_root != local_root:
		imported_root.free()

	local_root.name = asset_name
	if local_root is Node3D:
		(local_root as Node3D).transform = Transform3D.IDENTITY.scaled(Vector3(ROOT_SCALE, ROOT_SCALE, ROOT_SCALE))
	_clear_unique_names(local_root)
	_set_owner_recursive(local_root, local_root)

	var packed_scene := PackedScene.new()
	var pack_error := packed_scene.pack(local_root)
	if pack_error != OK:
		local_root.free()
		push_error("Pack failed for %s: %s" % [source_path, pack_error])
		return pack_error

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target_path.get_base_dir()))
	var save_error := ResourceSaver.save(packed_scene, target_path)
	if save_error != OK:
		local_root.free()
		push_error("Save failed for %s: %s" % [target_path, save_error])
		return save_error

	local_root.free()
	print("generated: ", target_path)
	return OK

func _extract_content_root(root_node: Node) -> Node:
	var current := root_node
	while _is_redundant_import_wrapper(current):
		current = current.get_child(0)
	return current

func _is_redundant_import_wrapper(node: Node) -> bool:
	if not node is Node3D:
		return false
	if node is MeshInstance3D:
		return false
	if node.get_child_count() != 1:
		return false
	return node.get_child(0) is Node3D

func _set_owner_recursive(node: Node, scene_owner: Node) -> void:
	if node != scene_owner:
		node.owner = scene_owner
	for child in node.get_children():
		_set_owner_recursive(child, scene_owner)

func _clear_unique_names(node: Node) -> void:
	node.unique_name_in_owner = false
	for child in node.get_children():
		_clear_unique_names(child)

func _to_snake_case(value: String) -> String:
	var output := ""
	var previous_was_separator := false
	for index in range(value.length()):
		var character := value[index]
		var is_upper := character >= "A" and character <= "Z"
		var is_digit := character >= "0" and character <= "9"
		var is_lower := character >= "a" and character <= "z"
		if character == "-" or character == " ":
			if not previous_was_separator and not output.is_empty():
				output += "_"
			previous_was_separator = true
			continue
		if is_upper and index > 0 and not previous_was_separator:
			var previous := value[index - 1]
			var previous_is_lower_or_digit := (previous >= "a" and previous <= "z") or (previous >= "0" and previous <= "9")
			var next_is_lower := index + 1 < value.length() and value[index + 1] >= "a" and value[index + 1] <= "z"
			if previous_is_lower_or_digit or next_is_lower:
				output += "_"
		if is_upper or is_lower or is_digit:
			output += character.to_lower()
			previous_was_separator = false
	return output

func _has_arg(argument: String) -> bool:
	for current in OS.get_cmdline_user_args():
		if current == argument:
			return true
	return false
