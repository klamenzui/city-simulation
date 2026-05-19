extends RefCounted
class_name SimulationInteractionController

var owner_node: Node = null
var world: World = null
var debug_panel: DebugPanel = null
var selection_state_controller = null
var hud_overlay_controller = null
var coordinate_picker_controller = null
var dialogue_runtime_service = null
var conversation_manager = null
var multiplayer_session = null
var camera_mode_manager = null

var _entity_clicked_this_frame: bool = false
var _panel_refresh_left: float = 0.0

func setup(owner_ref: Node, world_ref: World, multiplayer_session_ref = null) -> void:
	owner_node = owner_ref
	world = world_ref
	multiplayer_session = multiplayer_session_ref
	_ensure_dialog_interact_input_action()
	_ensure_player_building_input_actions()
	_build_debug_panel()

func bind_selection_state(selection_state_controller_ref, hud_overlay_controller_ref) -> void:
	selection_state_controller = selection_state_controller_ref
	hud_overlay_controller = hud_overlay_controller_ref

func bind_camera_mode_manager(camera_mode_manager_ref) -> void:
	camera_mode_manager = camera_mode_manager_ref

func bind_coordinate_picker(coordinate_picker_controller_ref) -> void:
	coordinate_picker_controller = coordinate_picker_controller_ref

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
	_refresh_player_action_ui()

	if selection_state_controller == null:
		return

	_panel_refresh_left -= delta
	if _panel_refresh_left > 0.0:
		return
	_panel_refresh_left = 0.25

	var selected_building: Building = selection_state_controller.get_selected_building()
	if selected_building != null:
		selected_building.refresh_info_panel(world)
		return

	# A selected citizen normally self-refreshes via its sim tick, but a
	# citizen inside a building (notably the player after R-enter) is not
	# ticked, so the panel kept stale building content. Refresh the selected
	# citizen here the same way buildings are refreshed.
	var selected_citizen: Citizen = selection_state_controller.get_selected_citizen()
	if selected_citizen != null and selected_citizen.has_method("get_info_sections"):
		debug_panel.update_sections(selected_citizen.get_info_sections(world))

func handle_citizen_clicked(citizen: Citizen) -> void:
	_entity_clicked_this_frame = true
	if selection_state_controller != null:
		selection_state_controller.handle_citizen_clicked(citizen)
		_panel_refresh_left = 0.0

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
		_panel_refresh_left = 0.0

func deselect() -> void:
	if selection_state_controller != null:
		selection_state_controller.deselect()

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
	var player_control_active: bool = selection_state_controller.is_player_control_active() if selection_state_controller != null else false
	var player_building_input_active := _is_player_building_input_active()
	var search_input: LineEdit = hud_overlay_controller.get_search_input() if hud_overlay_controller != null else null
	var search_results_list: ItemList = hud_overlay_controller.get_search_results_list() if hud_overlay_controller != null else null
	var viewport := owner_node.get_viewport() if owner_node != null else null
	var focus_owner: Control = viewport.gui_get_focus_owner() if viewport != null else null
	var text_input_focused := focus_owner is LineEdit or focus_owner is TextEdit

	if not text_input_focused and event.is_action_pressed("ui_cancel") and player_control_active:
		selection_state_controller.set_player_control_mode(false)
		return true

	if event.is_action_pressed("ui_accept") \
		and not text_input_focused \
		and controlled_citizen == null \
		and (search_input == null or not search_input.has_focus()) \
		and not _is_network_client():
		on_pause_pressed()
		return true

	if event.is_action_pressed("ui_cancel") and search_results_list != null and search_results_list.visible:
		search_results_list.visible = false
		return true

	if event.is_action_pressed("dialog_interact") and not text_input_focused:
		if _try_toggle_player_dialog_interaction():
			_entity_clicked_this_frame = true
			return true

	if not text_input_focused and player_building_input_active:
		if event.is_action_pressed("player_enter_building"):
			if _try_player_enter_building():
				return true
		if event.is_action_pressed("player_exit_building"):
			if _try_player_exit_building():
				return true

	if event is InputEventMouseButton \
		and event.button_index == MOUSE_BUTTON_LEFT \
		and event.pressed:
		var hovered_control: Control = viewport.gui_get_hovered_control() if viewport != null else null
		if hovered_control == null and _try_select_entity_under_cursor(event.position):
			return true
		call_deferred("_check_deselect_this_frame")

	return false

func on_pause_pressed() -> void:
	if _is_network_client():
		return
	if world != null:
		world.toggle_pause()

func on_speed_pressed(multiplier: float) -> void:
	if _is_network_client():
		return
	if world == null:
		return
	world.set_speed(multiplier)
	if world.is_paused:
		world.toggle_pause()

func _is_network_client() -> bool:
	return multiplayer_session != null \
		and multiplayer_session.has_method("is_client") \
		and multiplayer_session.is_client()

func on_building_overview_pressed() -> void:
	mark_ui_interacted()
	if hud_overlay_controller != null:
		hud_overlay_controller.toggle_building_overview()

func on_citizen_overview_pressed() -> void:
	mark_ui_interacted()
	if hud_overlay_controller != null:
		hud_overlay_controller.toggle_citizen_overview()

## Toggles the left DETAILS panel on the local player citizen, mirroring a
## citizen click — the player avatar is hard to click (camera target / hidden
## indoors), so the bottom-bar button is the reliable way to inspect it.
func on_player_overview_pressed() -> void:
	mark_ui_interacted()
	if selection_state_controller == null:
		return
	var player: Citizen = _get_player_citizen()
	if player == null:
		return
	selection_state_controller.handle_citizen_clicked(player)
	_panel_refresh_left = 0.0

func on_economy_overview_pressed() -> void:
	mark_ui_interacted()
	if hud_overlay_controller != null:
		hud_overlay_controller.toggle_economy_overview()

func on_search_overview_pressed() -> void:
	mark_ui_interacted()
	if hud_overlay_controller != null:
		hud_overlay_controller.toggle_search_overlay()

func on_debug_tools_pressed() -> void:
	mark_ui_interacted()
	if coordinate_picker_controller != null:
		coordinate_picker_controller.toggle_panel()

func on_player_control_pressed() -> void:
	mark_ui_interacted()
	if selection_state_controller != null:
		selection_state_controller.toggle_player_control()

func on_camera_mode_pressed() -> void:
	mark_ui_interacted()
	if camera_mode_manager != null:
		camera_mode_manager.toggle()

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
	debug_panel.citizen_dialog_toggled.connect(handle_debug_panel_citizen_dialog_toggled)
	debug_panel.citizen_dialog_message_submitted.connect(handle_debug_panel_citizen_dialog_message_submitted)
	debug_panel.player_action_pressed.connect(handle_debug_panel_player_action_pressed)

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
		_request_network_interaction(screen_citizen)
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
			_request_network_interaction(citizen)
			return true
		var building := _resolve_building_from_collider(collider)
		if building != null:
			_handle_building_hit(building)
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

func _handle_building_hit(building: Building) -> void:
	if world != null and world.has_method("get_canonical_building"):
		building = world.get_canonical_building(building)
	handle_building_clicked(building)
	_request_network_interaction(building)

func _request_network_interaction(target: Node) -> void:
	if multiplayer_session == null or not multiplayer_session.has_method("request_entity_interaction"):
		return
	multiplayer_session.request_entity_interaction(target)

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

func handle_debug_panel_player_action_pressed(action_id: String) -> void:
	mark_ui_interacted()
	var player: Citizen = _get_player_citizen()
	if player == null:
		return
	match action_id:
		"apply_work":
			player.player_apply_for_work(world)
		"work":
			player.player_work(world)
		"eat":
			player.player_eat(world)
		"sleep":
			player.player_sleep(world)
		"study":
			player.player_study(world)
		"quit_job":
			player.player_quit_job(world, true)
		"training":
			player.player_leave_for_training(world)
		"stop":
			player.cancel_player_action(world)
		_:
			return
	_refresh_selected_player_details(player)
	_refresh_player_action_ui()

func _refresh_selected_player_details(player: Citizen) -> void:
	if debug_panel == null or player == null:
		return
	if selection_state_controller == null or selection_state_controller.get_selected_citizen() != player:
		return
	if player.has_method("get_info_sections"):
		debug_panel.update_sections(player.get_info_sections(world))

func _refresh_player_action_ui() -> void:
	if debug_panel == null:
		return
	if selection_state_controller == null:
		debug_panel.update_player_actions({})
		return
	var player: Citizen = _get_player_citizen()
	var selected: Citizen = selection_state_controller.get_selected_citizen()
	if player == null or selected != player:
		debug_panel.update_player_actions({})
		return
	if player.has_method("get_player_action_ui_state"):
		debug_panel.update_player_actions(player.get_player_action_ui_state(world))
	else:
		debug_panel.update_player_actions({})

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

func _ensure_player_building_input_actions() -> void:
	_ensure_key_action("player_enter_building", KEY_R)
	_ensure_key_action("player_exit_building", KEY_T)

func _ensure_key_action(action_name: String, keycode: int) -> void:
	if InputMap.has_action(action_name):
		for event in InputMap.action_get_events(action_name):
			if event is InputEventKey and int(event.keycode) == keycode:
				return
	else:
		InputMap.add_action(action_name)
	var key_event := InputEventKey.new()
	key_event.keycode = keycode
	key_event.physical_keycode = keycode
	InputMap.action_add_event(action_name, key_event)

## Public accessor for the local player citizen (HUD reads it for the
## persistent hunger bar). Resolution order lives in _get_player_citizen.
func get_player_citizen() -> Citizen:
	return _get_player_citizen()

func _get_player_citizen() -> Citizen:
	if selection_state_controller == null:
		return null
	if selection_state_controller.has_method("get_player_avatar"):
		var avatar = selection_state_controller.get_player_avatar()
		if avatar != null:
			return avatar
	if selection_state_controller.has_method("get_controlled_citizen"):
		var controlled = selection_state_controller.get_controlled_citizen()
		if controlled != null:
			return controlled
	if selection_state_controller.has_method("get_camera_player_target"):
		var camera_target = selection_state_controller.get_camera_player_target()
		if camera_target != null:
			return camera_target
	return null

func _is_player_building_input_active() -> bool:
	var player := _get_player_citizen()
	if player == null:
		return false
	if selection_state_controller != null \
			and selection_state_controller.has_method("is_player_control_active") \
			and selection_state_controller.is_player_control_active():
		return true
	if player.has_method("is_keyboard_control_enabled") and player.is_keyboard_control_enabled():
		return true
	if player.has_method("is_manual_control_enabled") and player.is_manual_control_enabled():
		return true
	return false

func _try_player_enter_building() -> bool:
	var player: Citizen = _get_player_citizen()
	if player == null or world == null or player.is_inside_building():
		return false
	var nearest: Building = null
	var best := 3.5  # max flat distance to a building entrance to allow R-enter
	for b in world.buildings:
		if b == null or not is_instance_valid(b):
			continue
		var entrance: Vector3 = b.get_entrance_pos() if b.has_method("get_entrance_pos") else b.global_position
		var d := Vector2(player.global_position.x - entrance.x, player.global_position.z - entrance.z).length()
		if d <= best:
			best = d
			nearest = b
	if nearest == null:
		return false
	return player.player_enter_building(nearest, world)

func _try_player_exit_building() -> bool:
	var player: Citizen = _get_player_citizen()
	if player == null:
		return false
	return player.player_exit_building(world)
