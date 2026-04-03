extends RefCounted
class_name RuntimeDebugLogger

const SimLogger = preload("res://Simulation/Logging/SimLogger.gd")

var owner_node: Node = null
var world: World = null

var _enable_all_citizen_trace: bool = false
var _enable_map_snapshot_log: bool = false
var _selected_citizen_trace_left: float = 0.0
var _all_citizen_trace_left: float = 0.0
var _selected_trace_interval_sec: float = 1.0
var _all_trace_interval_sec: float = 0.5

func setup(
	owner_ref: Node,
	world_ref: World,
	enable_all_trace: bool,
	enable_map_snapshot: bool,
	selected_trace_interval_sec: float,
	all_trace_interval_sec: float
) -> void:
	owner_node = owner_ref
	world = world_ref
	_enable_all_citizen_trace = enable_all_trace
	_enable_map_snapshot_log = enable_map_snapshot
	_selected_trace_interval_sec = maxf(selected_trace_interval_sec, 0.05)
	_all_trace_interval_sec = maxf(all_trace_interval_sec, 0.05)

func update(delta: float, selected_citizen: Citizen) -> void:
	_update_selected_citizen_trace(delta, selected_citizen)
	_update_all_citizen_trace(delta)

func reset_selected_citizen_trace() -> void:
	_selected_citizen_trace_left = 0.0

func log_selected_citizen_trace(event_name: String, selected_citizen: Citizen) -> void:
	if selected_citizen == null or not is_instance_valid(selected_citizen):
		return

	SimLogger.log("[CitizenTrace %s] %s | %s" % [
		event_name,
		_get_time_label(),
		selected_citizen.get_trace_debug_summary()
	])

func log_initial_snapshot() -> void:
	if _enable_map_snapshot_log:
		_log_map_snapshot()
	if _enable_all_citizen_trace:
		_all_citizen_trace_left = 0.0
		_log_all_citizen_traces("spawn")

func _update_selected_citizen_trace(delta: float, selected_citizen: Citizen) -> void:
	if selected_citizen == null or not is_instance_valid(selected_citizen):
		_selected_citizen_trace_left = 0.0
		return

	_selected_citizen_trace_left -= delta
	if _selected_citizen_trace_left > 0.0:
		return

	_selected_citizen_trace_left = _selected_trace_interval_sec
	log_selected_citizen_trace("tick", selected_citizen)

func _update_all_citizen_trace(delta: float) -> void:
	if not _enable_all_citizen_trace:
		return
	_all_citizen_trace_left -= delta
	if _all_citizen_trace_left > 0.0:
		return

	_all_citizen_trace_left = _all_trace_interval_sec
	_log_all_citizen_traces("tick")

func _log_all_citizen_traces(event_name: String) -> void:
	if world == null:
		return

	var time_label := _get_time_label()
	for citizen in world.citizens:
		if citizen == null or not is_instance_valid(citizen):
			continue
		SimLogger.log("[CitizenTraceAll %s] %s | %s" % [
			event_name,
			time_label,
			citizen.get_trace_debug_summary()
		])

func _log_map_snapshot() -> void:
	if world == null:
		return

	var road_nodes := _collect_debug_roads()
	var crosswalk_nodes := _collect_debug_crosswalks()
	var light_nodes := _collect_debug_lights(owner_node)

	SimLogger.log("[MapDump summary] buildings=%d citizens=%d roads=%d crosswalks=%d lights=%d" % [
		world.buildings.size(),
		world.citizens.size(),
		road_nodes.size(),
		crosswalk_nodes.size(),
		light_nodes.size()
	])

	for building in world.buildings:
		if building == null:
			continue
		SimLogger.log("[MapDump building] name=%s pos=%s %s" % [
			building.get_display_name(),
			_fmt_vec3(building.global_position),
			building.get_navigation_debug_summary(world) if building.has_method("get_navigation_debug_summary") else ""
		])

	for citizen in world.citizens:
		if citizen == null:
			continue
		SimLogger.log("[MapDump citizen] name=%s pos=%s home=%s location=%s inside=%s action=%s" % [
			citizen.citizen_name,
			_fmt_vec3(citizen.global_position),
			citizen.home.get_display_name() if citizen.home != null else "-",
			citizen.current_location.get_display_name() if citizen.current_location != null else "-",
			citizen._inside_building.get_display_name() if citizen._inside_building != null else "-",
			citizen.current_action.label if citizen.current_action != null else "idle"
		])

	for road in road_nodes:
		SimLogger.log("[MapDump road] path=%s pos=%s" % [road.get_path(), _fmt_vec3(road.global_position)])

	for crosswalk in crosswalk_nodes:
		SimLogger.log("[MapDump crosswalk] path=%s pos=%s" % [crosswalk.get_path(), _fmt_vec3(crosswalk.global_position)])

	for light in light_nodes:
		SimLogger.log("[MapDump light] type=%s path=%s pos=%s" % [
			light.get_class(),
			light.get_path(),
			_fmt_vec3(light.global_position)
		])

func _collect_debug_roads() -> Array[Node3D]:
	var out: Array[Node3D] = []
	if owner_node == null:
		return out
	_append_transport_segments_for_log(owner_node.get_node_or_null("World/City/only_transport"), out)
	_append_transport_segments_for_log(owner_node.get_node_or_null("ImportedCity/only_transport"), out)
	var generated := owner_node.get_node_or_null("RoadNetwork")
	if generated != null:
		for child in generated.get_children():
			if child is Node3D:
				out.append(child as Node3D)
	return out

func _append_transport_segments_for_log(root: Node, out: Array[Node3D]) -> void:
	if root == null:
		return
	for category in root.get_children():
		if category is not Node3D:
			continue
		for segment in (category as Node3D).get_children():
			if segment is Node3D:
				out.append(segment as Node3D)

func _collect_debug_crosswalks() -> Array[Node3D]:
	var out: Array[Node3D] = []
	if owner_node == null:
		return out
	_append_node3d_children_for_log(owner_node.get_node_or_null("World/City/only_people_nav/only_people/Road_straight_crossing"), out)
	_append_node3d_children_for_log(owner_node.get_node_or_null("ImportedCity/only_people_nav/only_people/Road_straight_crossing"), out)
	return out

func _append_node3d_children_for_log(root: Node, out: Array[Node3D]) -> void:
	if root == null:
		return
	for child in root.get_children():
		if child is Node3D:
			out.append(child as Node3D)

func _collect_debug_lights(root: Node) -> Array[Light3D]:
	var out: Array[Light3D] = []
	_collect_debug_lights_recursive(root, out)
	return out

func _collect_debug_lights_recursive(node: Node, out: Array[Light3D]) -> void:
	if node == null:
		return
	if node is Light3D:
		out.append(node as Light3D)
	for child in node.get_children():
		if child is Node:
			_collect_debug_lights_recursive(child as Node, out)

func _fmt_vec3(value: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [value.x, value.y, value.z]

func _get_time_label() -> String:
	if world != null and world.time != null:
		return "day=%d time=%s" % [world.time.day, world.time.get_time_string()]
	return "day=? time=?"
