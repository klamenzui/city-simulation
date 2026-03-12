extends RefCounted
class_name RoadGraph

const LINK_MAX_DISTANCE := 12.5
const DEDUPE_STEP := 0.5

var nodes: Array[Vector3] = []
var neighbors: Dictionary = {}
var _is_ready: bool = false

func rebuild_from_scene(root: Node3D) -> void:
	nodes.clear()
	neighbors.clear()
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
	neighbors.clear()
	for i in range(nodes.size()):
		neighbors[i] = []

	for i in range(nodes.size()):
		for j in range(i + 1, nodes.size()):
			var d: float = _xz_distance(nodes[i], nodes[j])
			if d < 1.0 or d > LINK_MAX_DISTANCE:
				continue
			(neighbors[i] as Array).append(j)
			(neighbors[j] as Array).append(i)

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

func _grid_key(pos: Vector3) -> String:
	var x: float = round(pos.x / DEDUPE_STEP) * DEDUPE_STEP
	var z: float = round(pos.z / DEDUPE_STEP) * DEDUPE_STEP
	return "%0.2f|%0.2f" % [x, z]

func _xz_distance(a: Vector3, b: Vector3) -> float:
	var dx: float = a.x - b.x
	var dz: float = a.z - b.z
	return sqrt(dx * dx + dz * dz)
