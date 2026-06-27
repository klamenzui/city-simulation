extends SceneTree

const SceneTestUtils = preload("res://tools/codex_scene_test_utils.gd")

func _init() -> void:
	var main_scene: PackedScene = load("res://Main.tscn")
	if main_scene == null:
		push_error("Failed to load Main.tscn")
		quit(1)
		return

	var main: Node = main_scene.instantiate()
	root.add_child(main)

	await process_frame
	await process_frame
	await process_frame

	var world := SceneTestUtils.find_world(main)
	var world_environment := main.get_node_or_null("EnhancedSky/WorldEnvironment") as WorldEnvironment
	var directional_light := main.get_node_or_null("EnhancedSky/DirectionalLight3D") as DirectionalLight3D
	var sky_bridge: Node = main.get_node_or_null("SkyBridge")
	var sky_time_manager := main.get_node_or_null("EnhancedSky/SkyTimeManager") as SkyTimeManager
	var celestial_bodies := main.get_node_or_null("EnhancedSky/CelestialBodies") as CelestialBodies
	var water := main.get_node_or_null("Water") as MeshInstance3D
	if world == null or world_environment == null or directional_light == null or sky_bridge == null or sky_time_manager == null or celestial_bodies == null or water == null:
		var missing: Array[String] = []
		if world == null:
			missing.append("World")
		if world_environment == null:
			missing.append("EnhancedSky/WorldEnvironment")
		if directional_light == null:
			missing.append("EnhancedSky/DirectionalLight3D")
		if sky_bridge == null:
			missing.append("SkyBridge")
		if sky_time_manager == null:
			missing.append("EnhancedSky/SkyTimeManager")
		if celestial_bodies == null:
			missing.append("EnhancedSky/CelestialBodies")
		if water == null:
			missing.append("Water")
		push_error("Sky probe missing required nodes: %s" % ", ".join(missing))
		quit(1)
		return

	var sky: Sky = world_environment.environment.sky if world_environment.environment != null else null
	var sky_material: ShaderMaterial = sky.sky_material as ShaderMaterial if sky != null else null
	if sky_material == null or sky_material.shader == null:
		push_error("Sky probe missing shader material")
		quit(1)
		return

	print("SKY_PROBE initial shader=", sky_material.shader.resource_path, " time=", sky_time_manager.get_time_of_day_string(), " paused_scale=", snapped(sky_time_manager.time_scale, 0.01))
	print("SKY_PROBE initial sun_visible=", str(sky_material.get_shader_parameter("sun_visible")), " moon_visible=", str(sky_material.get_shader_parameter("moon_visible")), " energy=", snapped(directional_light.light_energy, 0.01))
	var water_mesh := water.mesh as PlaneMesh
	print("WATER_PROBE size=", water_mesh.size if water_mesh != null else Vector2.ZERO, " local_pos=", water.position)

	world.time.advance(12 * 60)
	await process_frame
	await process_frame

	print("SKY_PROBE evening time=", sky_time_manager.get_time_of_day_string(), " sun_visible=", str(sky_material.get_shader_parameter("sun_visible")), " moon_visible=", str(sky_material.get_shader_parameter("moon_visible")), " energy=", snapped(directional_light.light_energy, 0.01))

	world.toggle_pause()
	await process_frame
	print("SKY_PROBE paused time_scale=", snapped(sky_time_manager.time_scale, 0.01))

	world.toggle_pause()
	world.set_speed(0.5)
	await process_frame
	print("SKY_PROBE resumed time_scale=", snapped(sky_time_manager.time_scale, 0.01), " current_day=", snapped(celestial_bodies.current_day, 0.01))

	quit()
