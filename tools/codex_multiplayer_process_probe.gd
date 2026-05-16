extends SceneTree

const REPORT_INTERVAL_SEC := 0.10
const MAX_RUNTIME_SEC := 30.0
const CLIENT_DRIVE_COMMAND_COUNT := 18

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
		_maybe_send_client_drive_input()
		_write_report(_build_report("running"))
		await create_timer(REPORT_INTERVAL_SEC).timeout

	_write_report(_build_report("stopped"))
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
		"citizen_count": citizen_entries.size(),
		"visible_citizen_count": _count_visible_citizens(citizen_entries),
		"inside_citizen_count": _count_inside_citizens(citizen_entries),
		"citizen_ids": _ids_from_entries(citizen_entries),
		"building_count": building_entries.size(),
		"building_ids": _ids_from_entries(building_entries),
	}

func _maybe_send_client_drive_input() -> void:
	if _probe_role != "client" or _client_drive_commands_sent >= CLIENT_DRIVE_COMMAND_COUNT:
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
	session.send_command({
		"type": "player_input",
		"sequence": _client_drive_commands_sent,
		"direction": _vec3_to_array(_get_local_player_forward_direction(str(status.get("local_player_citizen_id", "")))),
	})

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

func _get_local_player_forward_direction(entity_id: String) -> Vector3:
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
		return forward.normalized() if forward.length_squared() > 0.0001 else Vector3.FORWARD
	return Vector3.FORWARD

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

func _write_report(report: Dictionary) -> void:
	if _report_path.is_empty():
		return
	var file := FileAccess.open(_report_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(report))
	file.close()

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
