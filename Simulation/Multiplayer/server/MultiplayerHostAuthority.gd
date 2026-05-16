extends RefCounted
class_name MultiplayerHostAuthority

const NetworkEntityRegistryScript = preload("res://Simulation/Multiplayer/shared/NetworkEntityRegistry.gd")
const WorldSnapshotSerializerScript = preload("res://Simulation/Multiplayer/shared/WorldSnapshotSerializer.gd")

const SNAPSHOT_INTERVAL_SEC := 0.25
const LOCAL_HOST_PEER_ID := 1

var root_node: Node = null
var world: World = null
var session_node: Node = null
var registry = NetworkEntityRegistryScript.new()

var _peer: ENetMultiplayerPeer = null
var _snapshot_sequence: int = 0
var _snapshot_timer: float = 0.0
var _active: bool = false
var _player_citizen_id_by_peer: Dictionary = {}
var _player_input_command_count_by_peer: Dictionary = {}
var _last_player_input_direction_by_peer: Dictionary = {}
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
	_snapshot_timer -= delta
	if _snapshot_timer > 0.0:
		return
	_snapshot_timer = SNAPSHOT_INTERVAL_SEC
	send_snapshot_to_all(false)

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
	}

func build_snapshot() -> Dictionary:
	_snapshot_sequence += 1
	return WorldSnapshotSerializerScript.build_snapshot(world, root_node, _snapshot_sequence, registry)

func send_snapshot_to_all(full_snapshot: bool) -> void:
	if session_node == null or not session_node.multiplayer.has_multiplayer_peer():
		return
	var peers := session_node.multiplayer.get_peers()
	if peers.is_empty():
		return
	var base_snapshot := build_snapshot()
	for peer_id in peers:
		var snapshot := base_snapshot.duplicate(true)
		_add_peer_snapshot_context(snapshot, int(peer_id))
		_send_snapshot_to_peer(int(peer_id), snapshot, full_snapshot)

func send_full_snapshot_to_peer(peer_id: int) -> void:
	var snapshot := build_snapshot()
	_add_peer_snapshot_context(snapshot, peer_id)
	_send_snapshot_to_peer(peer_id, snapshot, true)

func handle_client_command(peer_id: int, command: Dictionary) -> void:
	if peer_id <= 1 or command.is_empty():
		return
	match str(command.get("type", "")):
		"player_input":
			_handle_player_input_command(peer_id, command)

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

func _on_peer_disconnected(peer_id: int) -> void:
	_release_player_citizen(peer_id)

func _send_snapshot_to_peer(peer_id: int, snapshot: Dictionary, full_snapshot: bool) -> void:
	if session_node == null or snapshot.is_empty():
		return
	if full_snapshot:
		session_node.rpc_id(peer_id, "_client_apply_full_snapshot", snapshot)
	else:
		session_node.rpc_id(peer_id, "_client_apply_snapshot", snapshot)

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
	_player_input_command_count_by_peer[peer_id] = int(_player_input_command_count_by_peer.get(peer_id, 0)) + 1
	_last_player_input_direction_by_peer[str(peer_id)] = [direction.x, direction.y, direction.z]
	citizen.apply_network_server_control_input(direction, world)

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
	citizen.apply_network_server_control_input(_get_local_host_input_direction(), world)
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

func _find_citizen_by_id(entity_id: String) -> Citizen:
	if entity_id.is_empty() or world == null:
		return null
	for citizen in world.citizens:
		if citizen == null or not is_instance_valid(citizen):
			continue
		if NetworkEntityRegistryScript.get_entity_id(citizen) == entity_id:
			return citizen
	return null
