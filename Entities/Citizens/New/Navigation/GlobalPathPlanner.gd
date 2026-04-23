class_name GlobalPathPlanner
extends RefCounted

## Layer 1 of the 4-layer navigation pipeline (Navigation.md §Global Planner).
##
## Builds a coarse long-distance route from `start` to `target`.  Prefers the
## world's pedestrian graph (world.get_pedestrian_path) when available; falls
## back to NavigationServer3D and finally to a single straight segment.
##
## Stateless — exposes a single `build_path` entry point.  Logging describes
## which source produced the path so stuck bugs can be traced back to bad
## global routes vs. local-avoidance failures.

static func build_path(start: Vector3, target: Vector3, ctx: NavigationContext) -> PackedVector3Array:
	var logger := ctx.logger

	var world_path := _build_world_pedestrian_path(start, target, ctx)
	if world_path.size() >= 2:
		logger.info("GLOBAL", "PATH_BUILT", {
			"source": "pedestrian_graph",
			"waypoints": world_path.size(),
			"length": _polyline_length(world_path),
			"start": start,
			"target": target,
		})
		return world_path

	var route := PackedVector3Array()
	var nav_map := ctx.get_navigation_map()
	if not nav_map.is_valid() or NavigationServer3D.map_get_iteration_id(nav_map) <= 0:
		logger.warn("GLOBAL", "PATH_FALLBACK_STRAIGHT", {
			"reason": "no_nav_map",
			"start": start,
			"target": target,
		})
		route.append(start)
		route.append(target)
		return route

	var nav_start := NavigationServer3D.map_get_closest_point(nav_map, start)
	var nav_target := NavigationServer3D.map_get_closest_point(nav_map, target)
	var nav_path := NavigationServer3D.map_get_path(nav_map, nav_start, nav_target, true)
	if nav_path.is_empty():
		logger.warn("GLOBAL", "PATH_FALLBACK_STRAIGHT", {
			"reason": "nav_server_empty",
			"start": start,
			"target": target,
		})
		route.append(start)
		route.append(target)
		return route

	_append_path_point(route, start)
	for point in nav_path:
		_append_path_point(route, point)
	_append_path_point(route, target)

	logger.info("GLOBAL", "PATH_BUILT", {
		"source": "nav_server",
		"waypoints": route.size(),
		"length": _polyline_length(route),
		"start": start,
		"target": target,
	})
	return route


static func _build_world_pedestrian_path(start: Vector3, target: Vector3,
		ctx: NavigationContext) -> PackedVector3Array:
	var world := ctx.get_world_node()
	if world == null or not world.has_method("get_pedestrian_path"):
		return PackedVector3Array()
	var route: PackedVector3Array = world.get_pedestrian_path(start, target)
	if route.size() < 2:
		return PackedVector3Array()
	return route


static func _append_path_point(route: PackedVector3Array, point: Vector3) -> void:
	if route.is_empty() or route[route.size() - 1].distance_to(point) > 0.05:
		route.append(point)


static func _polyline_length(path: PackedVector3Array) -> float:
	var total := 0.0
	for idx in range(path.size() - 1):
		total += path[idx].distance_to(path[idx + 1])
	return total
