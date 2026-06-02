extends RefCounted
class_name SaveGameService

## Disk-backed save / load for the singleplayer session.
##
## Builds on WorldSnapshotSerializer (the same snapshot used by multiplayer)
## but stores it to user://saves/slot_N.json and applies it back without
## flipping citizens into network-replica mode. Slots are 1..MAX_SLOTS; slot 0
## is reserved for the quicksave keyed to F5 / F9. Apply assumes the world has
## already been bootstrapped (buildings exist, citizens spawned with stable
## entity ids).

const WorldSnapshotSerializerScript = preload("res://Simulation/Multiplayer/shared/WorldSnapshotSerializer.gd")
const NetworkEntityRegistryScript = preload("res://Simulation/Multiplayer/shared/NetworkEntityRegistry.gd")
const CitizenFactoryScript = preload("res://Simulation/Factories/CitizenFactory.gd")

const SAVE_DIR := "user://saves"
const SAVE_VERSION := 2
const MAX_SLOTS := 3
const QUICKSAVE_SLOT := 0
const _TEMP_SUFFIX := ".tmp"
const _BACKUP_SUFFIX := ".bak"

# --- Slot path helpers ------------------------------------------------------
static func slot_path(slot: int) -> String:
	if slot == QUICKSAVE_SLOT:
		return SAVE_DIR + "/quicksave.json"
	return SAVE_DIR + "/slot_%d.json" % slot

static func is_valid_slot(slot: int) -> bool:
	return slot == QUICKSAVE_SLOT or (slot >= 1 and slot <= MAX_SLOTS)

static func ensure_save_dir() -> Error:
	if DirAccess.dir_exists_absolute(SAVE_DIR):
		return OK
	return DirAccess.make_dir_recursive_absolute(SAVE_DIR)

# --- Public API -------------------------------------------------------------

## Saves the current world (plus the controlled player) into the given slot.
## Returns OK on success, otherwise an Error code; on parse-side issues we
## still bubble up FAILED so callers can surface a toast.
static func save_to_slot(slot: int, world: World, root: Node, player: Node3D, registry = null) -> Error:
	if not is_valid_slot(slot):
		return ERR_INVALID_PARAMETER
	if world == null or root == null:
		return ERR_INVALID_PARAMETER
	var dir_err := ensure_save_dir()
	if dir_err != OK:
		return dir_err

	# Assign deterministic ids before serializing so later loads can match.
	var working_registry = registry
	if working_registry == null:
		working_registry = NetworkEntityRegistryScript.new()
	working_registry.ensure_world_entities(world, root)

	var snapshot := WorldSnapshotSerializerScript.build_snapshot(world, root, 0, working_registry)
	if snapshot.is_empty():
		return ERR_CANT_CREATE

	var player_entity_id := ""
	if player != null and is_instance_valid(player):
		player_entity_id = NetworkEntityRegistryScript.get_entity_id(player)

	var payload := {
		"version": SAVE_VERSION,
		"saved_at_unix": int(Time.get_unix_time_from_system()),
		"saved_at_label": Time.get_datetime_string_from_system(false, true),
		"day": int(snapshot.get("time", {}).get("day", 1)),
		"hour": int(snapshot.get("time", {}).get("hour", 0)),
		"minute": int(snapshot.get("time", {}).get("minute", 0)),
		"city_balance": int(snapshot.get("world", {}).get("city_balance", 0)),
		"citizen_count": (snapshot.get("citizens", []) as Array).size(),
		"player_entity_id": player_entity_id,
		"snapshot": snapshot,
	}

	return _write_payload_atomic(slot_path(slot), JSON.stringify(payload))

## Reads the raw payload (incl. metadata + snapshot). Returns {} if missing
## or malformed. Callers can use this for both apply and slot previews.
static func read_payload(slot: int) -> Dictionary:
	if not is_valid_slot(slot):
		return {}
	var path := slot_path(slot)
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	if text.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if parsed is not Dictionary:
		return {}
	var payload := parsed as Dictionary
	if not _is_payload_compatible(payload):
		return {}
	return payload

## Returns a list of length MAX_SLOTS describing each user-visible slot.
## Each entry is {slot, exists, day, label, citizen_count, city_balance}.
static func list_slots() -> Array:
	var out: Array = []
	for slot in range(1, MAX_SLOTS + 1):
		out.append(_describe_slot(slot))
	return out

static func describe_quicksave() -> Dictionary:
	return _describe_slot(QUICKSAVE_SLOT)

static func _describe_slot(slot: int) -> Dictionary:
	var path := slot_path(slot)
	if not FileAccess.file_exists(path):
		return {"slot": slot, "exists": false}
	var payload := read_payload(slot)
	if payload.is_empty():
		return {"slot": slot, "exists": false}
	return {
		"slot": slot,
		"exists": true,
		"day": int(payload.get("day", 1)),
		"hour": int(payload.get("hour", 0)),
		"minute": int(payload.get("minute", 0)),
		"label": str(payload.get("saved_at_label", "")),
		"saved_at_unix": int(payload.get("saved_at_unix", 0)),
		"citizen_count": int(payload.get("citizen_count", 0)),
		"city_balance": int(payload.get("city_balance", 0)),
	}

## Apply a previously read payload onto the live world. The world must already
## be bootstrapped: buildings exist, citizens spawned. Citizens are matched
## first by entity_id, then by ordinal index as fallback (handles the common
## case where the snapshot was taken on the same initial citizen count).
##
## Returns OK on success, ERR_INVALID_DATA if the payload is unusable.
static func apply_payload(payload: Dictionary, world: World, root: Node, player: Node3D, registry = null) -> Error:
	if payload.is_empty() or world == null or root == null or not _is_payload_compatible(payload):
		return ERR_INVALID_DATA
	var snapshot_variant: Variant = payload.get("snapshot", null)
	if snapshot_variant is not Dictionary:
		return ERR_INVALID_DATA
	var snapshot := snapshot_variant as Dictionary

	var count_err := _sync_live_citizen_count(world, root, _snapshot_citizen_count(snapshot))
	if count_err != OK:
		return count_err

	# Stable ids on the live world so building/citizen matching works.
	var working_registry = registry
	if working_registry == null:
		working_registry = NetworkEntityRegistryScript.new()
	working_registry.ensure_world_entities(world, root)

	var building_lookup := WorldSnapshotSerializerScript.build_building_lookup(
		root, snapshot.get("buildings", []))
	var citizen_plan := _build_citizen_apply_plan(world, snapshot.get("citizens", []), building_lookup)
	var plan_err := int(citizen_plan.get("error", OK))
	if plan_err != OK:
		return plan_err
	WorldSnapshotSerializerScript.apply_snapshot_to_world(world, root, snapshot, building_lookup)

	var apply_err := _apply_citizens_from_plan(world, citizen_plan.get("matches", []), building_lookup)
	if apply_err != OK:
		return apply_err
	_restore_building_ownership(world, snapshot.get("buildings", []), building_lookup)

	var player_entity_id := str(payload.get("player_entity_id", ""))
	if player is not Citizen:
		_apply_player_state(player, player_entity_id, snapshot.get("citizens", []), building_lookup)
	return OK

# --- Internals --------------------------------------------------------------

static func _write_payload_atomic(path: String, text: String) -> Error:
	var temp_path := path + _TEMP_SUFFIX
	var backup_path := path + _BACKUP_SUFFIX
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	file.flush()
	file.close()
	if FileAccess.file_exists(backup_path):
		var backup_remove_err := DirAccess.remove_absolute(backup_path)
		if backup_remove_err != OK:
			DirAccess.remove_absolute(temp_path)
			return backup_remove_err
	if FileAccess.file_exists(path):
		var backup_err := DirAccess.rename_absolute(path, backup_path)
		if backup_err != OK:
			DirAccess.remove_absolute(temp_path)
			return backup_err
	var rename_err := DirAccess.rename_absolute(temp_path, path)
	if rename_err != OK:
		DirAccess.remove_absolute(temp_path)
		if FileAccess.file_exists(backup_path) and not FileAccess.file_exists(path):
			DirAccess.rename_absolute(backup_path, path)
		return rename_err
	if FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(backup_path)
	return OK

static func _is_payload_compatible(payload: Dictionary) -> bool:
	var version := int(payload.get("version", -1))
	if version < 1 or version > SAVE_VERSION:
		return false
	var snapshot_variant: Variant = payload.get("snapshot", null)
	if snapshot_variant is not Dictionary:
		return false
	var snapshot := snapshot_variant as Dictionary
	if int(snapshot.get("protocol", -1)) != WorldSnapshotSerializerScript.PROTOCOL_VERSION:
		return false
	if snapshot.get("citizens", null) is not Array:
		return false
	return true

static func _snapshot_citizen_count(snapshot: Dictionary) -> int:
	var entries: Variant = snapshot.get("citizens", [])
	if entries is not Array:
		return -1
	return (entries as Array).size()

static func _sync_live_citizen_count(world: World, root: Node, target_count: int) -> Error:
	if world == null or root == null or target_count < 0:
		return ERR_INVALID_DATA
	var ordered := _ordered_live_citizens(world)
	while ordered.size() > target_count:
		var citizen := ordered.pop_back() as Citizen
		if citizen == null or not is_instance_valid(citizen):
			continue
		world.unregister_citizen(citizen)
		citizen.queue_free()
	var missing := target_count - ordered.size()
	if missing <= 0:
		return OK
	var spawned: Array[Citizen] = CitizenFactoryScript.spawn_citizens(root, world, missing)
	return OK if spawned.size() == missing else ERR_CANT_CREATE

static func _build_citizen_apply_plan(world: World, entries: Variant, building_lookup: Dictionary) -> Dictionary:
	if entries is not Array:
		return {"error": ERR_INVALID_DATA, "matches": []}
	var entry_array := entries as Array
	var ordered_citizens := _ordered_live_citizens(world)
	if ordered_citizens.size() != entry_array.size():
		return {"error": ERR_INVALID_DATA, "matches": []}

	var by_id: Dictionary = {}
	for citizen in world.citizens:
		if citizen == null or not is_instance_valid(citizen):
			continue
		var id := NetworkEntityRegistryScript.get_entity_id(citizen)
		if not id.is_empty():
			by_id[id] = citizen

	var matches: Array = []
	var unmatched_indices: Array[int] = []
	var used_citizens: Dictionary = {}
	var used_entity_ids: Dictionary = {}
	for index in range(entry_array.size()):
		var entry = entry_array[index]
		if entry is not Dictionary:
			return {"error": ERR_INVALID_DATA, "matches": []}
		var data := entry as Dictionary
		var entity_id := str(data.get("id", ""))
		if entity_id.is_empty() or used_entity_ids.has(entity_id):
			return {"error": ERR_INVALID_DATA, "matches": []}
		used_entity_ids[entity_id] = true
		if not _validate_citizen_building_refs(data, building_lookup):
			return {"error": ERR_INVALID_DATA, "matches": []}
		var citizen: Citizen = by_id.get(entity_id, null) as Citizen
		matches.append({"citizen": citizen, "data": data})
		if citizen == null:
			unmatched_indices.append(index)
			continue
		if not is_instance_valid(citizen) or used_citizens.has(citizen.get_instance_id()):
			return {"error": ERR_INVALID_DATA, "matches": []}
		used_citizens[citizen.get_instance_id()] = true
	var fallback_cursor := 0
	for index in unmatched_indices:
		var fallback := _next_unused_citizen(ordered_citizens, used_citizens, fallback_cursor)
		fallback_cursor = int(fallback.get("next_index", fallback_cursor))
		var citizen := fallback.get("citizen", null) as Citizen
		if citizen == null:
			return {"error": ERR_INVALID_DATA, "matches": []}
		used_citizens[citizen.get_instance_id()] = true
		var match_data := matches[index] as Dictionary
		match_data["citizen"] = citizen
		matches[index] = match_data
	return {"error": OK, "matches": matches}

static func _next_unused_citizen(ordered_citizens: Array, used_citizens: Dictionary, start_index: int) -> Dictionary:
	var index := start_index
	while index < ordered_citizens.size():
		var candidate := ordered_citizens[index] as Citizen
		index += 1
		if candidate == null or not is_instance_valid(candidate):
			continue
		if used_citizens.has(candidate.get_instance_id()):
			continue
		return {"citizen": candidate, "next_index": index}
	return {"citizen": null, "next_index": index}

static func _ordered_live_citizens(world: World) -> Array:
	var ordered_citizens: Array = []
	if world == null:
		return ordered_citizens
	for c in world.citizens:
		if c != null and is_instance_valid(c):
			ordered_citizens.append(c)
	return ordered_citizens

static func _validate_citizen_building_refs(data: Dictionary, building_lookup: Dictionary) -> bool:
	var home_id := str(data.get("home_id", ""))
	if not home_id.is_empty() and building_lookup.get(home_id, null) is not ResidentialBuilding:
		return false
	var location_id := str(data.get("current_location_id", ""))
	if not location_id.is_empty() and building_lookup.get(location_id, null) is not Building:
		return false
	var workplace_id := str(data.get("workplace_id", ""))
	if not workplace_id.is_empty() and building_lookup.get(workplace_id, null) is not Building:
		return false
	return true

static func _apply_citizens_from_plan(world: World, matches: Variant, building_lookup: Dictionary) -> Error:
	if matches is not Array:
		return ERR_INVALID_DATA
	var match_array := matches as Array
	_clear_runtime_relationships(world)
	for match_entry in match_array:
		if match_entry is not Dictionary:
			return ERR_INVALID_DATA
		var match := match_entry as Dictionary
		var citizen := match.get("citizen", null) as Citizen
		var data := match.get("data", {}) as Dictionary
		if citizen == null or not is_instance_valid(citizen):
			return ERR_INVALID_DATA
		var entity_id := str(data.get("id", ""))
		if not entity_id.is_empty():
			NetworkEntityRegistryScript.set_entity_id(citizen, entity_id)
		_apply_citizen_state(citizen, data, building_lookup)
	return _rebuild_runtime_relationships(world, match_array)

static func _clear_runtime_relationships(world: World) -> void:
	if world == null:
		return
	for job in world.jobs.duplicate():
		world.unregister_job(job as Job)
	for building in world.buildings:
		if building == null or not is_instance_valid(building):
			continue
		building.workers.clear()
		building.visitors.clear()
		if building is ResidentialBuilding:
			(building as ResidentialBuilding).tenants.clear()
	for citizen in world.citizens:
		if citizen == null or not is_instance_valid(citizen):
			continue
		citizen.job = null
		citizen.home = null
		citizen.current_location = null
		citizen.current_action = null
		citizen.work_minutes_today = 0
		citizen.velocity = Vector3.ZERO

static func _rebuild_runtime_relationships(world: World, matches: Array) -> Error:
	for match_entry in matches:
		var match := match_entry as Dictionary
		var citizen := match.get("citizen", null) as Citizen
		var data := match.get("data", {}) as Dictionary
		if citizen == null or not is_instance_valid(citizen):
			return ERR_INVALID_DATA
		if citizen.home != null and bool(data.get("home_tenant", true)):
			if not citizen.home.add_tenant(citizen):
				return ERR_INVALID_DATA
		if citizen.job != null and citizen.job.workplace != null:
			if world != null:
				world.register_job(citizen.job)
			if bool(data.get("employed", false)) and not citizen.job.workplace.try_hire(citizen, false):
				return ERR_INVALID_DATA
		if citizen.current_location != null and bool(data.get("visitor", false)):
			if not citizen.current_location.try_add_visitor(citizen):
				return ERR_INVALID_DATA
	return OK

static func _apply_citizen_state(citizen: Citizen, data: Dictionary, building_lookup: Dictionary) -> void:
	citizen.global_position = WorldSnapshotSerializerScript.vector_from_snapshot(
		data.get("position", []), citizen.global_position)
	citizen.rotation.y = float(data.get("rotation_y", citizen.rotation.y))
	if data.has("visible"):
		citizen.visible = bool(data.get("visible", citizen.visible))
	if citizen.wallet != null and data.has("wallet"):
		citizen.wallet.balance = int(data.get("wallet", citizen.wallet.balance))
	if citizen.needs != null:
		var needs := citizen.needs
		needs.hunger = float(data.get("hunger", needs.hunger))
		needs.energy = float(data.get("energy", needs.energy))
		needs.fun = float(data.get("fun", needs.fun))
		needs.social = float(data.get("social", needs.social))
		needs.health = float(data.get("health", needs.health))
	if data.has("home_food_stock"):
		citizen.home_food_stock = int(data.get("home_food_stock", citizen.home_food_stock))
	if data.get("carried_inventory", null) is Dictionary:
		citizen.apply_carried_inventory_snapshot(data.get("carried_inventory", {}) as Dictionary)
	if data.has("clothing_items"):
		citizen.clothing_items = int(data.get("clothing_items", citizen.clothing_items))
	if data.has("education_level"):
		citizen.education_level = int(data.get("education_level", citizen.education_level))
	if data.has("personal_speed_multiplier"):
		citizen.personal_speed_multiplier = float(data.get("personal_speed_multiplier", citizen.personal_speed_multiplier))
	if data.has("job_tenure_days"):
		citizen.job_tenure_days = int(data.get("job_tenure_days", citizen.job_tenure_days))
	if data.has("job_absence_days"):
		citizen.job_absence_days = int(data.get("job_absence_days", citizen.job_absence_days))
	if data.has("experience_wage_bonus"):
		citizen.experience_wage_bonus = float(data.get("experience_wage_bonus", citizen.experience_wage_bonus))
	if data.has("home_id"):
		var home_id := str(data.get("home_id", ""))
		citizen.home = building_lookup.get(home_id, null) as ResidentialBuilding if not home_id.is_empty() else null
	if data.has("current_location_id"):
		var loc_id := str(data.get("current_location_id", ""))
		citizen.current_location = building_lookup.get(loc_id, null) as Building if not loc_id.is_empty() else null
	if data.has("workplace_id"):
		var workplace_id := str(data.get("workplace_id", ""))
		var workplace := building_lookup.get(workplace_id, null) as Building if not workplace_id.is_empty() else null
		if workplace == null:
			citizen.job = null
		else:
			var restored_job := Job.new()
			restored_job.workplace = workplace
			restored_job.preferred_workplace = workplace
			restored_job.title = str(data.get("job_title", restored_job.title))
			restored_job.wage_per_hour = int(data.get("job_wage_per_hour", restored_job.wage_per_hour))
			restored_job.shift_hours = int(data.get("job_shift_hours", restored_job.shift_hours))
			restored_job.required_education_level = int(data.get("job_required_education_level", restored_job.required_education_level))
			restored_job.workplace_service_type = str(data.get("job_workplace_service_type", restored_job.workplace_service_type))
			var allowed_types: Variant = data.get("job_allowed_building_types", restored_job.allowed_building_types)
			if allowed_types is Array:
				var converted_types: Array[int] = []
				for allowed_type in allowed_types as Array:
					converted_types.append(int(allowed_type))
				restored_job.allowed_building_types = converted_types
			citizen.job = restored_job
	if data.has("work_minutes_today"):
		citizen.work_minutes_today = int(data.get("work_minutes_today", citizen.work_minutes_today))
	if citizen.has_method("_apply_personal_movement_speed"):
		citizen._apply_personal_movement_speed()

static func _apply_player_state(player: Node3D, player_entity_id: String, citizens_data: Variant, building_lookup: Dictionary) -> void:
	if player == null or not is_instance_valid(player):
		return
	if player_entity_id.is_empty() or citizens_data is not Array:
		return
	for entry in citizens_data as Array:
		if entry is not Dictionary:
			continue
		var data := entry as Dictionary
		if str(data.get("id", "")) != player_entity_id:
			continue
		if player is Citizen:
			_apply_citizen_state(player as Citizen, data, building_lookup)
		else:
			player.global_position = WorldSnapshotSerializerScript.vector_from_snapshot(
				data.get("position", []), player.global_position)
			player.rotation.y = float(data.get("rotation_y", player.rotation.y))
		return

static func _restore_building_ownership(world: World, entries: Variant, building_lookup: Dictionary) -> void:
	if world == null or entries is not Array:
		return
	var citizen_lookup := _build_citizen_lookup_by_entity_id(world)
	for entry in entries as Array:
		if entry is not Dictionary:
			continue
		var data := entry as Dictionary
		var entity_id := str(data.get("id", ""))
		var building := building_lookup.get(entity_id, null) as Building
		if building == null:
			continue
		var owner_id := str(data.get("owner_id", ""))
		building.citizen_owner = citizen_lookup.get(owner_id, null) as Citizen if not owner_id.is_empty() else null
		if data.has("owner_name"):
			building.owner_display_name = str(data.get("owner_name", building.owner_display_name))

static func _build_citizen_lookup_by_entity_id(world: World) -> Dictionary:
	var lookup: Dictionary = {}
	if world == null:
		return lookup
	for citizen in world.citizens:
		if citizen == null or not is_instance_valid(citizen):
			continue
		var entity_id := NetworkEntityRegistryScript.get_entity_id(citizen)
		if not entity_id.is_empty():
			lookup[entity_id] = citizen
	return lookup
