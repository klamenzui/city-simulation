extends RefCounted
class_name SceneVisualLodController

const CONFIG_PATH := "res://config/visual_lod.json"
const META_DEBUG_HIDDEN := "city_visual_lod_debug_hidden"
const META_GEOMETRY_CONFIGURED := "city_visual_lod_geometry_configured"
const META_LIGHT_CONFIGURED := "city_visual_lod_light_configured"

var owner_node: Node = null
var city_camera: Camera3D = null

var _config: Dictionary = {}
var _summary: Dictionary = {
	"enabled": false,
	"configured_meshes": 0,
	"configured_lights": 0,
	"disabled_shadow_meshes": 0,
	"disabled_shadow_lights": 0,
	"hidden_debug_meshes": 0,
	"missing_roots": [],
}


func setup(owner_ref: Node, camera_ref: Camera3D, _headless_runtime: bool) -> void:
	owner_node = owner_ref
	city_camera = camera_ref
	_config = _load_config()
	_summary = {
		"enabled": bool(_config.get("enabled", false)),
		"configured_meshes": 0,
		"configured_lights": 0,
		"disabled_shadow_meshes": 0,
		"disabled_shadow_lights": 0,
		"hidden_debug_meshes": 0,
		"missing_roots": [],
	}
	if not bool(_config.get("enabled", false)):
		return

	_hide_debug_meshes(_get_hide_debug_names())
	_apply_static_ranges()
	_apply_light_lod()
	_bind_dynamic_updates()


func get_debug_summary() -> Dictionary:
	return _summary.duplicate(true)


func _load_config() -> Dictionary:
	if not FileAccess.file_exists(CONFIG_PATH):
		push_warning("Visual LOD config missing: %s" % CONFIG_PATH)
		return {}
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_warning("Cannot open visual LOD config: %s" % CONFIG_PATH)
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Visual LOD config is invalid JSON object: %s" % CONFIG_PATH)
		return {}
	return parsed as Dictionary


func _get_hide_debug_names() -> Dictionary:
	var names: Dictionary = {}
	var configured_names: Array = _config.get("hide_debug_mesh_names", [])
	for raw_name in configured_names:
		var mesh_name := str(raw_name)
		if mesh_name.is_empty():
			continue
		names[mesh_name] = true
	return names


func _hide_debug_meshes(names: Dictionary) -> void:
	if owner_node == null or names.is_empty():
		return
	_hide_debug_meshes_in_subtree(owner_node, names)


func _hide_debug_meshes_in_subtree(root: Node, names: Dictionary) -> void:
	for node in _collect_descendants_including_root(root):
		if not (node is MeshInstance3D):
			continue
		if not names.has(node.name):
			continue
		if node.has_meta(META_DEBUG_HIDDEN):
			continue
		var mesh_instance := node as MeshInstance3D
		mesh_instance.visible = false
		mesh_instance.set_meta(META_DEBUG_HIDDEN, true)
		_summary["hidden_debug_meshes"] = int(_summary.get("hidden_debug_meshes", 0)) + 1


func _apply_static_ranges() -> void:
	var ranges: Array = _config.get("static_ranges", [])
	for raw_entry in ranges:
		if typeof(raw_entry) != TYPE_DICTIONARY:
			continue
		var entry := raw_entry as Dictionary
		var root_path := str(entry.get("path", ""))
		if root_path.is_empty():
			continue
		var root := _find_node(root_path)
		if root == null:
			_track_missing_root(root_path)
			continue
		_apply_static_range_to_root(root, entry)


func _apply_static_range_to_root(root: Node, entry: Dictionary) -> void:
	var visibility_end := maxf(0.0, float(entry.get("visibility_end", 0.0)))
	var fade_margin := maxf(0.0, float(entry.get("fade_margin", 0.0)))
	var cast_shadows := bool(entry.get("cast_shadows", true))
	for node in _collect_descendants_including_root(root):
		if not (node is GeometryInstance3D):
			continue
		if node.has_meta(META_GEOMETRY_CONFIGURED):
			continue
		var geometry := node as GeometryInstance3D
		if visibility_end > 0.0:
			geometry.visibility_range_end = visibility_end
			geometry.visibility_range_end_margin = fade_margin
			geometry.visibility_range_fade_mode = (
				GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
				if fade_margin > 0.0
				else GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			)
		if not cast_shadows and geometry.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_summary["disabled_shadow_meshes"] = int(_summary.get("disabled_shadow_meshes", 0)) + 1
		geometry.set_meta(META_GEOMETRY_CONFIGURED, true)
		_summary["configured_meshes"] = int(_summary.get("configured_meshes", 0)) + 1


func _apply_light_lod() -> void:
	var light_lod: Dictionary = _config.get("light_lod", {})
	if not bool(light_lod.get("enabled", false)):
		return
	var fade_begin := maxf(0.0, float(light_lod.get("distance_fade_begin", 0.0)))
	var fade_length := maxf(0.0, float(light_lod.get("distance_fade_length", 0.0)))
	var shadow_enabled := bool(light_lod.get("shadow_enabled", true))
	var root_paths: Array = light_lod.get("root_paths", [])
	for raw_path in root_paths:
		var root_path := str(raw_path)
		if root_path.is_empty():
			continue
		var root := _find_node(root_path)
		if root == null:
			_track_missing_root(root_path)
			continue
		_apply_light_lod_to_root(root, fade_begin, fade_length, shadow_enabled)


func _apply_light_lod_to_root(root: Node, fade_begin: float, fade_length: float, shadow_enabled: bool) -> void:
	for node in _collect_descendants_including_root(root):
		if not (node is Light3D):
			continue
		if node.has_meta(META_LIGHT_CONFIGURED):
			continue
		var light := node as Light3D
		if fade_begin > 0.0 and fade_length > 0.0:
			light.distance_fade_enabled = true
			light.distance_fade_begin = fade_begin
			light.distance_fade_length = fade_length
			light.distance_fade_shadow = maxf(0.0, fade_begin - 8.0)
		if light.shadow_enabled != shadow_enabled:
			light.shadow_enabled = shadow_enabled
			if not shadow_enabled:
				_summary["disabled_shadow_lights"] = int(_summary.get("disabled_shadow_lights", 0)) + 1
		light.set_meta(META_LIGHT_CONFIGURED, true)
		_summary["configured_lights"] = int(_summary.get("configured_lights", 0)) + 1


func _bind_dynamic_updates() -> void:
	if owner_node == null:
		return
	var tree := owner_node.get_tree()
	if tree == null:
		return
	var callback := Callable(self, "_on_tree_node_added")
	if not tree.node_added.is_connected(callback):
		tree.node_added.connect(callback)


func _on_tree_node_added(node: Node) -> void:
	if node == null or not bool(_config.get("enabled", false)):
		return
	_hide_debug_meshes_in_subtree(node, _get_hide_debug_names())
	_apply_static_ranges_to_dynamic_root(node)
	_apply_light_lod_to_dynamic_root(node)


func _apply_static_ranges_to_dynamic_root(node: Node) -> void:
	var ranges: Array = _config.get("static_ranges", [])
	for raw_entry in ranges:
		if typeof(raw_entry) != TYPE_DICTIONARY:
			continue
		var entry := raw_entry as Dictionary
		var root_path := str(entry.get("path", ""))
		if root_path.is_empty():
			continue
		var configured_root := _find_node(root_path)
		if configured_root != null and _is_same_tree_branch(configured_root, node):
			_apply_static_range_to_root(node, entry)


func _apply_light_lod_to_dynamic_root(node: Node) -> void:
	var light_lod: Dictionary = _config.get("light_lod", {})
	if not bool(light_lod.get("enabled", false)):
		return
	var fade_begin := maxf(0.0, float(light_lod.get("distance_fade_begin", 0.0)))
	var fade_length := maxf(0.0, float(light_lod.get("distance_fade_length", 0.0)))
	var shadow_enabled := bool(light_lod.get("shadow_enabled", true))
	var root_paths: Array = light_lod.get("root_paths", [])
	for raw_path in root_paths:
		var root_path := str(raw_path)
		if root_path.is_empty():
			continue
		var configured_root := _find_node(root_path)
		if configured_root != null and _is_same_tree_branch(configured_root, node):
			_apply_light_lod_to_root(node, fade_begin, fade_length, shadow_enabled)


func _find_node(path: String) -> Node:
	if owner_node == null:
		return null
	if owner_node.has_node(NodePath(path)):
		return owner_node.get_node(NodePath(path))
	var tree := owner_node.get_tree()
	if tree != null and tree.root != null and tree.root.has_node(NodePath(path)):
		return tree.root.get_node(NodePath(path))
	return null


func _track_missing_root(path: String) -> void:
	var missing: Array = _summary.get("missing_roots", [])
	if not missing.has(path):
		missing.append(path)
	_summary["missing_roots"] = missing


func _is_same_tree_branch(root: Node, node: Node) -> bool:
	var current := node
	while current != null:
		if current == root:
			return true
		current = current.get_parent()
	return false


func _collect_descendants(root: Node) -> Array[Node]:
	var result: Array[Node] = []
	for child in root.get_children():
		if child is Node:
			result.append(child)
			result.append_array(_collect_descendants(child))
	return result


func _collect_descendants_including_root(root: Node) -> Array[Node]:
	var result: Array[Node] = [root]
	result.append_array(_collect_descendants(root))
	return result
