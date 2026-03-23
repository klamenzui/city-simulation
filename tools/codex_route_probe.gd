extends SceneTree

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
	if world == null:
		push_error("World node not found")
		quit(1)
		return

	var start_building = _find_building(world.buildings, "Residential 01 (Multi-building)")
	var target_building = _find_building(world.buildings, "University 02 (Services)")
	if start_building != null and target_building != null:
		var route: PackedVector3Array = world.get_pedestrian_path(
			start_building.get_entrance_pos(),
			target_building.get_entrance_pos(),
			start_building,
			target_building
		)
		print("ROUTE_PROBE start=", start_building.get_display_name(), " target=", target_building.get_display_name(), " size=", route.size())
		if world.has_method("describe_pedestrian_path"):
			print("ROUTE_SUMMARY ", world.describe_pedestrian_path(route))
		for point in route:
			print("ROUTE_POINT ", _fmt_vec3(point))

		if start_building.has_method("get_navigation_points"):
			var start_nav: Dictionary = start_building.get_navigation_points(world, 0.0)
			print("START_NAV entrance=", _fmt_vec3(start_nav.get("entrance", Vector3.ZERO)), " access=", _fmt_vec3(start_nav.get("access", Vector3.ZERO)), " spawn=", _fmt_vec3(start_nav.get("spawn", Vector3.ZERO)))
		if target_building.has_method("get_navigation_points"):
			var target_nav: Dictionary = target_building.get_navigation_points(world, 0.0)
			print("TARGET_NAV entrance=", _fmt_vec3(target_nav.get("entrance", Vector3.ZERO)), " access=", _fmt_vec3(target_nav.get("access", Vector3.ZERO)), " spawn=", _fmt_vec3(target_nav.get("spawn", Vector3.ZERO)))

	var same_side_start = _find_building(world.buildings, "Residential 03 (Multi-building)")
	var same_side_target = _find_building(world.buildings, "Cinema 05 (Stores)")
	if same_side_start != null and same_side_target != null:
		var same_side_route: PackedVector3Array = world.get_pedestrian_path(
			same_side_start.get_entrance_pos(),
			same_side_target.get_entrance_pos(),
			same_side_start,
			same_side_target
		)
		print("SAME_SIDE_ROUTE start=", same_side_start.get_display_name(), " target=", same_side_target.get_display_name(), " size=", same_side_route.size())
		if world.has_method("describe_pedestrian_path"):
			print("SAME_SIDE_SUMMARY ", world.describe_pedestrian_path(same_side_route))
		for point in same_side_route:
			print("SAME_SIDE_POINT ", _fmt_vec3(point))
		_print_graph_neighbors(world, Vector3(7.0, 0.0, -1.0))
		_print_graph_neighbors(world, Vector3(9.0, 0.0, -1.0))

	var jonas_start = _find_building_near(world.buildings, "Residential 03 (Multi-building)", Vector3(2.0, 0.0, -1.35))
	var jonas_target = _find_building(world.buildings, "Factory 01 (Garages)")
	if jonas_start != null and jonas_target != null:
		var jonas_route: PackedVector3Array = world.get_pedestrian_path(
			jonas_start.get_entrance_pos(),
			jonas_target.get_entrance_pos(),
			jonas_start,
			jonas_target
		)
		print("JONAS_ROUTE start=", jonas_start.get_display_name(), " target=", jonas_target.get_display_name(), " size=", jonas_route.size())
		if world.has_method("describe_pedestrian_path"):
			print("JONAS_SUMMARY ", world.describe_pedestrian_path(jonas_route))
		for point in jonas_route:
			print("JONAS_POINT ", _fmt_vec3(point))

	var crosswalk_pair := _find_crosswalk_building_pair(world)
	if not crosswalk_pair.is_empty():
		var cross_start: Building = crosswalk_pair.get("start")
		var cross_target: Building = crosswalk_pair.get("target")
		var cross_route: PackedVector3Array = crosswalk_pair.get("route")
		print("CROSSWALK_ROUTE start=", cross_start.get_display_name(), " target=", cross_target.get_display_name(), " size=", cross_route.size())
		if world.has_method("describe_pedestrian_path"):
			print("CROSSWALK_SUMMARY ", world.describe_pedestrian_path(cross_route))
		for point in cross_route:
			print("CROSSWALK_POINT ", _fmt_vec3(point))

	for direct_crosswalk_probe in _probe_first_crosswalk_axes(world, main):
		var direct_route: PackedVector3Array = direct_crosswalk_probe.get("route")
		print("DIRECT_CROSSWALK axis=", direct_crosswalk_probe.get("axis", "?"), " start=", _fmt_vec3(direct_crosswalk_probe.get("start", Vector3.ZERO)), " target=", _fmt_vec3(direct_crosswalk_probe.get("target", Vector3.ZERO)), " size=", direct_route.size())
		if world.has_method("describe_pedestrian_path"):
			print("DIRECT_CROSSWALK_SUMMARY ", world.describe_pedestrian_path(direct_route))
		for point in direct_route:
			print("DIRECT_CROSSWALK_POINT ", _fmt_vec3(point))

	for graph_crosswalk_probe in _probe_graph_crosswalks(world):
		var graph_route: PackedVector3Array = graph_crosswalk_probe.get("route")
		print(
			"GRAPH_CROSSWALK key=",
			graph_crosswalk_probe.get("key", ""),
			" axis=",
			graph_crosswalk_probe.get("axis", "?"),
			" center=",
			_fmt_vec3(graph_crosswalk_probe.get("center", Vector3.ZERO)),
			" start=",
			_fmt_vec3(graph_crosswalk_probe.get("start", Vector3.ZERO)),
			" target=",
			_fmt_vec3(graph_crosswalk_probe.get("target", Vector3.ZERO)),
			" size=",
			graph_route.size()
		)
		if world.has_method("describe_pedestrian_path"):
			print("GRAPH_CROSSWALK_SUMMARY ", world.describe_pedestrian_path(graph_route))

	if not world.citizens.is_empty():
		var citizen: Citizen = world.citizens[0] as Citizen
		var home: Building = citizen.home
		if citizen.has_method("exit_current_building") and citizen.has_method("enter_building") and home != null:
			citizen.exit_current_building(world)
			var exit_pos: Vector3 = citizen.global_position
			citizen.enter_building(home, world, false)
			var inside_anchor: Vector3 = citizen.global_position
			print("HOME_PROBE citizen=", citizen.citizen_name, " home=", home.get_display_name(), " exit=", _fmt_vec3(exit_pos), " inside_anchor=", _fmt_vec3(inside_anchor))

	main.queue_free()
	await process_frame
	quit()

func _find_building(buildings: Array, display_name: String):
	for building in buildings:
		if building != null and building.get_display_name() == display_name:
			return building
	return null

func _find_building_near(buildings: Array, display_name: String, near_pos: Vector3):
	var best = null
	var best_dist: float = INF
	for building in buildings:
		if building == null or building.get_display_name() != display_name:
			continue
		var dist: float = building.get_entrance_pos().distance_to(near_pos)
		if dist < best_dist:
			best_dist = dist
			best = building
	return best

func _find_crosswalk_building_pair(world) -> Dictionary:
	if world == null or not world.has_method("count_pedestrian_path_crosswalk_centers"):
		return {}
	for start_building in world.buildings:
		if start_building == null:
			continue
		for target_building in world.buildings:
			if target_building == null or target_building == start_building:
				continue
			var route: PackedVector3Array = world.get_pedestrian_path(
				start_building.get_entrance_pos(),
				target_building.get_entrance_pos(),
				start_building,
				target_building
			)
			if world.count_pedestrian_path_crosswalk_centers(route) <= 0:
				continue
			return {
				"start": start_building,
				"target": target_building,
				"route": route,
			}
	return {}

func _probe_first_crosswalk_axes(world, root: Node) -> Array[Dictionary]:
	if world == null or root == null:
		return []
	var crosswalk := _find_first_crosswalk_node(root)
	if crosswalk == null:
		return []
	var center: Vector3 = crosswalk.global_position
	var probes: Array[Dictionary] = []
	for axis in ["x", "z"]:
		var start_pos := center
		var target_pos := center
		if axis == "x":
			start_pos += Vector3(-1.0, 0.0, 0.0)
			target_pos += Vector3(1.0, 0.0, 0.0)
		else:
			start_pos += Vector3(0.0, 0.0, -1.0)
			target_pos += Vector3(0.0, 0.0, 1.0)
		var route: PackedVector3Array = world.get_pedestrian_path(start_pos, target_pos)
		probes.append({
			"axis": axis,
			"start": start_pos,
			"target": target_pos,
			"route": route,
		})
	return probes

func _probe_graph_crosswalks(world) -> Array[Dictionary]:
	var probes: Array[Dictionary] = []
	if world == null or world.pedestrian_graph == null:
		return probes

	var graph = world.pedestrian_graph
	for key in graph._crosswalk_cells.keys():
		var road := graph._crosswalk_cells[key] as Vector3
		var meta := graph._crosswalk_meta.get(key, {}) as Dictionary
		var axis := str(graph._crosswalk_axes.get(key, "x"))
		var center := meta.get("center", road) as Vector3
		var start_pos := meta.get("entry_anchor", meta.get("entry_point", center)) as Vector3
		var target_pos := meta.get("exit_anchor", meta.get("exit_point", center)) as Vector3
		start_pos.y = 0.0
		target_pos.y = 0.0

		probes.append({
			"key": str(key),
			"axis": axis,
			"center": center,
			"start": start_pos,
			"target": target_pos,
			"route": world.get_pedestrian_path(start_pos, target_pos),
		})

	return probes

func _find_first_crosswalk_node(root: Node) -> Node3D:
	var paths := [
		"World/City/only_people_nav/only_people/Road_straight_crossing",
		"ImportedCity/only_people_nav/only_people/Road_straight_crossing",
	]
	for path in paths:
		var crosswalk_root := root.get_node_or_null(path)
		if crosswalk_root == null:
			continue
		for child in crosswalk_root.get_children():
			if child is Node3D:
				return child as Node3D
	return null

func _print_graph_neighbors(world, point: Vector3) -> void:
	if world == null or world.pedestrian_graph == null:
		return
	var graph = world.pedestrian_graph
	var idx := int(graph._node_index_by_key.get(graph._grid_key(point), -1))
	if idx < 0:
		print("GRAPH_NODE missing point=", _fmt_vec3(point))
		return
	var meta: Dictionary = graph._node_meta.get(idx, {})
	var neighbor_labels: Array[String] = []
	for raw_neighbor in graph.neighbors.get(idx, []):
		var neighbor_idx := int(raw_neighbor)
		neighbor_labels.append("%s kind=%s" % [
			_fmt_vec3(graph.nodes[neighbor_idx]),
			str((graph._node_meta.get(neighbor_idx, {}) as Dictionary).get("kind", ""))
		])
	print("GRAPH_NODE point=", _fmt_vec3(point), " kind=", str((meta as Dictionary).get("kind", "")), " neighbors=", "; ".join(neighbor_labels))

func _fmt_vec3(value: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [value.x, value.y, value.z]
