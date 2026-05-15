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
	var snapshot := build_snapshot()
	for peer_id in peers:
		_send_snapshot_to_peer(int(peer_id), snapshot, full_snapshot)

func send_full_snapshot_to_peer(peer_id: int) -> void:
	var snapshot := build_snapshot()
	_send_snapshot_to_peer(peer_id, snapshot, true)

func handle_client_command(peer_id: int, command: Dictionary) -> void:
	# Phase 1 only accepts the channel and validates ownership. Gameplay
	# commands are intentionally ignored until Phase 2 input work begins.
	if peer_id <= 1 or command.is_empty():
		return

func _connect_signals() -> void:
	if session_node == null:
		return
	var peer_connected_cb := Callable(self, "_on_peer_connected")
	var peer_disconnected_cb := Callable(self, "_on_peer_disconnected")
	if not session_node.multiplayer.peer_connected.is_connected(peer_connected_cb):
		session_node.multiplayer.peer_connected.connect(peer_connected_cb)
	if not session_node.multiplayer.peer_disconnected.is_connected(peer_disconnected_cb):
		session_node.multiplayer.peer_disconnected.connect(peer_disconnected_cb)

func _on_peer_connected(peer_id: int) -> void:
	send_full_snapshot_to_peer(peer_id)

func _on_peer_disconnected(_peer_id: int) -> void:
	pass

func _send_snapshot_to_peer(peer_id: int, snapshot: Dictionary, full_snapshot: bool) -> void:
	if session_node == null or snapshot.is_empty():
		return
	if full_snapshot:
		session_node.rpc_id(peer_id, "_client_apply_full_snapshot", snapshot)
	else:
		session_node.rpc_id(peer_id, "_client_apply_snapshot", snapshot)
