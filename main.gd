extends Node3D

@onready var world: World = $World
@onready var _city_camera: CityBuilderCamera = $Camera3D as CityBuilderCamera
@onready var _controlled_citizen: Node3D = get_node_or_null("ControlledCitizen") as Node3D

const CITIZEN_COUNT := 15
const SELECTED_CITIZEN_TRACE_INTERVAL_SEC := 1.0
const ALL_CITIZEN_TRACE_INTERVAL_SEC := 0.5
const SEARCH_RESULT_LIMIT := 12
const SceneBootstrapControllerScript = preload("res://Simulation/Bootstrap/SceneBootstrapController.gd")
const SceneRuntimeControllerScript = preload("res://Simulation/Bootstrap/SceneRuntimeController.gd")
const MultiplayerSessionScript = preload("res://Simulation/Multiplayer/MultiplayerSession.gd")
const MultiplayerLaunchOptionsScript = preload("res://Simulation/Multiplayer/shared/MultiplayerLaunchOptions.gd")
const NetworkRoleScript = preload("res://Simulation/Multiplayer/shared/NetworkRole.gd")
const MultiplayerMenuControllerScript = preload("res://Simulation/UI/MultiplayerMenuController.gd")
const BalanceConfig = preload("res://Simulation/Config/BalanceConfig.gd")
const SimLogger = preload("res://Simulation/Logging/SimLogger.gd")
const BUILDING_OVERVIEW_REFRESH_INTERVAL_SEC := 0.5

var _runtime_controller = null
var _multiplayer_session = null
var _multiplayer_menu = null
var _enable_all_citizen_trace: bool = false
var _enable_map_snapshot_log: bool = false

func _ready() -> void:
	SimLogger.start_new_session(false)
	get_viewport().physics_object_picking = true
	_load_debug_runtime_flags()

	SceneBootstrapControllerScript.setup_scene(self, world)
	_setup_multiplayer_session()

	var launch_options := MultiplayerLaunchOptionsScript.from_command_line()
	if _should_show_multiplayer_menu(launch_options):
		_show_multiplayer_menu()
	else:
		_begin_session(launch_options)

func _start_runtime() -> void:
	if _is_network_client():
		_remove_local_scene_citizens_for_client()
	var initial_citizen_count := BalanceConfig.get_int("simulation.initial_citizen_count", CITIZEN_COUNT)
	if _is_network_client():
		initial_citizen_count = 0
	_runtime_controller = SceneRuntimeControllerScript.new()
	_runtime_controller.setup(
		self,
		world,
		_city_camera,
		_enable_all_citizen_trace,
		_enable_map_snapshot_log,
		SELECTED_CITIZEN_TRACE_INTERVAL_SEC,
		ALL_CITIZEN_TRACE_INTERVAL_SEC,
		SEARCH_RESULT_LIMIT,
		BUILDING_OVERVIEW_REFRESH_INTERVAL_SEC,
		initial_citizen_count
	)
	if not _is_network_client():
		_activate_controlled_citizen_debug_target()
	call_deferred("_log_initial_debug_snapshot")

func _load_debug_runtime_flags() -> void:
	_enable_all_citizen_trace = BalanceConfig.get_bool("debug.enable_all_citizen_trace", false)
	_enable_map_snapshot_log = BalanceConfig.get_bool("debug.enable_map_snapshot_log", false)

func _process(delta: float) -> void:
	if _multiplayer_session != null:
		_multiplayer_session.update(delta)
	if _runtime_controller != null:
		_runtime_controller.update(delta)

func _log_initial_debug_snapshot() -> void:
	if _runtime_controller != null:
		_runtime_controller.log_initial_debug_snapshot()

func _activate_controlled_citizen_debug_target() -> void:
	if _is_network_client():
		return
	if _controlled_citizen == null:
		return
	_disable_legacy_player_control()
	_controlled_citizen.set("accept_click_input", true)
	if _controlled_citizen.has_method("enter_keyboard_control_mode"):
		_controlled_citizen.call("enter_keyboard_control_mode", true)
	else:
		_controlled_citizen.set("keyboard_control_enabled", true)
		_city_camera.set_follow_target(_controlled_citizen)

func _deactivate_controlled_citizen_debug_target() -> void:
	if _controlled_citizen == null:
		return
	_controlled_citizen.set("accept_click_input", true)
	if _controlled_citizen.has_method("exit_keyboard_control_mode"):
		_controlled_citizen.call("exit_keyboard_control_mode")
	else:
		_controlled_citizen.set("keyboard_control_enabled", false)
		if _controlled_citizen is CharacterBody3D:
			(_controlled_citizen as CharacterBody3D).velocity = Vector3.ZERO
		_city_camera.clear_follow_target()

func _disable_legacy_player_control() -> void:
	if world == null:
		return
	var legacy_player := world.get_node_or_null("Player")
	if legacy_player == null:
		return
	if legacy_player.has_method("set_manual_control_enabled"):
		legacy_player.call("set_manual_control_enabled", false, world)
	if legacy_player.has_method("set_manual_control_input_locked"):
		legacy_player.call("set_manual_control_input_locked", true)

func _setup_multiplayer_session() -> void:
	_multiplayer_session = MultiplayerSessionScript.new()
	_multiplayer_session.name = "MultiplayerSession"
	add_child(_multiplayer_session)
	_multiplayer_session.bind(self, world)

# Interactive launches without an explicit --mp-host / --mp-client flag get the
# pre-game menu. Headless and CLI-role launches keep the original auto-start so
# the test suite and scripted hosting are unaffected.
func _should_show_multiplayer_menu(launch_options: Dictionary) -> bool:
	if _is_headless_runtime():
		return false
	var requested_role := NetworkRoleScript.normalize(str(launch_options.get("role", NetworkRoleScript.OFFLINE)))
	return requested_role == NetworkRoleScript.OFFLINE

func _is_headless_runtime() -> bool:
	return DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server")

func _begin_session(launch_options: Dictionary) -> void:
	_multiplayer_session.apply_options(launch_options)
	_start_runtime()

func _show_multiplayer_menu() -> void:
	_multiplayer_menu = MultiplayerMenuControllerScript.new()
	_multiplayer_menu.setup(self, _multiplayer_session, Callable(self, "_on_multiplayer_session_started"))

func _on_multiplayer_session_started() -> void:
	if _multiplayer_menu != null:
		_multiplayer_menu.close()
		_multiplayer_menu = null
	_start_runtime()

func _is_network_client() -> bool:
	return _multiplayer_session != null and _multiplayer_session.is_client()

func _remove_local_scene_citizens_for_client() -> void:
	if world == null or get_tree() == null:
		return
	for node in get_tree().get_nodes_in_group("citizens"):
		if node is not Citizen:
			continue
		var citizen := node as Citizen
		world.unregister_citizen(citizen)
		citizen.queue_free()

func _input(event: InputEvent) -> void:
	if _handle_controlled_citizen_shortcuts(event):
		return
	if _runtime_controller != null:
		_runtime_controller.handle_input(event)

func _handle_controlled_citizen_shortcuts(event: InputEvent) -> bool:
	if _is_network_client():
		return false
	if _controlled_citizen == null:
		return false
	if event is not InputEventKey:
		return false
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return false
	if key_event.keycode != KEY_F8:
		return false
	var active := bool(_controlled_citizen.get("keyboard_control_enabled"))
	if active:
		_deactivate_controlled_citizen_debug_target()
	else:
		_activate_controlled_citizen_debug_target()
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()
	return true
