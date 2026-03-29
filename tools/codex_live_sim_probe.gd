extends SceneTree

const SimLogger = preload("res://Simulation/Logging/SimLogger.gd")

const RUN_SECONDS := 300.0

func _init() -> void:
	var main_scene: PackedScene = load("res://Main.tscn")
	if main_scene == null:
		push_error("Failed to load Main.tscn")
		quit(1)
		return

	var main: Node = main_scene.instantiate()
	root.add_child(main)

	await process_frame
	await process_frame
	await process_frame

	var world := main.get_node_or_null("World") as World
	if world == null:
		push_error("World node not found")
		quit(1)
		return

	print("LIVE_SIM start run_seconds=", RUN_SECONDS, " log=", SimLogger.get_log_path())
	SimLogger.log("[LIVE_SIM] start run_seconds=%s" % str(RUN_SECONDS))

	await create_timer(RUN_SECONDS).timeout

	var building_state_counts := {
		"open": 0,
		"struggling": 0,
		"underfunded": 0,
		"closed": 0,
	}
	for building in world.buildings:
		if building == null:
			continue
		if building.has_method("is_closed") and building.is_closed():
			building_state_counts["closed"] += 1
		elif building.has_method("is_underfunded") and building.is_underfunded():
			building_state_counts["underfunded"] += 1
		elif building.has_method("is_struggling") and building.is_struggling():
			building_state_counts["struggling"] += 1
		else:
			building_state_counts["open"] += 1

	var travelling := 0
	var inside := 0
	var falling := 0
	for citizen in world.citizens:
		if citizen == null:
			continue
		if citizen.has_method("is_debug_travelling") and citizen.is_debug_travelling():
			travelling += 1
		if citizen.has_method("is_inside_building") and citizen.is_inside_building():
			inside += 1
		if not citizen.is_on_floor():
			falling += 1

	print(
		"LIVE_SIM summary day=",
		world.time.current_day,
		" time=",
		world.time.get_time_string(),
		" buildings=",
		building_state_counts,
		" travelling=",
		travelling,
		" inside=",
		inside,
		" falling=",
		falling
	)
	SimLogger.log(
		"[LIVE_SIM] summary day=%d time=%s buildings=%s travelling=%d inside=%d falling=%d" % [
			world.time.current_day,
			world.time.get_time_string(),
			str(building_state_counts),
			travelling,
			inside,
			falling,
		]
	)

	main.queue_free()
	await process_frame
	quit()
