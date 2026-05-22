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
const MainMenuControllerScript = preload("res://Simulation/UI/MainMenuController.gd")
const SaveSlotMenuControllerScript = preload("res://Simulation/UI/SaveSlotMenuController.gd")
const SaveGameServiceScript = preload("res://Simulation/Persistence/SaveGameService.gd")
const LocaleServiceScript = preload("res://Simulation/Localization/LocaleService.gd")
const PlayerThirdPersonCameraScript = preload("res://Simulation/Camera/PlayerThirdPersonCamera.gd")
const CameraModeManagerScript = preload("res://Simulation/Camera/CameraModeManager.gd")
const MusicDirectorScript = preload("res://Simulation/Audio/MusicDirector.gd")
const BalanceConfig = preload("res://Simulation/Config/BalanceConfig.gd")
const SimLogger = preload("res://Simulation/Logging/SimLogger.gd")
const BUILDING_OVERVIEW_REFRESH_INTERVAL_SEC := 0.5

var _runtime_controller = null
var _multiplayer_session = null
var _multiplayer_menu = null
var _main_menu = null
var _save_slot_menu = null
var _pending_load_payload: Dictionary = {}
var _player_camera: PlayerThirdPersonCamera = null
var _camera_mode_manager: CameraModeManager = null
var _music_director = null
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
	if _should_show_main_menu(launch_options):
		_show_main_menu()
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
	_setup_music_director()
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

func _setup_music_director() -> void:
	if _is_headless_runtime():
		return
	if _music_director == null or not is_instance_valid(_music_director):
		_music_director = MusicDirectorScript.new()
		_music_director.name = "MusicDirector"
		add_child(_music_director)
	_music_director.bind_world(world)
	_music_director.start()

# Interactive launches without an explicit --mp-host / --mp-client flag get the
# pre-game main menu. Headless and CLI-role launches keep the original
# auto-start so the test suite and scripted hosting are unaffected.
func _should_show_main_menu(launch_options: Dictionary) -> bool:
	if _is_headless_runtime():
		return false
	var requested_role := NetworkRoleScript.normalize(str(launch_options.get("role", NetworkRoleScript.OFFLINE)))
	return requested_role == NetworkRoleScript.OFFLINE

func _is_headless_runtime() -> bool:
	return DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server")

func _begin_session(launch_options: Dictionary) -> void:
	_multiplayer_session.apply_options(launch_options)
	_start_runtime()

func _show_main_menu() -> void:
	_main_menu = MainMenuControllerScript.new()
	_main_menu.setup(
		self,
		Callable(self, "_on_main_menu_singleplayer"),
		Callable(self, "_on_main_menu_load"),
		Callable(self, "_on_main_menu_multiplayer")
	)

func _close_main_menu() -> void:
	if _main_menu != null:
		_main_menu.close()
		_main_menu = null

func _on_main_menu_singleplayer() -> void:
	_close_main_menu()
	if _multiplayer_session != null:
		_multiplayer_session.start_offline()
	_start_runtime()

func _on_main_menu_load() -> void:
	_show_save_slot_menu(SaveSlotMenuControllerScript.Mode.LOAD, Callable(self, "_on_main_menu_load_chosen"))

func _on_main_menu_load_chosen(slot: int) -> void:
	var payload := SaveGameServiceScript.read_payload(slot)
	if payload.is_empty():
		if _save_slot_menu != null:
			_save_slot_menu.set_status(LocaleServiceScript.t("save.status_read_failed") % slot)
			_save_slot_menu.set_interaction_enabled(true)
		return
	_pending_load_payload = payload
	_close_save_slot_menu()
	_close_main_menu()
	if _multiplayer_session != null:
		_multiplayer_session.start_offline()
	_start_runtime()
	# Apply runs deferred so the runtime controller finished spawning citizens.
	call_deferred("_apply_pending_load_payload")

# The main menu stays in place behind the multiplayer modal so "Zurück" can
# return to it without rebuilding state.
func _on_main_menu_multiplayer() -> void:
	_show_multiplayer_menu()

func _show_save_slot_menu(mode: int, on_chosen: Callable) -> void:
	_close_save_slot_menu()
	_save_slot_menu = SaveSlotMenuControllerScript.new()
	_save_slot_menu.setup(self, mode, on_chosen, Callable(self, "_on_save_slot_menu_cancelled"))

func _close_save_slot_menu() -> void:
	if _save_slot_menu != null:
		_save_slot_menu.close()
		_save_slot_menu = null

func _on_save_slot_menu_cancelled() -> void:
	_close_save_slot_menu()
	if _main_menu != null:
		_main_menu.reactivate()

func _show_multiplayer_menu() -> void:
	_multiplayer_menu = MultiplayerMenuControllerScript.new()
	_multiplayer_menu.setup(
		self,
		_multiplayer_session,
		Callable(self, "_on_multiplayer_session_started"),
		Callable(self, "_on_multiplayer_menu_back")
	)

func _on_multiplayer_menu_back() -> void:
	if _multiplayer_menu != null:
		_multiplayer_menu.close()
		_multiplayer_menu = null
	if _main_menu != null:
		_main_menu.reactivate()
	else:
		_show_main_menu()

func _on_multiplayer_session_started() -> void:
	if _multiplayer_menu != null:
		_multiplayer_menu.close()
		_multiplayer_menu = null
	_close_main_menu()
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
	if _handle_save_load_hotkeys(event):
		return
	if _runtime_controller != null:
		_runtime_controller.handle_input(event)

# In-game shortcuts: F5 quicksave, F9 quickload, F6 save-slot picker, F7
# load-slot picker. They only fire once the runtime is up and no menu modal
# is active, so menu navigation does not collide with hotkeys.
func _handle_save_load_hotkeys(event: InputEvent) -> bool:
	if _runtime_controller == null:
		return false
	if _main_menu != null or _multiplayer_menu != null or _save_slot_menu != null:
		return false
	if not _can_use_local_savegames():
		return false
	if event is not InputEventKey:
		return false
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return false
	match key_event.keycode:
		KEY_F5:
			_perform_save(SaveGameServiceScript.QUICKSAVE_SLOT)
			return true
		KEY_F9:
			_perform_quickload()
			return true
		KEY_F6:
			_show_save_slot_menu(SaveSlotMenuControllerScript.Mode.SAVE, Callable(self, "_on_ingame_save_chosen"))
			return true
		KEY_F7:
			_show_save_slot_menu(SaveSlotMenuControllerScript.Mode.LOAD, Callable(self, "_on_ingame_load_chosen"))
			return true
	return false

func _on_ingame_save_chosen(slot: int) -> void:
	if not _can_use_local_savegames():
		_close_save_slot_menu()
		return
	_perform_save(slot)
	_close_save_slot_menu()

func _on_ingame_load_chosen(slot: int) -> void:
	if not _can_use_local_savegames():
		_close_save_slot_menu()
		return
	var payload := SaveGameServiceScript.read_payload(slot)
	if payload.is_empty():
		if _save_slot_menu != null:
			_save_slot_menu.set_status(LocaleServiceScript.t("save.status_read_failed") % slot)
			_save_slot_menu.set_interaction_enabled(true)
		return
	_close_save_slot_menu()
	var err: int = SaveGameServiceScript.apply_payload(payload, world, self, _get_active_player())
	if err != OK:
		push_warning("Quickload failed with error %d" % err)

func _perform_save(slot: int) -> void:
	if world == null or not _can_use_local_savegames():
		return
	var err: int = SaveGameServiceScript.save_to_slot(slot, world, self, _get_active_player())
	if err != OK:
		push_warning("Save to slot %d failed with error %d" % [slot, err])

func _perform_quickload() -> void:
	if not _can_use_local_savegames():
		return
	var payload := SaveGameServiceScript.read_payload(SaveGameServiceScript.QUICKSAVE_SLOT)
	if payload.is_empty():
		var slots := SaveGameServiceScript.list_slots()
		for entry in slots:
			var info := entry as Dictionary
			if bool(info.get("exists", false)):
				payload = SaveGameServiceScript.read_payload(int(info.get("slot", 0)))
				break
	if payload.is_empty():
		return
	var err: int = SaveGameServiceScript.apply_payload(payload, world, self, _get_active_player())
	if err != OK:
		push_warning("Quickload failed with error %d" % err)

func _apply_pending_load_payload() -> void:
	if _pending_load_payload.is_empty():
		return
	var payload := _pending_load_payload
	_pending_load_payload = {}
	var err: int = SaveGameServiceScript.apply_payload(payload, world, self, _get_active_player())
	if err != OK:
		push_warning("Apply load payload failed with error %d" % err)

func _can_use_local_savegames() -> bool:
	if _multiplayer_session == null:
		return true
	return not _multiplayer_session.is_host() and not _multiplayer_session.is_client()

# Save/load is built around the offline ControlledCitizen. Multiplayer hosts
# tear that node down (see _remove_legacy_controlled_citizen_for_network_host),
# so this returns null in network sessions and the snapshot is anchored solely
# via citizen entity_ids in the snapshot itself.
func _get_active_player() -> Node3D:
	if _controlled_citizen != null and is_instance_valid(_controlled_citizen):
		return _controlled_citizen
	return null
