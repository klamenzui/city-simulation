extends RefCounted
class_name MultiplayerHostAuthority

const NetworkEntityRegistryScript = preload("res://Simulation/Multiplayer/shared/NetworkEntityRegistry.gd")
const WorldSnapshotSerializerScript = preload("res://Simulation/Multiplayer/shared/WorldSnapshotSerializer.gd")

const SNAPSHOT_INTERVAL_SEC := 0.25
const WORLD_STATE_SNAPSHOT_INTERVAL_SEC := 1.0
const LOCAL_HOST_PEER_ID := 1
const CITIZEN_INTERACTION_DISTANCE := 1.2
const INTERACTION_ARRIVAL_TOLERANCE := 0.55
const INTERACTION_EFFECT_DURATION_SEC := 8.0
const INTERACTION_COMMAND_COOLDOWN_SEC := 0.25

var root_node: Node = null
var world: World = null
var session_node: Node = null
var registry = NetworkEntityRegistryScript.new()

var _peer: ENetMultiplayerPeer = null
var _snapshot_sequence: int = 0
var _snapshot_timer: float = 0.0
var _world_state_snapshot_timer: float = 0.0
var _active: bool = false
var _player_citizen_id_by_peer: Dictionary = {}
var _player_input_command_count_by_peer: Dictionary = {}
var _last_player_input_direction_by_peer: Dictionary = {}
var _interaction_command_count_by_peer: Dictionary = {}
var _accepted_interaction_command_count_by_peer: Dictionary = {}
var _rejected_interaction_command_count_by_peer: Dictionary = {}
var _completed_interaction_command_count_by_peer: Dictionary = {}
var _applied_interaction_effect_count_by_peer: Dictionary = {}
var _last_interaction_by_peer: Dictionary = {}
var _last_interaction_effect_by_peer: Dictionary = {}
var _last_interaction_status_by_peer: Dictionary = {}
var _interaction_command_cooldown_by_peer: Dictionary = {}
var _active_interaction_by_peer: Dictionary = {}
var _active_interaction_effect_by_peer: Dictionary = {}
var _local_host_camera_follow_target_id: String = ""

func setup(root_ref: Node, world_ref: World, session_ref: Node) -> void:
	root_node = root_ref
	world = world_ref
	session_node = session_ref
	if world != null and world.has_method("set_simulation_authority_enabled"):
		world.set_simulation_authority_enabled(true)

func start_host(port: int, max_clients: int) -> Error:
	if session_node == null:
		return ERR_UNCONFIGURED
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_server(port, max_clients)
	if err != OK:
		return err
	session_node.multiplayer.multiplayer_peer = _peer
	_connect_signals()
	_active = true
	_snapshot_timer = 0.0
	_world_state_snapshot_timer = WORLD_STATE_SNAPSHOT_INTERVAL_SEC
	if world != null and world.has_method("set_simulation_authority_enabled"):
		world.set_simulation_authority_enabled(true)
	return OK

func stop() -> void:
	_active = false
	_release_all_player_citizens()
	_disconnect_signals()
	if session_node != null and session_node.multiplayer.has_multiplayer_peer():
		session_node.multiplayer.multiplayer_peer = null
	if _peer != null:
		_peer.close()
	_peer = null
	_local_host_camera_follow_target_id = ""

func update(delta: float) -> void:
	if not _active or session_node == null:
		return
	_apply_local_host_player_input()
	_update_interaction_command_cooldowns(delta)
	_update_active_interactions()
	_update_interaction_effects(delta)
	_snapshot_timer -= delta
	if _snapshot_timer <= 0.0:
		_snapshot_timer = SNAPSHOT_INTERVAL_SEC
		send_snapshot_to_all(false)
	_world_state_snapshot_timer -= delta
	if _world_state_snapshot_timer <= 0.0:
		_world_state_snapshot_timer = WORLD_STATE_SNAPSHOT_INTERVAL_SEC
		send_world_state_snapshot_to_all()

func ensure_local_host_player() -> String:
	if not _active:
		return ""
	var entity_id := _assign_player_citizen(LOCAL_HOST_PEER_ID)
	_sync_local_host_player_camera(entity_id)
	return entity_id

func get_local_player_citizen_id() -> String:
	return str(_player_citizen_id_by_peer.get(LOCAL_HOST_PEER_ID, ""))

func get_local_player_citizen() -> Citizen:
	return _find_citizen_by_id(get_local_player_citizen_id())

func get_debug_status() -> Dictionary:
	var total_input_commands := 0
	var command_counts: Dictionary = {}
	for peer_id in _player_input_command_count_by_peer.keys():
		var count := int(_player_input_command_count_by_peer.get(peer_id, 0))
		total_input_commands += count
		command_counts[str(peer_id)] = count
	var assigned_players: Dictionary = {}
	for peer_id in _player_citizen_id_by_peer.keys():
		assigned_players[str(peer_id)] = str(_player_citizen_id_by_peer.get(peer_id, ""))
	return {
		"player_input_command_count": total_input_commands,
		"player_input_command_count_by_peer": command_counts,
		"assigned_player_citizen_ids_by_peer": assigned_players,
		"last_player_input_direction_by_peer": _last_player_input_direction_by_peer.duplicate(true),
		"interaction_command_count": _sum_int_values(_interaction_command_count_by_peer),
		"accepted_interaction_command_count": _sum_int_values(_accepted_interaction_command_count_by_peer),
		"rejected_interaction_command_count": _sum_int_values(_rejected_interaction_command_count_by_peer),
		"completed_interaction_command_count": _sum_int_values(_completed_interaction_command_count_by_peer),
		"applied_interaction_effect_count": _sum_int_values(_applied_interaction_effect_count_by_peer),
		"interaction_command_count_by_peer": _string_keyed_int_dictionary(_interaction_command_count_by_peer),
		"accepted_interaction_command_count_by_peer": _string_keyed_int_dictionary(_accepted_interaction_command_count_by_peer),
		"rejected_interaction_command_count_by_peer": _string_keyed_int_dictionary(_rejected_interaction_command_count_by_peer),
		"completed_interaction_command_count_by_peer": _string_keyed_int_dictionary(_completed_interaction_command_count_by_peer),
		"applied_interaction_effect_count_by_peer": _string_keyed_int_dictionary(_applied_interaction_effect_count_by_peer),
		"last_interaction_by_peer": _last_interaction_by_peer.duplicate(true),
		"last_interaction_effect_by_peer": _last_interaction_effect_by_peer.duplicate(true),
		"interaction_status_by_peer": _last_interaction_status_by_peer.duplicate(true),
		"interaction_command_cooldown_by_peer": _interaction_command_cooldown_debug_dictionary(),
		"active_interaction_by_peer": _active_interaction_debug_dictionary(),
		"active_interaction_effect_by_peer": _active_interaction_effect_debug_dictionary(),
	}

func build_snapshot() -> Dictionary:
	_snapshot_sequence += 1
	return WorldSnapshotSerializerScript.build_snapshot(world, root_node, _snapshot_sequence, registry)

func build_actor_state_snapshot() -> Dictionary:
	_snapshot_sequence += 1
	return WorldSnapshotSerializerScript.build_actor_state_snapshot(world, root_node, _snapshot_sequence, registry)

func build_world_state_snapshot() -> Dictionary:
	_snapshot_sequence += 1
	return WorldSnapshotSerializerScript.build_world_state_snapshot(world, root_node, _snapshot_sequence, registry)

func send_snapshot_to_all(full_snapshot: bool) -> void:
	if session_node == null or not session_node.multiplayer.has_multiplayer_peer():
		return
	var peers := session_node.multiplayer.get_peers()
	if peers.is_empty():
		return
	var base_snapshot := build_snapshot() if full_snapshot else build_actor_state_snapshot()
	for peer_id in peers:
		var snapshot := base_snapshot.duplicate(true)
		_add_peer_snapshot_context(snapshot, int(peer_id))
		_send_snapshot_to_peer(int(peer_id), snapshot, full_snapshot)

func send_world_state_snapshot_to_all() -> void:
	if session_node == null or not session_node.multiplayer.has_multiplayer_peer():
		return
	var peers := session_node.multiplayer.get_peers()
	if peers.is_empty():
		return
	var snapshot := build_world_state_snapshot()
	for peer_id in peers:
		var peer_snapshot := snapshot.duplicate(true)
		_add_peer_snapshot_context(peer_snapshot, int(peer_id))
		_send_world_state_snapshot_to_peer(int(peer_id), peer_snapshot)

func send_full_snapshot_to_peer(peer_id: int) -> void:
	var snapshot := build_snapshot()
	_add_peer_snapshot_context(snapshot, peer_id)
	_send_snapshot_to_peer(peer_id, snapshot, true)

func send_world_state_snapshot_to_peer(peer_id: int) -> void:
	var snapshot := build_world_state_snapshot()
	_add_peer_snapshot_context(snapshot, peer_id)
	_send_world_state_snapshot_to_peer(peer_id, snapshot)

func handle_local_command(command: Dictionary) -> void:
	_handle_authoritative_command(LOCAL_HOST_PEER_ID, command)

func handle_client_command(peer_id: int, command: Dictionary) -> void:
	if peer_id <= 1 or command.is_empty():
		return
	_handle_authoritative_command(peer_id, command)

func _handle_authoritative_command(peer_id: int, command: Dictionary) -> void:
	if command.is_empty():
		return
	match str(command.get("type", "")):
		"player_input":
			_handle_player_input_command(peer_id, command)
		"interact_entity":
			_handle_interact_entity_command(peer_id, command)

func _connect_signals() -> void:
	if session_node == null:
		return
	var peer_connected_cb := Callable(self, "_on_peer_connected")
	var peer_disconnected_cb := Callable(self, "_on_peer_disconnected")
	if not session_node.multiplayer.peer_connected.is_connected(peer_connected_cb):
		session_node.multiplayer.peer_connected.connect(peer_connected_cb)
	if not session_node.multiplayer.peer_disconnected.is_connected(peer_disconnected_cb):
		session_node.multiplayer.peer_disconnected.connect(peer_disconnected_cb)

func _disconnect_signals() -> void:
	if session_node == null:
		return
	var peer_connected_cb := Callable(self, "_on_peer_connected")
	var peer_disconnected_cb := Callable(self, "_on_peer_disconnected")
	if session_node.multiplayer.peer_connected.is_connected(peer_connected_cb):
		session_node.multiplayer.peer_connected.disconnect(peer_connected_cb)
	if session_node.multiplayer.peer_disconnected.is_connected(peer_disconnected_cb):
		session_node.multiplayer.peer_disconnected.disconnect(peer_disconnected_cb)

func _on_peer_connected(peer_id: int) -> void:
	_assign_player_citizen(peer_id)
	send_full_snapshot_to_peer(peer_id)
	send_world_state_snapshot_to_peer(peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	_release_player_citizen(peer_id)

func _send_snapshot_to_peer(peer_id: int, snapshot: Dictionary, full_snapshot: bool) -> void:
	if session_node == null or snapshot.is_empty():
		return
	if full_snapshot:
		session_node.rpc_id(peer_id, "_client_apply_full_snapshot", snapshot)
	else:
		session_node.rpc_id(peer_id, "_client_apply_snapshot", snapshot)

func _send_world_state_snapshot_to_peer(peer_id: int, snapshot: Dictionary) -> void:
	if session_node == null or snapshot.is_empty():
		return
	session_node.rpc_id(peer_id, "_client_apply_world_state_snapshot", snapshot)

func _add_peer_snapshot_context(snapshot: Dictionary, peer_id: int) -> void:
	if str(_player_citizen_id_by_peer.get(peer_id, "")).is_empty():
		_assign_player_citizen(peer_id)
	snapshot["local_player_citizen_id"] = str(_player_citizen_id_by_peer.get(peer_id, ""))

func _assign_player_citizen(peer_id: int) -> String:
	var existing_id := str(_player_citizen_id_by_peer.get(peer_id, ""))
	if not existing_id.is_empty() and _find_citizen_by_id(existing_id) != null:
		return existing_id
	if world == null or root_node == null:
		return ""
	registry.ensure_world_entities(world, root_node)
	var reserved_ids := _reserved_player_citizen_ids()
	var candidates := _player_assignment_candidates(peer_id)
	for citizen in candidates:
		var entity_id := NetworkEntityRegistryScript.get_entity_id(citizen)
		if entity_id.is_empty() or reserved_ids.has(entity_id):
			continue
		_player_citizen_id_by_peer[peer_id] = entity_id
		if citizen.has_method("set_network_server_control_enabled"):
			citizen.set_network_server_control_enabled(true, world)
		return entity_id
	return ""

func _release_player_citizen(peer_id: int) -> void:
	var entity_id := str(_player_citizen_id_by_peer.get(peer_id, ""))
	_player_citizen_id_by_peer.erase(peer_id)
	_active_interaction_by_peer.erase(peer_id)
	_interaction_command_cooldown_by_peer.erase(peer_id)
	_clear_interaction_effect_for_peer(peer_id)
	_last_interaction_status_by_peer.erase(str(peer_id))
	if peer_id == LOCAL_HOST_PEER_ID:
		_local_host_camera_follow_target_id = ""
	var citizen := _find_citizen_by_id(entity_id)
	if citizen != null and citizen.has_method("set_network_server_control_enabled"):
		citizen.set_network_server_control_enabled(false, world)

func _handle_player_input_command(peer_id: int, command: Dictionary) -> void:
	var citizen_id := str(_player_citizen_id_by_peer.get(peer_id, ""))
	if citizen_id.is_empty():
		citizen_id = _assign_player_citizen(peer_id)
	var citizen := _find_citizen_by_id(citizen_id)
	if citizen == null or not citizen.has_method("apply_network_server_control_input"):
		return
	var direction := WorldSnapshotSerializerScript.vector_from_snapshot(command.get("direction", []), Vector3.ZERO)
	direction.y = 0.0
	if direction.length_squared() > 1.0:
		direction = direction.normalized()
	if direction.length_squared() > 0.0001:
		_clear_interaction_effect_for_peer(peer_id)
	_player_input_command_count_by_peer[peer_id] = int(_player_input_command_count_by_peer.get(peer_id, 0)) + 1
	_last_player_input_direction_by_peer[str(peer_id)] = [direction.x, direction.y, direction.z]
	citizen.apply_network_server_control_input(direction, world)

func _handle_interact_entity_command(peer_id: int, command: Dictionary) -> void:
	_interaction_command_count_by_peer[peer_id] = int(_interaction_command_count_by_peer.get(peer_id, 0)) + 1
	var citizen_id := str(_player_citizen_id_by_peer.get(peer_id, ""))
	if citizen_id.is_empty():
		citizen_id = _assign_player_citizen(peer_id)
	var player := _find_citizen_by_id(citizen_id)
	var target_id := str(command.get("target_id", ""))
	if _is_interaction_command_on_cooldown(peer_id):
		var cooldown_rejection := _build_rejected_interaction(
			player,
			target_id,
			"interaction_cooldown",
			_find_entity_by_id(target_id)
		)
		cooldown_rejection["cooldown_remaining_sec"] = float(_interaction_command_cooldown_by_peer.get(peer_id, 0.0))
		_record_rejected_interaction(peer_id, cooldown_rejection, not _has_active_interaction_context(peer_id))
		return
	_interaction_command_cooldown_by_peer[peer_id] = INTERACTION_COMMAND_COOLDOWN_SEC
	var target := _find_entity_by_id(target_id)
	var interaction := _start_entity_interaction(peer_id, player, target_id, target)
	var accepted := bool(interaction.get("accepted", false))
	if accepted:
		_accepted_interaction_command_count_by_peer[peer_id] = int(_accepted_interaction_command_count_by_peer.get(peer_id, 0)) + 1
	else:
		_rejected_interaction_command_count_by_peer[peer_id] = int(_rejected_interaction_command_count_by_peer.get(peer_id, 0)) + 1
	_record_interaction_status(peer_id, _interaction_status_state_from_interaction(interaction), interaction)
	_last_interaction_by_peer[str(peer_id)] = interaction

func _start_entity_interaction(peer_id: int, player: Citizen, target_id: String, target: Node3D) -> Dictionary:
	var player_id := NetworkEntityRegistryScript.get_entity_id(player)
	var target_type := _entity_type_name(target)
	var result := {
		"target_id": target_id,
		"accepted": false,
		"player_id": player_id,
		"target_type": target_type,
		"state": "rejected",
		"reason": "",
	}
	if player == null:
		result["reason"] = "missing_player"
		return result
	if target == null:
		result["reason"] = "missing_target"
		return result
	result["target_name"] = _entity_display_name(target)
	if target == player:
		result["reason"] = "self_target"
		return result
	var unavailable_reason := _target_unavailable_reason(target)
	if not unavailable_reason.is_empty():
		result["reason"] = unavailable_reason
		return result
	_clear_interaction_effect_for_peer(peer_id)
	if target is Citizen:
		var direct_distance := _planar_distance(player.global_position, target.global_position)
		result["target_distance"] = direct_distance
		if direct_distance <= CITIZEN_INTERACTION_DISTANCE + _arrival_tolerance_for_target(target):
			_face_player_towards(player, target.global_position)
			result["accepted"] = true
			result["state"] = "arrived"
			result["current_distance"] = direct_distance
			result["target_position"] = _vec3_to_array(target.global_position)
			result["effect"] = _apply_interaction_effect(peer_id, player, target, result, direct_distance)
			_completed_interaction_command_count_by_peer[peer_id] = int(_completed_interaction_command_count_by_peer.get(peer_id, 0)) + 1
			_active_interaction_by_peer.erase(peer_id)
			return result
	var target_position := _interaction_target_position(player, target)
	var distance_before := _planar_distance(player.global_position, target_position)
	result["start_distance"] = distance_before
	result["target_position"] = _vec3_to_array(target_position)
	if distance_before <= _arrival_tolerance_for_target(target):
		_face_player_towards(player, target.global_position)
		result["accepted"] = true
		result["state"] = "arrived"
		result["current_distance"] = distance_before
		result["effect"] = _apply_interaction_effect(peer_id, player, target, result, distance_before)
		_completed_interaction_command_count_by_peer[peer_id] = int(_completed_interaction_command_count_by_peer.get(peer_id, 0)) + 1
		_active_interaction_by_peer.erase(peer_id)
		return result
	if not player.has_method("begin_network_server_interaction_travel"):
		result["reason"] = "player_cannot_travel"
		return result
	var target_building := target as Building
	var travel_started := bool(player.begin_network_server_interaction_travel(target_position, target_building, world))
	result["accepted"] = travel_started
	result["state"] = "travelling" if travel_started else "travel_failed"
	result["reason"] = "" if travel_started else "path_failed"
	result["current_distance"] = distance_before
	if travel_started:
		_set_citizen_interaction_label(player, "Going to %s" % _entity_display_name(target))
		_active_interaction_by_peer[peer_id] = {
			"player_id": player_id,
			"target_id": target_id,
			"target_type": target_type,
			"target_name": _entity_display_name(target),
			"target_position": target_position,
			"start_distance": distance_before,
		}
		_face_player_towards(player, target.global_position)
	return result

func _build_rejected_interaction(
	player: Citizen,
	target_id: String,
	reason: String,
	target: Node3D = null
) -> Dictionary:
	return {
		"target_id": target_id,
		"accepted": false,
		"player_id": NetworkEntityRegistryScript.get_entity_id(player),
		"target_type": _entity_type_name(target),
		"target_name": _entity_display_name(target) if target != null else "",
		"state": "rejected",
		"reason": reason,
	}

func _record_rejected_interaction(peer_id: int, interaction: Dictionary, publish_status: bool = true) -> void:
	_rejected_interaction_command_count_by_peer[peer_id] = int(_rejected_interaction_command_count_by_peer.get(peer_id, 0)) + 1
	_last_interaction_by_peer[str(peer_id)] = interaction
	if publish_status:
		_record_interaction_status(peer_id, "rejected", interaction)

func _update_active_interactions() -> void:
	if _active_interaction_by_peer.is_empty():
		return
	for peer_id in _active_interaction_by_peer.keys():
		var interaction := _active_interaction_by_peer.get(peer_id, {}) as Dictionary
		var player_id := str(interaction.get("player_id", ""))
		var target_id := str(interaction.get("target_id", ""))
		var player := _find_citizen_by_id(player_id)
		var target := _find_entity_by_id(target_id)
		if player == null or target == null:
			_finish_active_interaction(int(peer_id), interaction, "cancelled", "missing_entity", -1.0)
			continue
		var target_position: Vector3 = interaction.get("target_position", target.global_position)
		var current_distance := _planar_distance(player.global_position, target_position)
		var arrived := current_distance <= _arrival_tolerance_for_target(target)
		if not arrived and player.has_method("has_reached_travel_target"):
			arrived = player.has_reached_travel_target()
		if arrived:
			_face_player_towards(player, target.global_position)
			if player.has_method("finish_network_server_interaction_travel"):
				player.finish_network_server_interaction_travel()
			_apply_interaction_effect(int(peer_id), player, target, interaction, current_distance)
			_finish_active_interaction(int(peer_id), interaction, "arrived", "", current_distance)
			continue
		if player.has_method("is_network_server_interaction_travelling") \
				and not bool(player.is_network_server_interaction_travelling()):
			_finish_active_interaction(int(peer_id), interaction, "cancelled", "travel_interrupted", current_distance)
			continue
		_update_last_interaction_debug(int(peer_id), interaction, "travelling", "", current_distance)

func _finish_active_interaction(
	peer_id: int,
	interaction: Dictionary,
	state: String,
	reason: String,
	current_distance: float
) -> void:
	_active_interaction_by_peer.erase(peer_id)
	if state == "arrived":
		_completed_interaction_command_count_by_peer[peer_id] = int(_completed_interaction_command_count_by_peer.get(peer_id, 0)) + 1
	_update_last_interaction_debug(peer_id, interaction, state, reason, current_distance)
	var status_payload := _last_interaction_by_peer.get(str(peer_id), interaction) as Dictionary
	if state == "arrived":
		var effect_payload := _last_interaction_effect_by_peer.get(str(peer_id), {}) as Dictionary
		if not effect_payload.is_empty():
			status_payload["effect"] = effect_payload.duplicate(true)
	_record_interaction_status(peer_id, _interaction_status_state_from_interaction(status_payload), status_payload)

func _update_last_interaction_debug(
	peer_id: int,
	interaction: Dictionary,
	state: String,
	reason: String,
	current_distance: float
) -> void:
	_last_interaction_by_peer[str(peer_id)] = {
		"target_id": str(interaction.get("target_id", "")),
		"accepted": state != "cancelled",
		"player_id": str(interaction.get("player_id", "")),
		"target_type": str(interaction.get("target_type", "")),
		"target_name": str(interaction.get("target_name", "")),
		"state": state,
		"reason": reason,
		"start_distance": float(interaction.get("start_distance", 0.0)),
		"current_distance": current_distance,
		"target_position": _vec3_to_array(interaction.get("target_position", Vector3.ZERO)),
	}

func _apply_interaction_effect(
	peer_id: int,
	player: Citizen,
	target: Node3D,
	interaction: Dictionary,
	current_distance: float
) -> Dictionary:
	var effect := {
		"player_id": NetworkEntityRegistryScript.get_entity_id(player),
		"target_id": NetworkEntityRegistryScript.get_entity_id(target),
		"target_type": _entity_type_name(target),
		"target_name": _entity_display_name(target),
		"state": "not_applied",
		"reason": "",
		"current_distance": current_distance,
	}
	if player == null or target == null:
		effect["reason"] = "missing_entity"
		_record_interaction_effect(peer_id, effect, false)
		return effect

	if target is Building:
		var building := target as Building
		var blocked_reason := _building_interaction_block_reason(building)
		if not blocked_reason.is_empty():
			effect["reason"] = blocked_reason
			_record_interaction_effect(peer_id, effect, false)
			return effect
		if player.has_method("enter_building"):
			player.enter_building(building, world, false)
		var player_label := "Visiting %s" % _entity_display_name(building)
		_set_citizen_interaction_label(player, player_label)
		effect["state"] = "entered_building"
		effect["building_visitor_count"] = building.visitors.size()
		_track_interaction_effect(peer_id, effect, player_label, "")
		_record_interaction_effect(peer_id, effect, true)
		return effect

	if target is Citizen:
		var target_citizen := target as Citizen
		_face_player_towards(player, target_citizen.global_position)
		_face_player_towards(target_citizen, player.global_position)
		var player_label := "Talking to %s" % _entity_display_name(target_citizen)
		var target_label := "Talking to Player"
		_set_citizen_interaction_label(player, player_label)
		_set_citizen_interaction_label(target_citizen, target_label)
		if target_citizen.has_method("set_runtime_conversation_state"):
			target_citizen.set_runtime_conversation_state("interactive", "Player", "network_interaction")
		_upsert_network_interaction_commitment(target_citizen)
		effect["state"] = "citizen_interaction"
		_track_interaction_effect(peer_id, effect, player_label, target_label)
		_record_interaction_effect(peer_id, effect, true)
		return effect

	effect["reason"] = "unsupported_target"
	_record_interaction_effect(peer_id, effect, false)
	return effect

func _track_interaction_effect(
	peer_id: int,
	effect: Dictionary,
	player_label: String,
	target_label: String
) -> void:
	var tracked := effect.duplicate(true)
	tracked["remaining_sec"] = INTERACTION_EFFECT_DURATION_SEC
	tracked["player_label"] = player_label
	tracked["target_label"] = target_label
	_active_interaction_effect_by_peer[peer_id] = tracked

func _record_interaction_effect(peer_id: int, effect: Dictionary, applied: bool) -> void:
	_last_interaction_effect_by_peer[str(peer_id)] = effect.duplicate(true)
	if applied:
		_applied_interaction_effect_count_by_peer[peer_id] = int(_applied_interaction_effect_count_by_peer.get(peer_id, 0)) + 1

func _update_interaction_effects(delta: float) -> void:
	if _active_interaction_effect_by_peer.is_empty():
		return
	for peer_id in _active_interaction_effect_by_peer.keys():
		var effect := _active_interaction_effect_by_peer.get(peer_id, {}) as Dictionary
		var player := _find_citizen_by_id(str(effect.get("player_id", "")))
		var target := _find_entity_by_id(str(effect.get("target_id", "")))
		if player == null or target == null:
			_clear_interaction_effect_for_peer(int(peer_id))
			continue
		var remaining := float(effect.get("remaining_sec", 0.0)) - delta
		effect["remaining_sec"] = remaining
		if remaining <= 0.0:
			_clear_interaction_effect_for_peer(int(peer_id))
			continue
		_set_citizen_interaction_label(player, str(effect.get("player_label", "")))
		if target is Citizen:
			var target_citizen := target as Citizen
			_set_citizen_interaction_label(target_citizen, str(effect.get("target_label", "")))
			if target_citizen.has_method("set_runtime_conversation_state"):
				target_citizen.set_runtime_conversation_state("interactive", "Player", "network_interaction")
		_active_interaction_effect_by_peer[peer_id] = effect

func _clear_interaction_effect_for_peer(peer_id: int) -> void:
	var effect := _active_interaction_effect_by_peer.get(peer_id, {}) as Dictionary
	if effect.is_empty():
		return
	var player := _find_citizen_by_id(str(effect.get("player_id", "")))
	if player != null and player.has_method("clear_server_interaction_label"):
		player.clear_server_interaction_label(str(effect.get("player_label", "")))
	var target := _find_entity_by_id(str(effect.get("target_id", "")))
	if target is Citizen:
		var target_citizen := target as Citizen
		if target_citizen.has_method("clear_server_interaction_label"):
			target_citizen.clear_server_interaction_label(str(effect.get("target_label", "")))
		if target_citizen.has_method("clear_runtime_conversation_state"):
			target_citizen.clear_runtime_conversation_state()
		if target_citizen.has_method("remove_lod_commitment"):
			target_citizen.remove_lod_commitment("network_interaction")
	_active_interaction_effect_by_peer.erase(peer_id)
	_record_interaction_status(peer_id, "ready", {
		"player_id": str(effect.get("player_id", "")),
		"target_id": str(effect.get("target_id", "")),
		"target_type": str(effect.get("target_type", "")),
		"target_name": str(effect.get("target_name", "")),
		"detail": "Interaction ended.",
	})

func _building_interaction_block_reason(building: Building) -> String:
	if building == null:
		return "missing_building"
	var hour := world.time.get_hour() if world != null and world.time != null else -1
	if building.has_method("is_open") and not bool(building.is_open(hour)):
		return "building_closed"
	return ""

func _target_unavailable_reason(target: Node3D) -> String:
	if target is Citizen:
		var citizen := target as Citizen
		if not citizen.visible:
			return "target_not_visible"
		if citizen.has_method("is_inside_building") and citizen.is_inside_building():
			return "target_inside_building"
	if target is Building:
		return _building_interaction_block_reason(target as Building)
	return ""

func _is_interaction_command_on_cooldown(peer_id: int) -> bool:
	return float(_interaction_command_cooldown_by_peer.get(peer_id, 0.0)) > 0.0

func _has_active_interaction_context(peer_id: int) -> bool:
	return _active_interaction_by_peer.has(peer_id) or _active_interaction_effect_by_peer.has(peer_id)

func _update_interaction_command_cooldowns(delta: float) -> void:
	if delta <= 0.0 or _interaction_command_cooldown_by_peer.is_empty():
		return
	for peer_id in _interaction_command_cooldown_by_peer.keys():
		var remaining := maxf(float(_interaction_command_cooldown_by_peer.get(peer_id, 0.0)) - delta, 0.0)
		if remaining <= 0.0:
			_interaction_command_cooldown_by_peer.erase(peer_id)
		else:
			_interaction_command_cooldown_by_peer[peer_id] = remaining

func _upsert_network_interaction_commitment(citizen: Citizen) -> void:
	if citizen == null or world == null or world.time == null or not citizen.has_method("upsert_lod_commitment"):
		return
	var total_minutes := int(world.time.minutes_total) + 20
	var until_day := int(world.time.day) + int(total_minutes / (24 * 60))
	var until_minute := posmod(total_minutes, 24 * 60)
	citizen.upsert_lod_commitment("network_interaction", until_day, until_minute, 50.0, {
		"source": "multiplayer_interaction",
	})

func _set_citizen_interaction_label(citizen: Citizen, label: String) -> void:
	if citizen != null and citizen.has_method("set_server_interaction_label"):
		citizen.set_server_interaction_label(label)

func _interaction_target_position(player: Citizen, target: Node3D) -> Vector3:
	if target is Building:
		var building := target as Building
		var nav_points := player.get_navigation_points_for_building(building, world) if player != null and player.has_method("get_navigation_points_for_building") else {}
		var access_pos: Variant = nav_points.get("access", building.get_entrance_pos())
		return access_pos if access_pos is Vector3 else building.get_entrance_pos()
	if target is Citizen:
		var direction := player.global_position - target.global_position
		direction.y = 0.0
		if direction.length_squared() <= 0.0001:
			direction = -target.global_transform.basis.z
			direction.y = 0.0
		if direction.length_squared() <= 0.0001:
			direction = Vector3.FORWARD
		var position := target.global_position + direction.normalized() * CITIZEN_INTERACTION_DISTANCE
		if world != null and world.has_method("get_pedestrian_access_point"):
			position = world.get_pedestrian_access_point(position)
		return position
	return target.global_position

func _arrival_tolerance_for_target(target: Node3D) -> float:
	if target is Building:
		var building := target as Building
		if building.has_method("get_navigation_approach_distance"):
			return maxf(float(building.get_navigation_approach_distance()), INTERACTION_ARRIVAL_TOLERANCE)
	return INTERACTION_ARRIVAL_TOLERANCE

func _reserved_player_citizen_ids() -> Dictionary:
	var reserved: Dictionary = {}
	for value in _player_citizen_id_by_peer.values():
		var entity_id := str(value)
		if not entity_id.is_empty():
			reserved[entity_id] = true
	return reserved

func _player_assignment_candidates(peer_id: int) -> Array[Citizen]:
	var candidates: Array[Citizen] = []
	if world == null:
		return candidates
	for citizen in world.citizens:
		if citizen == null or not is_instance_valid(citizen):
			continue
		if not citizen.autonomous_simulation_enabled:
			continue
		candidates.append(citizen)
	if peer_id == LOCAL_HOST_PEER_ID:
		candidates.reverse()
	return candidates

func _release_all_player_citizens() -> void:
	for peer_id in _player_citizen_id_by_peer.keys():
		_release_player_citizen(int(peer_id))

func _apply_local_host_player_input() -> void:
	var entity_id := get_local_player_citizen_id()
	if entity_id.is_empty():
		entity_id = ensure_local_host_player()
	if entity_id.is_empty():
		return
	var citizen := _find_citizen_by_id(entity_id)
	if citizen == null or not citizen.has_method("apply_network_server_control_input"):
		return
	var direction := _get_local_host_input_direction()
	if direction.length_squared() > 0.0001:
		_clear_interaction_effect_for_peer(LOCAL_HOST_PEER_ID)
	citizen.apply_network_server_control_input(direction, world)
	_sync_local_host_player_camera(entity_id)

func _sync_local_host_player_camera(entity_id: String) -> void:
	if entity_id.is_empty() or _local_host_camera_follow_target_id == entity_id:
		return
	var citizen := _find_citizen_by_id(entity_id)
	if citizen == null or root_node == null:
		return
	var viewport := root_node.get_viewport()
	var camera := viewport.get_camera_3d() if viewport != null else null
	if camera != null and camera.has_method("set_follow_target"):
		camera.call("set_follow_target", citizen)
		_local_host_camera_follow_target_id = entity_id

func _get_local_host_input_direction() -> Vector3:
	if _is_text_input_focused():
		return Vector3.ZERO
	var side := 0.0
	var forward_amount := 0.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		side -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		side += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		forward_amount += 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		forward_amount -= 1.0
	if absf(side) <= 0.001 and absf(forward_amount) <= 0.001:
		return Vector3.ZERO

	var basis_forward := Vector3.FORWARD
	var basis_right := Vector3.RIGHT
	if root_node != null:
		var viewport := root_node.get_viewport()
		var camera := viewport.get_camera_3d() if viewport != null else null
		if camera != null:
			basis_forward = -camera.global_transform.basis.z
			basis_forward.y = 0.0
			if basis_forward.length_squared() > 0.0001:
				basis_forward = basis_forward.normalized()
			basis_right = camera.global_transform.basis.x
			basis_right.y = 0.0
			if basis_right.length_squared() > 0.0001:
				basis_right = basis_right.normalized()
	var direction := basis_right * side + basis_forward * forward_amount
	direction.y = 0.0
	return direction.normalized() if direction.length_squared() > 0.0001 else Vector3.ZERO

func _is_text_input_focused() -> bool:
	if root_node == null:
		return false
	var viewport := root_node.get_viewport()
	var focus_owner := viewport.gui_get_focus_owner() if viewport != null else null
	return focus_owner is LineEdit or focus_owner is TextEdit

func _face_player_towards(player: Citizen, target_position: Vector3) -> void:
	if player == null:
		return
	var direction := target_position - player.global_position
	direction.y = 0.0
	if direction.length_squared() <= 0.0001:
		return
	player.look_at(player.global_position + direction.normalized(), Vector3.UP)

func _find_entity_by_id(entity_id: String) -> Node3D:
	if entity_id.is_empty():
		return null
	var citizen := _find_citizen_by_id(entity_id)
	if citizen != null:
		return citizen
	var building := _find_building_by_id(entity_id)
	return building

func _find_building_by_id(entity_id: String) -> Building:
	if entity_id.is_empty() or world == null:
		return null
	for building in world.buildings:
		if building == null or not is_instance_valid(building):
			continue
		if NetworkEntityRegistryScript.get_entity_id(building) == entity_id:
			return building
	return null

func _entity_type_name(entity: Node) -> String:
	if entity is Citizen:
		return "citizen"
	if entity is Building:
		return "building"
	return ""

func _entity_display_name(entity: Node) -> String:
	if entity == null:
		return "Target"
	if entity is Citizen:
		return (entity as Citizen).citizen_name
	if entity is Building:
		var building := entity as Building
		if building.has_method("get_display_name"):
			return building.get_display_name()
		return building.building_name
	return entity.name

func _record_interaction_status(peer_id: int, state: String, payload: Dictionary) -> void:
	var target_id := str(payload.get("target_id", ""))
	var target_type := str(payload.get("target_type", ""))
	var target_name := str(payload.get("target_name", ""))
	var reason := str(payload.get("reason", ""))
	var raw_effect: Variant = payload.get("effect", {})
	var effect: Dictionary = {}
	if raw_effect is Dictionary:
		effect = raw_effect as Dictionary
	if target_name.is_empty() and not effect.is_empty():
		target_name = str(effect.get("target_name", ""))
	if reason.is_empty() and not effect.is_empty():
		reason = str(effect.get("reason", ""))
	if target_name.is_empty() and not target_id.is_empty():
		var target := _find_entity_by_id(target_id)
		if target != null:
			target_name = _entity_display_name(target)
	if target_type.is_empty() and not target_id.is_empty():
		var target_for_type := _find_entity_by_id(target_id)
		target_type = _entity_type_name(target_for_type)

	var status := {
		"state": state,
		"target_id": target_id,
		"target_type": target_type,
		"target_name": target_name,
		"player_id": str(payload.get("player_id", "")),
		"reason": reason,
		"detail": str(payload.get("detail", _interaction_status_detail(state, target_name, reason))),
	}
	_last_interaction_status_by_peer[str(peer_id)] = status
	if peer_id == LOCAL_HOST_PEER_ID or session_node == null:
		return
	session_node.rpc_id(peer_id, "_client_apply_interaction_status", status)

func _interaction_status_state_from_interaction(interaction: Dictionary) -> String:
	var state := str(interaction.get("state", "rejected"))
	var raw_effect: Variant = interaction.get("effect", {})
	var effect: Dictionary = {}
	if raw_effect is Dictionary:
		effect = raw_effect as Dictionary
	if state == "arrived" and not effect.is_empty():
		var effect_state := str(effect.get("state", ""))
		if not effect_state.is_empty() and effect_state != "not_applied":
			return "effect"
		if not str(effect.get("reason", "")).is_empty():
			return "rejected"
	return state

func _interaction_status_detail(state: String, target_name: String, reason: String) -> String:
	var target_label := target_name if not target_name.is_empty() else "target"
	match state:
		"travelling":
			return "Moving to %s." % target_label
		"arrived":
			return "Arrived at %s." % target_label
		"effect":
			return "Interacting with %s." % target_label
		"cancelled":
			return reason if not reason.is_empty() else "Interaction cancelled."
		"rejected", "travel_failed":
			return reason if not reason.is_empty() else "Interaction rejected."
		"ready":
			return "Ready."
	return str(state).capitalize()

func _active_interaction_debug_dictionary() -> Dictionary:
	var result: Dictionary = {}
	for peer_id in _active_interaction_by_peer.keys():
		var interaction := _active_interaction_by_peer.get(peer_id, {}) as Dictionary
		result[str(peer_id)] = {
			"player_id": str(interaction.get("player_id", "")),
			"target_id": str(interaction.get("target_id", "")),
			"target_type": str(interaction.get("target_type", "")),
			"target_name": str(interaction.get("target_name", "")),
			"state": "travelling",
			"start_distance": float(interaction.get("start_distance", 0.0)),
			"target_position": _vec3_to_array(interaction.get("target_position", Vector3.ZERO)),
		}
	return result

func _active_interaction_effect_debug_dictionary() -> Dictionary:
	var result: Dictionary = {}
	for peer_id in _active_interaction_effect_by_peer.keys():
		var effect := _active_interaction_effect_by_peer.get(peer_id, {}) as Dictionary
		result[str(peer_id)] = {
			"player_id": str(effect.get("player_id", "")),
			"target_id": str(effect.get("target_id", "")),
			"target_type": str(effect.get("target_type", "")),
			"target_name": str(effect.get("target_name", "")),
			"state": str(effect.get("state", "")),
			"remaining_sec": float(effect.get("remaining_sec", 0.0)),
		}
	return result

func _interaction_command_cooldown_debug_dictionary() -> Dictionary:
	var result: Dictionary = {}
	for peer_id in _interaction_command_cooldown_by_peer.keys():
		result[str(peer_id)] = float(_interaction_command_cooldown_by_peer.get(peer_id, 0.0))
	return result

func _sum_int_values(values: Dictionary) -> int:
	var total := 0
	for value in values.values():
		total += int(value)
	return total

func _string_keyed_int_dictionary(values: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in values.keys():
		result[str(key)] = int(values.get(key, 0))
	return result

func _planar_distance(a: Vector3, b: Vector3) -> float:
	a.y = 0.0
	b.y = 0.0
	return a.distance_to(b)

func _vec3_to_array(value: Variant) -> Array:
	if value is Vector3:
		var vec := value as Vector3
		return [vec.x, vec.y, vec.z]
	return []

func _find_citizen_by_id(entity_id: String) -> Citizen:
	if entity_id.is_empty() or world == null:
		return null
	for citizen in world.citizens:
		if citizen == null or not is_instance_valid(citizen):
			continue
		if NetworkEntityRegistryScript.get_entity_id(citizen) == entity_id:
			return citizen
	return null
