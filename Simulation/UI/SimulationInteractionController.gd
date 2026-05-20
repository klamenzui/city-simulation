extends RefCounted
class_name SimulationInteractionController

const NetworkRoleScript = preload("res://Simulation/Multiplayer/shared/NetworkRole.gd")
const PlayerInventoryWindowScript = preload("res://Simulation/UI/PlayerInventoryWindow.gd")

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
var toast_controller = null
var inventory_window: PlayerInventoryWindow = null

var _entity_clicked_this_frame: bool = false
var _panel_refresh_left: float = 0.0
var _player_home_marker: Label3D = null
var _player_home_marker_building: Building = null
var _last_network_toast_signature: String = ""
var _player_inventory_mode: String = ""

func setup(owner_ref: Node, world_ref: World, multiplayer_session_ref = null) -> void:
	owner_node = owner_ref
	world = world_ref
	multiplayer_session = multiplayer_session_ref
	_ensure_pause_input_action()
	_ensure_dialog_interact_input_action()
	_ensure_player_building_input_actions()
	_build_debug_panel()
	_build_inventory_window()

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

func bind_toast_controller(toast_controller_ref) -> void:
	toast_controller = toast_controller_ref

func get_debug_panel() -> DebugPanel:
	return debug_panel

func update(delta: float) -> void:
	_refresh_player_home_marker()
	_poll_network_interaction_toast()
	# The inventory window has its own visibility and survives the debug panel
	# being hidden, so refresh it independently before the early-out below.
	_refresh_player_inventory_ui()
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
	var target_citizen := _resolve_debug_panel_dialog_citizen()
	if target_citizen == null:
		return
	var result: Dictionary = conversation_manager.toggle_player_dialog(target_citizen)
	if bool(result.get("active", false)) and selection_state_controller.has_method("handle_citizen_clicked"):
		selection_state_controller.handle_citizen_clicked(target_citizen)
	_refresh_debug_panel_dialog_ui()
	if debug_panel != null and bool(result.get("active", false)) and debug_panel.has_method("focus_citizen_dialog_input"):
		debug_panel.focus_citizen_dialog_input()

func handle_debug_panel_citizen_dialog_message_submitted(message: String) -> void:
	_entity_clicked_this_frame = true
	if selection_state_controller == null or conversation_manager == null:
		return
	var target_citizen := _resolve_debug_panel_dialog_citizen()
	if target_citizen == null:
		return
	conversation_manager.submit_player_dialog_message(target_citizen, message)
	_refresh_debug_panel_dialog_ui()
	if debug_panel != null and debug_panel.has_method("focus_citizen_dialog_input"):
		debug_panel.focus_citizen_dialog_input()

func mark_ui_interacted() -> void:
	_entity_clicked_this_frame = true

func handle_input(event: InputEvent) -> bool:
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

	if event.is_action_pressed("simulation_pause") \
		and not text_input_focused \
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
		if hovered_control != null:
			mark_ui_interacted()
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

func _is_network_session_active() -> bool:
	if multiplayer_session == null:
		return false
	var active_client: bool = multiplayer_session.has_method("is_client") and bool(multiplayer_session.is_client())
	var active_host: bool = multiplayer_session.has_method("is_host") and bool(multiplayer_session.is_host())
	return active_client or active_host

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


func _build_inventory_window() -> void:
	if owner_node == null:
		return
	inventory_window = PlayerInventoryWindowScript.new()
	owner_node.add_child(inventory_window)
	inventory_window.ui_interacted.connect(mark_ui_interacted)
	inventory_window.action_pressed.connect(_on_inventory_window_action_pressed)
	inventory_window.closed.connect(_on_inventory_window_closed)


func _on_inventory_window_action_pressed(action_id: String) -> void:
	mark_ui_interacted()
	handle_debug_panel_player_action_pressed(action_id)


func _on_inventory_window_closed() -> void:
	mark_ui_interacted()
	if _player_inventory_mode.is_empty():
		return
	_player_inventory_mode = ""
	var player := _get_player_citizen()
	if player != null:
		_refresh_selected_player_details(player)
	_refresh_player_action_ui()
	_refresh_player_inventory_ui()

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

func _request_network_player_action(action_id: String) -> bool:
	if multiplayer_session == null or not multiplayer_session.has_method("request_player_action"):
		return false
	return bool(multiplayer_session.request_player_action(action_id))

func _show_toast(message: String, kind: String = "info", duration_sec: float = 0.0) -> void:
	if toast_controller == null or not toast_controller.has_method("show_toast"):
		return
	toast_controller.show_toast(message, kind, duration_sec)

func _poll_network_interaction_toast() -> void:
	if toast_controller == null or multiplayer_session == null:
		return
	var status := _current_network_interaction_status()
	if status.is_empty():
		return
	var state := str(status.get("state", ""))
	if state == "requested" or state == "travelling":
		_last_network_toast_signature = ""
		return
	if state == "arrived" or state == "ready":
		return
	var message := _network_status_toast_message(status)
	if message.is_empty():
		return
	var signature := "%s|%s|%s|%s|%s" % [
		state,
		str(status.get("target_id", "")),
		str(status.get("action_id", "")),
		str(status.get("detail", "")),
		str(status.get("reason", "")),
	]
	if signature == _last_network_toast_signature:
		return
	_last_network_toast_signature = signature
	_show_toast(message, _network_status_toast_kind(state))

func _current_network_interaction_status() -> Dictionary:
	if multiplayer_session == null or not multiplayer_session.has_method("get_status"):
		return {}
	var session_status: Dictionary = multiplayer_session.get_status()
	var role := str(session_status.get("role", NetworkRoleScript.OFFLINE))
	if role == NetworkRoleScript.CLIENT:
		var client_debug := _dictionary_from_variant(session_status.get("client_debug", {}))
		return _dictionary_from_variant(client_debug.get("interaction_status", {}))
	if role == NetworkRoleScript.HOST:
		var host_debug := _dictionary_from_variant(session_status.get("host_debug", {}))
		var statuses := _dictionary_from_variant(host_debug.get("interaction_status_by_peer", {}))
		var local_status := _dictionary_from_variant(statuses.get("1", {}))
		if not local_status.is_empty():
			return local_status
		var active_effects := _dictionary_from_variant(host_debug.get("active_interaction_effect_by_peer", {}))
		var effect_status := _dictionary_from_variant(active_effects.get("1", {}))
		if not effect_status.is_empty():
			effect_status["state"] = "effect"
			return effect_status
		var active_interactions := _dictionary_from_variant(host_debug.get("active_interaction_by_peer", {}))
		var active_status := _dictionary_from_variant(active_interactions.get("1", {}))
		if not active_status.is_empty():
			active_status["state"] = "travelling"
			return active_status
	return {}

func _dictionary_from_variant(value: Variant) -> Dictionary:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}

func _network_status_toast_message(status: Dictionary) -> String:
	var detail := str(status.get("detail", "")).strip_edges()
	var action_id := str(status.get("action_id", "")).strip_edges()
	if not detail.is_empty():
		if detail.begins_with("Interacting with"):
			return _target_interaction_message("Interaktion gestartet", status)
		if detail == "Interaction rejected." or detail.begins_with("Player action rejected"):
			return _target_interaction_message("Interaktion abgelehnt", status)
		if detail == "Interaction cancelled.":
			return "Interaktion abgebrochen."
		return detail
	match str(status.get("state", "")):
		"effect", "entered_building", "citizen_interaction":
			if not action_id.is_empty():
				return "%s ausgefuehrt." % _player_action_label(action_id)
			return _target_interaction_message("Interaktion gestartet", status)
		"rejected":
			if not action_id.is_empty():
				return "%s nicht moeglich." % _player_action_label(action_id)
			return _target_interaction_message("Interaktion abgelehnt", status)
		"travel_failed":
			return _target_interaction_message("Ziel nicht erreichbar", status)
		"cancelled":
			return "Interaktion abgebrochen."
	return ""

func _target_interaction_message(prefix: String, status: Dictionary) -> String:
	var target_label := _compact_target_label(status)
	if target_label.is_empty():
		return "%s." % prefix
	return "%s: %s." % [prefix, target_label]

func _network_status_toast_kind(state: String) -> String:
	match state:
		"effect", "entered_building", "citizen_interaction":
			return "success"
		"rejected", "travel_failed", "cancelled":
			return "warning"
	return "info"

func _offline_player_action_toast_message(action_id: String, accepted: bool, player: Citizen) -> String:
	var label := _player_action_label(action_id)
	var notice := ""
	if player != null and player.has_method("get_player_action_notice"):
		notice = str(player.get_player_action_notice()).strip_edges()
	if not accepted:
		return notice if not notice.is_empty() else "%s nicht moeglich." % label
	if not notice.is_empty():
		return notice
	match action_id:
		"work", "eat", "sleep", "study", "relax", "socialize", "watch_cinema":
			return "%s gestartet." % label
		"buy_shop_item", "buy_groceries":
			return "%s gekauft." % label
		"stop":
			return "Aktion gestoppt."
		"exit_building":
			return "Gebaeude verlassen."
	return "%s ausgefuehrt." % label

func _player_action_label(action_id: String) -> String:
	match action_id:
		"rent_home":
			return "Wohnung mieten"
		"quit_home":
			return "Wohnung kuendigen"
		"apply_work":
			return "Bewerben"
		"work":
			return "Arbeiten"
		"eat":
			return "Essen"
		"sleep":
			return "Schlafen"
		"study":
			return "Studieren"
		"relax":
			return "Entspannen"
		"socialize":
			return "Sozialisieren"
		"watch_cinema":
			return "Film schauen"
		"inventory":
			return "Inventar"
		"shop":
			return "Einkaufen"
		"inventory_close":
			return "Inventar schliessen"
		"buy_shop_item":
			return "Kleidung kaufen"
		"buy_groceries":
			return "Vorraete kaufen"
		"quit_job":
			return "Job kuendigen"
		"training":
			return "Zur Uni"
		"stop":
			return "Aktion stoppen"
		"exit_building":
			return "Gebaeude verlassen"
	return action_id

func _compact_target_label(status: Dictionary) -> String:
	var target_name := str(status.get("target_name", "")).strip_edges()
	var target_type := str(status.get("target_type", "")).strip_edges()
	if target_name.is_empty():
		return target_type.capitalize() if not target_type.is_empty() else ""
	if target_type.is_empty():
		return target_name
	return "%s: %s" % [target_type.capitalize(), target_name]

func _refresh_debug_panel_dialog_ui() -> void:
	if debug_panel == null:
		return
	if conversation_manager == null or selection_state_controller == null:
		debug_panel.update_citizen_dialog({})
		return
	var target_citizen := _resolve_debug_panel_dialog_citizen()
	if target_citizen == null:
		debug_panel.update_citizen_dialog({})
		return
	debug_panel.update_citizen_dialog(conversation_manager.get_player_dialog_ui_state(target_citizen))

func _resolve_debug_panel_dialog_citizen() -> Citizen:
	if conversation_manager == null or selection_state_controller == null:
		return null
	var active_citizen: Citizen = conversation_manager.get_active_player_dialog_citizen() if conversation_manager.has_method("get_active_player_dialog_citizen") else null
	if active_citizen != null:
		return active_citizen
	var selected_citizen: Citizen = selection_state_controller.get_selected_citizen()
	if selected_citizen == null:
		return null
	var player := _get_player_citizen()
	if selected_citizen == player and conversation_manager.has_method("find_best_player_dialog_candidate"):
		var candidate: Citizen = conversation_manager.find_best_player_dialog_candidate(null)
		if candidate != null:
			return candidate
	return selected_citizen

func handle_debug_panel_player_action_pressed(action_id: String) -> void:
	mark_ui_interacted()
	var player: Citizen = _get_player_citizen()
	if player == null:
		return
	if _handle_player_inventory_panel_action(action_id, player):
		return
	if _is_network_session_active():
		if _request_network_player_action(action_id):
			if action_id == "buy_shop_item" or action_id == "buy_groceries":
				_player_inventory_mode = "shop"
			_last_network_toast_signature = ""
			_show_toast("Anfrage gesendet: %s." % _player_action_label(action_id), "info", 1.8)
			_refresh_selected_player_details(player)
			_refresh_player_action_ui()
			_refresh_player_inventory_ui()
		return
	var accepted := false
	match action_id:
		"rent_home":
			accepted = player.player_rent_home(world)
		"quit_home":
			accepted = player.player_quit_home(world, true)
		"apply_work":
			accepted = player.player_apply_for_work(world)
		"work":
			accepted = player.player_work(world)
		"eat":
			accepted = player.player_eat(world)
		"sleep":
			accepted = player.player_sleep(world)
		"study":
			accepted = player.player_study(world)
		"relax":
			accepted = player.player_relax(world)
		"socialize":
			accepted = player.player_socialize(world)
		"watch_cinema":
			accepted = player.player_watch_cinema(world)
		"buy_shop_item":
			accepted = player.player_buy_shop_item(world)
		"buy_groceries":
			accepted = player.player_buy_groceries(world)
		"quit_job":
			accepted = player.player_quit_job(world, true)
		"training":
			accepted = player.player_leave_for_training(world)
		"stop":
			player.cancel_player_action(world)
			accepted = true
		_:
			return
	_show_toast(
		_offline_player_action_toast_message(action_id, accepted, player),
		"success" if accepted else "warning"
	)
	_refresh_selected_player_details(player)
	_refresh_player_action_ui()
	_refresh_player_inventory_ui()

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

func _handle_player_inventory_panel_action(action_id: String, player: Citizen) -> bool:
	match action_id:
		"inventory":
			_player_inventory_mode = "" if _player_inventory_mode == "player" else "player"
		"shop":
			_player_inventory_mode = "shop"
		"inventory_close":
			_player_inventory_mode = ""
		_:
			return false
	_refresh_selected_player_details(player)
	_refresh_player_action_ui()
	_refresh_player_inventory_ui()
	return true

func _refresh_player_inventory_ui() -> void:
	if inventory_window == null:
		return
	if selection_state_controller == null:
		_player_inventory_mode = ""
		inventory_window.hide_window()
		return
	var player: Citizen = _get_player_citizen()
	var selected: Citizen = selection_state_controller.get_selected_citizen()
	if player == null or selected != player or _player_inventory_mode.is_empty():
		if selected != player:
			_player_inventory_mode = ""
		inventory_window.hide_window()
		return
	if player.has_method("get_player_inventory_ui_state"):
		inventory_window.show_for_state(player.get_player_inventory_ui_state(world, _player_inventory_mode))
	else:
		inventory_window.hide_window()

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

func _ensure_pause_input_action() -> void:
	_ensure_key_action("simulation_pause", KEY_P)

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
	if _is_network_session_active():
		if multiplayer_session == null or not multiplayer_session.has_method("request_entity_interaction"):
			return false
		var requested := bool(multiplayer_session.request_entity_interaction(nearest))
		if requested:
			_last_network_toast_signature = ""
			_show_toast("Anfrage gesendet: Gebaeude betreten.", "info", 1.8)
		return requested
	var entered := player.player_enter_building(nearest, world)
	var enter_message := "Gebaeude betreten nicht moeglich."
	if entered:
		enter_message = "Gebaeude betreten: %s." % nearest.get_display_name()
	_show_toast(enter_message, "success" if entered else "warning")
	return entered

func _try_player_exit_building() -> bool:
	var player: Citizen = _get_player_citizen()
	if player == null:
		return false
	if _is_network_session_active():
		var requested := _request_network_player_action("exit_building")
		if requested:
			_last_network_toast_signature = ""
			_show_toast("Anfrage gesendet: Gebaeude verlassen.", "info", 1.8)
		return requested
	var exited := player.player_exit_building(world)
	_show_toast("Gebaeude verlassen." if exited else "Gebaeude verlassen nicht moeglich.", "success" if exited else "warning")
	return exited

func _refresh_player_home_marker() -> void:
	var player := _get_player_citizen()
	var home: Building = player.home if player != null and player.home != null else null
	if home == null or not is_instance_valid(home):
		_clear_player_home_marker()
		return
	if _player_home_marker_building == home \
			and _player_home_marker != null \
			and is_instance_valid(_player_home_marker):
		return

	_clear_player_home_marker()
	_player_home_marker_building = home
	_player_home_marker = Label3D.new()
	_player_home_marker.name = "PlayerHomeMarker"
	_player_home_marker.text = "v\nZUHAUSE"
	_player_home_marker.font_size = 34
	_player_home_marker.pixel_size = 0.025
	_player_home_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_player_home_marker.no_depth_test = true
	_player_home_marker.modulate = Color(0.35, 1.0, 0.55, 1.0)
	_player_home_marker.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	_player_home_marker.outline_size = 8
	_player_home_marker.position = Vector3(0.0, _get_player_home_marker_height(home), 0.0)
	home.add_child(_player_home_marker)

func _clear_player_home_marker() -> void:
	if _player_home_marker != null and is_instance_valid(_player_home_marker):
		_player_home_marker.queue_free()
	_player_home_marker = null
	_player_home_marker_building = null

func _get_player_home_marker_height(home: Building) -> float:
	if home == null:
		return 4.0
	var max_y := 4.0
	for child in home.get_children():
		if child is Node3D:
			max_y = maxf(max_y, (child as Node3D).position.y + 2.5)
	return max_y
