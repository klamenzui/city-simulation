extends RefCounted
class_name SceneBootstrapController

const ImportedCitySetupScript = preload("res://Simulation/Bootstrap/ImportedCitySetup.gd")
const NavigationSetupScript = preload("res://Simulation/Bootstrap/NavigationSetup.gd")
const RoadBuilderScript = preload("res://Simulation/Bootstrap/RoadBuilder.gd")
const WorldSetupScript = preload("res://Simulation/Bootstrap/WorldSetup.gd")

const RestaurantScene = preload("res://Scenes/Restaurant.tscn")
const SupermarketScene = preload("res://Scenes/Supermarket.tscn")
const ShopScene = preload("res://Scenes/Shop.tscn")
const CinemaScene = preload("res://Scenes/Cinema.tscn")
const UniversityScene = preload("res://Scenes/University.tscn")
const CityHallScene = preload("res://Scenes/CityHall.tscn")
const FarmScene = preload("res://Scenes/Farm.tscn")
const FactoryScene = preload("res://Scenes/Factory.tscn")

const OCEAN_NODE_NAME := "Ocean"
const MATTE_ROUGHNESS_FLOOR := 0.9
const MATTE_METALLIC_CAP := 0.02
const MATTE_SPECULAR_CAP := 0.18

static func setup_scene(root: Node3D, world: World) -> void:
	if root == null or world == null:
		return

	var has_scene_city: bool = root.get_node_or_null("World/City") != null
	var imported_city: Node3D = null
	if not has_scene_city:
		imported_city = ImportedCitySetupScript.ensure_city_visual(root)

	_spawn_missing_core_buildings(root)
	NavigationSetupScript.ensure_region(root, world)
	WorldSetupScript.configure_scene_buildings(root.get_tree(), world)
	if not has_scene_city and imported_city == null:
		RoadBuilderScript.build_simple_roads(root, world)
	_apply_matte_city_materials(root)

	world.rebuild_road_graph(root)
	world.rebuild_pedestrian_graph(root)
	_ensure_ocean(world)

static func _spawn_missing_core_buildings(root: Node3D) -> void:
	if root == null:
		return
	if not _has_building_type(root, "restaurant"):
		_spawn_if_missing(root, "Restaurant", RestaurantScene, Vector3(11.0, 0.0, -7.0))
	if not _has_building_type(root, "supermarket"):
		_spawn_if_missing(root, "Supermarket", SupermarketScene, Vector3(15.0, 0.0, 9.0))
	if not _has_building_type(root, "shop"):
		_spawn_if_missing(root, "Shop", ShopScene, Vector3(19.0, 0.0, -4.0))
	if not _has_building_type(root, "cinema"):
		_spawn_if_missing(root, "Cinema", CinemaScene, Vector3(-18.0, 0.0, -9.0))
	if not _has_building_type(root, "university"):
		_spawn_if_missing(root, "University", UniversityScene, Vector3(-14.0, 0.0, 10.0))
	if not _has_building_type(root, "city_hall"):
		_spawn_if_missing(root, "CityHall", CityHallScene, Vector3(1.0, 0.0, 15.0))
	if not _has_building_type(root, "farm"):
		_spawn_if_missing(root, "Farm", FarmScene, Vector3(-24.0, 0.0, 14.0))
	if not _has_building_type(root, "factory"):
		_spawn_if_missing(root, "Factory", FactoryScene, Vector3(24.0, 0.0, 14.0))

static func _has_building_type(root: Node3D, type_id: String) -> bool:
	if root == null or root.get_tree() == null:
		return false
	for node in root.get_tree().get_nodes_in_group("buildings"):
		if node is not Building:
			continue
		match type_id:
			"restaurant":
				if node is Restaurant:
					return true
			"supermarket":
				if node is Supermarket:
					return true
			"shop":
				if node is Shop and node is not Supermarket:
					return true
			"cinema":
				if node is Cinema:
					return true
			"university":
				if node is University:
					return true
			"city_hall":
				if node is CityHall:
					return true
			"farm":
				if node is Farm:
					return true
			"factory":
				if node is Factory:
					return true
			_:
				pass
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
	for path in ["World/City", "ImportedCity"]:
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

static func _apply_matte_materials_recursive(node: Node, matte_cache: Dictionary) -> void:
	if node is MeshInstance3D:
		_apply_matte_materials_to_mesh(node as MeshInstance3D, matte_cache)
	for child in node.get_children():
		_apply_matte_materials_recursive(child, matte_cache)

static func _apply_matte_materials_to_mesh(mesh_instance: MeshInstance3D, matte_cache: Dictionary) -> void:
	if mesh_instance == null or mesh_instance.mesh == null:
		return
	if mesh_instance.name == OCEAN_NODE_NAME:
		return

	if mesh_instance.material_override is StandardMaterial3D:
		mesh_instance.material_override = _get_or_create_matte_material(
			mesh_instance.material_override as StandardMaterial3D,
			matte_cache
		)

	for surface_idx in range(mesh_instance.mesh.get_surface_count()):
		var override_material := mesh_instance.get_surface_override_material(surface_idx)
		if override_material is StandardMaterial3D:
			mesh_instance.set_surface_override_material(
				surface_idx,
				_get_or_create_matte_material(override_material as StandardMaterial3D, matte_cache)
			)
			continue

		var surface_material := mesh_instance.mesh.surface_get_material(surface_idx)
		if surface_material is StandardMaterial3D:
			mesh_instance.set_surface_override_material(
				surface_idx,
				_get_or_create_matte_material(surface_material as StandardMaterial3D, matte_cache)
			)

static func _get_or_create_matte_material(material: StandardMaterial3D, matte_cache: Dictionary) -> StandardMaterial3D:
	if material == null:
		return null

	var material_id := material.get_instance_id()
	if matte_cache.has(material_id):
		return matte_cache[material_id] as StandardMaterial3D

	if material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		matte_cache[material_id] = material
		return material
	if material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
		matte_cache[material_id] = material
		return material

	var matte := material.duplicate() as StandardMaterial3D
	matte.roughness = maxf(matte.roughness, MATTE_ROUGHNESS_FLOOR)
	matte.metallic = minf(matte.metallic, MATTE_METALLIC_CAP)
	matte.metallic_specular = minf(matte.metallic_specular, MATTE_SPECULAR_CAP)
	matte_cache[material_id] = matte
	return matte

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
	ocean.mesh = plane
	ocean.material_override = _build_ocean_material()
	ocean.position = world.to_local(_get_ocean_world_position(world, bounds))

static func _get_ocean_world_position(world: World, bounds: AABB) -> Vector3:
	var center := bounds.position + bounds.size * 0.5
	var water_y := bounds.position.y + clampf(bounds.size.y * 0.08, 0.18, 0.75)
	if world != null and world.has_method("get_ground_fallback_y"):
		water_y = minf(water_y, world.get_ground_fallback_y() - 0.35)
	return Vector3(center.x, water_y, center.z)

static func _build_ocean_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.08, 0.33, 0.45, 0.74)
	material.roughness = 0.08
	material.metallic = 0.04
	material.metallic_specular = 0.82
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.emission_enabled = true
	material.emission = Color(0.03, 0.14, 0.18, 1.0)
	material.emission_energy_multiplier = 0.35
	return material
