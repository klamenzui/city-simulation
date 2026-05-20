extends RefCounted
class_name SelectionStateController

## Selection + player-avatar control.
##
## Direct WASD/click control of an arbitrary selected citizen was removed: only
## the real local player avatar (host/client networked player, or the offline
## ControlledCitizen) can be controlled. Clicking citizens/buildings only drives
## selection + the debug panel. The camera is owned by CameraModeManager.

var world: World = null
var camera_mode_manager = null
var debug_panel: DebugPanel = null
var hud_controller = null
var runtime_debug_logger = null
var selection_debug_controller = null
var building_status_badge_controller = null

var _selected_citizen: Citizen = null
var _selected_building: Building = null
var _controlled_citizen: Citizen = null
var _player_avatar: Citizen = null

func setup(
	world_ref: World,
	camera_mode_manager_ref,
	debug_panel_ref: DebugPanel,
	hud_controller_ref,
	runtime_debug_logger_ref,
	selection_debug_controller_ref,
	building_status_badge_controller_ref
) -> void:
	world = world_ref
	camera_mode_manager = camera_mode_manager_ref
	debug_panel = debug_panel_ref
	hud_controller = hud_controller_ref
	runtime_debug_logger = runtime_debug_logger_ref
	selection_debug_controller = selection_debug_controller_ref
	building_status_badge_controller = building_status_badge_controller_ref
	_player_avatar = _resolve_player_avatar()
	_refresh_hud_control_mode()
	_refresh_hud_player_control()

func get_selected_citizen() -> Citizen:
	return _selected_citizen if _selected_citizen != null and is_instance_valid(_selected_citizen) else null

func get_selected_building() -> Building:
	return _selected_building if _selected_building != null and is_instance_valid(_selected_building) else null

func get_controlled_citizen() -> Citizen:
	return _controlled_citizen if _controlled_citizen != null and is_instance_valid(_controlled_citizen) else null

func get_player_avatar() -> Citizen:
	return _player_avatar if _player_avatar != null and is_instance_valid(_player_avatar) else null

func get_camera_player_target() -> Citizen:
	if camera_mode_manager == null or not camera_mode_manager.has_method("get_player_target"):
		return null
	var target = camera_mode_manager.get_player_target()
	if target is Citizen and is_instance_valid(target):
		return target as Citizen
	return null

func is_player_control_active() -> bool:
	var player_avatar := get_player_avatar()
	return player_avatar != null and _controlled_citizen == player_avatar

func is_player_control_input_locked() -> bool:
	var player_avatar := _get_player_input_lock_target()
	if player_avatar == null or not player_avatar.has_method("is_manual_control_input_locked"):
		return false
	return bool(player_avatar.is_manual_control_input_locked())

func set_player_control_input_locked(locked: bool) -> void:
	var player_avatar := _get_player_input_lock_target()
	if player_avatar == null or not player_avatar.has_method("set_manual_control_input_locked"):
		return
	player_avatar.set_manual_control_input_locked(locked)
	_refresh_hud_control_mode()

func is_camera_input_locked() -> bool:
	if camera_mode_manager == null or not camera_mode_manager.has_method("is_input_locked"):
		return false
	return bool(camera_mode_manager.is_input_locked())

func set_camera_input_locked(locked: bool) -> void:
	if camera_mode_manager == null or not camera_mode_manager.has_method("set_input_locked"):
		return
	camera_mode_manager.set_input_locked(locked)
	_refresh_hud_control_mode()

func is_player_dialog_input_locked() -> bool:
	return is_player_control_input_locked() or is_camera_input_locked()

func set_player_dialog_input_locked(locked: bool) -> void:
	var player_avatar := _get_player_input_lock_target()
	if player_avatar != null and player_avatar.has_method("set_manual_control_input_locked"):
		player_avatar.set_manual_control_input_locked(locked)
	if camera_mode_manager != null and camera_mode_manager.has_method("set_input_locked"):
		camera_mode_manager.set_input_locked(locked)
	_refresh_hud_control_mode()

func _get_player_input_lock_target() -> Citizen:
	var player_avatar := get_player_avatar()
	if player_avatar != null:
		return player_avatar
	return get_camera_player_target()

func ensure_valid_control_target() -> void:
	if _player_avatar != null and not is_instance_valid(_player_avatar):
		_player_avatar = null
		_refresh_hud_player_control()
	if _controlled_citizen != null and not is_instance_valid(_controlled_citizen):
		set_player_control_mode(false)

func handle_citizen_clicked(citizen: Citizen) -> void:
	if citizen == null:
		return
	if _selected_citizen == citizen:
		deselect()
		return

	if _selected_building != null:
		_selected_building.select(null, world)
		_selected_building = null
		if building_status_badge_controller != null:
			building_status_badge_controller.hide()

	if _selected_citizen != null:
		if runtime_debug_logger != null:
			runtime_debug_logger.log_selected_citizen_trace("switch", _selected_citizen)
		_selected_citizen.select(null)
		if runtime_debug_logger != null:
			runtime_debug_logger.reset_selected_citizen_trace()
		if selection_debug_controller != null:
			selection_debug_controller.clear_citizen_path()

	_selected_citizen = citizen
	citizen.select(debug_panel)
	if debug_panel != null:
		debug_panel.visible = true
	if runtime_debug_logger != null:
		runtime_debug_logger.reset_selected_citizen_trace()
		runtime_debug_logger.log_selected_citizen_trace("selected", _selected_citizen)
	if selection_debug_controller != null:
		selection_debug_controller.update(_selected_citizen, _selected_building, world)

func handle_building_clicked(building: Building) -> void:
	if building == null:
		return
	if _selected_building == building:
		deselect()
		return

	if _selected_citizen != null:
		if runtime_debug_logger != null:
			runtime_debug_logger.log_selected_citizen_trace("deselected", _selected_citizen)
		_selected_citizen.select(null)
		_selected_citizen = null
		if runtime_debug_logger != null:
			runtime_debug_logger.reset_selected_citizen_trace()
		if selection_debug_controller != null:
			selection_debug_controller.clear_citizen_path()

	if _selected_building != null:
		_selected_building.select(null, world)

	_selected_building = building
	building.select(debug_panel, world)
	if debug_panel != null:
		debug_panel.visible = true
	if building_status_badge_controller != null:
		building_status_badge_controller.update(_selected_building, world)

func deselect() -> void:
	if _selected_citizen != null:
		if runtime_debug_logger != null:
			runtime_debug_logger.log_selected_citizen_trace("deselected", _selected_citizen)
		_selected_citizen.select(null)
		_selected_citizen = null
		if runtime_debug_logger != null:
			runtime_debug_logger.reset_selected_citizen_trace()
	if _selected_building != null:
		_selected_building.select(null, world)
		_selected_building = null
	if building_status_badge_controller != null:
		building_status_badge_controller.hide()
	if selection_debug_controller != null:
		selection_debug_controller.clear_all()
	if debug_panel != null:
		debug_panel.visible = false

func toggle_player_control() -> void:
	set_player_control_mode(not is_player_control_active())

func set_player_control_mode(enabled: bool) -> void:
	var player_avatar := get_player_avatar()
	if not enabled:
		if _controlled_citizen != null and is_instance_valid(_controlled_citizen):
			if _controlled_citizen.has_method("set_manual_control_input_locked"):
				_controlled_citizen.set_manual_control_input_locked(false)
			_controlled_citizen.set_manual_control_enabled(false, world)
		_controlled_citizen = null
		if camera_mode_manager != null:
			camera_mode_manager.clear_follow_target()
		_refresh_hud_control_mode()
		_refresh_hud_player_control()
		return

	if player_avatar == null:
		return
	_controlled_citizen = player_avatar
	if _controlled_citizen.has_method("set_manual_control_input_locked"):
		_controlled_citizen.set_manual_control_input_locked(false)
	_controlled_citizen.set_manual_control_enabled(true, world)
	if camera_mode_manager != null:
		camera_mode_manager.set_follow_target(_controlled_citizen, true)
	_refresh_hud_control_mode()
	_refresh_hud_player_control()

## The offline ControlledCitizen is driven by main.gd (keyboard control + the
## camera manager) — it is intentionally NOT a "player avatar" here, so the
## player-control toggle stays multiplayer-only and never mixes the keyboard
## and manual-control paths.
func _resolve_player_avatar() -> Citizen:
	if world == null:
		return null
	var scene_root := world.get_parent()
	if scene_root != null and scene_root.get_node_or_null("ControlledCitizen") != null:
		return null
	var candidate := world.get_node_or_null("Player")
	return candidate as Citizen

func _refresh_hud_control_mode() -> void:
	if hud_controller == null:
		return
	var controlled_citizen := get_controlled_citizen()
	if controlled_citizen == null:
		hud_controller.refresh_control_mode(null)
		return
	if controlled_citizen == get_player_avatar():
		if is_player_dialog_input_locked():
			hud_controller.refresh_control_mode(controlled_citizen, "PLAYER MODE", "Dialog active | Controls locked")
			return
		hud_controller.refresh_control_mode(controlled_citizen, "PLAYER MODE", "WASD Move | Space Jump | F Talk | Esc Exit")
		return
	hud_controller.refresh_control_mode(controlled_citizen)

func _refresh_hud_player_control() -> void:
	if hud_controller == null:
		return
	hud_controller.set_player_control_visible(get_player_avatar() != null)
	hud_controller.refresh_player_control_button(is_player_control_active())
