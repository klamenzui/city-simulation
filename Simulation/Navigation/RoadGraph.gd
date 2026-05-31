extends RefCounted
class_name RoadGraph

const LINK_MAX_DISTANCE := 12.5
const LINK_AXIS_TOLERANCE := 0.75
const DEDUPE_STEP := 0.5
const ROAD_SUPPORT_SAMPLE_STEP := 1.0
const ROAD_SUPPORT_RADIUS := 2.1

var nodes: Array[Vector3] = []
var neighbors: Dictionary = {}
var _is_ready: bool = false
var _road_support_keys: Dictionary = {}

func rebuild_from_scene(root: Node3D) -> void:
	nodes.clear()
	neighbors.clear()
	_road_support_keys.clear()
	_is_ready = false

	if root == null:
		return

	var road_nodes = _collect_road_nodes(root)
	if road_nodes.is_empty():
		return

	var dedupe: Dictionary = {}
	for node in road_nodes:
		if node == null:
			continue
		var pos: Vector3 = node.global_position
		var key: String = _grid_key(pos)
		if dedupe.has(key):
			continue
		dedupe[key] = Vector3(pos.x, 0.0, pos.z)

	for value in dedupe.values():
		nodes.append(value)

	if nodes.size() < 2:
		return

	_build_links()
	_is_ready = neighbors.size() > 0

func has_graph() -> bool:
	return _is_ready and nodes.size() > 1 and neighbors.size() > 0

func find_path_points(start_pos: Vector3, end_pos: Vector3) -> PackedVector3Array:
	var route = PackedVector3Array()
	route.append(start_pos)

	if not has_graph():
		route.append(end_pos)
		return route

	var start_idx: int = get_nearest_node_index(start_pos)
	var end_idx: int = get_nearest_node_index(end_pos)
	if start_idx < 0 or end_idx < 0:
		route.append(end_pos)
		return route

	var index_path: Array = _a_star(start_idx, end_idx)
	if index_path.is_empty():
		route.append(end_pos)
		return route

	for idx in index_path:
		var p: Vector3 = nodes[int(idx)]
		route.append(Vector3(p.x, start_pos.y, p.z))

	route.append(end_pos)
	return _remove_close_duplicates(route)

func find_vehicle_path_points(start_pos: Vector3, end_pos: Vector3, lane_offset: float = 0.45) -> PackedVector3Array:
	var route := PackedVector3Array()
	if not has_graph():
		return route

	var start_idx: int = get_nearest_node_index(start_pos)
	var end_idx: int = get_nearest_node_index(end_pos)
	if start_idx < 0 or end_idx < 0:
		return route

	var index_path: Array = _a_star(start_idx, end_idx)
	if index_path.is_empty():
		return route

	var center_path := PackedVector3Array()
	for idx in index_path:
		var p: Vector3 = nodes[int(idx)]
		center_path.append(Vector3(p.x, start_pos.y, p.z))
	return _center_path_to_right_lane(center_path, lane_offset)

func get_vehicle_access_point(pos: Vector3, lane_offset: float = 0.45) -> Vector3:
	if not has_graph():
		return pos
	var idx := get_nearest_node_index(pos)
	if idx < 0:
		return pos
	var center_path := PackedVector3Array([Vector3(nodes[idx].x, pos.y, nodes[idx].z)])
	var neighbor_idx := _get_best_neighbor_for_access(idx, pos)
	if neighbor_idx >= 0:
		center_path.append(Vector3(nodes[neighbor_idx].x, pos.y, nodes[neighbor_idx].z))
	var lane_path := _center_path_to_right_lane(center_path, lane_offset)
	if lane_path.is_empty():
		return center_path[0]
	return lane_path[0]

func get_nearest_node_index(pos: Vector3) -> int:
	if nodes.is_empty():
		return -1

	var best_idx := -1
	var best_dist := INF
	for i in range(nodes.size()):
		var d: float = _xz_distance(nodes[i], pos)
		if d < best_dist:
			best_dist = d
			best_idx = i
	return best_idx

func _collect_road_nodes(root: Node3D) -> Array[Node3D]:
	var out: Array[Node3D] = []

	# Main scene city roads under World/City/only_transport
	var world_city := root.get_node_or_null("World/City") as Node3D
	if world_city != null:
		var city_transport := world_city.get_node_or_null("only_transport") as Node3D
		if city_transport != null:
			_append_transport_segments(city_transport, out)

	# Imported streets scene fallback (legacy path).
	var imported := root.get_node_or_null("ImportedCity") as Node3D
	if imported != null:
		var transport := imported.get_node_or_null("only_transport") as Node3D
		if transport != null:
			_append_transport_segments(transport, out)

	# Fallback for generated simple roads.
	var generated := root.get_node_or_null("RoadNetwork") as Node3D
	if generated != null:
		for child in generated.get_children():
			if child is Node3D:
				out.append(child as Node3D)

	return out

func _append_transport_segments(transport_root: Node3D, out: Array[Node3D]) -> void:
	for category in transport_root.get_children():
		if category is not Node3D:
			continue
		for segment in (category as Node3D).get_children():
			if segment is Node3D:
				out.append(segment as Node3D)

func _build_links() -> void:
	_rebuild_road_support_keys()
	neighbors.clear()
	for i in range(nodes.size()):
		neighbors[i] = []

	for i in range(nodes.size()):
		for j in range(i + 1, nodes.size()):
			var d: float = _xz_distance(nodes[i], nodes[j])
			if d < 1.0 or d > LINK_MAX_DISTANCE:
				continue
			if not _is_axis_aligned_road_link(nodes[i], nodes[j]):
				continue
			if not _is_road_supported_link(nodes[i], nodes[j]):
				continue
			(neighbors[i] as Array).append(j)
			(neighbors[j] as Array).append(i)

func _is_axis_aligned_road_link(a: Vector3, b: Vector3) -> bool:
	var dx := absf(a.x - b.x)
	var dz := absf(a.z - b.z)
	return dx <= LINK_AXIS_TOLERANCE or dz <= LINK_AXIS_TOLERANCE

func _is_road_supported_link(a: Vector3, b: Vector3) -> bool:
	var delta := b - a
	delta.y = 0.0
	var distance := delta.length()
	if distance <= 0.001:
		return false
	var sample_distance := ROAD_SUPPORT_SAMPLE_STEP
	while sample_distance < distance - 0.001:
		var sample := a + delta * (sample_distance / distance)
		if not _has_road_node_near(sample):
			return false
		sample_distance += ROAD_SUPPORT_SAMPLE_STEP
	return true

func _rebuild_road_support_keys() -> void:
	_road_support_keys.clear()
	for point in nodes:
		var cell := _support_cell(point)
		_road_support_keys[_support_key(cell.x, cell.y)] = true

func _has_road_node_near(pos: Vector3) -> bool:
	if _road_support_keys.is_empty():
		_rebuild_road_support_keys()
	var cell := _support_cell(pos)
	var radius_cells := int(ceil(ROAD_SUPPORT_RADIUS / DEDUPE_STEP))
	for x in range(cell.x - radius_cells, cell.x + radius_cells + 1):
		for z in range(cell.y - radius_cells, cell.y + radius_cells + 1):
			if not _road_support_keys.has(_support_key(x, z)):
				continue
			var candidate := Vector3(float(x) * DEDUPE_STEP, 0.0, float(z) * DEDUPE_STEP)
			if _xz_distance(candidate, pos) <= ROAD_SUPPORT_RADIUS:
				return true
	return false

func _get_best_neighbor_for_access(idx: int, reference_pos: Vector3) -> int:
	var candidates := neighbors.get(idx, []) as Array
	if candidates.is_empty():
		return -1
	var best_idx := int(candidates[0])
	var best_score := INF
	for candidate in candidates:
		var candidate_idx := int(candidate)
		var score := _xz_distance(nodes[candidate_idx], reference_pos)
		if score < best_score:
			best_score = score
			best_idx = candidate_idx
	return best_idx

func _a_star(start_idx: int, end_idx: int) -> Array:
	if start_idx == end_idx:
		return [start_idx]

	var open: Array = [start_idx]
	var came_from: Dictionary = {}
	var g_score: Dictionary = {start_idx: 0.0}
	var f_score: Dictionary = {start_idx: _heuristic(start_idx, end_idx)}

	while not open.is_empty():
		var current = _pop_best(open, f_score)
		if current == end_idx:
			return _reconstruct_path(came_from, current)

		for n in neighbors.get(current, []):
			var neighbor_idx: int = int(n)
			var tentative: float = float(g_score.get(current, INF)) + _heuristic(current, neighbor_idx)
			if tentative >= float(g_score.get(neighbor_idx, INF)):
				continue

			came_from[neighbor_idx] = current
			g_score[neighbor_idx] = tentative
			f_score[neighbor_idx] = tentative + _heuristic(neighbor_idx, end_idx)
			if not open.has(neighbor_idx):
				open.append(neighbor_idx)

	return []

func _pop_best(open: Array, f_score: Dictionary):
	var best_idx := 0
	var best_node = open[0]
	var best_val: float = float(f_score.get(best_node, INF))

	for i in range(1, open.size()):
		var candidate = open[i]
		var candidate_val: float = float(f_score.get(candidate, INF))
		if candidate_val < best_val:
			best_val = candidate_val
			best_node = candidate
			best_idx = i

	open.remove_at(best_idx)
	return best_node

func _reconstruct_path(came_from: Dictionary, current) -> Array:
	var path: Array = [current]
	var node = current
	while came_from.has(node):
		node = came_from[node]
		path.push_front(node)
	return path

func _heuristic(a_idx: int, b_idx: int) -> float:
	return _xz_distance(nodes[a_idx], nodes[b_idx])

func _remove_close_duplicates(path: PackedVector3Array, min_dist: float = 0.15) -> PackedVector3Array:
	if path.is_empty():
		return path

	var out = PackedVector3Array()
	out.append(path[0])
	for i in range(1, path.size()):
		var p: Vector3 = path[i]
		if out[out.size() - 1].distance_to(p) >= min_dist:
			out.append(p)
	return out

func _center_path_to_right_lane(center_path: PackedVector3Array, lane_offset: float) -> PackedVector3Array:
	if center_path.size() < 2:
		return center_path

	var offset := maxf(lane_offset, 0.0)
	var lane_path := PackedVector3Array()
	for i in range(center_path.size()):
		var center := center_path[i]
		var direction := Vector3.ZERO
		if i < center_path.size() - 1:
			direction = center_path[i + 1] - center
		else:
			direction = center - center_path[i - 1]
		direction.y = 0.0
		if direction.length_squared() <= 0.0001:
			lane_path.append(center)
			continue
		direction = direction.normalized()
		var right := Vector3(-direction.z, 0.0, direction.x)
		lane_path.append(center + right * offset)
	return _remove_close_duplicates(lane_path, 0.22)

func _grid_key(pos: Vector3) -> String:
	var x: float = round(pos.x / DEDUPE_STEP) * DEDUPE_STEP
	var z: float = round(pos.z / DEDUPE_STEP) * DEDUPE_STEP
	return "%0.2f|%0.2f" % [x, z]

func _support_cell(pos: Vector3) -> Vector2i:
	return Vector2i(
		int(round(pos.x / DEDUPE_STEP)),
		int(round(pos.z / DEDUPE_STEP))
	)

func _support_key(x: int, z: int) -> String:
	return "%d|%d" % [x, z]

func _xz_distance(a: Vector3, b: Vector3) -> float:
	var dx: float = a.x - b.x
	var dz: float = a.z - b.z
	return sqrt(dx * dx + dz * dz)
