extends RefCounted
class_name PedestrianGraph

const CELL_STEP := 2.0
const HALF_ROAD_WIDTH := 1.0

const SIDE_DEFS := [
	{
		"id": 0,
		"neighbor": Vector3(-CELL_STEP, 0.0, 0.0),
		"mid": Vector3(-HALF_ROAD_WIDTH, 0.0, 0.0),
		"tangents": [
			Vector3(0.0, 0.0, -CELL_STEP),
			Vector3(0.0, 0.0, CELL_STEP),
		],
		"corners": [
			Vector3(-HALF_ROAD_WIDTH, 0.0, -HALF_ROAD_WIDTH),
			Vector3(-HALF_ROAD_WIDTH, 0.0, HALF_ROAD_WIDTH),
		],
	},
	{
		"id": 1,
		"neighbor": Vector3(CELL_STEP, 0.0, 0.0),
		"mid": Vector3(HALF_ROAD_WIDTH, 0.0, 0.0),
		"tangents": [
			Vector3(0.0, 0.0, -CELL_STEP),
			Vector3(0.0, 0.0, CELL_STEP),
		],
		"corners": [
			Vector3(HALF_ROAD_WIDTH, 0.0, -HALF_ROAD_WIDTH),
			Vector3(HALF_ROAD_WIDTH, 0.0, HALF_ROAD_WIDTH),
		],
	},
	{
		"id": 2,
		"neighbor": Vector3(0.0, 0.0, -CELL_STEP),
		"mid": Vector3(0.0, 0.0, -HALF_ROAD_WIDTH),
		"tangents": [
			Vector3(-CELL_STEP, 0.0, 0.0),
			Vector3(CELL_STEP, 0.0, 0.0),
		],
		"corners": [
			Vector3(-HALF_ROAD_WIDTH, 0.0, -HALF_ROAD_WIDTH),
			Vector3(HALF_ROAD_WIDTH, 0.0, -HALF_ROAD_WIDTH),
		],
	},
	{
		"id": 3,
		"neighbor": Vector3(0.0, 0.0, CELL_STEP),
		"mid": Vector3(0.0, 0.0, HALF_ROAD_WIDTH),
		"tangents": [
			Vector3(-CELL_STEP, 0.0, 0.0),
			Vector3(CELL_STEP, 0.0, 0.0),
		],
		"corners": [
			Vector3(-HALF_ROAD_WIDTH, 0.0, HALF_ROAD_WIDTH),
			Vector3(HALF_ROAD_WIDTH, 0.0, HALF_ROAD_WIDTH),
		],
	},
]

var nodes: Array[Vector3] = []
var neighbors: Dictionary = {}

var _access_node_indices: Array[int] = []
var _node_index_by_key: Dictionary = {}
var _node_meta: Dictionary = {}
var _component_by_node: Dictionary = {}
var _road_cells: Dictionary = {}
var _crosswalk_cells: Dictionary = {}
var _crosswalk_axes: Dictionary = {}
var _boundary_node_by_side: Dictionary = {}
var _boundary_nodes_by_road: Dictionary = {}
var _is_ready: bool = false

func rebuild_from_scene(root: Node3D, _buildings: Array = []) -> void:
	nodes.clear()
	neighbors.clear()
	_access_node_indices.clear()
	_node_index_by_key.clear()
	_node_meta.clear()
	_component_by_node.clear()
	_road_cells.clear()
	_crosswalk_cells.clear()
	_crosswalk_axes.clear()
	_boundary_node_by_side.clear()
	_boundary_nodes_by_road.clear()
	_is_ready = false

	if root == null:
		return

	_collect_road_cells(root)
	_collect_crosswalk_cells(root)
	_build_boundary_nodes()
	_initialize_neighbor_buckets()
	_build_side_links()
	_build_road_cross_links()
	_build_corner_links()
	_build_crosswalk_links()
	_rebuild_components()

	_is_ready = _has_connections()

func has_graph() -> bool:
	return _is_ready and nodes.size() > 1 and neighbors.size() > 0

func find_path_points(start_pos: Vector3, end_pos: Vector3, start_building: Building = null, end_building: Building = null) -> PackedVector3Array:
	var route := PackedVector3Array()
	var start_point := get_access_point(start_pos, start_building)
	var end_point := get_access_point(end_pos, end_building)

	_append_path_point(route, start_pos)

	if nodes.is_empty():
		_append_path_point(route, end_pos)
		return _remove_close_duplicates(route)

	_append_path_point(route, start_point)

	var start_idx := int(_node_index_by_key.get(_grid_key(start_point), get_nearest_node_index(start_point, true)))
	var end_idx := int(_node_index_by_key.get(_grid_key(end_point), get_nearest_node_index(end_point, true)))
	if start_idx < 0 or end_idx < 0:
		_append_path_point(route, end_pos)
		return _remove_close_duplicates(route)

	var index_path := _a_star(start_idx, end_idx)
	if index_path.is_empty():
		if start_point.distance_to(end_point) < 0.05:
			_append_path_point(route, end_pos)
		return _remove_close_duplicates(route)

	for idx in index_path:
		_append_path_point(route, nodes[int(idx)])
	_append_path_point(route, end_pos)
	return _remove_close_duplicates(route)

func get_access_point(pos: Vector3, _building: Building = null) -> Vector3:
	var idx := get_nearest_node_index(pos, true)
	if idx < 0:
		return pos
	return nodes[idx]

func get_component_id_for_pos(pos: Vector3, building: Building = null) -> int:
	var access_point := get_access_point(pos, building)
	var idx := int(_node_index_by_key.get(_grid_key(access_point), get_nearest_node_index(access_point, true)))
	if idx < 0:
		return 0
	return int(_component_by_node.get(idx, 0))

func has_path_between(start_pos: Vector3, end_pos: Vector3, start_building: Building = null, end_building: Building = null) -> bool:
	var start_point := get_access_point(start_pos, start_building)
	var end_point := get_access_point(end_pos, end_building)
	var start_idx := int(_node_index_by_key.get(_grid_key(start_point), get_nearest_node_index(start_point, true)))
	var end_idx := int(_node_index_by_key.get(_grid_key(end_point), get_nearest_node_index(end_point, true)))
	if start_idx < 0 or end_idx < 0:
		return false
	if start_idx == end_idx:
		return true

	var start_component := int(_component_by_node.get(start_idx, 0))
	var end_component := int(_component_by_node.get(end_idx, 0))
	return start_component != 0 and start_component == end_component

func get_nearest_node_index(pos: Vector3, boundary_only: bool = false) -> int:
	var search_indices: Array = _access_node_indices if boundary_only else range(nodes.size())
	if search_indices.is_empty():
		return -1

	var best_idx := -1
	var best_dist := INF
	for raw_idx in search_indices:
		var i := int(raw_idx)
		var dist := _xz_distance(nodes[i], pos)
		if dist < best_dist:
			best_dist = dist
			best_idx = i
	return best_idx

func _collect_road_cells(root: Node3D) -> void:
	for road in _iter_road_nodes(root):
		var snapped := _snap_to_cell(road.global_position)
		_road_cells[_grid_key(snapped)] = snapped

func _collect_crosswalk_cells(root: Node3D) -> void:
	for crosswalk in _iter_crosswalk_nodes(root):
		var snapped := _snap_to_cell(crosswalk.global_position)
		var key := _grid_key(snapped)
		_crosswalk_cells[key] = snapped

		var basis_x := crosswalk.global_transform.basis.x
		var axis := "x" if absf(basis_x.x) >= absf(basis_x.z) else "z"
		_crosswalk_axes[key] = axis

func _build_boundary_nodes() -> void:
	for road_pos in _road_cells.values():
		var road := road_pos as Vector3
		for side in SIDE_DEFS:
			var neighbor := road + (side["neighbor"] as Vector3)
			if _road_cells.has(_grid_key(neighbor)):
				continue

			var midpoint := road + (side["mid"] as Vector3)
			var node_idx := _append_unique_node(midpoint)
			var side_id := int(side["id"])
			_boundary_node_by_side[_side_key(road, side_id)] = node_idx
			var road_key := _grid_key(road)
			var road_nodes := _boundary_nodes_by_road.get(road_key, []) as Array
			if not road_nodes.has(node_idx):
				road_nodes.append(node_idx)
				_boundary_nodes_by_road[road_key] = road_nodes
			if not _access_node_indices.has(node_idx):
				_access_node_indices.append(node_idx)
			_node_meta[node_idx] = {
				"kind": "boundary",
				"road": road,
				"side_id": side_id,
			}

func _initialize_neighbor_buckets() -> void:
	neighbors.clear()
	for i in range(nodes.size()):
		neighbors[i] = []

func _build_side_links() -> void:
	for node_idx_value in _access_node_indices:
		var node_idx := int(node_idx_value)
		var meta := _node_meta.get(node_idx, {}) as Dictionary
		if meta.is_empty():
			continue

		var road := meta["road"] as Vector3
		var side_id := int(meta["side_id"])
		var side := SIDE_DEFS[side_id] as Dictionary
		for tangent in side["tangents"]:
			var next_road := road + (tangent as Vector3)
			var next_idx := int(_boundary_node_by_side.get(_side_key(next_road, side_id), -1))
			if next_idx >= 0:
				_connect_nodes(node_idx, next_idx)

func _build_road_cross_links() -> void:
	for node_indices_value in _boundary_nodes_by_road.values():
		var node_indices := node_indices_value as Array
		if node_indices.size() < 2:
			continue

		for i in range(node_indices.size()):
			var a_idx := int(node_indices[i])
			for j in range(i + 1, node_indices.size()):
				var b_idx := int(node_indices[j])
				_connect_nodes(a_idx, b_idx)

func _build_corner_links() -> void:
	for node_idx_value in _access_node_indices:
		var node_idx := int(node_idx_value)
		var meta := _node_meta.get(node_idx, {}) as Dictionary
		if meta.is_empty():
			continue

		var road := meta["road"] as Vector3
		var side_id := int(meta["side_id"])
		var side := SIDE_DEFS[side_id] as Dictionary
		for corner_offset in side["corners"]:
			var corner_pos := road + (corner_offset as Vector3)
			var corner_idx := _append_corner_node(corner_pos)
			_connect_nodes(node_idx, corner_idx)

func _build_crosswalk_links() -> void:
	for key in _crosswalk_cells.keys():
		var road := _crosswalk_cells[key] as Vector3
		var axis: String = str(_crosswalk_axes.get(key, "x"))
		var a: Vector3
		var b: Vector3
		if axis == "x":
			a = road + Vector3(-HALF_ROAD_WIDTH, 0.0, 0.0)
			b = road + Vector3(HALF_ROAD_WIDTH, 0.0, 0.0)
		else:
			a = road + Vector3(0.0, 0.0, -HALF_ROAD_WIDTH)
			b = road + Vector3(0.0, 0.0, HALF_ROAD_WIDTH)

		var a_idx := int(_node_index_by_key.get(_grid_key(a), -1))
		var b_idx := int(_node_index_by_key.get(_grid_key(b), -1))
		if a_idx < 0 or b_idx < 0:
			continue
		_connect_nodes(a_idx, b_idx)

func _iter_road_nodes(root: Node3D) -> Array[Node3D]:
	var out: Array[Node3D] = []

	var world_city := root.get_node_or_null("World/City") as Node3D
	if world_city != null:
		var city_transport := world_city.get_node_or_null("only_transport") as Node3D
		if city_transport != null:
			_append_transport_segments(city_transport, out)

	var imported := root.get_node_or_null("ImportedCity") as Node3D
	if imported != null:
		var transport := imported.get_node_or_null("only_transport") as Node3D
		if transport != null:
			_append_transport_segments(transport, out)

	var generated := root.get_node_or_null("RoadNetwork") as Node3D
	if generated != null:
		for child in generated.get_children():
			if child is Node3D:
				out.append(child as Node3D)

	return out

func _iter_crosswalk_nodes(root: Node3D) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var crosswalk_root := _find_crosswalk_root(root)
	if crosswalk_root == null:
		return out

	for child in crosswalk_root.get_children():
		if child is Node3D:
			out.append(child as Node3D)

	return out

func _find_crosswalk_root(root: Node3D) -> Node3D:
	var paths := [
		"World/City/only_people_nav/only_people/Road_straight_crossing",
		"ImportedCity/only_people_nav/only_people/Road_straight_crossing",
	]

	for path in paths:
		var node := root.get_node_or_null(path) as Node3D
		if node != null:
			return node

	return null

func _append_transport_segments(transport_root: Node3D, out: Array[Node3D]) -> void:
	for category in transport_root.get_children():
		if category is not Node3D:
			continue
		for segment in (category as Node3D).get_children():
			if segment is Node3D:
				out.append(segment as Node3D)

func _append_corner_node(pos: Vector3) -> int:
	var idx := _append_unique_node(pos)
	if not _node_meta.has(idx):
		_node_meta[idx] = {
			"kind": "corner",
		}
	return idx

func _append_unique_node(pos: Vector3) -> int:
	var snapped := _snap_to_edge(pos)
	var key := _grid_key(snapped)
	if _node_index_by_key.has(key):
		return int(_node_index_by_key[key])

	var idx := nodes.size()
	nodes.append(snapped)
	_node_index_by_key[key] = idx
	return idx

func _connect_nodes(a_idx: int, b_idx: int) -> void:
	if a_idx == b_idx:
		return

	var a_neighbors := neighbors.get(a_idx, []) as Array
	if not a_neighbors.has(b_idx):
		a_neighbors.append(b_idx)
		neighbors[a_idx] = a_neighbors

	var b_neighbors := neighbors.get(b_idx, []) as Array
	if not b_neighbors.has(a_idx):
		b_neighbors.append(a_idx)
		neighbors[b_idx] = b_neighbors

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

		for neighbor in neighbors.get(current, []):
			var neighbor_idx := int(neighbor)
			var tentative := float(g_score.get(current, INF)) + _heuristic(current, neighbor_idx)
			if tentative >= float(g_score.get(neighbor_idx, INF)):
				continue

			came_from[neighbor_idx] = current
			g_score[neighbor_idx] = tentative
			f_score[neighbor_idx] = tentative + _heuristic(neighbor_idx, end_idx)
			if not open.has(neighbor_idx):
				open.append(neighbor_idx)

	return []

func _has_connections() -> bool:
	for linked in neighbors.values():
		if not (linked as Array).is_empty():
			return true
	return false

func _rebuild_components() -> void:
	_component_by_node.clear()
	var component_id := 0

	for node_idx in neighbors.keys():
		var start_idx := int(node_idx)
		if _component_by_node.has(start_idx):
			continue
		var linked := neighbors.get(start_idx, []) as Array
		if linked.is_empty():
			continue

		component_id += 1
		var queue: Array[int] = [start_idx]
		_component_by_node[start_idx] = component_id

		while not queue.is_empty():
			var current = queue.pop_front()
			for neighbor in neighbors.get(current, []):
				var neighbor_idx := int(neighbor)
				if _component_by_node.has(neighbor_idx):
					continue
				_component_by_node[neighbor_idx] = component_id
				queue.append(neighbor_idx)

func _pop_best(open: Array, f_score: Dictionary):
	var best_idx := 0
	var best_node = open[0]
	var best_val := float(f_score.get(best_node, INF))

	for i in range(1, open.size()):
		var candidate = open[i]
		var candidate_val := float(f_score.get(candidate, INF))
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

func _append_path_point(path: PackedVector3Array, point: Vector3, min_dist: float = 0.05) -> void:
	if path.is_empty() or path[path.size() - 1].distance_to(point) >= min_dist:
		path.append(point)

func _remove_close_duplicates(path: PackedVector3Array, min_dist: float = 0.05) -> PackedVector3Array:
	if path.is_empty():
		return path

	var out := PackedVector3Array()
	out.append(path[0])
	for i in range(1, path.size()):
		var point: Vector3 = path[i]
		if out[out.size() - 1].distance_to(point) >= min_dist:
			out.append(point)
	return out

func _snap_to_cell(pos: Vector3) -> Vector3:
	return Vector3(
		round(pos.x / CELL_STEP) * CELL_STEP,
		0.0,
		round(pos.z / CELL_STEP) * CELL_STEP
	)

func _snap_to_edge(pos: Vector3) -> Vector3:
	return Vector3(
		round(pos.x * 2.0) * 0.5,
		0.0,
		round(pos.z * 2.0) * 0.5
	)

func _grid_key(pos: Vector3) -> String:
	return "%0.2f|%0.2f" % [pos.x, pos.z]

func _side_key(road: Vector3, side_id: int) -> String:
	return "%s|%d" % [_grid_key(road), side_id]

func _xz_distance(a: Vector3, b: Vector3) -> float:
	var dx := a.x - b.x
	var dz := a.z - b.z
	return sqrt(dx * dx + dz * dz)
