extends SceneTree

## Regression for a citizen getting stuck at the road/pedestrian edge near
## the park-side crossing. The log failure showed PATH_AHEAD_SKIP_JUMPABLE
## followed by LOW_STEP_IGNORED at this coordinate, then STUCK.EXHAUSTED.

const START_POSITION: Vector3 = Vector3(19.52, 0.13, 11.90)
const TARGET_POSITION: Vector3 = Vector3(8.77, 0.16, 3.06)
const PHYSICS_HZ: float = 60.0
const MAX_SECONDS: float = 12.0
const MIN_PROGRESS_METERS: float = 0.75


func _init() -> void:
	print("=== Citizen edge step regression ===")
	print("start  = (%.2f, %.2f, %.2f)" % [START_POSITION.x, START_POSITION.y, START_POSITION.z])
	print("target = (%.2f, %.2f, %.2f)" % [TARGET_POSITION.x, TARGET_POSITION.y, TARGET_POSITION.z])
	print()

	var main_scene := load("res://Main.tscn")
	if main_scene == null:
		printerr("FAIL: cannot load Main.tscn")
		quit(1)
		return
	var main_instance: Node = main_scene.instantiate()
	root.add_child(main_instance)

	for _i in range(8):
		await process_frame
	await physics_frame
	await physics_frame

	var citizen := _find_test_citizen(main_instance)
	if citizen == null:
		printerr("FAIL: $Citizen node not found in Main.tscn")
		quit(1)
		return

	citizen.global_position = START_POSITION
	citizen.velocity = Vector3.ZERO
	citizen.force_update_transform()
	await physics_frame

	if not citizen.has_method("set_global_target"):
		printerr("FAIL: $Citizen does not expose set_global_target")
		quit(1)
		return

	var stuck_emitted := [false]
	citizen.stuck.connect(func(): stuck_emitted[0] = true)

	var ok: bool = citizen.set_global_target(TARGET_POSITION)
	if not ok:
		printerr("FAIL: set_global_target returned false")
		_print_outcome(citizen, false, 0.0)
		quit(1)
		return
	_print_initial_jump_context(citizen)

	var start_distance := _planar_distance(citizen.global_position, TARGET_POSITION)
	var max_frames := int(ceil(MAX_SECONDS * PHYSICS_HZ))
	var elapsed_frames := 0
	while elapsed_frames < max_frames:
		await physics_frame
		elapsed_frames += 1
		if stuck_emitted[0]:
			break

	var elapsed_seconds := float(elapsed_frames) / PHYSICS_HZ
	var end_distance := _planar_distance(citizen.global_position, TARGET_POSITION)
	var progress := start_distance - end_distance
	var passed := _print_outcome(citizen, stuck_emitted[0], progress)
	print("  elapsed_seconds = %.2f (budget %.1f)" % [elapsed_seconds, MAX_SECONDS])
	print()
	print("=== End edge step regression ===")
	quit(0 if passed else 1)


func _find_test_citizen(main_instance: Node) -> CharacterBody3D:
	var controlled := main_instance.get_node_or_null("ControlledCitizen")
	if controlled is CharacterBody3D:
		return _prepare_scripted_citizen(controlled as CharacterBody3D)
	var world := main_instance.get_node_or_null("World") as World
	if world != null:
		for citizen in world.citizens:
			if _is_preferred_scripted_citizen(citizen):
				return _prepare_scripted_citizen(citizen as CharacterBody3D)
		for citizen in world.citizens:
			if citizen is CharacterBody3D:
				return _prepare_scripted_citizen(citizen as CharacterBody3D)
	for node_name in ["Citizen"]:
		var node := main_instance.get_node_or_null(node_name)
		if node is CharacterBody3D:
			return _prepare_scripted_citizen(node as CharacterBody3D)
	return null


func _is_preferred_scripted_citizen(node) -> bool:
	if node == null or not (node is CharacterBody3D):
		return false
	if node.has_method("is_keyboard_control_enabled") and node.is_keyboard_control_enabled():
		return false
	return node.has_method("set_global_target")


func _prepare_scripted_citizen(citizen: CharacterBody3D) -> CharacterBody3D:
	if citizen == null:
		return null
	if citizen.has_method("exit_keyboard_control_mode"):
		citizen.exit_keyboard_control_mode()
	elif "keyboard_control_enabled" in citizen:
		citizen.keyboard_control_enabled = false
	if "autonomous_simulation_enabled" in citizen:
		citizen.autonomous_simulation_enabled = false
	if citizen.has_method("set_manual_control_enabled"):
		citizen.set_manual_control_enabled(false, null)
	if citizen.has_method("set_click_move_mode_enabled"):
		citizen.set_click_move_mode_enabled(false, null)
	if citizen.has_method("set_simulation_lod_state"):
		citizen.set_simulation_lod_state("focus", true, true, 1)
	if citizen.has_method("is_inside_building") and citizen.is_inside_building() and citizen.has_method("exit_current_building"):
		citizen.exit_current_building(null)
	if citizen.has_method("stop_travel"):
		citizen.stop_travel()
	citizen.set_physics_process(true)
	return citizen


func _print_outcome(citizen: Node, stuck_emitted: bool, progress: float) -> bool:
	var step_ups := _event_count(citizen, "JUMP", "STEP_UP")
	var low_step_ignored := _event_count(citizen, "JUMP", "LOW_STEP_IGNORED")
	var stuck_replans := _event_count(citizen, "STUCK", "REPLAN")
	var stuck_exhausted := _event_count(citizen, "STUCK", "EXHAUSTED")

	print("--- Outcome ---")
	print("  end position       = (%.2f, %.2f, %.2f)" % [
		citizen.global_position.x, citizen.global_position.y, citizen.global_position.z])
	print("  progress_meters    = %.2f (min %.2f)" % [progress, MIN_PROGRESS_METERS])
	print("  JUMP.STEP_UP       = %d" % step_ups)
	print("  LOW_STEP_IGNORED   = %d" % low_step_ignored)
	print("  STUCK.REPLAN       = %d" % stuck_replans)
	print("  STUCK.EXHAUSTED    = %d" % stuck_exhausted)

	var failures := 0
	if step_ups <= 0:
		printerr("  FAIL  JUMP.STEP_UP was not emitted")
		failures += 1
	if progress < MIN_PROGRESS_METERS:
		printerr("  FAIL  citizen did not make enough progress")
		failures += 1
	if stuck_emitted:
		printerr("  FAIL  stuck signal was emitted")
		failures += 1
	if stuck_exhausted > 0:
		printerr("  FAIL  STUCK.EXHAUSTED > 0")
		failures += 1

	print("RESULT: %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	return failures == 0


func _print_initial_jump_context(citizen: Node) -> void:
	if not "_global_path" in citizen or not "_path_index" in citizen:
		return
	var path: PackedVector3Array = citizen._global_path
	var index: int = citizen._path_index
	if path.is_empty() or index < 0 or index >= path.size():
		return
	var direct: Vector3 = path[index] - citizen.global_position
	direct.y = 0.0
	if direct.length_squared() <= 0.0001 and index + 1 < path.size():
		direct = path[index + 1] - citizen.global_position
		direct.y = 0.0
	if direct.length_squared() <= 0.0001:
		return
	direct = direct.normalized()

	var surface := "?"
	var graph := "?"
	var near_road := false
	var edge_context := false
	var allow_low_step := false
	if "_perception" in citizen and citizen._perception != null:
		surface = citizen._perception.get_surface_kind(citizen.global_position)
		near_road = citizen._perception.is_point_near_road(citizen.global_position, 0.35)
	if citizen.has_method("_get_pedestrian_graph_kind"):
		graph = citizen._get_pedestrian_graph_kind(citizen.global_position)
	if citizen.has_method("_is_pedestrian_edge_route_context"):
		edge_context = citizen._is_pedestrian_edge_route_context()
	if citizen.has_method("_should_allow_low_step_to_walkable"):
		allow_low_step = citizen._should_allow_low_step_to_walkable(direct)

	print("--- Initial low-step context ---")
	print("  path_index        = %d/%d" % [index, path.size()])
	print("  direct            = (%.2f, %.2f, %.2f)" % [direct.x, direct.y, direct.z])
	print("  surface           = %s" % surface)
	print("  graph             = %s" % graph)
	print("  near_road_0.35    = %s" % near_road)
	print("  edge_context      = %s" % edge_context)
	print("  allow_low_step    = %s" % allow_low_step)


func _event_count(citizen: Node, layer: String, event: String) -> int:
	if citizen == null:
		return 0
	if not "_logger" in citizen:
		return 0
	var logger = citizen._logger
	if logger == null or not logger.has_method("get_event_count"):
		return 0
	return int(logger.get_event_count(layer, event))


func _planar_distance(a: Vector3, b: Vector3) -> float:
	var delta := a - b
	delta.y = 0.0
	return delta.length()
