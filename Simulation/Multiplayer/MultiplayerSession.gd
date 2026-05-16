extends Node
class_name MultiplayerSession

signal status_changed(status: String, detail: String)

const NetworkRoleScript = preload("res://Simulation/Multiplayer/shared/NetworkRole.gd")
const LaunchOptionsScript = preload("res://Simulation/Multiplayer/shared/MultiplayerLaunchOptions.gd")
const HostAuthorityScript = preload("res://Simulation/Multiplayer/server/MultiplayerHostAuthority.gd")
const ClientReplicaScript = preload("res://Simulation/Multiplayer/client/MultiplayerClientReplica.gd")
const NetworkEntityRegistryScript = preload("res://Simulation/Multiplayer/shared/NetworkEntityRegistry.gd")

var root_node: Node = null
var world: World = null
var role: String = NetworkRoleScript.OFFLINE
var address: String = LaunchOptionsScript.DEFAULT_ADDRESS
var port: int = LaunchOptionsScript.DEFAULT_PORT
var max_clients: int = LaunchOptionsScript.DEFAULT_MAX_CLIENTS

var _host_authority = null
var _client_replica = null
var _status: String = "offline"
var _detail: String = ""

# Wires the session to the scene without picking a role yet. Used by the
# pre-game menu, which decides host/join/offline interactively afterwards.
func bind(root_ref: Node, world_ref: World) -> void:
	root_node = root_ref
	world = world_ref

func setup(root_ref: Node, world_ref: World, launch_options: Dictionary = {}) -> void:
	bind(root_ref, world_ref)
	var options := launch_options
	if options.is_empty():
		options = LaunchOptionsScript.from_command_line()
	apply_options(options)

# Resolves a role from an options dictionary and acts on it. Same effect as the
# original setup() tail, kept separate so the menu can reuse it for CLI parity.
func apply_options(options: Dictionary) -> void:
	role = NetworkRoleScript.normalize(str(options.get("role", NetworkRoleScript.OFFLINE)))
	address = str(options.get("address", LaunchOptionsScript.DEFAULT_ADDRESS))
	port = int(options.get("port", LaunchOptionsScript.DEFAULT_PORT))
	max_clients = int(options.get("max_clients", LaunchOptionsScript.DEFAULT_MAX_CLIENTS))

	match role:
		NetworkRoleScript.HOST:
			host_game(port, max_clients)
		NetworkRoleScript.CLIENT:
			join_game(address, port)
		_:
			_enter_offline_mode()

func start_offline() -> void:
	_stop_network_peers()
	role = NetworkRoleScript.OFFLINE
	_enter_offline_mode()

func update(delta: float) -> void:
	if _host_authority != null:
		_host_authority.update(delta)
	if _client_replica != null and _client_replica.has_method("update"):
		_client_replica.update(delta)

func is_host() -> bool:
	return role == NetworkRoleScript.HOST

func is_client() -> bool:
	return role == NetworkRoleScript.CLIENT

func is_server_authority() -> bool:
	return NetworkRoleScript.is_server_authority(role)

func get_status() -> Dictionary:
	var status := {
		"role": role,
		"status": _status,
		"detail": _detail,
		"address": address,
		"port": port,
		"max_clients": max_clients,
		"local_player_citizen_id": get_local_player_citizen_id(),
	}
	if _host_authority != null and _host_authority.has_method("get_debug_status"):
		status["host_debug"] = _host_authority.get_debug_status()
	if _client_replica != null and _client_replica.has_method("get_debug_status"):
		status["client_debug"] = _client_replica.get_debug_status()
	return status

func get_local_player_citizen_id() -> String:
	if _client_replica != null:
		return str(_client_replica.local_player_citizen_id)
	if _host_authority != null and _host_authority.has_method("get_local_player_citizen_id"):
		return _host_authority.get_local_player_citizen_id()
	return ""

func get_local_player_citizen() -> Citizen:
	if _client_replica != null and _client_replica.has_method("get_local_player_citizen"):
		return _client_replica.get_local_player_citizen()
	if _host_authority != null and _host_authority.has_method("get_local_player_citizen"):
		return _host_authority.get_local_player_citizen()
	return null

func ensure_local_host_player() -> String:
	if _host_authority == null or not _host_authority.has_method("ensure_local_host_player"):
		return ""
	return _host_authority.ensure_local_host_player()

func host_game(host_port: int = LaunchOptionsScript.DEFAULT_PORT, host_max_clients: int = LaunchOptionsScript.DEFAULT_MAX_CLIENTS) -> Error:
	_stop_network_peers()
	role = NetworkRoleScript.HOST
	port = host_port
	max_clients = clampi(host_max_clients, 1, LaunchOptionsScript.MAX_CLIENTS)
	_host_authority = HostAuthorityScript.new()
	_host_authority.setup(root_node, world, self)
	var err: Error = _host_authority.start_host(port, max_clients)
	if err != OK:
		if _host_authority != null:
			_host_authority.stop()
			_host_authority = null
		_set_status("host_error", "Could not start ENet host on port %d (error %d)." % [port, err])
		return err
	_set_status("hosting", "Hosting on port %d for up to %d clients." % [port, max_clients])
	return OK

func join_game(join_address: String = LaunchOptionsScript.DEFAULT_ADDRESS, join_port: int = LaunchOptionsScript.DEFAULT_PORT) -> Error:
	_stop_network_peers()
	role = NetworkRoleScript.CLIENT
	address = join_address
	port = join_port
	_client_replica = ClientReplicaScript.new()
	_client_replica.setup(root_node, world, self)
	var err: Error = _client_replica.join_game(address, port)
	if err != OK:
		if _client_replica != null:
			_client_replica.stop()
			_client_replica = null
		_set_status("join_error", "Could not connect to %s:%d (error %d)." % [address, port, err])
		return err
	_set_status("joining", "Connecting to %s:%d." % [address, port])
	return OK

func send_command(command: Dictionary) -> void:
	if _client_replica == null:
		return
	_client_replica.send_command(command)

func request_entity_interaction(target: Node) -> void:
	if target == null:
		return
	var target_id := NetworkEntityRegistryScript.get_entity_id(target)
	if target_id.is_empty():
		return
	var command := {
		"type": "interact_entity",
		"target_id": target_id,
	}
	if is_client():
		send_command(command)
	elif is_host() and _host_authority != null and _host_authority.has_method("handle_local_command"):
		_host_authority.handle_local_command(command)

func _enter_offline_mode() -> void:
	if world != null and world.has_method("set_simulation_authority_enabled"):
		world.set_simulation_authority_enabled(true)
	_set_status("offline", "Local offline simulation authority.")

func _set_status(status: String, detail: String = "") -> void:
	_status = status
	_detail = detail
	status_changed.emit(status, detail)

func _stop_network_peers() -> void:
	if _host_authority != null:
		_host_authority.stop()
		_host_authority = null
	if _client_replica != null:
		_client_replica.stop()
		_client_replica = null

func _client_transport_connected() -> void:
	if not is_client():
		return
	_set_status("transport_connected", "Connected to %s:%d. Waiting for world snapshot." % [address, port])

func _client_connection_failed() -> void:
	if not is_client():
		return
	_set_status("connection_failed", "Connection to %s:%d failed." % [address, port])

func _client_server_disconnected() -> void:
	if not is_client():
		return
	_set_status("server_disconnected", "Server disconnected.")

@rpc("authority", "call_remote", "reliable")
func _client_apply_full_snapshot(snapshot: Dictionary) -> void:
	if _client_replica == null:
		return
	_client_replica.apply_snapshot(snapshot)
	_set_status("connected", "Received full snapshot sequence %d." % int(snapshot.get("sequence", 0)))

@rpc("authority", "call_remote", "unreliable_ordered", 0)
func _client_apply_snapshot(snapshot: Dictionary) -> void:
	if _client_replica == null:
		return
	_client_replica.apply_snapshot(snapshot)

@rpc("authority", "call_remote", "reliable")
func _client_apply_world_state_snapshot(snapshot: Dictionary) -> void:
	if _client_replica == null:
		return
	_client_replica.apply_snapshot(snapshot)

@rpc("any_peer", "call_remote", "reliable")
func _server_receive_command(command: Dictionary) -> void:
	if _host_authority == null:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	_host_authority.handle_client_command(sender_id, command)
