extends SceneTree

const REPORT_INTERVAL_SEC := 0.10
const MAX_RUNTIME_SEC := 30.0
const CLIENT_DRIVE_COMMAND_COUNT := 80
const HOST_DRIVE_FRAME_COUNT := 80
const HOST_INTERACTION_RELEASE_FRAME_COUNT := 8

const NetworkEntityRegistryScript = preload("res://Simulation/Multiplayer/shared/NetworkEntityRegistry.gd")
const WorldSnapshotSerializerScript = preload("res://Simulation/Multiplayer/shared/WorldSnapshotSerializer.gd")

var _probe_role: String = ""
var _report_path: String = ""
var _stop_path: String = ""
var _main: Node = null
var _registry = NetworkEntityRegistryScript.new()
var _authority_gate_checked: bool = false
var _authority_gate_ok: bool = false
var _client_drive_commands_sent: int = 0
var _client_interaction_command_sent: bool = false
var _host_interaction_request_sent: bool = false
var _host_drive_frames_sent: int = 0
var _host_interaction_release_frames: int = 0
var _host_drive_key_pressed: bool = false

func _init() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	_probe_role = str(args.get("probe_role", ""))
	_report_path = str(args.get("probe_report", ""))
	_stop_path = str(args.get("probe_stop", ""))
	if _probe_role.is_empty() or _report_path.is_empty():
		quit(2)
		return

	var main_scene := load("res://Main.tscn") as PackedScene
	if main_scene == null:
		_write_report({
			"phase": "error",
			"role": _probe_role,
			"error": "Main.tscn could not be loaded",
		})
		quit(1)
		return

	_main = main_scene.instantiate()
	root.add_child(_main)

	var deadline := Time.get_ticks_msec() + int(MAX_RUNTIME_SEC * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if not _stop_path.is_empty() and FileAccess.file_exists(_stop_path):
			break
		_maybe_check_client_tick_gate()
		_maybe_drive_host_player()
		_maybe_send_host_interaction_request()
		_maybe_send_client_drive_input()
		_maybe_send_client_interaction_request()
		_write_report(_build_report("running"))
		await create_timer(REPORT_INTERVAL_SEC).timeout

	_write_report(_build_report("stopped"))
	_set_host_drive_key_pressed(false)
	if _main != null and is_instance_valid(_main):
		_main.queue_free()
	await process_frame
	quit(0)

func _maybe_check_client_tick_gate() -> void:
	if _authority_gate_checked or _probe_role != "client":
		return
	var session := _get_session()
	var world := _get_world()
	if session == null or world == null:
		return
	var status: Dictionary = session.get_status() if session.has_method("get_status") else {}
	if str(status.get("status", "")) != "connected":
		return
	var minute_before := world.time.minutes_total if world.time != null else -1
	world.call("_on_tick")
	var minute_after := world.time.minutes_total if world.time != null else -2
	_authority_gate_ok = minute_after == minute_before
	_authority_gate_checked = true

func _build_report(phase: String) -> Dictionary:
	var session := _get_session()
	var world := _get_world()
	var status: Dictionary = session.get_status() if session != null and session.has_method("get_status") else {}
	var snapshot := WorldSnapshotSerializerScript.build_snapshot(world, _main, 1, _registry) if world != null and _main != null else {}
	var time_data := snapshot.get("time", {}) as Dictionary
	var world_data := snapshot.get("world", {}) as Dictionary
	var citizen_entries := snapshot.get("citizens", []) as Array
	var building_entries := snapshot.get("buildings", []) as Array
	var local_player_id := str(status.get("local_player_citizen_id", ""))
	var host_debug := status.get("host_debug", {}) as Dictionary
	var client_debug := status.get("client_debug", {}) as Dictionary
	var active_interactions := host_debug.get("active_interaction_by_peer", {}) as Dictionary
	var active_effects := host_debug.get("active_interaction_effect_by_peer", {}) as Dictionary
	return {
		"phase": phase,
		"probe_role": _probe_role,
		"session_role": str(status.get("role", "")),
		"session_status": str(status.get("status", "")),
		"session_detail": str(status.get("detail", "")),
		"port": int(status.get("port", 0)),
		"day": int(time_data.get("day", 0)),
		"minutes_total": int(time_data.get("minutes_total", -1)),
		"hour": int(time_data.get("hour", -1)),
		"minute": int(time_data.get("minute", -1)),
		"city_balance": int(world_data.get("city_balance", 0)),
		"simulation_authority_enabled": bool(world.simulation_authority_enabled) if world != null else false,
		"authority_gate_checked": _authority_gate_checked,
		"authority_gate_ok": _authority_gate_ok,
		"local_player_citizen_id": local_player_id,
		"local_player_visible": _entry_bool(citizen_entries, local_player_id, "visible"),
		"local_player_manual_control": _entry_bool(citizen_entries, local_player_id, "manual_control"),
		"local_player_position": _entry_value(citizen_entries, local_player_id, "position", []),
		"manual_control_citizen_count": _count_manual_control_citizens(citizen_entries),
		"manual_control_citizen_ids": _ids_from_entries_with_bool(citizen_entries, "manual_control"),
		"client_drive_commands_sent": _client_drive_commands_sent,
		"client_interaction_command_sent": _client_interaction_command_sent,
		"host_interaction_request_sent": _host_interaction_request_sent,
		"host_drive_frames_sent": _host_drive_frames_sent,
		"host_player_input_command_count": int(host_debug.get("player_input_command_count", 0)),
		"host_player_input_command_count_by_peer": host_debug.get("player_input_command_count_by_peer", {}),
		"host_assigned_player_citizen_ids_by_peer": host_debug.get("assigned_player_citizen_ids_by_peer", {}),
		"host_last_player_input_direction_by_peer": host_debug.get("last_player_input_direction_by_peer", {}),
		"host_interaction_command_count": int(host_debug.get("interaction_command_count", 0)),
		"host_accepted_interaction_command_count": int(host_debug.get("accepted_interaction_command_count", 0)),
		"host_rejected_interaction_command_count": int(host_debug.get("rejected_interaction_command_count", 0)),
		"host_completed_interaction_command_count": int(host_debug.get("completed_interaction_command_count", 0)),
		"host_applied_interaction_effect_count": int(host_debug.get("applied_interaction_effect_count", 0)),
		"host_interaction_command_count_by_peer": host_debug.get("interaction_command_count_by_peer", {}),
		"host_accepted_interaction_command_count_by_peer": host_debug.get("accepted_interaction_command_count_by_peer", {}),
		"host_rejected_interaction_command_count_by_peer": host_debug.get("rejected_interaction_command_count_by_peer", {}),
		"host_completed_interaction_command_count_by_peer": host_debug.get("completed_interaction_command_count_by_peer", {}),
		"host_applied_interaction_effect_count_by_peer": host_debug.get("applied_interaction_effect_count_by_peer", {}),
		"host_last_interaction_by_peer": host_debug.get("last_interaction_by_peer", {}),
		"host_last_interaction_effect_by_peer": host_debug.get("last_interaction_effect_by_peer", {}),
		"host_interaction_status_by_peer": host_debug.get("interaction_status_by_peer", {}),
		"host_active_interaction_by_peer": active_interactions,
		"host_active_interaction_count": active_interactions.size(),
		"host_active_interaction_effect_by_peer": active_effects,
		"host_active_interaction_effect_count": active_effects.size(),
		"client_received_full_snapshot": bool(client_debug.get("received_full_snapshot", false)),
		"client_building_lookup_count": int(client_debug.get("building_lookup_count", 0)),
		"client_last_full_sequence": int(client_debug.get("last_full_sequence", 0)),
		"client_last_actor_state_sequence": int(client_debug.get("last_actor_state_sequence", 0)),
		"client_last_world_state_sequence": int(client_debug.get("last_world_state_sequence", 0)),
		"client_replica_interpolation_target_count": int(client_debug.get("interpolation_target_count", 0)),
		"client_replica_interpolation_max_error": float(client_debug.get("interpolation_max_error", 0.0)),
		"client_prediction_frame_count": int(client_debug.get("prediction_frame_count", 0)),
		"client_prediction_distance": float(client_debug.get("prediction_distance", 0.0)),
		"client_prediction_error": float(client_debug.get("prediction_error", 0.0)),
		"client_interaction_status": client_debug.get("interaction_status", {}),
		"citizen_count": citizen_entries.size(),
		"visible_citizen_count": _count_visible_citizens(citizen_entries),
		"inside_citizen_count": _count_inside_citizens(citizen_entries),
		"total_fall_respawn_count": _sum_int_entry_values(citizen_entries, "fall_respawn_count"),
		"fall_respawn_counts_by_id": _int_values_by_id(citizen_entries, "fall_respawn_count"),
		"citizen_ids": _ids_from_entries(citizen_entries),
		"visible_citizen_ids": _ids_from_entries_with_bool(citizen_entries, "visible"),
		"citizen_positions_by_id": _positions_by_id(citizen_entries),
		"building_count": building_entries.size(),
		"building_ids": _ids_from_entries(building_entries),
	}

func _maybe_drive_host_player() -> void:
	if _probe_role != "host":
		_set_host_drive_key_pressed(false)
		return
	if _host_drive_frames_sent >= HOST_DRIVE_FRAME_COUNT:
		_set_host_drive_key_pressed(false)
		_host_interaction_release_frames += 1
		return
	var session := _get_session()
	if session == null or not session.has_method("get_status"):
		return
	var status: Dictionary = session.get_status()
	if str(status.get("status", "")) != "hosting":
		return
	if str(status.get("local_player_citizen_id", "")).is_empty():
		return
	if session.multiplayer.get_peers().is_empty():
		return
	_set_host_drive_key_pressed(true)
	_host_drive_frames_sent += 1

func _set_host_drive_key_pressed(pressed: bool) -> void:
	if _host_drive_key_pressed == pressed:
		return
	_host_drive_key_pressed = pressed
	var event := InputEventKey.new()
	event.keycode = KEY_W
	event.physical_keycode = KEY_W
	event.pressed = pressed
	Input.parse_input_event(event)

func _maybe_send_client_drive_input() -> void:
	if _probe_role != "client":
		return
	if _client_drive_commands_sent >= CLIENT_DRIVE_COMMAND_COUNT:
		return
	var session := _get_session()
	if session == null or not session.has_method("get_status") or not session.has_method("send_command"):
		return
	var status: Dictionary = session.get_status()
	if str(status.get("status", "")) != "connected":
		return
	if str(status.get("local_player_citizen_id", "")).is_empty():
		return
	_client_drive_commands_sent += 1
	var local_player_id := str(status.get("local_player_citizen_id", ""))
	session.send_command({
		"type": "player_input",
		"sequence": _client_drive_commands_sent,
		"direction": _vec3_to_array(_get_local_player_drive_direction(local_player_id, _client_drive_commands_sent)),
	})

func _maybe_send_client_interaction_request() -> void:
	if _probe_role != "client" or _client_interaction_command_sent:
		return
	if _client_drive_commands_sent < CLIENT_DRIVE_COMMAND_COUNT:
		return
	var session := _get_session()
	if session == null or not session.has_method("get_status") or not session.has_method("send_command"):
		return
	var status: Dictionary = session.get_status()
	if str(status.get("status", "")) != "connected":
		return
	var target := _find_nearest_interaction_target(str(status.get("local_player_citizen_id", "")))
	if target == null:
		return
	var target_id := NetworkEntityRegistryScript.get_entity_id(target)
	if target_id.is_empty():
		return
	session.send_command({
		"type": "interact_entity",
		"target_id": target_id,
	})
	session.send_command({
		"type": "interact_entity",
		"target_id": target_id,
	})
	_client_interaction_command_sent = true

func _maybe_send_host_interaction_request() -> void:
	if _probe_role != "host" or _host_interaction_request_sent:
		return
	if _host_drive_frames_sent < HOST_DRIVE_FRAME_COUNT:
		return
	if _host_interaction_release_frames < HOST_INTERACTION_RELEASE_FRAME_COUNT:
		return
	var session := _get_session()
	if session == null or not session.has_method("get_status") or not session.has_method("request_entity_interaction"):
		return
	var status: Dictionary = session.get_status()
	if str(status.get("status", "")) != "hosting":
		return
	if str(status.get("local_player_citizen_id", "")).is_empty():
		return
	var target := _find_nearest_interaction_target(str(status.get("local_player_citizen_id", "")))
	if target == null:
		return
	session.request_entity_interaction(target)
	_host_interaction_request_sent = true

func _entry_bool(entries: Array, entity_id: String, key: String) -> bool:
	return bool(_entry_value(entries, entity_id, key, false))

func _entry_value(entries: Array, entity_id: String, key: String, fallback: Variant) -> Variant:
	if entity_id.is_empty():
		return fallback
	for entry in entries:
		if entry is not Dictionary:
			continue
		var data := entry as Dictionary
		if str(data.get("id", "")) == entity_id:
			return data.get(key, fallback)
	return fallback

func _get_local_player_drive_direction(entity_id: String, command_index: int) -> Vector3:
	var world := _get_world()
	if world == null or entity_id.is_empty():
		return Vector3.FORWARD
	for citizen in world.citizens:
		if citizen == null or not is_instance_valid(citizen):
			continue
		if NetworkEntityRegistryScript.get_entity_id(citizen) != entity_id:
			continue
		var forward := -citizen.global_transform.basis.z
		forward.y = 0.0
		if forward.length_squared() <= 0.0001:
			forward = Vector3.FORWARD
		else:
			forward = forward.normalized()
		var right := citizen.global_transform.basis.x
		right.y = 0.0
		if right.length_squared() <= 0.0001:
			right = Vector3.RIGHT
		else:
			right = right.normalized()
		match int((command_index - 1) / 10) % 4:
			0:
				return forward
			1:
				return right
			2:
				return -forward
			_:
				return -right
	return Vector3.FORWARD

func _find_nearest_interaction_target(local_player_id: String) -> Node:
	var world := _get_world()
	if world == null or local_player_id.is_empty():
		return null
	var player := _find_citizen_by_id(local_player_id)
	if player == null:
		return null
	var best_citizen := _find_nearest_visible_citizen(player, local_player_id)
	if best_citizen != null:
		return best_citizen
	return _find_nearest_building(player.global_position)

func _find_nearest_visible_citizen(player: Citizen, local_player_id: String) -> Citizen:
	var world := _get_world()
	if world == null or player == null:
		return null
	var best: Citizen = null
	var best_distance := INF
	for citizen in world.citizens:
		if citizen == null or not is_instance_valid(citizen):
			continue
		if NetworkEntityRegistryScript.get_entity_id(citizen) == local_player_id:
			continue
		if not citizen.visible or citizen.is_inside_building():
			continue
		var distance := _planar_distance(player.global_position, citizen.global_position)
		if distance >= best_distance:
			continue
		best = citizen
		best_distance = distance
	return best

func _find_nearest_building(origin: Vector3) -> Building:
	var world := _get_world()
	if world == null:
		return null
	var best: Building = null
	var best_distance := INF
	for building in world.buildings:
		if building == null or not is_instance_valid(building):
			continue
		var distance := _planar_distance(origin, building.global_position)
		if distance >= best_distance:
			continue
		best = building
		best_distance = distance
	return best

func _find_citizen_by_id(entity_id: String) -> Citizen:
	var world := _get_world()
	if world == null or entity_id.is_empty():
		return null
	for citizen in world.citizens:
		if citizen == null or not is_instance_valid(citizen):
			continue
		if NetworkEntityRegistryScript.get_entity_id(citizen) == entity_id:
			return citizen
	return null

func _planar_distance(a: Vector3, b: Vector3) -> float:
	a.y = 0.0
	b.y = 0.0
	return a.distance_to(b)

func _vec3_to_array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func _count_visible_citizens(entries: Array) -> int:
	var total := 0
	for entry in entries:
		if entry is Dictionary and bool((entry as Dictionary).get("visible", false)):
			total += 1
	return total

func _count_inside_citizens(entries: Array) -> int:
	var total := 0
	for entry in entries:
		if entry is Dictionary and bool((entry as Dictionary).get("inside", false)):
			total += 1
	return total

func _count_manual_control_citizens(entries: Array) -> int:
	var total := 0
	for entry in entries:
		if entry is Dictionary and bool((entry as Dictionary).get("manual_control", false)):
			total += 1
	return total

func _ids_from_entries_with_bool(entries: Array, key: String) -> Array[String]:
	var ids: Array[String] = []
	for entry in entries:
		if entry is not Dictionary:
			continue
		var data := entry as Dictionary
		if not bool(data.get(key, false)):
			continue
		var entity_id := str(data.get("id", ""))
		if not entity_id.is_empty():
			ids.append(entity_id)
	ids.sort()
	return ids

func _ids_from_entries(entries: Array) -> Array[String]:
	var ids: Array[String] = []
	for entry in entries:
		if entry is not Dictionary:
			continue
		var entity_id := str((entry as Dictionary).get("id", ""))
		if not entity_id.is_empty():
			ids.append(entity_id)
	ids.sort()
	return ids

func _positions_by_id(entries: Array) -> Dictionary:
	var positions: Dictionary = {}
	for entry in entries:
		if entry is not Dictionary:
			continue
		var data := entry as Dictionary
		var entity_id := str(data.get("id", ""))
		if entity_id.is_empty():
			continue
		positions[entity_id] = data.get("position", [])
	return positions

func _int_values_by_id(entries: Array, key: String) -> Dictionary:
	var values: Dictionary = {}
	for entry in entries:
		if entry is not Dictionary:
			continue
		var data := entry as Dictionary
		var entity_id := str(data.get("id", ""))
		if entity_id.is_empty():
			continue
		values[entity_id] = int(data.get(key, 0))
	return values

func _sum_int_entry_values(entries: Array, key: String) -> int:
	var total := 0
	for entry in entries:
		if entry is Dictionary:
			total += int((entry as Dictionary).get(key, 0))
	return total

func _write_report(report: Dictionary) -> void:
	if _report_path.is_empty():
		return
	var temp_path := "%s.tmp" % _report_path
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(report))
	file.close()
	var dir := DirAccess.open(_report_path.get_base_dir())
	if dir == null:
		return
	var report_file := _report_path.get_file()
	var temp_file := temp_path.get_file()
	if FileAccess.file_exists(_report_path):
		dir.remove(report_file)
	dir.rename(temp_file, report_file)

func _get_session() -> Node:
	return _main.get_node_or_null("MultiplayerSession") if _main != null else null

func _get_world() -> World:
	return _main.get_node_or_null("World") as World if _main != null else null

func _parse_args(args: PackedStringArray) -> Dictionary:
	var parsed: Dictionary = {}
	var index := 0
	while index < args.size():
		var arg := str(args[index])
		match arg:
			"--probe-role":
				if index + 1 < args.size():
					index += 1
					parsed["probe_role"] = str(args[index])
			"--probe-report":
				if index + 1 < args.size():
					index += 1
					parsed["probe_report"] = str(args[index])
			"--probe-stop":
				if index + 1 < args.size():
					index += 1
					parsed["probe_stop"] = str(args[index])
		index += 1
	return parsed
