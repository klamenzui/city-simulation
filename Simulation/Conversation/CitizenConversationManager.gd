extends RefCounted
class_name CitizenConversationManager

const CONFIG_PATH := "res://config/conversation_rules.json"
const SimLogger = preload("res://Simulation/Logging/SimLogger.gd")

var world: World = null
var city_camera: Camera3D = null
var selection_state_controller = null
var dialogue_runtime = null

var _config: Dictionary = {}
var _refresh_left: float = 0.0
var _runtime_sec: float = 0.0
var _active_conversations: Dictionary = {}
var _player_dialog_sessions: Dictionary = {}
var _player_dialog_request_to_citizen: Dictionary = {}

func setup(world_ref: World, camera_ref: Camera3D, selection_state_controller_ref) -> void:
	world = world_ref
	city_camera = camera_ref
	selection_state_controller = selection_state_controller_ref
	_config = _load_config()
	_refresh_left = 0.0

func bind_dialogue_runtime(dialogue_runtime_ref) -> void:
	dialogue_runtime = dialogue_runtime_ref
	if dialogue_runtime == null:
		return
	if dialogue_runtime.has_signal("player_dialogue_ready"):
		var ready_cb := Callable(self, "_on_player_dialogue_ready")
		if not dialogue_runtime.player_dialogue_ready.is_connected(ready_cb):
			dialogue_runtime.player_dialogue_ready.connect(ready_cb)

func update(delta: float) -> void:
	if world == null or selection_state_controller == null:
		return

	_runtime_sec += delta
	_refresh_left -= delta
	if _refresh_left > 0.0:
		return
	_refresh_left = _get_float("pairing.refresh_interval_sec", 0.8)

	var selected_citizen: Citizen = selection_state_controller.get_selected_citizen()
	var controlled_citizen: Citizen = selection_state_controller.get_controlled_citizen()
	var player_avatar: Citizen = selection_state_controller.get_player_avatar() if selection_state_controller.has_method("get_player_avatar") else null
	var player_control_active: bool = selection_state_controller.is_player_control_active() if selection_state_controller.has_method("is_player_control_active") else false

	_clear_runtime_conversation_states()
	_remove_transient_commitments()
	_remove_stale_player_interest_commitments(selected_citizen, controlled_citizen, player_avatar)
	_apply_player_interest_commitments(selected_citizen, controlled_citizen, player_avatar, player_control_active)
	_apply_active_player_dialog_sessions(selected_citizen, player_avatar, player_control_active)
	_refresh_player_dialog_control_lock()
	_update_npc_conversations(player_avatar, player_control_active)

func get_active_conversations() -> Dictionary:
	return _active_conversations.duplicate(true)

func get_dialogue_runtime_status_label() -> String:
	if dialogue_runtime != null and dialogue_runtime.has_method("get_status_label"):
		return str(dialogue_runtime.get_status_label())
	return "template_only"

func get_player_dialog_availability(citizen: Citizen) -> Dictionary:
	var player_avatar: Citizen = selection_state_controller.get_player_avatar() if selection_state_controller != null and selection_state_controller.has_method("get_player_avatar") else null
	var player_control_active: bool = selection_state_controller.is_player_control_active() if selection_state_controller != null and selection_state_controller.has_method("is_player_control_active") else false
	var result := {
		"available": false,
		"reason": "no_citizen",
		"distance": INF,
		"max_distance": _get_float("distance_thresholds_m.interactive_auto_offer", 3.0)
	}
	if citizen == null:
		return result
	if citizen == player_avatar:
		result["reason"] = "player_avatar"
		return result
	if player_avatar == null or not player_control_active:
		result["reason"] = "player_mode_required"
		return result
	var distance := player_avatar.global_position.distance_to(citizen.global_position)
	result["distance"] = distance
	if distance > float(result["max_distance"]):
		result["reason"] = "move_closer"
		return result
	if citizen.has_method("get_simulation_lod_tier") and citizen.get_simulation_lod_tier() == "coarse":
		result["reason"] = "citizen_not_active"
		return result
	if citizen.has_method("is_inside_building") and citizen.is_inside_building():
		result["reason"] = "citizen_inside"
		return result
	result["available"] = true
	result["reason"] = "ready"
	return result

func can_start_player_dialog(citizen: Citizen) -> bool:
	return bool(get_player_dialog_availability(citizen).get("available", false)) and _has_interactive_budget_for(citizen)

func begin_player_dialog(citizen: Citizen) -> Dictionary:
	var availability := get_player_dialog_availability(citizen)
	if not bool(availability.get("available", false)):
		_log_player_dialog(citizen, "Start blocked: %s" % str(availability.get("reason", "unavailable")))
		return {
			"error": str(availability.get("reason", "unavailable")),
			"active": false
		}
	if not _has_interactive_budget_for(citizen):
		_log_player_dialog(citizen, "Start blocked: interactive_budget_reached")
		return {
			"error": "interactive_budget_reached",
			"active": false
		}
	var session := _ensure_player_dialog_session(citizen)
	session["active"] = true
	session["started_at_sec"] = float(session.get("started_at_sec", _runtime_sec))
	_player_dialog_sessions[citizen.get_instance_id()] = session
	_refresh_player_dialog_control_lock()
	_log_player_dialog(citizen, "Session started")
	return session.duplicate(true)

func close_player_dialog(citizen: Citizen, reason: String = "closed") -> void:
	if citizen == null:
		return
	var citizen_id := citizen.get_instance_id()
	var session_variant: Variant = _player_dialog_sessions.get(citizen_id, {})
	if session_variant is Dictionary:
		var session := session_variant as Dictionary
		var pending_request_key := str(session.get("pending_request_key", ""))
		if not pending_request_key.is_empty():
			_player_dialog_request_to_citizen.erase(pending_request_key)
		_log_player_dialog(citizen, "Session closed: %s" % reason)
	_player_dialog_sessions.erase(citizen_id)
	citizen.clear_runtime_conversation_state()
	citizen.remove_lod_commitment("player_dialog")
	_refresh_player_dialog_control_lock()

func get_player_dialog_session(citizen: Citizen) -> Dictionary:
	if citizen == null:
		return {}
	var session_variant: Variant = _player_dialog_sessions.get(citizen.get_instance_id(), {})
	if session_variant is not Dictionary:
		return {}
	return (session_variant as Dictionary).duplicate(true)

func toggle_player_dialog(citizen: Citizen) -> Dictionary:
	if citizen == null:
		return {}
	var session := get_player_dialog_session(citizen)
	if bool(session.get("active", false)):
		close_player_dialog(citizen, "user_closed")
		return {
			"active": false,
			"closed": true
		}
	return begin_player_dialog(citizen)

func get_player_dialog_ui_state(citizen: Citizen) -> Dictionary:
	var ui_state := {
		"visible": citizen != null,
		"button_visible": citizen != null,
		"button_enabled": false,
		"button_text": "Start Dialog",
		"status_text": "",
		"log_visible": false,
		"messages": [],
		"recent_summary": "",
		"pending_error": "",
		"input_visible": false,
		"input_enabled": false,
		"input_placeholder": "Type a message...",
		"send_enabled": false
	}
	if citizen == null:
		return ui_state

	var session := get_player_dialog_session(citizen)
	var is_active := bool(session.get("active", false))
	if is_active:
		var pending_reply := bool(session.get("pending_reply", false))
		var auto_close_due := float(session.get("auto_close_due_at_sec", -1.0))
		var closing_soon := not pending_reply and auto_close_due > _runtime_sec
		ui_state["button_enabled"] = true
		ui_state["button_text"] = "End Dialog"
		if pending_reply:
			ui_state["status_text"] = "Waiting for reply..."
		elif closing_soon:
			ui_state["status_text"] = "Dialog ending..."
		else:
			ui_state["status_text"] = "Dialog active (movement locked)"
		ui_state["log_visible"] = true
		ui_state["messages"] = (session.get("messages", []) as Array).duplicate(true)
		ui_state["recent_summary"] = str(session.get("recent_summary", ""))
		ui_state["pending_error"] = _describe_player_dialog_pending_error(str(session.get("pending_error", "")))
		ui_state["input_visible"] = true
		ui_state["input_enabled"] = not pending_reply
		ui_state["input_placeholder"] = "Waiting for NPC reply..." if pending_reply else "Type a message..."
		ui_state["send_enabled"] = not pending_reply
		return ui_state

	var availability := get_player_dialog_availability(citizen)
	if bool(availability.get("available", false)) and _has_interactive_budget_for(citizen):
		ui_state["button_enabled"] = true
		ui_state["status_text"] = "Ready to talk"
	else:
		ui_state["status_text"] = _describe_player_dialog_unavailable_reason(citizen, availability)
	return ui_state

func submit_player_dialog_message(citizen: Citizen, player_text: String) -> Dictionary:
	if citizen == null:
		return {}
	var clean_text := player_text.strip_edges()
	if clean_text.is_empty():
		return get_player_dialog_session(citizen)

	var session := _ensure_player_dialog_session(citizen)
	if bool(session.get("pending_reply", false)):
		session["pending_error"] = "reply_pending"
		_player_dialog_sessions[citizen.get_instance_id()] = session
		_log_player_dialog(citizen, "Ignored player line while reply pending")
		return session.duplicate(true)
	session["active"] = true
	var messages: Array = (session.get("messages", []) as Array).duplicate(true)
	messages.append({
		"speaker": "Player",
		"text": clean_text
	})
	session["messages"] = messages
	session["pending_reply"] = true
	session["pending_error"] = ""
	session["turn_count"] = int(session.get("turn_count", 0)) + 1
	session["last_player_message_at_sec"] = _runtime_sec
	session["farewell_requested"] = _is_farewell_player_line(clean_text)
	session["auto_close_due_at_sec"] = -1.0
	_compress_player_dialog_session_memory(session)

	var request_key := "%s_turn_%d" % [str(session.get("session_id", citizen.citizen_name.to_lower())), int(session.get("turn_count", 1))]
	session["pending_request_key"] = request_key
	var payload := _build_player_dialogue_payload(citizen, session)
	session["pending_payload"] = payload.duplicate(true)
	_log_player_dialog(citizen, "Player: %s" % clean_text)
	_log_player_dialog(
		citizen,
		"Context language=%s mood=%s goal=%s district=%s nearby=%s" % [
			str(payload.get("reply_language", "")),
			str(payload.get("mood", "")),
			str(payload.get("current_goal", "")),
			str(payload.get("district", "")),
			", ".join(_extract_place_names(payload.get("nearby_places", [])))
		]
	)

	var reply_result: Dictionary = {}
	if dialogue_runtime != null and dialogue_runtime.has_method("request_player_reply"):
		reply_result = dialogue_runtime.request_player_reply(request_key, payload)
	else:
		reply_result = {
			"state": "ready",
			"source": "template",
			"text": _build_player_fallback_reply(citizen)
		}

	var reply_state := str(reply_result.get("state", ""))
	_log_player_dialog(
		citizen,
		"Runtime state=%s source=%s model=%s request=%s" % [
			reply_state,
			str(reply_result.get("source", "")),
			str(reply_result.get("model", "")),
			request_key
		]
	)
	if reply_state == "ready":
		_apply_player_dialog_reply_to_session(session, citizen, reply_result)
	elif reply_state == "pending":
		_player_dialog_request_to_citizen[request_key] = citizen.get_instance_id()
	else:
		_log_player_dialog(citizen, "Runtime could not answer immediately, using template fallback")
		_apply_player_dialog_reply_to_session(session, citizen, {
			"state": "ready",
			"source": "template_fallback",
			"text": _build_player_fallback_reply(citizen)
		})

	_player_dialog_sessions[citizen.get_instance_id()] = session
	return session.duplicate(true)

func _apply_player_interest_commitments(
	selected_citizen: Citizen,
	controlled_citizen: Citizen,
	player_avatar: Citizen,
	player_control_active: bool
) -> void:
	if selected_citizen != null and selected_citizen != player_avatar:
		_upsert_commitment(selected_citizen, "player_interest", _get_int("player_interaction.selection_interest_lock_minutes", 15))

	if controlled_citizen != null and controlled_citizen != player_avatar:
		_upsert_commitment(controlled_citizen, "player_interest", _get_int("player_interaction.control_interest_lock_minutes", 20))

	if not player_control_active or player_avatar == null or selected_citizen == null or selected_citizen == player_avatar:
		return

	var interactive_distance := _get_float("distance_thresholds_m.interactive_auto_offer", 3.0)
	if player_avatar.global_position.distance_to(selected_citizen.global_position) > interactive_distance:
		return

	_upsert_commitment(selected_citizen, "player_dialog", _get_int("player_interaction.interactive_offer_lock_minutes", 20))
	selected_citizen.set_runtime_conversation_state("interactive", "Player", "player_offer")

func _apply_active_player_dialog_sessions(
	selected_citizen: Citizen,
	player_avatar: Citizen,
	player_control_active: bool
) -> void:
	var active_ids: Array = _player_dialog_sessions.keys()
	for citizen_id_variant in active_ids:
		var citizen_id := int(citizen_id_variant)
		var citizen := instance_from_id(citizen_id) as Citizen
		if citizen == null or not is_instance_valid(citizen):
			_player_dialog_sessions.erase(citizen_id)
			continue
		if selected_citizen != citizen:
			close_player_dialog(citizen, "selection_changed")
			continue
		var session_variant: Variant = _player_dialog_sessions.get(citizen_id, {})
		if session_variant is not Dictionary:
			_player_dialog_sessions.erase(citizen_id)
			continue
		var session := session_variant as Dictionary
		if _should_auto_close_player_dialog_session(session):
			close_player_dialog(citizen, "farewell_timeout")
			continue
		var availability := get_player_dialog_availability(citizen)
		if _get_bool("player_npc.cancel_if_player_leaves_range", true):
			if not player_control_active or player_avatar == null or not bool(availability.get("available", false)):
				close_player_dialog(citizen, str(availability.get("reason", "unavailable")))
				continue
		citizen.set_runtime_conversation_state("interactive", "Player", "player_dialog")
		_upsert_commitment(citizen, "player_dialog", _get_int("player_npc.commitment_lock_minutes", 20))

func _update_npc_conversations(player_avatar: Citizen, player_control_active: bool) -> void:
	var anchor_position := _get_anchor_position(player_avatar, player_control_active)
	var used: Dictionary = {}
	var active_pairs: Array = []
	var max_pairs := _get_int("pairing.max_active_pairs", 4)
	var pair_distance := _get_float("pairing.max_participant_distance_m", 3.5)
	var citizen_lookup := _build_citizen_lookup()
	var candidates := _gather_conversation_candidates(player_avatar, anchor_position)

	for existing in _active_conversations.values():
		if active_pairs.size() >= max_pairs:
			break
		if existing is not Dictionary:
			continue
		var existing_entry := existing as Dictionary
		var participant_ids: Variant = existing.get("participant_ids", [])
		if participant_ids is not Array or participant_ids.size() < 2:
			continue
		var citizen_a := citizen_lookup.get(int(participant_ids[0]), null) as Citizen
		var citizen_b := citizen_lookup.get(int(participant_ids[1]), null) as Citizen
		if citizen_a == null or citizen_b == null:
			continue
		var citizen_a_id := citizen_a.get_instance_id()
		var citizen_b_id := citizen_b.get_instance_id()
		if used.has(citizen_a_id) or used.has(citizen_b_id):
			continue
		var abort_reason := _get_abort_reason_for_pair(existing_entry, citizen_a, citizen_b, pair_distance)
		if not abort_reason.is_empty():
			continue
		if not _can_continue_npc_conversation(citizen_a, citizen_b, pair_distance):
			continue
		used[citizen_a_id] = true
		used[citizen_b_id] = true
		active_pairs.append({
			"id": str(existing.get("id", _make_pair_id(citizen_a, citizen_b))),
			"a": citizen_a,
			"b": citizen_b,
			"distance": citizen_a.global_position.distance_to(citizen_b.global_position),
			"topic": str(existing.get("topic", "")),
			"start_mode": str(existing.get("start_mode", _infer_pair_start_mode(citizen_a, citizen_b))),
			"previous": existing_entry.duplicate(true)
		})

	for candidate in candidates:
		if active_pairs.size() >= max_pairs:
			break
		var citizen: Citizen = candidate.get("citizen") as Citizen
		if citizen == null:
			continue
		var citizen_id := citizen.get_instance_id()
		if used.has(citizen_id):
			continue
		var candidate_start_mode := str(candidate.get("start_mode", ""))

		var best_partner: Citizen = null
		var best_distance := INF
		for other_candidate in candidates:
			var other: Citizen = other_candidate.get("citizen") as Citizen
			if other == null or other == citizen:
				continue
			var other_id := other.get_instance_id()
			if used.has(other_id):
				continue
			var other_start_mode := str(other_candidate.get("start_mode", ""))
			if not _pair_start_modes_are_compatible(citizen, candidate_start_mode, other, other_start_mode):
				continue
			var distance := citizen.global_position.distance_to(other.global_position)
			if distance > pair_distance:
				continue
			if distance < best_distance:
				best_distance = distance
				best_partner = other

		if best_partner == null:
			continue
		used[citizen_id] = true
		used[best_partner.get_instance_id()] = true
		active_pairs.append({
			"id": _make_pair_id(citizen, best_partner),
			"a": citizen,
			"b": best_partner,
			"distance": best_distance,
			"topic": "",
			"start_mode": candidate_start_mode
		})

	var runtime_entries: Array = []
	var active_conversations: Dictionary = {}
	for pair in active_pairs:
		var citizen_a: Citizen = pair["a"] as Citizen
		var citizen_b: Citizen = pair["b"] as Citizen
		if citizen_a == null or citizen_b == null:
			continue
		var conversation_id := str(pair.get("id", _make_pair_id(citizen_a, citizen_b)))
		var midpoint := (citizen_a.global_position + citizen_b.global_position) * 0.5
		var player_distance := anchor_position.distance_to(midpoint) if player_control_active and player_avatar != null else INF
		var mode := _resolve_mode_for_pair(conversation_id, player_distance)

		var topic := str(pair.get("topic", ""))
		if topic == "":
			topic = _resolve_topic_for_pair(
				conversation_id,
				citizen_a,
				citizen_b,
				str(pair.get("start_mode", "smalltalk"))
			)
		var previous_entry_variant: Variant = pair.get("previous", {})
		var previous_entry: Dictionary = previous_entry_variant as Dictionary if previous_entry_variant is Dictionary else {}
		runtime_entries.append({
			"id": conversation_id,
			"citizen_a": citizen_a,
			"citizen_b": citizen_b,
			"participant_ids": [citizen_a.get_instance_id(), citizen_b.get_instance_id()],
			"participants": [citizen_a.citizen_name, citizen_b.citizen_name],
			"mode": mode,
			"start_mode": str(pair.get("start_mode", "smalltalk")),
			"topic": topic,
			"midpoint": midpoint,
			"player_distance": player_distance,
			"previous": previous_entry.duplicate(true)
		})

	runtime_entries.sort_custom(_sort_conversation_entries)
	var materialized_budget := maxi(_get_int("lifecycle.max_parallel_materialized_conversations", 1), 0)
	var materialized_count := 0
	for entry in runtime_entries:
		var citizen_a: Citizen = entry.get("citizen_a") as Citizen
		var citizen_b: Citizen = entry.get("citizen_b") as Citizen
		if citizen_a == null or citizen_b == null:
			continue
		var conversation_id := str(entry.get("id", ""))
		var mode := str(entry.get("mode", "abstract"))
		var previous_entry_variant: Variant = entry.get("previous", {})
		var previous_entry: Dictionary = previous_entry_variant as Dictionary if previous_entry_variant is Dictionary else {}
		if mode == "materialized":
			if materialized_count >= materialized_budget:
				mode = "bark"
			else:
				materialized_count += 1
		var topic := str(entry.get("topic", "smalltalk"))
		var start_mode := str(entry.get("start_mode", "smalltalk"))
		var dialogue_block: Dictionary = {}
		var bark_lines: Array[String] = []
		if mode == "materialized" and dialogue_runtime != null and dialogue_runtime.has_method("request_npc_conversation_block"):
			dialogue_block = dialogue_runtime.request_npc_conversation_block(
				conversation_id,
				_build_npc_dialogue_payload(citizen_a, citizen_b, topic)
			)
		elif mode == "bark":
			bark_lines = _build_bark_lines(citizen_a, citizen_b, topic)
		citizen_a.set_runtime_conversation_state(mode, citizen_b.citizen_name, topic)
		citizen_b.set_runtime_conversation_state(mode, citizen_a.citizen_name, topic)
		_upsert_commitment(citizen_a, "meeting", _get_int("npc_npc.commitment_lock_minutes", 10), {
			"conversation_id": conversation_id
		})
		_upsert_commitment(citizen_b, "meeting", _get_int("npc_npc.commitment_lock_minutes", 10), {
			"conversation_id": conversation_id
		})
		if mode == "materialized":
			_upsert_commitment(citizen_a, "npc_dialog_materialized", _get_int("npc_npc.commitment_lock_minutes", 10), {
				"conversation_id": conversation_id
			})
			_upsert_commitment(citizen_b, "npc_dialog_materialized", _get_int("npc_npc.commitment_lock_minutes", 10), {
				"conversation_id": conversation_id
			})

		var started_at_sec := _runtime_sec
		var last_mode_change_sec := _runtime_sec
		if not previous_entry.is_empty():
			started_at_sec = float(previous_entry.get("started_at_sec", _runtime_sec))
			last_mode_change_sec = float(previous_entry.get("last_mode_change_sec", _runtime_sec))
			if str(previous_entry.get("mode", "")) != mode:
				last_mode_change_sec = _runtime_sec

		active_conversations[conversation_id] = {
			"id": conversation_id,
			"participant_ids": (entry.get("participant_ids", []) as Array).duplicate(),
			"participants": (entry.get("participants", []) as Array).duplicate(),
			"mode": mode,
			"start_mode": start_mode,
			"topic": topic,
			"dialogue_state": str(dialogue_block.get("state", "")),
			"dialogue_source": "bark" if mode == "bark" else str(dialogue_block.get("source", "")),
			"dialogue_model": str(dialogue_block.get("model", "")),
			"generated_lines": bark_lines if mode == "bark" else (dialogue_block.get("lines", []) as Array).duplicate(),
			"midpoint": entry.get("midpoint", Vector3.ZERO),
			"player_distance": float(entry.get("player_distance", INF)),
			"started_at_sec": started_at_sec,
			"last_mode_change_sec": last_mode_change_sec,
			"age_sec": maxf(_runtime_sec - started_at_sec, 0.0),
			"abort_reason": ""
		}

	_active_conversations = active_conversations

func _gather_conversation_candidates(player_avatar: Citizen, anchor_position: Vector3) -> Array:
	var scored: Array = []
	for citizen in world.citizens:
		if citizen == null or citizen == player_avatar:
			continue
		if not _is_eligible_for_npc_conversation(citizen):
			continue
		var start_mode := _get_npc_conversation_start_mode(citizen)
		if start_mode.is_empty():
			continue
		scored.append({
			"citizen": citizen,
			"distance": citizen.global_position.distance_to(anchor_position),
			"start_mode": start_mode
		})
	scored.sort_custom(_sort_candidate_priority)
	return scored

func _is_eligible_for_npc_conversation(citizen: Citizen, allow_existing_meeting: bool = false) -> bool:
	return _get_conversation_unavailability_reason(citizen, allow_existing_meeting).is_empty()

func _can_continue_npc_conversation(citizen_a: Citizen, citizen_b: Citizen, pair_distance: float) -> bool:
	if citizen_a == null or citizen_b == null or citizen_a == citizen_b:
		return false
	if citizen_a.global_position.distance_to(citizen_b.global_position) > pair_distance:
		return false
	return _is_eligible_for_npc_conversation(citizen_a, true) and _is_eligible_for_npc_conversation(citizen_b, true)

func _get_abort_reason_for_pair(existing_entry: Dictionary, citizen_a: Citizen, citizen_b: Citizen, pair_distance: float) -> String:
	if existing_entry.is_empty() or citizen_a == null or citizen_b == null:
		return ""
	if _has_abort_reason("participant_left_area") and citizen_a.global_position.distance_to(citizen_b.global_position) > pair_distance:
		return "participant_left_area"
	if _has_abort_reason("player_interrupted"):
		if citizen_a.has_method("has_active_lod_commitment") and citizen_a.has_active_lod_commitment(world, ["player_dialog"]):
			return "player_interrupted"
		if citizen_b.has_method("has_active_lod_commitment") and citizen_b.has_active_lod_commitment(world, ["player_dialog"]):
			return "player_interrupted"
	if _has_abort_reason("one_participant_became_busy"):
		var unavailable_a := _get_conversation_unavailability_reason(citizen_a, true)
		var unavailable_b := _get_conversation_unavailability_reason(citizen_b, true)
		if not unavailable_a.is_empty() and unavailable_a != "meeting_locked":
			return "one_participant_became_busy"
		if not unavailable_b.is_empty() and unavailable_b != "meeting_locked":
			return "one_participant_became_busy"
	if _has_abort_reason("topic_expired"):
		var age_limit := _get_float("modes.materialized.cache_ttl_sec", 45.0)
		if age_limit > 0.0:
			var started_at_sec := float(existing_entry.get("started_at_sec", _runtime_sec))
			if _runtime_sec - started_at_sec >= age_limit:
				return "topic_expired"
	return ""

func _clear_runtime_conversation_states() -> void:
	for citizen in world.citizens:
		if citizen != null and citizen.has_method("clear_runtime_conversation_state"):
			citizen.clear_runtime_conversation_state()

func _remove_transient_commitments() -> void:
	for citizen in world.citizens:
		if citizen == null:
			continue
		if citizen.has_method("remove_lod_commitment"):
			citizen.remove_lod_commitment("npc_dialog_materialized")
			citizen.remove_lod_commitment("player_dialog")

func _remove_stale_player_interest_commitments(
	selected_citizen: Citizen,
	controlled_citizen: Citizen,
	player_avatar: Citizen
) -> void:
	for citizen in world.citizens:
		if citizen == null or not citizen.has_method("remove_lod_commitment"):
			continue
		if citizen == selected_citizen or citizen == controlled_citizen or citizen == player_avatar:
			continue
		citizen.remove_lod_commitment("player_interest")

func _upsert_commitment(citizen: Citizen, commitment_type: String, lock_minutes: int, metadata: Dictionary = {}) -> void:
	if citizen == null or not citizen.has_method("upsert_lod_commitment"):
		return
	var future := _future_time(lock_minutes)
	citizen.upsert_lod_commitment(
		commitment_type,
		int(future.get("day", world.world_day())),
		int(future.get("minute", world.time.get_hour() * 60 + world.time.get_minute())),
		1.0,
		metadata
	)

func _future_time(offset_minutes: int) -> Dictionary:
	var current_day := world.world_day()
	var current_total := world.time.get_hour() * 60 + world.time.get_minute() + maxi(offset_minutes, 0)
	var extra_days: int = current_total / (24 * 60)
	var minute_of_day := current_total % (24 * 60)
	return {
		"day": current_day + extra_days,
		"minute": minute_of_day
	}

func _make_pair_id(a: Citizen, b: Citizen) -> String:
	var ids := [a.get_instance_id(), b.get_instance_id()]
	ids.sort()
	return "conv_%s_%s" % [str(ids[0]), str(ids[1])]

func _build_citizen_lookup() -> Dictionary:
	var lookup: Dictionary = {}
	for citizen in world.citizens:
		if citizen == null:
			continue
		lookup[citizen.get_instance_id()] = citizen
	return lookup

func _pick_topic(conversation_id: String) -> String:
	var raw_topics: Variant = _get_value("npc_npc.topics", [])
	if raw_topics is not Array or raw_topics.is_empty():
		return str(_get_value("lifecycle.default_topic", "smalltalk"))
	var topics: Array = raw_topics as Array
	var day := world.world_day()
	var index: int = abs((conversation_id + "_%d" % day).hash()) % topics.size()
	return str(topics[index])

func _resolve_topic_for_pair(conversation_id: String, citizen_a: Citizen, citizen_b: Citizen, start_mode: String) -> String:
	if start_mode == "committed_meeting":
		var scheduled_topic := _get_scheduled_meeting_topic(citizen_a, citizen_b)
		if not scheduled_topic.is_empty():
			return scheduled_topic
	return _pick_topic(conversation_id)

func _get_anchor_position(player_avatar: Citizen, player_control_active: bool) -> Vector3:
	if player_control_active and player_avatar != null:
		return player_avatar.global_position
	var selected_citizen: Citizen = selection_state_controller.get_selected_citizen()
	if selected_citizen != null:
		return selected_citizen.global_position
	var anchor := city_camera.global_position if city_camera != null else world.get_world_center()
	anchor.y = world.get_ground_fallback_y()
	return anchor

func _resolve_mode_for_pair(conversation_id: String, player_distance: float) -> String:
	if is_inf(player_distance):
		return "abstract"

	var previous_entry: Variant = _active_conversations.get(conversation_id, {})
	var previous_mode := ""
	if previous_entry is Dictionary:
		previous_mode = str((previous_entry as Dictionary).get("mode", ""))

	var bark_enter := _get_float("distance_thresholds_m.bark_enter", 20.0)
	var bark_exit := maxf(_get_float("distance_thresholds_m.bark_exit", bark_enter), bark_enter)
	var materialize_enter := _get_float("distance_thresholds_m.materialize_enter", 8.0)
	var materialize_exit := maxf(_get_float("distance_thresholds_m.materialize_exit", materialize_enter), materialize_enter)
	var allow_abstract_to_bark := _get_bool("transitions.abstract_to_bark.requires_player_in_range", true)
	var allow_bark_to_materialized := _get_bool("transitions.bark_to_materialized.requires_player_very_near", true)
	var allow_materialized_to_abstract := _get_bool("transitions.materialized_to_abstract.when_player_leaves_range", true)

	if previous_mode == "materialized":
		if not allow_materialized_to_abstract or player_distance <= materialize_exit:
			return "materialized"
	elif (not allow_bark_to_materialized and player_distance <= bark_enter) or player_distance <= materialize_enter:
		return "materialized"

	if previous_mode == "bark":
		if player_distance <= bark_exit:
			return "bark"
	elif not allow_abstract_to_bark or player_distance <= bark_enter:
		return "bark"

	return "abstract"

func _build_npc_dialogue_payload(citizen_a: Citizen, citizen_b: Citizen, topic: String) -> Dictionary:
	return {
		"participant_a": _build_citizen_dialogue_profile(citizen_a),
		"participant_b": _build_citizen_dialogue_profile(citizen_b),
		"relationship": "acquaintance",
		"location": _describe_shared_location(citizen_a, citizen_b),
		"weather": "clear",
		"topic": topic,
		"tone": _derive_conversation_tone(citizen_a, citizen_b)
	}

func _build_citizen_dialogue_profile(citizen: Citizen) -> Dictionary:
	if citizen == null:
		return {}
	return {
		"name": citizen.citizen_name,
		"mood": _describe_citizen_mood(citizen),
		"needs": {
			"hunger": roundf(citizen.needs.hunger),
			"energy": roundf(citizen.needs.energy),
			"fun": roundf(citizen.needs.fun),
			"health": roundf(citizen.needs.health)
		},
		"current_goal": citizen.current_action.label if citizen.current_action != null else "idle",
		"location": citizen.current_location.building_name if citizen.current_location != null else "street"
	}

func _describe_shared_location(citizen_a: Citizen, citizen_b: Citizen) -> String:
	if citizen_a != null and citizen_a.current_location != null:
		return citizen_a.current_location.building_name
	if citizen_b != null and citizen_b.current_location != null:
		return citizen_b.current_location.building_name
	return "street"

func _derive_conversation_tone(citizen_a: Citizen, citizen_b: Citizen) -> String:
	var high_stress := false
	for citizen in [citizen_a, citizen_b]:
		if citizen == null:
			continue
		if citizen.needs.hunger >= 75.0 or citizen.needs.energy <= 20.0:
			high_stress = true
			break
	return "tense" if high_stress else "light"

func _describe_citizen_mood(citizen: Citizen) -> String:
	if citizen == null:
		return "neutral"
	if citizen.needs.energy <= 18.0:
		return "exhausted"
	if citizen.needs.hunger >= 80.0:
		return "hungry"
	if citizen.needs.fun <= 20.0:
		return "bored"
	if citizen.needs.health <= 35.0:
		return "unwell"
	return "calm"

func _sort_candidate_priority(a, b) -> bool:
	var a_mode := str(a.get("start_mode", ""))
	var b_mode := str(b.get("start_mode", ""))
	var a_priority := _get_start_mode_priority(a_mode)
	var b_priority := _get_start_mode_priority(b_mode)
	if a_priority != b_priority:
		return a_priority > b_priority
	return float(a.get("distance", INF)) < float(b.get("distance", INF))

func _sort_conversation_entries(a, b) -> bool:
	return float(a.get("player_distance", INF)) < float(b.get("player_distance", INF))

func _build_bark_lines(citizen_a: Citizen, citizen_b: Citizen, topic: String) -> Array[String]:
	var bark_lines: Array[String] = []
	var max_lines := maxi(_get_int("modes.bark.max_lines", 2), 1)
	var raw_lines: Variant = _get_value("fallback_barks.%s" % topic, [])
	if raw_lines is Array:
		var speaker_names := [
			citizen_a.citizen_name if citizen_a != null else "Citizen A",
			citizen_b.citizen_name if citizen_b != null else "Citizen B"
		]
		var index := 0
		for raw_line in raw_lines:
			var clean_line := str(raw_line).strip_edges()
			if clean_line.is_empty():
				continue
			var speaker := str(speaker_names[index % speaker_names.size()])
			bark_lines.append("%s: %s" % [speaker, clean_line])
			index += 1
			if bark_lines.size() >= max_lines:
				break
	if bark_lines.is_empty():
		bark_lines = _build_default_bark_lines(citizen_a, citizen_b, topic, max_lines)
	return bark_lines

func _build_default_bark_lines(citizen_a: Citizen, citizen_b: Citizen, topic: String, max_lines: int) -> Array[String]:
	var speaker_a := citizen_a.citizen_name if citizen_a != null else "Citizen A"
	var speaker_b := citizen_b.citizen_name if citizen_b != null else "Citizen B"
	var lines: Array[String] = [
		"%s: Busy day around here." % speaker_a,
		"%s: Yeah, especially with %s on my mind." % [speaker_b, topic]
	]
	if lines.size() > max_lines:
		lines.resize(max_lines)
	return lines

func _get_conversation_unavailability_reason(citizen: Citizen, allow_existing_meeting: bool = false) -> String:
	if citizen == null:
		return "missing"
	if citizen.has_method("is_manual_control_enabled") and citizen.is_manual_control_enabled():
		return "manual_control"
	if citizen.has_method("is_click_move_mode_enabled") and citizen.is_click_move_mode_enabled():
		return "click_move"
	if citizen.has_method("get_simulation_lod_tier") and citizen.get_simulation_lod_tier() == "coarse":
		return "coarse"
	if citizen.has_method("is_inside_building") and citizen.is_inside_building():
		return "inside_building"
	if citizen.has_method("is_travelling") and citizen.is_travelling():
		return "travelling"
	if citizen.has_method("has_active_lod_commitment") and citizen.has_active_lod_commitment(world, ["player_dialog"]):
		return "locked"
	if not allow_existing_meeting and not _get_runtime_meeting_commitment(citizen).is_empty():
		return "meeting_locked"
	if citizen.current_action != null:
		return "busy_action"
	return ""

func _get_npc_conversation_start_mode(citizen: Citizen) -> String:
	if citizen == null:
		return ""
	if _qualifies_for_committed_meeting_start(citizen):
		return "committed_meeting"
	if _qualifies_for_smalltalk_start(citizen):
		return "smalltalk"
	return ""

func _qualifies_for_smalltalk_start(citizen: Citizen) -> bool:
	var rule := _get_start_rule("npc_npc_smalltalk")
	if _get_rule_max_participants(rule) < 2:
		return false
	if _get_citizen_social_need_proxy(citizen) < float(rule.get("min_social_need", 0.0)):
		return false
	if _get_citizen_stress_proxy(citizen) > float(rule.get("max_stress", 1.0)):
		return false
	return true

func _qualifies_for_committed_meeting_start(citizen: Citizen) -> bool:
	var rule := _get_start_rule("npc_npc_committed_meeting")
	if _get_rule_max_participants(rule) < 2:
		return false
	if bool(rule.get("requires_commitment", false)) and _get_scheduled_meeting_commitment(citizen).is_empty():
		return false
	return not _get_scheduled_meeting_commitment(citizen).is_empty()

func _pair_start_modes_are_compatible(
	citizen_a: Citizen,
	start_mode_a: String,
	citizen_b: Citizen,
	start_mode_b: String
) -> bool:
	if citizen_a == null or citizen_b == null:
		return false
	if start_mode_a == "committed_meeting" or start_mode_b == "committed_meeting":
		return start_mode_a == "committed_meeting" \
			and start_mode_b == "committed_meeting" \
			and _scheduled_meeting_commitments_are_compatible(citizen_a, citizen_b)
	return start_mode_a == "smalltalk" and start_mode_b == "smalltalk"

func _infer_pair_start_mode(citizen_a: Citizen, citizen_b: Citizen) -> String:
	if _scheduled_meeting_commitments_are_compatible(citizen_a, citizen_b):
		return "committed_meeting"
	if _qualifies_for_smalltalk_start(citizen_a) and _qualifies_for_smalltalk_start(citizen_b):
		return "smalltalk"
	return "smalltalk"

func _scheduled_meeting_commitments_are_compatible(citizen_a: Citizen, citizen_b: Citizen) -> bool:
	var meeting_a := _get_scheduled_meeting_commitment(citizen_a)
	var meeting_b := _get_scheduled_meeting_commitment(citizen_b)
	if meeting_a.is_empty() or meeting_b.is_empty():
		return false
	var partner_a := int(meeting_a.get("partner_id", 0))
	var partner_b := int(meeting_b.get("partner_id", 0))
	if partner_a > 0 and partner_a != citizen_b.get_instance_id():
		return false
	if partner_b > 0 and partner_b != citizen_a.get_instance_id():
		return false
	var key_a := str(meeting_a.get("meeting_key", "")).strip_edges()
	var key_b := str(meeting_b.get("meeting_key", "")).strip_edges()
	if not key_a.is_empty() or not key_b.is_empty():
		return not key_a.is_empty() and key_a == key_b
	return true

func _get_scheduled_meeting_topic(citizen_a: Citizen, citizen_b: Citizen) -> String:
	var meeting_a := _get_scheduled_meeting_commitment(citizen_a)
	var meeting_b := _get_scheduled_meeting_commitment(citizen_b)
	var topic_a := str(meeting_a.get("topic", "")).strip_edges()
	var topic_b := str(meeting_b.get("topic", "")).strip_edges()
	if not topic_a.is_empty() and topic_a == topic_b:
		return topic_a
	if not topic_a.is_empty():
		return topic_a
	return topic_b

func _get_scheduled_meeting_commitment(citizen: Citizen) -> Dictionary:
	for commitment in _get_commitments_of_type(citizen, "meeting"):
		if str(commitment.get("conversation_id", "")).strip_edges().is_empty():
			return commitment
	return {}

func _get_runtime_meeting_commitment(citizen: Citizen) -> Dictionary:
	for commitment in _get_commitments_of_type(citizen, "meeting"):
		if not str(commitment.get("conversation_id", "")).strip_edges().is_empty():
			return commitment
	return {}

func _get_commitments_of_type(citizen: Citizen, commitment_type: String) -> Array:
	var entries: Array = []
	if citizen == null or not citizen.has_method("get_active_lod_commitments"):
		return entries
	var raw_entries: Array = citizen.get_active_lod_commitments(world)
	for entry in raw_entries:
		if entry is not Dictionary:
			continue
		var typed_entry := entry as Dictionary
		if str(typed_entry.get("type", "")) != commitment_type:
			continue
		entries.append(typed_entry.duplicate(true))
	return entries

func _get_start_rule(rule_key: String) -> Dictionary:
	var raw_rule: Variant = _get_value("conversation_start_rules.%s" % rule_key, {})
	return raw_rule as Dictionary if raw_rule is Dictionary else {}

func _get_rule_max_participants(rule: Dictionary) -> int:
	if rule.is_empty():
		return 2
	return int(rule.get("max_participants", 2))

func _get_citizen_social_need_proxy(citizen: Citizen) -> float:
	if citizen == null:
		return 0.0
	var fun_pressure := clampf((100.0 - citizen.needs.fun) / 100.0, 0.0, 1.0)
	var idle_bonus := 0.15 if citizen.current_action == null and not citizen.is_travelling() else 0.0
	return clampf(fun_pressure + idle_bonus, 0.0, 1.0)

func _get_citizen_stress_proxy(citizen: Citizen) -> float:
	if citizen == null:
		return 1.0
	var hunger_pressure := clampf(citizen.needs.hunger / 100.0, 0.0, 1.0)
	var energy_pressure := clampf((100.0 - citizen.needs.energy) / 100.0, 0.0, 1.0)
	var health_pressure := clampf((100.0 - citizen.needs.health) / 100.0, 0.0, 1.0)
	return clampf(maxf(hunger_pressure, maxf(energy_pressure, health_pressure)), 0.0, 1.0)

func _get_start_mode_priority(start_mode: String) -> int:
	match start_mode:
		"committed_meeting":
			return 2
		"smalltalk":
			return 1
		_:
			return 0

func _has_abort_reason(reason: String) -> bool:
	var reasons: Variant = _get_value("abort_reasons", [])
	if reasons is not Array:
		return false
	for entry in reasons:
		if str(entry) == reason:
			return true
	return false

func _has_interactive_budget_for(citizen: Citizen) -> bool:
	var active_budget := maxi(_get_int("lifecycle.max_parallel_interactive_conversations", 1), 0)
	if active_budget <= 0:
		return true
	if citizen != null and _player_dialog_sessions.has(citizen.get_instance_id()):
		return true
	return _player_dialog_sessions.size() < active_budget

func _describe_player_dialog_unavailable_reason(citizen: Citizen, availability: Dictionary) -> String:
	if not _has_interactive_budget_for(citizen):
		return "Another dialog is already active"
	match str(availability.get("reason", "unavailable")):
		"ready":
			return "Ready to talk"
		"player_mode_required":
			return "Enable Player Mode first"
		"move_closer":
			var distance := float(availability.get("distance", INF))
			var max_distance := float(availability.get("max_distance", 0.0))
			if is_finite(distance) and max_distance > 0.0:
				return "Move closer (%.1fm / %.1fm)" % [distance, max_distance]
			return "Move closer"
		"citizen_not_active":
			return "Citizen is not active right now"
		"citizen_inside":
			return "Citizen is inside a building"
		"player_avatar":
			return "Player avatar cannot talk to itself"
		"no_citizen":
			return "No citizen selected"
		_:
			return "Dialog unavailable"

func _describe_player_dialog_pending_error(error_code: String) -> String:
	match error_code:
		"reply_pending":
			return "Waiting for the current NPC reply..."
		"":
			return ""
		_:
			return error_code

func _ensure_player_dialog_session(citizen: Citizen) -> Dictionary:
	var citizen_id := citizen.get_instance_id()
	var session_variant: Variant = _player_dialog_sessions.get(citizen_id, {})
	if session_variant is Dictionary:
		return (session_variant as Dictionary).duplicate(true)
	return {
		"session_id": "player_%d" % citizen_id,
		"citizen_id": citizen_id,
		"citizen_name": citizen.citizen_name,
		"messages": [],
		"pending_reply": false,
		"pending_request_key": "",
		"pending_payload": {},
		"pending_error": "",
		"recent_summary": "",
		"turn_count": 0,
		"farewell_requested": false,
		"auto_close_due_at_sec": -1.0,
		"last_player_message_at_sec": -1.0,
		"active": true
	}

func _build_player_dialogue_payload(citizen: Citizen, session: Dictionary) -> Dictionary:
	var messages: Array = session.get("messages", []) as Array
	var recent_turns: Array = []
	for message in messages:
		if message is not Dictionary:
			continue
		recent_turns.append((message as Dictionary).duplicate(true))
	var current_goal_context := _build_player_goal_context(citizen)
	var nearby_places := _build_player_nearby_places(citizen)
	var known_places := _build_player_known_places(citizen)
	return {
		"name": citizen.citizen_name,
		"personality": _describe_player_dialog_personality(citizen),
		"mood": _describe_citizen_mood(citizen),
		"needs": {
			"hunger": roundf(citizen.needs.hunger),
			"energy": roundf(citizen.needs.energy),
			"fun": roundf(citizen.needs.fun),
			"health": roundf(citizen.needs.health)
		},
		"wallet_balance": citizen.wallet.balance,
		"budget_state": _describe_wallet_state(citizen),
		"location": citizen.current_location.building_name if citizen.current_location != null else "street",
		"location_context": _build_player_location_context(citizen, nearby_places),
		"district": _get_player_dialog_district(citizen),
		"weather": "clear",
		"current_goal": str(current_goal_context.get("summary", "idle")),
		"current_goal_context": current_goal_context,
		"known_places": known_places,
		"nearby_places": nearby_places,
		"job_context": _build_player_job_context(citizen),
		"reply_language": _infer_player_dialog_reply_language(session),
		"relationship_to_player": "direct conversation",
		"recent_summary": str(session.get("recent_summary", "")),
		"last_turns": recent_turns,
		"grounding_rules": [
			"Only mention places listed in known_places or nearby_places by name.",
			"Do not invent landmarks, rivers, shops, or buildings.",
			"If unsure, say you are not sure instead of making something up."
		]
	}

func _infer_player_dialog_reply_language(session: Dictionary) -> String:
	var recent_summary := str(session.get("recent_summary", "")).to_lower()
	var messages: Variant = session.get("messages", [])
	if messages is Array:
		var typed_messages := messages as Array
		for idx in range(typed_messages.size() - 1, -1, -1):
			var entry: Variant = typed_messages[idx]
			if entry is not Dictionary:
				continue
			var typed_entry := entry as Dictionary
			if str(typed_entry.get("speaker", "")).to_lower() != "player":
				continue
			var player_text := str(typed_entry.get("text", "")).to_lower()
			if _contains_any_dialogue_token(player_text, ["hallo", "moin", "servus", "wie", "warum", "wieso", "wo", "wohin", "wer", "und", "gut", "ja", "nein"]):
				return "german"
			if _contains_any_dialogue_token(player_text, ["hello", "how", "where", "why", "good", "yeah", "no", "lets", "let's"]):
				return "english"
	if _contains_any_dialogue_token(recent_summary, ["hallo", "wie", "warum", "wo", "und", "gerade"]):
		return "german"
	return "german"

func _contains_any_dialogue_token(text: String, tokens: Array[String]) -> bool:
	if text.is_empty():
		return false
	for token in tokens:
		if text.contains(token):
			return true
	return false

func _build_player_location_context(citizen: Citizen, nearby_places: Array) -> Dictionary:
	return {
		"inside_building": citizen.is_inside_building(),
		"travelling": citizen.is_travelling(),
		"location_name": citizen.current_location.building_name if citizen.current_location != null else "street",
		"district": _get_player_dialog_district(citizen),
		"nearby_places": nearby_places.duplicate(true)
	}

func _build_player_goal_context(citizen: Citizen) -> Dictionary:
	var action_label := citizen.current_action.label if citizen.current_action != null else "idle"
	var target_building := citizen.get_debug_travel_target_building() if citizen.has_method("get_debug_travel_target_building") else null
	var summary := _describe_player_goal_summary(action_label, target_building, citizen.is_travelling())
	return {
		"action": action_label,
		"travelling": citizen.is_travelling(),
		"target_name": target_building.building_name if target_building != null else "",
		"target_service": target_building.get_service_type() if target_building != null else "",
		"summary": summary
	}

func _build_player_job_context(citizen: Citizen) -> Dictionary:
	if citizen.job == null:
		return {
			"employed": false
		}
	return {
		"employed": true,
		"title": citizen.job.title,
		"workplace": citizen.job.workplace.building_name if citizen.job.workplace != null else "",
		"preferred_workplace": citizen.job.preferred_workplace.building_name if citizen.job.preferred_workplace != null else ""
	}

func _build_player_known_places(citizen: Citizen) -> Array:
	var entries: Array = []
	for building in [
		citizen.home,
		citizen.favorite_restaurant,
		citizen.favorite_supermarket,
		citizen.favorite_shop,
		citizen.favorite_cinema,
		citizen.favorite_park,
		citizen.job.workplace if citizen.job != null else null,
		citizen.job.preferred_workplace if citizen.job != null else null
	]:
		var fact := _build_building_dialogue_fact(building, citizen.global_position, false)
		if not fact.is_empty():
			entries.append(fact)
	return _dedupe_dialogue_place_facts(entries)

func _build_player_nearby_places(citizen: Citizen, max_places: int = 4) -> Array:
	var entries: Array = []
	if world == null or citizen == null:
		return entries
	for building in world.buildings:
		if building == null or not is_instance_valid(building):
			continue
		var fact := _build_building_dialogue_fact(building, citizen.global_position, true)
		if fact.is_empty():
			continue
		entries.append(fact)
	entries.sort_custom(_sort_dialogue_place_facts_by_distance)
	var deduped := _dedupe_dialogue_place_facts(entries)
	if deduped.size() > max_places:
		deduped.resize(max_places)
	return deduped

func _build_building_dialogue_fact(building: Building, origin: Vector3, include_distance: bool) -> Dictionary:
	if building == null or not is_instance_valid(building):
		return {}
	var fact := {
		"name": building.building_name,
		"service": building.get_service_type(),
		"district": world.get_building_district_id(building) if world != null and world.has_method("get_building_district_id") else "",
		"open_now": building.is_open(world.time.get_hour()) if world != null and world.time != null else true
	}
	if include_distance:
		fact["distance_m"] = roundf(origin.distance_to(building.global_position) * 10.0) / 10.0
	return fact

func _dedupe_dialogue_place_facts(entries: Array) -> Array:
	var deduped: Array = []
	var seen: Dictionary = {}
	for entry in entries:
		if entry is not Dictionary:
			continue
		var fact := entry as Dictionary
		var key := str(fact.get("name", "")).strip_edges()
		if key.is_empty() or seen.has(key):
			continue
		seen[key] = true
		deduped.append(fact.duplicate(true))
	return deduped

func _sort_dialogue_place_facts_by_distance(a: Variant, b: Variant) -> bool:
	var fact_a: Dictionary = a as Dictionary if a is Dictionary else {}
	var fact_b: Dictionary = b as Dictionary if b is Dictionary else {}
	return float(fact_a.get("distance_m", INF)) < float(fact_b.get("distance_m", INF))

func _extract_place_names(entries: Variant) -> Array[String]:
	var names: Array[String] = []
	if entries is not Array:
		return names
	for entry in entries:
		if entry is not Dictionary:
			continue
		var name := str((entry as Dictionary).get("name", "")).strip_edges()
		if name.is_empty():
			continue
		names.append(name)
	return names

func _describe_wallet_state(citizen: Citizen) -> String:
	if citizen.wallet.balance <= 25:
		return "very_low"
	if citizen.wallet.balance <= 80:
		return "low"
	if citizen.wallet.balance <= 180:
		return "stable"
	return "comfortable"

func _get_player_dialog_district(citizen: Citizen) -> String:
	if world == null or citizen == null or not world.has_method("get_citizen_district_id"):
		return ""
	return world.get_citizen_district_id(citizen)

func _describe_player_goal_summary(action_label: String, target_building: Building, travelling: bool) -> String:
	var clean_action := action_label.strip_edges()
	if clean_action.is_empty():
		clean_action = "idle"
	if target_building != null:
		if clean_action == "GoTo":
			return "going to %s" % target_building.building_name
		return "%s at %s" % [clean_action, target_building.building_name]
	if travelling:
		if clean_action == "GoTo":
			return "travelling"
		return "%s while travelling" % clean_action
	match clean_action:
		"idle":
			return "taking it easy"
		"Sleep":
			return "trying to rest"
		"Work":
			return "focused on work"
		_:
			return clean_action

func _is_farewell_player_line(text: String) -> bool:
	var lower_text := text.to_lower().strip_edges()
	if lower_text.is_empty():
		return false
	var keywords: Array[String] = _get_string_array("player_npc.farewell_keywords")
	if keywords.is_empty():
		keywords = ["bye", "goodbye", "see you", "ciao", "tschuess", "tschuess", "tschuss", "cu", "machs gut", "bis spaeter", "bis bald"]
	return _contains_any_dialogue_token(lower_text, keywords)

func _should_auto_close_player_dialog_session(session: Dictionary) -> bool:
	if bool(session.get("pending_reply", false)):
		return false
	var due_at := float(session.get("auto_close_due_at_sec", -1.0))
	return due_at > 0.0 and _runtime_sec >= due_at

func _describe_player_dialog_personality(citizen: Citizen) -> String:
	var traits: Array[String] = []
	if citizen.work_motivation >= 1.15:
		traits.append("hardworking")
	elif citizen.work_motivation <= 0.85:
		traits.append("laid back")
	if citizen.park_interest >= 0.55:
		traits.append("likes parks")
	elif citizen.park_interest <= 0.2:
		traits.append("prefers indoors")
	if traits.is_empty():
		traits.append("ordinary")
	return ", ".join(traits)

func _compress_player_dialog_session_memory(session: Dictionary) -> void:
	var keep_last_turns := _get_int("player_npc.session_memory_turns", 6)
	var summarize_after_turns := _get_int("player_npc.summary_after_turns", 4)
	var messages := (session.get("messages", []) as Array).duplicate(true)
	if messages.size() < summarize_after_turns or messages.size() <= keep_last_turns:
		session["messages"] = messages
		return
	var overflow := messages.size() - keep_last_turns
	var summary_parts: Array[String] = []
	for index in range(overflow):
		var entry := messages[index] as Dictionary
		summary_parts.append("%s: %s" % [str(entry.get("speaker", "")), str(entry.get("text", ""))])
	var existing_summary := str(session.get("recent_summary", ""))
	var appended_summary := " | ".join(summary_parts)
	session["recent_summary"] = appended_summary if existing_summary.is_empty() else "%s | %s" % [existing_summary, appended_summary]
	session["messages"] = messages.slice(overflow)

func _apply_player_dialog_reply_to_session(session: Dictionary, citizen: Citizen, reply_result: Dictionary) -> void:
	session["pending_reply"] = false
	session["pending_error"] = ""
	session["pending_request_key"] = ""
	session["pending_payload"] = {}
	var reply_text := str(reply_result.get("text", "")).strip_edges()
	if reply_text.is_empty():
		_log_player_dialog(citizen, "NPC reply was empty")
		return
	var messages: Array = (session.get("messages", []) as Array).duplicate(true)
	messages.append({
		"speaker": citizen.citizen_name,
		"text": reply_text
	})
	session["messages"] = messages
	_compress_player_dialog_session_memory(session)
	if bool(session.get("farewell_requested", false)):
		session["auto_close_due_at_sec"] = _runtime_sec + _get_float("player_npc.farewell_auto_close_sec", 2.0)
	else:
		session["auto_close_due_at_sec"] = -1.0
	_log_player_dialog(
		citizen,
		"NPC reply source=%s model=%s text=%s" % [
			str(reply_result.get("source", "")),
			str(reply_result.get("model", "")),
			reply_text
		]
	)

func _build_player_fallback_reply(citizen: Citizen) -> String:
	return "Sure. What's up?"

func _refresh_player_dialog_control_lock() -> void:
	if selection_state_controller == null:
		return
	var locked := _has_active_player_dialog_session()
	if selection_state_controller.has_method("set_player_dialog_input_locked"):
		selection_state_controller.set_player_dialog_input_locked(locked)
		return
	if selection_state_controller.has_method("set_player_control_input_locked"):
		selection_state_controller.set_player_control_input_locked(locked)

func _has_active_player_dialog_session() -> bool:
	for session_variant in _player_dialog_sessions.values():
		if session_variant is not Dictionary:
			continue
		if bool((session_variant as Dictionary).get("active", false)):
			return true
	return false

func _on_player_dialogue_ready(request_key: String) -> void:
	if dialogue_runtime == null or not _player_dialog_request_to_citizen.has(request_key):
		return
	var citizen_id := int(_player_dialog_request_to_citizen.get(request_key, 0))
	var session_variant: Variant = _player_dialog_sessions.get(citizen_id, {})
	if session_variant is not Dictionary:
		_player_dialog_request_to_citizen.erase(request_key)
		return
	var session := (session_variant as Dictionary).duplicate(true)
	if str(session.get("pending_request_key", "")) != request_key:
		_player_dialog_request_to_citizen.erase(request_key)
		return
	var payload := (session.get("pending_payload", {}) as Dictionary).duplicate(true)
	var reply_result: Dictionary = dialogue_runtime.request_player_reply(request_key, payload)
	var citizen := instance_from_id(citizen_id) as Citizen
	if citizen == null or not is_instance_valid(citizen):
		_player_dialog_sessions.erase(citizen_id)
		_player_dialog_request_to_citizen.erase(request_key)
		_refresh_player_dialog_control_lock()
		return
	_log_player_dialog(
		citizen,
		"Async runtime reply source=%s model=%s request=%s" % [
			str(reply_result.get("source", "")),
			str(reply_result.get("model", "")),
			request_key
		]
	)
	_apply_player_dialog_reply_to_session(session, citizen, reply_result)
	_player_dialog_sessions[citizen_id] = session
	_player_dialog_request_to_citizen.erase(request_key)

func _log_player_dialog(citizen: Citizen, message: String) -> void:
	var citizen_name := citizen.citizen_name if citizen != null else "Unknown"
	SimLogger.log("[PlayerDialog %s] %s" % [citizen_name, message])

func _load_config() -> Dictionary:
	var defaults := {
		"lifecycle": {
			"default_topic": "smalltalk"
		},
		"distance_thresholds_m": {
			"bark_enter": 20.0,
			"materialize_enter": 8.0,
			"interactive_auto_offer": 3.0
		},
		"pairing": {
			"refresh_interval_sec": 0.8,
			"max_active_pairs": 4,
			"max_participant_distance_m": 3.5
		},
		"npc_npc": {
			"topics": ["smalltalk"],
			"commitment_lock_minutes": 10
		},
		"player_interaction": {
			"selection_interest_lock_minutes": 15,
			"control_interest_lock_minutes": 20,
			"interactive_offer_lock_minutes": 20
		},
		"player_npc": {
			"session_memory_turns": 6,
			"summary_after_turns": 4,
			"commitment_lock_minutes": 20,
			"cancel_if_player_leaves_range": true,
			"farewell_auto_close_sec": 2.0,
			"farewell_keywords": ["bye", "goodbye", "see you", "ciao", "tschuess", "tschuss", "bis spaeter", "bis bald", "machs gut", "cu"]
		},
		"conversation_start_rules": {
			"npc_npc_smalltalk": {
				"min_social_need": 0.35,
				"max_stress": 0.85,
				"max_participants": 2
			},
			"npc_npc_committed_meeting": {
				"requires_commitment": true,
				"max_participants": 4
			}
		}
	}
	if not FileAccess.file_exists(CONFIG_PATH):
		return defaults
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		return defaults
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		_deep_merge(defaults, parsed as Dictionary)
	return defaults

func _deep_merge(base: Dictionary, override: Dictionary) -> void:
	for key in override.keys():
		var override_value: Variant = override[key]
		if base.has(key) and base[key] is Dictionary and override_value is Dictionary:
			_deep_merge(base[key], override_value)
		else:
			base[key] = override_value

func _get_value(path: String, default_value = null):
	var current: Variant = _config
	for part in path.split("."):
		if part.is_empty():
			continue
		if current is Dictionary and current.has(part):
			current = current[part]
			continue
		return default_value
	return current

func _get_int(path: String, default_value: int) -> int:
	return int(_get_value(path, default_value))

func _get_float(path: String, default_value: float) -> float:
	return float(_get_value(path, default_value))

func _get_bool(path: String, default_value: bool) -> bool:
	return bool(_get_value(path, default_value))

func _get_string_array(path: String) -> Array[String]:
	var values: Variant = _get_value(path, [])
	var result: Array[String] = []
	if values is not Array:
		return result
	for value in values:
		var text := str(value).strip_edges()
		if text.is_empty():
			continue
		result.append(text.to_lower())
	return result
