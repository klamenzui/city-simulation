extends RefCounted
class_name MultiplayerClientReplica

const NetworkEntityRegistryScript = preload("res://Simulation/Multiplayer/shared/NetworkEntityRegistry.gd")
const WorldSnapshotSerializerScript = preload("res://Simulation/Multiplayer/shared/WorldSnapshotSerializer.gd")
const CITIZEN_SCENE_PATH := "res://Entities/Citizens/CitizenNew.tscn"

var root_node: Node = null
var world: World = null
var session_node: Node = null

var _peer: ENetMultiplayerPeer = null
var _replica_root: Node3D = null
var _citizen_scene: PackedScene = null
var _citizen_by_id: Dictionary = {}
var _last_sequence: int = 0

func setup(root_ref: Node, world_ref: World, session_ref: Node) -> void:
	root_node = root_ref
	world = world_ref
	session_node = session_ref
	_citizen_scene = load(CITIZEN_SCENE_PATH)
	_ensure_replica_root()
	if world != null and world.has_method("set_simulation_authority_enabled"):
		world.set_simulation_authority_enabled(false)

func join_game(address: String, port: int) -> Error:
	if session_node == null:
		return ERR_UNCONFIGURED
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(address, port)
	if err != OK:
		return err
	session_node.multiplayer.multiplayer_peer = _peer
	_connect_signals()
	if world != null and world.has_method("set_simulation_authority_enabled"):
		world.set_simulation_authority_enabled(false)
	return OK

func stop() -> void:
	_disconnect_signals()
	if session_node != null and session_node.multiplayer.has_multiplayer_peer():
		session_node.multiplayer.multiplayer_peer = null
	if _peer != null:
		_peer.close()
	_peer = null

func apply_snapshot(snapshot: Dictionary) -> void:
	if snapshot.is_empty() or world == null or root_node == null:
		return
	var sequence := int(snapshot.get("sequence", 0))
	if sequence > 0 and sequence < _last_sequence:
		return
	_last_sequence = sequence

	WorldSnapshotSerializerScript.apply_snapshot_to_world(world, root_node, snapshot)
	var building_lookup := WorldSnapshotSerializerScript.build_building_lookup(
		root_node,
		snapshot.get("buildings", [])
	)
	_apply_citizen_snapshots(snapshot.get("citizens", []), building_lookup)

func send_command(command: Dictionary) -> void:
	if session_node == null or command.is_empty():
		return
	session_node.rpc_id(1, "_server_receive_command", command)

func _connect_signals() -> void:
	if session_node == null:
		return
	var connected_cb := Callable(self, "_on_connected_to_server")
	var failed_cb := Callable(self, "_on_connection_failed")
	var disconnected_cb := Callable(self, "_on_server_disconnected")
	if not session_node.multiplayer.connected_to_server.is_connected(connected_cb):
		session_node.multiplayer.connected_to_server.connect(connected_cb)
	if not session_node.multiplayer.connection_failed.is_connected(failed_cb):
		session_node.multiplayer.connection_failed.connect(failed_cb)
	if not session_node.multiplayer.server_disconnected.is_connected(disconnected_cb):
		session_node.multiplayer.server_disconnected.connect(disconnected_cb)

func _disconnect_signals() -> void:
	if session_node == null:
		return
	var connected_cb := Callable(self, "_on_connected_to_server")
	var failed_cb := Callable(self, "_on_connection_failed")
	var disconnected_cb := Callable(self, "_on_server_disconnected")
	if session_node.multiplayer.connected_to_server.is_connected(connected_cb):
		session_node.multiplayer.connected_to_server.disconnect(connected_cb)
	if session_node.multiplayer.connection_failed.is_connected(failed_cb):
		session_node.multiplayer.connection_failed.disconnect(failed_cb)
	if session_node.multiplayer.server_disconnected.is_connected(disconnected_cb):
		session_node.multiplayer.server_disconnected.disconnect(disconnected_cb)

func _ensure_replica_root() -> void:
	if _replica_root != null:
		return
	if root_node == null:
		return
	_replica_root = root_node.get_node_or_null("ClientReplicas") as Node3D
	if _replica_root != null:
		return
	_replica_root = Node3D.new()
	_replica_root.name = "ClientReplicas"
	root_node.add_child(_replica_root)

func _apply_citizen_snapshots(entries: Variant, building_lookup: Dictionary) -> void:
	if entries is not Array:
		return
	var seen: Dictionary = {}
	for entry in entries:
		if entry is not Dictionary:
			continue
		var data := entry as Dictionary
		var entity_id := str(data.get("id", ""))
		if entity_id.is_empty():
			continue
		seen[entity_id] = true
		var citizen := _get_or_create_citizen(entity_id)
		if citizen == null:
			continue
		if citizen.has_method("apply_network_snapshot"):
			citizen.apply_network_snapshot(data, building_lookup)
		else:
			citizen.global_position = WorldSnapshotSerializerScript.vector_from_snapshot(data.get("position", []), citizen.global_position)
	_remove_missing_citizens(seen)

func _get_or_create_citizen(entity_id: String) -> Citizen:
	if _citizen_by_id.has(entity_id):
		var existing := _citizen_by_id[entity_id] as Citizen
		if existing != null and is_instance_valid(existing):
			return existing
		_citizen_by_id.erase(entity_id)
	if _citizen_scene == null:
		return null
	_ensure_replica_root()
	if _replica_root == null:
		return null
	var instance := _citizen_scene.instantiate()
	if instance is not Citizen:
		instance.queue_free()
		return null
	var citizen := instance as Citizen
	citizen.name = _safe_node_name("RemoteCitizen_%s" % entity_id)
	if citizen.has_method("set_network_replica_mode"):
		citizen.set_network_replica_mode(true)
	else:
		citizen.autonomous_simulation_enabled = false
	NetworkEntityRegistryScript.set_entity_id(citizen, entity_id)
	_replica_root.add_child(citizen)
	if citizen.has_method("set_network_replica_mode"):
		citizen.set_network_replica_mode(true)
	citizen.set_physics_process(false)
	_citizen_by_id[entity_id] = citizen
	return citizen

func _remove_missing_citizens(seen: Dictionary) -> void:
	var ids := _citizen_by_id.keys()
	for entity_id in ids:
		if seen.has(entity_id):
			continue
		var citizen := _citizen_by_id[entity_id] as Citizen
		_citizen_by_id.erase(entity_id)
		if citizen != null and is_instance_valid(citizen):
			citizen.queue_free()

func _safe_node_name(value: String) -> String:
	var result := value
	for ch in [":", "/", "\\", " ", "."]:
		result = result.replace(ch, "_")
	return result

func _on_connected_to_server() -> void:
	if session_node != null and session_node.has_method("_client_transport_connected"):
		session_node.call("_client_transport_connected")

func _on_connection_failed() -> void:
	if world != null and world.has_method("set_simulation_authority_enabled"):
		world.set_simulation_authority_enabled(false)
	if session_node != null and session_node.has_method("_client_connection_failed"):
		session_node.call("_client_connection_failed")

func _on_server_disconnected() -> void:
	if world != null and world.has_method("set_simulation_authority_enabled"):
		world.set_simulation_authority_enabled(false)
	if session_node != null and session_node.has_method("_client_server_disconnected"):
		session_node.call("_client_server_disconnected")
