extends SceneTree

const GoToBuildingActionScript = preload("res://Actions/GoToBuildingAction.gd")

const SETTLE_FRAMES := 30
const MAX_TRAVEL_SECONDS := 120.0
const PHYSICS_HZ := 60.0
const ACTION_TICK_FRAMES := 30

func _init() -> void:
	print("=== Building entry travel test ===")

	var main_scene := load("res://Main.tscn")
	if main_scene == null:
		printerr("FAIL: cannot load Main.tscn")
		quit(1)
		return

	var main: Node = main_scene.instantiate()
	root.add_child(main)
	for _i in range(SETTLE_FRAMES):
		await process_frame
	await physics_frame

	var world := main.get_node_or_null("World") as World
	if world == null:
		printerr("FAIL: World node not found")
		quit(1)
		return
	if world.citizens.is_empty():
		printerr("FAIL: no citizens registered")
		quit(1)
		return

	var route_case := _find_short_entry_route(world)
	if route_case.is_empty():
		printerr("FAIL: no building-to-building pedestrian route found")
		quit(1)
		return

	var citizen := _find_scripted_travel_citizen(world)
	if citizen == null:
		printerr("FAIL: no scriptable citizen registered")
		quit(1)
		return
	var source: Building = route_case.get("source")
	var target: Building = route_case.get("target")
	var source_pos: Vector3 = route_case.get("source_pos")
	var route: PackedVector3Array = route_case.get("route")
	citizen.global_position = source_pos
	citizen.velocity = Vector3.ZERO
	citizen.force_update_transform()
	citizen.current_location = null
	await physics_frame

	var action: GoToBuildingAction = GoToBuildingActionScript.new(target, 20)
	citizen.current_action = action
	action.start(world, citizen)
	if action.is_done():
		printerr("FAIL: GoTo action finished during start")
		_print_debug(citizen, source, target, route)
		quit(1)
		return

	var max_frames := int(ceil(MAX_TRAVEL_SECONDS * PHYSICS_HZ))
	for frame in range(max_frames):
		await physics_frame
		if frame % ACTION_TICK_FRAMES == 0:
			action.tick(world, citizen, world.minutes_per_tick)
			if action.is_done():
				action.finish(world, citizen)
				if citizen.current_action == action:
					citizen.current_action = null
				break

	var inside_ok := citizen.current_location == target \
			and citizen.is_inside_building() \
			and not citizen.visible \
			and not citizen.is_travelling()
	if not inside_ok:
		printerr("FAIL: citizen did not enter/hide after reaching building")
		_print_debug(citizen, source, target, route)
		quit(1)
		return

	var indoor_y := citizen.global_position.y
	for _i in range(120):
		await physics_frame
	var indoor_y_delta := absf(citizen.global_position.y - indoor_y)
	if indoor_y_delta > 0.02 or citizen.velocity.length_squared() > 0.0001:
		printerr("FAIL: hidden indoor citizen kept simulating physics and fell")
		_print_debug(citizen, source, target, route)
		printerr("  indoor_y_before=%.3f indoor_y_after=%.3f velocity=%s" % [
			indoor_y,
			citizen.global_position.y,
			_fmt_v3(citizen.velocity),
		])
		quit(1)
		return

	print("ENTRY_TRAVEL OK source=%s target=%s route_points=%d pos=%s visible=%s inside=%s" % [
		source.get_display_name(),
		target.get_display_name(),
		route.size(),
		_fmt_v3(citizen.global_position),
		str(citizen.visible),
		str(citizen.is_inside_building())
	])
	main.queue_free()
	await process_frame
	quit(0)


func _find_scripted_travel_citizen(world: World) -> Citizen:
	for citizen in world.citizens:
		if _is_scriptable_travel_citizen(citizen):
			return _prepare_scripted_travel_citizen(citizen)
	for citizen in world.citizens:
		if citizen != null and citizen is Citizen:
			return _prepare_scripted_travel_citizen(citizen)
	return null


func _is_scriptable_travel_citizen(citizen) -> bool:
	if citizen == null or not (citizen is Citizen):
		return false
	if citizen.has_method("is_keyboard_control_enabled") and citizen.is_keyboard_control_enabled():
		return false
	return citizen.is_inside_tree()


func _prepare_scripted_travel_citizen(citizen: Citizen) -> Citizen:
	if citizen == null:
		return null
	if citizen.has_method("exit_keyboard_control_mode"):
		citizen.exit_keyboard_control_mode()
	else:
		citizen.keyboard_control_enabled = false
	citizen.autonomous_simulation_enabled = false
	citizen.set_manual_control_enabled(false, null)
	citizen.set_click_move_mode_enabled(false, null)
	citizen.set_simulation_lod_state("focus", true, true, 1)
	if citizen.is_inside_building():
		citizen.exit_current_building(null)
	citizen.set_physics_process(true)
	citizen.stop_travel()
	citizen.current_action = null
	return citizen


func _find_short_entry_route(world: World) -> Dictionary:
	var best: Dictionary = {}
	var best_len := INF
	for source in world.buildings:
		if source == null or _is_outdoor(source):
			continue
		for target in world.buildings:
			if target == null or target == source or _is_outdoor(target):
				continue
			var source_points := source.get_navigation_points(world, 0.0)
			var target_points := target.get_navigation_points(world, 0.0)
			var source_pos: Vector3 = source_points.get("access", source.get_entrance_pos())
			var target_pos: Vector3 = target_points.get("access", target.get_entrance_pos())
			var route: PackedVector3Array = world.get_pedestrian_path(source_pos, target_pos, source, target)
			if route.size() < 2:
				continue
			var length := _route_length(route)
			if length < 1.0 or length >= best_len:
				continue
			best_len = length
			best = {
				"source": source,
				"target": target,
				"source_pos": source_pos,
				"route": route,
			}
	return best


func _is_outdoor(building: Building) -> bool:
	return building.has_method("is_outdoor_destination") and building.is_outdoor_destination()


func _route_length(route: PackedVector3Array) -> float:
	var total := 0.0
	for index in range(1, route.size()):
		var a := route[index - 1]
		var b := route[index]
		a.y = 0.0
		b.y = 0.0
		total += a.distance_to(b)
	return total


func _print_debug(citizen: Citizen, source: Building, target: Building, route: PackedVector3Array) -> void:
	printerr("  source=%s target=%s route_points=%d" % [
		source.get_display_name() if source != null else "-",
		target.get_display_name() if target != null else "-",
		route.size()
	])
	printerr("  citizen pos=%s visible=%s travelling=%s current_location=%s inside=%s" % [
		_fmt_v3(citizen.global_position),
		str(citizen.visible),
		str(citizen.is_travelling()),
		citizen.current_location.get_display_name() if citizen.current_location != null else "-",
		str(citizen.is_inside_building())
	])
	printerr("  reached=%s failed=%s remaining=%.2f" % [
		str(citizen.has_reached_travel_target()),
		str(citizen.did_debug_last_travel_fail()),
		citizen.get_remaining_travel_distance()
	])


func _fmt_v3(pos: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [pos.x, pos.y, pos.z]
