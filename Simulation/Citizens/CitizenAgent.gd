extends RefCounted
class_name CitizenAgent

const CrosswalkAwarenessScript = preload("res://Simulation/Citizens/CitizenCrosswalkAwareness.gd")
const NeedsComponentScript = preload("res://Simulation/Citizens/CitizenNeedsComponent.gd")
const LocomotionScript = preload("res://Simulation/Citizens/CitizenLocomotion.gd")
const ObstacleAvoidanceScript = preload("res://Simulation/Citizens/CitizenObstacleAvoidance.gd")
const PlannerScript = preload("res://Simulation/Citizens/CitizenPlanner.gd")
const QueryResolverScript = preload("res://Simulation/Citizens/CitizenQueryResolver.gd")
const GoToBuildingActionScript = preload("res://Actions/GoToBuildingAction.gd")
const RelaxAtBenchActionScript = preload("res://Actions/RelaxAtBenchAction.gd")
const RelaxAtParkActionScript = preload("res://Actions/RelaxAtParkAction.gd")
const LOD_CONFIG_PATH := "res://config/citizen_simulation_lod.json"

static var _coarse_travel_config_loaded: bool = false
static var _coarse_travel_config: Dictionary = {}

var needs_component = NeedsComponentScript.new()
var locomotion = LocomotionScript.new()
var obstacle_avoidance = ObstacleAvoidanceScript.new()
var crosswalk_awareness = CrosswalkAwarenessScript.new()
var planner = PlannerScript.new()
var query_resolver = QueryResolverScript.new()

func setup(citizen) -> void:
	if citizen == null:
		return
	locomotion.setup(citizen)

func physics_step(citizen, delta: float, world) -> void:
	if _should_pause_for_player_dialog(citizen):
		citizen._current_speed = 0.0
		citizen.velocity.x = 0.0
		citizen.velocity.z = 0.0
		if citizen.has_method("_update_trace_navigation_state"):
			citizen._update_trace_navigation_state("dialog_pause", Vector3.ZERO, Vector3.ZERO)
		return
	locomotion.physics_step(citizen, delta, world)

func sim_tick(citizen, world) -> void:
	if citizen == null or world == null:
		return
	if citizen._world_ref == null:
		citizen.set_world_ref(world)
	if citizen.has_method("is_autonomous_simulation_enabled") \
		and not citizen.is_autonomous_simulation_enabled() \
		and not citizen.is_manual_control_enabled() \
		and not citizen.is_click_move_mode_enabled():
		return
	if citizen.has_method("get_simulation_lod_tier") and citizen.get_simulation_lod_tier() == "coarse":
		_sim_tick_coarse(citizen, world)
		return

	var h_delta := needs_component.tick_needs(world, citizen)
	citizen._update_work_day(world)
	citizen._update_debug(world, h_delta)
	if citizen.has_method("is_manual_control_enabled") and citizen.is_manual_control_enabled():
		return
	if citizen.has_method("is_click_move_mode_enabled") and citizen.is_click_move_mode_enabled():
		return
	_clear_stale_rest_pose(citizen, world)
	if _should_pause_for_player_dialog(citizen):
		return

	if citizen.current_action != null:
		_tick_current_action(citizen, world)
		return

	if citizen.decision_cooldown_left > 0:
		citizen.decision_cooldown_left -= world.minutes_per_tick
		if citizen.decision_cooldown_left > 0:
			return

	planner.plan_next_action(world, citizen)
	citizen.decision_cooldown_left = _roll_decision_cooldown_minutes(citizen, world)

func _tick_current_action(citizen, world) -> void:
	var action = citizen.current_action
	if action == null:
		return
	action.tick(world, citizen, world.minutes_per_tick)
	if citizen.current_action != action:
		return
	if not action.is_done():
		return
	action.finish(world, citizen)
	if citizen.current_action == action:
		citizen.current_action = null
	_clear_stale_rest_pose(citizen, world)

func _clear_stale_rest_pose(citizen, world) -> void:
	if citizen == null or not citizen.has_method("has_active_rest_pose") or not citizen.has_active_rest_pose():
		return
	if citizen.current_action is RelaxAtParkActionScript or citizen.current_action is RelaxAtBenchActionScript:
		return
	citizen.clear_rest_pose(true)
	if citizen.has_method("release_reserved_benches"):
		citizen.release_reserved_benches(world)

func _sim_tick_coarse(citizen, world) -> void:
	var h_delta := needs_component.tick_needs(world, citizen)
	citizen._update_work_day(world)
	citizen._update_debug(world, h_delta)
	if citizen.has_method("is_manual_control_enabled") and citizen.is_manual_control_enabled():
		return
	if citizen.has_method("is_click_move_mode_enabled") and citizen.is_click_move_mode_enabled():
		return
	_clear_stale_rest_pose(citizen, world)
	if _should_pause_for_player_dialog(citizen):
		return

	if citizen.current_action != null:
		if citizen.current_action is GoToBuildingActionScript \
			or (citizen.has_method("is_travelling") and citizen.is_travelling()):
			_tick_coarse_travel_action(citizen, world)
		else:
			_tick_current_action(citizen, world)
		return

	if citizen.has_method("is_travelling") and citizen.is_travelling():
		_advance_coarse_travel(citizen, world)
		return

	if citizen.decision_cooldown_left > 0:
		citizen.decision_cooldown_left -= world.minutes_per_tick
		if citizen.decision_cooldown_left > 0:
			return

	planner.plan_next_action(world, citizen)
	citizen.decision_cooldown_left = _roll_decision_cooldown_minutes(citizen, world)

func _roll_decision_cooldown_minutes(citizen, world) -> int:
	if citizen == null:
		return 0
	var min_minutes: int = int(citizen.decision_cooldown_range_min)
	var max_minutes: int = int(citizen.decision_cooldown_range_max)
	if citizen.has_method("get_simulation_lod_decision_cooldown_range_minutes"):
		var range: Vector2i = citizen.get_simulation_lod_decision_cooldown_range_minutes(world)
		min_minutes = range.x
		max_minutes = range.y
	if max_minutes < min_minutes:
		max_minutes = min_minutes
	return randi_range(min_minutes, max_minutes)

func _tick_coarse_travel_action(citizen, world) -> void:
	var action = citizen.current_action
	if action == null:
		return
	_advance_coarse_travel(citizen, world)
	action.tick(world, citizen, world.minutes_per_tick)
	if citizen.current_action != action:
		return
	if not action.is_done():
		return
	action.finish(world, citizen)
	if citizen.current_action == action:
		citizen.current_action = null
	_clear_stale_rest_pose(citizen, world)

func _advance_coarse_travel(citizen, world) -> void:
	if citizen == null or world == null:
		return
	if not citizen.has_method("advance_coarse_travel_by_distance"):
		return
	var travel_distance := _get_coarse_travel_distance_for_tick(citizen, world)
	if travel_distance <= 0.0:
		return
	citizen.advance_coarse_travel_by_distance(travel_distance)

func estimate_coarse_travel_minutes(citizen, world, remaining_distance: float = -1.0) -> int:
	if citizen == null or world == null:
		return 0
	var resolved_distance := remaining_distance
	if resolved_distance < 0.0 and citizen.has_method("get_remaining_travel_distance"):
		resolved_distance = float(citizen.get_remaining_travel_distance())
	if resolved_distance <= 0.05:
		return 0

	var distance_per_tick := _get_coarse_travel_distance_for_tick(citizen, world)
	if distance_per_tick <= 0.001:
		return int(_get_coarse_travel_config().get("fallback_eta_minutes", 20))

	var eta_ticks := ceili(resolved_distance / distance_per_tick)
	var eta_minutes := eta_ticks * maxi(world.minutes_per_tick, 1)
	var minimum_eta := int(_get_coarse_travel_config().get("minimum_eta_minutes", 2))
	return maxi(eta_minutes, minimum_eta)

func _get_coarse_travel_distance_for_tick(citizen, world) -> float:
	var config := _get_coarse_travel_config()
	var base_speeds: Dictionary = config.get("base_speeds_m_per_min", {})
	var modifiers: Dictionary = config.get("modifiers", {})
	var default_walk_speed := float(base_speeds.get("walk", 78.0))
	var citizen_walk_speed := float(citizen._walk_speed * 60.0) if citizen != null else default_walk_speed
	var effective_speed := maxf(lerpf(default_walk_speed, citizen_walk_speed, 0.5), 1.0)

	var travel_time_multiplier := 1.0
	if citizen != null and citizen.needs.energy <= citizen.low_energy_threshold:
		travel_time_multiplier *= float(modifiers.get("fatigue_multiplier", 1.15))
	var hour: int = int(world.time.get_hour()) if world != null and world.time != null else 12
	if hour >= 22 or hour < 6:
		travel_time_multiplier *= float(modifiers.get("night_multiplier", 1.05))

	return effective_speed * float(world.minutes_per_tick) / maxf(travel_time_multiplier, 0.01)

func _get_coarse_travel_config() -> Dictionary:
	if _coarse_travel_config_loaded:
		return _coarse_travel_config

	var defaults := {
		"base_speeds_m_per_min": {
			"walk": 78.0,
			"car": 260.0,
			"transit": 180.0
		},
		"modifiers": {
			"rain_multiplier": 1.10,
			"snow_multiplier": 1.25,
			"rush_hour_multiplier": 1.30,
			"fatigue_multiplier": 1.15,
			"night_multiplier": 1.05
		},
		"minimum_eta_minutes": 2,
		"fallback_eta_minutes": 20
	}

	_coarse_travel_config = defaults
	_coarse_travel_config_loaded = true
	if not FileAccess.file_exists(LOD_CONFIG_PATH):
		return _coarse_travel_config

	var file := FileAccess.open(LOD_CONFIG_PATH, FileAccess.READ)
	if file == null:
		return _coarse_travel_config
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		var coarse_config: Variant = (parsed as Dictionary).get("coarse_travel", {})
		if coarse_config is Dictionary:
			_deep_merge(_coarse_travel_config, coarse_config as Dictionary)
	return _coarse_travel_config

func _deep_merge(base: Dictionary, override: Dictionary) -> void:
	for key in override.keys():
		var override_value: Variant = override[key]
		if base.has(key) and base[key] is Dictionary and override_value is Dictionary:
			_deep_merge(base[key], override_value)
		else:
			base[key] = override_value

func _should_pause_for_player_dialog(citizen) -> bool:
	if citizen == null:
		return false
	if citizen.has_method("is_manual_control_enabled") and citizen.is_manual_control_enabled():
		return false
	if citizen.has_method("is_click_move_mode_enabled") and citizen.is_click_move_mode_enabled():
		return false
	return citizen.has_method("is_active_player_dialog_session") and citizen.is_active_player_dialog_session()
