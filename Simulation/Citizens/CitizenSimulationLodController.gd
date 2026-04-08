extends RefCounted
class_name CitizenSimulationLodController

const CONFIG_PATH := "res://config/citizen_simulation_lod.json"

var world: World = null
var city_camera: Camera3D = null
var selection_state_controller = null

var _config: Dictionary = {}
var _refresh_left: float = 0.0
var _runtime_sec: float = 0.0
var _last_tier_change_sec: Dictionary = {}
var _last_focus_sec: Dictionary = {}
var _high_social_density_ids: Dictionary = {}

func setup(world_ref: World, camera_ref: Camera3D, selection_state_controller_ref) -> void:
	world = world_ref
	city_camera = camera_ref
	selection_state_controller = selection_state_controller_ref
	_config = _load_config()
	_refresh_left = 0.0

func update(delta: float) -> void:
	if world == null or city_camera == null or selection_state_controller == null:
		return

	_runtime_sec += delta
	_refresh_left -= delta
	if _refresh_left > 0.0:
		return

	_refresh_left = _get_float("refresh.relevance_update_interval_sec", 0.5)
	_apply_lod_tiers()

func _apply_lod_tiers() -> void:
	var selected_citizen: Citizen = selection_state_controller.get_selected_citizen()
	var controlled_citizen: Citizen = selection_state_controller.get_controlled_citizen()
	var player_avatar: Citizen = selection_state_controller.get_player_avatar() if selection_state_controller.has_method("get_player_avatar") else null
	var player_control_active: bool = selection_state_controller.is_player_control_active() if selection_state_controller.has_method("is_player_control_active") else false
	var focus_budget: int = _get_int("budgets.focus_citizens", 15)
	var active_budget: int = _get_int("budgets.active_citizens", 30)

	var forced_focus: Dictionary = {}
	var forced_active: Dictionary = {}
	if _get_bool("budgets.always_keep_selected_focus", true) and selected_citizen != null:
		forced_focus[selected_citizen.get_instance_id()] = true
	if _get_bool("budgets.always_keep_player_focus", true) and player_avatar != null:
		forced_focus[player_avatar.get_instance_id()] = true
	if controlled_citizen != null and player_control_active:
		forced_focus[controlled_citizen.get_instance_id()] = true

	var anchor_pos := _get_anchor_position(player_avatar, controlled_citizen, selected_citizen, player_control_active)
	var relevance_context := _build_relevance_context(
		anchor_pos,
		player_avatar,
		controlled_citizen,
		selected_citizen,
		player_control_active
	)
	_rebuild_social_density_lookup()
	var scored: Array = []
	for citizen in world.citizens:
		if citizen == null:
			continue
		if citizen.has_method("clear_expired_lod_commitments"):
			citizen.clear_expired_lod_commitments(world)
		if citizen.has_method("is_safe_home_rotation_candidate"):
			citizen.is_safe_home_rotation_candidate(world)
		scored.append({
			"citizen": citizen,
			"score": _score_citizen(citizen, relevance_context, selected_citizen, player_avatar)
		})
		if _should_force_active_dialog_participant(citizen, forced_focus):
			forced_active[citizen.get_instance_id()] = true

	scored.sort_custom(_sort_scored_desc)

	var desired_focus: Dictionary = forced_focus.duplicate()
	var focus_count := 0
	for entry in scored:
		var citizen: Citizen = entry["citizen"] as Citizen
		if citizen == null:
			continue
		var score := float(entry.get("score", 0.0))
		var citizen_id := citizen.get_instance_id()
		if desired_focus.has(citizen_id):
			continue
		if focus_count >= focus_budget:
			break
		if not _qualifies_for_focus(citizen, score):
			continue
		desired_focus[citizen_id] = true
		focus_count += 1

	var desired_active: Dictionary = forced_active.duplicate()
	var active_count := 0
	for entry in scored:
		var citizen: Citizen = entry["citizen"] as Citizen
		if citizen == null:
			continue
		var score := float(entry.get("score", 0.0))
		var citizen_id := citizen.get_instance_id()
		if desired_focus.has(citizen_id):
			continue
		if desired_active.has(citizen_id):
			continue
		if active_count >= active_budget:
			break
		if not _qualifies_for_active(citizen, score, anchor_pos):
			continue
		desired_active[citizen_id] = true
		active_count += 1

	for citizen in world.citizens:
		if citizen == null:
			continue
		var desired_tier := "coarse"
		var citizen_id := citizen.get_instance_id()
		if desired_focus.has(citizen_id):
			desired_tier = "focus"
		elif desired_active.has(citizen_id):
			desired_tier = "active"

		desired_tier = _apply_hold_rules(citizen, desired_tier)
		if desired_tier == "coarse" and not _can_demote_to_coarse(citizen, selected_citizen, player_avatar):
			desired_tier = "active"

		_apply_tier(citizen, desired_tier)

func _score_citizen(citizen: Citizen, relevance_context: Dictionary, selected_citizen: Citizen, player_avatar: Citizen) -> float:
	var score := 0.0
	var citizen_pos := citizen.global_position
	var anchor_pos: Vector3 = relevance_context.get("anchor_pos", citizen_pos)
	var distance := citizen_pos.distance_to(anchor_pos)
	var focus_radius := _get_float("visibility.focus_radius_m", 18.0)

	if citizen == selected_citizen:
		score += _get_float("relevance_weights.selected", 100.0)
	if citizen == player_avatar:
		score += _get_float("relevance_weights.player_dialog", 90.0)
	if citizen.has_method("has_active_lod_commitment") and citizen.has_active_lod_commitment(world, ["player_dialog", "player_interest"]):
		score += _get_float("relevance_weights.player_dialog", 90.0)
	if citizen.has_method("has_active_lod_commitment") and citizen.has_active_lod_commitment(world, ["npc_dialog_materialized"]):
		score += _get_float("relevance_weights.npc_conversation_near_player", 70.0)
	if distance <= focus_radius:
		score += _get_float("relevance_weights.very_near_player", 60.0)
	score += _distance_score(distance)
	if _is_in_camera_view(citizen_pos):
		score += _get_float("relevance_weights.in_camera_view", 40.0)
	if _is_in_anchor_district(citizen_pos, relevance_context):
		score += _get_float("relevance_weights.same_district_as_player", 18.0)
	if _is_near_predicted_route(citizen, relevance_context):
		score += _get_float("relevance_weights.near_player_predicted_route", 20.0)
	if _is_near_camera_hotspot(citizen_pos, relevance_context):
		score += _get_float("relevance_weights.near_camera_hotspot", 14.0)
	if citizen.has_method("has_active_lod_commitment") and citizen.has_active_lod_commitment(world, _get_lock_types()):
		score += _get_float("relevance_weights.important_event", 25.0)
	if citizen.has_method("is_travelling") and citizen.is_travelling():
		score += _get_float("relevance_weights.soon_visible_route", 15.0)
	if _has_high_social_density(citizen):
		score += _get_float("relevance_weights.high_social_density_area", 12.0)
	if _was_inactive_for_long_time(citizen):
		score += _get_float("relevance_weights.not_active_for_long_time", 12.0)
	if _was_recently_promoted(citizen):
		score += _get_float("relevance_weights.recently_promoted_penalty", -20.0)

	return score

func _distance_score(distance: float) -> float:
	var bands: Variant = _get_value("visibility.distance_bands_m", [])
	if bands is Array:
		for band in bands:
			if band is not Dictionary:
				continue
			var max_distance := float(band.get("max_distance", -1.0))
			if max_distance >= 0.0 and distance <= max_distance:
				return float(band.get("bonus", 0.0))
	return distance * _get_float("relevance_weights.distance_penalty_per_meter", -1.0)

func _qualifies_for_focus(citizen: Citizen, score: float) -> bool:
	if citizen == null:
		return false
	var current_tier := _get_current_lod_tier(citizen)
	if current_tier == "focus":
		return score >= _get_float("hysteresis.demote_below_score", 50.0)
	return score >= _get_float("hysteresis.promote_above_score", 70.0)

func _qualifies_for_active(citizen: Citizen, score: float, anchor_pos: Vector3) -> bool:
	if citizen == null:
		return false
	var current_tier := _get_current_lod_tier(citizen)
	var active_radius := _get_float("visibility.active_radius_m", 42.0)
	var within_active_radius := active_radius <= 0.0 or citizen.global_position.distance_to(anchor_pos) <= active_radius
	if current_tier == "focus" or current_tier == "active":
		return score >= _get_float("hysteresis.demote_below_score", 50.0)
	if within_active_radius:
		return true
	return score >= _get_float("hysteresis.promote_above_score", 70.0)

func _can_demote_to_coarse(citizen: Citizen, selected_citizen: Citizen, player_avatar: Citizen) -> bool:
	if citizen == null:
		return false
	if citizen == selected_citizen or citizen == player_avatar:
		return false
	if citizen.has_method("has_active_lod_commitment") and citizen.has_active_lod_commitment(world, _get_lock_types()):
		return false
	if not citizen.has_method("is_safe_home_rotation_candidate"):
		return false
	if not citizen.is_safe_home_rotation_candidate(world):
		return false

	var require_next_day := _get_bool("rotation.home_arrival_swap_requires_next_day", true)
	if not require_next_day:
		return true
	if not citizen.has_method("get_home_rotation_candidate_day"):
		return false
	return int(citizen.get_home_rotation_candidate_day()) >= 0 and int(citizen.get_home_rotation_candidate_day()) < world.world_day()

func _apply_hold_rules(citizen: Citizen, desired_tier: String) -> String:
	if citizen == null or not citizen.has_method("get_simulation_lod_tier"):
		return desired_tier
	var current_tier := citizen.get_simulation_lod_tier()
	if current_tier == desired_tier:
		return desired_tier

	var citizen_id := citizen.get_instance_id()
	var last_change_sec := float(_last_tier_change_sec.get(citizen_id, -10000.0))
	var elapsed := _runtime_sec - last_change_sec
	if current_tier == "focus" and desired_tier != "focus":
		if elapsed < _get_float("hysteresis.minimum_focus_hold_sec", 12.0):
			return "focus"
	if current_tier == "active" and desired_tier == "coarse":
		if elapsed < _get_float("hysteresis.minimum_active_hold_sec", 8.0):
			return "active"
	return desired_tier

func _get_current_lod_tier(citizen: Citizen) -> String:
	if citizen == null or not citizen.has_method("get_simulation_lod_tier"):
		return ""
	return citizen.get_simulation_lod_tier()

func _apply_tier(citizen: Citizen, tier: String) -> void:
	if citizen == null or not citizen.has_method("set_simulation_lod_state"):
		return
	var current_tier := citizen.get_simulation_lod_tier() if citizen.has_method("get_simulation_lod_tier") else ""
	var tier_profile_variant: Variant = _get_value("tiers.%s" % tier, {})
	var tier_profile: Dictionary = tier_profile_variant as Dictionary if tier_profile_variant is Dictionary else {}
	if current_tier == tier:
		if citizen.has_method("apply_simulation_lod_runtime_profile"):
			citizen.apply_simulation_lod_runtime_profile(tier_profile, world)
		if tier == "focus":
			_last_focus_sec[citizen.get_instance_id()] = _runtime_sec
		return
	var rendered := _get_bool("tiers.%s.rendered" % tier, true)
	var physics_enabled := _get_bool("tiers.%s.physics" % tier, true)
	var tick_interval := _get_int("refresh.coarse_tick_minutes_step", 5) if tier == "coarse" else 1
	citizen.set_simulation_lod_state(tier, rendered, physics_enabled, tick_interval)
	if citizen.has_method("apply_simulation_lod_runtime_profile"):
		citizen.apply_simulation_lod_runtime_profile(tier_profile, world)

	var citizen_id := citizen.get_instance_id()
	if current_tier != tier:
		_last_tier_change_sec[citizen_id] = _runtime_sec
	if tier == "focus":
		_last_focus_sec[citizen_id] = _runtime_sec

func _build_relevance_context(
	anchor_pos: Vector3,
	player_avatar: Citizen,
	controlled_citizen: Citizen,
	selected_citizen: Citizen,
	player_control_active: bool
) -> Dictionary:
	var route_owner := _get_relevance_route_owner(player_avatar, controlled_citizen, selected_citizen, player_control_active)
	return {
		"anchor_pos": anchor_pos,
		"anchor_district_id": world.get_district_id_for_position(anchor_pos) if world != null and world.has_method("get_district_id_for_position") else "",
		"route_owner_id": route_owner.get_instance_id() if route_owner != null else 0,
		"route_points": _get_predicted_route_points(route_owner),
		"camera_hotspot": _get_camera_hotspot_position(),
		"has_camera_hotspot": city_camera != null
	}

func _get_relevance_route_owner(
	player_avatar: Citizen,
	controlled_citizen: Citizen,
	selected_citizen: Citizen,
	player_control_active: bool
) -> Citizen:
	if player_control_active and _can_supply_route_relevance(player_avatar):
		return player_avatar
	if _can_supply_route_relevance(controlled_citizen):
		return controlled_citizen
	if _can_supply_route_relevance(selected_citizen):
		return selected_citizen
	return null

func _can_supply_route_relevance(citizen: Citizen) -> bool:
	if citizen == null:
		return false
	if not citizen.has_method("is_travelling") or not citizen.is_travelling():
		return false
	return citizen.has_method("get_debug_travel_route_points")

func _get_predicted_route_points(citizen: Citizen) -> Array:
	var route_points: Array = []
	if citizen == null or not citizen.has_method("get_debug_travel_route_points"):
		return route_points
	route_points.append(citizen.global_position)
	var raw_route: Variant = citizen.get_debug_travel_route_points()
	if raw_route is PackedVector3Array:
		for point in raw_route:
			route_points.append(point)
	return route_points

func _get_anchor_position(
	player_avatar: Citizen,
	controlled_citizen: Citizen,
	selected_citizen: Citizen,
	player_control_active: bool
) -> Vector3:
	if player_control_active and player_avatar != null:
		return player_avatar.global_position
	if controlled_citizen != null:
		return controlled_citizen.global_position
	if selected_citizen != null:
		return selected_citizen.global_position
	var fallback := city_camera.global_position
	fallback.y = world.get_ground_fallback_y()
	return fallback

func _is_in_camera_view(world_pos: Vector3) -> bool:
	if city_camera == null:
		return false
	if not _get_bool("visibility.screen_visibility_bonus_enabled", true):
		return false
	var to_target := world_pos - city_camera.global_position
	if to_target.length_squared() <= 0.0001:
		return true
	var camera_forward := -city_camera.global_transform.basis.z.normalized()
	return camera_forward.dot(to_target.normalized()) > 0.2

func _is_in_anchor_district(citizen_pos: Vector3, relevance_context: Dictionary) -> bool:
	if world == null or not world.has_method("get_district_id_for_position"):
		return false
	var anchor_district_id := str(relevance_context.get("anchor_district_id", ""))
	if anchor_district_id.is_empty():
		return false
	return world.get_district_id_for_position(citizen_pos) == anchor_district_id

func _is_near_predicted_route(citizen: Citizen, relevance_context: Dictionary) -> bool:
	if citizen == null:
		return false
	var route_owner_id := int(relevance_context.get("route_owner_id", 0))
	if route_owner_id == 0 or route_owner_id == citizen.get_instance_id():
		return false
	var route_points: Variant = relevance_context.get("route_points", [])
	if route_points is not Array or (route_points as Array).size() < 2:
		return false
	var route_radius := _get_float("visibility.predicted_route_radius_m", 5.0)
	return _distance_to_polyline_flat(citizen.global_position, route_points as Array) <= route_radius

func _is_near_camera_hotspot(citizen_pos: Vector3, relevance_context: Dictionary) -> bool:
	if not bool(relevance_context.get("has_camera_hotspot", false)):
		return false
	var hotspot_pos: Vector3 = relevance_context.get("camera_hotspot", citizen_pos)
	var hotspot_radius := _get_float("visibility.camera_hotspot_radius_m", 8.0)
	return _distance_flat(citizen_pos, hotspot_pos) <= hotspot_radius

func _get_camera_hotspot_position() -> Vector3:
	if city_camera == null:
		return Vector3.ZERO
	var hotspot_distance := _get_float("visibility.camera_hotspot_distance_m", 18.0)
	var camera_forward := -city_camera.global_transform.basis.z.normalized()
	var hotspot := city_camera.global_position + camera_forward * hotspot_distance
	hotspot.y = world.get_ground_fallback_y() if world != null else hotspot.y
	return hotspot

func _distance_to_polyline_flat(point: Vector3, polyline: Array) -> float:
	if polyline.size() < 2:
		return INF
	var best_distance := INF
	for index in range(polyline.size() - 1):
		var point_a: Variant = polyline[index]
		var point_b: Variant = polyline[index + 1]
		if point_a is not Vector3 or point_b is not Vector3:
			continue
		best_distance = minf(best_distance, _distance_to_segment_flat(point, point_a as Vector3, point_b as Vector3))
	return best_distance

func _distance_to_segment_flat(point: Vector3, start: Vector3, end: Vector3) -> float:
	var segment := Vector2(end.x - start.x, end.z - start.z)
	var segment_length_sq := segment.length_squared()
	if segment_length_sq <= 0.0001:
		return _distance_flat(point, start)
	var point_delta := Vector2(point.x - start.x, point.z - start.z)
	var t := clampf(point_delta.dot(segment) / segment_length_sq, 0.0, 1.0)
	var closest := Vector3(
		lerpf(start.x, end.x, t),
		point.y,
		lerpf(start.z, end.z, t)
	)
	return _distance_flat(point, closest)

func _distance_flat(point_a: Vector3, point_b: Vector3) -> float:
	var delta := point_a - point_b
	delta.y = 0.0
	return delta.length()

func _has_high_social_density(citizen: Citizen) -> bool:
	if citizen == null:
		return false
	return bool(_high_social_density_ids.get(citizen.get_instance_id(), false))

func _was_inactive_for_long_time(citizen: Citizen) -> bool:
	if citizen == null:
		return false
	var citizen_id := citizen.get_instance_id()
	if not _last_focus_sec.has(citizen_id):
		return true
	return _runtime_sec - float(_last_focus_sec[citizen_id]) >= 45.0

func _was_recently_promoted(citizen: Citizen) -> bool:
	if citizen == null:
		return false
	var citizen_id := citizen.get_instance_id()
	if not _last_tier_change_sec.has(citizen_id):
		return false
	return _runtime_sec - float(_last_tier_change_sec[citizen_id]) < 20.0

func _rebuild_social_density_lookup() -> void:
	_high_social_density_ids.clear()
	if world == null:
		return

	var radius := 6.0
	var buckets: Dictionary = {}
	for citizen in world.citizens:
		if citizen == null:
			continue
		var key := _get_density_bucket_key(citizen.global_position, radius)
		var bucket: Array = buckets.get(key, [])
		bucket.append(citizen)
		buckets[key] = bucket

	for citizen in world.citizens:
		if citizen == null:
			continue
		var citizen_id := citizen.get_instance_id()
		var origin_key := _get_density_bucket_key(citizen.global_position, radius)
		var neighbor_count := 0
		for bucket_x in range(origin_key.x - 1, origin_key.x + 2):
			for bucket_y in range(origin_key.y - 1, origin_key.y + 2):
				var bucket: Variant = buckets.get(Vector2i(bucket_x, bucket_y), [])
				if bucket is not Array:
					continue
				for other in bucket as Array:
					if other == null or other == citizen:
						continue
					if citizen.global_position.distance_to((other as Citizen).global_position) > radius:
						continue
					neighbor_count += 1
					if neighbor_count >= 2:
						_high_social_density_ids[citizen_id] = true
						break
				if bool(_high_social_density_ids.get(citizen_id, false)):
					break
			if bool(_high_social_density_ids.get(citizen_id, false)):
				break
		if not _high_social_density_ids.has(citizen_id):
			_high_social_density_ids[citizen_id] = false

func _get_density_bucket_key(world_pos: Vector3, bucket_size: float) -> Vector2i:
	var safe_bucket_size := maxf(bucket_size, 0.001)
	return Vector2i(
		int(floor(world_pos.x / safe_bucket_size)),
		int(floor(world_pos.z / safe_bucket_size))
	)

func _should_force_active_dialog_participant(citizen: Citizen, forced_focus: Dictionary) -> bool:
	if citizen == null:
		return false
	if not _get_bool("budgets.always_keep_dialog_participants_active", true):
		return false
	var citizen_id := citizen.get_instance_id()
	if forced_focus.has(citizen_id):
		return false
	if not citizen.has_method("has_active_lod_commitment"):
		return false
	return citizen.has_active_lod_commitment(world, ["player_dialog", "npc_dialog_materialized", "meeting"])

func _get_lock_types() -> Array:
	var lock_types: Array = []
	var raw_types: Variant = _get_value("commitments.lock_types", [])
	if raw_types is not Array:
		return lock_types
	for raw_type in raw_types:
		lock_types.append(str(raw_type))
	return lock_types

func _sort_scored_desc(a, b) -> bool:
	return float(a.get("score", 0.0)) > float(b.get("score", 0.0))

func _load_config() -> Dictionary:
	var defaults := {
		"budgets": {
			"focus_citizens": 15,
			"active_citizens": 30,
			"always_keep_selected_focus": true,
			"always_keep_player_focus": true
		},
		"refresh": {
			"relevance_update_interval_sec": 0.5,
			"coarse_tick_minutes_step": 5
		},
		"visibility": {
			"focus_radius_m": 18.0,
			"active_radius_m": 42.0,
			"predicted_route_radius_m": 5.0,
			"camera_hotspot_distance_m": 18.0,
			"camera_hotspot_radius_m": 8.0,
			"screen_visibility_bonus_enabled": true,
			"distance_bands_m": []
		},
		"hysteresis": {
			"minimum_focus_hold_sec": 12.0,
			"minimum_active_hold_sec": 8.0
		},
		"relevance_weights": {
			"selected": 100.0,
			"player_dialog": 90.0,
			"very_near_player": 60.0,
			"in_camera_view": 40.0,
			"important_event": 25.0,
			"soon_visible_route": 15.0,
			"high_social_density_area": 12.0,
			"not_active_for_long_time": 12.0,
			"recently_promoted_penalty": -20.0,
			"distance_penalty_per_meter": -1.0
		},
		"tiers": {
			"focus": {
				"rendered": true,
				"physics": true
			},
			"active": {
				"rendered": true,
				"physics": true
			},
			"coarse": {
				"rendered": false,
				"physics": false
			}
		},
		"rotation": {
			"home_arrival_swap_requires_next_day": true
		},
		"commitments": {
			"lock_types": []
		}
	}

	if not FileAccess.file_exists(CONFIG_PATH):
		return defaults
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		return defaults
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		_deep_merge(defaults, parsed as Dictionary)
	return defaults

func _deep_merge(base: Dictionary, override: Dictionary) -> void:
	for key in override.keys():
		var override_value: Variant = override[key]
		if base.has(key) and base[key] is Dictionary and override_value is Dictionary:
			_deep_merge(base[key], override_value)
		else:
			base[key] = override_value

func _get_value(path: String, default_value = null):
	var current: Variant = _config
	for part in path.split("."):
		if part.is_empty():
			continue
		if current is Dictionary and current.has(part):
			current = current[part]
			continue
		return default_value
	return current

func _get_bool(path: String, default_value: bool) -> bool:
	return bool(_get_value(path, default_value))

func _get_int(path: String, default_value: int) -> int:
	return int(_get_value(path, default_value))

func _get_float(path: String, default_value: float) -> float:
	return float(_get_value(path, default_value))
