extends SceneTree

# Generates the forest with the Yamms MultiMesh scatter plugin and bakes the
# result into a plugin-free, visual-only MultiMeshInstance3D scene.
#
# Pipeline:
#   1) Instance Main.tscn (provides the ground collider for raycast snapping).
#   2) Build (first run) or load an editable Yamms MultiScatter authoring setup:
#      island polygon + city exclude + one MultiScatterItem per plant asset with
#      a PMDropOnCollider (ground snap), proportional scale and random yaw.
#   3) Generate -> Yamms fills each item's MultiMesh buffer.
#   4) Bake each item into a plain MultiMeshInstance3D under category nodes and
#      save res://Scenes/Plants/ForestMultiMesh.tscn (contract preserved).
#   5) On first run, save the authoring setup so the polygon/scale stay editable.
#
# Re-run after editing the authoring scene to regenerate and re-bake.
#
# IMPORTANT: run with a REAL renderer, NOT --headless. Yamms fills the MultiMesh
# through set_instance_transform, which is a no-op under the headless dummy
# rendering server (buffer stays empty). Invoke as:
#   Godot_v4.6.3-stable_win64_console.exe --path . \
#     --script res://tools/codex_generate_forest_yamms.gd --quit

const MAIN_SCENE_PATH := "res://Main.tscn"
const OUTPUT_SCENE_PATH := "res://Scenes/Plants/ForestMultiMesh.tscn"
const AUTHORING_SCENE_PATH := "res://Scenes/Plants/ForestScatterAuthoring.tscn"

const CITY_EXCLUSION := Rect2(Vector2(-12.0, -46.0), Vector2(58.0, 94.0))
const ISLAND_RADIUS := Vector2(122.0, 118.0)
const ISLAND_INSET := 0.95
const POLY_POINTS := 24
const POLY_Y := 42.0           # Ray start height above terrain (matches old generator).
const GROUND_MASK := 0x1       # World/StaticBody3D ground is on the default layer.
const FOREST_CUSTOM_AABB := AABB(Vector3(-124.0, -6.0, -124.0), Vector3(248.0, 22.0, 248.0))
const SCATTER_SEED := 202605261

const CATEGORIES := ["Trees", "Understory", "GroundPlants", "Flowers"]

const ASSET_DEFS := [
	{"name": "Tree01", "category": "Trees", "path": "res://ImportedCitySource/assets/plants/tree01.gltf", "count": 36, "height_min": 4.5, "height_max": 6.7, "shadow": true},
	{"name": "Tree02", "category": "Trees", "path": "res://ImportedCitySource/assets/plants/tree02.gltf", "count": 38, "height_min": 5.0, "height_max": 7.5, "shadow": true},
	{"name": "Tree03", "category": "Trees", "path": "res://ImportedCitySource/assets/plants/tree03.gltf", "count": 42, "height_min": 4.8, "height_max": 7.2, "shadow": true},
	{"name": "Tree04", "category": "Trees", "path": "res://ImportedCitySource/assets/plants/tree04.gltf", "count": 36, "height_min": 4.6, "height_max": 6.9, "shadow": true},
	{"name": "Tree05", "category": "Trees", "path": "res://ImportedCitySource/assets/plants/tree05.gltf", "count": 34, "height_min": 5.4, "height_max": 8.2, "shadow": true},
	{"name": "Bush01", "category": "Understory", "path": "res://ImportedCitySource/assets/plants/bush01.gltf", "count": 46, "height_min": 0.8, "height_max": 1.35, "shadow": true},
	{"name": "Bush02", "category": "Understory", "path": "res://ImportedCitySource/assets/plants/bush02.gltf", "count": 44, "height_min": 0.85, "height_max": 1.45, "shadow": true},
	{"name": "Bush03", "category": "Understory", "path": "res://ImportedCitySource/assets/plants/bush03.gltf", "count": 48, "height_min": 0.75, "height_max": 1.25, "shadow": true},
	{"name": "Bush04", "category": "Understory", "path": "res://ImportedCitySource/assets/plants/bush04.gltf", "count": 40, "height_min": 0.9, "height_max": 1.55, "shadow": true},
	{"name": "Weed01", "category": "GroundPlants", "path": "res://ImportedCitySource/assets/plants/Weed01.gltf", "count": 52, "height_min": 0.35, "height_max": 0.65, "shadow": false},
	{"name": "Weed02", "category": "GroundPlants", "path": "res://ImportedCitySource/assets/plants/Weed02.gltf", "count": 48, "height_min": 0.35, "height_max": 0.65, "shadow": false},
	{"name": "Weed03", "category": "GroundPlants", "path": "res://ImportedCitySource/assets/plants/Weed03.gltf", "count": 44, "height_min": 0.35, "height_max": 0.65, "shadow": false},
	{"name": "Weedplant01", "category": "GroundPlants", "path": "res://ImportedCitySource/assets/plants/Weedplant01.gltf", "count": 32, "height_min": 0.45, "height_max": 0.8, "shadow": false},
	{"name": "Weedplant02", "category": "GroundPlants", "path": "res://ImportedCitySource/assets/plants/weedplant02.gltf", "count": 32, "height_min": 0.45, "height_max": 0.8, "shadow": false},
	{"name": "Weedplant03", "category": "GroundPlants", "path": "res://ImportedCitySource/assets/plants/weedplant03.gltf", "count": 28, "height_min": 0.45, "height_max": 0.8, "shadow": false},
	{"name": "ThreeLeaf01", "category": "GroundPlants", "path": "res://ImportedCitySource/assets/plants/threeleaf01.gltf", "count": 38, "height_min": 0.25, "height_max": 0.48, "shadow": false},
	{"name": "Mushroom01", "category": "GroundPlants", "path": "res://ImportedCitySource/assets/plants/mushroom01.gltf", "count": 24, "height_min": 0.18, "height_max": 0.36, "shadow": false},
	{"name": "Mushroom02", "category": "GroundPlants", "path": "res://ImportedCitySource/assets/plants/mushroom02.gltf", "count": 22, "height_min": 0.18, "height_max": 0.36, "shadow": false},
	{"name": "FlowerBlue01", "category": "Flowers", "path": "res://ImportedCitySource/assets/plants/flowerblue01.gltf", "count": 18, "height_min": 0.28, "height_max": 0.55, "shadow": false},
	{"name": "FlowerKrokus01", "category": "Flowers", "path": "res://ImportedCitySource/assets/plants/flowerKrokus01.gltf", "count": 18, "height_min": 0.25, "height_max": 0.5, "shadow": false},
	{"name": "FlowerTulipan01", "category": "Flowers", "path": "res://ImportedCitySource/assets/plants/flowertulipan01.gltf", "count": 18, "height_min": 0.35, "height_max": 0.65, "shadow": false},
	{"name": "FlowerValmue01", "category": "Flowers", "path": "res://ImportedCitySource/assets/plants/flowervalmue01.gltf", "count": 18, "height_min": 0.35, "height_max": 0.65, "shadow": false},
	{"name": "Flowers01", "category": "Flowers", "path": "res://ImportedCitySource/assets/plants/flowers01.gltf", "count": 20, "height_min": 0.25, "height_max": 0.5, "shadow": false},
	{"name": "Flowers02", "category": "Flowers", "path": "res://ImportedCitySource/assets/plants/flowers02.gltf", "count": 20, "height_min": 0.25, "height_max": 0.5, "shadow": false},
]

const MultiScatterScript := preload("res://addons/yamms/MultiScatter.gd")
const MultiScatterItemScript := preload("res://addons/yamms/MultiScatterItem.gd")
const MultiScatterExcludeScript := preload("res://addons/yamms/MultiScatterExclude.gd")
const PMDropOnColliderScript := preload("res://addons/yamms/PMDropOnCollider.gd")

var _built_new_authoring := false


func _initialize() -> void:
	var main_scene := load(MAIN_SCENE_PATH) as PackedScene
	if main_scene == null:
		push_error("Could not load %s." % MAIN_SCENE_PATH)
		quit(1)
		return

	var main := main_scene.instantiate()
	root.add_child(main)
	# Let physics bodies (ground collider) register before raycasting.
	for _i in 6:
		await physics_frame

	var world := main.get_node_or_null(NodePath("World")) as Node3D
	if world == null:
		push_error("Main scene is missing World node.")
		quit(1)
		return

	var multi_scatter := _get_multiscatter(world)
	if multi_scatter == null:
		quit(1)
		return

	# Run generation synchronously here instead of via _physics_process (Yamms'
	# editor-thread deferral); a real renderer is required (see header note).
	multi_scatter.do_generate()

	var total := _bake_and_save(multi_scatter)
	if total < 0:
		quit(1)
		return

	if _built_new_authoring:
		_save_authoring(multi_scatter, world)

	main.free()
	print("Yamms forest generated and baked: %d instances across %d variants." % [total, ASSET_DEFS.size()])
	quit(0)


func _get_multiscatter(world: Node3D) -> Node3D:
	if ResourceLoader.exists(AUTHORING_SCENE_PATH):
		var packed := load(AUTHORING_SCENE_PATH) as PackedScene
		if packed != null:
			var instance := packed.instantiate()
			world.add_child(instance)
			print("Loaded existing authoring setup %s." % AUTHORING_SCENE_PATH)
			return instance as Node3D
		push_error("Could not load %s; rebuilding default setup." % AUTHORING_SCENE_PATH)

	return _build_multiscatter(world)


func _build_multiscatter(world: Node3D) -> Node3D:
	var total_count := 0
	for asset_def in ASSET_DEFS:
		total_count += int(asset_def["count"])

	var multi_scatter: Node3D = MultiScatterScript.new()
	multi_scatter.name = "ForestScatter"
	multi_scatter.curve = _build_island_curve()
	multi_scatter.amount = total_count
	multi_scatter.seed = SCATTER_SEED
	world.add_child(multi_scatter)

	var exclude: Node3D = MultiScatterExcludeScript.new()
	exclude.name = "CityExclude"
	exclude.curve = _build_rect_curve(CITY_EXCLUSION)
	multi_scatter.add_child(exclude)

	for asset_def in ASSET_DEFS:
		var mesh := _load_first_mesh(asset_def["path"])
		if mesh == null:
			push_error("Could not load mesh from %s." % asset_def["path"])
			return null
		var base_height: float = maxf(mesh.get_aabb().size.y, 0.01)

		var multi_mesh := MultiMesh.new()
		multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
		multi_mesh.mesh = mesh

		var item: Node3D = MultiScatterItemScript.new()
		item.name = "%sItem" % asset_def["name"]
		item.multimesh = multi_mesh
		item.percentage = float(asset_def["count"]) / float(total_count) * 100.0
		multi_scatter.add_child(item)

		var placement: Node3D = PMDropOnColliderScript.new()
		placement.name = "DropOnGround"
		placement.collision_mask = GROUND_MASK
		placement.placement_direction = 1  # direction.Down
		placement.normal_influence = 0.0   # keep instances upright
		placement.random_scale_type = 1    # scale_type_enum.Proportional
		placement.min_random_scale = float(asset_def["height_min"]) / base_height
		placement.max_random_scale = float(asset_def["height_max"]) / base_height
		placement.randomize_rotation = true
		placement.min_random_rotation = Vector3.ZERO
		placement.max_random_rotation = Vector3(0.0, 360.0, 0.0)
		item.add_child(placement)

	_built_new_authoring = true
	return multi_scatter


func _build_island_curve() -> Curve3D:
	var curve := Curve3D.new()
	for i in POLY_POINTS:
		var angle := TAU * float(i) / float(POLY_POINTS)
		var x := cos(angle) * ISLAND_RADIUS.x * ISLAND_INSET
		var z := sin(angle) * ISLAND_RADIUS.y * ISLAND_INSET
		curve.add_point(Vector3(x, POLY_Y, z))
	return curve


func _build_rect_curve(rect: Rect2) -> Curve3D:
	var curve := Curve3D.new()
	curve.add_point(Vector3(rect.position.x, 0.0, rect.position.y))
	curve.add_point(Vector3(rect.position.x + rect.size.x, 0.0, rect.position.y))
	curve.add_point(Vector3(rect.position.x + rect.size.x, 0.0, rect.position.y + rect.size.y))
	curve.add_point(Vector3(rect.position.x, 0.0, rect.position.y + rect.size.y))
	return curve


func _bake_and_save(multi_scatter: Node3D) -> int:
	var forest_root := Node3D.new()
	forest_root.name = "ForestMultiMesh"
	forest_root.set_meta("visual_only", true)
	forest_root.set_meta("generated_by", "tools/codex_generate_forest_yamms.gd")
	forest_root.set_meta("source_assets", "res://ImportedCitySource/assets/plants")

	var category_nodes := {}
	for category in CATEGORIES:
		var node := Node3D.new()
		node.name = category
		forest_root.add_child(node)
		node.owner = forest_root
		category_nodes[category] = node

	var items := _collect_items(multi_scatter)
	if items.size() != ASSET_DEFS.size():
		push_error("Expected %d MultiScatterItems, found %d." % [ASSET_DEFS.size(), items.size()])
		forest_root.free()
		return -1

	var total_instances := 0
	for i in ASSET_DEFS.size():
		var asset_def: Dictionary = ASSET_DEFS[i]
		var item: Node3D = items[i]
		var source_mm: MultiMesh = item.multimesh
		if source_mm == null or source_mm.instance_count <= 0:
			push_error("%s produced no instances." % asset_def["name"])
			forest_root.free()
			return -1

		# Rebuild a clean TRANSFORM_3D buffer (12 floats per instance) so it
		# serializes; Yamms' own buffer stride differs and is not saved directly.
		var count := source_mm.instance_count
		var buffer := PackedFloat32Array()
		buffer.resize(count * 12)
		for k in count:
			var t := source_mm.get_instance_transform(k)
			var o := k * 12
			buffer[o] = t.basis.x.x
			buffer[o + 1] = t.basis.y.x
			buffer[o + 2] = t.basis.z.x
			buffer[o + 3] = t.origin.x
			buffer[o + 4] = t.basis.x.y
			buffer[o + 5] = t.basis.y.y
			buffer[o + 6] = t.basis.z.y
			buffer[o + 7] = t.origin.y
			buffer[o + 8] = t.basis.x.z
			buffer[o + 9] = t.basis.y.z
			buffer[o + 10] = t.basis.z.z
			buffer[o + 11] = t.origin.z
		var baked_mm := MultiMesh.new()
		baked_mm.transform_format = MultiMesh.TRANSFORM_3D
		baked_mm.mesh = source_mm.mesh
		baked_mm.instance_count = count
		baked_mm.buffer = buffer
		baked_mm.custom_aabb = FOREST_CUSTOM_AABB
		baked_mm.visible_instance_count = count

		var instance := MultiMeshInstance3D.new()
		instance.name = "%sMultiMesh" % asset_def["name"]
		instance.multimesh = baked_mm
		instance.cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			if bool(asset_def["shadow"])
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		)
		instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		instance.visibility_range_end = 180.0

		var category_node: Node3D = category_nodes[asset_def["category"]]
		category_node.add_child(instance)
		instance.owner = forest_root
		total_instances += baked_mm.instance_count

	var packed_scene := PackedScene.new()
	if packed_scene.pack(forest_root) != OK:
		push_error("Could not pack baked forest scene.")
		forest_root.free()
		return -1
	if ResourceSaver.save(packed_scene, OUTPUT_SCENE_PATH) != OK:
		push_error("Could not save %s." % OUTPUT_SCENE_PATH)
		forest_root.free()
		return -1

	forest_root.free()
	return total_instances


func _save_authoring(multi_scatter: Node3D, world: Node3D) -> void:
	world.remove_child(multi_scatter)
	# Lean authoring scene: clear baked buffers (regenerate to preview) and own
	# only the Yamms nodes so density-map preview Decals are not serialized.
	multi_scatter.owner = null
	for item in _collect_items(multi_scatter):
		if item.multimesh != null:
			var lean_mm := MultiMesh.new()
			lean_mm.transform_format = MultiMesh.TRANSFORM_3D
			lean_mm.mesh = item.multimesh.mesh
			item.multimesh = lean_mm
		item.owner = multi_scatter
		for child in item.get_children():
			if child is PlacementMode:
				child.owner = multi_scatter
	for child in multi_scatter.get_children():
		if child is MultiScatterExclude:
			child.owner = multi_scatter

	var packed := PackedScene.new()
	if packed.pack(multi_scatter) != OK:
		push_error("Could not pack authoring scene.")
		return
	if ResourceSaver.save(packed, AUTHORING_SCENE_PATH) != OK:
		push_error("Could not save %s." % AUTHORING_SCENE_PATH)
		return
	print("Saved editable authoring setup %s." % AUTHORING_SCENE_PATH)


func _collect_items(multi_scatter: Node3D) -> Array:
	var items := []
	for child in multi_scatter.get_children():
		if child is MultiScatterItem:
			items.append(child)
	return items


func _load_first_mesh(scene_path: String) -> Mesh:
	var scene := load(scene_path) as PackedScene
	if scene == null:
		return null
	var scene_root := scene.instantiate()
	var mesh := _find_first_mesh(scene_root)
	scene_root.free()
	return mesh


func _find_first_mesh(node: Node) -> Mesh:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		return (node as MeshInstance3D).mesh
	for child in node.get_children():
		var mesh := _find_first_mesh(child)
		if mesh != null:
			return mesh
	return null
