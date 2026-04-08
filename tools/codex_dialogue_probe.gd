extends SceneTree

const SimLogger = preload("res://Simulation/Logging/SimLogger.gd")
const CitizenScript = preload("res://Entities/Citizens/Citizen.gd")
const ResidentialBuildingScript = preload("res://Entities/Buildings/ResidentialBuilding.gd")
const RestaurantScript = preload("res://Entities/Buildings/Restaurant.gd")
const SupermarketScript = preload("res://Entities/Buildings/Supermarket.gd")
const ShopScript = preload("res://Entities/Buildings/Shop.gd")
const CinemaScript = preload("res://Entities/Buildings/Cinema.gd")
const ParkScript = preload("res://Entities/Buildings/Park.gd")
const WorldScript = preload("res://Simulation/World.gd")
const ActionScript = preload("res://Actions/Action.gd")
const CitizenConversationManagerScript = preload("res://Simulation/Conversation/CitizenConversationManager.gd")
const LocalDialogueRuntimeServiceScript = preload("res://Simulation/AI/LocalDialogueRuntimeService.gd")

const DEFAULT_SCENARIO_PATH := "res://tools/dialogue_probe_default.json"
const DEFAULT_RUNTIME_WAIT_SEC := 20.0
const DEFAULT_REPLY_WAIT_SEC := 25.0
const STEP_SEC := 0.1

class MockSelectionStateController:
	extends RefCounted

	var selected_citizen: Citizen = null
	var controlled_citizen: Citizen = null
	var player_avatar: Citizen = null
	var player_control_active: bool = false
	var player_control_input_locked: bool = false

	func get_selected_citizen() -> Citizen:
		return selected_citizen if selected_citizen != null and is_instance_valid(selected_citizen) else null

	func get_controlled_citizen() -> Citizen:
		return controlled_citizen if controlled_citizen != null and is_instance_valid(controlled_citizen) else null

	func get_player_avatar() -> Citizen:
		return player_avatar if player_avatar != null and is_instance_valid(player_avatar) else null

	func is_player_control_active() -> bool:
		return player_control_active and get_player_avatar() != null

	func set_player_control_input_locked(locked: bool) -> void:
		player_control_input_locked = locked
		var avatar := get_player_avatar()
		if avatar != null and avatar.has_method("set_manual_control_input_locked"):
			avatar.set_manual_control_input_locked(locked)

	func is_player_control_input_locked() -> bool:
		return player_control_input_locked

var _harness_root: Node3D = null

func _initialize() -> void:
	_harness_root = Node3D.new()
	get_root().add_child(_harness_root)
	call_deferred("_run_probe")

func _run_probe() -> void:
	SimLogger.start_new_session(false)

	var options := _parse_options()
	var scenario := _load_scenario(str(options.get("scenario_path", DEFAULT_SCENARIO_PATH)))
	if scenario.is_empty():
		push_error("DIALOGUE_PROBE failed to load scenario")
		quit(2)
		return

	var override_turns: Array[String] = options.get("turns", []) as Array[String]
	if not override_turns.is_empty():
		scenario["turns"] = override_turns.duplicate()

	var world := _new_world()
	var camera := _new_camera(Vector3(0.0, 10.0, 14.0), Vector3.ZERO)
	var selection := MockSelectionStateController.new()

	_apply_world_scenario(world, scenario)
	var places := _spawn_probe_places(world, scenario)
	await process_frame
	var player_avatar := _spawn_probe_player(world, scenario)
	var citizen := _spawn_probe_citizen(world, scenario, places)

	selection.player_avatar = player_avatar
	selection.controlled_citizen = player_avatar
	selection.selected_citizen = citizen
	selection.player_control_active = true
	player_avatar.set_manual_control_enabled(true, world)

	var runtime_service = LocalDialogueRuntimeServiceScript.new()
	_harness_root.add_child(runtime_service)
	runtime_service.setup({
		"runtime": {
			"force_template_mode": bool(options.get("force_template", false))
		},
		"startup": {
			"auto_start_on_game_boot": true,
			"disabled_in_headless": false,
			"prewarm_on_boot": false
		}
	}, false)

	var manager = CitizenConversationManagerScript.new()
	manager.setup(world, camera, selection)
	manager.bind_dialogue_runtime(runtime_service)

	print("DIALOGUE_PROBE scenario=%s" % str(options.get("scenario_path", DEFAULT_SCENARIO_PATH)))
	print("DIALOGUE_PROBE log=%s ai_log=%s" % [SimLogger.get_log_path(), SimLogger.get_ai_log_path()])

	if not await _wait_for_runtime_ready(runtime_service, manager, float(options.get("runtime_wait_sec", DEFAULT_RUNTIME_WAIT_SEC)), bool(options.get("allow_fallback", false))):
		push_error("DIALOGUE_PROBE runtime did not become usable in time: %s" % runtime_service.get_status_label())
		_cleanup_world(world)
		quit(3)
		return

	var ui_state := runtime_service.get_ui_runtime_state()
	print("DIALOGUE_PROBE runtime=%s models=%s" % [
		runtime_service.get_status_label(),
		str(ui_state.get("selected_models", []))
	])

	manager.update(STEP_SEC)
	var started_session := manager.begin_player_dialog(citizen)
	if not bool(started_session.get("active", false)):
		push_error("DIALOGUE_PROBE failed to start dialog: %s" % str(started_session.get("error", "unknown")))
		_cleanup_world(world)
		quit(4)
		return

	var turns: Array = scenario.get("turns", []) as Array
	for raw_turn in turns:
		var player_line := str(raw_turn).strip_edges()
		if player_line.is_empty():
			continue
		print("PLAYER> %s" % player_line)
		manager.submit_player_dialog_message(citizen, player_line)
		var session := await _wait_for_player_reply(manager, runtime_service, citizen, float(options.get("reply_wait_sec", DEFAULT_REPLY_WAIT_SEC)))
		if session.is_empty():
			push_error("DIALOGUE_PROBE timed out waiting for NPC reply")
			_cleanup_world(world)
			quit(5)
			return
		var messages: Array = session.get("messages", []) as Array
		var last_reply := ""
		if not messages.is_empty() and messages[messages.size() - 1] is Dictionary:
			last_reply = str((messages[messages.size() - 1] as Dictionary).get("text", ""))
		print("NPC[%s|%s]> %s" % [
			str(session.get("last_reply_source", "")),
			str(session.get("last_reply_model", "")),
			last_reply
		])

	manager.close_player_dialog(citizen, "probe_finished")
	_cleanup_world(world)
	print("DIALOGUE_PROBE done ai_log=%s" % SimLogger.get_ai_log_path())
	quit(0)

func _parse_options() -> Dictionary:
	var args := OS.get_cmdline_user_args()
	var turns: Array[String] = []
	var options := {
		"scenario_path": DEFAULT_SCENARIO_PATH,
		"force_template": false,
		"allow_fallback": false,
		"runtime_wait_sec": DEFAULT_RUNTIME_WAIT_SEC,
		"reply_wait_sec": DEFAULT_REPLY_WAIT_SEC,
		"turns": turns
	}
	var idx := 0
	while idx < args.size():
		var token := str(args[idx])
		match token:
			"--scenario":
				if idx + 1 < args.size():
					options["scenario_path"] = str(args[idx + 1])
					idx += 1
			"--turn":
				if idx + 1 < args.size():
					turns.append(str(args[idx + 1]))
					idx += 1
			"--template":
				options["force_template"] = true
			"--allow-fallback":
				options["allow_fallback"] = true
			"--runtime-wait":
				if idx + 1 < args.size() and str(args[idx + 1]).is_valid_float():
					options["runtime_wait_sec"] = maxf(str(args[idx + 1]).to_float(), 1.0)
					idx += 1
			"--reply-wait":
				if idx + 1 < args.size() and str(args[idx + 1]).is_valid_float():
					options["reply_wait_sec"] = maxf(str(args[idx + 1]).to_float(), 1.0)
					idx += 1
			_:
				pass
		idx += 1
	return options

func _load_scenario(path_hint: String) -> Dictionary:
	var path := path_hint.strip_edges()
	if path.is_empty():
		path = DEFAULT_SCENARIO_PATH
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null and not path.begins_with("res://"):
		file = FileAccess.open(ProjectSettings.globalize_path(path), FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed as Dictionary if parsed is Dictionary else {}

func _apply_world_scenario(world: World, scenario: Dictionary) -> void:
	var world_config := scenario.get("world", {}) as Dictionary
	world.time.day = int(world_config.get("day", 1))
	world.time.minutes_total = int(world_config.get("hour", 12)) * 60 + int(world_config.get("minute", 0))

func _spawn_probe_places(world: World, scenario: Dictionary) -> Dictionary:
	var places_config := scenario.get("places", {}) as Dictionary
	var places := {}
	places["home"] = _new_residential(
		str((places_config.get("home", {}) as Dictionary).get("name", "Wohnhaus am Platz")),
		_to_vec3((places_config.get("home", {}) as Dictionary).get("position", [0.5, 0.0, 2.0]))
	)
	places["restaurant"] = _new_restaurant(
		str((places_config.get("restaurant", {}) as Dictionary).get("name", "Cafe Nord")),
		_to_vec3((places_config.get("restaurant", {}) as Dictionary).get("position", [2.8, 0.0, 0.0]))
	)
	places["supermarket"] = _new_supermarket(
		str((places_config.get("supermarket", {}) as Dictionary).get("name", "Nordmarkt")),
		_to_vec3((places_config.get("supermarket", {}) as Dictionary).get("position", [0.7, 0.0, 0.2]))
	)
	places["shop"] = _new_shop(
		str((places_config.get("shop", {}) as Dictionary).get("name", "Kiosk am Eck")),
		_to_vec3((places_config.get("shop", {}) as Dictionary).get("position", [3.3, 0.0, 0.0]))
	)
	places["cinema"] = _new_cinema(
		str((places_config.get("cinema", {}) as Dictionary).get("name", "Lichtspielhaus")),
		_to_vec3((places_config.get("cinema", {}) as Dictionary).get("position", [4.5, 0.0, 0.0]))
	)
	places["park"] = _new_park(
		str((places_config.get("park", {}) as Dictionary).get("name", "Stadtpark")),
		_to_vec3((places_config.get("park", {}) as Dictionary).get("position", [5.5, 0.0, 0.0]))
	)
	for building in places.values():
		if building is Building:
			world.register_building(building as Building)
	return places

func _spawn_probe_player(world: World, scenario: Dictionary) -> Citizen:
	var player_config := scenario.get("player", {}) as Dictionary
	var player_avatar := _new_citizen(
		str(player_config.get("name", "Player")),
		_to_vec3(player_config.get("position", [0.0, 0.0, 0.0]))
	)
	world.register_citizen(player_avatar)
	return player_avatar

func _spawn_probe_citizen(world: World, scenario: Dictionary, places: Dictionary) -> Citizen:
	var citizen_config := scenario.get("citizen", {}) as Dictionary
	var citizen := _new_citizen(
		str(citizen_config.get("name", "Jonas Schmidt")),
		_to_vec3(citizen_config.get("position", [1.5, 0.0, 0.0]))
	)
	world.register_citizen(citizen)
	citizen.wallet.balance = int(citizen_config.get("wallet_balance", 145))
	citizen.work_motivation = float(citizen_config.get("work_motivation", 0.8))
	citizen.park_interest = float(citizen_config.get("park_interest", 0.2))
	var needs := citizen_config.get("needs", {}) as Dictionary
	citizen.needs.hunger = float(needs.get("hunger", citizen.needs.hunger))
	citizen.needs.energy = float(needs.get("energy", citizen.needs.energy))
	citizen.needs.fun = float(needs.get("fun", citizen.needs.fun))
	citizen.needs.health = float(needs.get("health", citizen.needs.health))

	citizen.home = places.get("home", null) as ResidentialBuilding
	citizen.favorite_restaurant = places.get("restaurant", null) as Restaurant
	citizen.favorite_supermarket = places.get("supermarket", null) as Supermarket
	citizen.favorite_shop = places.get("shop", null) as Shop
	citizen.favorite_cinema = places.get("cinema", null) as Cinema
	citizen.favorite_park = places.get("park", null) as Building

	var current_location_key := str(citizen_config.get("current_location", "street"))
	if current_location_key != "street" and places.has(current_location_key):
		citizen.current_location = places.get(current_location_key, null) as Building
	else:
		citizen.current_location = null

	var travel_target_key := str(citizen_config.get("travel_target", "")).strip_edges()
	if not travel_target_key.is_empty() and places.has(travel_target_key):
		var target_building := places.get(travel_target_key, null) as Building
		citizen.current_action = ActionScript.new(999)
		citizen.current_action.label = "GoTo"
		citizen._is_travelling = true
		citizen._travel_target_building = target_building
		citizen._travel_target = target_building.global_position if target_building != null else citizen.global_position

	return citizen

func _wait_for_runtime_ready(runtime_service: LocalDialogueRuntimeService, manager, timeout_sec: float, allow_fallback: bool) -> bool:
	var elapsed := 0.0
	while elapsed < timeout_sec:
		runtime_service.update(STEP_SEC)
		manager.update(STEP_SEC)
		var ui_state := runtime_service.get_ui_runtime_state()
		var status := str(ui_state.get("status", ""))
		if status == "ready":
			return true
		if allow_fallback and status == "template_only":
			return true
		await create_timer(STEP_SEC).timeout
		elapsed += STEP_SEC
	return false

func _wait_for_player_reply(manager, runtime_service: LocalDialogueRuntimeService, citizen: Citizen, timeout_sec: float) -> Dictionary:
	var elapsed := 0.0
	while elapsed < timeout_sec:
		runtime_service.update(STEP_SEC)
		manager.update(STEP_SEC)
		var session: Dictionary = manager.get_player_dialog_session(citizen)
		if not bool(session.get("pending_reply", false)):
			return session
		await create_timer(STEP_SEC).timeout
		elapsed += STEP_SEC
	return {}

func _new_world() -> World:
	var world: World = WorldScript.new()
	_harness_root.add_child(world)
	if world._timer != null:
		world._timer.stop()
	return world

func _new_camera(position: Vector3, look_target: Vector3) -> Camera3D:
	var camera := Camera3D.new()
	camera.name = "ProbeCamera"
	_harness_root.add_child(camera)
	camera.global_position = position
	camera.look_at(look_target, Vector3.UP)
	return camera

func _new_residential(building_name: String, spawn_position: Vector3) -> ResidentialBuilding:
	var building: ResidentialBuilding = ResidentialBuildingScript.new()
	_prepare_building(building, building_name, spawn_position)
	building.capacity = 4
	return building

func _new_restaurant(building_name: String, spawn_position: Vector3) -> Restaurant:
	var building: Restaurant = RestaurantScript.new()
	_prepare_building(building, building_name, spawn_position)
	return building

func _new_supermarket(building_name: String, spawn_position: Vector3) -> Supermarket:
	var building: Supermarket = SupermarketScript.new()
	_prepare_building(building, building_name, spawn_position)
	return building

func _new_shop(building_name: String, spawn_position: Vector3) -> Shop:
	var building: Shop = ShopScript.new()
	_prepare_building(building, building_name, spawn_position)
	return building

func _new_cinema(building_name: String, spawn_position: Vector3) -> Cinema:
	var building: Cinema = CinemaScript.new()
	_prepare_building(building, building_name, spawn_position)
	return building

func _new_park(building_name: String, spawn_position: Vector3) -> Park:
	var building: Park = ParkScript.new()
	_prepare_building(building, building_name, spawn_position)
	return building

func _prepare_building(building: Building, building_name: String, spawn_position: Vector3) -> void:
	building.name = building_name
	building.building_name = building_name
	var entrance := Node3D.new()
	entrance.name = "Entrance"
	entrance.position = Vector3(0.0, 0.0, 1.1)
	building.add_child(entrance)
	_harness_root.add_child(building)
	building.global_position = spawn_position

func _new_citizen(citizen_name: String, spawn_position: Vector3) -> Citizen:
	var citizen: Citizen = CitizenScript.new()
	citizen.name = citizen_name
	citizen.citizen_name = citizen_name
	_harness_root.add_child(citizen)
	citizen.global_position = spawn_position
	return citizen

func _to_vec3(value: Variant) -> Vector3:
	if value is Array:
		var arr := value as Array
		if arr.size() >= 3:
			return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
	return Vector3.ZERO

func _cleanup_world(world: World) -> void:
	if world != null and world._timer != null:
		world._timer.stop()
	if is_instance_valid(_harness_root):
		_harness_root.queue_free()
