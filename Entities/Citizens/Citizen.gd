extends CharacterBody3D
class_name Citizen

const CitizenAgentScript = preload("res://Simulation/Citizens/CitizenAgent.gd")
const SimLogger = preload("res://Simulation/Logging/SimLogger.gd")
const BalanceConfig = preload("res://Simulation/Config/BalanceConfig.gd")

# Emittiert wenn der Spieler auf diesen Citizen klickt
signal clicked

@export var citizen_name: String = "Alex"
@export var home_path: NodePath
@export var restaurant_path: NodePath
@export var supermarket_path: NodePath
@export var shop_path: NodePath
@export var cinema_path: NodePath
@export var park_path: NodePath
@export var job: Job
@export var debug_panel: DebugPanel
@export var autonomous_simulation_enabled: bool = true

var home: ResidentialBuilding
var favorite_restaurant: Restaurant
var favorite_supermarket: Supermarket
var favorite_shop: Shop
var favorite_cinema: Cinema
var favorite_park: Building

var needs := Needs.new()
var wallet := Account.new()
var home_food_stock: int = 2
var education_level: int = 0

var current_location: Building = null
var current_action: Action = null
var simulation_lod_tier: String = "focus"
var _simulation_lod_tick_interval_minutes: int = 1
var _simulation_lod_tick_phase_seed: int = 0
var _lod_commitments: Array = []
var _lod_presence_hidden: bool = false
var _interior_presence_hidden: bool = false
var _home_rotation_candidate_day: int = -1
var _runtime_conversation_mode: String = ""
var _runtime_conversation_partner: String = ""
var _runtime_conversation_topic: String = ""
var _simulation_lod_path_mode: String = "default"
var _simulation_lod_decision_interval_sec: float = 0.0
var _lod_runtime_defaults_captured: bool = false
var _lod_default_repath_interval_sec: float = 0.6
var _lod_default_local_navigation_raycast_checks_enabled: bool = true

var _world_ref: World = null
var _agent = CitizenAgentScript.new()
var _last_job_requirement_notice_level: int = -1
var _last_job_requirement_notice_title: String = ""
var _last_workplace_full_notice_day: int = -1
var _debug_once_day: int = -1
var _debug_once_keys: Dictionary = {}

# --- Movement / Navigation ---
@export var move_speed_min: float = 1.6
@export var move_speed_max: float = 2.4
@export var move_acceleration: float = 5.5
@export var move_deceleration: float = 7.0
@export var turn_speed: float = 8.0
@export var waypoint_reach_distance: float = 0.35
@export var arrival_distance: float = 0.65
@export var final_arrival_distance: float = 0.18
@export var floor_snap_distance: float = 0.35
@export var ground_probe_up: float = 4.0
@export var ground_probe_down: float = 12.0
@export var max_ground_step_up: float = 0.85
@export var max_ground_probe_skips: int = 8
@export var repath_interval_sec: float = 0.6
@export var gravity_strength: float = 28.0
@export var max_fall_speed: float = 35.0
@export var ground_snap_rate: float = 18.0
@export var local_navigation_raycast_checks_enabled: bool = true
@export var cheap_path_follow_lod_enabled: bool = true
@export var cheap_path_follow_camera_distance: float = 16.0
@export var cheap_path_follow_ground_snap_interval_sec: float = 0.18
@export var cheap_path_follow_corner_blend_distance: float = 0.8
@export var cheap_path_follow_corner_blend_strength: float = 0.45
@export var obstacle_sensor_height: float = 0.9
@export var obstacle_probe_length: float = 0.95
@export var obstacle_side_probe_length: float = 0.9
@export var obstacle_side_angle_deg: float = 25.0
@export var obstacle_turn_weight: float = 1.1
@export var obstacle_side_bias: float = 0.35
@export var obstacle_stuck_timeout: float = 0.7
@export var obstacle_stuck_distance: float = 0.02
@export var obstacle_stuck_progress_distance: float = 0.012
@export var obstacle_stuck_hotspot_confirm_sec: float = 0.35
@export var obstacle_repath_timeout: float = 1.6
@export var obstacle_slide_hold_sec: float = 0.4
@export var obstacle_jump_stuck_timeout: float = 2.2
@export var obstacle_jump_velocity: float = 5.2
@export var obstacle_jump_cooldown_sec: float = 1.35
@export var obstacle_jump_floor_snap_suppress_sec: float = 0.28
@export var obstacle_jump_forward_hold_sec: float = 0.22
@export var obstacle_jump_forward_speed_multiplier: float = 1.2
@export var obstacle_clearance_probe_distance: float = 0.34
@export var obstacle_clearance_radius: float = 0.10
@export var obstacle_clearance_height: float = 0.78
@export var forward_avoidance_enabled: bool = true
@export var forward_avoidance_min_alignment: float = 0.08
@export var crosswalk_signal_stop_distance: float = 0.92
@export var crosswalk_signal_detection_radius: float = 2.35
@export var surface_probe_forward_distance: float = 0.42
@export var surface_probe_lateral_offset: float = 0.24
@export var surface_probe_up: float = 1.4
@export var surface_probe_down: float = 2.2
@export var surface_guard_turn_angle_deg: float = 55.0
@export var surface_guard_side_turn_angle_deg: float = 85.0
@export var surface_guard_blocked_waypoint_extra_distance: float = 0.18
@export var surface_guard_repath_timeout_sec: float = 0.85
@export var surface_guard_log_cooldown_sec: float = 1.5
@export var surface_guard_edge_route_exception_delay_sec: float = 0.35
@export var unreachable_target_retry_limit: int = 3
@export var unreachable_target_no_progress_minutes: int = 18
@export var unreachable_target_cooldown_minutes: int = 180
@export var crowded_waypoint_skip_distance: float = 1.0
@export var crowded_waypoint_neighbor_radius: float = 0.55
@export var crowded_waypoint_shared_target_radius: float = 0.45
@export var crowded_waypoint_neighbor_count: int = 2
@export var entrance_contact_height_tolerance: float = 0.35
@export var entrance_contact_distance: float = 1.05
@export var entrance_contact_alignment: float = 0.45

var _nav_agent: NavigationAgent3D = null
var _is_travelling: bool = false
var _travel_target: Vector3 = Vector3.ZERO
var _travel_target_building: Building = null
var _travel_route: PackedVector3Array = PackedVector3Array()
var _travel_route_index: int = -1
var _arrived_via_entrance_contact: bool = false
var _repath_time_left: float = 0.0
var _walk_speed: float = 2.0
var _current_speed: float = 0.0
var _vertical_speed: float = 0.0
var _ground_fallback_y: float = 0.0
var _debug_last_travel_route: PackedVector3Array = PackedVector3Array()
var _debug_last_travel_failed: bool = false
var _obstacle_sensor_pivot: Node3D = null
var _obstacle_ray_forward: RayCast3D = null
var _obstacle_ray_down: RayCast3D = null
var _obstacle_ray_left: RayCast3D = null
var _obstacle_ray_right: RayCast3D = null
var _body_collision_shape: CollisionShape3D = null
var _forward_avoidance_area: Area3D = null
var _forward_avoidance_shape: CollisionShape3D = null
var _click_area: Area3D = null
var _click_area_shape: CollisionShape3D = null
var _saved_collision_layer: int = 0
var _saved_collision_mask: int = 0
var _inside_building: Building = null
var _stuck_timer: float = 0.0
var _stuck_hotspot_label: String = ""
var _stuck_hotspot_time: float = 0.0
var _last_move_position: Vector3 = Vector3.ZERO
var _trace_last_decision_reason: String = "idle"
var _trace_last_desired_dir: Vector3 = Vector3.ZERO
var _trace_last_move_dir: Vector3 = Vector3.ZERO
var _trace_last_forward_hit: String = "clear"
var _trace_last_down_hit: String = "clear"
var _trace_last_left_hit: String = "clear"
var _trace_last_right_hit: String = "clear"
var _trace_last_surface_probe: String = "-"
var _stuck_slide_hold_dir: Vector3 = Vector3.ZERO
var _stuck_slide_hold_left: float = 0.0
var _surface_guard_log_cooldown_left: float = 0.0
var _surface_guard_stop_time: float = 0.0
var _stuck_jump_cooldown_left: float = 0.0
var _floor_snap_suppress_left: float = 0.0
var _stuck_jump_hold_dir: Vector3 = Vector3.ZERO
var _stuck_jump_hold_left: float = 0.0
var _temporarily_unreachable_targets: Dictionary = {}
var _cheap_path_follow_ground_snap_left: float = 0.0
var _selection_active: bool = false
# TODO: Keep local crowd-deadlock diagnosis separate from economy stabilization fixes.
var _debug_repath_count: int = 0
var _debug_stuck_slide_count: int = 0
var _debug_stuck_jump_count: int = 0
var _debug_last_blocking_area: String = "-"
var _rest_pose_active: bool = false
var _rest_pose_position: Vector3 = Vector3.ZERO
var _rest_pose_yaw: float = 0.0
# --- Variation / Personality ---
@export var schedule_offset_min: int = -25
@export var schedule_offset_max: int = 25
var schedule_offset: int = 0

@export var decision_cooldown_range_min: int = 5
@export var decision_cooldown_range_max: int = 20
var decision_cooldown_left: int = 0

@export var hunger_threshold_base: float = 60.0
@export var hunger_threshold_jitter: float = 12.0
var hunger_threshold: float = 60.0

@export var low_energy_threshold_base: float = 35.0
@export var low_energy_threshold_jitter: float = 10.0
var low_energy_threshold: float = 35.0

@export var work_motivation_base: float = 1.0
@export var work_motivation_jitter: float = 0.4
var work_motivation: float = 1.0

@export var park_interest_base: float = 0.35
@export var park_interest_jitter: float = 0.20
var park_interest: float = 0.35

@export var fun_target_base: float = 65.0
@export var fun_target_jitter: float = 15.0
var fun_target: float = 65.0
@export var manual_control_move_speed: float = 3.6
@export var manual_control_turn_speed: float = 10.0
@export var manual_control_jump_velocity: float = 5.6

# --- Work tracking ---
var work_minutes_today: int = 0
var _work_day_key: int = -1

# --- Selection highlight ---
var _mesh_instance: MeshInstance3D = null
var _original_material: Material = null
var _highlight_material: StandardMaterial3D = null
var _manual_control_enabled: bool = false
var _click_move_mode_enabled: bool = false
var _manual_jump_was_pressed: bool = false
var _manual_control_input_locked: bool = false

func _ready() -> void:
	_apply_balance_config()
	_capture_lod_runtime_defaults()
	wallet.owner_name = citizen_name
	wallet.balance = BalanceConfig.get_int("citizen.wallet_start_balance", wallet.balance)
	home_food_stock = BalanceConfig.get_int("citizen.home_food_stock_start", home_food_stock)
	education_level = BalanceConfig.get_int("citizen.education_level_start", education_level)

	schedule_offset = randi_range(schedule_offset_min, schedule_offset_max)
	hunger_threshold = hunger_threshold_base + randf_range(-hunger_threshold_jitter, hunger_threshold_jitter)
	low_energy_threshold = low_energy_threshold_base + randf_range(-low_energy_threshold_jitter, low_energy_threshold_jitter)
	work_motivation = work_motivation_base + randf_range(-work_motivation_jitter, work_motivation_jitter)
	park_interest = clamp(park_interest_base + randf_range(-park_interest_jitter, park_interest_jitter), 0.0, 0.9)
	_walk_speed = randf_range(move_speed_min, move_speed_max)

	decision_cooldown_left = randi_range(0, 10)
	_cheap_path_follow_ground_snap_left = randf() * maxf(cheap_path_follow_ground_snap_interval_sec, 0.01)

	_setup_clickable()
	_setup_forward_avoidance_sensor()
	_setup_highlight()
	_setup_obstacle_sensors()
	_body_collision_shape = get_node_or_null("CollisionShape3D") as CollisionShape3D
	# Entrance triggers are debug/contact helpers, not physical blockers for walking.
	collision_mask &= ~8
	_saved_collision_layer = collision_layer
	_saved_collision_mask = collision_mask
	floor_snap_length = floor_snap_distance
	_agent.setup(self)
	_last_move_position = global_position
	call_deferred("_auto_resolve_refs")

func _apply_balance_config() -> void:
	var threshold_settings := BalanceConfig.get_section("citizen.thresholds")
	hunger_threshold_base = float(threshold_settings.get("hunger_threshold_base", hunger_threshold_base))
	hunger_threshold_jitter = float(threshold_settings.get("hunger_threshold_jitter", hunger_threshold_jitter))
	low_energy_threshold_base = float(threshold_settings.get("low_energy_threshold_base", low_energy_threshold_base))
	low_energy_threshold_jitter = float(threshold_settings.get("low_energy_threshold_jitter", low_energy_threshold_jitter))
	work_motivation_base = float(threshold_settings.get("work_motivation_base", work_motivation_base))
	work_motivation_jitter = float(threshold_settings.get("work_motivation_jitter", work_motivation_jitter))
	park_interest_base = float(threshold_settings.get("park_interest_base", park_interest_base))
	park_interest_jitter = float(threshold_settings.get("park_interest_jitter", park_interest_jitter))
	fun_target_base = float(threshold_settings.get("fun_target_base", fun_target_base))
	fun_target_jitter = float(threshold_settings.get("fun_target_jitter", fun_target_jitter))

func _physics_process(delta: float) -> void:
	if _manual_control_enabled:
		_manual_control_physics(delta)
		return
	_agent.physics_step(self, delta, _world_ref)

func set_manual_control_enabled(enabled: bool, world: World = null) -> void:
	if _manual_control_enabled == enabled:
		return
	_manual_control_enabled = enabled
	if enabled:
		clear_rest_pose(true)
		if is_inside_building():
			exit_current_building(world)
		elif current_location != null:
			leave_current_location(world)
		stop_travel()
		release_reserved_benches(world)
		current_action = null
		decision_cooldown_left = 0
		_current_speed = 0.0
		_vertical_speed = 0.0
		velocity = Vector3.ZERO
		_manual_control_input_locked = false
		_manual_jump_was_pressed = false
		_update_trace_navigation_state("manual_control", Vector3.ZERO, Vector3.ZERO)
	else:
		stop_travel()
		decision_cooldown_left = 0
		_current_speed = 0.0
		_vertical_speed = 0.0
		velocity = Vector3.ZERO
		_manual_control_input_locked = false
		_manual_jump_was_pressed = false
		_update_trace_navigation_state("manual_control_exit", Vector3.ZERO, Vector3.ZERO)

func is_manual_control_enabled() -> bool:
	return _manual_control_enabled

func set_manual_control_input_locked(locked: bool) -> void:
	_manual_control_input_locked = locked
	if locked:
		_current_speed = 0.0
		velocity.x = 0.0
		velocity.z = 0.0
		_manual_jump_was_pressed = false

func is_manual_control_input_locked() -> bool:
	return _manual_control_input_locked

func set_click_move_mode_enabled(enabled: bool, world: World = null) -> void:
	if _click_move_mode_enabled == enabled:
		return
	_click_move_mode_enabled = enabled
	if enabled:
		clear_rest_pose(true)
		release_reserved_benches(world)
		current_action = null
		stop_travel()
		decision_cooldown_left = 0
		_current_speed = 0.0
		_vertical_speed = 0.0
		velocity = Vector3.ZERO
		_update_trace_navigation_state("click_move_mode", Vector3.ZERO, Vector3.ZERO)
	else:
		decision_cooldown_left = 0
		_update_trace_navigation_state("click_move_mode_exit", Vector3.ZERO, Vector3.ZERO)

func is_click_move_mode_enabled() -> bool:
	return _click_move_mode_enabled

func is_autonomous_simulation_enabled() -> bool:
	return autonomous_simulation_enabled

func get_simulation_lod_tier() -> String:
	return simulation_lod_tier

func set_simulation_lod_state(
	tier: String,
	rendered: bool,
	physics_enabled: bool,
	tick_interval_minutes: int = 1
) -> void:
	simulation_lod_tier = tier
	_simulation_lod_tick_interval_minutes = maxi(tick_interval_minutes, 1)
	_simulation_lod_tick_phase_seed = randi()
	_lod_presence_hidden = not rendered
	_apply_presence_hidden_state()

	var should_process_physics := physics_enabled or _manual_control_enabled or _click_move_mode_enabled
	set_physics_process(should_process_physics)
	if not should_process_physics:
		velocity = Vector3.ZERO
		_current_speed = 0.0
		_vertical_speed = 0.0
	if _world_ref != null and is_instance_valid(_world_ref) and _world_ref.has_method("notify_citizen_lod_changed"):
		_world_ref.notify_citizen_lod_changed(self)

func apply_simulation_lod_runtime_profile(profile: Dictionary, world: World = null) -> void:
	_capture_lod_runtime_defaults()
	var resolved_profile := profile.duplicate(true)
	var path_mode := "default"
	if bool(resolved_profile.get("full_navigation", false)):
		path_mode = "full"
	elif bool(resolved_profile.get("cheap_path_follow", false)) or not bool(resolved_profile.get("full_navigation", true)):
		path_mode = "cheap"
	_simulation_lod_path_mode = path_mode

	var local_avoidance_enabled := bool(resolved_profile.get("local_avoidance", _lod_default_local_navigation_raycast_checks_enabled))
	set_local_navigation_raycast_checks_enabled(local_avoidance_enabled)
	if _nav_agent != null:
		_nav_agent.avoidance_enabled = local_avoidance_enabled

	var repath_override := float(resolved_profile.get("path_refresh_interval_sec", _lod_default_repath_interval_sec))
	repath_interval_sec = maxf(repath_override, 0.05)
	_simulation_lod_decision_interval_sec = maxf(float(resolved_profile.get("decision_interval_sec", 0.0)), 0.0)
	if world != null:
		_world_ref = world

func get_simulation_lod_decision_cooldown_range_minutes(world: World) -> Vector2i:
	if _simulation_lod_decision_interval_sec <= 0.0 or world == null:
		return Vector2i(decision_cooldown_range_min, decision_cooldown_range_max)
	var default_range := Vector2i(decision_cooldown_range_min, decision_cooldown_range_max)
	# Keep decision throttling tied to the simulation cadence, not wall-clock fast-forward.
	# Otherwise higher speed multipliers would starve active/coarse citizens from replanning.
	var tick_wait_sec := maxf(world.tick_interval_sec, 0.001)
	var ticks_needed := maxi(ceili(_simulation_lod_decision_interval_sec / maxf(tick_wait_sec, 0.001)), 1)
	var base_minutes := ticks_needed * maxi(world.minutes_per_tick, 1)
	if base_minutes <= default_range.x:
		return default_range
	var jitter_minutes := maxi(world.minutes_per_tick, 1)
	return Vector2i(maxi(base_minutes - jitter_minutes, world.minutes_per_tick), max(base_minutes + jitter_minutes, default_range.x))

func _capture_lod_runtime_defaults() -> void:
	if _lod_runtime_defaults_captured:
		return
	_lod_runtime_defaults_captured = true
	_lod_default_repath_interval_sec = repath_interval_sec
	_lod_default_local_navigation_raycast_checks_enabled = local_navigation_raycast_checks_enabled

func should_run_simulation_lod_tick(world: World) -> bool:
	if world == null:
		return true
	if simulation_lod_tier != "coarse":
		return true
	if not world.has_method("is_citizen_due_for_simulation"):
		return true
	return world.is_citizen_due_for_simulation(self)

func get_simulation_lod_tick_interval_minutes() -> int:
	return maxi(_simulation_lod_tick_interval_minutes, 1)

func get_simulation_lod_tick_interval_ticks(world: World) -> int:
	if world == null:
		return 1
	return maxi(ceili(float(get_simulation_lod_tick_interval_minutes()) / float(maxi(world.minutes_per_tick, 1))), 1)

func get_simulation_lod_tick_slot(world: World) -> int:
	var interval_ticks := get_simulation_lod_tick_interval_ticks(world)
	if interval_ticks <= 1:
		return 0
	return posmod(_simulation_lod_tick_phase_seed, interval_ticks)

func add_lod_commitment(commitment_type: String, until_day: int, until_minute: int, priority: float = 1.0) -> void:
	_lod_commitments.append({
		"type": commitment_type,
		"until_day": until_day,
		"until_minute": until_minute,
		"priority": priority
	})

func upsert_lod_commitment(
	commitment_type: String,
	until_day: int,
	until_minute: int,
	priority: float = 1.0,
	metadata: Dictionary = {}
) -> void:
	for i in _lod_commitments.size():
		var commitment: Variant = _lod_commitments[i]
		if commitment is not Dictionary:
			continue
		if str(commitment.get("type", "")) != commitment_type:
			continue
		var merged := (commitment as Dictionary).duplicate(true)
		merged["until_day"] = until_day
		merged["until_minute"] = until_minute
		merged["priority"] = priority
		for key in metadata.keys():
			merged[key] = metadata[key]
		_lod_commitments[i] = merged
		return

	var entry := {
		"type": commitment_type,
		"until_day": until_day,
		"until_minute": until_minute,
		"priority": priority
	}
	for key in metadata.keys():
		entry[key] = metadata[key]
	_lod_commitments.append(entry)

func remove_lod_commitment(commitment_type: String) -> void:
	var remaining: Array = []
	for commitment in _lod_commitments:
		if commitment is Dictionary and str(commitment.get("type", "")) == commitment_type:
			continue
		remaining.append(commitment)
	_lod_commitments = remaining

func remove_lod_commitments(commitment_types: Array) -> void:
	if commitment_types.is_empty():
		return
	var remaining: Array = []
	for commitment in _lod_commitments:
		if commitment is Dictionary and commitment_types.has(str(commitment.get("type", ""))):
			continue
		remaining.append(commitment)
	_lod_commitments = remaining

func clear_expired_lod_commitments(world: World) -> void:
	if world == null:
		return
	var current_day := world.world_day()
	var current_minute := world.time.get_hour() * 60 + world.time.get_minute()
	var remaining: Array = []
	for commitment in _lod_commitments:
		if commitment is not Dictionary:
			continue
		var until_day := int(commitment.get("until_day", current_day))
		var until_minute := int(commitment.get("until_minute", current_minute))
		if until_day > current_day or (until_day == current_day and until_minute > current_minute):
			remaining.append(commitment)
	_lod_commitments = remaining

func has_active_lod_commitment(world: World, required_types: Array = []) -> bool:
	clear_expired_lod_commitments(world)
	if required_types.is_empty():
		return not _lod_commitments.is_empty()
	for commitment in _lod_commitments:
		if commitment is not Dictionary:
			continue
		if required_types.has(str(commitment.get("type", ""))):
			return true
	return false

func get_active_lod_commitments(world: World) -> Array:
	clear_expired_lod_commitments(world)
	return _lod_commitments.duplicate(true)

func set_runtime_conversation_state(mode: String, partner_name: String = "", topic: String = "") -> void:
	_runtime_conversation_mode = mode
	_runtime_conversation_partner = partner_name
	_runtime_conversation_topic = topic

func clear_runtime_conversation_state() -> void:
	_runtime_conversation_mode = ""
	_runtime_conversation_partner = ""
	_runtime_conversation_topic = ""

func get_runtime_conversation_label() -> String:
	if _runtime_conversation_mode == "":
		return "-"
	var parts: Array[String] = [ _runtime_conversation_mode ]
	if _runtime_conversation_partner != "":
		parts.append("with %s" % _runtime_conversation_partner)
	if _runtime_conversation_topic != "":
		parts.append("topic=%s" % _runtime_conversation_topic)
	return " ".join(parts)

func is_active_player_dialog_session() -> bool:
	return _runtime_conversation_mode == "interactive" and _runtime_conversation_partner == "Player" and _runtime_conversation_topic == "player_dialog"

func face_position_horizontal(target_position: Vector3) -> void:
	var facing_dir := target_position - global_position
	facing_dir.y = 0.0
	if facing_dir.length_squared() <= 0.0001:
		return
	rotation.y = _yaw_from_move_direction(facing_dir.normalized())

func get_home_rotation_candidate_day() -> int:
	return _home_rotation_candidate_day

func is_safe_home_rotation_candidate(world: World) -> bool:
	clear_expired_lod_commitments(world)
	var at_home_idle := home != null \
		and current_location == home \
		and not _is_travelling \
		and current_action == null \
		and not _manual_control_enabled \
		and not _click_move_mode_enabled
	if at_home_idle:
		if _home_rotation_candidate_day < 0 and world != null:
			_home_rotation_candidate_day = world.world_day()
	else:
		_home_rotation_candidate_day = -1
	return at_home_idle and not has_active_lod_commitment(world)

func is_travelling() -> bool:
	return _is_travelling

func _manual_control_physics(delta: float) -> void:
	var input_vec := Vector2.ZERO
	var controls_locked := _manual_control_input_locked
	if not controls_locked:
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			input_vec.x -= 1.0
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			input_vec.x += 1.0
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			input_vec.y += 1.0
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			input_vec.y -= 1.0

	var move_dir := Vector3.ZERO
	if input_vec.length_squared() > 0.0001:
		input_vec = input_vec.normalized()
		var camera := get_viewport().get_camera_3d()
		var forward := Vector3.FORWARD
		var right := Vector3.RIGHT
		if camera != null:
			forward = -camera.global_transform.basis.z
			right = camera.global_transform.basis.x
			forward.y = 0.0
			right.y = 0.0
			if forward.length_squared() > 0.0001:
				forward = forward.normalized()
			else:
				forward = Vector3.FORWARD
			if right.length_squared() > 0.0001:
				right = right.normalized()
			else:
				right = Vector3.RIGHT
		move_dir = (right * input_vec.x + forward * input_vec.y).normalized()
		_update_facing(move_dir, delta * (manual_control_turn_speed / maxf(turn_speed, 0.001)))
		_current_speed = move_toward(_current_speed, manual_control_move_speed, move_acceleration * delta)
	else:
		_current_speed = move_toward(_current_speed, 0.0, move_deceleration * delta)

	var jump_pressed := Input.is_key_pressed(KEY_SPACE) if not controls_locked else false
	if jump_pressed and not _manual_jump_was_pressed and is_on_floor():
		velocity.y = maxf(velocity.y, manual_control_jump_velocity)
		_floor_snap_suppress_left = maxf(_floor_snap_suppress_left, obstacle_jump_floor_snap_suppress_sec)
		floor_snap_length = 0.0
	_update_stuck_state(delta)
	_manual_jump_was_pressed = jump_pressed

	velocity.x = move_dir.x * _current_speed
	velocity.z = move_dir.z * _current_speed
	if is_on_floor():
		if velocity.y < 0.0:
			velocity.y = 0.0
	else:
		velocity.y = maxf(velocity.y - gravity_strength * delta, -max_fall_speed)
	move_and_slide()
	_recover_floor_contact()
	_last_move_position = global_position
	_update_trace_navigation_state("manual_control_locked" if controls_locked else "manual_control", move_dir, move_dir)

# Click detection via Area3D
func _setup_clickable() -> void:
	var area := get_node_or_null("ClickArea") as Area3D
	if area == null:
		area = Area3D.new()
		area.name = "ClickArea"
		add_child(area)
	area.input_ray_pickable = true

	var col := area.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col == null:
		col = CollisionShape3D.new()
		col.name = "CollisionShape3D"
		area.add_child(col)
	var body_col := get_node_or_null("CollisionShape3D") as CollisionShape3D
	var body_shape := body_col.shape as CapsuleShape3D if body_col != null else null
	var shape := col.shape as CapsuleShape3D
	if shape == null:
		shape = CapsuleShape3D.new()
		col.shape = shape
	if body_shape != null:
		shape.radius = body_shape.radius
		shape.height = body_shape.height
		col.transform = body_col.transform
	else:
		shape.radius = 0.45
		shape.height = 2.1
		col.position = Vector3(0, 1.05, 0)  # Mitte der Kapsel-Figur

	_click_area = area
	_click_area_shape = col

	if not area.input_event.is_connected(_on_area_input_event):
		area.input_event.connect(_on_area_input_event)


func _on_area_input_event(_camera: Camera3D, event: InputEvent,
		_position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if event is InputEventMouseButton \
		and event.button_index == MOUSE_BUTTON_LEFT \
		and event.pressed:
		clicked.emit()
		get_viewport().set_input_as_handled()

func _setup_forward_avoidance_sensor() -> void:
	var area := get_node_or_null("ForwardAvoidanceArea") as Area3D
	if area == null:
		area = get_node_or_null("Area3D") as Area3D

	_forward_avoidance_area = area
	_forward_avoidance_shape = null
	if area == null:
		return

	area.input_ray_pickable = false
	area.monitoring = true
	area.monitorable = false
	area.collision_layer = 0
	if area.collision_mask == 0:
		area.collision_mask = 9

	var shape_node := area.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node == null:
		shape_node = area.get_node_or_null("CollisionShape3D2") as CollisionShape3D
	if shape_node == null:
		shape_node = CollisionShape3D.new()
		shape_node.name = "CollisionShape3D"
		area.add_child(shape_node)

	if shape_node.shape == null:
		var fallback_shape := CylinderShape3D.new()
		fallback_shape.radius = maxf(obstacle_clearance_radius * 2.4, 0.22)
		fallback_shape.height = maxf(obstacle_clearance_height * 0.55, 0.32)
		shape_node.shape = fallback_shape
		shape_node.position = Vector3(0.0, obstacle_sensor_height * 0.3, -maxf(obstacle_probe_length * 0.55, 0.28))

	_forward_avoidance_shape = shape_node


# Highlight selection material
func _setup_highlight() -> void:
	_mesh_instance = get_node_or_null("MeshInstance3D") as MeshInstance3D
	if _mesh_instance == null:
		return
	_original_material = _mesh_instance.material_overlay

	_highlight_material = StandardMaterial3D.new()
	_highlight_material.albedo_color = Color(1.0, 0.85, 0.1)  # Gelb
	_highlight_material.emission_enabled = true
	_highlight_material.emission = Color(0.6, 0.4, 0.0)

func _setup_obstacle_sensors() -> void:
	_obstacle_sensor_pivot = get_node_or_null("ObstacleSensorPivot") as Node3D
	_obstacle_ray_forward = get_node_or_null("ObstacleSensorPivot/ObstacleRayCastForward") as RayCast3D
	_obstacle_ray_down = get_node_or_null("ObstacleSensorPivot/ObstacleRayCastDown") as RayCast3D
	_obstacle_ray_left = get_node_or_null("ObstacleSensorPivot/ObstacleRayCastLeft") as RayCast3D
	_obstacle_ray_right = get_node_or_null("ObstacleSensorPivot/ObstacleRayCastRight") as RayCast3D

	if _obstacle_sensor_pivot != null:
		# Preserve the scene-authored pivot height. Only fall back to the exported
		# value when the pivot has not been positioned in the scene yet.
		if _obstacle_sensor_pivot.position.is_zero_approx():
			_obstacle_sensor_pivot.position = Vector3(0.0, obstacle_sensor_height, 0.0)

	var side_angle := deg_to_rad(obstacle_side_angle_deg)
	var side_x := sin(side_angle) * obstacle_side_probe_length
	var side_z := -cos(side_angle) * obstacle_side_probe_length

	if _obstacle_ray_forward != null:
		_configure_obstacle_ray(_obstacle_ray_forward, Vector3(0.0, 0.0, -obstacle_probe_length), 9)
	if _obstacle_ray_down != null:
		# Preserve the scene-authored downwards tilt so we can probe curb-height
		# obstacles that the horizontal rays miss.
		_configure_obstacle_ray(_obstacle_ray_down, _obstacle_ray_down.target_position, 9, true)
	if _obstacle_ray_left != null:
		_configure_obstacle_ray(_obstacle_ray_left, Vector3(-side_x, 0.0, side_z), 9)
	if _obstacle_ray_right != null:
		_configure_obstacle_ray(_obstacle_ray_right, Vector3(side_x, 0.0, side_z), 9)
	_apply_local_navigation_raycast_state()

func _configure_obstacle_ray(
	ray: RayCast3D,
	target_position: Vector3,
	collision_mask_value: int,
	preserve_target: bool = false
) -> void:
	if ray == null:
		return
	if not preserve_target:
		ray.target_position = target_position
	ray.collision_mask = collision_mask_value
	ray.add_exception(self)

func set_local_navigation_raycast_checks_enabled(enabled: bool) -> void:
	local_navigation_raycast_checks_enabled = enabled
	_apply_local_navigation_raycast_state()

func _apply_local_navigation_raycast_state() -> void:
	if _obstacle_ray_forward != null:
		_obstacle_ray_forward.enabled = local_navigation_raycast_checks_enabled
	if _obstacle_ray_down != null:
		_obstacle_ray_down.enabled = local_navigation_raycast_checks_enabled
	if _obstacle_ray_left != null:
		_obstacle_ray_left.enabled = local_navigation_raycast_checks_enabled
	if _obstacle_ray_right != null:
		_obstacle_ray_right.enabled = local_navigation_raycast_checks_enabled
	if _forward_avoidance_area != null:
		_forward_avoidance_area.monitoring = local_navigation_raycast_checks_enabled and forward_avoidance_enabled
	if _forward_avoidance_shape != null:
		_forward_avoidance_shape.disabled = not (local_navigation_raycast_checks_enabled and forward_avoidance_enabled)

func _setup_navigation() -> void:
	_nav_agent = get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	if _nav_agent == null:
		_nav_agent = NavigationAgent3D.new()
		_nav_agent.name = "NavigationAgent3D"
		add_child(_nav_agent)

	_nav_agent.path_desired_distance = waypoint_reach_distance
	_nav_agent.target_desired_distance = arrival_distance
	_nav_agent.path_max_distance = 2.0
	_nav_agent.radius = 0.35
	_nav_agent.height = 1.8
	_nav_agent.avoidance_enabled = false

func _probe_ground_hit(pos: Vector3) -> Dictionary:
	if not is_inside_tree():
		return {}

	var from := pos + Vector3.UP * ground_probe_up
	var to := pos + Vector3.DOWN * ground_probe_down
	var exclude: Array[RID] = [get_rid()]
	var attempts := maxi(max_ground_probe_skips, 1)

	for _attempt in range(attempts):
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.collision_mask = 1
		query.collide_with_areas = false
		query.exclude = exclude

		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			return {}

		var collider: Variant = hit.get("collider", null)
		if _is_citizen_collider(collider):
			if not hit.has("rid"):
				return {}
			exclude.append(hit["rid"])
			continue

		var hit_pos: Vector3 = hit.get("position", pos)
		if hit_pos.y <= pos.y + max_ground_step_up:
			return hit

		if not hit.has("rid"):
			return {}
		exclude.append(hit["rid"])

	return {}

func _probe_surface_hit(pos: Vector3) -> Dictionary:
	if not is_inside_tree():
		return {}

	var from := pos + Vector3.UP * maxf(surface_probe_up, 0.2)
	var to := pos + Vector3.DOWN * maxf(surface_probe_down, 0.2)
	var exclude: Array[RID] = [get_rid()]
	var attempts := maxi(max_ground_probe_skips, 1)

	for _attempt in range(attempts):
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.collision_mask = 3
		query.collide_with_areas = false
		query.exclude = exclude

		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			return {}

		var collider: Variant = hit.get("collider", null)
		if _is_citizen_collider(collider):
			if not hit.has("rid"):
				return {}
			exclude.append(hit["rid"])
			continue
		if collider is Node and _is_entrance_trigger_node(collider as Node):
			if not hit.has("rid"):
				return {}
			exclude.append(hit["rid"])
			continue

		return hit

	return {}

func _classify_surface_hit(hit: Dictionary) -> String:
	if hit.is_empty():
		return "unknown"

	var collider: Variant = hit.get("collider", null)
	if collider is Node:
		return _classify_surface_node(collider as Node)
	return "unknown"

func _classify_surface_node(node: Node) -> String:
	var current := node
	while current != null:
		if current.is_in_group("road_group"):
			return "road"

		var current_path := ""
		if current.is_inside_tree():
			current_path = str(current.get_path()).to_lower()
		var current_name := current.name.to_lower()

		if current_path.contains("/road_straight_crossing/") \
				or current_name.contains("crosswalk") \
				or current_name.contains("crossing"):
			return "crosswalk"
		if current_path.contains("/only_transport/"):
			return "road"
		if current_path.contains("/only_people_nav/"):
			return "pedestrian"

		current = current.get_parent()

	return "unknown"

func _get_surface_probe_samples(move_dir: Vector3) -> Array[Dictionary]:
	var planar_dir := move_dir
	planar_dir.y = 0.0
	if planar_dir.length_squared() <= 0.0001:
		_trace_last_surface_probe = "idle"
		return []
	planar_dir = planar_dir.normalized()

	var forward_distance := maxf(surface_probe_forward_distance, 0.12)
	var center := global_position + planar_dir * forward_distance
	var lateral := Vector3(-planar_dir.z, 0.0, planar_dir.x)
	if lateral.length_squared() <= 0.0001:
		lateral = global_transform.basis.x
		lateral.y = 0.0
	if lateral.length_squared() > 0.0001:
		lateral = lateral.normalized()

	var sample_points := [
		center - lateral * surface_probe_lateral_offset,
		center,
		center + lateral * surface_probe_lateral_offset,
	]
	var sample_labels := ["L", "C", "R"]
	var samples: Array[Dictionary] = []
	var summary_parts: Array[String] = []

	for i in range(sample_points.size()):
		var point := sample_points[i] as Vector3
		var hit := _probe_surface_hit(point)
		var kind := _classify_surface_hit(hit)
		samples.append({
			"label": sample_labels[i],
			"kind": kind,
			"point": point,
			"hit": hit,
		})
		summary_parts.append("%s=%s" % [sample_labels[i], kind])

	_trace_last_surface_probe = " ".join(summary_parts)
	return samples

func _is_crosswalk_route_context() -> bool:
	if _world_ref == null:
		return false

	var current_kind := str(_world_ref.get_pedestrian_path_point_kind(global_position))
	if current_kind.begins_with("crosswalk"):
		return true

	if _travel_route.is_empty():
		return false

	var start_idx := maxi(_travel_route_index - 1, 0)
	var end_idx := mini(_travel_route_index + 1, _travel_route.size() - 1)
	for idx in range(start_idx, end_idx + 1):
		var kind := str(_world_ref.get_pedestrian_path_point_kind(_travel_route[idx]))
		if kind.begins_with("crosswalk"):
			return true

	var target_kind := str(_world_ref.get_pedestrian_path_point_kind(_travel_target))
	return target_kind.begins_with("crosswalk")

func _is_surface_edge_kind(kind: String) -> bool:
	return kind == "boundary" or kind == "corner" \
		or kind == "crosswalk_entry" or kind == "crosswalk_exit"

func _is_surface_edge_route_context() -> bool:
	if _world_ref == null:
		return false

	if _is_surface_edge_kind(str(_world_ref.get_pedestrian_path_point_kind(global_position))):
		return true
	if _travel_route.is_empty():
		return false

	var start_idx := maxi(_travel_route_index - 1, 0)
	var end_idx := mini(_travel_route_index + 1, _travel_route.size() - 1)
	for idx in range(start_idx, end_idx + 1):
		var kind := str(_world_ref.get_pedestrian_path_point_kind(_travel_route[idx]))
		if _is_surface_edge_kind(kind):
			return true

	var target_kind := str(_world_ref.get_pedestrian_path_point_kind(_travel_target))
	return _is_surface_edge_kind(target_kind)

func _is_move_surface_allowed(move_dir: Vector3, crosswalk_context: bool = false) -> bool:
	if crosswalk_context:
		return true

	var samples := _get_surface_probe_samples(move_dir)
	if samples.is_empty():
		return true

	var has_crosswalk := false
	var road_count := 0
	var pedestrian_count := 0
	var center_kind := str((samples[1] as Dictionary).get("kind", "unknown")) if samples.size() >= 2 else "unknown"
	for sample in samples:
		var kind := str((sample as Dictionary).get("kind", "unknown"))
		if kind == "crosswalk":
			has_crosswalk = true
		elif kind == "road":
			road_count += 1
		elif kind == "pedestrian":
			pedestrian_count += 1

	if has_crosswalk:
		return true
	if road_count == 0:
		return true
	# Accept curb-edge cases where the body center and most of the footprint are
	# already on pedestrian space, but one outer probe still clips the road edge.
	if center_kind == "pedestrian" and pedestrian_count >= 2 and road_count <= 1:
		return true
	if _surface_guard_stop_time >= maxf(surface_guard_edge_route_exception_delay_sec, 0.0) \
			and pedestrian_count >= 1 \
			and _is_surface_edge_route_context():
		_trace_last_surface_probe += " edge_route_exception"
		return true
	return false

func _rotate_planar_direction(dir: Vector3, angle_deg: float) -> Vector3:
	var planar := dir
	planar.y = 0.0
	if planar.length_squared() <= 0.0001:
		return Vector3.ZERO
	return planar.normalized().rotated(Vector3.UP, deg_to_rad(angle_deg)).normalized()

func _append_surface_candidate(out: Array[Vector3], candidate: Vector3) -> void:
	var planar := candidate
	planar.y = 0.0
	if planar.length_squared() <= 0.0001:
		return
	planar = planar.normalized()

	for existing in out:
		if (existing as Vector3).distance_to(planar) <= 0.01:
			return

	out.append(planar)

func _constrain_move_direction_to_pedestrian_surface(move_dir: Vector3, desired_dir: Vector3) -> Vector3:
	var planar_move := move_dir
	planar_move.y = 0.0
	if planar_move.length_squared() <= 0.0001:
		return Vector3.ZERO
	planar_move = planar_move.normalized()
	if not local_navigation_raycast_checks_enabled:
		return planar_move

	var crosswalk_context := _is_crosswalk_route_context()
	if crosswalk_context:
		_trace_last_surface_probe = "crosswalk_context"
		return planar_move

	if _is_move_surface_allowed(planar_move, crosswalk_context):
		return planar_move

	var candidates: Array[Vector3] = []
	var left_dir := _ray_move_direction(_obstacle_ray_left)
	var right_dir := _ray_move_direction(_obstacle_ray_right)
	_append_surface_candidate(candidates, desired_dir)
	_append_surface_candidate(candidates, _blend_move_direction(desired_dir, left_dir, obstacle_side_bias))
	_append_surface_candidate(candidates, _blend_move_direction(desired_dir, right_dir, obstacle_side_bias))
	_append_surface_candidate(candidates, left_dir)
	_append_surface_candidate(candidates, right_dir)
	_append_surface_candidate(candidates, _rotate_planar_direction(desired_dir, surface_guard_turn_angle_deg))
	_append_surface_candidate(candidates, _rotate_planar_direction(desired_dir, -surface_guard_turn_angle_deg))
	_append_surface_candidate(candidates, _rotate_planar_direction(desired_dir, surface_guard_side_turn_angle_deg))
	_append_surface_candidate(candidates, _rotate_planar_direction(desired_dir, -surface_guard_side_turn_angle_deg))

	var best_dir := Vector3.ZERO
	var best_score := INF
	for candidate in candidates:
		if not _is_move_surface_allowed(candidate, crosswalk_context):
			continue
		var score := _score_direction(candidate)
		if score < best_score:
			best_score = score
			best_dir = candidate

	if best_dir != Vector3.ZERO:
		_maybe_log_surface_guard("reroute", planar_move, best_dir)
		_update_trace_navigation_state("surface_guard_%s" % _trace_relative_label(best_dir), desired_dir, best_dir)
		return best_dir

	_maybe_log_surface_guard("stop", planar_move, Vector3.ZERO)
	_update_trace_navigation_state("surface_guard_stop", desired_dir, Vector3.ZERO)
	return Vector3.ZERO

func _is_eligible_for_cheap_lod() -> bool:
	if _manual_control_enabled:
		return false
	if _selection_active:
		return false
	if _simulation_lod_path_mode == "full":
		return false
	if _simulation_lod_path_mode == "cheap":
		return true
	if not cheap_path_follow_lod_enabled:
		return false
	if simulation_lod_tier == "active":
		return true
	if simulation_lod_tier == "coarse":
		return true
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return false
	var threshold := maxf(cheap_path_follow_camera_distance, 0.0)
	if threshold <= 0.0:
		return true
	var planar_camera_delta := global_position - camera.global_position
	planar_camera_delta.y = 0.0
	return planar_camera_delta.length_squared() >= threshold * threshold

func _is_using_cheap_path_follow() -> bool:
	return _is_travelling and _is_eligible_for_cheap_lod()

func _get_cheap_path_follow_move_target() -> Vector3:
	var move_target := _get_waypoint_move_target()
	if _travel_route_index < 0 or _travel_route_index >= _travel_route.size() - 1:
		return move_target

	var current_delta := _travel_target - global_position
	current_delta.y = 0.0
	var current_distance := current_delta.length()
	if current_distance >= maxf(cheap_path_follow_corner_blend_distance, 0.05):
		return move_target

	var next_point := _travel_route[_travel_route_index + 1]
	var blend_t := 1.0 - clampf(
		current_distance / maxf(cheap_path_follow_corner_blend_distance, 0.05),
		0.0,
		1.0
	)
	var blend_weight := clampf(blend_t * cheap_path_follow_corner_blend_strength, 0.0, 0.8)
	var blended_target := move_target.lerp(next_point, blend_weight)
	blended_target.y = lerpf(move_target.y, next_point.y, blend_weight)
	return blended_target

func _apply_cheap_path_follow_grounding(pos: Vector3, delta: float, force_snap: bool = false) -> Vector3:
	if force_snap:
		_cheap_path_follow_ground_snap_left = maxf(cheap_path_follow_ground_snap_interval_sec, 0.01)
		return _project_to_ground(pos)

	_cheap_path_follow_ground_snap_left = maxf(_cheap_path_follow_ground_snap_left - delta, 0.0)
	if _cheap_path_follow_ground_snap_left > 0.0:
		pos.y = global_position.y
		return pos

	_cheap_path_follow_ground_snap_left = maxf(cheap_path_follow_ground_snap_interval_sec, 0.01)
	return _project_to_ground(pos)

func _move_along_path_cheap(delta: float) -> void:
	if _repath_time_left > 0.0:
		_repath_time_left = maxf(_repath_time_left - delta, 0.0)

	if _arrived_via_entrance_contact:
		_current_speed = move_toward(_current_speed, 0.0, move_deceleration * delta)
		velocity = Vector3.ZERO
		return

	var to_target := _travel_target - global_position
	to_target.y = 0.0
	var distance_to_target := to_target.length()
	var is_last_waypoint: bool = _travel_route_index >= _travel_route.size() - 1
	var reach_distance: float = final_arrival_distance if is_last_waypoint else waypoint_reach_distance
	var is_building_arrival := is_last_waypoint \
		and _travel_target_building != null \
		and _should_use_entrance_contact_arrival()
	if is_last_waypoint and _travel_target_building != null:
		reach_distance = maxf(reach_distance, arrival_distance)

	if distance_to_target <= reach_distance:
		if _advance_travel_route():
			return
		if is_building_arrival \
				and distance_to_target <= final_arrival_distance \
				and absf(global_position.y - _travel_target.y) <= entrance_contact_height_tolerance:
			_arrived_via_entrance_contact = true
			_current_speed = 0.0
			velocity = Vector3.ZERO
			_update_trace_navigation_state("cheap_arrive_target_access", Vector3.ZERO, Vector3.ZERO)
			return
		if _travel_target_building != null and _travel_target_building.has_method("is_outdoor_destination") and _travel_target_building.is_outdoor_destination():
			global_position = _apply_cheap_path_follow_grounding(_travel_target, delta, true)
			stop_travel()
			_update_trace_navigation_state("cheap_arrive_target_path_end", Vector3.ZERO, Vector3.ZERO)
			return
		if _travel_target_building == null:
			global_position = _apply_cheap_path_follow_grounding(_travel_target, delta, true)
			stop_travel()
			_update_trace_navigation_state("cheap_arrive_target_path_end", Vector3.ZERO, Vector3.ZERO)
			return

	var move_target := _get_cheap_path_follow_move_target()
	var move_delta := move_target - global_position
	move_delta.y = 0.0
	var move_distance := move_delta.length()
	if move_distance <= 0.001:
		_current_speed = move_toward(_current_speed, 0.0, move_deceleration * delta)
		velocity = Vector3.ZERO
		_update_trace_navigation_state("cheap_arriving", Vector3.ZERO, Vector3.ZERO)
		return

	var desired_speed: float = _walk_speed
	if distance_to_target < 1.2:
		desired_speed *= clamp(distance_to_target / 1.2, 0.25, 1.0)
	if _current_speed < desired_speed:
		_current_speed = move_toward(_current_speed, desired_speed, move_acceleration * delta)
	else:
		_current_speed = move_toward(_current_speed, desired_speed, move_deceleration * delta)

	var move_dir := move_delta / move_distance
	_update_facing(move_dir, delta)
	var move_step := minf(_current_speed * delta, move_distance)
	var next_pos := global_position + move_dir * move_step
	global_position = _apply_cheap_path_follow_grounding(next_pos, delta)
	velocity = Vector3(move_dir.x * _current_speed, 0.0, move_dir.z * _current_speed)
	_vertical_speed = 0.0
	_surface_guard_stop_time = 0.0
	_stuck_timer = 0.0
	_last_move_position = global_position
	_update_trace_navigation_state("cheap_path_follow", move_dir, move_dir)

func _maybe_log_surface_guard(action: String, attempted_dir: Vector3, resolved_dir: Vector3) -> void:
	if surface_guard_log_cooldown_sec <= 0.0:
		return
	if _surface_guard_log_cooldown_left > 0.0:
		return
	_surface_guard_log_cooldown_left = surface_guard_log_cooldown_sec
	debug_log("Surface guard %s | attempted=%s resolved=%s target=%s probes=%s" % [
		action,
		_trace_relative_label(attempted_dir),
		_trace_relative_label(resolved_dir),
		_trace_fmt_vec3(_travel_target),
		_trace_last_surface_probe
	])

func _project_to_ground(pos: Vector3) -> Vector3:
	var hit := _probe_ground_hit(pos)
	if hit.is_empty():
		var fallback := pos
		fallback.y = _ground_fallback_y
		return fallback

	var grounded := pos
	grounded.y = (hit["position"] as Vector3).y
	return grounded

func _apply_grounding(pos: Vector3, delta: float) -> Vector3:
	var grounded := pos
	var hit := _probe_ground_hit(pos)
	if hit.is_empty():
		_vertical_speed = max(_vertical_speed - gravity_strength * delta, -max_fall_speed)
		grounded.y += _vertical_speed * delta
		if grounded.y < _ground_fallback_y:
			grounded.y = _ground_fallback_y
			_vertical_speed = 0.0
		return grounded

	_vertical_speed = 0.0
	var floor_y := (hit["position"] as Vector3).y
	grounded.y = lerp(grounded.y, floor_y, clamp(ground_snap_rate * delta, 0.0, 1.0))
	return grounded

func set_position_grounded(pos: Vector3) -> void:
	_agent.locomotion.set_position_grounded(self, pos, _world_ref)

func has_active_rest_pose() -> bool:
	return _rest_pose_active

func set_rest_pose(target_pos: Vector3, yaw: float = 0.0) -> void:
	if _inside_building == null and is_inside_tree():
		target_pos = _project_to_ground(target_pos)
	_rest_pose_active = true
	_rest_pose_position = target_pos
	_rest_pose_yaw = yaw
	apply_rest_pose()

func apply_rest_pose() -> void:
	if not _rest_pose_active:
		return
	global_position = _rest_pose_position
	rotation.y = _rest_pose_yaw
	_current_speed = 0.0
	_vertical_speed = 0.0
	velocity = Vector3.ZERO
	_last_move_position = global_position
	_update_trace_navigation_state("rest_pose", Vector3.ZERO, Vector3.ZERO)

func clear_rest_pose(snap_to_ground: bool = false) -> void:
	if not _rest_pose_active:
		_clear_rest_pose_trace_state()
		return
	_rest_pose_active = false
	_current_speed = 0.0
	_vertical_speed = 0.0
	velocity = Vector3.ZERO
	if snap_to_ground and is_inside_tree():
		set_position_grounded(global_position)
	_last_move_position = global_position
	_clear_rest_pose_trace_state()

func _clear_rest_pose_trace_state() -> void:
	if not _trace_last_decision_reason.begins_with("rest_pose"):
		return
	_update_trace_navigation_state("clear_rest_pose", Vector3.ZERO, Vector3.ZERO)

func release_reserved_benches(world: World = null, building: Building = null) -> void:
	var reserved_building := building if building != null else current_location
	if reserved_building != null and reserved_building.has_method("release_bench_for"):
		reserved_building.release_bench_for(self)
	var resolved_world := world if world != null else _world_ref
	if resolved_world != null and resolved_world.has_method("release_city_bench_for"):
		resolved_world.release_city_bench_for(self)

func reset_travel_debug_state() -> void:
	_debug_repath_count = 0
	_debug_stuck_slide_count = 0
	_debug_stuck_jump_count = 0
	_debug_last_blocking_area = "-"
	_stuck_hotspot_label = ""
	_stuck_hotspot_time = 0.0

func begin_travel_to(target_pos: Vector3, target_building: Building = null) -> bool:
	return _agent.locomotion.begin_travel_to(self, target_pos, target_building, _world_ref)

func begin_custom_travel_route(route_points: PackedVector3Array, target_building: Building = null) -> bool:
	return _agent.locomotion.begin_route(self, route_points, target_building)

func begin_click_move_to(target_pos: Vector3, world: World = null) -> bool:
	var resolved_world := world if world != null else _world_ref
	if _manual_control_enabled:
		set_manual_control_enabled(false, resolved_world)

	clear_rest_pose(true)
	if is_inside_building():
		exit_current_building(resolved_world)
		current_location = null
	elif current_location != null:
		leave_current_location(resolved_world, false)

	release_reserved_benches(resolved_world)
	current_action = null
	decision_cooldown_left = 0
	stop_travel()
	current_location = null

	var snapped_target := target_pos
	if resolved_world != null and resolved_world.has_method("get_pedestrian_access_point"):
		snapped_target = resolved_world.get_pedestrian_access_point(target_pos)

	var started := begin_travel_to(snapped_target, null)
	if started:
		SimLogger.log("[Citizen %s] Click-move target set to %s (raw=%s)" % [
			citizen_name,
			_trace_fmt_vec3(snapped_target),
			_trace_fmt_vec3(target_pos)
		])
	return started

func has_reached_travel_target() -> bool:
	return _agent.locomotion.has_reached_travel_target(self)

func stop_travel() -> void:
	_agent.locomotion.stop_travel(self)

func get_remaining_travel_distance() -> float:
	var current_pos := global_position if is_inside_tree() else position
	current_pos = _project_to_ground(current_pos)
	if _travel_route.is_empty():
		if _is_travelling:
			var direct_target := _project_to_ground(_travel_target)
			direct_target.y = current_pos.y
			return current_pos.distance_to(direct_target)
		if _travel_target_building != null:
			var fallback_target := _get_building_access_pos(_travel_target_building, _world_ref)
			fallback_target = _project_to_ground(fallback_target)
			fallback_target.y = current_pos.y
			return current_pos.distance_to(fallback_target)
		return 0.0

	var remaining := 0.0
	var segment_start := current_pos
	var current_target := _project_to_ground(_travel_target)
	current_target.y = segment_start.y
	remaining += segment_start.distance_to(current_target)

	var start_index := clampi(_travel_route_index, 0, _travel_route.size() - 1)
	for idx in range(start_index, _travel_route.size() - 1):
		var point_a := _project_to_ground(_travel_route[idx])
		var point_b := _project_to_ground(_travel_route[idx + 1])
		point_b.y = point_a.y
		remaining += point_a.distance_to(point_b)
	return remaining

func advance_coarse_travel_by_distance(distance_m: float) -> bool:
	if distance_m <= 0.0:
		return has_reached_travel_target()
	if not _is_travelling:
		return has_reached_travel_target()

	var remaining_distance := distance_m
	while remaining_distance > 0.001 and _is_travelling:
		var segment_target := _project_to_ground(_travel_target)
		var current_pos := _project_to_ground(global_position if is_inside_tree() else position)
		var to_target := segment_target - current_pos
		to_target.y = 0.0
		var segment_length := to_target.length()
		if segment_length <= 0.001:
			if _advance_travel_route():
				continue
			return _finish_coarse_travel_arrival()

		if remaining_distance < segment_length:
			var next_pos := current_pos + to_target.normalized() * remaining_distance
			set_position_grounded(next_pos)
			_last_move_position = global_position
			return false

		set_position_grounded(segment_target)
		remaining_distance -= segment_length
		if _advance_travel_route():
			continue
		return _finish_coarse_travel_arrival()

	return has_reached_travel_target()

func _finish_coarse_travel_arrival() -> bool:
	_current_speed = 0.0
	velocity = Vector3.ZERO
	if _travel_target_building != null:
		_arrived_via_entrance_contact = true
		_update_trace_navigation_state("coarse_arrive_target", Vector3.ZERO, Vector3.ZERO)
		return true
	stop_travel()
	_update_trace_navigation_state("coarse_arrive_target", Vector3.ZERO, Vector3.ZERO)
	return true

func get_debug_travel_target_building() -> Building:
	if _travel_target_building != null and is_instance_valid(_travel_target_building):
		return _travel_target_building
	if current_action != null:
		var action_target: Variant = current_action.get("target")
		if action_target is Building:
			return action_target as Building
	return null

func get_debug_lod_label(world: World = null) -> String:
	var label := simulation_lod_tier
	if simulation_lod_tier == "coarse":
		var active_world := world if world != null else _world_ref
		var minutes_until_tick := 0
		if active_world != null and active_world.has_method("get_citizen_simulation_minutes_until_due"):
			minutes_until_tick = int(active_world.get_citizen_simulation_minutes_until_due(self))
		label += " tick=%dmin" % maxi(minutes_until_tick, 0)
	var hidden := _lod_presence_hidden or _interior_presence_hidden
	if hidden:
		label += " hidden"
	return label

func get_debug_coarse_eta_minutes(world: World = null) -> int:
	var active_world := world if world != null else _world_ref
	if active_world == null:
		return 0
	if simulation_lod_tier != "coarse":
		return 0
	var target_building := get_debug_travel_target_building()
	if not _is_travelling and target_building == null:
		return 0
	if _agent != null and _agent.has_method("estimate_coarse_travel_minutes"):
		return _agent.estimate_coarse_travel_minutes(self, active_world, get_remaining_travel_distance())
	return 0

func is_inside_building() -> bool:
	return _inside_building != null

func enter_building(building: Building, world: World = null, emit_log: bool = true) -> void:
	if building == null:
		return
	clear_rest_pose(true)
	if current_location != building:
		release_reserved_benches(world, current_location)
	var nav_points := _get_building_nav_points(building, world)
	var entry_pos := global_position
	stop_travel()
	current_location = building
	var is_outdoor := building.has_method("is_outdoor_destination") and building.is_outdoor_destination()
	if is_outdoor:
		set_position_grounded(global_position)
		_inside_building = null
	else:
		if nav_points.has("spawn"):
			set_position_grounded(nav_points["spawn"])
		_inside_building = building
	if building.has_method("on_citizen_entered"):
		building.on_citizen_entered(self)
	_set_interior_presence(not is_outdoor)
	if world != null:
		_ground_fallback_y = world.get_ground_fallback_y()
	_update_trace_navigation_state("entered_%s" % building.get_display_name(), Vector3.ZERO, Vector3.ZERO)
	if emit_log:
		SimLogger.log("[Citizen %s] Entered %s at %s | entrance=%s access=%s visit=%s spawn=%s" % [
			citizen_name,
			building.get_display_name(),
			_trace_fmt_vec3(entry_pos),
			_trace_fmt_vec3(nav_points.get("entrance", building.get_entrance_pos())),
			_trace_fmt_vec3(nav_points.get("access", _get_building_access_pos(building, world))),
			_trace_fmt_vec3(nav_points.get("visit", global_position)),
			_trace_fmt_vec3(nav_points.get("spawn", global_position))
		])

func leave_current_location(world: World = null, emit_log: bool = true) -> void:
	if is_inside_building():
		exit_current_building(world)
		return
	if current_location == null:
		return

	var exit_building := current_location
	clear_rest_pose(true)
	release_reserved_benches(world, exit_building)
	var nav_points := _get_building_nav_points(exit_building, world)
	var is_outdoor := exit_building.has_method("is_outdoor_destination") and exit_building.is_outdoor_destination()
	var exit_pos: Vector3 = nav_points.get("spawn", nav_points.get("access", global_position))
	if is_outdoor:
		set_position_grounded(exit_pos)
	current_location = null
	if exit_building.has_method("on_citizen_exited"):
		exit_building.on_citizen_exited(self)
	_update_trace_navigation_state("left_%s" % exit_building.get_display_name(), Vector3.ZERO, Vector3.ZERO)
	if emit_log:
		SimLogger.log("[Citizen %s] Left %s at %s | entrance=%s access=%s visit=%s" % [
			citizen_name,
			exit_building.get_display_name(),
			_trace_fmt_vec3(global_position),
			_trace_fmt_vec3(nav_points.get("entrance", exit_building.get_entrance_pos())),
			_trace_fmt_vec3(nav_points.get("access", _get_building_access_pos(exit_building, world))),
			_trace_fmt_vec3(nav_points.get("visit", global_position))
		])

func exit_current_building(world: World = null) -> void:
	if _inside_building == null:
		return

	clear_rest_pose(true)
	var exit_building := _inside_building
	var nav_points := _get_building_nav_points(exit_building, world)
	var access_pos: Vector3 = nav_points.get("access", _get_building_access_pos(exit_building, world))
	var exit_pos: Vector3 = nav_points.get("spawn", _get_building_exit_spawn_pos(exit_building, world))

	_inside_building = null
	if exit_building.has_method("on_citizen_exited"):
		exit_building.on_citizen_exited(self)
	_set_interior_presence(false)
	set_position_grounded(exit_pos)
	if absf(global_position.y - exit_pos.y) > 0.45:
		global_position = exit_pos
		_vertical_speed = 0.0
		velocity = Vector3.ZERO
		_last_move_position = global_position
	_update_trace_navigation_state("exited_%s" % exit_building.get_display_name(), Vector3.ZERO, Vector3.ZERO)
	SimLogger.log("[Citizen %s] Exited %s at %s | entrance=%s access=%s spawn=%s" % [
		citizen_name,
		exit_building.get_display_name(),
		_trace_fmt_vec3(global_position),
		_trace_fmt_vec3(nav_points.get("entrance", exit_building.get_entrance_pos())),
		_trace_fmt_vec3(access_pos),
		_trace_fmt_vec3(exit_pos)
	])

func _set_interior_presence(hidden: bool) -> void:
	_interior_presence_hidden = hidden
	_apply_presence_hidden_state()

func _apply_presence_hidden_state() -> void:
	var hidden := _interior_presence_hidden or _lod_presence_hidden
	if hidden:
		hide()
		velocity = Vector3.ZERO
		collision_layer = 0
		collision_mask = 0
	else:
		show()
		collision_layer = _saved_collision_layer
		collision_mask = _saved_collision_mask

	if _body_collision_shape != null:
		_body_collision_shape.disabled = hidden
	if _forward_avoidance_area != null:
		_forward_avoidance_area.monitoring = not hidden and local_navigation_raycast_checks_enabled and forward_avoidance_enabled
	if _forward_avoidance_shape != null:
		_forward_avoidance_shape.disabled = hidden or not forward_avoidance_enabled or not local_navigation_raycast_checks_enabled
	if _click_area != null:
		_click_area.input_ray_pickable = not hidden
	if _click_area_shape != null:
		_click_area_shape.disabled = hidden

func _get_building_access_pos(building: Building, world: World = null) -> Vector3:
	var nav_points := _get_building_nav_points(building, world)
	return nav_points.get("access", global_position)

func get_navigation_points_for_building(building: Building, world: World = null) -> Dictionary:
	return _get_building_nav_points(building, world)

func _get_building_exit_spawn_pos(building: Building, world: World = null) -> Vector3:
	var nav_points := _get_building_nav_points(building, world)
	return nav_points.get("spawn", global_position)

func _get_building_nav_points(building: Building, world: World = null) -> Dictionary:
	if building == null:
		return {}

	var lane_offset := _get_building_lane_offset()
	var nav_points: Dictionary = {}
	if building.has_method("get_navigation_points"):
		nav_points = building.get_navigation_points(world, lane_offset, global_position)
	else:
		var entrance_pos := building.get_entrance_pos()
		var access_pos := entrance_pos
		if world != null and world.has_method("get_pedestrian_access_point"):
			access_pos = world.get_pedestrian_access_point(entrance_pos, building)

		nav_points = {
			"entrance": entrance_pos,
			"access": access_pos,
			"spawn": _compute_building_exit_spawn_from_points(building, entrance_pos, access_pos, lane_offset),
		}

	var reserved_bench: Dictionary = {}
	if building is Park:
		reserved_bench = (building as Park).get_reserved_bench_for(self)
	elif building.has_method("get_reserved_bench_for"):
		reserved_bench = building.get_reserved_bench_for(self)
	if not reserved_bench.is_empty():
		var bench_pos: Vector3 = reserved_bench.get("position", nav_points.get("visit", nav_points.get("center", global_position)))
		nav_points["visit"] = bench_pos
		nav_points["center"] = bench_pos
		nav_points["bench"] = bench_pos
		nav_points["bench_yaw"] = float(reserved_bench.get("yaw", 0.0))

	return nav_points

func _get_building_lane_offset() -> float:
	var lane_offsets := [-0.12, -0.04, 0.04, 0.12]
	var lane_slot := int(abs(citizen_name.hash())) % lane_offsets.size()
	return float(lane_offsets[lane_slot])

func _compute_building_exit_spawn_from_points(
	building: Building,
	entrance_pos: Vector3,
	access_pos: Vector3,
	lane_offset: float = 0.0
) -> Vector3:
	if building == null:
		return access_pos

	var outward := access_pos - entrance_pos
	outward.y = 0.0
	if outward.length_squared() <= 0.0001:
		outward = access_pos - building.global_position
		outward.y = 0.0
	if outward.length_squared() <= 0.0001:
		outward = Vector3.FORWARD
	else:
		outward = outward.normalized()

	var lateral := Vector3(-outward.z, 0.0, outward.x)
	var spawn_base := entrance_pos.lerp(access_pos, 0.55)
	var spawn_pos := spawn_base + lateral * lane_offset + outward * 0.02
	spawn_pos.y = spawn_base.y
	return spawn_pos

func _get_waypoint_move_target() -> Vector3:
	if _travel_route_index <= 0 or _travel_route_index >= _travel_route.size() - 1:
		return _travel_target
	if _is_crosswalk_waypoint(_travel_target):
		return _travel_target

	var prev_point := _travel_route[_travel_route_index - 1]
	var next_point := _travel_route[_travel_route_index + 1]
	var axis := next_point - prev_point
	axis.y = 0.0
	if axis.length_squared() <= 0.0001:
		axis = _travel_target - prev_point
		axis.y = 0.0
	if axis.length_squared() <= 0.0001:
		return _travel_target

	var lateral := Vector3(-axis.z, 0.0, axis.x).normalized()
	var adjusted_target := _travel_target + lateral * _get_building_lane_offset()
	adjusted_target.y = _travel_target.y
	return adjusted_target

func _should_skip_crowded_waypoint(distance_to_target: float, is_last_waypoint: bool) -> bool:
	if _is_using_cheap_path_follow():
		return false
	if is_last_waypoint:
		return false
	if _travel_route_index <= 0 or _travel_route_index >= _travel_route.size() - 1:
		return false
	if _is_crosswalk_waypoint(_travel_target):
		return false
	if distance_to_target > crowded_waypoint_skip_distance:
		return false
	if _stuck_timer < obstacle_stuck_timeout:
		return false
	return _count_waypoint_conflicts() >= crowded_waypoint_neighbor_count

func _count_waypoint_conflicts() -> int:
	if _world_ref == null:
		return 0

	var conflicts := 0
	for other in _world_ref.citizens:
		if other == null or other == self:
			continue
		if not is_instance_valid(other):
			continue
		if other.has_method("is_inside_building") and other.is_inside_building():
			continue
		if global_position.distance_to(other.global_position) > crowded_waypoint_neighbor_radius:
			continue

		var shares_target := false
		if other is Citizen:
			var other_citizen := other as Citizen
			if other_citizen._is_travelling and other_citizen._travel_target.distance_to(_travel_target) <= crowded_waypoint_shared_target_radius:
				shares_target = true
		if not shares_target and other.global_position.distance_to(_travel_target) > crowded_waypoint_skip_distance:
			continue
		conflicts += 1

	return conflicts

func _is_crosswalk_waypoint(point: Vector3) -> bool:
	if _world_ref == null or not _world_ref.has_method("get_pedestrian_path_point_kind"):
		return false
	var kind := str(_world_ref.get_pedestrian_path_point_kind(point))
	return kind.begins_with("crosswalk")

func _recover_floor_contact() -> void:
	if _floor_snap_suppress_left > 0.0:
		return
	if is_on_floor():
		return
	var hit := _probe_ground_hit(global_position)
	if hit.is_empty():
		return
	var floor_pos := hit["position"] as Vector3
	var floor_gap := global_position.y - floor_pos.y
	if floor_gap < -0.05 or floor_gap > maxf(floor_snap_distance + 0.1, 0.55):
		return
	global_position.y = floor_pos.y
	velocity.y = 0.0
	_vertical_speed = 0.0

func get_debug_travel_path() -> PackedVector3Array:
	var path := PackedVector3Array()
	path.append(global_position)

	if not _is_travelling:
		return path

	if _travel_target != Vector3.ZERO:
		path.append(_travel_target)

	var start_idx := clampi(_travel_route_index + 1, 0, _travel_route.size())
	for i in range(start_idx, _travel_route.size()):
		var point: Vector3 = _travel_route[i]
		if path[path.size() - 1].distance_to(point) >= 0.05:
			path.append(point)

	return path

func get_debug_source_building() -> Building:
	if _inside_building != null:
		return _inside_building
	if current_location != null:
		return current_location
	return home

func get_debug_access_pos(building: Building, world: World = null) -> Vector3:
	return _get_building_access_pos(building, world)

func get_debug_exit_spawn_pos(building: Building, world: World = null) -> Vector3:
	return _get_building_exit_spawn_pos(building, world)

func get_debug_travel_route_points() -> PackedVector3Array:
	if _is_travelling:
		return _travel_route
	return _debug_last_travel_route

func get_debug_travel_current_target() -> Vector3:
	if _is_travelling:
		return _travel_target
	return Vector3.ZERO

func get_debug_travel_route_index() -> int:
	if _is_travelling:
		return _travel_route_index
	return -1

func is_debug_travelling() -> bool:
	return _is_travelling

func has_debug_travel_route() -> bool:
	return _is_travelling or _debug_last_travel_route.size() >= 2

func did_debug_last_travel_fail() -> bool:
	return _debug_last_travel_failed

func _advance_travel_route() -> bool:
	if _travel_route.is_empty():
		return false

	var next_index := _travel_route_index + 1
	if next_index >= _travel_route.size():
		return false

	_travel_route_index = next_index
	_travel_target = _project_to_ground(_travel_route[_travel_route_index])
	_surface_guard_stop_time = 0.0
	if _nav_agent != null:
		_nav_agent.target_position = _travel_target
	_repath_time_left = repath_interval_sec
	return true

func _pause_travel_motion(delta: float, desired_facing: Vector3, reason: String, blocking_area: String = "") -> void:
	_current_speed = move_toward(_current_speed, 0.0, move_deceleration * delta)
	if desired_facing != Vector3.ZERO:
		_update_facing(desired_facing, delta)
	velocity.x = 0.0
	velocity.z = 0.0
	if is_on_floor():
		if velocity.y < 0.0:
			velocity.y = 0.0
	else:
		velocity.y = maxf(velocity.y - gravity_strength * delta, -max_fall_speed)
	move_and_slide()
	_recover_floor_contact()
	_surface_guard_stop_time = 0.0
	_stuck_timer = 0.0
	_stuck_hotspot_label = ""
	_stuck_hotspot_time = 0.0
	_last_move_position = global_position
	if blocking_area != "":
		_debug_last_blocking_area = blocking_area
	_update_trace_navigation_state(reason, desired_facing, Vector3.ZERO)

func _move_along_path(delta: float) -> void:
	if _repath_time_left > 0.0:
		_repath_time_left = maxf(_repath_time_left - delta, 0.0)

	if _arrived_via_entrance_contact:
		_current_speed = move_toward(_current_speed, 0.0, move_deceleration * delta)
		velocity.x = 0.0
		velocity.z = 0.0
		if is_on_floor():
			if velocity.y < 0.0:
				velocity.y = 0.0
		else:
			velocity.y = maxf(velocity.y - gravity_strength * delta, -max_fall_speed)
		move_and_slide()
		_recover_floor_contact()
		return

	var to_target := _travel_target - global_position
	to_target.y = 0.0
	var distance_to_target := to_target.length()
	var is_last_waypoint: bool = _travel_route_index >= _travel_route.size() - 1
	var reach_distance: float = final_arrival_distance if is_last_waypoint else waypoint_reach_distance
	var is_building_arrival := is_last_waypoint \
		and _travel_target_building != null \
		and _should_use_entrance_contact_arrival()
	if is_last_waypoint and _travel_target_building != null:
		reach_distance = maxf(reach_distance, arrival_distance)

	if distance_to_target <= reach_distance:
		if _advance_travel_route():
			return
		if is_building_arrival \
				and distance_to_target <= final_arrival_distance \
				and absf(global_position.y - _travel_target.y) <= entrance_contact_height_tolerance:
			_arrived_via_entrance_contact = true
			_current_speed = 0.0
			velocity.x = 0.0
			velocity.z = 0.0
			_update_trace_navigation_state("arrive_target_access_precise", Vector3.ZERO, Vector3.ZERO)
			return
		if is_building_arrival:
			pass
		elif _travel_target_building != null and _travel_target_building.has_method("is_outdoor_destination") and _travel_target_building.is_outdoor_destination():
			set_position_grounded(_travel_target)
			stop_travel()
			_update_trace_navigation_state("arrive_target_path_end", Vector3.ZERO, Vector3.ZERO)
			return
		elif _travel_target_building == null:
			stop_travel()
			_update_trace_navigation_state("arrive_target_path_end", Vector3.ZERO, Vector3.ZERO)
			return

	if _should_skip_crowded_waypoint(distance_to_target, is_last_waypoint):
		if _advance_travel_route():
			_update_trace_navigation_state("skip_crowded_waypoint", Vector3.ZERO, Vector3.ZERO)
			return

	var move_target := _get_waypoint_move_target()
	var move_delta := move_target - global_position
	move_delta.y = 0.0
	var move_distance := move_delta.length()
	var desired_dir: Vector3 = move_delta / move_distance if move_distance > 0.001 else Vector3.ZERO

	if move_distance <= 0.001:
		_current_speed = move_toward(_current_speed, 0.0, move_deceleration * delta)
		_update_trace_navigation_state("arriving", Vector3.ZERO, Vector3.ZERO)
		return

	if _agent != null and _agent.crosswalk_awareness != null:
		var crosswalk_wait: Dictionary = _agent.crosswalk_awareness.get_wait_state(self, distance_to_target, desired_dir)
		if bool(crosswalk_wait.get("should_wait", false)):
			_pause_travel_motion(
				delta,
				desired_dir,
				str(crosswalk_wait.get("reason", "crosswalk_wait")),
				str(crosswalk_wait.get("signal", "traffic_light"))
			)
			return

	var desired_speed: float = _walk_speed
	if distance_to_target < 1.2:
		desired_speed *= clamp(distance_to_target / 1.2, 0.25, 1.0)

	if _current_speed < desired_speed:
		_current_speed = move_toward(_current_speed, desired_speed, move_acceleration * delta)
	else:
		_current_speed = move_toward(_current_speed, desired_speed, move_deceleration * delta)

	var move_dir := _compute_move_direction(desired_dir)
	move_dir = _constrain_move_direction_to_pedestrian_surface(move_dir, desired_dir)
	if _agent != null and _agent.obstacle_avoidance != null and move_dir != Vector3.ZERO:
		var refined_move_dir: Vector3 = _agent.obstacle_avoidance.refine_move_direction(self, move_dir, desired_dir)
		if refined_move_dir != move_dir:
			_update_trace_navigation_state("clearance_refine_%s" % _trace_relative_label(refined_move_dir), desired_dir, refined_move_dir)
		move_dir = refined_move_dir
	if move_dir == Vector3.ZERO:
		_surface_guard_stop_time += delta
		var blocked_waypoint_reach := reach_distance + maxf(surface_guard_blocked_waypoint_extra_distance, 0.0)
		if not is_last_waypoint \
				and not _is_crosswalk_waypoint(_travel_target) \
				and distance_to_target <= blocked_waypoint_reach:
			if _advance_travel_route():
				_update_trace_navigation_state("surface_guard_skip_waypoint", desired_dir, Vector3.ZERO)
				return
		if _surface_guard_stop_time >= surface_guard_repath_timeout_sec:
			if _agent != null and _agent.locomotion != null and _agent.locomotion.repath_current_travel(self, _world_ref):
				_surface_guard_stop_time = 0.0
				_debug_repath_count += 1
				_update_congestion_debug_label()
				_update_trace_navigation_state("surface_guard_repath", desired_dir, Vector3.ZERO)
				return
		_current_speed = move_toward(_current_speed, 0.0, move_deceleration * delta)
		velocity.x = 0.0
		velocity.z = 0.0
		if is_on_floor():
			if velocity.y < 0.0:
				velocity.y = 0.0
		else:
			velocity.y = maxf(velocity.y - gravity_strength * delta, -max_fall_speed)
		move_and_slide()
		_recover_floor_contact()
		_update_stuck_state(delta)
		return
	_surface_guard_stop_time = 0.0
	if _stuck_jump_hold_left > 0.0 and _stuck_jump_hold_dir != Vector3.ZERO:
		_current_speed = maxf(_current_speed, _walk_speed * obstacle_jump_forward_speed_multiplier)
	_update_facing(move_dir, delta)

	velocity.x = move_dir.x * _current_speed
	velocity.z = move_dir.z * _current_speed
	if is_on_floor():
		if velocity.y < 0.0:
			velocity.y = 0.0
	else:
		velocity.y = maxf(velocity.y - gravity_strength * delta, -max_fall_speed)

	move_and_slide()
	_recover_floor_contact()
	_update_stuck_state(delta)

func _update_facing(move_dir: Vector3, delta: float) -> void:
	if move_dir.length_squared() <= 0.0001:
		return

	var target_yaw := _yaw_from_move_direction(move_dir)
	rotation.y = lerp_angle(rotation.y, target_yaw, clamp(turn_speed * delta, 0.0, 1.0))

func _yaw_from_move_direction(move_dir: Vector3) -> float:
	return atan2(-move_dir.x, -move_dir.z)

func _compute_move_direction(desired_dir: Vector3) -> Vector3:
	var planar_dir := desired_dir
	planar_dir.y = 0.0
	if planar_dir.length_squared() <= 0.0001:
		_update_trace_navigation_state("idle", Vector3.ZERO, Vector3.ZERO)
		return Vector3.ZERO
	planar_dir = planar_dir.normalized()
	if not local_navigation_raycast_checks_enabled:
		_update_trace_navigation_state("path_follow_no_rays", planar_dir, planar_dir)
		return planar_dir

	if _stuck_jump_hold_left > 0.0 and _stuck_jump_hold_dir != Vector3.ZERO:
		var jump_dir := _stuck_jump_hold_dir.normalized()
		_update_trace_navigation_state("jump_carry", planar_dir, jump_dir)
		return jump_dir

	_refresh_obstacle_sensors(planar_dir)
	_update_trace_obstacle_hits()
	if _try_step_up_from_down_ray():
		_refresh_obstacle_sensors(planar_dir)
		_update_trace_obstacle_hits()
	if _try_mark_arrived_via_target_entrance(planar_dir):
		_update_trace_navigation_state("arrive_target_entrance", planar_dir, Vector3.ZERO)
		return Vector3.ZERO
	if _stuck_timer >= obstacle_stuck_timeout:
		var repath_timeout := maxf(obstacle_repath_timeout, obstacle_jump_stuck_timeout + 0.35)
		# Give the locomotion system a chance to rebuild the route before we keep
		# committing to the same slide direction forever against the same obstacle.
		if _stuck_timer >= repath_timeout:
			if _agent != null and _agent.locomotion != null and _agent.locomotion.repath_current_travel(self, _world_ref):
				_debug_repath_count += 1
				_update_congestion_debug_label()
				_update_trace_navigation_state("repath_stuck", planar_dir, Vector3.ZERO)
				return Vector3.ZERO
		if _stuck_timer >= obstacle_jump_stuck_timeout and _try_stuck_jump(planar_dir):
			_debug_stuck_jump_count += 1
			_update_congestion_debug_label()
			_update_trace_navigation_state("stuck_jump", planar_dir, planar_dir)
			return planar_dir
		var slide_escape := _get_stuck_slide_direction(planar_dir)
		if slide_escape != Vector3.ZERO:
			_debug_stuck_slide_count += 1
			_update_congestion_debug_label()
			_update_trace_navigation_state("stuck_slide_%s" % _trace_relative_label(slide_escape), planar_dir, slide_escape)
			return slide_escape
		var escape_dir := _compute_escape_direction(planar_dir)
		_update_trace_navigation_state("stuck_escape_%s" % _trace_relative_label(escape_dir), planar_dir, escape_dir)
		return escape_dir

	var forward_blocked := _ray_is_blocked(_obstacle_ray_forward)
	if not forward_blocked and _ray_detects_low_obstacle(_obstacle_ray_down):
		forward_blocked = true
	var left_blocked := _ray_is_blocked(_obstacle_ray_left)
	var right_blocked := _ray_is_blocked(_obstacle_ray_right)

	if forward_blocked:
		var avoid_dir := _choose_turn_direction(planar_dir, left_blocked, right_blocked)
		if avoid_dir != Vector3.ZERO:
			var blended_avoid := _blend_move_direction(planar_dir, avoid_dir)
			_update_trace_navigation_state("avoid_forward_%s" % _trace_relative_label(avoid_dir), planar_dir, blended_avoid)
			return blended_avoid
		var reverse_dir := -planar_dir
		_update_trace_navigation_state("avoid_forward_back", planar_dir, reverse_dir)
		return reverse_dir

	if left_blocked != right_blocked:
		var side_push := global_transform.basis.x if left_blocked else -global_transform.basis.x
		side_push.y = 0.0
		var nudged_dir := _blend_move_direction(planar_dir, side_push.normalized(), obstacle_side_bias)
		_update_trace_navigation_state(
			"nudge_%s_blocked" % ("left" if left_blocked else "right"),
			planar_dir,
			nudged_dir
		)
		return nudged_dir

	_update_trace_navigation_state("path_follow", planar_dir, planar_dir)
	return planar_dir

func _refresh_obstacle_sensors(move_dir: Vector3) -> void:
	if _obstacle_sensor_pivot == null and _forward_avoidance_area == null:
		return
	var target_yaw := _yaw_from_move_direction(move_dir)
	var local_sensor_yaw := wrapf(target_yaw - rotation.y, -PI, PI)
	if _obstacle_sensor_pivot != null:
		_obstacle_sensor_pivot.rotation.y = local_sensor_yaw
	if _forward_avoidance_area != null:
		_forward_avoidance_area.rotation.y = local_sensor_yaw
	if _obstacle_ray_forward != null:
		_obstacle_ray_forward.force_raycast_update()
	if _obstacle_ray_down != null:
		_obstacle_ray_down.force_raycast_update()
	if _obstacle_ray_left != null:
		_obstacle_ray_left.force_raycast_update()
	if _obstacle_ray_right != null:
		_obstacle_ray_right.force_raycast_update()

func _ray_is_blocked(ray: RayCast3D) -> bool:
	if _agent == null or _agent.obstacle_avoidance == null:
		return false
	return _agent.obstacle_avoidance.is_ray_blocked(self, ray)

func _ray_detects_low_obstacle(ray: RayCast3D) -> bool:
	if _agent == null or _agent.obstacle_avoidance == null:
		return false
	return _agent.obstacle_avoidance.ray_detects_low_obstacle(self, ray)

func _is_citizen_collider(collider: Variant) -> bool:
	if collider == null or collider == self:
		return false
	if collider is Citizen:
		return true
	if collider is CharacterBody3D:
		var node := collider as Node
		return node.is_in_group("citizens")
	return false

func _is_walkable_step_surface(collider: Variant) -> bool:
	if not (collider is Node):
		return false
	var node := collider as Node
	var label := node.name.to_lower()
	if node.is_inside_tree():
		label = str(node.get_path()).to_lower()
	return label.contains("road_")

func _try_step_up_from_down_ray() -> bool:
	if _floor_snap_suppress_left > 0.0:
		return false
	if _obstacle_ray_down == null or not _obstacle_ray_down.enabled or not _obstacle_ray_down.is_colliding():
		return false

	var collider := _obstacle_ray_down.get_collider()
	if collider == null or collider == self:
		return false
	if _is_citizen_collider(collider):
		return false
	if collider is Node:
		var node := collider as Node
		if _is_entrance_trigger_node(node):
			return false
	if not _is_walkable_step_surface(collider):
		return false

	var hit_normal := _obstacle_ray_down.get_collision_normal()
	if hit_normal.dot(Vector3.UP) < 0.55:
		return false

	var hit_pos := _obstacle_ray_down.get_collision_point()
	var step_height := hit_pos.y - global_position.y
	if step_height <= 0.02 or step_height > max_ground_step_up:
		return false

	global_position.y = hit_pos.y
	velocity.y = 0.0
	_vertical_speed = 0.0
	_last_move_position = global_position
	return true

func _try_mark_arrived_via_target_entrance(preferred_dir: Vector3) -> bool:
	if _travel_target_building == null:
		return false
	if not _should_use_entrance_contact_arrival():
		return false
	var access_delta := _travel_target - global_position
	access_delta.y = 0.0
	var access_distance := access_delta.length()
	var height_distance := absf(global_position.y - _travel_target.y)
	var height_aligned := height_distance <= entrance_contact_height_tolerance
	var precise_target_distance := maxf(final_arrival_distance, 0.16)
	var trigger_contact_distance := minf(arrival_distance, maxf(precise_target_distance * 2.0, 0.35))
	if _any_ray_hits_target_entrance_trigger() and height_aligned and access_distance <= trigger_contact_distance:
		_arrived_via_entrance_contact = true
		return true
	if not _any_ray_hits_target_building():
		return false
	if height_aligned and access_distance <= precise_target_distance:
		_arrived_via_entrance_contact = true
		return true
	if access_distance > precise_target_distance or not height_aligned:
		return false

	var to_entrance := _travel_target_building.get_entrance_pos() - global_position
	to_entrance.y = 0.0
	var entrance_distance := to_entrance.length()
	if entrance_distance > entrance_contact_distance:
		return false
	if entrance_distance > 0.001:
		var entrance_dir := to_entrance / entrance_distance
		if preferred_dir.dot(entrance_dir) < entrance_contact_alignment:
			return false

	_arrived_via_entrance_contact = true
	return true

func _should_use_entrance_contact_arrival() -> bool:
	if _travel_target_building == null:
		return false
	return not (
		_travel_target_building.has_method("is_outdoor_destination")
		and _travel_target_building.is_outdoor_destination()
	)

func _ray_hits_target_building(ray: RayCast3D) -> bool:
	if ray == null or not ray.enabled or not ray.is_colliding():
		return false
	var collider := ray.get_collider()
	if not (collider is Node):
		return false
	var node := collider as Node
	if _is_target_entrance_trigger(node):
		return true
	if _travel_target_building != null and _travel_target_building.has_method("owns_navigation_node"):
		return _travel_target_building.owns_navigation_node(node)
	return false

func _ray_hits_target_entrance_trigger(ray: RayCast3D) -> bool:
	if ray == null or not ray.enabled or not ray.is_colliding():
		return false
	var collider := ray.get_collider()
	if not (collider is Node):
		return false
	return _is_target_entrance_trigger(collider as Node)

func _any_ray_hits_target_building() -> bool:
	return _ray_hits_target_building(_obstacle_ray_forward) \
		or _ray_hits_target_building(_obstacle_ray_left) \
		or _ray_hits_target_building(_obstacle_ray_right)

func _any_ray_hits_target_entrance_trigger() -> bool:
	return _ray_hits_target_entrance_trigger(_obstacle_ray_forward) \
		or _ray_hits_target_entrance_trigger(_obstacle_ray_left) \
		or _ray_hits_target_entrance_trigger(_obstacle_ray_right)

func _is_entrance_trigger_node(node: Node) -> bool:
	var current := node
	while current != null:
		if current.name.begins_with("EntranceTrigger"):
			return true
		current = current.get_parent()
	return false

func _is_target_entrance_trigger(node: Node) -> bool:
	if _travel_target_building == null or node == null:
		return false
	if _travel_target_building.has_method("is_entrance_trigger_node"):
		return _travel_target_building.is_entrance_trigger_node(node)
	return false

func _choose_turn_direction(preferred_dir: Vector3, left_blocked: bool, right_blocked: bool) -> Vector3:
	var left_dir := _ray_move_direction(_obstacle_ray_left)
	var right_dir := _ray_move_direction(_obstacle_ray_right)
	var left_open := not left_blocked and left_dir != Vector3.ZERO
	var right_open := not right_blocked and right_dir != Vector3.ZERO

	if left_open and right_open:
		return left_dir if _score_direction(left_dir) <= _score_direction(right_dir) else right_dir
	if left_open:
		return left_dir
	if right_open:
		return right_dir
	return -preferred_dir

func _compute_escape_direction(preferred_dir: Vector3) -> Vector3:
	var left_dir := _ray_move_direction(_obstacle_ray_left)
	var right_dir := _ray_move_direction(_obstacle_ray_right)
	var left_open := not _ray_is_blocked(_obstacle_ray_left) and left_dir != Vector3.ZERO
	var right_open := not _ray_is_blocked(_obstacle_ray_right) and right_dir != Vector3.ZERO

	if left_open or right_open:
		return _choose_turn_direction(preferred_dir, not left_open, not right_open)
	return -preferred_dir

func _get_stuck_slide_direction(preferred_dir: Vector3) -> Vector3:
	if _stuck_slide_hold_left > 0.0 and _stuck_slide_hold_dir != Vector3.ZERO:
		if _is_slide_escape_direction_viable(_stuck_slide_hold_dir):
			return _stuck_slide_hold_dir
		_stuck_slide_hold_dir = Vector3.ZERO
		_stuck_slide_hold_left = 0.0

	var slide_dir := _compute_slide_escape_direction(preferred_dir)
	if slide_dir != Vector3.ZERO:
		_stuck_slide_hold_dir = slide_dir
		_stuck_slide_hold_left = obstacle_slide_hold_sec
	return slide_dir

func _try_stuck_jump(forward_dir: Vector3) -> bool:
	if _stuck_jump_cooldown_left > 0.0:
		return false
	if not _ensure_ground_contact_for_stuck_jump():
		return false
	if forward_dir.length_squared() <= 0.0001:
		return false

	velocity.y = maxf(velocity.y, obstacle_jump_velocity)
	_vertical_speed = velocity.y
	_stuck_jump_hold_dir = forward_dir.normalized()
	_stuck_jump_hold_left = obstacle_jump_forward_hold_sec
	_current_speed = maxf(_current_speed, _walk_speed * obstacle_jump_forward_speed_multiplier)
	_stuck_jump_cooldown_left = obstacle_jump_cooldown_sec
	_floor_snap_suppress_left = obstacle_jump_floor_snap_suppress_sec
	floor_snap_length = 0.0
	_stuck_timer = 0.0
	_stuck_slide_hold_dir = Vector3.ZERO
	_stuck_slide_hold_left = 0.0
	return true

func _ensure_ground_contact_for_stuck_jump() -> bool:
	if is_on_floor():
		return true

	var hit := _probe_ground_hit(global_position)
	if hit.is_empty():
		return false

	var floor_pos := hit["position"] as Vector3
	var floor_gap := global_position.y - floor_pos.y
	var max_jump_ground_gap := maxf(floor_snap_distance * 0.6, 0.18)
	if floor_gap < -0.05 or floor_gap > max_jump_ground_gap:
		return false

	global_position.y = floor_pos.y
	velocity.y = 0.0
	_vertical_speed = 0.0
	return true

func _compute_slide_escape_direction(preferred_dir: Vector3) -> Vector3:
	var collision_count := get_slide_collision_count()
	if collision_count <= 0:
		return Vector3.ZERO

	var crosswalk_context := _is_crosswalk_route_context()
	var best_dir := Vector3.ZERO
	var best_score := INF
	var candidates: Array[Vector3] = []
	for i in range(collision_count):
		var collision := get_slide_collision(i)
		if collision == null:
			continue
		var normal := collision.get_normal()
		normal.y = 0.0
		if normal.length_squared() <= 0.0001:
			continue
		normal = normal.normalized()

		var tangent_a := Vector3(-normal.z, 0.0, normal.x)
		var tangent_b := -tangent_a
		for candidate in [tangent_a, tangent_b]:
			if candidate.length_squared() <= 0.0001:
				continue
			_append_surface_candidate(candidates, candidate)
			_append_surface_candidate(candidates, _blend_move_direction(preferred_dir, candidate, 0.42))

	_append_surface_candidate(candidates, _rotate_planar_direction(preferred_dir, 35.0))
	_append_surface_candidate(candidates, _rotate_planar_direction(preferred_dir, -35.0))
	_append_surface_candidate(candidates, _rotate_planar_direction(preferred_dir, 62.0))
	_append_surface_candidate(candidates, _rotate_planar_direction(preferred_dir, -62.0))

	for candidate in candidates:
		if not crosswalk_context and not _is_move_surface_allowed(candidate, false):
			continue
		var score := _score_slide_escape_direction(candidate, preferred_dir, crosswalk_context)
		if score < best_score:
			best_score = score
			best_dir = candidate

	return best_dir.normalized() if best_dir != Vector3.ZERO else Vector3.ZERO

func _is_slide_escape_direction_viable(candidate: Vector3) -> bool:
	var planar_candidate := candidate
	planar_candidate.y = 0.0
	if planar_candidate.length_squared() <= 0.0001:
		return false
	var crosswalk_context := _is_crosswalk_route_context()
	if not crosswalk_context and not _is_move_surface_allowed(planar_candidate, false):
		return false
	if _agent == null or _agent.obstacle_avoidance == null:
		return true
	return _agent.obstacle_avoidance.score_move_direction(self, planar_candidate, crosswalk_context) < 1000.0

func _score_slide_escape_direction(candidate: Vector3, preferred_dir: Vector3, crosswalk_context: bool) -> float:
	var planar_candidate := candidate
	planar_candidate.y = 0.0
	if planar_candidate.length_squared() <= 0.0001:
		return INF
	planar_candidate = planar_candidate.normalized()

	var score := _score_direction(planar_candidate)
	if _agent != null and _agent.obstacle_avoidance != null:
		score = _agent.obstacle_avoidance.score_move_direction(self, planar_candidate, crosswalk_context)
	if planar_candidate.dot(preferred_dir) < -0.35:
		score += 2.5
	elif planar_candidate.dot(preferred_dir) < 0.15:
		score += 0.3
	return score

func _ray_move_direction(ray: RayCast3D) -> Vector3:
	if ray == null:
		return Vector3.ZERO
	var local_target := ray.target_position
	var world_target := ray.to_global(local_target)
	var dir := world_target - ray.global_position
	dir.y = 0.0
	if dir.length_squared() <= 0.0001:
		return Vector3.ZERO
	return dir.normalized()

func _score_direction(dir: Vector3) -> float:
	var projected := global_position + dir * obstacle_side_probe_length
	projected.y = _travel_target.y
	return projected.distance_to(_travel_target)

func _blend_move_direction(preferred_dir: Vector3, avoid_dir: Vector3, weight: float = -1.0) -> Vector3:
	var effective_weight := obstacle_turn_weight if weight < 0.0 else weight
	var blended := preferred_dir + avoid_dir * effective_weight
	blended.y = 0.0
	if blended.length_squared() <= 0.0001:
		return avoid_dir
	return blended.normalized()

func _update_stuck_state(delta: float) -> void:
	if _surface_guard_log_cooldown_left > 0.0:
		_surface_guard_log_cooldown_left = maxf(_surface_guard_log_cooldown_left - delta, 0.0)
	if _stuck_slide_hold_left > 0.0:
		_stuck_slide_hold_left = maxf(_stuck_slide_hold_left - delta, 0.0)
		if _stuck_slide_hold_left <= 0.0:
			_stuck_slide_hold_dir = Vector3.ZERO
	if _stuck_jump_cooldown_left > 0.0:
		_stuck_jump_cooldown_left = maxf(_stuck_jump_cooldown_left - delta, 0.0)
	if _stuck_jump_hold_left > 0.0:
		_stuck_jump_hold_left = maxf(_stuck_jump_hold_left - delta, 0.0)
		if _stuck_jump_hold_left <= 0.0:
			_stuck_jump_hold_dir = Vector3.ZERO
	if _floor_snap_suppress_left > 0.0:
		_floor_snap_suppress_left = maxf(_floor_snap_suppress_left - delta, 0.0)
		floor_snap_length = 0.0
	else:
		floor_snap_length = floor_snap_distance

	var hotspot_label := _get_stuck_hotspot_label()
	if hotspot_label.is_empty():
		_stuck_hotspot_label = ""
		_stuck_hotspot_time = 0.0
	elif hotspot_label == _stuck_hotspot_label:
		_stuck_hotspot_time += delta
	else:
		_stuck_hotspot_label = hotspot_label
		_stuck_hotspot_time = delta

	var moved := global_position.distance_to(_last_move_position)
	var reference_target := _get_stuck_reference_target()
	var previous_target_delta := reference_target - _last_move_position
	previous_target_delta.y = 0.0
	var current_target_delta := reference_target - global_position
	current_target_delta.y = 0.0
	var target_progress := previous_target_delta.length() - current_target_delta.length()
	var hotspot_persistent := _stuck_hotspot_time >= obstacle_stuck_hotspot_confirm_sec
	var has_low_movement := moved <= obstacle_stuck_distance
	var has_low_progress := _is_travelling and target_progress <= obstacle_stuck_progress_distance
	var should_count_direct_progress_stall := has_low_progress \
		and current_target_delta.length() > maxf(final_arrival_distance, 0.35) \
		and (_click_move_mode_enabled or _travel_target_building == null)
	if _current_speed > 0.2 and (
		has_low_movement
		or (hotspot_persistent and has_low_progress)
		or should_count_direct_progress_stall
	):
		_stuck_timer += delta
	else:
		_stuck_timer = 0.0
		_stuck_slide_hold_dir = Vector3.ZERO
		_stuck_slide_hold_left = 0.0
		if is_on_floor():
			_stuck_jump_hold_dir = Vector3.ZERO
			_stuck_jump_hold_left = 0.0
	_last_move_position = global_position

func _update_trace_navigation_state(reason: String, desired_dir: Vector3, move_dir: Vector3) -> void:
	_trace_last_decision_reason = reason
	_trace_last_desired_dir = desired_dir
	_trace_last_move_dir = move_dir

func _update_trace_obstacle_hits() -> void:
	_trace_last_forward_hit = _trace_describe_ray_hit(_obstacle_ray_forward)
	_trace_last_down_hit = _trace_describe_ray_hit(_obstacle_ray_down)
	_trace_last_left_hit = _trace_describe_ray_hit(_obstacle_ray_left)
	_trace_last_right_hit = _trace_describe_ray_hit(_obstacle_ray_right)
	_update_congestion_debug_label()

func _update_congestion_debug_label() -> void:
	for candidate in [_trace_last_forward_hit, _trace_last_down_hit, _trace_last_left_hit, _trace_last_right_hit]:
		if candidate != "clear" and candidate != "off":
			_debug_last_blocking_area = candidate
			return
	_debug_last_blocking_area = "-"

func _get_stuck_reference_target() -> Vector3:
	if _is_travelling:
		return _get_waypoint_move_target()
	return global_position

func _get_stuck_hotspot_label() -> String:
	if _is_blocking_hotspot_ray(_obstacle_ray_forward):
		return _trace_collider_label(_obstacle_ray_forward.get_collider())
	if _is_blocking_hotspot_ray(_obstacle_ray_down, true):
		return _trace_collider_label(_obstacle_ray_down.get_collider())
	if _is_blocking_hotspot_ray(_obstacle_ray_left):
		return _trace_collider_label(_obstacle_ray_left.get_collider())
	if _is_blocking_hotspot_ray(_obstacle_ray_right):
		return _trace_collider_label(_obstacle_ray_right.get_collider())
	return ""

func _is_blocking_hotspot_ray(ray: RayCast3D, require_low_obstacle: bool = false) -> bool:
	if _agent == null or _agent.obstacle_avoidance == null:
		return false
	return _agent.obstacle_avoidance.is_blocking_hotspot_ray(self, ray, require_low_obstacle)

func _trace_describe_ray_hit(ray: RayCast3D) -> String:
	if _agent == null or _agent.obstacle_avoidance == null:
		return "off"
	return _agent.obstacle_avoidance.describe_ray_hit(self, ray)

func _get_debug_action_label() -> String:
	if current_action != null:
		return current_action.label
	if _manual_control_enabled:
		return "ManualControl"
	if _click_move_mode_enabled:
		return "ClickMove" if _is_travelling else "ClickMoveIdle"
	if _is_travelling:
		return "Travel"
	return "idle"

func _trace_collider_label(collider: Variant) -> String:
	if collider is Node:
		var node := collider as Node
		if node.is_inside_tree():
			return str(node.get_path())
		return node.name
	return str(collider)

func _trace_relative_label(direction: Vector3) -> String:
	if direction.length_squared() <= 0.0001:
		return "none"
	var local_dir := global_transform.basis.inverse() * direction
	if absf(local_dir.x) > absf(local_dir.z):
		return "right" if local_dir.x > 0.0 else "left"
	return "back" if local_dir.z > 0.0 else "forward"

func _trace_fmt_vec3(value: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [value.x, value.y, value.z]

func get_trace_debug_summary() -> String:
	var action_label := _get_debug_action_label()
	var location_label := current_location.get_display_name() if current_location != null else "travelling"
	var inside_label := _inside_building.get_display_name() if _inside_building != null else "-"
	var travel_building_label := _travel_target_building.get_display_name() if _travel_target_building != null else "-"
	var target_label := _trace_fmt_vec3(_travel_target) if _is_travelling else "-"
	var waypoint_label := "-"
	if _is_travelling and not _travel_route.is_empty():
		waypoint_label = "%d/%d" % [_travel_route_index, _travel_route.size() - 1]

	return "citizen=%s pos=%s vel=%s speed=%.2f action=%s location=%s inside=%s travel_to=%s on_floor=%s travelling=%s target=%s waypoint=%s decision=%s desired=%s move=%s seen[fwd=%s | down=%s | left=%s | right=%s] crowd[repath=%d stuck_slide=%d jump=%d hotspot=%s]" % [
		citizen_name,
		_trace_fmt_vec3(global_position),
		_trace_fmt_vec3(velocity),
		_current_speed,
		action_label,
		location_label,
		inside_label,
		travel_building_label,
		str(is_on_floor()),
		str(_is_travelling),
		target_label,
		waypoint_label,
		_trace_last_decision_reason,
		_trace_fmt_vec3(_trace_last_desired_dir),
		_trace_fmt_vec3(_trace_last_move_dir),
		_trace_last_forward_hit,
		_trace_last_down_hit,
		_trace_last_left_hit,
		_trace_last_right_hit,
		_debug_repath_count,
		_debug_stuck_slide_count,
		_debug_stuck_jump_count,
		"%s ground=%s" % [_debug_last_blocking_area, _trace_last_surface_probe]
	]
# Called from main.gd when selection/debug panel changes.
func set_selected(selected: bool) -> void:
	_selection_active = selected
	if _mesh_instance == null:
		return
	if selected:
		_mesh_instance.material_overlay = _highlight_material
	else:
		_mesh_instance.material_overlay = _original_material


# Selection entrypoint called from main.gd
# NOTE: _set() is not called for exported vars in this case.
# Variable ist schon definiert, daher greift der _set-Fallback nie.
# Solution: main.gd calls select(panel) directly.
func select(panel) -> void:
	debug_panel = panel
	set_selected(panel != null)


# Auto-resolve optional node references
func _auto_resolve_refs() -> void:
	_get_query_world()
	if home_path != NodePath():
		home = get_node_or_null(home_path) as ResidentialBuilding
	if restaurant_path != NodePath():
		favorite_restaurant = get_node_or_null(restaurant_path) as Restaurant
	if supermarket_path != NodePath():
		favorite_supermarket = get_node_or_null(supermarket_path) as Supermarket
	if shop_path != NodePath():
		favorite_shop = get_node_or_null(shop_path) as Shop
	if cinema_path != NodePath():
		favorite_cinema = get_node_or_null(cinema_path) as Cinema
	if park_path != NodePath():
		favorite_park = get_node_or_null(park_path) as Building

	if home == null:
		home = _find_first_residential_building(global_position)
		if home:
			SimLogger.log("[Citizen %s] Auto-found home: %s" % [citizen_name, _building_label(home)])

	if home != null:
		var added := home.add_tenant(self)
		if added:
			SimLogger.log("[Citizen %s] Registered as tenant at: %s" % [citizen_name, _building_label(home)])
		else:
			var full_home := home
			home = _find_first_residential_building(global_position)
			if home != null and home != full_home and home.add_tenant(self):
				SimLogger.log("[Citizen %s] Home %s was full, reassigned to: %s" % [
					citizen_name,
					_building_label(full_home),
					_building_label(home)
				])
				SimLogger.log("[Citizen %s] Registered as tenant at: %s" % [citizen_name, _building_label(home)])
			else:
				home = null
				SimLogger.log("[Citizen %s] WARNING: No residential building with free tenant slot found." % citizen_name)

	var origin := home.get_entrance_pos() if home else global_position
	if home != null and _world_ref != null and _world_ref.has_method("get_pedestrian_access_point"):
		origin = _world_ref.get_pedestrian_access_point(origin, home)

	if favorite_restaurant == null:
		favorite_restaurant = _find_nearest_restaurant(origin, false)
		if favorite_restaurant:
			SimLogger.log("[Citizen %s] Auto-found restaurant: %s" % [citizen_name, _building_label(favorite_restaurant)])

	if favorite_supermarket == null:
		favorite_supermarket = _find_nearest_supermarket(origin, false)
		if favorite_supermarket:
			SimLogger.log("[Citizen %s] Auto-found supermarket: %s" % [citizen_name, _building_label(favorite_supermarket)])

	if favorite_shop == null:
		favorite_shop = _find_nearest_shop(origin, false)
		if favorite_shop:
			SimLogger.log("[Citizen %s] Auto-found shop: %s" % [citizen_name, _building_label(favorite_shop)])

	if favorite_cinema == null:
		favorite_cinema = _find_nearest_cinema(origin, false)
		if favorite_cinema:
			SimLogger.log("[Citizen %s] Auto-found cinema: %s" % [citizen_name, _building_label(favorite_cinema)])

	if favorite_park == null:
		favorite_park = _find_nearest_park(origin)
		if favorite_park:
			SimLogger.log("[Citizen %s] Auto-found park: %s" % [citizen_name, _building_label(favorite_park)])

	_try_find_job_once()

	if home:
		current_location = home
		set_position_grounded(origin)
		enter_building(home, _world_ref, false)

func _try_find_job_once() -> void:
	var from_pos := _get_job_search_origin()
	if job == null:
		_try_retarget_job_to_city_need(from_pos)
		if job == null:
			return
	elif job.workplace == null:
		_try_retarget_job_to_city_need(from_pos)

	if job == null or job.workplace != null:
		return
	var found_reachable_workplace := false
	if _world_ref != null:
		job.workplace = _world_ref.find_best_workplace_for_job(from_pos, job, self)
		found_reachable_workplace = job.workplace != null

	if job.workplace == null and _world_ref == null:
		var root := get_tree().current_scene
		job.resolve_nearest(root, from_pos)
		if job.workplace != null and not found_reachable_workplace:
			debug_log_once_per_day(
				"job_fallback_%s" % job.title,
				"Fallback workplace selected without world reachability check: %s for %s (%s)." % [
					_building_label(job.workplace),
					job.title,
					get_job_debug_summary()
				]
			)

	if job.workplace == null:
		debug_log_once_per_day(
			"job_search_none_%s" % job.title,
			"No reachable open workplace found for %s (service=%s, reqEdu=%d, from=%s)." % [
				job.title,
				job.workplace_service_type if job.workplace_service_type != "" else "any",
				job.required_education_level,
				_building_label(home)
			]
		)
		return

	if not job.meets_requirements(self):
		var blocked_workplace := job.workplace
		_maybe_log_job_requirement_notice(blocked_workplace)
		job.workplace = null
		return

	var hired := job.try_get_employed(self)
	if hired:
		_reset_job_notice_state()
		SimLogger.log("[Citizen %s] Employed at: %s | %s" % [
			citizen_name,
			_building_label(job.workplace),
			get_job_debug_summary()
		])
	else:
		var full_workplace := job.workplace
		job.workplace = null
		_maybe_log_workplace_full_notice(full_workplace)

func set_world_ref(world: World) -> void:
	if world == null:
		return
	_world_ref = world
	_ground_fallback_y = world.get_ground_fallback_y()
	_connect_time_signals(world)
	if world.citizens.has(self) and world.has_method("notify_citizen_lod_changed"):
		world.notify_citizen_lod_changed(self)

func _get_query_world() -> World:
	if _agent != null and _agent.query_resolver != null:
		return _agent.query_resolver.resolve_query_world(self)
	if _world_ref != null and is_instance_valid(_world_ref):
		return _world_ref
	_world_ref = null
	return null

func _resolve_world_ref_from_tree() -> World:
	if _agent != null and _agent.query_resolver != null:
		return _agent.query_resolver.resolve_world_ref_from_tree(self)
	return null

func _connect_time_signals(world: World) -> void:
	if world == null or world.time == null:
		return
	if not world.time.hour_changed.is_connected(_on_hour_changed):
		world.time.hour_changed.connect(_on_hour_changed)


func _on_hour_changed(new_hour: int) -> void:
	if new_hour < 6 or new_hour > 20:
		return
	_try_find_job_once()

func notify_job_lost(closed_building: Building = null, reason: String = "") -> void:
	if job == null or job.workplace != null:
		return
	_reset_job_notice_state()
	if reason != "":
		debug_log("Searching for a new job after losing %s (%s)." % [
			_building_label(closed_building),
			reason
		])
	_try_find_job_once()

func _update_debug(world: World, h_delta: float) -> void:
	if not debug_panel:
		return

	if abs(h_delta) >= 0.5:
		var reason := ""
		if needs.hunger >= 80.0:   reason += " [starving]"
		if needs.energy <= 10.0:   reason += " [exhausted]"
		if needs.fun <= 0.0:       reason += " [depressed]"
		if h_delta > 0:            reason = " [recovering]"
		SimLogger.log("[%s] Health %s%.1f -> %.1f%s" % [
			citizen_name,
			"+" if h_delta > 0 else "",
			h_delta, needs.health, reason
		])

	var debug_route := get_debug_travel_route_points()
	var travel_state := "idle"
	var path_start := "-"
	var path_end := "-"
	var travel_target_building := get_debug_travel_target_building()
	var travel_target_label := _building_label(travel_target_building) if travel_target_building != null else "-"
	var remaining_travel_distance := get_remaining_travel_distance() if (_is_travelling or travel_target_building != null) else 0.0
	var remaining_travel_label := "%.1f m" % remaining_travel_distance if remaining_travel_distance > 0.05 else "-"
	var coarse_eta_minutes := get_debug_coarse_eta_minutes(world)
	var coarse_eta_label := "%d min" % coarse_eta_minutes if coarse_eta_minutes > 0 else "-"
	var planar_velocity := Vector2(velocity.x, velocity.z).length()
	if _is_travelling:
		if simulation_lod_tier == "coarse":
			travel_state = "coarse_travel"
		elif _trace_last_decision_reason == "surface_guard_stop" or _surface_guard_stop_time > 0.05:
			travel_state = "blocked"
		elif planar_velocity > 0.05 or _current_speed > 0.05:
			travel_state = "moving"
		else:
			travel_state = "pathing"
	elif _debug_last_travel_failed and debug_route.size() >= 2:
		travel_state = "route_failed"
	elif debug_route.size() >= 2:
		travel_state = "last_route"

	if debug_route.size() >= 2:
		var route_start: Vector3 = debug_route[0]
		var route_end: Vector3 = debug_route[debug_route.size() - 1]
		path_start = "%d, %d, %d" % [route_start.x, route_start.y, route_start.z]
		path_end = "%d, %d, %d" % [route_end.x, route_end.y, route_end.z]

	debug_panel.update_debug({
		"Citizen"  : citizen_name,
		"Location" : current_location.building_name if current_location else "travelling...",
		"Action"   : current_action.label if current_action else "idle",
		"----------": "",
		"Hunger"   : "%.1f / 100  (eat@50)" % needs.hunger,
		"Energy"   : "%.1f / 100  (sleep@80)" % needs.energy,
		"Fun"      : "%.1f / 100  (relax@30)" % needs.fun,
		"Health"   : "%.1f / 100" % needs.health,
		"----------2": "",
		"Money"    : "%d EUR" % wallet.balance,
		"Groceries": str(home_food_stock),
		"Education": "%d" % education_level,
		"Workplace": job.workplace.building_name if (job and job.workplace) else "unemployed",
		"WorkToday": "%d / %d min" % [
			work_minutes_today,
			int(job.shift_hours * 60) if job else 0
		],
		"JobReqEdu": "%d" % (job.required_education_level if job else 0),
		"Motivation": "%.2f" % work_motivation,
		"ParkInterest": "%.2f" % park_interest,
		"Position": "%d, %d, %d " % [global_position.x, global_position.y, global_position.z],
		"LOD": get_debug_lod_label(world),
		"Conversation": get_runtime_conversation_label(),
		"Commitments": "%d" % get_active_lod_commitments(world).size(),
		"NavMode": "cheap_path_follow" if _is_using_cheap_path_follow() else ("path_only" if not local_navigation_raycast_checks_enabled else "raycast_local"),
		"TravelState": travel_state,
		"TravelTarget": travel_target_label,
		"TravelRemain": remaining_travel_label,
		"CoarseETA": coarse_eta_label,
		"PathStart": path_start,
		"PathEnd": path_end,
	})

func _update_work_day(world: World) -> void:
	var today: int = world.time.day
	if _work_day_key != today:
		_work_day_key = today
		work_minutes_today = 0


func sim_tick(world: World) -> void:
	if not should_run_simulation_lod_tick(world):
		return
	_agent.sim_tick(self, world)

func plan_next_action(world: World) -> void:
	_agent.planner.plan_next_action(world, self)

func can_afford_restaurant(world: World) -> bool:
	if favorite_restaurant == null:
		return false
	var price: int = favorite_restaurant.meal_price
	if favorite_restaurant.has_method("get_meal_price"):
		price = int(favorite_restaurant.get_meal_price(world))
	return wallet.balance >= price

func can_afford_groceries(world: World) -> bool:
	if favorite_supermarket == null:
		return false
	var price: int = favorite_supermarket.grocery_price
	if favorite_supermarket.has_method("get_grocery_price"):
		price = int(favorite_supermarket.get_grocery_price(world))
	return wallet.balance >= price

func can_afford_shop_item(_world: World) -> bool:
	if favorite_shop == null:
		return false
	var price: int = favorite_shop.item_price
	if favorite_shop.has_method("get_item_price_quote"):
		price = int(favorite_shop.get_item_price_quote(1.0))
	return wallet.balance >= price + _get_fun_cash_reserve(_world)

func can_afford_cinema(_world: World) -> bool:
	if favorite_cinema == null:
		return false
	return wallet.balance >= favorite_cinema.ticket_price + _get_fun_cash_reserve(_world)

func _get_fun_cash_reserve(world: World) -> int:
	var reserve: int = 20
	if home != null:
		reserve = maxi(reserve, home.rent_per_day)
	if favorite_supermarket != null:
		var grocery_price: int = favorite_supermarket.grocery_price
		if favorite_supermarket.has_method("get_grocery_price"):
			grocery_price = int(favorite_supermarket.get_grocery_price(world))
		reserve += grocery_price
	elif favorite_restaurant != null:
		var meal_price: int = favorite_restaurant.meal_price
		if favorite_restaurant.has_method("get_meal_price"):
			meal_price = int(favorite_restaurant.get_meal_price(world))
		reserve += meal_price
	return reserve

func _find_first_residential_building(from_pos: Vector3 = Vector3.ZERO) -> ResidentialBuilding:
	if _agent != null and _agent.query_resolver != null:
		return _agent.query_resolver.find_first_residential_building(self, from_pos)
	return null


func _find_nearest_restaurant(from_pos: Vector3, require_open: bool = true) -> Restaurant:
	if _agent != null and _agent.query_resolver != null:
		return _agent.query_resolver.find_nearest_restaurant(self, from_pos, require_open)
	return null


func _find_nearest_supermarket(from_pos: Vector3, require_open: bool = true) -> Supermarket:
	if _agent != null and _agent.query_resolver != null:
		return _agent.query_resolver.find_nearest_supermarket(self, from_pos, require_open)
	return null


func _find_nearest_shop(from_pos: Vector3, require_open: bool = true) -> Shop:
	if _agent != null and _agent.query_resolver != null:
		return _agent.query_resolver.find_nearest_shop(self, from_pos, require_open)
	return null


func _find_nearest_cinema(from_pos: Vector3, require_open: bool = true) -> Cinema:
	if _agent != null and _agent.query_resolver != null:
		return _agent.query_resolver.find_nearest_cinema(self, from_pos, require_open)
	return null

func _find_nearest_university(from_pos: Vector3, require_open: bool = true) -> University:
	if _agent != null and _agent.query_resolver != null:
		return _agent.query_resolver.find_nearest_university(self, from_pos, require_open)
	return null

func _find_nearest_park(from_pos: Vector3) -> Building:
	if _agent != null and _agent.query_resolver != null:
		return _agent.query_resolver.find_nearest_park(self, from_pos)
	return null

func _find_best_tree_residential_building(from_pos: Vector3) -> ResidentialBuilding:
	if _agent != null and _agent.query_resolver != null:
		return _agent.query_resolver.find_best_tree_residential_building(self, from_pos)
	return null

func _find_nearest_tree_building(from_pos: Vector3, group_name: String, accept: Callable) -> Building:
	if _agent != null and _agent.query_resolver != null:
		return _agent.query_resolver.find_nearest_tree_building(self, from_pos, group_name, accept)
	return null

func debug_log(message: String) -> void:
	SimLogger.log("[Citizen %s] %s" % [citizen_name, message])

func debug_log_once_per_day(key: String, message: String) -> void:
	var today := _world_ref.world_day() if _world_ref != null else -1
	if _debug_once_day != today:
		_debug_once_day = today
		_debug_once_keys.clear()
	if _debug_once_keys.has(key):
		return
	_debug_once_keys[key] = true
	debug_log(message)

func get_job_debug_summary() -> String:
	if job == null:
		return "job=none"
	var workplace_label := "none"
	if job.workplace != null:
		workplace_label = _building_label(job.workplace)
	elif job.preferred_workplace != null:
		workplace_label = "target:%s" % _building_label(job.preferred_workplace)
	var service_type := job.workplace_service_type if job.workplace_service_type != "" else "any"
	return "job=%s reqEdu=%d/%d service=%s workplace=%s wage=%d shift=%02d+%dh worked=%dmin" % [
		job.title,
		education_level,
		job.required_education_level,
		service_type,
		workplace_label,
		job.wage_per_hour,
		job.start_hour,
		job.shift_hours,
		work_minutes_today
	]

func get_unemployment_debug_reason() -> String:
	if job == null:
		return "no assigned job"
	if job.workplace == null and not job.meets_requirements(self):
		var target_label := _building_label(job.preferred_workplace) if job.preferred_workplace != null else "no target workplace"
		return "education mismatch for %s (%d/%d) target=%s" % [
			job.title,
			education_level,
			job.required_education_level,
			target_label
		]
	if job.workplace == null:
		var preferred_label := _building_label(job.preferred_workplace) if job.preferred_workplace != null else "none"
		return "no workplace assigned for %s (service=%s target=%s)" % [
			job.title,
			job.workplace_service_type if job.workplace_service_type != "" else "any",
			preferred_label
		]
	return "employment status unclear"

func _get_job_search_origin() -> Vector3:
	var from_pos := home.get_entrance_pos() if home else (global_position if is_inside_tree() else position)
	if home != null and _world_ref != null and _world_ref.has_method("get_pedestrian_access_point"):
		from_pos = _world_ref.get_pedestrian_access_point(from_pos, home)
	return from_pos

func _try_retarget_job_to_city_need(from_pos: Vector3) -> bool:
	if _world_ref == null or not _world_ref.has_method("find_best_job_offer_for_citizen"):
		return false
	var allow_training := _find_nearest_university(from_pos, true) != null
	var offer: Dictionary = _world_ref.find_best_job_offer_for_citizen(from_pos, self, allow_training)
	if offer.is_empty():
		return false
	return _apply_job_offer(offer)

func _apply_job_offer(offer: Dictionary) -> bool:
	var building := offer.get("building", null) as Building
	var job_title := str(offer.get("title", ""))
	if building == null or job_title.is_empty():
		return false
	if job != null \
		and job.title == job_title \
		and job.preferred_workplace == building \
		and job.required_education_level == int(offer.get("required_education_level", job.required_education_level)):
		return false

	if job == null:
		job = Job.new()
		if _world_ref != null and _world_ref.has_method("register_job"):
			_world_ref.register_job(job)

	job.title = job_title
	job.wage_per_hour = int(offer.get("wage_per_hour", job.wage_per_hour))
	job.required_education_level = int(offer.get("required_education_level", job.required_education_level))
	job.workplace_service_type = ""
	job.workplace_name = ""
	var allowed_types_variant: Variant = offer.get("allowed_building_types", [])
	job.allowed_building_types = (allowed_types_variant as Array).duplicate() if allowed_types_variant is Array else []
	job.preferred_workplace = building
	job.workplace = null
	_reset_job_notice_state()

	var mode := "training" if education_level < job.required_education_level else "direct placement"
	debug_log_once_per_day(
		"job_retarget_%s_%s" % [job.title, building.get_display_name()],
		"Retargeted to %s at %s (%s, edu %d/%d)." % [
			job.title,
			building.get_display_name(),
			mode,
			education_level,
			job.required_education_level
		]
	)
	return true

func get_zero_pay_debug_reason() -> String:
	var action_label := _get_debug_action_label()
	var location_label := _building_label(current_location) if current_location != null else "travelling"
	return "%s action=%s location=%s" % [get_job_debug_summary(), action_label, location_label]

func is_building_temporarily_unreachable(building: Building, world: World = null) -> bool:
	if building == null:
		return false
	var active_world := world if world != null else _world_ref
	if active_world == null or active_world.time == null:
		return false
	var key := building.get_instance_id()
	if not _temporarily_unreachable_targets.has(key):
		return false
	var blocked_until := int(_temporarily_unreachable_targets.get(key, 0))
	if blocked_until <= _get_sim_total_minutes(active_world):
		_temporarily_unreachable_targets.erase(key)
		return false
	return true

func _get_building_temporarily_unreachable_remaining_minutes(building: Building, world: World = null) -> int:
	if not is_building_temporarily_unreachable(building, world):
		return 0
	var active_world := world if world != null else _world_ref
	if active_world == null:
		return 0
	var blocked_until := int(_temporarily_unreachable_targets.get(building.get_instance_id(), 0))
	return maxi(blocked_until - _get_sim_total_minutes(active_world), 0)

func prepare_go_to_target(target: Building, world: World) -> Building:
	if target == null:
		return null
	if not is_building_temporarily_unreachable(target, world):
		return target
	var replacement := _find_alternative_for_building(target, world)
	if replacement != null and replacement != target:
		_apply_building_target_replacement(target, replacement)
		debug_log("Retargeting from cooled-down %s to %s." % [
			_building_label(target),
			_building_label(replacement)
		])
		return replacement
	var remaining_minutes := _get_building_temporarily_unreachable_remaining_minutes(target, world)
	debug_log_once_per_day(
		"target_cooldown_%d" % target.get_instance_id(),
		"Skipping temporarily unreachable target %s (%d sim-min remaining)." % [
			_building_label(target),
			remaining_minutes
		]
	)
	return null

func handle_unreachable_target(target: Building, world: World, reason: String = "") -> Building:
	if target == null:
		return null
	_mark_building_temporarily_unreachable(target, world, reason)
	var replacement := _find_alternative_for_building(target, world)
	if replacement != null and replacement != target:
		_apply_building_target_replacement(target, replacement)
		debug_log("Retargeting from unreachable %s to %s (%s)." % [
			_building_label(target),
			_building_label(replacement),
			reason if reason != "" else "stuck"
		])
		return replacement
	debug_log("Aborting unreachable target %s (%s)." % [
		_building_label(target),
		reason if reason != "" else "stuck"
	])
	return null

func _mark_building_temporarily_unreachable(target: Building, world: World, reason: String = "") -> void:
	if target == null:
		return
	var active_world := world if world != null else _world_ref
	if active_world == null or active_world.time == null:
		return
	var until_minute := _get_sim_total_minutes(active_world) + maxi(unreachable_target_cooldown_minutes, 1)
	var key := target.get_instance_id()
	var previous_until := int(_temporarily_unreachable_targets.get(key, 0))
	if previous_until >= until_minute:
		return
	_temporarily_unreachable_targets[key] = until_minute
	debug_log("Marked %s as temporarily unreachable for %d sim-min (%s)." % [
		_building_label(target),
		unreachable_target_cooldown_minutes,
		reason if reason != "" else "navigation failure"
	])

func _get_sim_total_minutes(world: World = null) -> int:
	var active_world := world if world != null else _world_ref
	if active_world == null or active_world.time == null:
		return 0
	return maxi(active_world.time.day - 1, 0) * 24 * 60 + active_world.time.minutes_total

func _get_retarget_origin(world: World) -> Vector3:
	if current_location != null:
		var origin := current_location.get_entrance_pos()
		if world != null and world.has_method("get_pedestrian_access_point"):
			return world.get_pedestrian_access_point(origin, current_location)
		return origin
	if _inside_building != null:
		return _get_building_access_pos(_inside_building, world)
	return global_position if is_inside_tree() else position

func _find_alternative_for_building(target: Building, world: World) -> Building:
	var from_pos := _get_retarget_origin(world)
	if target == null:
		return null
	if target == home:
		var alt_home := _find_first_residential_building(from_pos)
		return alt_home if alt_home != target else null
	if target == favorite_restaurant or target is Restaurant:
		var alt_restaurant := _find_nearest_restaurant(from_pos, true)
		return alt_restaurant if alt_restaurant != target else null
	if target == favorite_supermarket or target is Supermarket:
		var alt_market := _find_nearest_supermarket(from_pos, true)
		return alt_market if alt_market != target else null
	if target == favorite_shop or (target is Shop and target is not Supermarket):
		var alt_shop := _find_nearest_shop(from_pos, true)
		return alt_shop if alt_shop != target else null
	if target == favorite_cinema or target is Cinema:
		var alt_cinema := _find_nearest_cinema(from_pos, true)
		return alt_cinema if alt_cinema != target else null
	if target == favorite_park or target.is_in_group("parks"):
		var alt_park := _find_nearest_park(from_pos)
		return alt_park if alt_park != target else null
	if target is University:
		var alt_uni := _find_nearest_university(from_pos, true)
		return alt_uni if alt_uni != target else null
	if job != null and job.workplace == target:
		job.workplace = null
		_try_find_job_once()
		return job.workplace if job != null and job.workplace != target else null
	if world != null and world.has_method("find_nearest_building_with_service"):
		var alt_service := world.find_nearest_building_with_service(from_pos, target.get_service_type(), true, self)
		return alt_service if alt_service != target else null
	return null

func _apply_building_target_replacement(original: Building, replacement: Building) -> void:
	if original == null or replacement == null:
		return
	if home == original and replacement is ResidentialBuilding:
		home = replacement as ResidentialBuilding
	if favorite_restaurant == original and replacement is Restaurant:
		favorite_restaurant = replacement as Restaurant
	if favorite_supermarket == original and replacement is Supermarket:
		favorite_supermarket = replacement as Supermarket
	if favorite_shop == original and replacement is Shop:
		favorite_shop = replacement as Shop
	if favorite_cinema == original and replacement is Cinema:
		favorite_cinema = replacement as Cinema
	if favorite_park == original:
		favorite_park = replacement
	if job != null:
		if job.workplace == original:
			job.workplace = replacement
		if job.preferred_workplace == original:
			job.preferred_workplace = replacement


func start_action(a: Action, world: World) -> void:
	_start_action(a, world)

func _start_action(a: Action, world: World) -> void:
	clear_rest_pose(true)
	if a is GoToBuildingAction and is_inside_building():
		exit_current_building(world)
	elif a is GoToBuildingAction and current_location != null:
		leave_current_location(world)

	current_action = a
	current_action.start(world, self)

	var h := world.time.get_hour()
	var m := world.time.get_minute()
	var w := world.time.get_weekday_name()
	var loc = _building_label(current_location) if current_location else "travelling"

	if a is GoToBuildingAction:
		var target := (a as GoToBuildingAction).target
		if target != null:
			loc = "-> " + _building_label(target)

	var health_icon := ""
	if needs.health < 50.0:    health_icon = " [LOW]"
	elif needs.health < 75.0:  health_icon = " [WARN]"

	SimLogger.log("[%s] %02d:%02d (%s) | %-10s | H:%.0f E:%.0f F:%.0f HP:%.0f%s | $%d | at=%s" % [
		citizen_name, h, m, w,
		a.label,
		needs.hunger, needs.energy, needs.fun, needs.health, health_icon,
		wallet.balance,
		loc
	])


func pay_rent(world: World, landlord: ResidentialBuilding, amount: int) -> void:
	if landlord == null:
		return
	var before := wallet.balance
	var success := world.economy.transfer(wallet, landlord.account, amount)
	if success:
		SimLogger.log("[%s] Rent paid: %d EUR (balance: %d -> %d)" % [
			citizen_name, amount, before, wallet.balance
		])
	else:
		SimLogger.log("[%s] Could not pay rent! Need %d EUR, have %d EUR" % [
			citizen_name, amount, wallet.balance
		])

func _building_label(building: Building) -> String:
	if building == null:
		return "Unknown"
	return building.get_display_name()

func _maybe_log_job_requirement_notice(blocked_workplace: Building = null) -> void:
	if job == null:
		return
	if _last_job_requirement_notice_level == education_level and _last_job_requirement_notice_title == job.title:
		return
	_last_job_requirement_notice_level = education_level
	_last_job_requirement_notice_title = job.title
	var study_origin := home.get_entrance_pos() if home else global_position
	if home != null and _world_ref != null and _world_ref.has_method("get_pedestrian_access_point"):
		study_origin = _world_ref.get_pedestrian_access_point(study_origin, home)
	var nearest_uni := _find_nearest_university(study_origin, false)
	var study_hint := " No reachable university available right now."
	if nearest_uni != null:
		study_hint = " Study option: %s (publicly funded)." % [
			nearest_uni.get_display_name(),
		]
	debug_log("Needs education level %d for job %s (current %d). Candidate workplace: %s.%s" % [
		job.required_education_level,
		job.title,
		education_level,
		_building_label(blocked_workplace),
		study_hint
	])

func _maybe_log_workplace_full_notice(workplace: Building = null) -> void:
	var today := _world_ref.world_day() if _world_ref != null else -1
	if _last_workplace_full_notice_day == today:
		return
	_last_workplace_full_notice_day = today
	var worker_count := workplace.workers.size() if workplace != null else 0
	var capacity := workplace.job_capacity if workplace != null else 0
	debug_log("Workplace full at %s (%d/%d workers), will retry later." % [
		_building_label(workplace),
		worker_count,
		capacity
	])

func _reset_job_notice_state() -> void:
	_last_job_requirement_notice_level = -1
	_last_job_requirement_notice_title = ""
	_last_workplace_full_notice_day = -1
