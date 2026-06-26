extends SceneTree

const LowPolyWaterPlaneScript = preload("res://Scenes/LowPolyWater/WaterPack/Scripts/low_poly_water_plane.gd")
const DEFAULT_SCENE := "res://Scenes/LowPolyWater/Scenes/pirate_water_demo.tscn"
const DEFAULT_WATER_NODE := "Water"
const DEFAULT_OUTPUT := "res://Scenes/LowPolyWater/WaterPack/Textures/shore_mask_pirate.png"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var options := _parse_options(OS.get_cmdline_user_args())
	var scene_path := str(options.get("scene", DEFAULT_SCENE))
	var water_node_path := NodePath(str(options.get("water-node", DEFAULT_WATER_NODE)))
	var output_path := str(options.get("output", DEFAULT_OUTPUT))

	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_error("Could not load scene: %s" % scene_path)
		quit(1)
		return

	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame

	var water := scene.get_node_or_null(water_node_path)
	if water == null or water.get_script() != LowPolyWaterPlaneScript:
		push_error("Could not find LowPolyWaterPlane at: %s" % water_node_path)
		quit(1)
		return

	if not water.generate_and_apply_shore_mask(true):
		push_error("Shore-mask generation failed.")
		quit(1)
		return

	var save_error: int = int(water.save_generated_shore_mask(output_path))
	if save_error != OK:
		push_error("Could not save shore mask to %s (error %d)." % [output_path, save_error])
		quit(1)
		return

	print("SHORE_MASK_BAKED path=%s resolution=%d" % [output_path, water.shore_mask_resolution])
	quit()

func _parse_options(arguments: PackedStringArray) -> Dictionary:
	var result := {}
	for argument in arguments:
		if not argument.begins_with("--") or not argument.contains("="):
			continue
		var separator := argument.find("=")
		var key := argument.substr(2, separator - 2)
		var value := argument.substr(separator + 1)
		result[key] = value
	return result
