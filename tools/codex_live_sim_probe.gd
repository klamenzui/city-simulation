extends SceneTree

const SimLogger = preload("res://Simulation/Logging/SimLogger.gd")

const DEFAULT_RUN_SECONDS := 300.0
const MIN_RUN_SECONDS := 10.0
const DEFAULT_START_HOUR := -1
const DEFAULT_START_MINUTE := 0
const DEFAULT_START_DAY := 1
const DEFAULT_FORCE_FUN_CITIZENS := 0
const TARGET_FUN_LEVEL := 5.0
const TARGET_ENERGY_LEVEL := 72.0
const TARGET_HUNGER_LEVEL := 10.0
const TARGET_HEALTH_LEVEL := 100.0

func _resolve_run_seconds() -> float:
	var raw_value := OS.get_environment("CODEX_LIVE_SIM_RUN_SECONDS").strip_edges()
	if raw_value == "":
		return DEFAULT_RUN_SECONDS
	if not raw_value.is_valid_float():
		return DEFAULT_RUN_SECONDS
	return clampf(raw_value.to_float(), MIN_RUN_SECONDS, DEFAULT_RUN_SECONDS)

func _resolve_env_int(name: String, default_value: int) -> int:
	var raw_value := OS.get_environment(name).strip_edges()
	if raw_value == "":
		return default_value
	return raw_value.to_int()

func _configure_probe_world(world: World) -> Dictionary:
	var start_hour := clampi(_resolve_env_int("CODEX_LIVE_SIM_START_HOUR", DEFAULT_START_HOUR), -1, 23)
	var start_minute := clampi(_resolve_env_int("CODEX_LIVE_SIM_START_MINUTE", DEFAULT_START_MINUTE), 0, 59)
	var start_day := maxi(_resolve_env_int("CODEX_LIVE_SIM_START_DAY", DEFAULT_START_DAY), 1)
	if start_hour >= 0:
		world.time.day = start_day
		world.time.minutes_total = start_hour * 60 + start_minute

	var forced_fun_citizens := maxi(_resolve_env_int("CODEX_LIVE_SIM_FORCE_FUN_CITIZENS", DEFAULT_FORCE_FUN_CITIZENS), 0)
	var forced_names: Array[String] = []
	if forced_fun_citizens > 0:
		for citizen in world.citizens:
			if citizen == null:
				continue
			if citizen.favorite_park == null:
				continue
			if citizen.job != null and citizen.job.workplace == citizen.favorite_park:
				continue
			citizen.needs.fun = TARGET_FUN_LEVEL
			citizen.needs.energy = maxf(citizen.needs.energy, TARGET_ENERGY_LEVEL)
			citizen.needs.hunger = minf(citizen.needs.hunger, TARGET_HUNGER_LEVEL)
			citizen.needs.health = maxf(citizen.needs.health, TARGET_HEALTH_LEVEL)
			citizen.current_action = null
			citizen.decision_cooldown_left = 0
			if citizen.has_method("clear_rest_pose"):
				citizen.clear_rest_pose(true)
			forced_names.append(citizen.citizen_name)
			if forced_names.size() >= forced_fun_citizens:
				break

	return {
		"start_day": world.time.day,
		"start_time": world.time.get_time_string(),
		"forced_fun_citizens": forced_names,
	}

func _init() -> void:
	var run_seconds := _resolve_run_seconds()
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

	var config := _configure_probe_world(world)

	print("LIVE_SIM start run_seconds=", run_seconds, " start_day=", config.get("start_day", world.time.day), " start_time=", config.get("start_time", world.time.get_time_string()), " forced_fun=", config.get("forced_fun_citizens", []), " log=", SimLogger.get_log_path())
	SimLogger.log("[LIVE_SIM] start run_seconds=%s start_day=%s start_time=%s forced_fun=%s" % [
		str(run_seconds),
		str(config.get("start_day", world.time.day)),
		str(config.get("start_time", world.time.get_time_string())),
		str(config.get("forced_fun_citizens", [])),
	])

	await create_timer(run_seconds).timeout

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
