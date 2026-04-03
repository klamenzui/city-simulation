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
	refresh_debug_panel_mode_controls()

func get_selected_citizen() -> Citizen:
	return _selected_citizen if _selected_citizen != null and is_instance_valid(_selected_citizen) else null

func get_selected_building() -> Building:
	return _selected_building if _selected_building != null and is_instance_valid(_selected_building) else null

func get_controlled_citizen() -> Citizen:
	return _controlled_citizen if _controlled_citizen != null and is_instance_valid(_controlled_citizen) else null

func ensure_valid_control_target() -> void:
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
	if _controlled_citizen != null:
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

func set_citizen_control_mode(enabled: bool) -> void:
	if not enabled:
		if _controlled_citizen != null and is_instance_valid(_controlled_citizen):
			_controlled_citizen.set_manual_control_enabled(false, world)
		_controlled_citizen = null
		if city_camera != null:
			city_camera.clear_follow_target()
		if hud_controller != null:
			hud_controller.refresh_control_mode(null)
		refresh_debug_panel_mode_controls()
		return

	if _selected_citizen == null or not is_instance_valid(_selected_citizen):
		return
	if _controlled_citizen != null and _controlled_citizen != _selected_citizen and is_instance_valid(_controlled_citizen):
		_controlled_citizen.set_manual_control_enabled(false, world)
	_controlled_citizen = _selected_citizen
	_controlled_citizen.set_manual_control_enabled(true, world)
	if city_camera != null:
		city_camera.set_follow_target(_controlled_citizen)
	if hud_controller != null:
		hud_controller.refresh_control_mode(_controlled_citizen)
	refresh_debug_panel_mode_controls()

func refresh_debug_panel_mode_controls() -> void:
	if debug_panel == null:
		return
	var citizen_selected := _selected_citizen != null and is_instance_valid(_selected_citizen)
	debug_panel.set_citizen_control_button_visible(citizen_selected)
	debug_panel.set_citizen_control_active(citizen_selected and _controlled_citizen == _selected_citizen)
