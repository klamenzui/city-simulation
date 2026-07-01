extends SceneTree

const SceneTestUtils = preload("res://tools/codex_scene_test_utils.gd")
const GoToBuildingActionScript = preload("res://Actions/GoToBuildingAction.gd")

const SETTLE_FRAMES := 30
const MIN_TRAVEL_SECONDS_PER_CASE := 40.0
const TRAVEL_SECONDS_PER_ROUTE_POINT := 2.0
const PHYSICS_HZ := 60.0
const ACTION_TICK_FRAMES := 30
const SOURCE_NAME := "Hospital"
const TARGET_NAME := "Residential 01 (Foundation)"

var failures: Array[String] = []


func _initialize() -> void:
	var main_scene := load("res://Main.tscn") as PackedScene
	if main_scene == null:
		printerr("FAIL: cannot load Main.tscn")
		quit(1)
		return
	var main := main_scene.instantiate()
	root.add_child(main)
	for _i in range(SETTLE_FRAMES):
		await process_frame
	await physics_frame

	var world := SceneTestUtils.find_world(main)
	var citizen := _find_scripted_travel_citizen(world)
	var source := _find_building_by_name(world, SOURCE_NAME)
	var targets := _find_buildings_by_name(world, TARGET_NAME)
	if source != null and not targets.is_empty():
		targets.sort_custom(func(a: Building, b: Building) -> bool:
			return source.get_entrance_pos().distance_squared_to(a.get_entrance_pos()) \
					< source.get_entrance_pos().distance_squared_to(b.get_entrance_pos())
		)
		targets = [targets[0]]
	if world == null:
		failures.append("World node not found.")
	elif citizen == null:
		failures.append("No scriptable citizen found.")
	elif source == null:
		failures.append("Source building '%s' not found." % SOURCE_NAME)
	elif targets.is_empty():
		failures.append("No target buildings named '%s' found." % TARGET_NAME)
	else:
		print("=== Building entry regression: %s -> %s (%d targets) ===" % [
			SOURCE_NAME,
			TARGET_NAME,
			targets.size(),
		])
		for target in targets:
			await _run_case(world, citizen, source, target)

	main.queue_free()
	await process_frame
	if failures.is_empty():
		print("ENTRY_REGRESSION_TEST OK cases=%d" % targets.size())
		quit(0)
		return
	for failure in failures:
		printerr("FAIL: %s" % failure)
	quit(1)


func _run_case(world: World, citizen: Citizen, source: Building, target: Building) -> void:
	if citizen.is_inside_building():
		citizen.exit_current_building(world)
	citizen.stop_travel()
	citizen.current_action = null
	citizen.enter_building(source, world)
	var action := GoToBuildingActionScript.new(target, 20)
	citizen.start_action(action, world)
	if action.is_done():
		failures.append("%s: action finished during start." % _building_case_label(target))
		return

	var source_nav := citizen.get_navigation_points_for_building(source, world)
	var source_access: Vector3 = source_nav.get("access", source.get_entrance_pos()) as Vector3
	if absf(citizen.global_position.y - source_access.y) > 0.5:
		failures.append("%s: source exit snapped above walkable access pos=%s access=%s" % [
			_building_case_label(target),
			_fmt_v3(citizen.global_position),
			_fmt_v3(source_access),
		])
		return

	var route := citizen.get_debug_travel_route_points()
	if route.size() < 2:
		failures.append("%s: no route generated." % _building_case_label(target))
		return

	var travel_budget_seconds := maxf(
			MIN_TRAVEL_SECONDS_PER_CASE,
			float(route.size()) * TRAVEL_SECONDS_PER_ROUTE_POINT
	)
	var max_frames := int(ceil(travel_budget_seconds * PHYSICS_HZ))
	for frame in range(max_frames):
		await physics_frame
		if frame % ACTION_TICK_FRAMES != 0:
			continue
		action.tick(world, citizen, world.minutes_per_tick)
		if not action.is_done():
			continue
		action.finish(world, citizen)
		if citizen.current_action == action:
			citizen.current_action = null
		break

	# A physics frame can complete the final waypoint exactly at the test
	# budget boundary. Give the action one final state-sync tick so arrival is
	# evaluated after movement has stopped.
	if not action.is_done():
		action.tick(world, citizen, world.minutes_per_tick)
	if action.is_done() and citizen.current_action == action:
		action.finish(world, citizen)
		citizen.current_action = null

	var reached := citizen.current_location == target \
			and citizen.is_inside_building() \
			and not citizen.is_travelling()
	if not reached:
		failures.append(
				("%s: stalled pos=%s target=%s remaining=%.2f route_index=%d/%d "
				+ "travelling=%s physics=%s lod=%s abort=%s nav_failed=%s location=%s") % [
			_building_case_label(target),
			_fmt_v3(citizen.global_position),
			_fmt_v3(target.get_entrance_pos()),
			citizen.get_remaining_travel_distance(),
			citizen.get_debug_travel_route_index(),
			route.size(),
			str(citizen.is_travelling()),
			str(citizen.is_physics_processing()),
			citizen.get_simulation_lod_tier(),
			action._abort_reason,
			str(citizen.did_debug_last_travel_fail()),
			str(citizen.current_location.get_path()) \
					if citizen.current_location != null else "<none>",
		])
		return

	var target_nav := citizen.get_navigation_points_for_building(target, world)
	var target_access: Vector3 = target_nav.get("access", target.get_entrance_pos()) as Vector3
	if absf(citizen.global_position.y - target_access.y) > 0.5:
		failures.append("%s: target entry anchor snapped above walkable access pos=%s access=%s" % [
			_building_case_label(target),
			_fmt_v3(citizen.global_position),
			_fmt_v3(target_access),
		])
		return

	citizen.exit_current_building(world)
	var exit_delta := citizen.global_position - target_access
	exit_delta.y = 0.0
	if exit_delta.length() > 1.0 or absf(citizen.global_position.y - target_access.y) > 0.5:
		failures.append("%s: target exit did not reappear at walkable access pos=%s access=%s" % [
			_building_case_label(target),
			_fmt_v3(citizen.global_position),
			_fmt_v3(target_access),
		])
		return
	print("  PASS %s route_points=%d" % [_building_case_label(target), route.size()])


func _find_scripted_travel_citizen(world: World) -> Citizen:
	if world == null:
		return null
	for citizen in world.citizens:
		if citizen == null or not is_instance_valid(citizen):
			continue
		if citizen.has_method("is_keyboard_control_enabled") and citizen.is_keyboard_control_enabled():
			continue
		citizen.autonomous_simulation_enabled = false
		# Keep the scripted actor inside the normal forced-focus player contract
		# so the runtime LOD controller cannot disable physics mid-regression.
		citizen.set_manual_control_enabled(true, world)
		citizen.set_click_move_mode_enabled(false, world)
		citizen.set_simulation_lod_state("focus", true, true, 1)
		citizen.set_physics_process(true)
		return citizen
	return null


func _find_building_by_name(world: World, display_name: String) -> Building:
	var matches := _find_buildings_by_name(world, display_name)
	return matches[0] if not matches.is_empty() else null


func _find_buildings_by_name(world: World, display_name: String) -> Array[Building]:
	var matches: Array[Building] = []
	if world == null:
		return matches
	for building in world.buildings:
		if building != null and is_instance_valid(building) \
				and building.get_display_name() == display_name:
			matches.append(building)
	matches.sort_custom(func(a: Building, b: Building) -> bool:
		return str(a.get_path()) < str(b.get_path())
	)
	return matches


func _building_case_label(building: Building) -> String:
	return str(building.get_path()) if building != null and building.is_inside_tree() else TARGET_NAME


func _fmt_v3(pos: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [pos.x, pos.y, pos.z]
