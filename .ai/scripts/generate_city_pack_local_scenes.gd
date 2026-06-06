extends SceneTree

const SOURCE_DIR := "res://ImportedCitySource/assets/city_pack"

const MANUAL_SCENES := {
	"Building Red Corner": "res://Scenes/Plants/City2/building_red_corner.tscn",
}

const TARGET_DIR_BY_ASSET := {
	"Adventurer": "res://Scenes/Characters/CityPack",
	"Air conditioner": "res://Scenes/Environment/BuildingProps/CityPack",
	"Animated Woman": "res://Scenes/Characters/CityPack",
	"Animated Woman-nIItLV9nxS": "res://Scenes/Characters/CityPack",
	"Animated Woman-qJ2gsTUBHL": "res://Scenes/Characters/CityPack",
	"ATM": "res://Scenes/Environment/CityProps/CityPack",
	"Bench": "res://Scenes/Environment/CityProps/CityPack",
	"Bicycle": "res://Scenes/Vehicles/CityPack",
	"Big Building": "res://Scenes/CityBuildings/city_pack",
	"Billboard": "res://Scenes/Environment/CityProps/CityPack",
	"Box": "res://Scenes/Environment/CityProps/CityPack",
	"Brown Building": "res://Scenes/CityBuildings/city_pack",
	"Building Green": "res://Scenes/CityBuildings/city_pack",
	"Building Red": "res://Scenes/CityBuildings/city_pack",
	"Building Red Corner": "res://Scenes/CityBuildings/city_pack",
	"Bus": "res://Scenes/Vehicles/CityPack",
	"Bus Stop": "res://Scenes/Environment/StreetProps/CityPack",
	"Bus stop sign": "res://Scenes/Environment/StreetProps/CityPack",
	"Car": "res://Scenes/Vehicles/CityPack",
	"Car-unqqkULtRU": "res://Scenes/Vehicles/CityPack",
	"Cone": "res://Scenes/Environment/StreetProps/CityPack",
	"Debris Papers": "res://Scenes/Environment/CityProps/CityPack",
	"Dumpster": "res://Scenes/Environment/CityProps/CityPack",
	"Fence": "res://Scenes/Environment/CityProps/CityPack",
	"Fence End": "res://Scenes/Environment/CityProps/CityPack",
	"Fence Piece": "res://Scenes/Environment/CityProps/CityPack",
	"Fire Exit": "res://Scenes/Environment/BuildingProps/CityPack",
	"Fire hydrant": "res://Scenes/Environment/StreetProps/CityPack",
	"Floor Hole": "res://Scenes/Environment/BuildingProps/CityPack",
	"Flower Pot": "res://Scenes/Plants/CityPack",
	"Flower Pot-Kgt363WkKd": "res://Scenes/Plants/CityPack",
	"Gb Blank": "res://Scenes/CityBuildings/city_pack",
	"Greenhouse": "res://Scenes/CityBuildings/city_pack",
	"Mailbox": "res://Scenes/Environment/CityProps/CityPack",
	"Man": "res://Scenes/Characters/CityPack",
	"Manhole Cover": "res://Scenes/Environment/StreetProps/CityPack",
	"Motorcycle": "res://Scenes/Vehicles/CityPack",
	"Pickup Truck": "res://Scenes/Vehicles/CityPack",
	"Pizza Corner": "res://Scenes/CityBuildings/city_pack",
	"Planter & Bushes": "res://Scenes/Plants/CityPack",
	"Police Car": "res://Scenes/Vehicles/CityPack",
	"Power Box": "res://Scenes/Environment/CityProps/CityPack",
	"RB Blank": "res://Scenes/CityBuildings/city_pack",
	"Road Bits": "res://Scenes/Roads/CityPack",
	"Rock band poster": "res://Scenes/Environment/CityProps/CityPack",
	"Roof Exit": "res://Scenes/Environment/BuildingProps/CityPack",
	"SUV": "res://Scenes/Vehicles/CityPack",
	"Sports Car": "res://Scenes/Vehicles/CityPack",
	"Sports Car-Gzj704DXdr": "res://Scenes/Vehicles/CityPack",
	"Stop sign": "res://Scenes/Environment/StreetProps/CityPack",
	"Traffic Light": "res://Scenes/Environment/StreetProps/CityPack",
	"Trash Can": "res://Scenes/Environment/CityProps/CityPack",
	"Tree": "res://Scenes/Plants/CityPack",
	"Van": "res://Scenes/Vehicles/CityPack",
	"Washing Line": "res://Scenes/Environment/CityProps/CityPack",
	"Yellow Post-it": "res://Scenes/Environment/CityProps/CityPack",
	"trah bag grey": "res://Scenes/Environment/CityProps/CityPack",
}

func _init() -> void:
	var overwrite_existing := _has_arg("--overwrite")
	var generated_count := 0
	var skipped_count := 0
	var failed_count := 0

	var assets := TARGET_DIR_BY_ASSET.keys()
	assets.sort()
	for asset_name in assets:
		if MANUAL_SCENES.has(asset_name):
			print("skip manual scene: %s -> %s" % [asset_name, MANUAL_SCENES[asset_name]])
			skipped_count += 1
			continue

		var source_path := "%s/%s.glb" % [SOURCE_DIR, asset_name]
		var target_path := "%s/%s.tscn" % [TARGET_DIR_BY_ASSET[asset_name], _to_snake_case(asset_name)]
		var result := _generate_scene(asset_name, source_path, target_path, overwrite_existing)
		if result == OK:
			generated_count += 1
		elif result == ERR_ALREADY_EXISTS:
			skipped_count += 1
		else:
			failed_count += 1

	print("CITY_PACK_SCENE_GENERATOR generated=%d skipped=%d failed=%d overwrite=%s" % [
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

	local_root.name = _to_node_name(asset_name)
	if local_root is Node3D:
		(local_root as Node3D).transform = Transform3D.IDENTITY
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

	var child := node.get_child(0)
	if child is MeshInstance3D:
		return false
	if child is AnimationPlayer:
		return false
	if child is Skeleton3D:
		return false
	return child is Node3D

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
		if not is_upper and not is_lower and not is_digit:
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
		output += character.to_lower()
		previous_was_separator = false
	return output.trim_suffix("_")

func _to_node_name(value: String) -> String:
	var output := ""
	var capitalize_next := true
	for index in range(value.length()):
		var character := value[index]
		var is_letter := (character >= "A" and character <= "Z") or (character >= "a" and character <= "z")
		var is_digit := character >= "0" and character <= "9"
		if not is_letter and not is_digit:
			capitalize_next = true
			continue
		if capitalize_next:
			output += character.to_upper()
			capitalize_next = false
		else:
			output += character
	return output

func _has_arg(argument: String) -> bool:
	for current in OS.get_cmdline_user_args():
		if current == argument:
			return true
	return false
