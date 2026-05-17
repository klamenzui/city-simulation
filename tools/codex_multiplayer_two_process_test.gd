extends SceneTree

const HOST_READY_TIMEOUT_SEC := 12.0
const CLIENT_READY_TIMEOUT_SEC := 18.0
const CLIENT_DISCONNECT_TIMEOUT_SEC := 8.0
const INTERACTION_READY_TIMEOUT_SEC := 12.0
const INTERACTION_EFFECT_TIMEOUT_SEC := 12.0
const SHUTDOWN_WAIT_SEC := 1.0
const POLL_INTERVAL_SEC := 0.10
const PORT_BASE := 35600
const PORT_SPAN := 400

func _init() -> void:
	print("=== Multiplayer two-process smoke ===")
	var run_dir := _make_run_dir()
	if run_dir.is_empty():
		printerr("FAIL: could not create process test run directory")
		quit(1)
		return

	var port := _find_available_port()
	if port <= 0:
		printerr("FAIL: could not find available local port")
		quit(1)
		return

	var host_report := run_dir.path_join("host.json")
	var host_stop := run_dir.path_join("host.stop")
	var client_report := run_dir.path_join("client.json")
	var client_stop := run_dir.path_join("client.stop")
	var pids: Array[int] = []
	var stop_paths: Array[String] = []

	var host_pid := _start_probe("host", port, host_report, host_stop)
	if host_pid <= 0:
		printerr("FAIL: host process did not start")
		quit(1)
		return
	pids.append(host_pid)
	stop_paths.append(host_stop)

	var host_ready := await _wait_for_report(host_report, HOST_READY_TIMEOUT_SEC, "host")
	if host_ready.is_empty():
		printerr("FAIL: host process did not report hosting state")
		await _stop_processes(pids, stop_paths)
		quit(1)
		return

	var client_pid := _start_probe("client", port, client_report, client_stop)
	if client_pid <= 0:
		printerr("FAIL: client process did not start")
		await _stop_processes(pids, stop_paths)
		quit(1)
		return
	pids.append(client_pid)
	stop_paths.append(client_stop)

	var client_ready := await _wait_for_report(client_report, CLIENT_READY_TIMEOUT_SEC, "client")
	if client_ready.is_empty():
		printerr("FAIL: client process did not receive full snapshot")
		await _stop_processes(pids, stop_paths)
		quit(1)
		return

	host_ready = _read_report(host_report)
	var host_player_id := str(host_ready.get("local_player_citizen_id", ""))
	var host_visible_on_client := await _wait_for_entity_visible(client_report, host_player_id, 4.0)
	if host_visible_on_client.is_empty():
		printerr("FAIL: host player citizen is not visible on client")
		await _stop_processes(pids, stop_paths)
		quit(1)
		return
	var host_moved_on_client := await _wait_for_entity_movement(client_report, host_visible_on_client, host_player_id, 6.0)
	if host_moved_on_client.is_empty():
		printerr("FAIL: host player citizen did not move on client from server snapshots")
		await _stop_processes(pids, stop_paths)
		quit(1)
		return
	client_ready = host_moved_on_client

	var client_player_id := str(client_ready.get("local_player_citizen_id", ""))
	var client_moved_on_host := await _wait_for_entity_movement(host_report, _read_report(host_report), client_player_id, 6.0)
	if client_moved_on_host.is_empty():
		printerr("FAIL: client player citizen did not move on host from server-authoritative input")
		await _stop_processes(pids, stop_paths)
		quit(1)
		return
	host_ready = client_moved_on_host
	host_ready = _read_report(host_report)
	client_ready = _read_report(client_report)
	var interactions_ready := await _wait_for_interaction_travel_started(host_report, INTERACTION_READY_TIMEOUT_SEC)
	if interactions_ready.is_empty():
		printerr("FAIL: server-authorized interaction travel did not start")
		await _stop_processes(pids, stop_paths)
		quit(1)
		return
	host_ready = interactions_ready
	client_ready = _read_report(client_report)
	var effects_ready := await _wait_for_interaction_effect_applied(host_report, INTERACTION_EFFECT_TIMEOUT_SEC)
	if effects_ready.is_empty():
		printerr("FAIL: server-authorized interaction effect was not applied")
		await _stop_processes(pids, stop_paths)
		quit(1)
		return
	host_ready = effects_ready
	client_ready = _read_report(client_report)

	if not _validate_host_client_state(host_ready, client_ready):
		await _stop_processes(pids, stop_paths)
		quit(1)
		return

	_signal_stop(host_stop)
	var disconnect_report := await _wait_for_client_disconnect(client_report, CLIENT_DISCONNECT_TIMEOUT_SEC)
	if disconnect_report.is_empty():
		printerr("FAIL: client did not observe server disconnect")
		await _stop_processes(pids, stop_paths)
		quit(1)
		return

	print("host citizens=%d visible=%d inside=%d player=%s player_visible=%s player_manual=%s buildings=%d time=%s" % [
		int(host_ready.get("citizen_count", 0)),
		int(host_ready.get("visible_citizen_count", 0)),
		int(host_ready.get("inside_citizen_count", 0)),
		str(host_ready.get("local_player_citizen_id", "")),
		str(host_ready.get("local_player_visible", false)),
		str(host_ready.get("local_player_manual_control", false)),
		int(host_ready.get("building_count", 0)),
		_time_text(host_ready),
	])
	print("client citizens=%d visible=%d inside=%d player=%s player_visible=%s player_manual=%s buildings=%d time=%s" % [
		int(client_ready.get("citizen_count", 0)),
		int(client_ready.get("visible_citizen_count", 0)),
		int(client_ready.get("inside_citizen_count", 0)),
		str(client_ready.get("local_player_citizen_id", "")),
		str(client_ready.get("local_player_visible", false)),
		str(client_ready.get("local_player_manual_control", false)),
		int(client_ready.get("building_count", 0)),
		_time_text(client_ready),
	])
	print("client disconnect status=%s" % str(disconnect_report.get("session_status", "")))
	print("MULTIPLAYER_TWO_PROCESS OK")
	await _stop_processes(pids, stop_paths)
	_cleanup_run_dir(run_dir)
	quit(0)

func _start_probe(role: String, port: int, report_path: String, stop_path: String) -> int:
	var args := [
		"--headless",
		"--path",
		ProjectSettings.globalize_path("res://"),
		"--script",
		"res://tools/codex_multiplayer_process_probe.gd",
		"--",
		"--probe-role",
		role,
		"--probe-report",
		report_path,
		"--probe-stop",
		stop_path,
		"--mp-port",
		str(port),
	]
	if role == "host":
		args.append_array(["--mp-host", "--mp-max-clients", "3"])
	else:
		args.append_array(["--mp-client", "--mp-address", "127.0.0.1"])
	return OS.create_process(OS.get_executable_path(), args)

func _wait_for_report(report_path: String, timeout_sec: float, role: String) -> Dictionary:
	var deadline := Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var report := _read_report(report_path)
		if _is_report_ready(report, role):
			return report
		await create_timer(POLL_INTERVAL_SEC).timeout
	return {}

func _wait_for_client_disconnect(report_path: String, timeout_sec: float) -> Dictionary:
	var deadline := Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var report := _read_report(report_path)
		if str(report.get("session_status", "")) == "server_disconnected":
			return report
		await create_timer(POLL_INTERVAL_SEC).timeout
	return {}

func _wait_for_player_movement(report_path: String, start_report: Dictionary, timeout_sec: float) -> Dictionary:
	var start_player_id := str(start_report.get("local_player_citizen_id", ""))
	var start_pos := _position_from_report(start_report)
	if start_player_id.is_empty():
		return {}
	var deadline := Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var report := _read_report(report_path)
		if str(report.get("local_player_citizen_id", "")) != start_player_id:
			await create_timer(POLL_INTERVAL_SEC).timeout
			continue
		var pos := _position_from_report(report)
		if _planar_distance(start_pos, pos) > 0.05:
			return report
		await create_timer(POLL_INTERVAL_SEC).timeout
	return {}

func _wait_for_entity_movement(
	report_path: String,
	start_report: Dictionary,
	entity_id: String,
	timeout_sec: float
) -> Dictionary:
	var start_pos := _position_for_entity(start_report, entity_id)
	if entity_id.is_empty():
		return {}
	var deadline := Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var report := _read_report(report_path)
		var visible_ids := report.get("visible_citizen_ids", []) as Array
		if not visible_ids.has(entity_id):
			await create_timer(POLL_INTERVAL_SEC).timeout
			continue
		var pos := _position_for_entity(report, entity_id)
		if _planar_distance(start_pos, pos) > 0.05:
			return report
		await create_timer(POLL_INTERVAL_SEC).timeout
	return {}

func _wait_for_entity_visible(report_path: String, entity_id: String, timeout_sec: float) -> Dictionary:
	if entity_id.is_empty():
		return {}
	var deadline := Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var report := _read_report(report_path)
		var visible_ids := report.get("visible_citizen_ids", []) as Array
		if visible_ids.has(entity_id):
			return report
		await create_timer(POLL_INTERVAL_SEC).timeout
	return {}

func _wait_for_interaction_travel_started(report_path: String, timeout_sec: float) -> Dictionary:
	var deadline := Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var report := _read_report(report_path)
		if _interaction_travel_ready(report):
			return report
		await create_timer(POLL_INTERVAL_SEC).timeout
	return {}

func _wait_for_interaction_effect_applied(report_path: String, timeout_sec: float) -> Dictionary:
	var deadline := Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var report := _read_report(report_path)
		if _interaction_effect_ready(report):
			return report
		await create_timer(POLL_INTERVAL_SEC).timeout
	return {}

func _interaction_travel_ready(report: Dictionary) -> bool:
	if report.is_empty():
		return false
	var accepted_counts := report.get("host_accepted_interaction_command_count_by_peer", {}) as Dictionary
	if int(accepted_counts.get("1", 0)) <= 0:
		return false
	if _sum_peer_counts_except(accepted_counts, "1") <= 0:
		return false
	var completed_counts := report.get("host_completed_interaction_command_count_by_peer", {}) as Dictionary
	var active_interactions := report.get("host_active_interaction_by_peer", {}) as Dictionary
	var host_ready := int(completed_counts.get("1", 0)) > 0 or active_interactions.has("1")
	var client_ready := _sum_peer_counts_except(completed_counts, "1") > 0 or _active_peer_count_except(active_interactions, "1") > 0
	return host_ready and client_ready

func _interaction_effect_ready(report: Dictionary) -> bool:
	if report.is_empty():
		return false
	var effect_counts := report.get("host_applied_interaction_effect_count_by_peer", {}) as Dictionary
	if int(effect_counts.get("1", 0)) <= 0:
		return false
	return _sum_peer_counts_except(effect_counts, "1") > 0

func _is_report_ready(report: Dictionary, role: String) -> bool:
	if report.is_empty():
		return false
	if role == "host":
		return str(report.get("session_status", "")) == "hosting" \
			and int(report.get("citizen_count", 0)) > 0 \
			and int(report.get("building_count", 0)) > 0
	return str(report.get("session_status", "")) == "connected" \
		and int(report.get("citizen_count", 0)) > 0 \
		and int(report.get("building_count", 0)) > 0 \
		and bool(report.get("authority_gate_checked", false)) \
		and bool(report.get("authority_gate_ok", false))

func _validate_host_client_state(host_report: Dictionary, client_report: Dictionary) -> bool:
	if str(host_report.get("session_status", "")) != "hosting":
		printerr("FAIL: host is not hosting")
		return false
	if str(client_report.get("session_status", "")) != "connected":
		printerr("FAIL: client is not connected")
		return false
	if bool(client_report.get("simulation_authority_enabled", true)):
		printerr("FAIL: client simulation authority is enabled")
		return false
	if not bool(client_report.get("authority_gate_ok", false)):
		printerr("FAIL: client world tick gate advanced local time")
		return false
	if int(host_report.get("citizen_count", -1)) != int(client_report.get("citizen_count", -2)):
		printerr("FAIL: host/client citizen counts differ")
		return false
	if int(host_report.get("visible_citizen_count", 0)) <= 0:
		printerr("FAIL: host has no visible citizens")
		return false
	if int(client_report.get("visible_citizen_count", 0)) <= 0:
		printerr("FAIL: client has no visible replicated citizens")
		return false
	if not bool(client_report.get("client_received_full_snapshot", false)):
		printerr("FAIL: client did not apply a reliable full snapshot")
		return false
	if int(client_report.get("client_building_lookup_count", 0)) != int(client_report.get("building_count", 0)):
		printerr("FAIL: client building lookup does not match replicated building count")
		return false
	if int(client_report.get("client_last_actor_state_sequence", 0)) <= 0:
		printerr("FAIL: client did not apply actor-state delta snapshots")
		return false
	if int(client_report.get("client_last_world_state_sequence", 0)) <= 0:
		printerr("FAIL: client did not apply reliable world-state snapshots")
		return false
	if int(client_report.get("client_replica_interpolation_target_count", 0)) != int(client_report.get("citizen_count", 0)):
		printerr("FAIL: client replica interpolation is not tracking all citizens")
		return false
	if float(client_report.get("client_replica_interpolation_max_error", 0.0)) > 8.0:
		printerr("FAIL: client replica interpolation drift is too large")
		return false
	if int(client_report.get("client_prediction_frame_count", 0)) <= 0:
		printerr("FAIL: client local prediction did not run")
		return false
	if float(client_report.get("client_prediction_distance", 0.0)) <= 0.0:
		printerr("FAIL: client local prediction did not move the player replica")
		return false
	if float(client_report.get("client_prediction_error", 0.0)) > 8.0:
		printerr("FAIL: client local prediction reconciliation error is too large")
		return false
	var host_player_id := str(host_report.get("local_player_citizen_id", ""))
	if host_player_id.is_empty():
		printerr("FAIL: host did not receive a local player citizen id")
		return false
	if not bool(host_report.get("local_player_visible", false)):
		printerr("FAIL: host's assigned player citizen is not visible")
		return false
	if not bool(host_report.get("local_player_manual_control", false)):
		printerr("FAIL: host's assigned player citizen is not marked as server-controlled")
		return false
	var local_player_id := str(client_report.get("local_player_citizen_id", ""))
	if local_player_id.is_empty():
		printerr("FAIL: client did not receive a local player citizen id")
		return false
	if local_player_id == host_player_id:
		printerr("FAIL: host and client received the same player citizen id")
		return false
	if not bool(client_report.get("local_player_visible", false)):
		printerr("FAIL: client's assigned player citizen is not visible")
		return false
	if not bool(client_report.get("local_player_manual_control", false)):
		printerr("FAIL: client's assigned player citizen is not marked as server-controlled")
		return false
	var client_visible_ids := client_report.get("visible_citizen_ids", []) as Array
	if not client_visible_ids.has(host_player_id):
		printerr("FAIL: host player citizen is not visible on the client")
		return false
	if int(host_report.get("host_drive_frames_sent", 0)) <= 0:
		printerr("FAIL: host player was not driven during the process test")
		return false
	if not bool(client_report.get("client_interaction_command_sent", false)):
		printerr("FAIL: client did not send an interaction command")
		return false
	if not bool(host_report.get("host_interaction_request_sent", false)):
		printerr("FAIL: host did not send a local interaction command")
		return false
	var host_interaction_counts := host_report.get("host_accepted_interaction_command_count_by_peer", {}) as Dictionary
	if int(host_interaction_counts.get("1", 0)) <= 0:
		printerr("FAIL: host local interaction command was not accepted")
		return false
	if _sum_peer_counts_except(host_interaction_counts, "1") <= 0:
		printerr("FAIL: client interaction command was not accepted by the host")
		return false
	if int(host_report.get("host_interaction_command_count", 0)) <= 1:
		printerr("FAIL: host did not receive the client interaction command")
		return false
	if int(host_report.get("host_accepted_interaction_command_count", 0)) <= 1:
		printerr("FAIL: host did not accept the client interaction command")
		return false
	var completed_interaction_counts := host_report.get("host_completed_interaction_command_count_by_peer", {}) as Dictionary
	var active_interactions := host_report.get("host_active_interaction_by_peer", {}) as Dictionary
	if int(completed_interaction_counts.get("1", 0)) <= 0 and not active_interactions.has("1"):
		printerr("FAIL: host local interaction did not start travel or complete")
		return false
	if _sum_peer_counts_except(completed_interaction_counts, "1") <= 0 and _active_peer_count_except(active_interactions, "1") <= 0:
		printerr("FAIL: client interaction did not start server-authorized travel or complete")
		return false
	var effect_counts := host_report.get("host_applied_interaction_effect_count_by_peer", {}) as Dictionary
	if int(effect_counts.get("1", 0)) <= 0:
		printerr("FAIL: host local interaction effect was not applied")
		return false
	if _sum_peer_counts_except(effect_counts, "1") <= 0:
		printerr("FAIL: client interaction effect was not applied by the host")
		return false
	if int(host_report.get("building_count", -1)) != int(client_report.get("building_count", -2)):
		printerr("FAIL: host/client building counts differ")
		return false
	var host_ids := host_report.get("citizen_ids", []) as Array
	var client_ids := client_report.get("citizen_ids", []) as Array
	if host_ids != client_ids:
		printerr("FAIL: host/client citizen network ids differ")
		return false
	if not host_ids.has(host_player_id):
		printerr("FAIL: host assigned player citizen id is not part of the host snapshot")
		return false
	if not client_ids.has(local_player_id):
		printerr("FAIL: assigned player citizen id is not part of the client snapshot")
		return false
	var minute_delta := absi(int(host_report.get("minutes_total", 0)) - int(client_report.get("minutes_total", 0)))
	if minute_delta > 3:
		printerr("FAIL: host/client time drift too large (%d minutes)" % minute_delta)
		return false
	return true

func _read_report(report_path: String) -> Dictionary:
	if report_path.is_empty() or not FileAccess.file_exists(report_path):
		return {}
	var text := FileAccess.get_file_as_string(report_path)
	if text.is_empty():
		return {}
	var json := JSON.new()
	if json.parse(text) != OK:
		return {}
	var parsed: Variant = json.data
	return parsed as Dictionary if parsed is Dictionary else {}

func _stop_processes(pids: Array[int], stop_paths: Array[String]) -> void:
	for stop_path in stop_paths:
		_signal_stop(stop_path)
	await create_timer(SHUTDOWN_WAIT_SEC).timeout
	for pid in pids:
		if pid > 0:
			OS.kill(pid)

func _signal_stop(stop_path: String) -> void:
	var file := FileAccess.open(stop_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string("stop")
	file.close()

func _make_run_dir() -> String:
	var root_dir := ProjectSettings.globalize_path("res://.ai/test_runs")
	var run_dir := root_dir.path_join("mp_two_process_%d_%d" % [OS.get_process_id(), Time.get_ticks_msec()])
	var err := DirAccess.make_dir_recursive_absolute(run_dir)
	if err != OK:
		return ""
	return run_dir

func _cleanup_run_dir(run_dir: String) -> void:
	var dir := DirAccess.open(run_dir)
	if dir == null:
		return
	for file_name in ["host.json", "host.stop", "client.json", "client.stop"]:
		if FileAccess.file_exists(run_dir.path_join(file_name)):
			dir.remove(file_name)
	var parent_dir := DirAccess.open(run_dir.get_base_dir())
	if parent_dir != null:
		parent_dir.remove(run_dir.get_file())

func _find_available_port() -> int:
	var server := ENetMultiplayerPeer.new()
	var offset := OS.get_process_id() % PORT_SPAN
	for attempt in range(PORT_SPAN):
		var port := PORT_BASE + ((offset + attempt) % PORT_SPAN)
		var err := server.create_server(port, 1)
		if err == OK:
			server.close()
			return port
	server.close()
	return -1

func _time_text(report: Dictionary) -> String:
	return "day %d %02d:%02d" % [
		int(report.get("day", 0)),
		int(report.get("hour", 0)),
		int(report.get("minute", 0)),
	]

func _position_from_report(report: Dictionary) -> Vector3:
	var raw: Variant = report.get("local_player_position", [])
	if raw is Array and (raw as Array).size() >= 3:
		var values := raw as Array
		return Vector3(float(values[0]), float(values[1]), float(values[2]))
	return Vector3.ZERO

func _position_for_entity(report: Dictionary, entity_id: String) -> Vector3:
	if entity_id.is_empty():
		return Vector3.ZERO
	var positions := report.get("citizen_positions_by_id", {}) as Dictionary
	var raw: Variant = positions.get(entity_id, [])
	if raw is Array and (raw as Array).size() >= 3:
		var values := raw as Array
		return Vector3(float(values[0]), float(values[1]), float(values[2]))
	return Vector3.ZERO

func _sum_peer_counts_except(counts: Dictionary, excluded_key: String) -> int:
	var total := 0
	for key in counts.keys():
		if str(key) == excluded_key:
			continue
		total += int(counts.get(key, 0))
	return total

func _active_peer_count_except(active_interactions: Dictionary, excluded_key: String) -> int:
	var total := 0
	for key in active_interactions.keys():
		if str(key) == excluded_key:
			continue
		total += 1
	return total

func _planar_distance(a: Vector3, b: Vector3) -> float:
	a.y = 0.0
	b.y = 0.0
	return a.distance_to(b)
