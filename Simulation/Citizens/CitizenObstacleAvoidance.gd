extends RefCounted
class_name CitizenObstacleAvoidance

const SOFT_OBSTACLE_GROUP := "pedestrian_soft_obstacle"
const SOFT_OBSTACLE_KEYWORDS := [
	"trafficlight",
	"traffic_light",
	"streetlight",
	"street_light",
]

var _clearance_shape := SphereShape3D.new()

func is_ray_blocked(citizen: Citizen, ray: RayCast3D) -> bool:
	if ray == null or not ray.enabled or not ray.is_colliding():
		return false
	return _is_hard_blocking_kind(_classify_collider(citizen, ray.get_collider()))

func ray_detects_low_obstacle(citizen: Citizen, ray: RayCast3D) -> bool:
	if ray == null or not ray.enabled or not ray.is_colliding():
		return false
	if not _is_hard_blocking_kind(_classify_collider(citizen, ray.get_collider())):
		return false
	var hit_normal: Vector3 = ray.get_collision_normal()
	return hit_normal.dot(Vector3.UP) < 0.55

func is_blocking_hotspot_ray(citizen: Citizen, ray: RayCast3D, require_low_obstacle: bool = false) -> bool:
	if ray == null or not ray.enabled or not ray.is_colliding():
		return false
	if not _is_hard_blocking_kind(_classify_collider(citizen, ray.get_collider())):
		return false
	if require_low_obstacle and not ray_detects_low_obstacle(citizen, ray):
		return false
	return true

func describe_ray_hit(citizen: Citizen, ray: RayCast3D) -> String:
	if ray == null or not ray.enabled:
		return "off"
	if not ray.is_colliding():
		return "clear"

	var collider: Variant = ray.get_collider()
	if not _is_hard_blocking_kind(_classify_collider(citizen, collider)):
		return "clear"

	var collider_name: String = citizen._trace_collider_label(collider)
	var hit_pos: Vector3 = ray.get_collision_point()
	var distance: float = ray.global_position.distance_to(hit_pos)
	return "%s @ %s d=%.2f" % [collider_name, citizen._trace_fmt_vec3(hit_pos), distance]

func refine_move_direction(citizen: Citizen, current_dir: Vector3, desired_dir: Vector3) -> Vector3:
	var planar_current: Vector3 = _normalize_planar(current_dir)
	if citizen == null or planar_current == Vector3.ZERO:
		return planar_current
	if not citizen.local_navigation_raycast_checks_enabled:
		return planar_current
	if not citizen.is_inside_tree() or citizen.get_world_3d() == null:
		return planar_current

	var current_context_crosswalk: bool = citizen._is_crosswalk_route_context()
	var current_score: float = _score_direction(citizen, planar_current, current_context_crosswalk)
	if current_score < 1000.0:
		return planar_current

	var candidates: Array[Vector3] = []
	_append_candidate(candidates, planar_current)
	_append_candidate(candidates, desired_dir)
	_append_candidate(candidates, citizen._ray_move_direction(citizen._obstacle_ray_left))
	_append_candidate(candidates, citizen._ray_move_direction(citizen._obstacle_ray_right))
	_append_candidate(candidates, citizen._rotate_planar_direction(desired_dir, 18.0))
	_append_candidate(candidates, citizen._rotate_planar_direction(desired_dir, -18.0))
	_append_candidate(candidates, citizen._rotate_planar_direction(desired_dir, 32.0))
	_append_candidate(candidates, citizen._rotate_planar_direction(desired_dir, -32.0))
	_append_candidate(candidates, citizen._blend_move_direction(desired_dir, citizen._ray_move_direction(citizen._obstacle_ray_left), 0.45))
	_append_candidate(candidates, citizen._blend_move_direction(desired_dir, citizen._ray_move_direction(citizen._obstacle_ray_right), 0.45))

	var best_dir: Vector3 = planar_current
	var best_score: float = current_score
	for candidate in candidates:
		var normalized_candidate: Vector3 = _normalize_planar(candidate)
		if normalized_candidate == Vector3.ZERO:
			continue
		if not current_context_crosswalk and not citizen._is_move_surface_allowed(normalized_candidate, false):
			continue
		var score: float = _score_direction(citizen, normalized_candidate, current_context_crosswalk)
		if score < best_score:
			best_score = score
			best_dir = normalized_candidate

	return best_dir if best_score + 0.05 < current_score else planar_current

func score_move_direction(citizen: Citizen, direction: Vector3, crosswalk_context: bool = false) -> float:
	var normalized_direction: Vector3 = _normalize_planar(direction)
	if citizen == null or normalized_direction == Vector3.ZERO:
		return INF
	return _score_direction(citizen, normalized_direction, crosswalk_context)

func _score_direction(citizen: Citizen, direction: Vector3, crosswalk_context: bool) -> float:
	var hits: Array = _collect_clearance_hits(citizen, direction)
	var hard_blockers := 0
	var soft_blockers := 0
	for hit in hits:
		var hit_data: Dictionary = hit as Dictionary
		var kind := str(_classify_collider(citizen, hit_data.get("collider", null)).get("kind", "solid"))
		match kind:
			"solid":
				hard_blockers += 1
			"soft_obstacle":
				soft_blockers += 1

	var projected: Vector3 = citizen.global_position + direction * maxf(citizen.obstacle_clearance_probe_distance, 0.1)
	projected.y = citizen._travel_target.y
	var target_score: float = projected.distance_to(citizen._travel_target)
	if crosswalk_context:
		target_score *= 0.85
	return target_score + float(hard_blockers) * 1000.0 + float(soft_blockers) * 8.0

func _collect_clearance_hits(citizen: Citizen, direction: Vector3) -> Array:
	var normalized_direction: Vector3 = _normalize_planar(direction)
	if citizen == null or normalized_direction == Vector3.ZERO:
		return []
	if citizen.get_world_3d() == null:
		return []

	_clearance_shape.radius = maxf(citizen.obstacle_clearance_radius, 0.04)
	var sample_center: Vector3 = citizen.global_position + normalized_direction * maxf(citizen.obstacle_clearance_probe_distance, 0.1)
	sample_center.y = citizen.global_position.y + maxf(citizen.obstacle_clearance_height, citizen.obstacle_sensor_height)

	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _clearance_shape
	query.transform = Transform3D(Basis.IDENTITY, sample_center)
	query.collision_mask = _get_clearance_collision_mask(citizen)
	query.collide_with_areas = false
	query.exclude = [citizen.get_rid()]

	return citizen.get_world_3d().direct_space_state.intersect_shape(query, 8)

func _classify_collider(citizen: Citizen, collider: Variant) -> Dictionary:
	if collider == null or collider == citizen:
		return {"kind": "clear"}
	if citizen != null and citizen._is_citizen_collider(collider):
		return {"kind": "citizen"}

	if collider is Node:
		var node := collider as Node
		if citizen != null and citizen._is_entrance_trigger_node(node):
			return {"kind": "entrance_trigger", "node": node}
		if _is_target_building_node(citizen, node):
			return {"kind": "target_building", "node": node}
		if citizen != null and citizen._is_walkable_step_surface(collider):
			return {"kind": "walkable_step", "node": node}
		if _is_soft_obstacle_node(node):
			return {"kind": "soft_obstacle", "node": node}
		return {"kind": "solid", "node": node}

	return {"kind": "solid"}

func _get_clearance_collision_mask(citizen: Citizen) -> int:
	if citizen == null:
		return 0
	if citizen._obstacle_ray_forward != null and citizen._obstacle_ray_forward.collision_mask != 0:
		return citizen._obstacle_ray_forward.collision_mask
	return citizen.collision_mask

func _is_target_building_node(citizen: Citizen, node: Node) -> bool:
	if citizen == null or node == null or citizen._travel_target_building == null:
		return false
	if citizen._is_target_entrance_trigger(node):
		return true
	if citizen._travel_target_building.has_method("owns_navigation_node"):
		return citizen._travel_target_building.owns_navigation_node(node)
	return false

func _is_soft_obstacle_node(node: Node) -> bool:
	var current := node
	while current != null:
		if current.is_in_group(SOFT_OBSTACLE_GROUP):
			return true
		var current_name := current.name.to_lower()
		if _contains_soft_obstacle_keyword(current_name):
			return true
		if current.is_inside_tree():
			var current_path := str(current.get_path()).to_lower()
			if _contains_soft_obstacle_keyword(current_path):
				return true
		current = current.get_parent()
	return false

func _contains_soft_obstacle_keyword(label: String) -> bool:
	for keyword in SOFT_OBSTACLE_KEYWORDS:
		if label.contains(keyword):
			return true
	return false

func _is_hard_blocking_kind(info: Dictionary) -> bool:
	return str(info.get("kind", "solid")) == "solid"

func _append_candidate(out: Array[Vector3], candidate: Vector3) -> void:
	var normalized_candidate := _normalize_planar(candidate)
	if normalized_candidate == Vector3.ZERO:
		return
	for existing in out:
		if (existing as Vector3).distance_to(normalized_candidate) <= 0.01:
			return
	out.append(normalized_candidate)

func _normalize_planar(direction: Vector3) -> Vector3:
	var planar := direction
	planar.y = 0.0
	if planar.length_squared() <= 0.0001:
		return Vector3.ZERO
	return planar.normalized()
