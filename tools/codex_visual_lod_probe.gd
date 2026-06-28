extends SceneTree

const SceneTestUtils = preload("res://tools/codex_scene_test_utils.gd")
const SETTLE_FRAMES := 40


func _init() -> void:
	print("=== Visual LOD probe ===")
	var main_scene := load("res://Main.tscn")
	if main_scene == null:
		printerr("FAIL: cannot load Main.tscn")
		quit(1)
		return

	var main: Node = main_scene.instantiate()
	root.add_child(main)

	for _i in range(8):
		await process_frame
	if main.get("_runtime_controller") == null and main.has_method("_on_main_menu_singleplayer"):
		main.call("_on_main_menu_singleplayer")

	for _i in range(SETTLE_FRAMES):
		await process_frame

	var world := SceneTestUtils.find_world(main)
	if world == null:
		printerr("FAIL: World node not found")
		quit(1)
		return

	var runtime = main.get("_runtime_controller")
	if runtime == null or not runtime.has_method("get_visual_lod_summary"):
		printerr("FAIL: runtime visual LOD summary not available")
		quit(1)
		return

	var summary: Dictionary = runtime.get_visual_lod_summary()
	print("visual_lod_summary=%s" % str(summary))
	if not bool(summary.get("enabled", false)):
		printerr("FAIL: visual LOD is not enabled")
		quit(1)
		return
	if int(summary.get("configured_meshes", 0)) <= 0:
		printerr("FAIL: visual LOD configured no meshes")
		quit(1)
		return
	if int(summary.get("configured_lights", 0)) <= 0:
		printerr("FAIL: visual LOD configured no lights")
		quit(1)
		return
	if not bool(summary.get("light_pool_enabled", false)):
		printerr("FAIL: visual LOD light pool is not enabled")
		quit(1)
		return
	if int(summary.get("light_pool_managed", 0)) <= 0:
		printerr("FAIL: visual LOD light pool manages no lights")
		quit(1)
		return
	if int(summary.get("light_pool_active", 0)) > int(summary.get("light_pool_budget", 0)):
		printerr("FAIL: active pooled lights exceed budget")
		quit(1)
		return
	if int(summary.get("hidden_debug_meshes", 0)) <= 0:
		printerr("FAIL: visual LOD hid no debug meshes")
		quit(1)
		return
	var missing_roots: Array = summary.get("missing_roots", [])
	if not missing_roots.is_empty():
		printerr("FAIL: visual LOD missing configured roots: %s" % str(missing_roots))
		quit(1)
		return

	var city_plants := main.get_node_or_null("RootNode/City/CityPlants")
	var plant_geometry := _find_first_geometry(city_plants)
	if plant_geometry == null or plant_geometry.visibility_range_end <= 0.0:
		printerr("FAIL: CityPlants geometry has no visibility range")
		quit(1)
		return

	var streetlights := main.get_node_or_null("RootNode/City/Streetlight")
	var streetlight_light := _find_first_light(streetlights)
	if streetlight_light == null or not streetlight_light.distance_fade_enabled:
		printerr("FAIL: streetlight light distance fade is not enabled")
		quit(1)
		return

	print("VISUAL_LOD OK meshes=%d lights=%d active_lights=%d/%d hidden_debug=%d" % [
		int(summary.get("configured_meshes", 0)),
		int(summary.get("configured_lights", 0)),
		int(summary.get("light_pool_active", 0)),
		int(summary.get("light_pool_budget", 0)),
		int(summary.get("hidden_debug_meshes", 0)),
	])
	main.queue_free()
	await process_frame
	quit(0)


func _find_first_geometry(root_node: Node) -> GeometryInstance3D:
	if root_node == null:
		return null
	if root_node is GeometryInstance3D:
		return root_node as GeometryInstance3D
	for child in root_node.get_children():
		var found := _find_first_geometry(child)
		if found != null:
			return found
	return null


func _find_first_light(root_node: Node) -> Light3D:
	if root_node == null:
		return null
	if root_node is Light3D:
		return root_node as Light3D
	for child in root_node.get_children():
		var found := _find_first_light(child)
		if found != null:
			return found
	return null
