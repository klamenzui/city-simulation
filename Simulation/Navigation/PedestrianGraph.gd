extends RefCounted
class_name PedestrianGraph

const CELL_STEP := 2.0
const HALF_ROAD_WIDTH := 0.5
const SIDEWALK_PATH_OFFSET := 0.8
const SIDE_DEFS := [
	{
		"id": 0,
		"neighbor": Vector3(-CELL_STEP, 0.0, 0.0),
		"mid": Vector3(-SIDEWALK_PATH_OFFSET, 0.0, 0.0),
		"tangents": [
			Vector3(0.0, 0.0, -CELL_STEP),
			Vector3(0.0, 0.0, CELL_STEP),
		],
		"corners": [
			Vector3(-SIDEWALK_PATH_OFFSET, 0.0, -SIDEWALK_PATH_OFFSET),
			Vector3(-SIDEWALK_PATH_OFFSET, 0.0, SIDEWALK_PATH_OFFSET),
		],
	},
	{
		"id": 1,
		"neighbor": Vector3(CELL_STEP, 0.0, 0.0),
		"mid": Vector3(SIDEWALK_PATH_OFFSET, 0.0, 0.0),
		"tangents": [
			Vector3(0.0, 0.0, -CELL_STEP),
			Vector3(0.0, 0.0, CELL_STEP),
		],
		"corners": [
			Vector3(SIDEWALK_PATH_OFFSET, 0.0, -SIDEWALK_PATH_OFFSET),
			Vector3(SIDEWALK_PATH_OFFSET, 0.0, SIDEWALK_PATH_OFFSET),
		],
	},
	{
		"id": 2,
		"neighbor": Vector3(0.0, 0.0, -CELL_STEP),
		"mid": Vector3(0.0, 0.0, -SIDEWALK_PATH_OFFSET),
		"tangents": [
			Vector3(-CELL_STEP, 0.0, 0.0),
			Vector3(CELL_STEP, 0.0, 0.0),
		],
		"corners": [
			Vector3(-SIDEWALK_PATH_OFFSET, 0.0, -SIDEWALK_PATH_OFFSET),
			Vector3(SIDEWALK_PATH_OFFSET, 0.0, -SIDEWALK_PATH_OFFSET),
		],
	},
	{
		"id": 3,
		"neighbor": Vector3(0.0, 0.0, CELL_STEP),
		"mid": Vector3(0.0, 0.0, SIDEWALK_PATH_OFFSET),
		"tangents": [
			Vector3(-CELL_STEP, 0.0, 0.0),
			Vector3(CELL_STEP, 0.0, 0.0),
		],
		"corners": [
			Vector3(-SIDEWALK_PATH_OFFSET, 0.0, SIDEWALK_PATH_OFFSET),
			Vector3(SIDEWALK_PATH_OFFSET, 0.0, SIDEWALK_PATH_OFFSET),
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
var _crosswalk_meta: Dictionary = {}
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
	_crosswalk_meta.clear()
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
	_build_corner_links()
	_build_corner_perimeter_links()
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

func get_access_point(pos: Vector3, building: Building = null) -> Vector3:
	if building == null:
		var direct_idx := find_node_index_for_path_point(pos)
		if direct_idx >= 0:
			return nodes[direct_idx]
	var idx := _get_access_node_index(pos, building)
	if idx < 0:
		return pos
	var access_point := nodes[idx]
	if building != null:
		return _refine_building_access_point(building, access_point)
	return access_point

func _get_access_node_index(pos: Vector3, building: Building = null) -> int:
	if building != null:
		var building_idx := _get_building_access_node_index(building)
		if building_idx >= 0:
			return building_idx
	return get_nearest_node_index(pos, true)

func _get_building_access_node_index(building: Building) -> int:
	if building == null or _access_node_indices.is_empty():
		return -1

	var entrance_pos := building.get_entrance_pos()
	var building_center := _get_building_world_center(building)
	var outward_dir := entrance_pos - building_center
	outward_dir.y = 0.0
	var has_outward_dir := outward_dir.length_squared() > 0.0001
	if has_outward_dir:
		outward_dir = outward_dir.normalized()

	var best_idx := -1
	var best_score := INF
	for raw_idx in _access_node_indices:
		var idx := int(raw_idx)
		var node_pos := nodes[idx]
		var score := _xz_distance(node_pos, entrance_pos)
		if has_outward_dir:
			var node_dir := node_pos - entrance_pos
			node_dir.y = 0.0
			if node_dir.length_squared() > 0.0001:
				var alignment := outward_dir.dot(node_dir.normalized())
				if alignment < -0.15:
					score += 5.0
				elif alignment < 0.2:
					score += 1.5
				else:
					score -= minf(alignment, 1.0) * 0.35
		if score < best_score:
			best_score = score
			best_idx = idx

	return best_idx

func _refine_building_access_point(building: Building, boundary_point: Vector3) -> Vector3:
	if building == null:
		return boundary_point

	var entrance_pos := building.get_entrance_pos()
	var outward_dir := boundary_point - entrance_pos
	outward_dir.y = 0.0
	if outward_dir.length_squared() <= 0.0001:
		outward_dir = entrance_pos - _get_building_world_center(building)
		outward_dir.y = 0.0
	if outward_dir.length_squared() <= 0.0001:
		return boundary_point
	outward_dir = outward_dir.normalized()

	var boundary_distance := _xz_distance(boundary_point, entrance_pos)
	var desired_distance := minf(boundary_distance, _get_building_access_clearance(building))
	var refined := entrance_pos + outward_dir * desired_distance
	refined.y = boundary_point.y
	return refined

func _get_building_access_clearance(building: Building) -> float:
	if building == null:
		return 0.0
	if building.has_method("get_navigation_approach_distance"):
		return float(building.get_navigation_approach_distance())
	return maxf(
		building.entrance_clearance_depth * 0.8,
		building.entrance_trigger_outset + building.entrance_trigger_radius + 0.25
	)

func _get_building_world_center(building: Building) -> Vector3:
	if building == null:
		return Vector3.ZERO
	if building.has_method("get_footprint_bounds"):
		var bounds: AABB = building.get_footprint_bounds()
		return building.to_global(bounds.position + bounds.size * 0.5)
	return building.global_position

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

func describe_path(points: PackedVector3Array) -> String:
	if points.is_empty():
		return "points=0 crosswalk_centers=0"

	var crosswalk_centers := _collect_crosswalk_centers(points)
	var centers_preview := "-"
	if not crosswalk_centers.is_empty():
		var limited := crosswalk_centers.slice(0, min(4, crosswalk_centers.size()))
		centers_preview = ", ".join(limited)
		if crosswalk_centers.size() > limited.size():
			centers_preview += ", ..."

	return "points=%d crosswalk_centers=%d [%s]" % [
		points.size(),
		crosswalk_centers.size(),
		centers_preview
	]

func count_crosswalk_centers(points: PackedVector3Array) -> int:
	return _collect_crosswalk_centers(points).size()

func get_path_point_kind(point: Vector3) -> String:
	var idx := find_node_index_for_path_point(point)
	if idx < 0:
		return ""
	var meta := _node_meta.get(idx, {}) as Dictionary
	return str(meta.get("kind", ""))

func _collect_crosswalk_centers(points: PackedVector3Array) -> Array[String]:
	var crosswalk_centers: Array[String] = []
	for point in points:
		var idx := find_node_index_for_path_point(point)
		if idx < 0:
			continue
		var meta := _node_meta.get(idx, {}) as Dictionary
		if str(meta.get("kind", "")) != "crosswalk":
			continue
		var point_label := _fmt_vec3(nodes[idx])
		if not crosswalk_centers.has(point_label):
			crosswalk_centers.append(point_label)
	return crosswalk_centers

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

func find_node_index_for_path_point(point: Vector3, max_dist: float = 0.35) -> int:
	var precise := Vector3(
		round(point.x * 100.0) / 100.0,
		0.0,
		round(point.z * 100.0) / 100.0
	)
	var precise_idx := int(_node_index_by_key.get(_grid_key(precise), -1))
	if precise_idx >= 0:
		return precise_idx

	var edge_idx := int(_node_index_by_key.get(_grid_key(_snap_to_edge(point)), -1))
	if edge_idx >= 0 and _xz_distance(nodes[edge_idx], point) <= max_dist:
		return edge_idx

	var nearest_idx := get_nearest_node_index(point)
	if nearest_idx >= 0 and _xz_distance(nodes[nearest_idx], point) <= max_dist:
		return nearest_idx

	return -1

func _collect_road_cells(root: Node3D) -> void:
	for road in _iter_road_nodes(root):
		var snapped := _snap_to_cell(road.global_position)
		_road_cells[_grid_key(snapped)] = snapped

func _collect_crosswalk_cells(root: Node3D) -> void:
	for crosswalk in _iter_crosswalk_nodes(root):
		var geometry := _get_crosswalk_geometry(crosswalk)
		var center := geometry.get("center", crosswalk.global_position) as Vector3
		var snapped := _snap_to_cell(center)
		var key := _grid_key(snapped)
		_road_cells[key] = snapped
		_crosswalk_cells[key] = snapped
		_crosswalk_meta[key] = geometry

		var cross_dir := geometry.get("cross_dir", Vector3.FORWARD) as Vector3
		_crosswalk_axes[key] = "x" if absf(cross_dir.x) >= absf(cross_dir.z) else "z"

func _get_crosswalk_geometry(crosswalk: Node3D) -> Dictionary:
	if crosswalk == null:
		return {}

	var mesh_instance := _find_first_mesh_instance(crosswalk)
	if mesh_instance == null or mesh_instance.mesh == null:
		return {
			"center": crosswalk.global_position,
			"cross_dir": _crosswalk_direction_from_basis(crosswalk.global_transform.basis),
			"half_span": HALF_ROAD_WIDTH,
		}

	var local_aabb := mesh_instance.get_aabb()
	var local_center := local_aabb.position + local_aabb.size * 0.5
	var local_half_cross := local_aabb.size.z * 0.5
	var world_center := mesh_instance.to_global(local_center)
	var world_entry := mesh_instance.to_global(local_center - Vector3(0.0, 0.0, local_half_cross))
	var world_exit := mesh_instance.to_global(local_center + Vector3(0.0, 0.0, local_half_cross))
	world_center.y = 0.0
	world_entry.y = 0.0
	world_exit.y = 0.0

	var cross_dir := world_exit - world_entry
	cross_dir.y = 0.0
	if cross_dir.length_squared() <= 0.0001:
		cross_dir = _crosswalk_direction_from_basis(crosswalk.global_transform.basis)
	else:
		cross_dir = cross_dir.normalized()

	# Use the visual mesh only to detect center/orientation. For navigation we want
	# the crossing to start/end at the road edges, otherwise the perimeter around
	# the tile can become as cheap as the intended center crossing.
	var half_span := HALF_ROAD_WIDTH
	return {
		"center": world_center,
		"cross_dir": cross_dir,
		"half_span": half_span,
	}

func _crosswalk_direction_from_basis(basis: Basis) -> Vector3:
	var cross_dir := basis.z
	cross_dir.y = 0.0
	if cross_dir.length_squared() <= 0.0001:
		return Vector3.FORWARD
	return cross_dir.normalized()

func _find_first_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var mesh_instance := _find_first_mesh_instance(child)
		if mesh_instance != null:
			return mesh_instance
	return null

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

func _build_corner_perimeter_links() -> void:
	for key in _crosswalk_cells.keys():
		var road := _crosswalk_cells[key] as Vector3
		var axis := str(_crosswalk_axes.get(key, "x"))
		var north_west := _append_corner_node(road + Vector3(-SIDEWALK_PATH_OFFSET, 0.0, -SIDEWALK_PATH_OFFSET))
		var north_east := _append_corner_node(road + Vector3(SIDEWALK_PATH_OFFSET, 0.0, -SIDEWALK_PATH_OFFSET))
		var south_west := _append_corner_node(road + Vector3(-SIDEWALK_PATH_OFFSET, 0.0, SIDEWALK_PATH_OFFSET))
		var south_east := _append_corner_node(road + Vector3(SIDEWALK_PATH_OFFSET, 0.0, SIDEWALK_PATH_OFFSET))

		if axis == "x":
			_connect_nodes(north_west, south_west)
			_connect_nodes(north_east, south_east)
		else:
			_connect_nodes(north_west, north_east)
			_connect_nodes(south_west, south_east)

func _build_crosswalk_links() -> void:
	for key in _crosswalk_cells.keys():
		var road := _crosswalk_cells[key] as Vector3
		var axis: String = str(_crosswalk_axes.get(key, "x"))
		var cross_meta := _crosswalk_meta.get(key, {}) as Dictionary
		var center := cross_meta.get("center", road) as Vector3
		var cross_dir := cross_meta.get("cross_dir", Vector3.RIGHT if axis == "x" else Vector3.FORWARD) as Vector3
		var half_span := float(cross_meta.get("half_span", HALF_ROAD_WIDTH))
		cross_dir.y = 0.0
		if cross_dir.length_squared() <= 0.0001:
			cross_dir = Vector3.RIGHT if axis == "x" else Vector3.FORWARD
		else:
			cross_dir = cross_dir.normalized()

		var entry_point := center - cross_dir * half_span
		var exit_point := center + cross_dir * half_span
		entry_point.y = 0.0
		exit_point.y = 0.0

		var entry_anchor_idx := _resolve_crosswalk_anchor_index(road, center, cross_dir, false, entry_point)
		var exit_anchor_idx := _resolve_crosswalk_anchor_index(road, center, cross_dir, true, exit_point)
		if entry_anchor_idx < 0 or exit_anchor_idx < 0:
			continue
		cross_meta["entry_point"] = entry_point
		cross_meta["exit_point"] = exit_point
		cross_meta["entry_anchor"] = nodes[entry_anchor_idx]
		cross_meta["exit_anchor"] = nodes[exit_anchor_idx]
		_crosswalk_meta[key] = cross_meta

		var center_idx := _append_unique_node(center, false)
		var entry_idx := _append_unique_node(entry_point, false)
		var exit_idx := _append_unique_node(exit_point, false)
		_node_meta[center_idx] = {
			"kind": "crosswalk",
			"road": road,
			"axis": axis,
			"center": center,
			"half_span": half_span,
		}
		if not _node_meta.has(entry_idx):
			_node_meta[entry_idx] = {
				"kind": "crosswalk_entry",
				"road": road,
				"axis": axis,
			}
		if not _node_meta.has(exit_idx):
			_node_meta[exit_idx] = {
				"kind": "crosswalk_exit",
				"road": road,
				"axis": axis,
			}
		for corner_idx in _get_crosswalk_side_corner_indices(road, cross_dir, false):
			_connect_nodes(entry_idx, corner_idx)
		for corner_idx in _get_crosswalk_side_corner_indices(road, cross_dir, true):
			_connect_nodes(exit_idx, corner_idx)
		_connect_nodes(entry_anchor_idx, entry_idx)
		_connect_nodes(entry_idx, center_idx)
		_connect_nodes(center_idx, exit_idx)
		_connect_nodes(exit_idx, exit_anchor_idx)

func _resolve_crosswalk_anchor_index(road: Vector3, center: Vector3, cross_dir: Vector3, forward_side: bool, fallback_point: Vector3) -> int:
	var exact_side_idx := _get_crosswalk_side_boundary_index(road, cross_dir, forward_side)
	if exact_side_idx >= 0:
		return exact_side_idx

	var road_nodes := _boundary_nodes_by_road.get(_grid_key(road), []) as Array
	if not road_nodes.is_empty():
		var desired_dir := cross_dir if forward_side else -cross_dir
		var best_idx := -1
		var best_score := -INF
		for raw_idx in road_nodes:
			var idx := int(raw_idx)
			var offset := nodes[idx] - center
			offset.y = 0.0
			if offset.length_squared() <= 0.0001:
				continue
			var alignment := desired_dir.dot(offset.normalized())
			var score := alignment * 10.0 - offset.length()
			if score > best_score:
				best_score = score
				best_idx = idx
		if best_idx >= 0:
			return best_idx

	return get_nearest_node_index(fallback_point, true)

func _get_crosswalk_side_boundary_index(road: Vector3, cross_dir: Vector3, forward_side: bool) -> int:
	var side_id := -1
	if absf(cross_dir.x) >= absf(cross_dir.z):
		if forward_side:
			side_id = 1 if cross_dir.x >= 0.0 else 0
		else:
			side_id = 0 if cross_dir.x >= 0.0 else 1
	else:
		if forward_side:
			side_id = 3 if cross_dir.z >= 0.0 else 2
		else:
			side_id = 2 if cross_dir.z >= 0.0 else 3
	return int(_boundary_node_by_side.get(_side_key(road, side_id), -1))

func _get_crosswalk_side_corner_indices(road: Vector3, cross_dir: Vector3, forward_side: bool) -> Array[int]:
	var corners: Array[int] = []
	if absf(cross_dir.x) >= absf(cross_dir.z):
		var use_east_side := (cross_dir.x >= 0.0) if forward_side else (cross_dir.x < 0.0)
		if use_east_side:
			corners.append(_append_corner_node(road + Vector3(SIDEWALK_PATH_OFFSET, 0.0, -SIDEWALK_PATH_OFFSET)))
			corners.append(_append_corner_node(road + Vector3(SIDEWALK_PATH_OFFSET, 0.0, SIDEWALK_PATH_OFFSET)))
		else:
			corners.append(_append_corner_node(road + Vector3(-SIDEWALK_PATH_OFFSET, 0.0, -SIDEWALK_PATH_OFFSET)))
			corners.append(_append_corner_node(road + Vector3(-SIDEWALK_PATH_OFFSET, 0.0, SIDEWALK_PATH_OFFSET)))
	else:
		var use_south_side := (cross_dir.z >= 0.0) if forward_side else (cross_dir.z < 0.0)
		if use_south_side:
			corners.append(_append_corner_node(road + Vector3(-SIDEWALK_PATH_OFFSET, 0.0, SIDEWALK_PATH_OFFSET)))
			corners.append(_append_corner_node(road + Vector3(SIDEWALK_PATH_OFFSET, 0.0, SIDEWALK_PATH_OFFSET)))
		else:
			corners.append(_append_corner_node(road + Vector3(-SIDEWALK_PATH_OFFSET, 0.0, -SIDEWALK_PATH_OFFSET)))
			corners.append(_append_corner_node(road + Vector3(SIDEWALK_PATH_OFFSET, 0.0, -SIDEWALK_PATH_OFFSET)))
	return corners

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

func _append_unique_node(pos: Vector3, snap_to_grid: bool = true) -> int:
	var snapped := _snap_to_edge(pos) if snap_to_grid else Vector3(
		round(pos.x * 100.0) / 100.0,
		0.0,
		round(pos.z * 100.0) / 100.0
	)
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
			var tentative := float(g_score.get(current, INF)) + _edge_cost(current, neighbor_idx)
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

func _edge_cost(a_idx: int, b_idx: int) -> float:
	return _heuristic(a_idx, b_idx)

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

func _fmt_vec3(value: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [value.x, value.y, value.z]

func _xz_distance(a: Vector3, b: Vector3) -> float:
	var dx := a.x - b.x
	var dz := a.z - b.z
	return sqrt(dx * dx + dz * dz)
