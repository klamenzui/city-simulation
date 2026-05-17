extends RefCounted
class_name WorldSnapshotSerializer

const NetworkEntityRegistryScript = preload("res://Simulation/Multiplayer/shared/NetworkEntityRegistry.gd")
const CITIZEN_SCENE_PATH := "res://Entities/Citizens/CitizenNew.tscn"
const PROTOCOL_VERSION := 1
const SNAPSHOT_FULL := "full"
const SNAPSHOT_ACTOR_STATE := "actor_state"
const SNAPSHOT_WORLD_STATE := "world_state"

static func build_snapshot(world: World, root: Node, sequence: int, registry) -> Dictionary:
	if world == null or root == null:
		return {}
	if registry != null:
		registry.ensure_world_entities(world, root)

	return {
		"protocol": PROTOCOL_VERSION,
		"snapshot_kind": SNAPSHOT_FULL,
		"sequence": sequence,
		"citizens_complete": true,
		"time": _build_time_snapshot(world),
		"world": _build_world_snapshot(world),
		"buildings": _build_building_snapshots(world, root, true),
		"citizens": _build_citizen_snapshots(world, true),
	}

static func build_actor_state_snapshot(world: World, root: Node, sequence: int, registry) -> Dictionary:
	if world == null or root == null:
		return {}
	if registry != null:
		registry.ensure_world_entities(world, root)

	return {
		"protocol": PROTOCOL_VERSION,
		"snapshot_kind": SNAPSHOT_ACTOR_STATE,
		"sequence": sequence,
		"citizens_complete": true,
		"time": _build_time_snapshot(world),
		"world": _build_world_snapshot(world),
		"citizens": _build_citizen_snapshots(world, false),
	}

static func build_world_state_snapshot(world: World, root: Node, sequence: int, registry) -> Dictionary:
	if world == null or root == null:
		return {}
	if registry != null:
		registry.ensure_world_entities(world, root)

	return {
		"protocol": PROTOCOL_VERSION,
		"snapshot_kind": SNAPSHOT_WORLD_STATE,
		"sequence": sequence,
		"time": _build_time_snapshot(world),
		"world": _build_world_snapshot(world),
		"buildings": _build_building_snapshots(world, root, false),
	}

static func _build_time_snapshot(world: World) -> Dictionary:
	return {
		"day": world.time.day if world.time != null else 1,
		"minutes_total": world.time.minutes_total if world.time != null else 0,
		"hour": world.time.get_hour() if world.time != null else 0,
		"minute": world.time.get_minute() if world.time != null else 0,
	}

static func _build_world_snapshot(world: World) -> Dictionary:
	return {
		"paused": world.is_paused,
		"speed_multiplier": world.speed_multiplier,
		"tick": world.get_simulation_tick_counter(),
		"city_balance": world.city_account.balance if world.city_account != null else 0,
	}

static func _build_building_snapshots(world: World, root: Node, include_static: bool) -> Array:
	var snapshots: Array = []
	for building in world.buildings:
		if building == null or not is_instance_valid(building):
			continue
		var entity_id := NetworkEntityRegistryScript.get_entity_id(building)
		if entity_id.is_empty():
			continue
		var data := {
			"id": entity_id,
			"position": _vec3_to_array(building.global_position),
			"balance": building.account.balance if building.account != null else 0,
			"condition": building.condition,
			"state": building.get_financial_state_key() if building.has_method("get_financial_state_key") else "",
			"forced_closed_reason": building.forced_closed_reason,
			"workers": building.workers.size(),
			"visitors": building.visitors.size(),
			"capacity": building.capacity,
		}
		if include_static:
			data["path"] = _node_path(root, building)
			data["name"] = building.building_name
			data["display_name"] = building.get_display_name() if building.has_method("get_display_name") else building.building_name
			data["type"] = int(building.building_type)
			data["type_name"] = building.get_building_type_name() if building.has_method("get_building_type_name") else ""
		snapshots.append(data)
	return snapshots

static func _build_citizen_snapshots(world: World, include_static: bool) -> Array:
	var snapshots: Array = []
	for citizen in world.citizens:
		if citizen == null or not is_instance_valid(citizen):
			continue
		var entity_id := NetworkEntityRegistryScript.get_entity_id(citizen)
		if entity_id.is_empty():
			continue
		var action_label := ""
		if citizen.current_action != null:
			action_label = str(citizen.current_action.label)
		elif citizen.has_method("get_server_interaction_label"):
			action_label = str(citizen.get_server_interaction_label())
		var needs := citizen.needs
		var job_workplace := citizen.job.workplace if citizen.job != null else null
		var manual_control := citizen.is_manual_control_enabled() if citizen.has_method("is_manual_control_enabled") else false
		if citizen.has_method("is_network_manual_controlled"):
			manual_control = manual_control or citizen.is_network_manual_controlled()
		var data := {
			"id": entity_id,
			"position": _vec3_to_array(citizen.global_position),
			"rotation_y": citizen.rotation.y,
			"visible": citizen.visible,
			"wallet": citizen.wallet.balance if citizen.wallet != null else 0,
			"hunger": needs.hunger if needs != null else 0.0,
			"energy": needs.energy if needs != null else 0.0,
			"fun": needs.fun if needs != null else 0.0,
			"health": needs.health if needs != null else 0.0,
			"home_id": NetworkEntityRegistryScript.get_entity_id(citizen.home),
			"current_location_id": NetworkEntityRegistryScript.get_entity_id(citizen.current_location),
			"workplace_id": NetworkEntityRegistryScript.get_entity_id(job_workplace),
			"action": action_label,
			"travelling": citizen.is_travelling() if citizen.has_method("is_travelling") else false,
			"manual_control": manual_control,
			"lod": citizen.get_simulation_lod_tier() if citizen.has_method("get_simulation_lod_tier") else "focus",
			"inside": citizen.is_inside_building() if citizen.has_method("is_inside_building") else false,
		}
		if include_static:
			data["scene"] = CITIZEN_SCENE_PATH
			data["name"] = citizen.citizen_name
		snapshots.append(data)
	return snapshots

static func apply_snapshot_to_world(world: World, root: Node, snapshot: Dictionary, building_lookup: Dictionary = {}) -> void:
	if world == null or root == null or snapshot.is_empty():
		return
	_apply_time_snapshot(world, snapshot.get("time", {}))
	_apply_world_snapshot(world, snapshot.get("world", {}))
	_apply_building_snapshots(root, snapshot.get("buildings", []), building_lookup)

static func build_building_lookup(root: Node, building_snapshots: Array) -> Dictionary:
	var lookup: Dictionary = {}
	if root == null:
		return lookup
	for entry in building_snapshots:
		if entry is not Dictionary:
			continue
		var data := entry as Dictionary
		var entity_id := str(data.get("id", ""))
		var path := str(data.get("path", ""))
		if entity_id.is_empty() or path.is_empty():
			continue
		var node := root.get_node_or_null(path)
		if node is Building:
			lookup[entity_id] = node
	return lookup

static func vector_from_snapshot(value: Variant, fallback: Vector3 = Vector3.ZERO) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and (value as Array).size() >= 3:
		var arr := value as Array
		return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
	return fallback

static func _apply_time_snapshot(world: World, data: Variant) -> void:
	if data is not Dictionary or world.time == null:
		return
	var time_data := data as Dictionary
	var day := int(time_data.get("day", world.time.day))
	var minutes_total := int(time_data.get("minutes_total", world.time.minutes_total))
	if world.time.has_method("apply_network_state"):
		world.time.apply_network_state(day, minutes_total)
	else:
		world.time.day = day
		world.time.minutes_total = clampi(minutes_total, 0, 24 * 60 - 1)
		world.time.time_advanced.emit(world.time.day, world.time.get_hour(), world.time.get_minute())

static func _apply_world_snapshot(world: World, data: Variant) -> void:
	if data is not Dictionary:
		return
	var world_data := data as Dictionary
	var paused := bool(world_data.get("paused", world.is_paused))
	if world.is_paused != paused:
		world.is_paused = paused
		world.paused_changed.emit(world.is_paused)
	var speed := float(world_data.get("speed_multiplier", world.speed_multiplier))
	if not is_equal_approx(world.speed_multiplier, speed):
		world.speed_multiplier = maxf(speed, 0.1)
		world.speed_changed.emit(world.speed_multiplier)
	if world.city_account != null:
		world.city_account.balance = int(world_data.get("city_balance", world.city_account.balance))

static func _apply_building_snapshots(root: Node, entries: Variant, building_lookup: Dictionary) -> void:
	if entries is not Array:
		return
	for entry in entries:
		if entry is not Dictionary:
			continue
		var data := entry as Dictionary
		var entity_id := str(data.get("id", ""))
		var path := str(data.get("path", ""))
		var node := root.get_node_or_null(path) if not path.is_empty() else null
		if node == null and not entity_id.is_empty():
			node = building_lookup.get(entity_id, null) as Node
		if node is not Building:
			continue
		var building := node as Building
		if not entity_id.is_empty():
			NetworkEntityRegistryScript.set_entity_id(building, entity_id)
		if data.has("name"):
			building.building_name = str(data.get("name", building.building_name))
		if building.account != null:
			building.account.balance = int(data.get("balance", building.account.balance))
		building.condition = float(data.get("condition", building.condition))
		building.forced_closed_reason = str(data.get("forced_closed_reason", building.forced_closed_reason))

static func _node_path(root: Node, node: Node) -> String:
	if root == null or node == null:
		return ""
	if root == node:
		return "."
	if not root.is_ancestor_of(node):
		return str(node.get_path())
	return str(root.get_path_to(node))

static func _vec3_to_array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]
