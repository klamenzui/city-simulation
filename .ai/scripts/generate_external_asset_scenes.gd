extends SceneTree

const ASSETS := [
	{
		"name": "FloorBrick",
		"source": "res://ImportedCitySource/assets/medieval_village/Floor_Brick.gltf",
		"target": "res://Scenes/Environment/Ground/MedievalVillage/floor_brick.tscn",
	},
	{
		"name": "FloorRedBrick",
		"source": "res://ImportedCitySource/assets/medieval_village/Floor_RedBrick.gltf",
		"target": "res://Scenes/Environment/Ground/MedievalVillage/floor_red_brick.tscn",
	},
	{
		"name": "FloorUnevenBrick",
		"source": "res://ImportedCitySource/assets/medieval_village/Floor_UnevenBrick.gltf",
		"target": "res://Scenes/Environment/Ground/MedievalVillage/floor_uneven_brick.tscn",
	},
	{
		"name": "Vine1",
		"source": "res://ImportedCitySource/assets/medieval_village/Prop_Vine1.gltf",
		"target": "res://Scenes/Plants/MedievalVillage/vine_1.tscn",
	},
	{
		"name": "Vine2",
		"source": "res://ImportedCitySource/assets/medieval_village/Prop_Vine2.gltf",
		"target": "res://Scenes/Plants/MedievalVillage/vine_2.tscn",
	},
	{
		"name": "Vine4",
		"source": "res://ImportedCitySource/assets/medieval_village/Prop_Vine4.gltf",
		"target": "res://Scenes/Plants/MedievalVillage/vine_4.tscn",
	},
	{
		"name": "Vine5",
		"source": "res://ImportedCitySource/assets/medieval_village/Prop_Vine5.gltf",
		"target": "res://Scenes/Plants/MedievalVillage/vine_5.tscn",
	},
	{
		"name": "Vine6",
		"source": "res://ImportedCitySource/assets/medieval_village/Prop_Vine6.gltf",
		"target": "res://Scenes/Plants/MedievalVillage/vine_6.tscn",
	},
	{
		"name": "Vine9",
		"source": "res://ImportedCitySource/assets/medieval_village/Prop_Vine9.gltf",
		"target": "res://Scenes/Plants/MedievalVillage/vine_9.tscn",
	},
	{
		"name": "Corn1",
		"source": "res://Scenes/FarmAssets/Quaternius/GLB/Corn_1.glb",
		"target": "res://Scenes/FarmAssets/Quaternius/Corn_1.tscn",
	},
	{
		"name": "Corn2",
		"source": "res://Scenes/FarmAssets/Quaternius/GLB/Corn_2.glb",
		"target": "res://Scenes/FarmAssets/Quaternius/Corn_2.tscn",
	},
	{
		"name": "Wheat",
		"source": "res://Scenes/FarmAssets/Quaternius/GLB/Wheat.glb",
		"target": "res://Scenes/FarmAssets/Quaternius/Wheat.tscn",
	},
	{
		"name": "AmbulanceLowPoly",
		"source": "res://Scenes/Vehicles/Ambulances/GLB/ambulance_low_poly.glb",
		"target": "res://Scenes/Vehicles/Ambulances/ambulance_low_poly.tscn",
	},
	{
		"name": "DodgeAmbulance1957",
		"source": "res://Scenes/Vehicles/Ambulances/GLB/dodge_ambulance_1957.glb",
		"target": "res://Scenes/Vehicles/Ambulances/dodge_ambulance_1957.tscn",
	},
	{
		"name": "SyntyCityVan",
		"source": "res://Scenes/Vehicles/Synty/GLB/city_van.glb",
		"target": "res://Scenes/Vehicles/Synty/city_van.tscn",
	},
	{
		"name": "SyntyCityPoliceCar",
		"source": "res://Scenes/Vehicles/Synty/GLB/city_police_car.glb",
		"target": "res://Scenes/Vehicles/Synty/city_police_car.tscn",
	},
	{
		"name": "SyntyCityTaxiCar",
		"source": "res://Scenes/Vehicles/Synty/GLB/city_taxi_car.glb",
		"target": "res://Scenes/Vehicles/Synty/city_taxi_car.tscn",
	},
	{
		"name": "FarmTractorYellow",
		"source": "res://Scenes/Vehicles/Farm/GLB/tractor_yellow.glb",
		"target": "res://Scenes/Vehicles/Farm/tractor_yellow.tscn",
	},
	{
		"name": "FarmTractorGreen",
		"source": "res://Scenes/Vehicles/Farm/GLB/tractor_green.glb",
		"target": "res://Scenes/Vehicles/Farm/tractor_green.tscn",
	},
	{
		"name": "CropHarvester",
		"source": "res://Scenes/Vehicles/Farm/GLB/crop_harvester.glb",
		"target": "res://Scenes/Vehicles/Farm/crop_harvester.tscn",
	},
	{
		"name": "CombineHarvesterA",
		"source": "res://Scenes/Vehicles/Farm/GLB/combine_harvester_a.glb",
		"target": "res://Scenes/Vehicles/Farm/combine_harvester_a.tscn",
	},
	{
		"name": "CombineHarvesterB",
		"source": "res://Scenes/Vehicles/Farm/GLB/combine_harvester_b.glb",
		"target": "res://Scenes/Vehicles/Farm/combine_harvester_b.tscn",
	},
	{
		"name": "CombineHarvesterC",
		"source": "res://Scenes/Vehicles/Farm/GLB/combine_harvester_c.glb",
		"target": "res://Scenes/Vehicles/Farm/combine_harvester_c.tscn",
	},
	{
		"name": "TruckBox",
		"source": "res://Scenes/Vehicles/Trucks/GLB/truck_box.glb",
		"target": "res://Scenes/Vehicles/Trucks/truck_box.tscn",
	},
	{
		"name": "TruckCargo",
		"source": "res://Scenes/Vehicles/Trucks/GLB/truck_cargo.glb",
		"target": "res://Scenes/Vehicles/Trucks/truck_cargo.tscn",
	},
	{
		"name": "TruckFlatbed",
		"source": "res://Scenes/Vehicles/Trucks/GLB/truck_flatbed.glb",
		"target": "res://Scenes/Vehicles/Trucks/truck_flatbed.tscn",
	},
	{
		"name": "TruckCab",
		"source": "res://Scenes/Vehicles/Trucks/GLB/truck_cab.glb",
		"target": "res://Scenes/Vehicles/Trucks/truck_cab.tscn",
	},
	{
		"name": "TruckTanker",
		"source": "res://Scenes/Vehicles/Trucks/GLB/truck_tanker.glb",
		"target": "res://Scenes/Vehicles/Trucks/truck_tanker.tscn",
	},
]


func _init() -> void:
	var overwrite_existing := _has_arg("--overwrite")
	var only_targets := _arg_values("--only-target")
	var generated_count := 0
	var skipped_count := 0
	var failed_count := 0

	for spec in ASSETS:
		var target_path := str(spec["target"])
		if not only_targets.is_empty() and not only_targets.has(target_path):
			continue
		var result := _generate_scene(
			str(spec["name"]),
			str(spec["source"]),
			target_path,
			overwrite_existing
		)
		if result == OK:
			generated_count += 1
		elif result == ERR_ALREADY_EXISTS:
			skipped_count += 1
		else:
			failed_count += 1

	print("EXTERNAL_ASSET_SCENE_GENERATOR generated=%d skipped=%d failed=%d overwrite=%s" % [
		generated_count,
		skipped_count,
		failed_count,
		str(overwrite_existing),
	])
	quit(1 if failed_count > 0 else 0)


func _generate_scene(
	asset_name: String,
	source_path: String,
	target_path: String,
	overwrite_existing: bool
) -> Error:
	if not ResourceLoader.exists(source_path):
		push_error("Missing source GLB: %s" % source_path)
		return ERR_FILE_NOT_FOUND
	if ResourceLoader.exists(target_path) and not overwrite_existing:
		print("skip existing: ", target_path)
		return ERR_ALREADY_EXISTS

	var source_scene := ResourceLoader.load(
		source_path,
		"PackedScene",
		ResourceLoader.CACHE_MODE_IGNORE_DEEP
	) as PackedScene
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
	local_root.free()
	if save_error != OK:
		push_error("Save failed for %s: %s" % [target_path, save_error])
		return save_error

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


func _has_arg(argument: String) -> bool:
	for current in OS.get_cmdline_user_args():
		if current == argument:
			return true
	return false


func _arg_values(argument: String) -> PackedStringArray:
	var values := PackedStringArray()
	var args := OS.get_cmdline_user_args()
	for index in range(args.size()):
		var current := args[index]
		if current == argument and index + 1 < args.size():
			values.append(args[index + 1])
		elif current.begins_with(argument + "="):
			values.append(current.substr(argument.length() + 1))
	return values
