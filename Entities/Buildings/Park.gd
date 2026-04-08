extends Building
class_name Park

const BENCH_NAME_HINTS := ["bench", "bank", "seat", "sit"]
const BENCH_RESERVATIONS_META := "_park_bench_reservations"

@export var park_visit_inside_distance: float = 1.25
@export var park_wall_depth: float = 0.6

var _bench_nodes_cache: Array[Node3D] = []
var _bench_nodes_cache_valid: bool = false

func _ready() -> void:
	building_type = BuildingType.PARK
	apply_balance_settings("park")
	#_remove_embedded_scene_bodies()
	super._ready()
	#_rebuild_park_navigation_boundaries()
	_invalidate_park_bench_cache()
	add_to_group("parks")

func _remove_embedded_scene_bodies() -> void:
	var stale_bodies: Array[StaticBody3D] = []
	_collect_embedded_scene_bodies(self, stale_bodies)
	for body in stale_bodies:
		var parent := body.get_parent()
		if parent != null:
			parent.remove_child(body)
		body.queue_free()

func _collect_embedded_scene_bodies(node: Node, out: Array[StaticBody3D]) -> void:
	for child in node.get_children():
		if child is StaticBody3D:
			out.append(child as StaticBody3D)
			continue
		if child is Node:
			_collect_embedded_scene_bodies(child as Node, out)

func get_service_type() -> String:
	return "fun"

func is_outdoor_destination() -> bool:
	return true

func has_navigation_entry() -> bool:
	return not _get_park_entrance_nodes().is_empty()

func has_available_bench_for(citizen = null) -> bool:
	if not get_reserved_bench_for(citizen).is_empty():
		return true
	_prune_invalid_bench_reservations()
	for bench in _get_park_bench_nodes():
		if _is_bench_available(bench):
			return true
	return false

func reserve_bench_for(citizen, reference_pos = null) -> Dictionary:
	if citizen == null:
		return {}

	var existing: Dictionary = get_reserved_bench_for(citizen)
	if not existing.is_empty():
		return existing

	_prune_invalid_bench_reservations()
	var ref_pos: Vector3 = global_position
	if citizen is Node3D:
		ref_pos = (citizen as Node3D).global_position
	if reference_pos is Vector3:
		ref_pos = reference_pos as Vector3

	var best_bench: Node3D = null
	var best_score := INF
	for bench in _get_park_bench_nodes():
		if not _is_bench_available(bench):
			continue
		var score := bench.global_position.distance_squared_to(ref_pos)
		if score < best_score:
			best_score = score
			best_bench = bench

	if best_bench == null:
		return {}

	var reservations := _get_park_bench_reservations()
	reservations[best_bench.get_instance_id()] = weakref(citizen)
	_set_park_bench_reservations(reservations)
	return _build_bench_reservation(best_bench)

func get_reserved_bench_for(citizen) -> Dictionary:
	if citizen == null:
		return {}

	_prune_invalid_bench_reservations()
	var reservations := _get_park_bench_reservations()
	for bench_id in reservations.keys():
		if _resolve_reserved_citizen(reservations[bench_id]) != citizen:
			continue
		var bench := instance_from_id(int(bench_id)) as Node3D
		if bench == null or not is_instance_valid(bench):
			continue
		return _build_bench_reservation(bench)
	return {}

func release_bench_for(citizen) -> void:
	if citizen == null:
		return
	var reservations := _get_park_bench_reservations()
	var release_keys: Array[int] = []
	for bench_id in reservations.keys():
		if _resolve_reserved_citizen(reservations[bench_id]) == citizen:
			release_keys.append(int(bench_id))
	for bench_id in release_keys:
		reservations.erase(bench_id)
	if not release_keys.is_empty():
		_set_park_bench_reservations(reservations)

func _get_extra_info(_world = null) -> Dictionary:
	var center_anchor := _get_park_center_anchor()
	return {
		"Base operating cost": "%d EUR" % get_base_operating_cost_per_day(),
		"Estimated daily obligations": "%d EUR" % get_total_daily_obligation_estimate(),
		"Attractiveness": "%.0f%%" % (get_attractiveness_multiplier() * 100.0),
		"Maintenance staff": "%d" % get_workers_by_titles(["Gardener", "MaintenanceWorker", "Janitor"]).size(),
		"Entrances": "%d" % _get_park_entrance_nodes().size(),
		"Center anchor": center_anchor.name if center_anchor != null else "-",
	}

func get_entrance_node() -> Node3D:
	var entrances := _get_park_entrance_nodes()
	if not entrances.is_empty():
		return entrances[0]
	return super.get_entrance_node()

func get_navigation_points(world = null, lateral_lane_offset: float = 0.0, reference_pos = null) -> Dictionary:
	var entrance_node := _select_park_entrance_node(world, reference_pos)
	var scene_entrance_pos := entrance_node.global_position if entrance_node != null else get_entrance_pos()
	var entrance_pos := _get_park_path_entry_pos(scene_entrance_pos)
	var sidewalk_access_pos := entrance_pos
	if world != null and world.has_method("get_pedestrian_access_point"):
		sidewalk_access_pos = world.get_pedestrian_access_point(entrance_pos, self)
	var access_pos := entrance_pos
	var center_anchor := _get_park_center_anchor()
	var center_pos := center_anchor.global_position if center_anchor != null else global_position
	var visit_pos := _get_park_visit_point(entrance_pos, access_pos, center_pos, lateral_lane_offset)
	return {
		"entrance": entrance_pos,
		"access": access_pos,
		"sidewalk_access": sidewalk_access_pos,
		"visit": visit_pos,
		"center": center_pos,
		"center_node": center_anchor.name if center_anchor != null else "",
		"spawn": _compute_park_spawn_point(entrance_pos, sidewalk_access_pos, lateral_lane_offset),
	}

func get_debug_navigation_entries(world = null) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var center_anchor := _get_park_center_anchor()
	var center_pos := center_anchor.global_position if center_anchor != null else global_position
	for entrance_node in _get_park_entrance_nodes():
		if entrance_node == null:
			continue
		var scene_entrance_pos := entrance_node.global_position
		var entrance_pos := _get_park_path_entry_pos(scene_entrance_pos)
		var access_pos := entrance_pos
		var sidewalk_access_pos := entrance_pos
		if world != null and world.has_method("get_pedestrian_access_point"):
			sidewalk_access_pos = world.get_pedestrian_access_point(entrance_pos, self)
		var visit_pos := _get_park_visit_point(entrance_pos, access_pos, center_pos, 0.0)
		entries.append({
			"entrance": entrance_pos,
			"access": access_pos,
			"sidewalk_access": sidewalk_access_pos,
			"visit": visit_pos,
			"center": center_pos,
		})
	return entries

func get_internal_navigation_route(nav_points: Dictionary) -> PackedVector3Array:
	var start_pos: Vector3 = nav_points.get("entrance", get_entrance_pos())
	var end_pos: Vector3 = nav_points.get("visit", nav_points.get("center", global_position))
	return _build_park_internal_route(start_pos, end_pos)

func _get_park_bench_nodes() -> Array[Node3D]:
	if _bench_nodes_cache_valid:
		var cached: Array[Node3D] = []
		for bench in _bench_nodes_cache:
			if bench != null and is_instance_valid(bench):
				cached.append(bench)
		_bench_nodes_cache = cached
		return cached

	var benches: Array[Node3D] = []
	_collect_park_bench_nodes(_get_park_cluster_root(), benches)
	_bench_nodes_cache = benches
	_bench_nodes_cache_valid = true
	return benches

func _invalidate_park_bench_cache() -> void:
	_bench_nodes_cache.clear()
	_bench_nodes_cache_valid = false

func _collect_park_bench_nodes(node: Node, out: Array[Node3D]) -> void:
	for child in node.get_children():
		if child is Node3D:
			var marker := child as Node3D
			if _is_bench_marker_node(marker):
				out.append(marker)
		if child is Node:
			_collect_park_bench_nodes(child, out)

func _is_bench_marker_node(node: Node3D) -> bool:
	if node == null:
		return false
	if node.get_script() != null:
		return false
	if node.get_child_count() > 0:
		return false
	var node_class := node.get_class()
	if node_class != "Node3D" and node_class != "Marker3D":
		return false
	var name_lower := node.name.to_lower()
	for hint in BENCH_NAME_HINTS:
		if name_lower.contains(hint):
			return true
	return false

func _is_bench_available(bench: Node3D) -> bool:
	if bench == null or not is_instance_valid(bench):
		return false
	var reservations := _get_park_bench_reservations()
	var bench_id := bench.get_instance_id()
	if not reservations.has(bench_id):
		return true
	return _resolve_reserved_citizen(reservations[bench_id]) == null

func _build_bench_reservation(bench: Node3D) -> Dictionary:
	if bench == null:
		return {}
	return {
		"node": bench,
		"name": bench.name,
		"position": bench.global_position,
		"yaw": bench.global_rotation.y,
	}

func _get_park_cluster_root() -> Node:
	var park_root: Node = get_parent()
	return park_root if park_root != null else self

func _get_park_bench_reservations() -> Dictionary:
	var park_root := _get_park_cluster_root()
	if not park_root.has_meta(BENCH_RESERVATIONS_META):
		park_root.set_meta(BENCH_RESERVATIONS_META, {})
	var reservations: Variant = park_root.get_meta(BENCH_RESERVATIONS_META)
	if reservations is Dictionary:
		return reservations as Dictionary
	var fresh: Dictionary = {}
	park_root.set_meta(BENCH_RESERVATIONS_META, fresh)
	return fresh

func _set_park_bench_reservations(reservations: Dictionary) -> void:
	var park_root := _get_park_cluster_root()
	park_root.set_meta(BENCH_RESERVATIONS_META, reservations)

func _resolve_reserved_citizen(value) -> Node:
	if value is WeakRef:
		var citizen: Node = (value as WeakRef).get_ref() as Node
		if citizen != null and is_instance_valid(citizen):
			return citizen
	return null

func _prune_invalid_bench_reservations() -> void:
	var reservations := _get_park_bench_reservations()
	var stale_keys: Array[int] = []
	for bench_id in reservations.keys():
		var bench := instance_from_id(int(bench_id)) as Node3D
		if bench == null or not is_instance_valid(bench):
			stale_keys.append(int(bench_id))
			continue
		if _resolve_reserved_citizen(reservations[bench_id]) == null:
			stale_keys.append(int(bench_id))
	for bench_id in stale_keys:
		reservations.erase(bench_id)
	if not stale_keys.is_empty():
		_set_park_bench_reservations(reservations)

func _get_park_center_anchor() -> Node3D:
	var park_root := get_parent()
	if park_root == null:
		return self

	for explicit_name in ["ParkCenter", "_Node3D_187"]:
		var explicit_anchor := park_root.get_node_or_null(explicit_name) as Node3D
		if explicit_anchor != null:
			return explicit_anchor

	var park_tiles: Array[Park] = []
	var centroid := Vector3.ZERO
	for child in park_root.get_children():
		if child is Park:
			var tile := child as Park
			park_tiles.append(tile)
			centroid += tile.global_position
	if park_tiles.is_empty():
		return self

	centroid /= float(park_tiles.size())
	var center_candidates: Array[Park] = []
	for tile in park_tiles:
		if tile != null and not tile.has_navigation_entry():
			center_candidates.append(tile)
	if center_candidates.is_empty():
		center_candidates = park_tiles

	var best_tile := center_candidates[0]
	var best_distance := best_tile.global_position.distance_squared_to(centroid)
	for tile in center_candidates:
		if tile == null:
			continue
		var distance := tile.global_position.distance_squared_to(centroid)
		if distance < best_distance:
			best_distance = distance
			best_tile = tile
	return best_tile

func _get_park_center_path() -> Path3D:
	var park_root := get_parent()
	if park_root == null:
		return null
	var named_center := park_root.get_node_or_null("Center") as Path3D
	if named_center != null:
		return named_center
	for child in park_root.get_children():
		if child is Path3D:
			var path := child as Path3D
			if path.curve != null and path.curve.closed:
				return path
	return null

func _get_park_connector_paths() -> Array[Path3D]:
	var paths: Array[Path3D] = []
	var park_root := get_parent()
	if park_root == null:
		return paths
	var center_path := _get_park_center_path()
	for child in park_root.get_children():
		if child is Path3D:
			var path := child as Path3D
			if path == center_path:
				continue
			if path.curve == null:
				continue
			paths.append(path)
	return paths

func _get_park_visit_point(
	entrance_pos: Vector3,
	access_pos: Vector3,
	center_pos: Vector3,
	lateral_lane_offset: float = 0.0
) -> Vector3:
	var visit_pos := center_pos
	var center_path := _get_park_center_path()
	if center_path != null and center_path.curve != null:
		var connector_match := _get_park_connector_match(entrance_pos)
		var ring_start := connector_match.get("ring_pos", center_pos) as Vector3 if not connector_match.is_empty() else center_pos
		var curve := center_path.curve
		var start_offset := curve.get_closest_offset(center_path.to_local(ring_start))
		var center_offset := curve.get_closest_offset(center_path.to_local(center_pos))
		var visit_offset := center_offset
		if curve.closed:
			var ring_length := curve.get_baked_length()
			if ring_length > 0.01:
				var clockwise := fposmod(center_offset - start_offset, ring_length)
				var counter_clockwise := clockwise - ring_length
				visit_offset = start_offset + (clockwise if absf(clockwise) <= absf(counter_clockwise) else counter_clockwise)
		visit_pos = center_path.to_global(curve.sample_baked(visit_offset, true))
		visit_pos.y = center_pos.y
	return _compute_park_visit_point(visit_pos, center_pos, entrance_pos, access_pos, lateral_lane_offset)

func _build_park_internal_route(entrance_pos: Vector3, visit_pos: Vector3) -> PackedVector3Array:
	var route := PackedVector3Array()
	var connector_match := _get_park_connector_match(entrance_pos)
	if not connector_match.is_empty():
		var connector_path := connector_match.get("path") as Path3D
		if connector_path != null and connector_path.curve != null:
			var connector_segment := _sample_park_path_segment(
				connector_path,
				float(connector_match.get("start_offset", 0.0)),
				float(connector_match.get("end_offset", 0.0))
			)
			route = _append_route_points(route, connector_segment)

	var center_path := _get_park_center_path()
	if center_path != null and center_path.curve != null:
		var ring_start_pos := connector_match.get("ring_pos", entrance_pos) as Vector3 if not connector_match.is_empty() else entrance_pos
		var ring_curve := center_path.curve
		var start_offset := ring_curve.get_closest_offset(center_path.to_local(ring_start_pos))
		var end_offset := ring_curve.get_closest_offset(center_path.to_local(visit_pos))
		var ring_segment := _sample_park_path_segment(center_path, start_offset, end_offset)
		route = _append_route_points(route, ring_segment)

	if route.is_empty():
		route.append(visit_pos)
	return route

func _get_park_connector_match(entrance_pos: Vector3) -> Dictionary:
	var best_match := {}
	var best_score := INF
	for connector_path in _get_park_connector_paths():
		var endpoints := _get_path_endpoints_world(connector_path)
		if endpoints.size() < 2:
			continue
		var start_point := endpoints[0]
		var end_point := endpoints[1]
		var start_distance := entrance_pos.distance_squared_to(start_point)
		var end_distance := entrance_pos.distance_squared_to(end_point)
		var approach_from_start := start_distance <= end_distance
		var curve := connector_path.curve
		var curve_length := curve.get_baked_length()
		var score := minf(start_distance, end_distance)
		if score < best_score:
			best_score = score
			best_match = {
				"path": connector_path,
				"entry_pos": start_point if approach_from_start else end_point,
				"start_offset": 0.0 if approach_from_start else curve_length,
				"end_offset": curve_length if approach_from_start else 0.0,
				"ring_pos": end_point if approach_from_start else start_point,
			}
	return best_match

func _get_park_path_entry_pos(scene_entrance_pos: Vector3) -> Vector3:
	var connector_match := _get_park_connector_match(scene_entrance_pos)
	if connector_match.is_empty():
		return scene_entrance_pos
	return connector_match.get("entry_pos", scene_entrance_pos) as Vector3

func _get_path_endpoints_world(path: Path3D) -> Array[Vector3]:
	var endpoints: Array[Vector3] = []
	if path == null or path.curve == null:
		return endpoints
	var curve := path.curve
	var length := curve.get_baked_length()
	endpoints.append(path.to_global(curve.sample_baked(0.0, true)))
	endpoints.append(path.to_global(curve.sample_baked(length, true)))
	return endpoints

func _append_route_points(base_route: PackedVector3Array, extra_points: PackedVector3Array) -> PackedVector3Array:
	var combined := PackedVector3Array(base_route)
	for point in extra_points:
		if combined.is_empty() or combined[combined.size() - 1].distance_to(point) > 0.15:
			combined.append(point)
	return combined

func _get_park_entrance_nodes() -> Array[Node3D]:
	var entrances: Array[Node3D] = []
	if entrance != null:
		entrances.append(entrance)
	for child in get_children():
		if child is Node3D:
			var node := child as Node3D
			if node == entrance:
				continue
			if node.name == "Entrance" or (node.name.begins_with("Entrance") and not node.name.begins_with("EntranceTrigger")):
				entrances.append(node)
	return entrances

func _select_park_entrance_node(world = null, reference_pos = null) -> Node3D:
	var entrances := _get_park_entrance_nodes()
	if entrances.is_empty():
		return null
	if entrances.size() == 1:
		return entrances[0]

	var has_reference := reference_pos is Vector3
	var ref_pos: Vector3 = reference_pos if has_reference else global_position
	var best_node := entrances[0]
	var best_score := INF

	for entrance_node in entrances:
		if entrance_node == null:
			continue
		var entrance_pos := entrance_node.global_position
		var anchor_pos := _get_park_path_entry_pos(entrance_pos)
		if world != null and world.has_method("get_pedestrian_access_point"):
			anchor_pos = world.get_pedestrian_access_point(anchor_pos, self)
		var score := ref_pos.distance_squared_to(anchor_pos) if has_reference else anchor_pos.distance_squared_to(global_position)
		if score < best_score:
			best_score = score
			best_node = entrance_node
	return best_node

func _compute_park_visit_point(
	path_visit: Vector3,
	center_pos: Vector3,
	entrance_pos: Vector3,
	access_pos: Vector3,
	lateral_lane_offset: float = 0.0
) -> Vector3:
	var inward := center_pos - entrance_pos
	inward.y = 0.0
	if inward.length_squared() <= 0.0001:
		inward = entrance_pos - access_pos
		inward.y = 0.0
	if inward.length_squared() <= 0.0001:
		inward = Vector3.ZERO
	else:
		inward = inward.normalized()

	var visit_pos := path_visit
	if inward.length_squared() > 0.0001 and absf(lateral_lane_offset) > 0.001:
		var lateral := Vector3(-inward.z, 0.0, inward.x)
		visit_pos += lateral * (lateral_lane_offset * 0.35)
	visit_pos.y = path_visit.y
	return visit_pos

func _sample_park_path_segment(path: Path3D, start_offset: float, end_offset: float) -> PackedVector3Array:
	var route := PackedVector3Array()
	if path == null or path.curve == null:
		return route

	var curve := path.curve
	var length := curve.get_baked_length()
	if length <= 0.01:
		route.append(path.to_global(curve.sample_baked(end_offset, true)))
		return route

	var distance := end_offset - start_offset
	if curve.closed:
		var wrapped_forward := fposmod(distance, length)
		var wrapped_backward := wrapped_forward - length
		distance = wrapped_backward if absf(wrapped_backward) < absf(wrapped_forward) else wrapped_forward

	var direction := 1.0 if distance >= 0.0 else -1.0
	var step := 0.9 * direction
	var travelled := 0.0
	while absf(travelled) < absf(distance):
		var sample_offset := start_offset + travelled
		if curve.closed:
			sample_offset = fposmod(sample_offset, length)
		else:
			sample_offset = clampf(sample_offset, 0.0, length)
		route.append(path.to_global(curve.sample_baked(sample_offset, true)))
		travelled += step

	var end_sample := end_offset
	if curve.closed:
		end_sample = fposmod(end_sample, length)
	else:
		end_sample = clampf(end_sample, 0.0, length)
	route.append(path.to_global(curve.sample_baked(end_sample, true)))

	var deduped := PackedVector3Array()
	for point in route:
		if deduped.is_empty() or deduped[deduped.size() - 1].distance_to(point) > 0.15:
			deduped.append(point)
	return deduped

func _compute_park_spawn_point(
	entrance_pos: Vector3,
	access_pos: Vector3,
	lateral_lane_offset: float = 0.0
) -> Vector3:
	var outward := access_pos - entrance_pos
	outward.y = 0.0
	if outward.length_squared() <= 0.0001:
		outward = Vector3.FORWARD
	else:
		outward = outward.normalized()

	var lateral := Vector3(-outward.z, 0.0, outward.x)
	var spawn_base := entrance_pos.lerp(access_pos, 0.82)
	var spawn_pos := spawn_base + lateral * lateral_lane_offset + outward * 0.10
	spawn_pos.y = spawn_base.y
	return spawn_pos

func _rebuild_park_navigation_boundaries() -> void:
	var existing_blocker := get_node_or_null("NavigationBlocker")
	if existing_blocker != null:
		existing_blocker.queue_free()
	var existing_trigger := get_node_or_null("EntranceTrigger")
	if existing_trigger != null:
		existing_trigger.queue_free()
	var existing_triggers := get_node_or_null("EntranceTriggers")
	if existing_triggers != null:
		existing_triggers.queue_free()

	_create_park_wall_blocker()
	_create_park_entrance_triggers()

func _create_park_wall_blocker() -> void:
	var bounds := get_footprint_bounds()
	var blocker_size := bounds.size
	blocker_size.x = maxf(blocker_size.x - navigation_blocker_margin, 0.8)
	blocker_size.z = maxf(blocker_size.z - navigation_blocker_margin, 0.8)
	blocker_size.y = maxf(blocker_size.y, 1.2)
	var blocker_bounds := _build_blocker_bounds(bounds, blocker_size)
	var wall_depth := clampf(park_wall_depth, 0.25, minf(blocker_bounds.size.x, blocker_bounds.size.z) * 0.45)

	var blocker := StaticBody3D.new()
	blocker.name = "NavigationBlocker"
	blocker.collision_layer = 1
	blocker.collision_mask = 1

	_add_park_wall_side(blocker, blocker_bounds, "x", -1, wall_depth)
	_add_park_wall_side(blocker, blocker_bounds, "x", 1, wall_depth)
	_add_park_wall_side(blocker, blocker_bounds, "z", -1, wall_depth)
	_add_park_wall_side(blocker, blocker_bounds, "z", 1, wall_depth)
	add_child(blocker)

func _add_park_wall_side(blocker: StaticBody3D, blocker_bounds: AABB, axis: String, sign: int, wall_depth: float) -> void:
	var side_gaps := _get_side_gaps(blocker_bounds, axis, sign)
	var cross_min := blocker_bounds.position.z if axis == "x" else blocker_bounds.position.x
	var cross_max := cross_min + (blocker_bounds.size.z if axis == "x" else blocker_bounds.size.x)
	var segments := _segments_from_gaps(cross_min, cross_max, side_gaps)
	var shape_index := blocker.get_child_count()
	for segment in segments:
		var start := float(segment.x)
		var end := float(segment.y)
		if end - start <= 0.12:
			continue
		var local_bounds := AABB()
		if axis == "x":
			var band_min_x := blocker_bounds.position.x if sign < 0 else blocker_bounds.position.x + blocker_bounds.size.x - wall_depth
			local_bounds = AABB(
				Vector3(band_min_x, blocker_bounds.position.y, start),
				Vector3(wall_depth, blocker_bounds.size.y, end - start)
			)
		else:
			var band_min_z := blocker_bounds.position.z if sign < 0 else blocker_bounds.position.z + blocker_bounds.size.z - wall_depth
			local_bounds = AABB(
				Vector3(start, blocker_bounds.position.y, band_min_z),
				Vector3(end - start, blocker_bounds.size.y, wall_depth)
			)
		shape_index = _add_blocker_shape(blocker, local_bounds, shape_index)

func _get_side_gaps(blocker_bounds: AABB, axis: String, sign: int) -> Array[Vector2]:
	var gaps: Array[Vector2] = []
	var cross_min := blocker_bounds.position.z if axis == "x" else blocker_bounds.position.x
	var cross_max := cross_min + (blocker_bounds.size.z if axis == "x" else blocker_bounds.size.x)
	for entrance_node in _get_park_entrance_nodes():
		if entrance_node == null:
			continue
		var local_entrance := to_local(entrance_node.global_position)
		var center := blocker_bounds.position + blocker_bounds.size * 0.5
		var outward_dir := local_entrance - center
		outward_dir.y = 0.0
		if outward_dir.length_squared() <= 0.0001:
			continue
		var entrance_axis := "x" if absf(outward_dir.x) >= absf(outward_dir.z) else "z"
		var entrance_sign := 1 if (outward_dir.x if entrance_axis == "x" else outward_dir.z) >= 0.0 else -1
		if entrance_axis != axis or entrance_sign != sign:
			continue
		var cross_center := local_entrance.z if axis == "x" else local_entrance.x
		var half_gap := maxf(entrance_clearance_width * 0.5, 0.45)
		var clamped_center := clampf(cross_center, cross_min + half_gap, cross_max - half_gap)
		gaps.append(Vector2(clamped_center - half_gap, clamped_center + half_gap))
	return _merge_gap_segments(gaps)

func _merge_gap_segments(gaps: Array[Vector2]) -> Array[Vector2]:
	if gaps.is_empty():
		return []
	gaps.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var merged: Array[Vector2] = [gaps[0]]
	for idx in range(1, gaps.size()):
		var current := gaps[idx]
		var last := merged[merged.size() - 1]
		if current.x <= last.y + 0.05:
			last.y = maxf(last.y, current.y)
			merged[merged.size() - 1] = last
		else:
			merged.append(current)
	return merged

func _segments_from_gaps(range_min: float, range_max: float, gaps: Array[Vector2]) -> Array[Vector2]:
	var segments: Array[Vector2] = []
	var cursor := range_min
	for gap in gaps:
		if gap.x > cursor:
			segments.append(Vector2(cursor, minf(gap.x, range_max)))
		cursor = maxf(cursor, gap.y)
	if cursor < range_max:
		segments.append(Vector2(cursor, range_max))
	return segments

func _create_park_entrance_triggers() -> void:
	var entrances := _get_park_entrance_nodes()
	if entrances.is_empty():
		return
	var trigger_root := Node3D.new()
	trigger_root.name = "EntranceTriggers"
	add_child(trigger_root)

	for idx in range(entrances.size()):
		var entrance_node := entrances[idx]
		if entrance_node == null:
			continue
		var local_entrance := to_local(entrance_node.global_position)
		var bounds := get_footprint_bounds()
		var bounds_center := bounds.position + bounds.size * 0.5
		var outward_dir := Vector3(
			local_entrance.x - bounds_center.x,
			0.0,
			local_entrance.z - bounds_center.z
		)
		if outward_dir.length_squared() <= 0.0001:
			outward_dir = Vector3.FORWARD
		else:
			outward_dir = outward_dir.normalized()

		var trigger := StaticBody3D.new()
		trigger.name = "EntranceTrigger_%d" % idx
		trigger.collision_layer = 8
		trigger.collision_mask = 0

		var shape_node := CollisionShape3D.new()
		shape_node.name = "CollisionShape3D"
		var shape := SphereShape3D.new()
		shape.radius = entrance_trigger_radius
		shape_node.shape = shape

		var trigger_pos := local_entrance + outward_dir * entrance_trigger_outset
		trigger_pos.y = maxf(local_entrance.y, entrance_trigger_height * 0.5)
		shape_node.position = trigger_pos

		trigger.add_child(shape_node)
		trigger_root.add_child(trigger)
