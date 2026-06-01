extends RefCounted
class_name CitizenWorkRules

const BalanceConfig = preload("res://Simulation/Config/BalanceConfig.gd")

static var _low_health: float = BalanceConfig.get_float(
	"planner.low_health",
	BalanceConfig.get_float("goap.work.health_min", 35.0)
)
static var _work_hunger_max: float = BalanceConfig.get_float(
	"planner.work_fit_hunger_threshold",
	BalanceConfig.get_float("goap.work.hunger_max", 75.0)
)
static var _commute_buffer_min: int = BalanceConfig.get_int("planner.work_commute_buffer_min", 30)
static var _travel_minutes: int = BalanceConfig.get_int(
	"planner.work_travel_minutes",
	BalanceConfig.get_int("goap.work.travel_minutes", 20)
)
static var _sick_skip_threshold: float = BalanceConfig.get_float("planner.health.sick_work_skip_threshold", 55.0)
static var _sick_skip_base_probability: float = BalanceConfig.get_float("planner.health.sick_work_skip_base_probability", 0.18)
static var _sick_skip_max_probability: float = BalanceConfig.get_float("planner.health.sick_work_skip_max_probability", 0.75)
static var _health_visit_threshold: float = BalanceConfig.get_float("planner.health.visit_threshold", 20.0)


static func build_context(world, citizen) -> Dictionary:
	var context := {
		"has_job": false,
		"has_workplace": false,
		"requirements_met": false,
		"valid_job": false,
		"weekend": false,
		"now_total": 0,
		"shift_minutes": 0,
		"work_start": 0,
		"work_end": 0,
		"remaining_work": 0,
		"in_commute_window": false,
		"in_work_window": false,
		"at_workplace": false,
		"needs_fit": false,
		"sick_skip": false,
		"work_fit": false,
		"block_reason": "",
	}
	if world == null or citizen == null or citizen.job == null:
		return context

	var job = citizen.job
	context["has_job"] = true
	if job.workplace == null:
		return context
	context["has_workplace"] = true
	if not job.meets_requirements(citizen):
		return context
	context["requirements_met"] = true
	context["valid_job"] = true

	var time = world.time
	var now_total := int(time.get_hour()) * 60 + int(time.get_minute())
	var shift_minutes := int(job.shift_hours * 60)
	var work_start := int(job.start_hour * 60 + citizen.schedule_offset)
	var work_end := work_start + shift_minutes
	var remaining_work := maxi(0, shift_minutes - int(citizen.work_minutes_today))
	var weekend := bool(time.is_weekend()) if time.has_method("is_weekend") else false
	var in_commute_window := now_total >= maxi(work_start - _commute_buffer_min, 0) and now_total < work_start
	var in_work_window := now_total >= work_start and now_total < work_end
	var needs_fit := _is_needs_fit_for_work(citizen)
	var sick_skip := should_skip_work_for_sickness(world, citizen)
	var current_location = citizen.current_location if "current_location" in citizen else null

	context["weekend"] = weekend
	context["now_total"] = now_total
	context["shift_minutes"] = shift_minutes
	context["work_start"] = work_start
	context["work_end"] = work_end
	context["remaining_work"] = remaining_work
	context["in_commute_window"] = in_commute_window
	context["in_work_window"] = in_work_window
	context["at_workplace"] = current_location == job.workplace
	context["needs_fit"] = needs_fit
	context["sick_skip"] = sick_skip
	context["work_fit"] = needs_fit and not sick_skip
	if not needs_fit:
		context["block_reason"] = get_needs_block_reason(citizen)
	elif sick_skip:
		context["block_reason"] = "sickness"
	return context


static func get_travel_minutes() -> int:
	return _travel_minutes


static func is_goal_available(context: Dictionary) -> bool:
	return bool(context.get("valid_job", false)) \
		and not bool(context.get("weekend", false)) \
		and bool(context.get("in_work_window", false)) \
		and int(context.get("remaining_work", 0)) > 0 \
		and bool(context.get("work_fit", false))


static func is_schedule_window(context: Dictionary) -> bool:
	return bool(context.get("in_commute_window", false)) or bool(context.get("in_work_window", false))


static func should_skip_work_for_sickness(world, citizen) -> bool:
	if world == null or citizen == null or citizen.needs == null:
		return false
	if citizen.needs.health > _sick_skip_threshold:
		return false
	var denominator := maxf(_sick_skip_threshold - _health_visit_threshold, 1.0)
	var severity := clampf((_sick_skip_threshold - citizen.needs.health) / denominator, 0.0, 1.0)
	var probability := lerpf(_sick_skip_base_probability, _sick_skip_max_probability, severity)
	var roll := _stable_daily_roll(citizen, world, "sick_work")
	return roll < probability


static func get_needs_block_reason(citizen) -> String:
	if citizen == null or citizen.needs == null:
		return "missing needs"
	if citizen.needs.health <= _low_health:
		return "health %.0f <= %.0f" % [citizen.needs.health, _low_health]
	if citizen.needs.energy <= citizen.low_energy_threshold:
		return "energy %.0f <= %.0f" % [citizen.needs.energy, citizen.low_energy_threshold]
	if citizen.needs.hunger >= _work_hunger_max:
		return "hunger %.0f >= %.0f" % [citizen.needs.hunger, _work_hunger_max]
	return "unknown blocker"


static func _is_needs_fit_for_work(citizen) -> bool:
	if citizen == null or citizen.needs == null:
		return false
	return citizen.needs.health > _low_health \
		and citizen.needs.energy > citizen.low_energy_threshold \
		and citizen.needs.hunger < _work_hunger_max


static func _stable_daily_roll(citizen, world, salt: String) -> float:
	var day: int = int(world.world_day()) if world != null and world.has_method("world_day") else 0
	var raw := hash("%d:%d:%s" % [citizen.get_instance_id(), day, salt])
	return float(posmod(int(raw), 10000)) / 10000.0
