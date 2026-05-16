extends RefCounted
class_name MultiplayerHostAuthority

const NetworkEntityRegistryScript = preload("res://Simulation/Multiplayer/shared/NetworkEntityRegistry.gd")
const WorldSnapshotSerializerScript = preload("res://Simulation/Multiplayer/shared/WorldSnapshotSerializer.gd")

const SNAPSHOT_INTERVAL_SEC := 0.25

var root_node: Node = null
var world: World = null
var session_node: Node = null
var registry = NetworkEntityRegistryScript.new()

var _peer: ENetMultiplayerPeer = null
var _snapshot_sequence: int = 0
var _snapshot_timer: float = 0.0
var _active: bool = false
var _player_citizen_id_by_peer: Dictionary = {}

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
	_disconnect_signals()
	if session_node != null and session_node.multiplayer.has_multiplayer_peer():
		session_node.multiplayer.multiplayer_peer = null
	if _peer != null:
		_peer.close()
	_peer = null

func update(delta: float) -> void:
	if not _active or session_node == null:
		return
	_snapshot_timer -= delta
	if _snapshot_timer > 0.0:
		return
	_snapshot_timer = SNAPSHOT_INTERVAL_SEC
	send_snapshot_to_all(false)

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
	snapshot["local_player_citizen_id"] = str(_player_citizen_id_by_peer.get(peer_id, ""))

func _assign_player_citizen(peer_id: int) -> String:
	var existing_id := str(_player_citizen_id_by_peer.get(peer_id, ""))
	if not existing_id.is_empty() and _find_citizen_by_id(existing_id) != null:
		return existing_id
	if world == null or root_node == null:
		return ""
	registry.ensure_world_entities(world, root_node)
	var reserved_ids := _reserved_player_citizen_ids()
	for citizen in world.citizens:
		if citizen == null or not is_instance_valid(citizen):
			continue
		if not citizen.autonomous_simulation_enabled:
			continue
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
	citizen.apply_network_server_control_input(direction, world)

func _reserved_player_citizen_ids() -> Dictionary:
	var reserved: Dictionary = {}
	for value in _player_citizen_id_by_peer.values():
		var entity_id := str(value)
		if not entity_id.is_empty():
			reserved[entity_id] = true
	return reserved

func _find_citizen_by_id(entity_id: String) -> Citizen:
	if entity_id.is_empty() or world == null:
		return null
	for citizen in world.citizens:
		if citizen == null or not is_instance_valid(citizen):
			continue
		if NetworkEntityRegistryScript.get_entity_id(citizen) == entity_id:
			return citizen
	return null
