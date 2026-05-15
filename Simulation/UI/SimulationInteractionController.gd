extends RefCounted
class_name SimulationInteractionController

var owner_node: Node = null
var world: World = null
var debug_panel: DebugPanel = null
var selection_state_controller = null
var hud_overlay_controller = null
var dialogue_runtime_service = null
var conversation_manager = null

var _entity_clicked_this_frame: bool = false
var _building_panel_refresh_left: float = 0.0

func setup(owner_ref: Node, world_ref: World) -> void:
	owner_node = owner_ref
	world = world_ref
	_ensure_dialog_interact_input_action()
	_build_debug_panel()

func bind_selection_state(selection_state_controller_ref, hud_overlay_controller_ref) -> void:
	selection_state_controller = selection_state_controller_ref
	hud_overlay_controller = hud_overlay_controller_ref
	refresh_debug_panel_mode_controls()

func bind_dialogue_runtime_service(dialogue_runtime_service_ref) -> void:
	dialogue_runtime_service = dialogue_runtime_service_ref

func bind_conversation_manager(conversation_manager_ref) -> void:
	conversation_manager = conversation_manager_ref

func get_debug_panel() -> DebugPanel:
	return debug_panel

func update(delta: float) -> void:
	if debug_panel == null or not debug_panel.visible:
		return
	_refresh_debug_panel_dialog_ui()

	var selected_building: Building = selection_state_controller.get_selected_building() if selection_state_controller != null else null
	if selected_building == null:
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
	if world != null and world.has_method("get_canonical_building"):
		building = world.get_canonical_building(building)
	if building == null:
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

func handle_debug_panel_citizen_click_move_toggled() -> void:
	_entity_clicked_this_frame = true
	if selection_state_controller != null:
		selection_state_controller.toggle_selected_citizen_click_move()

func handle_debug_panel_citizen_dialog_toggled() -> void:
	_entity_clicked_this_frame = true
	if selection_state_controller == null or conversation_manager == null:
		return
	var selected_citizen: Citizen = selection_state_controller.get_selected_citizen()
	if selected_citizen == null:
		return
	var result: Dictionary = conversation_manager.toggle_player_dialog(selected_citizen)
	_refresh_debug_panel_dialog_ui()
	if debug_panel != null and bool(result.get("active", false)) and debug_panel.has_method("focus_citizen_dialog_input"):
		debug_panel.focus_citizen_dialog_input()

func handle_debug_panel_citizen_dialog_message_submitted(message: String) -> void:
	_entity_clicked_this_frame = true
	if selection_state_controller == null or conversation_manager == null:
		return
	var selected_citizen: Citizen = selection_state_controller.get_selected_citizen()
	if selected_citizen == null:
		return
	conversation_manager.submit_player_dialog_message(selected_citizen, message)
	_refresh_debug_panel_dialog_ui()
	if debug_panel != null and debug_panel.has_method("focus_citizen_dialog_input"):
		debug_panel.focus_citizen_dialog_input()

func mark_ui_interacted() -> void:
	_entity_clicked_this_frame = true

func handle_input(event: InputEvent) -> bool:
	var controlled_citizen: Citizen = selection_state_controller.get_controlled_citizen() if selection_state_controller != null else null
	var click_move_active: bool = selection_state_controller.is_citizen_click_move_active() if selection_state_controller != null else false
	var search_input: LineEdit = hud_overlay_controller.get_search_input() if hud_overlay_controller != null else null
	var search_results_list: ItemList = hud_overlay_controller.get_search_results_list() if hud_overlay_controller != null else null
	var viewport := owner_node.get_viewport() if owner_node != null else null
	var focus_owner: Control = viewport.gui_get_focus_owner() if viewport != null else null
	var text_input_focused := focus_owner is LineEdit or focus_owner is TextEdit

	if not text_input_focused and event.is_action_pressed("ui_cancel") and controlled_citizen != null:
		set_citizen_control_mode(false)
		return true
	if not text_input_focused and event.is_action_pressed("ui_cancel") and click_move_active:
		selection_state_controller.set_citizen_click_move_mode(false)
		return true

	if event.is_action_pressed("ui_accept") \
		and not text_input_focused \
		and controlled_citizen == null \
		and (search_input == null or not search_input.has_focus()):
		on_pause_pressed()

	if event.is_action_pressed("ui_cancel") and search_results_list != null and search_results_list.visible:
		search_results_list.visible = false
		return true

	if event.is_action_pressed("dialog_interact") and not text_input_focused:
		if _try_toggle_player_dialog_interaction():
			_entity_clicked_this_frame = true
			return true

	if event is InputEventMouseButton \
		and event.button_index == MOUSE_BUTTON_LEFT \
		and event.pressed:
		var hovered_control: Control = viewport.gui_get_hovered_control() if viewport != null else null
		if click_move_active and hovered_control == null:
			if selection_state_controller.try_handle_click_move(event.position):
				_entity_clicked_this_frame = true
				return true
		if hovered_control == null and _try_select_entity_under_cursor(event.position):
			return true
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

func on_citizen_overview_pressed() -> void:
	mark_ui_interacted()
	if hud_overlay_controller != null:
		hud_overlay_controller.toggle_citizen_overview()

func on_economy_overview_pressed() -> void:
	mark_ui_interacted()
	if hud_overlay_controller != null:
		hud_overlay_controller.toggle_economy_overview()

func on_player_control_pressed() -> void:
	mark_ui_interacted()
	if selection_state_controller != null:
		selection_state_controller.toggle_player_control()

func on_ai_runtime_pressed() -> void:
	mark_ui_interacted()
	if dialogue_runtime_service != null and dialogue_runtime_service.has_method("trigger_ui_runtime_action"):
		dialogue_runtime_service.trigger_ui_runtime_action()

func _build_debug_panel() -> void:
	if owner_node == null:
		return

	debug_panel = preload("res://Scenes/DebugPanel.tscn").instantiate()
	owner_node.add_child(debug_panel)
	debug_panel.visible = false
	debug_panel.ui_interacted.connect(mark_ui_interacted)
	debug_panel.citizen_control_toggled.connect(handle_debug_panel_citizen_control_toggled)
	debug_panel.citizen_click_move_toggled.connect(handle_debug_panel_citizen_click_move_toggled)
	debug_panel.citizen_dialog_toggled.connect(handle_debug_panel_citizen_dialog_toggled)
	debug_panel.citizen_dialog_message_submitted.connect(handle_debug_panel_citizen_dialog_message_submitted)

func _check_deselect_this_frame() -> void:
	if not _entity_clicked_this_frame:
		deselect()
	_entity_clicked_this_frame = false

func _try_select_entity_under_cursor(screen_pos: Vector2) -> bool:
	if owner_node == null or selection_state_controller == null:
		return false
	var viewport := owner_node.get_viewport()
	if viewport == null:
		return false
	var camera := viewport.get_camera_3d()
	if camera == null:
		return false
	var world_3d := camera.get_world_3d()
	if world_3d == null:
		return false
	var screen_citizen := _find_citizen_near_screen_pos(camera, screen_pos)
	if screen_citizen != null:
		handle_citizen_clicked(screen_citizen)
		return true

	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * 1000.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.collision_mask = 0xFFFFFFFF

	var excluded: Array[RID] = []
	for _i in range(12):
		query.exclude = excluded
		var hit := world_3d.direct_space_state.intersect_ray(query)
		if hit.is_empty():
			return false
		var collider: Variant = hit.get("collider", null)
		var citizen := _resolve_citizen_from_collider(collider)
		if citizen != null:
			handle_citizen_clicked(citizen)
			return true
		var building := _resolve_building_from_collider(collider)
		if building != null:
			handle_building_clicked(building)
			return true
		if collider is CollisionObject3D:
			excluded.append((collider as CollisionObject3D).get_rid())
			continue
		return false
	return false

func _find_citizen_near_screen_pos(camera: Camera3D, screen_pos: Vector2) -> Citizen:
	if world == null or camera == null:
		return null
	var best: Citizen = null
	var best_dist := INF
	var max_pick_radius_px := 28.0
	for citizen in world.citizens:
		if citizen == null or not is_instance_valid(citizen):
			continue
		if not citizen.visible or citizen.is_inside_building():
			continue
		var pick_pos := citizen.global_position + Vector3(0.0, 0.45, 0.0)
		if camera.is_position_behind(pick_pos):
			continue
		var projected := camera.unproject_position(pick_pos)
		var dist := projected.distance_to(screen_pos)
		if dist > max_pick_radius_px or dist >= best_dist:
			continue
		best = citizen
		best_dist = dist
	return best

func _resolve_citizen_from_collider(collider: Variant) -> Citizen:
	var node := collider as Node if collider is Node else null
	while node != null:
		if node is Citizen:
			var citizen := node as Citizen
			return citizen if citizen.visible else null
		node = node.get_parent()
	return null

func _resolve_building_from_collider(collider: Variant) -> Building:
	var node := collider as Node if collider is Node else null
	while node != null:
		if node is Building:
			return node as Building
		node = node.get_parent()
	return null

func _refresh_debug_panel_dialog_ui() -> void:
	if debug_panel == null:
		return
	if conversation_manager == null or selection_state_controller == null:
		debug_panel.update_citizen_dialog({})
		return
	var selected_citizen: Citizen = selection_state_controller.get_selected_citizen()
	if selected_citizen == null:
		debug_panel.update_citizen_dialog({})
		return
	debug_panel.update_citizen_dialog(conversation_manager.get_player_dialog_ui_state(selected_citizen))

func _try_toggle_player_dialog_interaction() -> bool:
	if selection_state_controller == null or conversation_manager == null:
		return false
	var active_citizen: Citizen = conversation_manager.get_active_player_dialog_citizen() if conversation_manager.has_method("get_active_player_dialog_citizen") else null
	if active_citizen != null:
		conversation_manager.close_player_dialog(active_citizen, "shortcut_closed")
		_refresh_debug_panel_dialog_ui()
		return true

	var selected_citizen: Citizen = selection_state_controller.get_selected_citizen()
	var target_citizen: Citizen = null
	if conversation_manager.has_method("find_best_player_dialog_candidate"):
		target_citizen = conversation_manager.find_best_player_dialog_candidate(selected_citizen)
	else:
		target_citizen = selected_citizen
	if target_citizen == null:
		return false
	if selected_citizen != target_citizen and selection_state_controller.has_method("handle_citizen_clicked"):
		selection_state_controller.handle_citizen_clicked(target_citizen)
	if not conversation_manager.can_start_player_dialog(target_citizen):
		return false
	conversation_manager.begin_player_dialog(target_citizen)
	_refresh_debug_panel_dialog_ui()
	if debug_panel != null and debug_panel.has_method("focus_citizen_dialog_input"):
		debug_panel.focus_citizen_dialog_input()
	return true

func _ensure_dialog_interact_input_action() -> void:
	if InputMap.has_action("dialog_interact"):
		for event in InputMap.action_get_events("dialog_interact"):
			if event is InputEventKey and int(event.keycode) == KEY_F:
				return
	else:
		InputMap.add_action("dialog_interact")

	var key_event := InputEventKey.new()
	key_event.keycode = KEY_F
	key_event.physical_keycode = KEY_F
	InputMap.action_add_event("dialog_interact", key_event)
