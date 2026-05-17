extends SceneTree

const SETTLE_FRAMES := 30
const CONNECT_FRAMES := 120
const PORT_BASE := 34200
const PORT_SPAN := 400

const NetworkEntityRegistryScript = preload("res://Simulation/Multiplayer/shared/NetworkEntityRegistry.gd")
const WorldSnapshotSerializerScript = preload("res://Simulation/Multiplayer/shared/WorldSnapshotSerializer.gd")

func _init() -> void:
	print("=== Multiplayer host/connect smoke ===")
	var main_scene := load("res://Main.tscn")
	if main_scene == null:
		printerr("FAIL: cannot load Main.tscn")
		quit(1)
		return

	var main: Node = main_scene.instantiate()
	root.add_child(main)
	for _i in range(SETTLE_FRAMES):
		await process_frame

	var world := main.get_node_or_null("World") as World
	if world == null:
		printerr("FAIL: World node not found")
		quit(1)
		return
	var session := main.get_node_or_null("MultiplayerSession")
	if session == null:
		printerr("FAIL: MultiplayerSession node not found")
		quit(1)
		return
	if session.is_client():
		printerr("FAIL: smoke scene should start offline without command-line args")
		quit(1)
		return

	var registry = NetworkEntityRegistryScript.new()
	var snapshot_a := WorldSnapshotSerializerScript.build_snapshot(world, main, 1, registry)
	var snapshot_b := WorldSnapshotSerializerScript.build_snapshot(world, main, 2, registry)
	if snapshot_a.is_empty() or snapshot_b.is_empty():
		printerr("FAIL: snapshot generation returned empty data")
		quit(1)
		return
	if (snapshot_a.get("citizens", []) as Array).is_empty():
		printerr("FAIL: snapshot has no citizens")
		quit(1)
		return
	if not _citizens_have_fall_respawn_debug(snapshot_a.get("citizens", [])):
		printerr("FAIL: citizen snapshots missing fall respawn debug field")
		quit(1)
		return
	if (snapshot_a.get("buildings", []) as Array).is_empty():
		printerr("FAIL: snapshot has no buildings")
		quit(1)
		return
	if not _ids_match(snapshot_a.get("citizens", []), snapshot_b.get("citizens", [])):
		printerr("FAIL: citizen network ids drifted between snapshots")
		quit(1)
		return

	var minute_before := world.time.minutes_total
	world.set_simulation_authority_enabled(false)
	world.call("_on_tick")
	if world.time.minutes_total != minute_before:
		printerr("FAIL: client-side world tick gate advanced time")
		quit(1)
		return
	world.set_simulation_authority_enabled(true)

	var connect_ok := await _run_enet_loopback_connect()
	if not connect_ok:
		printerr("FAIL: ENet loopback host/client did not connect")
		quit(1)
		return

	print("snapshot citizens=%d buildings=%d sequence=%d" % [
		(snapshot_a.get("citizens", []) as Array).size(),
		(snapshot_a.get("buildings", []) as Array).size(),
		int(snapshot_a.get("sequence", 0)),
	])
	print("MULTIPLAYER_HOST_CONNECT OK")
	main.queue_free()
	await process_frame
	quit(0)

func _ids_match(left: Variant, right: Variant) -> bool:
	if left is not Array or right is not Array:
		return false
	var left_arr := left as Array
	var right_arr := right as Array
	if left_arr.size() != right_arr.size():
		return false
	for idx in range(left_arr.size()):
		var left_entry := left_arr[idx] as Dictionary
		var right_entry := right_arr[idx] as Dictionary
		if left_entry == null or right_entry == null:
			return false
		if str(left_entry.get("id", "")) != str(right_entry.get("id", "")):
			return false
	return true

func _citizens_have_fall_respawn_debug(entries: Variant) -> bool:
	if entries is not Array:
		return false
	var entry_array := entries as Array
	for entry in entry_array:
		if entry is not Dictionary:
			return false
		if not (entry as Dictionary).has("fall_respawn_count"):
			return false
	return true

func _run_enet_loopback_connect() -> bool:
	var server := ENetMultiplayerPeer.new()
	var port := _create_server_on_available_port(server)
	if port <= 0:
		return false
	var client := ENetMultiplayerPeer.new()
	var err := client.create_client("127.0.0.1", port)
	if err != OK:
		server.close()
		return false

	var connected := false
	for _i in range(CONNECT_FRAMES):
		server.poll()
		client.poll()
		if client.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			connected = true
			break
		await process_frame

	client.close()
	server.close()
	return connected

func _create_server_on_available_port(server: ENetMultiplayerPeer) -> int:
	var offset := OS.get_process_id() % PORT_SPAN
	for attempt in range(PORT_SPAN):
		var port := PORT_BASE + ((offset + attempt) % PORT_SPAN)
		var err := server.create_server(port, 1)
		if err == OK:
			return port
	return -1
