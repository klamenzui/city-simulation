extends SceneTree

const MAIN_SCENE_PATH := "res://Main.tscn"
const OUTPUT_SCENE_PATH := "res://Scenes/Plants/ForestMultiMesh.tscn"

const FOREST_REGIONS := [
	{"min": Vector2(-96.0, -76.0), "max": Vector2(-48.0, 68.0)},
	{"min": Vector2(-76.0, -104.0), "max": Vector2(78.0, -58.0)},
	{"min": Vector2(48.0, -72.0), "max": Vector2(104.0, 10.0)},
	{"min": Vector2(-52.0, 58.0), "max": Vector2(74.0, 104.0)},
]
const CITY_EXCLUSION := Rect2(Vector2(-12.0, -46.0), Vector2(58.0, 94.0))
const ISLAND_RADIUS := Vector2(122.0, 118.0)
const FOREST_CUSTOM_AABB := AABB(Vector3(-124.0, -6.0, -124.0), Vector3(248.0, 22.0, 248.0))

const ASSET_DEFS := [
	{"name": "Tree01", "category": "Trees", "path": "res://ImportedCitySource/assets/plants/tree01.gltf", "count": 36, "height_min": 4.5, "height_max": 6.7, "min_distance": 5.6, "shadow": true},
	{"name": "Tree02", "category": "Trees", "path": "res://ImportedCitySource/assets/plants/tree02.gltf", "count": 38, "height_min": 5.0, "height_max": 7.5, "min_distance": 5.8, "shadow": true},
	{"name": "Tree03", "category": "Trees", "path": "res://ImportedCitySource/assets/plants/tree03.gltf", "count": 42, "height_min": 4.8, "height_max": 7.2, "min_distance": 5.5, "shadow": true},
	{"name": "Tree04", "category": "Trees", "path": "res://ImportedCitySource/assets/plants/tree04.gltf", "count": 36, "height_min": 4.6, "height_max": 6.9, "min_distance": 5.4, "shadow": true},
	{"name": "Tree05", "category": "Trees", "path": "res://ImportedCitySource/assets/plants/tree05.gltf", "count": 34, "height_min": 5.4, "height_max": 8.2, "min_distance": 6.0, "shadow": true},
	{"name": "Bush01", "category": "Understory", "path": "res://ImportedCitySource/assets/plants/bush01.gltf", "count": 46, "height_min": 0.8, "height_max": 1.35, "min_distance": 2.1, "shadow": true},
	{"name": "Bush02", "category": "Understory", "path": "res://ImportedCitySource/assets/plants/bush02.gltf", "count": 44, "height_min": 0.85, "height_max": 1.45, "min_distance": 2.1, "shadow": true},
	{"name": "Bush03", "category": "Understory", "path": "res://ImportedCitySource/assets/plants/bush03.gltf", "count": 48, "height_min": 0.75, "height_max": 1.25, "min_distance": 2.0, "shadow": true},
	{"name": "Bush04", "category": "Understory", "path": "res://ImportedCitySource/assets/plants/bush04.gltf", "count": 40, "height_min": 0.9, "height_max": 1.55, "min_distance": 2.2, "shadow": true},
	{"name": "Weed01", "category": "GroundPlants", "path": "res://ImportedCitySource/assets/plants/Weed01.gltf", "count": 52, "height_min": 0.35, "height_max": 0.65, "min_distance": 0.75, "shadow": false},
	{"name": "Weed02", "category": "GroundPlants", "path": "res://ImportedCitySource/assets/plants/Weed02.gltf", "count": 48, "height_min": 0.35, "height_max": 0.65, "min_distance": 0.75, "shadow": false},
	{"name": "Weed03", "category": "GroundPlants", "path": "res://ImportedCitySource/assets/plants/Weed03.gltf", "count": 44, "height_min": 0.35, "height_max": 0.65, "min_distance": 0.75, "shadow": false},
	{"name": "Weedplant01", "category": "GroundPlants", "path": "res://ImportedCitySource/assets/plants/Weedplant01.gltf", "count": 32, "height_min": 0.45, "height_max": 0.8, "min_distance": 0.9, "shadow": false},
	{"name": "Weedplant02", "category": "GroundPlants", "path": "res://ImportedCitySource/assets/plants/weedplant02.gltf", "count": 32, "height_min": 0.45, "height_max": 0.8, "min_distance": 0.9, "shadow": false},
	{"name": "Weedplant03", "category": "GroundPlants", "path": "res://ImportedCitySource/assets/plants/weedplant03.gltf", "count": 28, "height_min": 0.45, "height_max": 0.8, "min_distance": 0.9, "shadow": false},
	{"name": "ThreeLeaf01", "category": "GroundPlants", "path": "res://ImportedCitySource/assets/plants/threeleaf01.gltf", "count": 38, "height_min": 0.25, "height_max": 0.48, "min_distance": 0.75, "shadow": false},
	{"name": "Mushroom01", "category": "GroundPlants", "path": "res://ImportedCitySource/assets/plants/mushroom01.gltf", "count": 24, "height_min": 0.18, "height_max": 0.36, "min_distance": 0.75, "shadow": false},
	{"name": "Mushroom02", "category": "GroundPlants", "path": "res://ImportedCitySource/assets/plants/mushroom02.gltf", "count": 22, "height_min": 0.18, "height_max": 0.36, "min_distance": 0.75, "shadow": false},
	{"name": "FlowerBlue01", "category": "Flowers", "path": "res://ImportedCitySource/assets/plants/flowerblue01.gltf", "count": 18, "height_min": 0.28, "height_max": 0.55, "min_distance": 0.65, "shadow": false},
	{"name": "FlowerKrokus01", "category": "Flowers", "path": "res://ImportedCitySource/assets/plants/flowerKrokus01.gltf", "count": 18, "height_min": 0.25, "height_max": 0.5, "min_distance": 0.65, "shadow": false},
	{"name": "FlowerTulipan01", "category": "Flowers", "path": "res://ImportedCitySource/assets/plants/flowertulipan01.gltf", "count": 18, "height_min": 0.35, "height_max": 0.65, "min_distance": 0.7, "shadow": false},
	{"name": "FlowerValmue01", "category": "Flowers", "path": "res://ImportedCitySource/assets/plants/flowervalmue01.gltf", "count": 18, "height_min": 0.35, "height_max": 0.65, "min_distance": 0.7, "shadow": false},
	{"name": "Flowers01", "category": "Flowers", "path": "res://ImportedCitySource/assets/plants/flowers01.gltf", "count": 20, "height_min": 0.25, "height_max": 0.5, "min_distance": 0.7, "shadow": false},
	{"name": "Flowers02", "category": "Flowers", "path": "res://ImportedCitySource/assets/plants/flowers02.gltf", "count": 20, "height_min": 0.25, "height_max": 0.5, "min_distance": 0.7, "shadow": false},
]

var _world_node: Node3D
var _space_state: PhysicsDirectSpaceState3D
var _occupied_points: Array[Vector2] = []


func _initialize() -> void:
	var main_scene := load(MAIN_SCENE_PATH) as PackedScene
	if main_scene == null:
		push_error("Could not load %s." % MAIN_SCENE_PATH)
		quit(FAILED)
		return

	var main := main_scene.instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame

	_world_node = main.get_node_or_null(NodePath("World")) as Node3D
	if _world_node == null:
		push_error("Main scene is missing World node.")
		quit(FAILED)
		return
	_space_state = _world_node.get_world_3d().direct_space_state

	var forest_root := Node3D.new()
	forest_root.name = "ForestMultiMesh"
	forest_root.set_meta("visual_only", true)
	forest_root.set_meta("generated_by", "tools/codex_generate_forest_scene.gd")
	forest_root.set_meta("source_assets", "res://ImportedCitySource/assets/plants")

	var category_nodes := _create_category_nodes(forest_root)
	var rng := RandomNumberGenerator.new()
	rng.seed = 202605261

	var total_instances := 0
	for asset_def in ASSET_DEFS:
		var mesh := _load_first_mesh(asset_def["path"])
		if mesh == null:
			push_error("Could not load mesh from %s." % asset_def["path"])
			quit(FAILED)
			return

		var transforms := _build_transforms_for_asset(mesh, asset_def, rng)
		if transforms.is_empty():
			push_error("No transforms generated for %s." % asset_def["name"])
			quit(FAILED)
			return

		var multi_mesh := MultiMesh.new()
		multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
		multi_mesh.mesh = mesh
		multi_mesh.instance_count = transforms.size()
		multi_mesh.visible_instance_count = transforms.size()
		multi_mesh.custom_aabb = FOREST_CUSTOM_AABB
		multi_mesh.buffer = _build_multimesh_buffer(transforms)

		var instance := MultiMeshInstance3D.new()
		instance.name = "%sMultiMesh" % asset_def["name"]
		instance.multimesh = multi_mesh
		instance.cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			if bool(asset_def["shadow"])
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		)
		instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		instance.visibility_range_end = 180.0
		category_nodes[asset_def["category"]].add_child(instance)
		instance.owner = forest_root
		total_instances += transforms.size()

	var packed_scene := PackedScene.new()
	var pack_result := packed_scene.pack(forest_root)
	if pack_result != OK:
		push_error("Could not pack forest scene, error=%d." % pack_result)
		quit(FAILED)
		return

	var save_result := ResourceSaver.save(packed_scene, OUTPUT_SCENE_PATH)
	if save_result != OK:
		push_error("Could not save %s, error=%d." % [OUTPUT_SCENE_PATH, save_result])
		quit(FAILED)
		return

	forest_root.free()
	main.free()
	print("Generated %s with %d MultiMesh instances across %d asset variants." % [
		OUTPUT_SCENE_PATH,
		total_instances,
		ASSET_DEFS.size(),
	])
	quit(OK)


func _create_category_nodes(forest_root: Node3D) -> Dictionary:
	var category_nodes := {}
	for category in ["Trees", "Understory", "GroundPlants", "Flowers"]:
		var node := Node3D.new()
		node.name = category
		forest_root.add_child(node)
		node.owner = forest_root
		category_nodes[category] = node
	return category_nodes


func _load_first_mesh(scene_path: String) -> Mesh:
	var scene := load(scene_path) as PackedScene
	if scene == null:
		return null
	var scene_root := scene.instantiate()
	var mesh := _find_first_mesh(scene_root)
	scene_root.free()
	return mesh


func _find_first_mesh(node: Node) -> Mesh:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			return mesh_instance.mesh
	for child in node.get_children():
		var mesh := _find_first_mesh(child)
		if mesh != null:
			return mesh
	return null


func _build_transforms_for_asset(mesh: Mesh, asset_def: Dictionary, rng: RandomNumberGenerator) -> Array[Transform3D]:
	var transforms: Array[Transform3D] = []
	var wanted_count := int(asset_def["count"])
	var attempts := 0
	var max_attempts := wanted_count * 90
	while transforms.size() < wanted_count and attempts < max_attempts:
		attempts += 1
		var point := _random_point_in_forest(rng)
		if _is_inside_city_exclusion(point) or not _is_inside_playable_island(point):
			continue
		if not _has_spacing(point, float(asset_def["min_distance"])):
			continue

		var ground_position: Variant = _sample_ground(point)
		if ground_position == null:
			continue

		var target_height := rng.randf_range(float(asset_def["height_min"]), float(asset_def["height_max"]))
		var transform := _make_transform(mesh, ground_position as Vector3, target_height, rng)
		transforms.append(transform)
		_occupied_points.append(point)
	return transforms


func _build_multimesh_buffer(transforms: Array[Transform3D]) -> PackedFloat32Array:
	var buffer := PackedFloat32Array()
	buffer.resize(transforms.size() * 12)
	var offset := 0
	for transform in transforms:
		buffer[offset] = transform.basis.x.x
		buffer[offset + 1] = transform.basis.y.x
		buffer[offset + 2] = transform.basis.z.x
		buffer[offset + 3] = transform.origin.x
		buffer[offset + 4] = transform.basis.x.y
		buffer[offset + 5] = transform.basis.y.y
		buffer[offset + 6] = transform.basis.z.y
		buffer[offset + 7] = transform.origin.y
		buffer[offset + 8] = transform.basis.x.z
		buffer[offset + 9] = transform.basis.y.z
		buffer[offset + 10] = transform.basis.z.z
		buffer[offset + 11] = transform.origin.z
		offset += 12
	return buffer


func _random_point_in_forest(rng: RandomNumberGenerator) -> Vector2:
	var region: Dictionary = FOREST_REGIONS[rng.randi_range(0, FOREST_REGIONS.size() - 1)]
	var min_point: Vector2 = region["min"]
	var max_point: Vector2 = region["max"]
	return Vector2(
		rng.randf_range(min_point.x, max_point.x),
		rng.randf_range(min_point.y, max_point.y)
	)


func _is_inside_city_exclusion(point: Vector2) -> bool:
	return CITY_EXCLUSION.has_point(point)


func _is_inside_playable_island(point: Vector2) -> bool:
	var normalized := Vector2(point.x / ISLAND_RADIUS.x, point.y / ISLAND_RADIUS.y)
	return normalized.length_squared() <= 1.0


func _has_spacing(point: Vector2, min_distance: float) -> bool:
	var min_distance_sq := min_distance * min_distance
	for occupied in _occupied_points:
		if occupied.distance_squared_to(point) < min_distance_sq:
			return false
	return true


func _sample_ground(point: Vector2) -> Variant:
	var from := _world_node.to_global(Vector3(point.x, 42.0, point.y))
	var to := _world_node.to_global(Vector3(point.x, -70.0, point.y))
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := _space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	var hit_position: Vector3 = hit["position"]
	return _world_node.to_local(hit_position)


func _make_transform(mesh: Mesh, ground_position: Vector3, target_height: float, rng: RandomNumberGenerator) -> Transform3D:
	var mesh_aabb := mesh.get_aabb()
	var base_height: float = maxf(mesh_aabb.size.y, 0.01)
	var height_scale: float = target_height / base_height
	var width_scale: float = height_scale * rng.randf_range(0.86, 1.16)
	var rotation := rng.randf_range(0.0, TAU)
	var origin := ground_position
	origin.y += -mesh_aabb.position.y * height_scale + 0.02

	var basis := Basis(Vector3.UP, rotation)
	basis = basis.scaled(Vector3(width_scale, height_scale, width_scale))
	return Transform3D(basis, origin)
