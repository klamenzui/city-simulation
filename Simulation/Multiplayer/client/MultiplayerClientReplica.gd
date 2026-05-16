extends RefCounted
class_name MultiplayerClientReplica

const NetworkEntityRegistryScript = preload("res://Simulation/Multiplayer/shared/NetworkEntityRegistry.gd")
const WorldSnapshotSerializerScript = preload("res://Simulation/Multiplayer/shared/WorldSnapshotSerializer.gd")
const CITIZEN_SCENE_PATH := "res://Entities/Citizens/CitizenNew.tscn"
const INPUT_SEND_INTERVAL_SEC := 0.05
const REPLICA_INTERPOLATION_SPEED := 10.0
const REPLICA_ROTATION_INTERPOLATION_SPEED := 12.0
const REPLICA_SNAP_DISTANCE_METERS := 8.0
const REPLICA_TARGET_EPSILON_METERS := 0.02
const LOCAL_PLAYER_DEFAULT_PREDICTION_SPEED := 0.5

var root_node: Node = null
var world: World = null
var session_node: Node = null
var local_player_citizen_id: String = ""

var _peer: ENetMultiplayerPeer = null
var _replica_root: Node3D = null
var _citizen_scene: PackedScene = null
var _building_lookup_by_id: Dictionary = {}
var _citizen_by_id: Dictionary = {}
var _replica_interpolation_by_id: Dictionary = {}
var _received_full_snapshot: bool = false
var _last_full_sequence: int = 0
var _last_actor_state_sequence: int = 0
var _last_world_state_sequence: int = 0
var _input_timer: float = 0.0
var _input_sequence: int = 0
var _camera_follow_target_id: String = ""
var _last_sent_input_direction: Vector3 = Vector3.ZERO
var _local_prediction_frame_count: int = 0
var _local_prediction_distance: float = 0.0
var _last_prediction_direction: Vector3 = Vector3.ZERO

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
	local_player_citizen_id = ""
	_camera_follow_target_id = ""
	_last_sent_input_direction = Vector3.ZERO
	_building_lookup_by_id.clear()
	_replica_interpolation_by_id.clear()
	_received_full_snapshot = false
	_last_full_sequence = 0
	_last_actor_state_sequence = 0
	_last_world_state_sequence = 0
	_reset_local_prediction_debug()

func update(delta: float) -> void:
	_update_replica_interpolation(delta)
	if local_player_citizen_id.is_empty() or session_node == null:
		return
	var direction := _get_player_input_direction()
	_apply_local_player_prediction(delta, direction)
	_input_timer -= delta
	if _input_timer > 0.0:
		return
	_input_timer = INPUT_SEND_INTERVAL_SEC
	if direction.length_squared() <= 0.0001 and _last_sent_input_direction.length_squared() <= 0.0001:
		return
	_input_sequence += 1
	_send_command_raw({
		"type": "player_input",
		"sequence": _input_sequence,
		"direction": _vec3_to_array(direction),
	})
	_last_sent_input_direction = direction

func apply_snapshot(snapshot: Dictionary) -> void:
	if snapshot.is_empty() or world == null or root_node == null:
		return
	var snapshot_kind := str(snapshot.get("snapshot_kind", WorldSnapshotSerializerScript.SNAPSHOT_FULL))
	var sequence := int(snapshot.get("sequence", 0))
	if not _should_apply_snapshot(snapshot_kind, sequence):
		return

	_update_snapshot_sequence(snapshot_kind, sequence)
	_merge_building_lookup(snapshot.get("buildings", []))
	WorldSnapshotSerializerScript.apply_snapshot_to_world(world, root_node, snapshot, _building_lookup_by_id)
	local_player_citizen_id = str(snapshot.get("local_player_citizen_id", local_player_citizen_id))
	if snapshot.has("citizens"):
		var remove_missing := bool(snapshot.get("citizens_complete", true))
		_apply_citizen_snapshots(snapshot.get("citizens", []), _building_lookup_by_id, remove_missing)
	_sync_local_player_camera()

func get_local_player_citizen() -> Citizen:
	if local_player_citizen_id.is_empty():
		return null
	if not _citizen_by_id.has(local_player_citizen_id):
		return null
	var citizen := _citizen_by_id[local_player_citizen_id] as Citizen
	return citizen if citizen != null and is_instance_valid(citizen) else null

func get_debug_status() -> Dictionary:
	return {
		"received_full_snapshot": _received_full_snapshot,
		"building_lookup_count": _building_lookup_by_id.size(),
		"last_full_sequence": _last_full_sequence,
		"last_actor_state_sequence": _last_actor_state_sequence,
		"last_world_state_sequence": _last_world_state_sequence,
		"interpolation_target_count": _replica_interpolation_by_id.size(),
		"interpolation_max_error": _get_replica_interpolation_max_error(),
		"prediction_frame_count": _local_prediction_frame_count,
		"prediction_distance": _local_prediction_distance,
		"prediction_error": _get_local_player_prediction_error(),
		"prediction_last_direction": _vec3_to_array(_last_prediction_direction),
	}

func send_command(command: Dictionary) -> void:
	if str(command.get("type", "")) == "player_input":
		_apply_player_input_command_prediction(command)
	_send_command_raw(command)

func _send_command_raw(command: Dictionary) -> void:
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

func _should_apply_snapshot(snapshot_kind: String, sequence: int) -> bool:
	match snapshot_kind:
		WorldSnapshotSerializerScript.SNAPSHOT_FULL:
			return sequence <= 0 or sequence >= _last_full_sequence
		WorldSnapshotSerializerScript.SNAPSHOT_WORLD_STATE:
			return _received_full_snapshot and (sequence <= 0 or sequence > _last_world_state_sequence)
		_:
			return _received_full_snapshot and (sequence <= 0 or sequence > _last_actor_state_sequence)

func _update_snapshot_sequence(snapshot_kind: String, sequence: int) -> void:
	match snapshot_kind:
		WorldSnapshotSerializerScript.SNAPSHOT_FULL:
			_received_full_snapshot = true
			_last_full_sequence = maxi(_last_full_sequence, sequence)
		WorldSnapshotSerializerScript.SNAPSHOT_WORLD_STATE:
			_last_world_state_sequence = maxi(_last_world_state_sequence, sequence)
		_:
			_last_actor_state_sequence = maxi(_last_actor_state_sequence, sequence)

func _merge_building_lookup(entries: Variant) -> void:
	if entries is not Array:
		return
	var lookup := WorldSnapshotSerializerScript.build_building_lookup(root_node, entries as Array)
	for entity_id in lookup.keys():
		_building_lookup_by_id[entity_id] = lookup[entity_id]

func _apply_citizen_snapshots(entries: Variant, building_lookup: Dictionary, remove_missing: bool) -> void:
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
		_apply_citizen_snapshot(entity_id, citizen, data, building_lookup)
	if remove_missing:
		_remove_missing_citizens(seen)

func _apply_citizen_snapshot(entity_id: String, citizen: Citizen, data: Dictionary, building_lookup: Dictionary) -> void:
	var had_interpolation_state := _replica_interpolation_by_id.has(entity_id)
	var render_position := citizen.global_position
	var render_rotation_y := citizen.rotation.y
	var target_position := WorldSnapshotSerializerScript.vector_from_snapshot(data.get("position", []), render_position)
	var target_rotation_y := float(data.get("rotation_y", render_rotation_y))
	if citizen.has_method("apply_network_snapshot"):
		citizen.apply_network_snapshot(data, building_lookup)
	else:
		citizen.global_position = target_position
		citizen.rotation.y = target_rotation_y
	var should_snap := not had_interpolation_state or render_position.distance_to(target_position) > REPLICA_SNAP_DISTANCE_METERS
	if should_snap:
		citizen.global_position = target_position
		citizen.rotation.y = target_rotation_y
	else:
		citizen.global_position = render_position
		citizen.rotation.y = render_rotation_y
	_replica_interpolation_by_id[entity_id] = {
		"target_position": target_position,
		"target_rotation_y": target_rotation_y,
	}

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
		_replica_interpolation_by_id.erase(entity_id)
		if citizen != null and is_instance_valid(citizen):
			citizen.queue_free()

func _update_replica_interpolation(delta: float) -> void:
	if delta <= 0.0 or _replica_interpolation_by_id.is_empty():
		return
	var position_alpha := clampf(delta * REPLICA_INTERPOLATION_SPEED, 0.0, 1.0)
	var rotation_alpha := clampf(delta * REPLICA_ROTATION_INTERPOLATION_SPEED, 0.0, 1.0)
	for entity_id in _replica_interpolation_by_id.keys():
		if not _citizen_by_id.has(entity_id):
			continue
		var citizen := _citizen_by_id[entity_id] as Citizen
		if citizen == null or not is_instance_valid(citizen):
			continue
		var state := _replica_interpolation_by_id[entity_id] as Dictionary
		var target_position: Vector3 = state.get("target_position", citizen.global_position)
		var target_rotation_y := float(state.get("target_rotation_y", citizen.rotation.y))
		var distance := citizen.global_position.distance_to(target_position)
		if distance > REPLICA_SNAP_DISTANCE_METERS or distance <= REPLICA_TARGET_EPSILON_METERS:
			citizen.global_position = target_position
		else:
			citizen.global_position = citizen.global_position.lerp(target_position, position_alpha)
		citizen.rotation.y = lerp_angle(citizen.rotation.y, target_rotation_y, rotation_alpha)

func _get_replica_interpolation_max_error() -> float:
	var max_error := 0.0
	for entity_id in _replica_interpolation_by_id.keys():
		if not _citizen_by_id.has(entity_id):
			continue
		var citizen := _citizen_by_id[entity_id] as Citizen
		if citizen == null or not is_instance_valid(citizen):
			continue
		var state := _replica_interpolation_by_id[entity_id] as Dictionary
		var target_position: Vector3 = state.get("target_position", citizen.global_position)
		max_error = maxf(max_error, citizen.global_position.distance_to(target_position))
	return max_error

func _apply_local_player_prediction(delta: float, direction: Vector3) -> void:
	if delta <= 0.0 or direction.length_squared() <= 0.0001:
		_last_prediction_direction = Vector3.ZERO
		return
	var citizen := get_local_player_citizen()
	if citizen == null:
		return
	direction.y = 0.0
	if direction.length_squared() > 1.0:
		direction = direction.normalized()
	var displacement := direction * _get_prediction_speed(citizen) * delta
	if displacement.length_squared() <= 0.000001:
		return
	citizen.global_position += displacement
	citizen.look_at(citizen.global_position + direction, Vector3.UP)
	_local_prediction_frame_count += 1
	_local_prediction_distance += displacement.length()
	_last_prediction_direction = direction

func _apply_player_input_command_prediction(command: Dictionary) -> void:
	if local_player_citizen_id.is_empty():
		return
	var direction := WorldSnapshotSerializerScript.vector_from_snapshot(command.get("direction", []), Vector3.ZERO)
	_apply_local_player_prediction(INPUT_SEND_INTERVAL_SEC, direction)

func _get_prediction_speed(citizen: Citizen) -> float:
	var speed := LOCAL_PLAYER_DEFAULT_PREDICTION_SPEED
	var raw_speed: Variant = citizen.get("move_speed")
	if raw_speed is float or raw_speed is int:
		speed = maxf(float(raw_speed), 0.0)
	var raw_multiplier: Variant = citizen.get("keyboard_control_speed_multiplier")
	if raw_multiplier is float or raw_multiplier is int:
		speed *= maxf(float(raw_multiplier), 0.0)
	return speed

func _get_local_player_prediction_error() -> float:
	if local_player_citizen_id.is_empty() or not _replica_interpolation_by_id.has(local_player_citizen_id):
		return 0.0
	var citizen := get_local_player_citizen()
	if citizen == null:
		return 0.0
	var state := _replica_interpolation_by_id[local_player_citizen_id] as Dictionary
	var target_position: Vector3 = state.get("target_position", citizen.global_position)
	return citizen.global_position.distance_to(target_position)

func _reset_local_prediction_debug() -> void:
	_local_prediction_frame_count = 0
	_local_prediction_distance = 0.0
	_last_prediction_direction = Vector3.ZERO

func _safe_node_name(value: String) -> String:
	var result := value
	for ch in [":", "/", "\\", " ", "."]:
		result = result.replace(ch, "_")
	return result

func _sync_local_player_camera() -> void:
	if local_player_citizen_id.is_empty() or _camera_follow_target_id == local_player_citizen_id:
		return
	var citizen := get_local_player_citizen()
	if citizen == null or root_node == null:
		return
	var viewport := root_node.get_viewport()
	var camera := viewport.get_camera_3d() if viewport != null else null
	if camera != null and camera.has_method("set_follow_target"):
		camera.call("set_follow_target", citizen)
		_camera_follow_target_id = local_player_citizen_id

func _get_player_input_direction() -> Vector3:
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

func _vec3_to_array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func _on_connected_to_server() -> void:
	if session_node != null and session_node.has_method("_client_transport_connected"):
		session_node.call("_client_transport_connected")

func _on_connection_failed() -> void:
	if world != null and world.has_method("set_simulation_authority_enabled"):
		world.set_simulation_authority_enabled(false)
	if session_node != null and session_node.has_method("_client_connection_failed"):
		session_node.call("_client_connection_failed")

func _on_server_disconnected() -> void:
	local_player_citizen_id = ""
	_camera_follow_target_id = ""
	_last_sent_input_direction = Vector3.ZERO
	_building_lookup_by_id.clear()
	_replica_interpolation_by_id.clear()
	_received_full_snapshot = false
	_last_full_sequence = 0
	_last_actor_state_sequence = 0
	_last_world_state_sequence = 0
	_reset_local_prediction_debug()
	if world != null and world.has_method("set_simulation_authority_enabled"):
		world.set_simulation_authority_enabled(false)
	if session_node != null and session_node.has_method("_client_server_disconnected"):
		session_node.call("_client_server_disconnected")
