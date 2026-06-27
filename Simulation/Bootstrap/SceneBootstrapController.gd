extends RefCounted
class_name SceneBootstrapController

const BuildingScript = preload("res://Entities/Buildings/Building.gd")
const NavigationSetupScript = preload("res://Simulation/Bootstrap/NavigationSetup.gd")
const RoadBuilderScript = preload("res://Simulation/Bootstrap/RoadBuilder.gd")
const WorldSetupScript = preload("res://Simulation/Bootstrap/WorldSetup.gd")

const CityHallScene = preload("res://Scenes/CityHall.tscn")
const GasStationScene = preload("res://Scenes/CityBuildings/services/services_004_b6d7b717.tscn")
const FarmScene = preload("res://Scenes/Farm.tscn")
const SupermarketScene = preload("res://Scenes/CityBuildings/stores/stores_003_d67cc4f3.tscn")

const OCEAN_NODE_NAME := "Ocean"
const MATTE_ROUGHNESS_FLOOR := 0.9
const MATTE_METALLIC_CAP := 0.02
const MATTE_SPECULAR_CAP := 0.18
# Brightness normalization for flat (untextured) albedo only. Lifts near-black import
# artifacts (e.g. OBJ Kd ~0.05 palms) and tames over-bright flats. Luma = Rec.709.
const DARK_LUMA_FLOOR := 0.12
const DARK_LUMA_TARGET := 0.22
const BRIGHT_LUMA_CEIL := 0.82
const BRIGHT_LUMA_TARGET := 0.70

static func setup_scene(root: Node3D, world: World) -> void:
	if root == null or world == null:
		return
	var is_headless := _is_headless_runtime()

	var has_scene_city: bool = root.get_node_or_null("RootNode/City") != null
	var imported_city: Node3D = null

	_spawn_missing_core_buildings(root)
	NavigationSetupScript.ensure_region(root, world)
	WorldSetupScript.configure_scene_buildings(root.get_tree(), world)
	if not has_scene_city and imported_city == null:
		RoadBuilderScript.build_simple_roads(root, world)
	if not is_headless:
		_apply_matte_city_materials(root)
		_polish_plant_materials(root)
	else:
		_disable_headless_visual_nodes(root)

	world.rebuild_road_graph(root)
	world.rebuild_pedestrian_graph(root)
	#_ensure_ocean(world)

static func _is_headless_runtime() -> bool:
	return DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server")

static func _disable_headless_visual_nodes(node: Node) -> void:
	if node == null:
		return
	if node is GeometryInstance3D:
		var geometry_node := node as GeometryInstance3D
		geometry_node.visible = false
		geometry_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	elif node is Light3D:
		(node as Light3D).visible = false
	elif node is GPUParticles3D:
		(node as GPUParticles3D).visible = false
	elif node is CPUParticles3D:
		(node as CPUParticles3D).visible = false
	elif node is Decal:
		(node as Decal).visible = false
	for child in node.get_children():
		_disable_headless_visual_nodes(child)

static func _spawn_missing_core_buildings(root: Node3D) -> void:
	if root == null:
		return
	
	if not _has_building_type(root, "city_hall"):
		_spawn_if_missing(root, "CityHall", CityHallScene, Vector3(1.0, 0.0, 15.0))
	if not _has_building_type(root, "gas_station"):
		_spawn_if_missing(root, "GasStation", GasStationScene, Vector3(20.0, 0.0, -4.0))
	if not _has_building_type(root, "farm"):
		_spawn_if_missing(root, "Farm", FarmScene, Vector3(-24.0, 0.0, 14.0))
	if not _has_building_type(root, "supermarket"):
		_spawn_if_missing(root, "Supermarket", SupermarketScene, Vector3(13.8, 0.0, -2.9))
	
static func _has_building_type(root: Node3D, type_id: String) -> bool:
	if root == null or root.get_tree() == null:
		return false
	for node in root.get_tree().get_nodes_in_group("buildings"):
		if node is not Building:
			continue
		if _building_matches_type(node as Building, type_id):
			return true
	return false

static func _building_matches_type(building: Building, type_id: String) -> bool:
	if building == null:
		return false
	match type_id:
		"restaurant":
			return building is Restaurant or building.building_type == BuildingScript.BuildingType.RESTAURANT
		"supermarket":
			return building is Supermarket or building.building_type == BuildingScript.BuildingType.SUPERMARKET
		"shop":
			return (building is Shop and building is not Supermarket) or building.building_type == BuildingScript.BuildingType.SHOP
		"cinema":
			return building is Cinema or building.building_type == BuildingScript.BuildingType.CINEMA
		"university":
			return building is University or building.building_type == BuildingScript.BuildingType.UNIVERSITY
		"city_hall":
			return building is CityHall or building.building_type == BuildingScript.BuildingType.CITY_HALL
		"gas_station":
			return building is GasStation or building.building_type == BuildingScript.BuildingType.GAS_STATION
		"farm":
			return building is Farm or building.building_type == BuildingScript.BuildingType.FARM
		"factory":
			return building is Factory or building.building_type == BuildingScript.BuildingType.FACTORY
		_:
			return false

static func _spawn_if_missing(root: Node3D, node_name: String, scene: PackedScene, pos: Vector3) -> void:
	if root.get_node_or_null(node_name) != null:
		return
	var instance := scene.instantiate() as Node3D
	if instance == null:
		return
	instance.name = node_name
	instance.position = pos
	root.add_child(instance)

static func _apply_matte_city_materials(root: Node3D) -> void:
	if root == null or root.get_tree() == null:
		return
	var processed_roots: Dictionary = {}
	var matte_cache: Dictionary = {}
	for path in ["RootNode/City", "World/City", "ImportedCity"]:
		var visual_root := root.get_node_or_null(path)
		if visual_root == null:
			continue
		processed_roots[visual_root.get_instance_id()] = true
		_apply_matte_materials_recursive(visual_root, matte_cache)

	for building_node in root.get_tree().get_nodes_in_group("buildings"):
		if building_node == null:
			continue
		var root_id := building_node.get_instance_id()
		if processed_roots.has(root_id):
			continue
		_apply_matte_materials_recursive(building_node, matte_cache)

static func _apply_matte_materials_recursive(node: Node, material_cache: Dictionary) -> void:
	if node is MeshInstance3D:
		_polish_mesh_instance(node as MeshInstance3D, material_cache)
	for child in node.get_children():
		_apply_matte_materials_recursive(child, material_cache)

static func _polish_mesh_instance(mesh_instance: MeshInstance3D, material_cache: Dictionary) -> void:
	if mesh_instance == null or mesh_instance.mesh == null:
		return
	if mesh_instance.name == OCEAN_NODE_NAME:
		return

	if mesh_instance.material_override is StandardMaterial3D:
		mesh_instance.material_override = _get_or_create_polished_material(
			mesh_instance.material_override as StandardMaterial3D,
			material_cache
		)

	for surface_idx in range(mesh_instance.mesh.get_surface_count()):
		var override_material := mesh_instance.get_surface_override_material(surface_idx)
		if override_material is StandardMaterial3D:
			mesh_instance.set_surface_override_material(
				surface_idx,
				_get_or_create_polished_material(override_material as StandardMaterial3D, material_cache)
			)
			continue

		var surface_material := mesh_instance.mesh.surface_get_material(surface_idx)
		if surface_material is StandardMaterial3D:
			mesh_instance.set_surface_override_material(
				surface_idx,
				_get_or_create_polished_material(surface_material as StandardMaterial3D, material_cache)
			)
		elif surface_material == null and override_material == null:
			# Surface ships with no material (e.g. Farm fields) -> give it a neutral matte
			# material so it stops rendering as the raw white engine default.
			mesh_instance.set_surface_override_material(surface_idx, _neutral_fallback_material(material_cache))

# Polishes the live plant scatters (MultiMeshInstance3D under World). Separate from the
# city pass because scatter meshes carry their materials per surface on the shared mesh,
# not as node overrides.
static func _polish_plant_materials(root: Node3D) -> void:
	if root == null:
		return
	var search_root: Node = root.get_node_or_null("RootNode/Islands/MainIsland")
	if search_root == null:
		search_root = root.get_node_or_null("RootNode/Islands/World")
	if search_root == null:
		search_root = root
	var material_cache: Dictionary = {}
	var processed_meshes: Dictionary = {}
	_polish_multimesh_recursive(search_root, material_cache, processed_meshes)

static func _polish_multimesh_recursive(node: Node, material_cache: Dictionary, processed_meshes: Dictionary) -> void:
	if node is MultiMeshInstance3D:
		_polish_multimesh(node as MultiMeshInstance3D, material_cache, processed_meshes)
	for child in node.get_children():
		_polish_multimesh_recursive(child, material_cache, processed_meshes)

static func _polish_multimesh(instance: MultiMeshInstance3D, material_cache: Dictionary, processed_meshes: Dictionary) -> void:
	if instance.material_override is StandardMaterial3D:
		instance.material_override = _get_or_create_polished_material(instance.material_override as StandardMaterial3D, material_cache)
		return
	if instance.multimesh == null or instance.multimesh.mesh is not ArrayMesh:
		return
	var mesh := instance.multimesh.mesh as ArrayMesh
	var mesh_id := mesh.get_instance_id()
	if processed_meshes.has(mesh_id):
		return
	processed_meshes[mesh_id] = true
	for surface_idx in range(mesh.get_surface_count()):
		var surface_material := mesh.surface_get_material(surface_idx)
		if surface_material is StandardMaterial3D:
			mesh.surface_set_material(surface_idx, _get_or_create_polished_material(surface_material as StandardMaterial3D, material_cache))

static func _get_or_create_polished_material(material: StandardMaterial3D, material_cache: Dictionary) -> StandardMaterial3D:
	if material == null:
		return null

	var material_id := material.get_instance_id()
	if material_cache.has(material_id):
		return material_cache[material_id] as StandardMaterial3D

	# Leave transparent and unshaded materials untouched (glass, billboards, decals).
	if material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		material_cache[material_id] = material
		return material
	if material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
		material_cache[material_id] = material
		return material

	var polished := material.duplicate() as StandardMaterial3D
	# Matte pass: drop plastic specular so nothing reads as glossy under the stylized sun.
	polished.roughness = maxf(polished.roughness, MATTE_ROUGHNESS_FLOOR)
	polished.metallic = minf(polished.metallic, MATTE_METALLIC_CAP)
	polished.metallic_specular = minf(polished.metallic_specular, MATTE_SPECULAR_CAP)

	# Brightness pass: only for flat (untextured) albedo. Textured models (GLTF foliage)
	# carry authored color in their texture and must not be tinted.
	if polished.albedo_texture == null:
		var luma := _relative_luminance(polished.albedo_color)
		if luma > 0.0001 and luma < DARK_LUMA_FLOOR:
			# Near-black import artifact (e.g. OBJ Kd ~0.05) -> lift toward a visible floor, keep hue.
			polished.albedo_color = _scale_rgb(polished.albedo_color, DARK_LUMA_TARGET / luma)
		elif luma > BRIGHT_LUMA_CEIL:
			# Over-bright flat color -> pull it down so it stops blowing out next to textured assets.
			polished.albedo_color = _scale_rgb(polished.albedo_color, BRIGHT_LUMA_TARGET / luma)

	material_cache[material_id] = polished
	return polished

static func _relative_luminance(color: Color) -> float:
	return color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722

static func _scale_rgb(color: Color, factor: float) -> Color:
	return Color(
		clampf(color.r * factor, 0.0, 1.0),
		clampf(color.g * factor, 0.0, 1.0),
		clampf(color.b * factor, 0.0, 1.0),
		color.a
	)

static func _neutral_fallback_material(material_cache: Dictionary) -> StandardMaterial3D:
	if material_cache.has("fallback"):
		return material_cache["fallback"] as StandardMaterial3D
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.52, 0.50, 0.45)
	material.roughness = 0.95
	material.metallic = 0.0
	material.metallic_specular = MATTE_SPECULAR_CAP
	material_cache["fallback"] = material
	return material

static func _ensure_ocean(world: World) -> void:
	if world == null or not world.has_method("get_world_bounds"):
		return

	var ocean := world.get_node_or_null(OCEAN_NODE_NAME) as MeshInstance3D
	if ocean == null:
		ocean = MeshInstance3D.new()
		ocean.name = OCEAN_NODE_NAME
		ocean.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.add_child(ocean)

	var bounds: AABB = world.get_world_bounds()
	var span := maxf(maxf(bounds.size.x, bounds.size.z), 120.0)
	var plane := PlaneMesh.new()
	plane.size = Vector2(span * 2.4, span * 2.4)
	plane.subdivide_width = 24
	plane.subdivide_depth = 24
	var ocean_material := _build_ocean_material()
	plane.material = ocean_material
	ocean.mesh = plane
	ocean.position = world.to_local(_get_ocean_world_position(world, bounds))

static func _get_ocean_world_position(world: World, bounds: AABB) -> Vector3:
	var center := bounds.position + bounds.size * 0.5
	var water_y := bounds.position.y + clampf(bounds.size.y * 0.08, 0.18, 0.75)
	if world != null and world.has_method("get_ground_fallback_y"):
		water_y = minf(water_y, world.get_ground_fallback_y() - 0.35)
	return Vector3(center.x, water_y, center.z)

static func _build_ocean_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	# Bright turquoise with mild transparency — reads as shallow stylized lake water.
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.22, 0.62, 0.66, 0.78)
	material.roughness = 0.18
	material.metallic = 0.0
	material.metallic_specular = 0.95
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Subtle inner glow so the water stays vivid even in shadow.
	material.emission_enabled = true
	material.emission = Color(0.08, 0.30, 0.34, 1.0)
	material.emission_energy_multiplier = 0.20
	# Rim highlight at grazing angles — bright shoreline edge like in stylized scenes.
	material.rim_enabled = true
	material.rim = 0.35
	material.rim_tint = 0.6
	# Procedural wave normal map: low-frequency noise -> soft, large ripples (no shader needed).
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.012
	noise.fractal_octaves = 3
	noise.fractal_lacunarity = 2.1
	noise.fractal_gain = 0.45
	var normal_tex := NoiseTexture2D.new()
	normal_tex.noise = noise
	normal_tex.width = 256
	normal_tex.height = 256
	normal_tex.seamless = true
	normal_tex.as_normal_map = true
	normal_tex.bump_strength = 4.0
	material.normal_enabled = true
	material.normal_texture = normal_tex
	material.normal_scale = 0.6
	material.uv1_scale = Vector3(48.0, 48.0, 1.0)
	return material
