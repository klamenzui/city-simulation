extends RefCounted
class_name SimulationInteractionController

var owner_node: Node = null
var world: World = null
var debug_panel: DebugPanel = null
var selection_state_controller = null
var hud_overlay_controller = null

var _entity_clicked_this_frame: bool = false
var _building_panel_refresh_left: float = 0.0

func setup(owner_ref: Node, world_ref: World) -> void:
	owner_node = owner_ref
	world = world_ref
	_build_debug_panel()

func bind_selection_state(selection_state_controller_ref, hud_overlay_controller_ref) -> void:
	selection_state_controller = selection_state_controller_ref
	hud_overlay_controller = hud_overlay_controller_ref
	refresh_debug_panel_mode_controls()

func get_debug_panel() -> DebugPanel:
	return debug_panel

func update(delta: float) -> void:
	var selected_building: Building = selection_state_controller.get_selected_building() if selection_state_controller != null else null
	if selected_building == null or debug_panel == null or not debug_panel.visible:
		return

	_building_panel_refresh_left -= delta
	if _building_panel_refresh_left > 0.0:
		return

	_building_panel_refresh_left = 0.25
	selected_building.refresh_info_panel(world)

func handle_citizen_clicked(citizen: Citizen) -> void:
	_entity_clicked_this_frame = true
	if selection_state_controller != null:
		selection_state_controller.handle_citizen_clicked(citizen)

func handle_building_clicked(building: Building) -> void:
	_entity_clicked_this_frame = true
	if selection_state_controller == null:
		return

	selection_state_controller.handle_building_clicked(building)
	if selection_state_controller.get_selected_building() != null:
		_building_panel_refresh_left = 0.0

func deselect() -> void:
	if selection_state_controller != null:
		selection_state_controller.deselect()

func handle_debug_panel_citizen_control_toggled() -> void:
	_entity_clicked_this_frame = true
	if selection_state_controller != null:
		selection_state_controller.toggle_selected_citizen_control()

func mark_ui_interacted() -> void:
	_entity_clicked_this_frame = true

func handle_input(event: InputEvent) -> bool:
	var controlled_citizen: Citizen = selection_state_controller.get_controlled_citizen() if selection_state_controller != null else null
	var search_input: LineEdit = hud_overlay_controller.get_search_input() if hud_overlay_controller != null else null
	var search_results_list: ItemList = hud_overlay_controller.get_search_results_list() if hud_overlay_controller != null else null

	if event.is_action_pressed("ui_cancel") and controlled_citizen != null:
		set_citizen_control_mode(false)
		return true

	if event.is_action_pressed("ui_accept") \
		and controlled_citizen == null \
		and (search_input == null or not search_input.has_focus()):
		on_pause_pressed()

	if event.is_action_pressed("ui_cancel") and search_results_list != null and search_results_list.visible:
		search_results_list.visible = false
		return true

	if event is InputEventMouseButton \
		and event.button_index == MOUSE_BUTTON_LEFT \
		and event.pressed:
		call_deferred("_check_deselect_this_frame")

	return false

func set_citizen_control_mode(enabled: bool) -> void:
	if selection_state_controller != null:
		selection_state_controller.set_citizen_control_mode(enabled)

func refresh_debug_panel_mode_controls() -> void:
	if selection_state_controller != null:
		selection_state_controller.refresh_debug_panel_mode_controls()

func on_pause_pressed() -> void:
	if world != null:
		world.toggle_pause()

func on_speed_pressed(multiplier: float) -> void:
	if world == null:
		return
	world.set_speed(multiplier)
	if world.is_paused:
		world.toggle_pause()

func on_building_overview_pressed() -> void:
	mark_ui_interacted()
	if hud_overlay_controller != null:
		hud_overlay_controller.toggle_building_overview()

func _build_debug_panel() -> void:
	if owner_node == null:
		return

	debug_panel = preload("res://Scenes/DebugPanel.tscn").instantiate()
	owner_node.add_child(debug_panel)
	debug_panel.visible = false
	debug_panel.ui_interacted.connect(mark_ui_interacted)
	debug_panel.citizen_control_toggled.connect(handle_debug_panel_citizen_control_toggled)

func _check_deselect_this_frame() -> void:
	if not _entity_clicked_this_frame:
		deselect()
	_entity_clicked_this_frame = false
