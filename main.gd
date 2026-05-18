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
const PlayerThirdPersonCameraScript = preload("res://Simulation/Camera/PlayerThirdPersonCamera.gd")
const CameraModeManagerScript = preload("res://Simulation/Camera/CameraModeManager.gd")
const BalanceConfig = preload("res://Simulation/Config/BalanceConfig.gd")
const SimLogger = preload("res://Simulation/Logging/SimLogger.gd")
const BUILDING_OVERVIEW_REFRESH_INTERVAL_SEC := 0.5

var _runtime_controller = null
var _multiplayer_session = null
var _multiplayer_menu = null
var _player_camera: PlayerThirdPersonCamera = null
var _camera_mode_manager: CameraModeManager = null
var _enable_all_citizen_trace: bool = false
var _enable_map_snapshot_log: bool = false

func _ready() -> void:
	SimLogger.start_new_session(false)
	get_viewport().physics_object_picking = true
	_load_debug_runtime_flags()

	SceneBootstrapControllerScript.setup_scene(self, world)
	_setup_multiplayer_session()
	_setup_camera_system()

	var launch_options := MultiplayerLaunchOptionsScript.from_command_line()
	if _should_show_multiplayer_menu(launch_options):
		_show_multiplayer_menu()
	else:
		_begin_session(launch_options)

func _start_runtime() -> void:
	if _is_network_client():
		_remove_local_scene_citizens_for_client()
	elif _is_network_host():
		_remove_legacy_controlled_citizen_for_network_host()
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
		initial_citizen_count,
		_multiplayer_session,
		_camera_mode_manager
	)
	if _is_network_host():
		_multiplayer_session.ensure_local_host_player()
	elif not _is_network_client():
		_setup_offline_player()
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

func _setup_camera_system() -> void:
	_player_camera = PlayerThirdPersonCameraScript.new()
	_player_camera.name = "PlayerThirdPersonCamera"
	add_child(_player_camera)
	_camera_mode_manager = CameraModeManagerScript.new()
	_camera_mode_manager.setup(_city_camera, _player_camera, _multiplayer_session)

func get_camera_mode_manager() -> CameraModeManager:
	return _camera_mode_manager

# Offline single-player: the in-scene ControlledCitizen IS the player. It is
# permanently keyboard-controlled (camera-relative) and followed by the
# 3rd-person rig. The camera itself is owned by CameraModeManager, so keyboard
# control must NOT also grab the viewport camera.
func _setup_offline_player() -> void:
	if _controlled_citizen == null or not is_instance_valid(_controlled_citizen):
		return
	_controlled_citizen.set("accept_click_input", true)
	if _controlled_citizen.has_method("enter_keyboard_control_mode"):
		_controlled_citizen.call("enter_keyboard_control_mode", false)
	else:
		_controlled_citizen.set("keyboard_control_enabled", true)
	if _camera_mode_manager != null:
		_camera_mode_manager.set_player_target(_controlled_citizen)
	if _runtime_controller != null and _runtime_controller.has_method("refresh_citizen_lod_now"):
		_runtime_controller.refresh_citizen_lod_now()

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

func _is_network_host() -> bool:
	return _multiplayer_session != null and _multiplayer_session.is_host()

func _remove_legacy_controlled_citizen_for_network_host() -> void:
	if _controlled_citizen == null or not is_instance_valid(_controlled_citizen):
		_controlled_citizen = null
		return
	if world != null and _controlled_citizen is Citizen:
		world.unregister_citizen(_controlled_citizen as Citizen)
	_controlled_citizen.queue_free()
	_controlled_citizen = null

func _remove_local_scene_citizens_for_client() -> void:
	if world == null or get_tree() == null:
		return
	for node in get_tree().get_nodes_in_group("citizens"):
		if node is not Citizen:
			continue
		var citizen := node as Citizen
		if bool(citizen.get("network_replica_mode")) or _is_client_replica_node(citizen):
			continue
		world.unregister_citizen(citizen)
		citizen.queue_free()

func _is_client_replica_node(node: Node) -> bool:
	var current := node
	while current != null:
		if current.name == "ClientReplicas":
			return true
		current = current.get_parent()
	return false

func _input(event: InputEvent) -> void:
	if _runtime_controller != null:
		_runtime_controller.handle_input(event)
