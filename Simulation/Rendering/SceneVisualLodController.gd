extends RefCounted
class_name SceneVisualLodController

const CONFIG_PATH := "res://config/visual_lod.json"
const META_DEBUG_HIDDEN := "city_visual_lod_debug_hidden"
const META_GEOMETRY_CONFIGURED := "city_visual_lod_geometry_configured"
const META_LIGHT_CONFIGURED := "city_visual_lod_light_configured"

var owner_node: Node = null
var city_camera: Camera3D = null

var _config: Dictionary = {}
var _managed_lights: Array[Light3D] = []
var _light_pool_update_left: float = 0.0
var _summary: Dictionary = {
	"enabled": false,
	"configured_meshes": 0,
	"configured_lights": 0,
	"disabled_shadow_meshes": 0,
	"disabled_shadow_lights": 0,
	"hidden_debug_meshes": 0,
	"light_pool_enabled": false,
	"light_pool_budget": 0,
	"light_pool_active": 0,
	"light_pool_managed": 0,
	"light_pool_camera_valid": false,
	"missing_roots": [],
}


func setup(owner_ref: Node, camera_ref: Camera3D, _headless_runtime: bool) -> void:
	owner_node = owner_ref
	city_camera = camera_ref
	_config = _load_config()
	_managed_lights.clear()
	_light_pool_update_left = 0.0
	_summary = {
		"enabled": bool(_config.get("enabled", false)),
		"configured_meshes": 0,
		"configured_lights": 0,
		"disabled_shadow_meshes": 0,
		"disabled_shadow_lights": 0,
		"hidden_debug_meshes": 0,
		"light_pool_enabled": _is_light_pool_enabled(),
		"light_pool_budget": _get_light_pool_budget(),
		"light_pool_active": 0,
		"light_pool_managed": 0,
		"light_pool_camera_valid": false,
		"missing_roots": [],
	}
	if not bool(_config.get("enabled", false)):
		return

	_hide_debug_meshes(_get_hide_debug_names())
	_apply_static_ranges()
	_apply_light_lod()
	_bind_dynamic_updates()
	_refresh_light_pool()


func update(delta: float, camera_ref: Camera3D = null) -> void:
	if camera_ref != null and is_instance_valid(camera_ref):
		city_camera = camera_ref
	if not bool(_config.get("enabled", false)) or not _is_light_pool_enabled():
		return
	_light_pool_update_left -= delta
	if _light_pool_update_left > 0.0:
		return
	_light_pool_update_left = maxf(0.05, _get_light_pool_update_interval())
	_refresh_light_pool()


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
		_register_managed_light(light)
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
	_light_pool_update_left = 0.0


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


func _register_managed_light(light: Light3D) -> void:
	if light == null or not is_instance_valid(light):
		return
	if _managed_lights.has(light):
		return
	_managed_lights.append(light)
	_summary["light_pool_managed"] = _managed_lights.size()


func _refresh_light_pool() -> void:
	_prune_invalid_lights()
	_summary["light_pool_enabled"] = _is_light_pool_enabled()
	_summary["light_pool_budget"] = _get_light_pool_budget()
	_summary["light_pool_managed"] = _managed_lights.size()
	if not _is_light_pool_enabled():
		_set_all_managed_lights_visible(true)
		_summary["light_pool_active"] = _managed_lights.size()
		_summary["light_pool_camera_valid"] = false
		return

	var budget := _get_light_pool_budget()
	if budget <= 0:
		_set_all_managed_lights_visible(false)
		_summary["light_pool_active"] = 0
		_summary["light_pool_camera_valid"] = false
		return

	if city_camera == null or not is_instance_valid(city_camera):
		_set_all_managed_lights_visible(true)
		_summary["light_pool_active"] = _managed_lights.size()
		_summary["light_pool_camera_valid"] = false
		return

	var max_distance := _get_light_pool_max_distance()
	var max_distance_sq := max_distance * max_distance
	var camera_position := city_camera.global_position
	var candidates: Array[Dictionary] = []
	for light in _managed_lights:
		if light == null or not is_instance_valid(light):
			continue
		var distance_sq := camera_position.distance_squared_to(light.global_position)
		if max_distance > 0.0 and distance_sq > max_distance_sq:
			light.visible = false
			continue
		candidates.append({
			"light": light,
			"distance_sq": distance_sq,
		})
	candidates.sort_custom(Callable(self, "_compare_light_candidates"))

	var active_count := 0
	for index in range(candidates.size()):
		var entry := candidates[index]
		var light := entry.get("light") as Light3D
		if light == null or not is_instance_valid(light):
			continue
		var should_enable := index < budget
		light.visible = should_enable
		if should_enable:
			active_count += 1
	_summary["light_pool_active"] = active_count
	_summary["light_pool_camera_valid"] = true


func _compare_light_candidates(a: Dictionary, b: Dictionary) -> bool:
	return float(a.get("distance_sq", 0.0)) < float(b.get("distance_sq", 0.0))


func _set_all_managed_lights_visible(visible: bool) -> void:
	for light in _managed_lights:
		if light != null and is_instance_valid(light):
			light.visible = visible


func _prune_invalid_lights() -> void:
	var valid_lights: Array[Light3D] = []
	for light in _managed_lights:
		if light != null and is_instance_valid(light):
			valid_lights.append(light)
	_managed_lights = valid_lights


func _get_light_pool_config() -> Dictionary:
	var light_lod: Dictionary = _config.get("light_lod", {})
	var pool_config: Dictionary = light_lod.get("pool", {})
	return pool_config


func _is_light_pool_enabled() -> bool:
	var light_lod: Dictionary = _config.get("light_lod", {})
	if not bool(light_lod.get("enabled", false)):
		return false
	var pool_config := _get_light_pool_config()
	return bool(pool_config.get("enabled", false))


func _get_light_pool_budget() -> int:
	var pool_config := _get_light_pool_config()
	return maxi(0, int(pool_config.get("max_active_lights", 0)))


func _get_light_pool_max_distance() -> float:
	var pool_config := _get_light_pool_config()
	return maxf(0.0, float(pool_config.get("max_distance", 0.0)))


func _get_light_pool_update_interval() -> float:
	var pool_config := _get_light_pool_config()
	return maxf(0.05, float(pool_config.get("update_interval_sec", 0.25)))


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
