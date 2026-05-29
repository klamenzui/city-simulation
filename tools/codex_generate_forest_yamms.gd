extends SceneTree

# Builds the forest with the Yamms MultiMesh scatter plugin from a data-driven
# recipe (config/forest_scatter.json) and bakes the result into a plugin-free,
# visual-only MultiMeshInstance3D scene.
#
# Pipeline:
#   1) Load config/forest_scatter.json (defaults in code, JSON overrides).
#   2) Instance Main.tscn (provides the ground collider for raycast snapping).
#   3) Build a Yamms MultiScatter from the config (one MultiScatterItem per item,
#      PMDropOnCollider ground snap, proportional scale, random yaw). Items and
#      all settings ALWAYS come from the config. When area.source == "authoring"
#      the forest polygon + exclusions are preserved from the existing authoring
#      scene (so editor reshaping survives); otherwise the config polygon is used.
#   4) do_generate() -> Yamms fills each item's MultiMesh buffer.
#   5) Bake each item into a plain MultiMeshInstance3D under category nodes and
#      save output.baked_scene; rewrite output.authoring_scene (lean, editable).
#
# IMPORTANT: run with a REAL renderer, NOT --headless. Yamms fills the MultiMesh
# through set_instance_transform, which is a no-op under the headless dummy
# rendering server (buffer stays empty). Invoke as:
#   Godot_v4.6.3-stable_win64_console.exe --path . \
#     --script res://tools/codex_generate_forest_yamms.gd --quit

const CONFIG_PATH := "res://config/forest_scatter.json"
const MAIN_SCENE_PATH := "res://Main.tscn"

const MultiScatterScript := preload("res://addons/yamms/MultiScatter.gd")
const MultiScatterItemScript := preload("res://addons/yamms/MultiScatterItem.gd")
const MultiScatterExcludeScript := preload("res://addons/yamms/MultiScatterExclude.gd")
const PMDropOnColliderScript := preload("res://addons/yamms/PMDropOnCollider.gd")

var _config: Dictionary = {}


func _initialize() -> void:
	_config = _load_config()
	var items: Array = _config.get("items", [])
	if items.is_empty():
		push_error("%s defines no items." % CONFIG_PATH)
		quit(1)
		return

	var main_scene := load(MAIN_SCENE_PATH) as PackedScene
	if main_scene == null:
		push_error("Could not load %s." % MAIN_SCENE_PATH)
		quit(1)
		return

	var main := main_scene.instantiate()
	root.add_child(main)
	for _i in 6:
		await physics_frame

	var world := main.get_node_or_null(NodePath("World")) as Node3D
	if world == null:
		push_error("Main scene is missing World node.")
		quit(1)
		return

	var multi_scatter := _build_multiscatter(world)
	if multi_scatter == null:
		quit(1)
		return

	# Run generation synchronously here (not via _physics_process); a real
	# renderer is required (see header note).
	multi_scatter.do_generate()

	var total := _bake_and_save(multi_scatter)
	if total < 0:
		quit(1)
		return

	_save_authoring(multi_scatter, world)

	main.free()
	print("Yamms forest generated and baked: %d instances across %d variants." % [total, items.size()])
	quit(0)


# --- Config loading -------------------------------------------------------

func _load_config() -> Dictionary:
	var cfg := _default_config()
	if not FileAccess.file_exists(CONFIG_PATH):
		push_warning("%s missing; using built-in defaults." % CONFIG_PATH)
		return cfg
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_warning("Could not open %s; using defaults." % CONFIG_PATH)
		return cfg
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		_deep_merge(cfg, parsed as Dictionary)
	else:
		push_error("Invalid JSON in %s; using defaults." % CONFIG_PATH)
	return cfg


func _default_config() -> Dictionary:
	return {
		"output": {
			"baked_scene": "res://Scenes/Plants/ForestMultiMesh.tscn",
			"authoring_scene": "res://Scenes/Plants/ForestScatterAuthoring.tscn",
			"root_name": "ForestMultiMesh",
		},
		"global": {
			"seed": 202605261,
			"density_multiplier": 1.0,
			"ground_collision_mask": 1,
			"ray_height": 42.0,
			"visibility_range_end": 180.0,
			"custom_aabb": {"position": [-124.0, -6.0, -124.0], "size": [248.0, 22.0, 248.0]},
		},
		"area": {
			"source": "authoring",
			"polygon": {"shape": "ellipse", "radius": [122.0, 118.0], "inset": 0.95, "segments": 24},
			"exclusions": [],
		},
		"placement_defaults": {
			"mode": "drop_on_collider",
			"normal_influence": 0.0,
			"rotation": {"randomize": true, "min_deg": [0.0, 0.0, 0.0], "max_deg": [0.0, 360.0, 0.0]},
		},
		"categories": {},
		"items": [],
	}


func _deep_merge(base: Dictionary, override: Dictionary) -> void:
	for key in override.keys():
		var override_value: Variant = override[key]
		if base.has(key) and base[key] is Dictionary and override_value is Dictionary:
			_deep_merge(base[key], override_value)
		else:
			base[key] = override_value


# --- Build ----------------------------------------------------------------

func _build_multiscatter(world: Node3D) -> Node3D:
	var items: Array = _config["items"]
	var global: Dictionary = _config["global"]
	var density := float(global.get("density_multiplier", 1.0))

	var counts: Array[int] = []
	var total_count := 0
	for it in items:
		var c := int(round(float(it.get("count", 0)) * density))
		counts.append(c)
		total_count += c
	if total_count <= 0:
		push_error("Total instance count resolved to 0.")
		return null

	# Polygon + exclusions: preserved from the authoring scene when configured.
	var polygon: Curve3D = null
	var excludes: Array = []
	if str(_config["area"].get("source", "authoring")) == "authoring":
		var preserved := _preserved_area()
		polygon = preserved[0]
		excludes = preserved[1]
	if polygon == null:
		polygon = _build_area_curve()
	if excludes.is_empty():
		excludes = _build_exclude_curves()

	var multi_scatter: Node3D = MultiScatterScript.new()
	multi_scatter.name = "ForestScatter"
	multi_scatter.curve = polygon
	multi_scatter.amount = total_count
	multi_scatter.seed = int(global.get("seed", 0))
	world.add_child(multi_scatter)

	for ex in excludes:
		var exclude: Node3D = MultiScatterExcludeScript.new()
		exclude.name = str(ex["name"])
		exclude.curve = ex["curve"]
		multi_scatter.add_child(exclude)

	var defaults: Dictionary = _config.get("placement_defaults", {})
	var categories: Dictionary = _config.get("categories", {})
	for i in items.size():
		var it: Dictionary = items[i]
		var cat_cfg: Dictionary = categories.get(str(it.get("category", "")), {})

		var mesh := _load_first_mesh(str(it["mesh"]))
		if mesh == null:
			push_error("Could not load mesh from %s." % it.get("mesh", "?"))
			return null
		var base_height: float = maxf(mesh.get_aabb().size.y, 0.01)

		var multi_mesh := MultiMesh.new()
		multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
		multi_mesh.mesh = mesh

		var item: Node3D = MultiScatterItemScript.new()
		item.name = "%sItem" % str(it["name"])
		item.multimesh = multi_mesh
		item.percentage = float(counts[i]) / float(total_count) * 100.0
		multi_scatter.add_child(item)

		var rotation: Dictionary = _resolve_rotation(it, cat_cfg, defaults)
		var placement: Node3D = PMDropOnColliderScript.new()
		placement.name = "DropOnGround"
		placement.collision_mask = int(global.get("ground_collision_mask", 1))
		placement.placement_direction = 1  # direction.Down
		placement.normal_influence = float(_resolve(it, cat_cfg, defaults, "normal_influence", 0.0))
		placement.random_scale_type = 1    # scale_type_enum.Proportional
		placement.min_random_scale = float(it["height_min"]) / base_height
		placement.max_random_scale = float(it["height_max"]) / base_height
		placement.randomize_rotation = bool(rotation.get("randomize", true))
		placement.min_random_rotation = _to_vec3(rotation.get("min_deg"), Vector3.ZERO)
		placement.max_random_rotation = _to_vec3(rotation.get("max_deg"), Vector3(0.0, 360.0, 0.0))
		item.add_child(placement)

	return multi_scatter


# Returns [Curve3D polygon_or_null, Array exclude_dicts] from the saved authoring
# scene, so editor reshaping is preserved across rebuilds.
func _preserved_area() -> Array:
	var authoring_path := str(_config["output"].get("authoring_scene", ""))
	if authoring_path.is_empty() or not ResourceLoader.exists(authoring_path):
		return [null, []]
	var packed := load(authoring_path) as PackedScene
	if packed == null:
		return [null, []]
	var old := packed.instantiate() as Path3D
	if old == null:
		return [null, []]
	var polygon: Curve3D = null
	if old.curve != null:
		polygon = old.curve.duplicate()
	var excludes: Array = []
	for child in old.get_children():
		if child is MultiScatterExclude and (child as Path3D).curve != null:
			excludes.append({"name": child.name, "curve": (child as Path3D).curve.duplicate()})
	old.free()
	print("Preserved polygon + %d exclusion(s) from existing authoring scene." % excludes.size())
	return [polygon, excludes]


func _build_area_curve() -> Curve3D:
	var poly: Dictionary = _config["area"].get("polygon", {})
	var ray_height := float(_config["global"].get("ray_height", 42.0))
	var curve := Curve3D.new()
	if str(poly.get("shape", "ellipse")) == "points":
		for p in poly.get("points", []):
			var v := _to_vec2(p, Vector2.ZERO)
			curve.add_point(Vector3(v.x, ray_height, v.y))
	else:
		var radius := _to_vec2(poly.get("radius"), Vector2(122.0, 118.0))
		var inset := float(poly.get("inset", 0.95))
		var segments := int(poly.get("segments", 24))
		for i in segments:
			var angle := TAU * float(i) / float(segments)
			curve.add_point(Vector3(cos(angle) * radius.x * inset, ray_height, sin(angle) * radius.y * inset))
	return curve


func _build_exclude_curves() -> Array:
	var result: Array = []
	for ex in _config["area"].get("exclusions", []):
		var curve := Curve3D.new()
		if str(ex.get("shape", "rect")) == "points":
			for p in ex.get("points", []):
				var v := _to_vec2(p, Vector2.ZERO)
				curve.add_point(Vector3(v.x, 0.0, v.y))
		else:
			var pos := _to_vec2(ex.get("position"), Vector2.ZERO)
			var size := _to_vec2(ex.get("size"), Vector2.ZERO)
			curve.add_point(Vector3(pos.x, 0.0, pos.y))
			curve.add_point(Vector3(pos.x + size.x, 0.0, pos.y))
			curve.add_point(Vector3(pos.x + size.x, 0.0, pos.y + size.y))
			curve.add_point(Vector3(pos.x, 0.0, pos.y + size.y))
		result.append({"name": "%sExclude" % str(ex.get("name", "Area")), "curve": curve})
	return result


# --- Bake -----------------------------------------------------------------

func _bake_and_save(multi_scatter: Node3D) -> int:
	var items: Array = _config["items"]
	var categories: Dictionary = _config.get("categories", {})
	var global: Dictionary = _config["global"]
	var output: Dictionary = _config["output"]
	var default_vis := float(global.get("visibility_range_end", 180.0))
	var aabb := _custom_aabb()

	var forest_root := Node3D.new()
	forest_root.name = str(output.get("root_name", "ForestMultiMesh"))
	forest_root.set_meta("visual_only", true)
	forest_root.set_meta("generated_by", "tools/codex_generate_forest_yamms.gd")
	forest_root.set_meta("source_config", CONFIG_PATH)

	var category_nodes := {}
	for it in items:
		var cat := str(it.get("category", "Uncategorized"))
		if not category_nodes.has(cat):
			var node := Node3D.new()
			node.name = cat
			forest_root.add_child(node)
			node.owner = forest_root
			category_nodes[cat] = node

	var scatter_items := _collect_items(multi_scatter)
	if scatter_items.size() != items.size():
		push_error("Expected %d MultiScatterItems, found %d." % [items.size(), scatter_items.size()])
		forest_root.free()
		return -1

	var total_instances := 0
	for i in items.size():
		var it: Dictionary = items[i]
		var cat := str(it.get("category", "Uncategorized"))
		var cat_cfg: Dictionary = categories.get(cat, {})
		var item: Node3D = scatter_items[i]
		var source_mm: MultiMesh = item.multimesh
		if source_mm == null or source_mm.instance_count <= 0:
			push_error("%s produced no instances." % it.get("name", "?"))
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
		baked_mm.custom_aabb = aabb
		baked_mm.visible_instance_count = count

		var instance := MultiMeshInstance3D.new()
		instance.name = "%sMultiMesh" % str(it["name"])
		instance.multimesh = baked_mm
		instance.cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			if bool(_resolve(it, cat_cfg, {}, "shadow", false))
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		)
		instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		instance.visibility_range_end = float(_resolve(it, cat_cfg, {}, "visibility_range_end", default_vis))

		var category_node: Node3D = category_nodes[cat]
		category_node.add_child(instance)
		instance.owner = forest_root
		total_instances += count

	var packed_scene := PackedScene.new()
	if packed_scene.pack(forest_root) != OK:
		push_error("Could not pack baked forest scene.")
		forest_root.free()
		return -1
	if ResourceSaver.save(packed_scene, str(output["baked_scene"])) != OK:
		push_error("Could not save %s." % output["baked_scene"])
		forest_root.free()
		return -1

	forest_root.free()
	return total_instances


func _save_authoring(multi_scatter: Node3D, world: Node3D) -> void:
	var authoring_path := str(_config["output"].get("authoring_scene", ""))
	if authoring_path.is_empty():
		return
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
	if ResourceSaver.save(packed, authoring_path) != OK:
		push_error("Could not save %s." % authoring_path)
		return
	print("Saved editable authoring setup %s." % authoring_path)


# --- Helpers --------------------------------------------------------------

func _resolve(item: Dictionary, category: Dictionary, defaults: Dictionary, key: String, default_value):
	if item.has(key):
		return item[key]
	if category.has(key):
		return category[key]
	if defaults.has(key):
		return defaults[key]
	return default_value


func _resolve_rotation(item: Dictionary, category: Dictionary, defaults: Dictionary) -> Dictionary:
	if item.get("rotation") is Dictionary:
		return item["rotation"]
	if category.get("rotation") is Dictionary:
		return category["rotation"]
	if defaults.get("rotation") is Dictionary:
		return defaults["rotation"]
	return {}


func _custom_aabb() -> AABB:
	var c: Dictionary = _config["global"].get("custom_aabb", {})
	var pos := _to_vec3(c.get("position"), Vector3(-124.0, -6.0, -124.0))
	var size := _to_vec3(c.get("size"), Vector3(248.0, 22.0, 248.0))
	return AABB(pos, size)


func _to_vec2(value: Variant, default_value: Vector2) -> Vector2:
	if value is Array and (value as Array).size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return default_value


func _to_vec3(value: Variant, default_value: Vector3) -> Vector3:
	if value is Array and (value as Array).size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return default_value


func _collect_items(multi_scatter: Node3D) -> Array:
	var items: Array = []
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
