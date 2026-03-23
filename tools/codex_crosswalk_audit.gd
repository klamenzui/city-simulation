extends SceneTree

const MAX_PRINT := 24

func _init() -> void:
	var main_scene := load("res://Main.tscn")
	if main_scene == null:
		push_error("Failed to load Main.tscn")
		quit(1)
		return

	var main = main_scene.instantiate()
	root.add_child(main)

	await process_frame
	await process_frame
	await process_frame

	var world = main.get_node_or_null("World")
	if world == null or world.pedestrian_graph == null:
		push_error("World or pedestrian_graph missing")
		quit(1)
		return

	var graph = world.pedestrian_graph
	var edge_findings := _audit_graph_edges(graph)
	print("EDGE_AUDIT total=", edge_findings.size())
	for finding in edge_findings.slice(0, min(edge_findings.size(), MAX_PRINT)):
		print(
			"EDGE_FINDING type=",
			finding.get("type", ""),
			" cell=",
			_fmt_vec3(finding.get("cell", Vector3.ZERO)),
			" a=",
			_fmt_vec3(finding.get("a", Vector3.ZERO)),
			" a_kind=",
			finding.get("a_kind", ""),
			" b=",
			_fmt_vec3(finding.get("b", Vector3.ZERO)),
			" b_kind=",
			finding.get("b_kind", "")
		)

	var route_findings: Array[Dictionary] = []
	var total_routes := 0
	var routes_with_crosswalk := 0
	for start_building in world.buildings:
		if start_building == null:
			continue
		for target_building in world.buildings:
			if target_building == null or target_building == start_building:
				continue
			total_routes += 1
			var route: PackedVector3Array = world.get_pedestrian_path(
				start_building.get_entrance_pos(),
				target_building.get_entrance_pos(),
				start_building,
				target_building
			)
			if world.has_method("count_pedestrian_path_crosswalk_centers") and world.count_pedestrian_path_crosswalk_centers(route) > 0:
				routes_with_crosswalk += 1
			for issue in _audit_route_segments(graph, route):
				issue["start"] = start_building.get_display_name()
				issue["target"] = target_building.get_display_name()
				route_findings.append(issue)

	print(
		"ROUTE_AUDIT total_routes=",
		total_routes,
		" routes_with_crosswalk=",
		routes_with_crosswalk,
		" illegal_routes=",
		route_findings.size()
	)
	for finding in route_findings.slice(0, min(route_findings.size(), MAX_PRINT)):
		print(
			"ROUTE_FINDING start=",
			finding.get("start", ""),
			" target=",
			finding.get("target", ""),
			" type=",
			finding.get("type", ""),
			" cell=",
			_fmt_vec3(finding.get("cell", Vector3.ZERO)),
			" a=",
			_fmt_vec3(finding.get("a", Vector3.ZERO)),
			" b=",
			_fmt_vec3(finding.get("b", Vector3.ZERO))
		)

	main.queue_free()
	await process_frame
	quit()

func _audit_graph_edges(graph) -> Array[Dictionary]:
	var findings: Array[Dictionary] = []
	for raw_a_idx in graph.neighbors.keys():
		var a_idx := int(raw_a_idx)
		for raw_b_idx in graph.neighbors.get(a_idx, []):
			var b_idx := int(raw_b_idx)
			if b_idx <= a_idx:
				continue
			var finding := _classify_segment(graph, graph.nodes[a_idx], graph.nodes[b_idx], a_idx, b_idx)
			if not finding.is_empty():
				findings.append(finding)
	return findings

func _audit_route_segments(graph, route: PackedVector3Array) -> Array[Dictionary]:
	var findings: Array[Dictionary] = []
	var mapped_indices: Array[int] = []
	var mapped_points: Array[Vector3] = []
	for point in route:
		var idx := int(graph._node_index_by_key.get(graph._grid_key(graph._snap_to_edge(point)), -1))
		if idx < 0:
			continue
		if not mapped_indices.is_empty() and mapped_indices[mapped_indices.size() - 1] == idx:
			continue
		mapped_indices.append(idx)
		mapped_points.append(graph.nodes[idx])

	for i in range(mapped_indices.size() - 1):
		var a_idx := mapped_indices[i]
		var b_idx := mapped_indices[i + 1]
		var finding := _classify_segment(graph, mapped_points[i], mapped_points[i + 1], a_idx, b_idx)
		if not finding.is_empty():
			findings.append(finding)
	return findings

func _classify_segment(graph, a: Vector3, b: Vector3, a_idx: int, b_idx: int) -> Dictionary:
	var a_meta := graph._node_meta.get(a_idx, {}) as Dictionary
	var b_meta := graph._node_meta.get(b_idx, {}) as Dictionary
	if _is_crosswalk_kind(str(a_meta.get("kind", ""))) or _is_crosswalk_kind(str(b_meta.get("kind", ""))):
		return {}

	var midpoint := (a + b) * 0.5
	var road_center: Vector3 = graph._snap_to_cell(midpoint)
	if midpoint.distance_to(road_center) > 0.05:
		return {}

	var cell_key: String = graph._grid_key(road_center)
	if not graph._road_cells.has(cell_key):
		return {}

	return {
		"type": "crosswalk_bypass" if graph._crosswalk_cells.has(cell_key) else "off_crosswalk_crossing",
		"cell": road_center,
		"a": a,
		"b": b,
		"a_kind": str(a_meta.get("kind", "")),
		"b_kind": str(b_meta.get("kind", "")),
	}

func _is_crosswalk_kind(kind: String) -> bool:
	return kind.begins_with("crosswalk")

func _fmt_vec3(value: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [value.x, value.y, value.z]
