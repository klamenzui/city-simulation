extends SceneTree

# Generates one editable Yamms MultiScatter scene per biome from the data-driven
# recipe in config/forest_scatter.json. The biome scenes are meant to be
# instanced under World in Main.tscn (where the ground collider lives) and filled
# live with the Yamms "Generate" button in the editor.
#
# This tool ONLY writes the per-biome scenes under output.biome_scene_dir. It
# never touches Main.tscn and does not bake — the live MultiScatter nodes are the
# runtime. Because no instances are generated here (no set_instance_transform),
# it is safe to run headless:
#   Godot_v4.6.3-stable_win64_console.exe --headless --path . \
#     --script res://tools/codex_generate_forest_yamms.gd
#
# Per biome, items + settings ALWAYS come from the config. When area.source ==
# "authoring" the polygon + exclusions are preserved from the existing biome
# scene (so editor reshaping of that scene file survives a rebuild).

const CONFIG_PATH := "res://config/forest_scatter.json"

const MultiScatterScript := preload("res://addons/yamms/MultiScatter.gd")
const MultiScatterItemScript := preload("res://addons/yamms/MultiScatterItem.gd")
const MultiScatterExcludeScript := preload("res://addons/yamms/MultiScatterExclude.gd")
const PMDropOnColliderScript := preload("res://addons/yamms/PMDropOnCollider.gd")

var _config: Dictionary = {}


func _initialize() -> void:
	_config = _load_config()
	var biomes: Array = _config.get("biomes", [])
	if biomes.is_empty():
		push_error("%s defines no biomes." % CONFIG_PATH)
		quit(1)
		return

	var dir := str(_config.get("output", {}).get("biome_scene_dir", "res://Scenes/Plants/Biomes/"))
	if not _ensure_dir(dir):
		quit(1)
		return

	var generated := 0
	for biome in biomes:
		if not _build_biome_scene(biome, dir):
			quit(1)
			return
		generated += 1

	print("Generated %d biome scatter scene(s) in %s." % [generated, dir])
	quit(0)


# --- Config ---------------------------------------------------------------

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
		"output": {"biome_scene_dir": "res://Scenes/Plants/Biomes/", "root_suffix": "Scatter"},
		"global": {
			"seed": 202605261,
			"density_multiplier": 1.0,
			"ground_collision_mask": 1,
			"ray_height": 42.0,
			"visibility_range_end": 180.0,
		},
		"placement_defaults": {
			"normal_influence": 0.0,
			"rotation": {"randomize": true, "min_deg": [0.0, 0.0, 0.0], "max_deg": [0.0, 360.0, 0.0]},
		},
		"categories": {},
		"biomes": [],
	}


func _deep_merge(base: Dictionary, override: Dictionary) -> void:
	for key in override.keys():
		var override_value: Variant = override[key]
		if base.has(key) and base[key] is Dictionary and override_value is Dictionary:
			_deep_merge(base[key], override_value)
		else:
			base[key] = override_value


# --- Biome scene build ----------------------------------------------------

func _build_biome_scene(biome: Dictionary, dir: String) -> bool:
	var biome_name := str(biome.get("name", "Biome"))
	var items: Array = biome.get("items", [])
	if items.is_empty():
		push_error("Biome '%s' has no items." % biome_name)
		return false

	var global: Dictionary = _config["global"]
	var defaults: Dictionary = _config.get("placement_defaults", {})
	var categories: Dictionary = _config.get("categories", {})
	var density := float(global.get("density_multiplier", 1.0))
	var default_vis := float(global.get("visibility_range_end", 180.0))
	var scene_path := "%s%s.tscn" % [dir, biome_name]

	var counts: Array[int] = []
	var total_count := 0
	for it in items:
		var c := int(round(float(it.get("count", 0)) * density))
		counts.append(c)
		total_count += c
	if total_count <= 0:
		push_error("Biome '%s' total count resolved to 0." % biome_name)
		return false

	# Polygon + exclusions: preserved from the existing biome scene when set to
	# "authoring", otherwise built from the config.
	var area: Dictionary = biome.get("area", {})
	var polygon: Curve3D = null
	var excludes: Array = []
	if str(area.get("source", "authoring")) == "authoring":
		var preserved := _preserved_area(scene_path)
		polygon = preserved[0]
		excludes = preserved[1]
	if polygon == null:
		polygon = _build_area_curve(area)
	if excludes.is_empty():
		excludes = _build_exclude_curves(area)

	var multi_scatter: Node3D = MultiScatterScript.new()
	multi_scatter.name = "%s%s" % [biome_name, str(_config["output"].get("root_suffix", "Scatter"))]
	multi_scatter.curve = polygon
	multi_scatter.amount = total_count
	multi_scatter.seed = int(global.get("seed", 0))

	for ex in excludes:
		var exclude: Node3D = MultiScatterExcludeScript.new()
		exclude.name = str(ex["name"])
		exclude.curve = ex["curve"]
		multi_scatter.add_child(exclude)
		exclude.owner = multi_scatter

	for i in items.size():
		var it: Dictionary = items[i]
		var cat_cfg: Dictionary = categories.get(str(it.get("category", "")), {})

		var mesh := _load_mesh(str(it["mesh"]))
		if mesh == null:
			push_error("Biome '%s': could not load mesh %s." % [biome_name, it.get("mesh", "?")])
			return false

		var multi_mesh := MultiMesh.new()
		multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
		multi_mesh.mesh = mesh

		var item: Node3D = MultiScatterItemScript.new()
		item.name = "%sItem" % str(it["name"])
		item.multimesh = multi_mesh
		item.percentage = float(counts[i]) / float(total_count) * 100.0
		item.cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			if bool(_resolve(it, cat_cfg, {}, "shadow", false))
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		)
		item.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		item.visibility_range_end = float(_resolve(it, cat_cfg, {}, "visibility_range_end", default_vis))
		multi_scatter.add_child(item)
		item.owner = multi_scatter

		var placement: Node3D = PMDropOnColliderScript.new()
		placement.name = "DropOnGround"
		placement.collision_mask = int(global.get("ground_collision_mask", 1))
		placement.placement_direction = 1  # direction.Down
		placement.normal_influence = float(_resolve(it, cat_cfg, defaults, "normal_influence", 0.0))
		placement.random_scale_type = 1    # scale_type_enum.Proportional
		var scale_range := _scale_range(it, mesh)
		placement.min_random_scale = scale_range.x
		placement.max_random_scale = scale_range.y
		var rotation: Dictionary = _resolve_rotation(it, cat_cfg, defaults)
		placement.randomize_rotation = bool(rotation.get("randomize", true))
		placement.min_random_rotation = _to_vec3(rotation.get("min_deg"), Vector3.ZERO)
		placement.max_random_rotation = _to_vec3(rotation.get("max_deg"), Vector3(0.0, 360.0, 0.0))
		item.add_child(placement)
		placement.owner = multi_scatter

	var packed := PackedScene.new()
	if packed.pack(multi_scatter) != OK:
		push_error("Could not pack biome '%s'." % biome_name)
		multi_scatter.free()
		return false
	if ResourceSaver.save(packed, scene_path) != OK:
		push_error("Could not save %s." % scene_path)
		multi_scatter.free()
		return false
	multi_scatter.free()
	print("  %s -> %s (%d items, amount=%d)" % [biome_name, scene_path, items.size(), total_count])
	return true


# Returns [Curve3D polygon_or_null, Array exclude_dicts] from an existing biome
# scene so editor reshaping of that scene survives a rebuild.
func _preserved_area(scene_path: String) -> Array:
	if not ResourceLoader.exists(scene_path):
		return [null, []]
	var packed := load(scene_path) as PackedScene
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
	print("  preserved polygon + %d exclusion(s) from existing %s" % [excludes.size(), scene_path])
	return [polygon, excludes]


func _build_area_curve(area: Dictionary) -> Curve3D:
	var poly: Dictionary = area.get("polygon", {})
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


func _build_exclude_curves(area: Dictionary) -> Array:
	var result: Array = []
	for ex in area.get("exclusions", []):
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


# --- Helpers --------------------------------------------------------------

# Proportional scale range. Prefer explicit scale_min/scale_max; otherwise derive
# from target height_min/height_max relative to the mesh's base height.
func _scale_range(item: Dictionary, mesh: Mesh) -> Vector2:
	if item.has("scale_min") and item.has("scale_max"):
		return Vector2(float(item["scale_min"]), float(item["scale_max"]))
	if item.has("height_min") and item.has("height_max"):
		var base_height: float = maxf(mesh.get_aabb().size.y, 0.01)
		return Vector2(float(item["height_min"]) / base_height, float(item["height_max"]) / base_height)
	return Vector2(0.8, 1.2)


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


func _to_vec2(value: Variant, default_value: Vector2) -> Vector2:
	if value is Array and (value as Array).size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return default_value


func _to_vec3(value: Variant, default_value: Vector3) -> Vector3:
	if value is Array and (value as Array).size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return default_value


func _ensure_dir(dir: String) -> bool:
	if DirAccess.dir_exists_absolute(dir):
		return true
	if DirAccess.make_dir_recursive_absolute(dir) != OK:
		push_error("Could not create directory %s." % dir)
		return false
	return true


func _load_mesh(path: String) -> Mesh:
	var res: Resource = load(path)
	if res is Mesh:
		return res as Mesh
	if res is PackedScene:
		var scene_root := (res as PackedScene).instantiate()
		var mesh := _find_first_mesh(scene_root)
		scene_root.free()
		return mesh
	return null


func _find_first_mesh(node: Node) -> Mesh:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		return (node as MeshInstance3D).mesh
	for child in node.get_children():
		var mesh := _find_first_mesh(child)
		if mesh != null:
			return mesh
	return null
