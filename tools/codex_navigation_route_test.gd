extends SceneTree

## Map-based regression test for the new CitizenController stack.
##
## Loads Main.tscn headless, finds a scriptable registered Citizen, teleports
## it to a known START coordinate, sets a known
## END coordinate as the global target, and ticks until ARRIVED or timeout.
##
## START / END coordinates are user-supplied (picked via the in-game
## CoordinatePickerController). They represent a real-world route on the
## current map that includes:
##   - park-side walkway start (Z ≈ 18.65)
##   - crosswalk transit at ≈ Vector3(18.87, 0.16, 17.78)
##   - building target on the south side
##
## Pass criteria are derived from the live citizen.log baseline (52 s,
## 145 NO_CANDIDATES) with margin so the current behaviour passes but
## measurable degradation fails.

const START_POSITION: Vector3 = Vector3(11.45, 0.16, 18.65)
const TARGET_POSITION: Vector3 = Vector3(21.29, 0.16, 8.40)

## Indicator waypoints supplied by the user — the route is supposed to pass
## near these. Soft check (print-only, no fail): if the citizen deviates a lot
## the avoidance is steering wrong. Reported as min planar distance to each.
const INDICATOR_WAYPOINTS: Array[Dictionary] = [
	# Mid-walkway alongside the park, near start.
	{"label": "park-walk midpoint", "pos": Vector3(11.45, 0.16, 18.65), "expect_within": 0.6},
	# Crosswalk transit point.
	{"label": "crosswalk transit", "pos": Vector3(18.87, 0.16, 17.78), "expect_within": 1.0},
]
const POSITION_SAMPLE_INTERVAL_FRAMES: int = 4  # ~15 Hz at 60 Hz physics

## Hard time budget. Live trip was 52 s; a 90 s budget allows for headless
## frame jitter and gives a clear FAIL signal if travel grinds to a halt.
const MAX_TRAVEL_SECONDS: float = 90.0
## Pass thresholds. Pre-fix baseline was 145-200 NO_CANDIDATES because the
## replan timer kept firing every 0.18s after FALLBACK_GLOBAL. After the
## fallback-cooldown fix (2026-04-27) the count dropped to ~40. Limit set
## to 80 — fails any regression that doubles failed-replan frequency.
const MAX_NO_CANDIDATES: int = 80
const MAX_STUCK_REPLAN: int = 2
## Headless physics tick rate. Godot default is 60 Hz; we drive the loop
## manually so tests run as fast as the engine can chew through frames.
const PHYSICS_HZ: float = 60.0


func _init() -> void:
	print("=== Citizen navigation route test ===")
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

	# Let the scene initialize: World setup, citizen spawn, navigation map.
	for _i in range(8):
		await process_frame
	await physics_frame
	await physics_frame

	var citizen := _find_test_citizen(main_instance)
	if citizen == null:
		printerr("FAIL: $Citizen node not found in Main.tscn")
		quit(1)
		return

	# Teleport to start. The CharacterBody3D needs a force_update_transform
	# pulse so the next physics frame sees the new position.
	citizen.global_position = START_POSITION
	citizen.velocity = Vector3.ZERO
	citizen.force_update_transform()
	await physics_frame

	if not citizen.has_method("set_global_target"):
		printerr("FAIL: $Citizen does not expose set_global_target — wrong scene?")
		quit(1)
		return

	# Wire signals + dispatch the target.
	var arrived := [false]
	var stuck_emitted := [false]
	citizen.target_reached.connect(func(): arrived[0] = true)
	citizen.stuck.connect(func(): stuck_emitted[0] = true)

	var ok: bool = citizen.set_global_target(TARGET_POSITION)
	if not ok:
		printerr("FAIL: set_global_target returned false (no path?)")
		_print_outcome(citizen, false, false, 0.0)
		quit(1)
		return
	_print_global_path(citizen)

	# Tick the physics loop until ARRIVED or timeout. Sample positions for the
	# indicator-waypoint soft check.
	var max_frames := int(ceil(MAX_TRAVEL_SECONDS * PHYSICS_HZ))
	var elapsed_frames := 0
	var samples: Array[Vector3] = []
	var path_samples: Array[String] = []
	while elapsed_frames < max_frames:
		await physics_frame
		elapsed_frames += 1
		if (elapsed_frames % POSITION_SAMPLE_INTERVAL_FRAMES) == 0:
			samples.append(citizen.global_position)
		if (elapsed_frames % int(PHYSICS_HZ)) == 0 and "_path_index" in citizen:
			path_samples.append("t=%.0f idx=%d pos=%s" % [
				float(elapsed_frames) / PHYSICS_HZ,
				int(citizen._path_index),
				_fmt_vec3(citizen.global_position)
			])
		if arrived[0] or stuck_emitted[0]:
			break

	var elapsed_seconds := float(elapsed_frames) / PHYSICS_HZ
	var passed := _print_outcome(citizen, arrived[0], stuck_emitted[0], elapsed_seconds)
	_print_path_samples(path_samples)
	_print_indicator_waypoints(samples)
	print()
	print("=== End route test ===")
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


func _print_outcome(citizen: Node, arrived: bool, stuck_emitted: bool, elapsed_seconds: float) -> bool:
	var no_candidates := _event_count(citizen, "LOCAL_GRID", "NO_CANDIDATES")
	var stuck_replans := _event_count(citizen, "STUCK", "REPLAN")
	var stuck_exhausted := _event_count(citizen, "STUCK", "EXHAUSTED")
	var jumps_fired := _event_count(citizen, "JUMP", "FIRED")
	var build_fails := _event_count(citizen, "LOCAL_GRID", "BUILD_FAIL")
	var path_fallbacks := _event_count(citizen, "GLOBAL", "PATH_FALLBACK_STRAIGHT")

	print("--- Outcome ---")
	print("  arrived         = %s" % arrived)
	print("  stuck_emitted   = %s" % stuck_emitted)
	print("  elapsed_seconds = %.2f (budget %.1f)" % [elapsed_seconds, MAX_TRAVEL_SECONDS])
	print("  end position    = (%.2f, %.2f, %.2f)" % [
		citizen.global_position.x, citizen.global_position.y, citizen.global_position.z])
	if "_path_index" in citizen and "_global_path" in citizen:
		var path: PackedVector3Array = citizen._global_path
		var path_index: int = int(citizen._path_index)
		print("  path_index      = %d/%d" % [path_index, maxi(path.size() - 1, 0)])
		if path_index >= 0 and path_index < path.size():
			var next_point := path[path_index]
			print("  next waypoint   = (%.2f, %.2f, %.2f) kind=%s" % [
				next_point.x, next_point.y, next_point.z,
				citizen._get_pedestrian_graph_kind(next_point) if citizen.has_method("_get_pedestrian_graph_kind") else "-"
			])
	if "_perception" in citizen and citizen._perception != null:
		print("  end surface     = %s" % str(citizen._perception.get_surface_kind(citizen.global_position)))
	print("  NO_CANDIDATES   = %d (limit %d)" % [no_candidates, MAX_NO_CANDIDATES])
	print("  STUCK.REPLAN    = %d (limit %d)" % [stuck_replans, MAX_STUCK_REPLAN])
	print("  STUCK.EXHAUSTED = %d" % stuck_exhausted)
	print("  JUMP.FIRED      = %d" % jumps_fired)
	print("  BUILD_FAIL      = %d" % build_fails)
	print("  PATH_FALLBACK   = %d" % path_fallbacks)

	var failures := 0
	if not arrived:
		printerr("  FAIL  arrived=false (citizen did not reach target)")
		failures += 1
	if stuck_emitted:
		printerr("  FAIL  stuck signal was emitted")
		failures += 1
	if elapsed_seconds > MAX_TRAVEL_SECONDS:
		printerr("  FAIL  exceeded time budget")
		failures += 1
	if no_candidates > MAX_NO_CANDIDATES:
		printerr("  FAIL  NO_CANDIDATES count above limit")
		failures += 1
	if stuck_replans > MAX_STUCK_REPLAN:
		printerr("  FAIL  STUCK.REPLAN count above limit")
		failures += 1
	if stuck_exhausted > 0:
		printerr("  FAIL  STUCK.EXHAUSTED > 0")
		failures += 1
	if build_fails > 0:
		printerr("  FAIL  BUILD_FAIL > 0")
		failures += 1

	print("RESULT: %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	return failures == 0


func _print_indicator_waypoints(samples: Array[Vector3]) -> void:
	if samples.is_empty():
		return
	print()
	print("--- Indicator waypoints (avoidance correctness, soft check) ---")
	for waypoint in INDICATOR_WAYPOINTS:
		var label: String = str(waypoint.get("label", "?"))
		var pos: Vector3 = waypoint.get("pos", Vector3.ZERO) as Vector3
		var expect_within: float = float(waypoint.get("expect_within", 1.0))
		var min_dist := INF
		for sample in samples:
			var off := sample - pos
			off.y = 0.0
			var d := off.length()
			if d < min_dist:
				min_dist = d
		var status := "ok" if min_dist <= expect_within else "FAR"
		print("  %-22s closest=%.2f m  (expected within %.2f) [%s]" % [
			label, min_dist, expect_within, status])


func _print_path_samples(path_samples: Array[String]) -> void:
	if path_samples.is_empty():
		return
	print()
	print("--- Path samples ---")
	for sample in path_samples.slice(maxi(path_samples.size() - 12, 0), path_samples.size()):
		print("  ", sample)


func _print_global_path(citizen: Node) -> void:
	if citizen == null or not "_global_path" in citizen:
		return
	var path: PackedVector3Array = citizen._global_path
	print("--- Global path ---")
	print("  points = %d" % path.size())
	for i in range(path.size()):
		var point := path[i]
		var kind := "-"
		if citizen.has_method("_get_pedestrian_graph_kind"):
			kind = str(citizen._get_pedestrian_graph_kind(point))
			if kind.is_empty():
				kind = "-"
		print("  %02d %s kind=%s" % [i, _fmt_vec3(point), kind])
	print()


func _event_count(citizen: Node, layer: String, event: String) -> int:
	# Reach into the controller's logger via the private member.
	# Acceptable for a test — the logger is the source of truth for events.
	if citizen == null:
		return 0
	if not "_logger" in citizen:
		return 0
	var logger = citizen._logger
	if logger == null or not logger.has_method("get_event_count"):
		return 0
	return int(logger.get_event_count(layer, event))


func _fmt_vec3(value: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [value.x, value.y, value.z]
