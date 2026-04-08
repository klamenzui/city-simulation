extends RefCounted
class_name SelectionStateController

var world: World = null
var city_camera: CityBuilderCamera = null
var debug_panel: DebugPanel = null
var hud_controller = null
var runtime_debug_logger = null
var selection_debug_controller = null
var building_status_badge_controller = null

var _selected_citizen: Citizen = null
var _selected_building: Building = null
var _controlled_citizen: Citizen = null
var _click_move_citizen: Citizen = null
var _player_avatar: Citizen = null

func setup(
	world_ref: World,
	camera_ref: CityBuilderCamera,
	debug_panel_ref: DebugPanel,
	hud_controller_ref,
	runtime_debug_logger_ref,
	selection_debug_controller_ref,
	building_status_badge_controller_ref
) -> void:
	world = world_ref
	city_camera = camera_ref
	debug_panel = debug_panel_ref
	hud_controller = hud_controller_ref
	runtime_debug_logger = runtime_debug_logger_ref
	selection_debug_controller = selection_debug_controller_ref
	building_status_badge_controller = building_status_badge_controller_ref
	_player_avatar = _resolve_player_avatar()
	_refresh_hud_control_mode()
	_refresh_hud_player_control()
	refresh_debug_panel_mode_controls()

func get_selected_citizen() -> Citizen:
	return _selected_citizen if _selected_citizen != null and is_instance_valid(_selected_citizen) else null

func get_selected_building() -> Building:
	return _selected_building if _selected_building != null and is_instance_valid(_selected_building) else null

func get_controlled_citizen() -> Citizen:
	return _controlled_citizen if _controlled_citizen != null and is_instance_valid(_controlled_citizen) else null

func get_player_avatar() -> Citizen:
	return _player_avatar if _player_avatar != null and is_instance_valid(_player_avatar) else null

func is_citizen_click_move_active() -> bool:
	return _click_move_citizen != null and is_instance_valid(_click_move_citizen) and _click_move_citizen == _selected_citizen

func is_player_control_active() -> bool:
	var player_avatar := get_player_avatar()
	return player_avatar != null and _controlled_citizen == player_avatar

func is_player_control_input_locked() -> bool:
	var player_avatar := get_player_avatar()
	if player_avatar == null or not player_avatar.has_method("is_manual_control_input_locked"):
		return false
	return bool(player_avatar.is_manual_control_input_locked())

func set_player_control_input_locked(locked: bool) -> void:
	var player_avatar := get_player_avatar()
	if player_avatar == null or not player_avatar.has_method("set_manual_control_input_locked"):
		return
	player_avatar.set_manual_control_input_locked(locked)
	_refresh_hud_control_mode()

func is_camera_input_locked() -> bool:
	if city_camera == null or not city_camera.has_method("is_input_locked"):
		return false
	return bool(city_camera.is_input_locked())

func set_camera_input_locked(locked: bool) -> void:
	if city_camera == null or not city_camera.has_method("set_input_locked"):
		return
	city_camera.set_input_locked(locked)
	_refresh_hud_control_mode()

func is_player_dialog_input_locked() -> bool:
	return is_player_control_input_locked() or is_camera_input_locked()

func set_player_dialog_input_locked(locked: bool) -> void:
	var player_avatar := get_player_avatar()
	if player_avatar != null and player_avatar.has_method("set_manual_control_input_locked"):
		player_avatar.set_manual_control_input_locked(locked)
	if city_camera != null and city_camera.has_method("set_input_locked"):
		city_camera.set_input_locked(locked)
	_refresh_hud_control_mode()

func ensure_valid_control_target() -> void:
	if _player_avatar != null and not is_instance_valid(_player_avatar):
		_player_avatar = null
		_refresh_hud_player_control()
	if _controlled_citizen != null and not is_instance_valid(_controlled_citizen):
		set_citizen_control_mode(false)

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
		if _click_move_citizen == _selected_citizen:
			set_citizen_click_move_mode(false)
		if _controlled_citizen == _selected_citizen:
			set_citizen_control_mode(false)
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
	refresh_debug_panel_mode_controls()

func handle_building_clicked(building: Building) -> void:
	if building == null:
		return
	if _selected_building == building:
		deselect()
		return

	if _selected_citizen != null:
		if _click_move_citizen == _selected_citizen:
			set_citizen_click_move_mode(false)
		if _controlled_citizen == _selected_citizen:
			set_citizen_control_mode(false)
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
	refresh_debug_panel_mode_controls()

func deselect() -> void:
	if _click_move_citizen != null:
		set_citizen_click_move_mode(false)
	if _controlled_citizen != null and not is_player_control_active():
		set_citizen_control_mode(false)
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
	refresh_debug_panel_mode_controls()

func toggle_selected_citizen_control() -> void:
	if _selected_citizen == null or not is_instance_valid(_selected_citizen):
		return
	set_citizen_control_mode(_controlled_citizen != _selected_citizen)

func toggle_selected_citizen_click_move() -> void:
	if _selected_citizen == null or not is_instance_valid(_selected_citizen):
		return
	set_citizen_click_move_mode(_click_move_citizen != _selected_citizen)

func toggle_player_control() -> void:
	set_player_control_mode(not is_player_control_active())

func set_citizen_control_mode(enabled: bool) -> void:
	if not enabled:
		if _controlled_citizen != null and is_instance_valid(_controlled_citizen):
			if _controlled_citizen.has_method("set_manual_control_input_locked"):
				_controlled_citizen.set_manual_control_input_locked(false)
			_controlled_citizen.set_manual_control_enabled(false, world)
		_controlled_citizen = null
		if city_camera != null:
			city_camera.clear_follow_target()
		_refresh_hud_control_mode()
		_refresh_hud_player_control()
		refresh_debug_panel_mode_controls()
		return

	if _selected_citizen == null or not is_instance_valid(_selected_citizen):
		return
	if _click_move_citizen == _selected_citizen:
		set_citizen_click_move_mode(false)
	if _controlled_citizen != null and _controlled_citizen != _selected_citizen and is_instance_valid(_controlled_citizen):
		if _controlled_citizen.has_method("set_manual_control_input_locked"):
			_controlled_citizen.set_manual_control_input_locked(false)
		_controlled_citizen.set_manual_control_enabled(false, world)
	_controlled_citizen = _selected_citizen
	if _controlled_citizen.has_method("set_manual_control_input_locked"):
		_controlled_citizen.set_manual_control_input_locked(false)
	_controlled_citizen.set_manual_control_enabled(true, world)
	if city_camera != null:
		city_camera.set_follow_target(_controlled_citizen)
	_refresh_hud_control_mode()
	_refresh_hud_player_control()
	refresh_debug_panel_mode_controls()

func set_player_control_mode(enabled: bool) -> void:
	var player_avatar := get_player_avatar()
	if not enabled:
		if is_player_control_active():
			set_citizen_control_mode(false)
		_refresh_hud_player_control()
		return

	if player_avatar == null:
		return
	if _click_move_citizen != null:
		set_citizen_click_move_mode(false)
	if _controlled_citizen != null and _controlled_citizen != player_avatar and is_instance_valid(_controlled_citizen):
		if _controlled_citizen.has_method("set_manual_control_input_locked"):
			_controlled_citizen.set_manual_control_input_locked(false)
		_controlled_citizen.set_manual_control_enabled(false, world)
	_controlled_citizen = player_avatar
	if _controlled_citizen.has_method("set_manual_control_input_locked"):
		_controlled_citizen.set_manual_control_input_locked(false)
	_controlled_citizen.set_manual_control_enabled(true, world)
	if city_camera != null:
		city_camera.set_follow_target(_controlled_citizen)
	_refresh_hud_control_mode()
	_refresh_hud_player_control()
	refresh_debug_panel_mode_controls()

func set_citizen_click_move_mode(enabled: bool) -> void:
	if not enabled:
		if _click_move_citizen != null and is_instance_valid(_click_move_citizen):
			_click_move_citizen.set_click_move_mode_enabled(false, world)
		_click_move_citizen = null
		refresh_debug_panel_mode_controls()
		return

	if _selected_citizen == null or not is_instance_valid(_selected_citizen):
		return
	if _controlled_citizen != null:
		set_citizen_control_mode(false)
	_click_move_citizen = _selected_citizen
	_click_move_citizen.set_click_move_mode_enabled(true, world)
	refresh_debug_panel_mode_controls()

func try_handle_click_move(screen_pos: Vector2) -> bool:
	if not is_citizen_click_move_active():
		return false
	if city_camera == null or world == null:
		return false
	var citizen := get_selected_citizen()
	if citizen == null:
		return false

	var world_pos: Variant = _pick_click_move_world_position(screen_pos, citizen)
	if world_pos == null:
		return false
	if citizen.has_method("begin_click_move_to") and citizen.begin_click_move_to(world_pos, world):
		return true
	return false

func _pick_click_move_world_position(screen_pos: Vector2, citizen: Citizen) -> Variant:
	if city_camera == null:
		return null
	var from := city_camera.project_ray_origin(screen_pos)
	var to := from + city_camera.project_ray_normal(screen_pos) * 1000.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	if citizen != null:
		query.exclude = [citizen.get_rid()]
	var hit := city_camera.get_world_3d().direct_space_state.intersect_ray(query)
	var world_pos: Vector3
	if hit.is_empty():
		var ground_y := world.get_ground_fallback_y() if world != null else 0.0
		var ground_plane := Plane(Vector3.UP, ground_y)
		var maybe_hit: Variant = ground_plane.intersects_ray(from, city_camera.project_ray_normal(screen_pos))
		if maybe_hit == null:
			return null
		world_pos = maybe_hit as Vector3
	else:
		world_pos = hit.get("position", Vector3.ZERO) as Vector3
	if world != null and world.has_method("get_pedestrian_access_point"):
		world_pos = world.get_pedestrian_access_point(world_pos)
	return world_pos

func refresh_debug_panel_mode_controls() -> void:
	if debug_panel == null:
		return
	var citizen_selected := _selected_citizen != null and is_instance_valid(_selected_citizen)
	debug_panel.set_citizen_control_button_visible(citizen_selected)
	debug_panel.set_citizen_control_active(citizen_selected and _controlled_citizen == _selected_citizen)
	debug_panel.set_citizen_click_move_button_visible(citizen_selected)
	debug_panel.set_citizen_click_move_active(citizen_selected and _click_move_citizen == _selected_citizen)

func _resolve_player_avatar() -> Citizen:
	if world == null:
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
