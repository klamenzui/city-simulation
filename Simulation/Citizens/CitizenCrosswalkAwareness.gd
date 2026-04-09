extends RefCounted
class_name CitizenCrosswalkAwareness

const TRAFFIC_LIGHT_GROUP := "traffic_lights"

func get_wait_state(citizen, distance_to_target: float, move_dir: Vector3) -> Dictionary:
	if citizen == null or citizen._world_ref == null:
		return {}
	if distance_to_target > citizen.crosswalk_signal_stop_distance:
		return {}
	if _get_target_kind(citizen) != "crosswalk_entry":
		return {}

	var traffic_light = _find_relevant_signal(citizen, move_dir)
	if traffic_light == null:
		return {}
	if _is_crossing_allowed(traffic_light):
		return {}

	var signal_name: String = str(traffic_light.name)
	if traffic_light.is_inside_tree():
		signal_name = str(traffic_light.get_path())
	return {
		"should_wait": true,
		"reason": "crosswalk_wait_%s" % _get_signal_state_name(traffic_light),
		"signal": signal_name,
	}

func _find_relevant_signal(citizen, move_dir: Vector3) -> Node3D:
	var tree: SceneTree = citizen.get_tree()
	if tree == null:
		return null

	var entry_point: Vector3 = citizen._travel_target
	var best_signal: Node3D = null
	var best_score: float = INF
	var planar_move: Vector3 = _normalize_planar(move_dir)

	for candidate in tree.get_nodes_in_group(TRAFFIC_LIGHT_GROUP):
		if not (candidate is Node3D):
			continue
		var traffic_light: Node3D = candidate as Node3D
		if not is_instance_valid(traffic_light):
			continue

		var to_signal: Vector3 = traffic_light.global_position - entry_point
		to_signal.y = 0.0
		var distance: float = to_signal.length()
		if distance > citizen.crosswalk_signal_detection_radius:
			continue

		var score: float = distance
		if planar_move != Vector3.ZERO and to_signal.length_squared() > 0.0001:
			var alignment: float = planar_move.dot(to_signal.normalized())
			score -= alignment * 0.18
		if score < best_score:
			best_score = score
			best_signal = traffic_light

	return best_signal

func _is_crossing_allowed(traffic_light: Node3D) -> bool:
	if traffic_light == null:
		return true
	if traffic_light.has_method("is_pedestrian_crossing_allowed"):
		return bool(traffic_light.is_pedestrian_crossing_allowed())
	return _get_signal_state_name(traffic_light) == "green"

func _get_signal_state_name(traffic_light: Node3D) -> String:
	if traffic_light == null:
		return "unknown"
	if traffic_light.has_method("get_current_light_name"):
		return str(traffic_light.get_current_light_name())
	if traffic_light.has_method("get_current_light_color"):
		var state := int(traffic_light.get_current_light_color())
		match state:
			0:
				return "green"
			1:
				return "yellow"
			2:
				return "red"
	return "unknown"

func _get_target_kind(citizen) -> String:
	if citizen == null or citizen._world_ref == null:
		return ""
	return str(citizen._world_ref.get_pedestrian_path_point_kind(citizen._travel_target))

func _normalize_planar(direction: Vector3) -> Vector3:
	var planar := direction
	planar.y = 0.0
	if planar.length_squared() <= 0.0001:
		return Vector3.ZERO
	return planar.normalized()
