extends SceneTree

const BuildingScript = preload("res://Entities/Buildings/Building.gd")

const MAIN_SCENE_PATH := "res://Main.tscn"
const OUTPUT_ROOT_DIR := "res://Scenes/CityBuildings"
const TARGET_CATEGORY_NAMES := [
	"Services",
	"Production",
	"Garages",
	"Stores",
	"Multilayer",
	"Foundation",
	"Multi-building",
	"Commercial building",
	"Park",
]

const CATEGORY_ARCHETYPES := {
	"Services": ["city_hall", "university", "restaurant", "gas_station"],
	"Production": ["farm", "factory"],
	"Garages": ["gas_station", "factory"],
	"Stores": ["shop", "restaurant", "supermarket", "cafe", "cinema"],
	"Multilayer": ["residential"],
	"Foundation": ["residential", "shop"],
	"Multi-building": ["residential"],
	"Commercial building": ["shop", "restaurant", "supermarket"],
	"Park": ["park"],
}

const ARCHETYPE_SCRIPT_PATH := {
	"generic": "res://Entities/Buildings/Building.gd",
	"residential": "res://Entities/Buildings/ResidentialBuilding.gd",
	"restaurant": "res://Entities/Buildings/Restaurant.gd",
	"shop": "res://Entities/Buildings/Shop.gd",
	"supermarket": "res://Entities/Buildings/Supermarket.gd",
	"cafe": "res://Entities/Buildings/Cafe.gd",
	"city_hall": "res://Entities/Buildings/CityHall.gd",
	"university": "res://Entities/Buildings/University.gd",
	"cinema": "res://Entities/Buildings/Cinema.gd",
	"park": "res://Entities/Buildings/Park.gd",
	"farm": "res://Entities/Buildings/Farm.gd",
	"factory": "res://Entities/Buildings/Factory.gd",
	"gas_station": "res://Entities/Buildings/GasStation.gd",
}

const ARCHETYPE_BUILDING_TYPE := {
	"generic": BuildingScript.BuildingType.GENERIC,
	"residential": BuildingScript.BuildingType.RESIDENTIAL,
	"restaurant": BuildingScript.BuildingType.RESTAURANT,
	"shop": BuildingScript.BuildingType.SHOP,
	"supermarket": BuildingScript.BuildingType.SUPERMARKET,
	"cafe": BuildingScript.BuildingType.CAFE,
	"city_hall": BuildingScript.BuildingType.CITY_HALL,
	"university": BuildingScript.BuildingType.UNIVERSITY,
	"cinema": BuildingScript.BuildingType.CINEMA,
	"park": BuildingScript.BuildingType.PARK,
	"farm": BuildingScript.BuildingType.FARM,
	"factory": BuildingScript.BuildingType.FACTORY,
	"gas_station": BuildingScript.BuildingType.GAS_STATION,
}

const ARCHETYPE_LABEL := {
	"generic": "Building",
	"residential": "Residential",
	"restaurant": "Restaurant",
	"shop": "Shop",
	"supermarket": "Supermarket",
	"cafe": "Cafe",
	"city_hall": "City Hall",
	"university": "University",
	"cinema": "Cinema",
	"park": "Park",
	"farm": "Farm",
	"factory": "Factory",
	"gas_station": "Gas Station",
}

var _signature_to_scene_path: Dictionary = {}
var _unique_counter_by_category: Dictionary = {}
var _created_scene_count = 0
var _replaced_instance_count = 0

func _init() -> void:
	var exit_code = _run()
	quit(exit_code)

func _run() -> int:
	var main_scene: PackedScene = load(MAIN_SCENE_PATH)
	if main_scene == null:
		push_error("CitySceneRefactor: Could not load %s" % MAIN_SCENE_PATH)
		return 1

	var root = main_scene.instantiate() as Node
	if root == null:
		push_error("CitySceneRefactor: Could not instantiate %s" % MAIN_SCENE_PATH)
		return 1

	var people_root = root.get_node_or_null("World/City/only_people_nav/only_people") as Node3D
	if people_root == null:
		push_error("CitySceneRefactor: Node path 'World/City/only_people_nav/only_people' not found.")
		return 1

	_ensure_directory(OUTPUT_ROOT_DIR)
	for category_name in TARGET_CATEGORY_NAMES:
		_process_category(root, people_root, category_name)

	var packed_main = PackedScene.new()
	_set_owner_recursive(root, root)
	var pack_err = packed_main.pack(root)
	if pack_err != OK:
		push_error("CitySceneRefactor: Could not pack Main scene (%s)." % error_string(pack_err))
		return 1

	var save_err = ResourceSaver.save(packed_main, MAIN_SCENE_PATH)
	if save_err != OK:
		push_error("CitySceneRefactor: Could not save Main scene (%s)." % error_string(save_err))
		return 1

	print("CitySceneRefactor: Created %d scene prefabs." % _created_scene_count)
	print("CitySceneRefactor: Replaced %d imported instances." % _replaced_instance_count)
	return 0

func _process_category(main_root: Node, people_root: Node3D, category_name: String) -> void:
	var category = people_root.get_node_or_null(category_name) as Node3D
	if category == null:
		print("CitySceneRefactor: Category missing -> %s" % category_name)
		return

	var candidates: Array[Node3D] = []
	for child in category.get_children():
		if child is Node3D:
			var node_3d = child as Node3D
			if node_3d.scene_file_path.begins_with(OUTPUT_ROOT_DIR + "/"):
				continue
			candidates.append(node_3d)

	for source in candidates:
		var signature = _build_signature(source, true)
		var scene_path = str(_signature_to_scene_path.get(signature, ""))
		if scene_path == "":
			var unique_index = int(_unique_counter_by_category.get(category_name, 0))
			_unique_counter_by_category[category_name] = unique_index + 1
			var archetype = _pick_archetype(category_name, unique_index)
			scene_path = _create_prefab_scene(category_name, archetype, unique_index, source, signature)
			if scene_path == "":
				continue
			_signature_to_scene_path[signature] = scene_path

		var packed: PackedScene = load(scene_path)
		if packed == null:
			push_warning("CitySceneRefactor: Could not reload prefab %s" % scene_path)
			continue
		var replacement = packed.instantiate() as Node3D
		if replacement == null:
			push_warning("CitySceneRefactor: Prefab is not Node3D %s" % scene_path)
			continue

		var source_index = source.get_index()
		replacement.name = source.name
		replacement.transform = source.transform
		replacement.visible = source.visible

		category.add_child(replacement)
		category.move_child(replacement, source_index)
		replacement.owner = main_root
		_set_owner_recursive(replacement, main_root)

		category.remove_child(source)
		source.free()
		_replaced_instance_count += 1

func _create_prefab_scene(category_name: String, archetype: String, unique_index: int, source: Node3D, signature: String) -> String:
	var category_slug = _slugify(category_name)
	var category_dir = "%s/%s" % [OUTPUT_ROOT_DIR, category_slug]
	_ensure_directory(category_dir)

	var signature_hash = abs(signature.hash())
	var scene_file_name = "%s_%03d_%08x.tscn" % [category_slug, unique_index + 1, signature_hash]
	var scene_path = "%s/%s" % [category_dir, scene_file_name]

	var flags = Node.DuplicateFlags.DUPLICATE_SIGNALS \
		| Node.DuplicateFlags.DUPLICATE_GROUPS \
		| Node.DuplicateFlags.DUPLICATE_SCRIPTS \
		| Node.DuplicateFlags.DUPLICATE_USE_INSTANTIATION
	var prefab_root = source.duplicate(flags) as Node3D
	if prefab_root == null:
		push_warning("CitySceneRefactor: Could not duplicate %s" % source.name)
		return ""

	prefab_root.name = _prefab_node_name(category_name, archetype, unique_index)
	_apply_archetype(prefab_root, category_name, archetype, unique_index)
	_ensure_entrance(prefab_root)

	_set_owner_recursive(prefab_root, prefab_root)
	var packed = PackedScene.new()
	var pack_err = packed.pack(prefab_root)
	if pack_err != OK:
		push_warning("CitySceneRefactor: Could not pack prefab %s (%s)" % [scene_path, error_string(pack_err)])
		return ""

	var save_err = ResourceSaver.save(packed, scene_path)
	if save_err != OK:
		push_warning("CitySceneRefactor: Could not save prefab %s (%s)" % [scene_path, error_string(save_err)])
		return ""

	_created_scene_count += 1
	return scene_path

func _pick_archetype(category_name: String, unique_index: int) -> String:
	var archetypes: Array = CATEGORY_ARCHETYPES.get(category_name, ["generic"])
	if archetypes.is_empty():
		return "generic"
	return str(archetypes[unique_index % archetypes.size()])

func _apply_archetype(root: Node3D, category_name: String, archetype: String, unique_index: int) -> void:
	var script_path = str(ARCHETYPE_SCRIPT_PATH.get(archetype, ARCHETYPE_SCRIPT_PATH["generic"]))
	var script_resource: Script = load(script_path)
	if script_resource != null:
		root.set_script(script_resource)
	else:
		push_warning("CitySceneRefactor: Missing script %s for archetype %s" % [script_path, archetype])

	_set_prop_if_exists(root, "building_name", _prefab_label(category_name, archetype, unique_index))
	_set_prop_if_exists(root, "building_type", int(ARCHETYPE_BUILDING_TYPE.get(archetype, 0)))

	if not root.is_in_group("buildings"):
		root.add_to_group("buildings")
	if not root.is_in_group("city_buildings"):
		root.add_to_group("city_buildings")

	var category_group = "city_%s" % _slugify(category_name)
	if not root.is_in_group(category_group):
		root.add_to_group(category_group)

	if archetype == "residential" and not root.is_in_group("residential"):
		root.add_to_group("residential")
	if archetype == "park" and not root.is_in_group("parks"):
		root.add_to_group("parks")
	if archetype in ["shop", "restaurant", "supermarket", "cafe", "cinema", "gas_station"] \
		and not root.is_in_group("commercial"):
		root.add_to_group("commercial")
	if archetype in ["shop", "restaurant", "supermarket", "cafe", "cinema", "factory", "farm", "city_hall", "university", "gas_station"] \
		and not root.is_in_group("work"):
		root.add_to_group("work")

func _ensure_entrance(root: Node3D) -> void:
	var entrance = root.get_node_or_null("Entrance") as Node3D
	if entrance == null:
		entrance = Node3D.new()
		entrance.name = "Entrance"
		entrance.position = _estimate_entrance_position(root)
		root.add_child(entrance)
		entrance.owner = root
	else:
		entrance.position = _estimate_entrance_position(root)

	_set_prop_if_exists(root, "entrance", entrance)

func _estimate_entrance_position(root: Node3D) -> Vector3:
	var aabb = _compute_local_aabb(root)
	var center = aabb.position + aabb.size * 0.5
	var floor_y = maxf(aabb.position.y + 0.06, 0.06)
	return Vector3(center.x, floor_y, center.z)

func _compute_local_aabb(root: Node3D) -> AABB:
	var state = {
		"has_value": false,
		"min": Vector3.ZERO,
		"max": Vector3.ZERO,
	}

	for child in root.get_children():
		if child is Node:
			_collect_mesh_bounds(child as Node, Transform3D.IDENTITY, state)

	if not bool(state["has_value"]):
		return AABB(Vector3(-0.75, 0.0, -0.75), Vector3(1.5, 2.0, 1.5))

	var min_v = state["min"] as Vector3
	var max_v = state["max"] as Vector3
	return AABB(min_v, max_v - min_v)

func _collect_mesh_bounds(node: Node, parent_xform: Transform3D, state: Dictionary) -> void:
	var node_xform = parent_xform
	if node is Node3D:
		node_xform = parent_xform * (node as Node3D).transform

	if node is MeshInstance3D:
		var mesh_instance = node as MeshInstance3D
		if mesh_instance.mesh != null:
			for corner in _aabb_corners(mesh_instance.mesh.get_aabb()):
				var p = node_xform * corner
				if not bool(state["has_value"]):
					state["has_value"] = true
					state["min"] = p
					state["max"] = p
				else:
					var min_v = state["min"] as Vector3
					var max_v = state["max"] as Vector3
					state["min"] = Vector3(
						minf(min_v.x, p.x),
						minf(min_v.y, p.y),
						minf(min_v.z, p.z)
					)
					state["max"] = Vector3(
						maxf(max_v.x, p.x),
						maxf(max_v.y, p.y),
						maxf(max_v.z, p.z)
					)

	for child in node.get_children():
		if child is Node:
			_collect_mesh_bounds(child as Node, node_xform, state)

func _aabb_corners(aabb: AABB) -> Array[Vector3]:
	var p = aabb.position
	var s = aabb.size
	return [
		p,
		p + Vector3(s.x, 0, 0),
		p + Vector3(0, s.y, 0),
		p + Vector3(0, 0, s.z),
		p + Vector3(s.x, s.y, 0),
		p + Vector3(s.x, 0, s.z),
		p + Vector3(0, s.y, s.z),
		p + s,
	]

func _build_signature(node: Node, is_root: bool) -> String:
	var tokens = PackedStringArray()
	_append_signature_tokens(node, is_root, tokens)
	return "||".join(tokens)

func _append_signature_tokens(node: Node, is_root: bool, out: PackedStringArray) -> void:
	var token = node.get_class()
	if node is Node3D and not is_root:
		token += "@%s" % _transform_key((node as Node3D).transform)
	if node is MeshInstance3D:
		var mesh_instance = node as MeshInstance3D
		if mesh_instance.mesh != null:
			var mesh_path = mesh_instance.mesh.resource_path
			token += "#mesh:%s" % (mesh_path if mesh_path != "" else "<mesh>")
		else:
			token += "#mesh:null"
	if node.scene_file_path != "":
		token += "#scene:%s" % node.scene_file_path

	out.append(token)

	var child_chunks: Array[String] = []
	for child in node.get_children():
		if child is Node:
			var nested = PackedStringArray()
			_append_signature_tokens(child as Node, false, nested)
			child_chunks.append("%s[%s]" % [str(child.name), "||".join(nested)])
	child_chunks.sort()
	out.append("{%s}" % "|".join(child_chunks))

func _transform_key(xform: Transform3D) -> String:
	var o = xform.origin
	var b = xform.basis
	return "%.3f,%.3f,%.3f|%.3f,%.3f,%.3f|%.3f,%.3f,%.3f|%.3f,%.3f,%.3f" % [
		b.x.x, b.x.y, b.x.z,
		b.y.x, b.y.y, b.y.z,
		b.z.x, b.z.y, b.z.z,
		o.x, o.y, o.z
	]

func _set_prop_if_exists(target: Object, prop_name: String, value) -> void:
	if _has_property(target, prop_name):
		target.set(prop_name, value)

func _has_property(target: Object, prop_name: String) -> bool:
	for item in target.get_property_list():
		if str(item.name) == prop_name:
			return true
	return false

func _set_owner_recursive(node: Node, owner: Node) -> void:
	for child in node.get_children():
		if child is Node:
			var n = child as Node
			n.owner = owner
			_set_owner_recursive(n, owner)

func _prefab_node_name(category_name: String, archetype: String, unique_index: int) -> String:
	return "%s_%s_%02d" % [_slugify(category_name), _slugify(archetype), unique_index + 1]

func _prefab_label(category_name: String, archetype: String, unique_index: int) -> String:
	var label = str(ARCHETYPE_LABEL.get(archetype, "Building"))
	return "%s %02d (%s)" % [label, unique_index + 1, category_name]

func _slugify(input: String) -> String:
	var text = input.to_lower().strip_edges()
	var out = ""
	for i in text.length():
		var code = text.unicode_at(i)
		var is_alpha = code >= 97 and code <= 122
		var is_num = code >= 48 and code <= 57
		if is_alpha or is_num:
			out += char(code)
		else:
			out += "_"

	while out.find("__") >= 0:
		out = out.replace("__", "_")

	out = out.strip_edges()
	if out.begins_with("_"):
		out = out.trim_prefix("_")
	if out.ends_with("_"):
		out = out.trim_suffix("_")

	if out == "":
		return "item"
	return out

func _ensure_directory(res_path: String) -> void:
	var abs_path = ProjectSettings.globalize_path(res_path)
	var err = DirAccess.make_dir_recursive_absolute(abs_path)
	if err != OK and err != ERR_ALREADY_EXISTS:
		push_warning("CitySceneRefactor: Could not create directory %s (%s)" % [res_path, error_string(err)])

