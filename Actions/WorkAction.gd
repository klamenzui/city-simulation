extends Action
class_name WorkAction

const BalanceConfig = preload("res://Simulation/Config/BalanceConfig.gd")

var job
var worked_net := 0
var current_day := -1
var _finish_reason: String = ""
var _lunch_start_minute: int = 11 * 60 + 30
var _lunch_end_minute: int = 13 * 60 + 30
var _needs_modifier: Dictionary = Action.DEFAULT_NEEDS_MOD.duplicate(true)
var _extra_energy_drain_per_min: float = 0.05
var _extra_hunger_gain_per_min: float = 0.08
var _extra_fun_drain_per_min: float = 0.03
var _stop_health_threshold: float = 35.0
var _stop_hunger_threshold: float = 70.0

func _init(_job) -> void:
	super()
	label = "Work"
	job = _job
	var config: Dictionary = BalanceConfig.get_section("actions.work")
	_lunch_start_minute = int(config.get("lunch_start_minute", 11 * 60 + 30))
	_lunch_end_minute = int(config.get("lunch_end_minute", 13 * 60 + 30))
	_needs_modifier = {
		"hunger_mul": float(config.get("needs_hunger_mul", 1.8)),
		"energy_mul": float(config.get("needs_energy_mul", 1.625)),
		"fun_mul": float(config.get("needs_fun_mul", 2.0)),
		"hunger_add": float(config.get("needs_hunger_add", 0.0)),
		"energy_add": float(config.get("needs_energy_add", 0.0)),
		"fun_add": float(config.get("needs_fun_add", 0.0)),
	}
	_extra_energy_drain_per_min = float(config.get("extra_energy_drain_per_min", 0.05))
	_extra_hunger_gain_per_min = float(config.get("extra_hunger_gain_per_min", 0.08))
	_extra_fun_drain_per_min = float(config.get("extra_fun_drain_per_min", 0.03))
	_stop_health_threshold = float(config.get("stop_health_threshold", 35.0))
	_stop_hunger_threshold = float(config.get("stop_hunger_threshold", 70.0))

func start(world, citizen) -> void:
	super.start(world, citizen)
	current_day = world.time.day
	worked_net = 0
	_finish_reason = ""
	var workplace_label = job.workplace.get_display_name() if job != null and job.workplace != null else "Unknown"
	citizen.debug_log("Work shift started at %s for %s (worked_today=%d/%d min, wage=%d/h)." % [
		workplace_label,
		job.title if job != null else "Unknown",
		citizen.work_minutes_today,
		int(job.shift_hours * 60) if job != null else 0,
		job.wage_per_hour if job != null else 0
	])

func get_needs_modifier(world, citizen) -> Dictionary:
	if _is_lunch_break(world.time.get_hour(), world.time.get_minute()):
		return Action.DEFAULT_NEEDS_MOD
	return _needs_modifier

func tick(world, citizen, dt: int) -> void:
	super.tick(world, citizen, dt)

	var day_id: int = world.time.day
	if day_id != current_day:
		current_day = day_id
		worked_net = 0

	var hour: int = world.time.get_hour()
	var minute: int = world.time.get_minute()
	var now_total: int = hour * 60 + minute
	var is_lunch: bool = _is_lunch_break(hour, minute)

	if not is_lunch:
		worked_net += dt
		citizen.work_minutes_today += dt

	citizen.needs.energy -= _extra_energy_drain_per_min * float(dt)
	citizen.needs.hunger += _extra_hunger_gain_per_min * float(dt)
	citizen.needs.fun -= _extra_fun_drain_per_min * float(dt)

	var shift_minutes := int(job.shift_hours * 60)

	if citizen.needs.health <= _stop_health_threshold:
		_finish_reason = "health %.0f <= %.0f" % [citizen.needs.health, _stop_health_threshold]
		finished = true
		return

	if citizen.needs.energy <= citizen.low_energy_threshold:
		_finish_reason = "energy %.0f <= %.0f" % [citizen.needs.energy, citizen.low_energy_threshold]
		finished = true
		return

	if citizen.needs.hunger >= _stop_hunger_threshold:
		_finish_reason = "hunger %.0f >= %.0f" % [citizen.needs.hunger, _stop_hunger_threshold]
		finished = true
		return

	if is_lunch and now_total == _lunch_start_minute:
		_finish_reason = "lunch break at %s" % _format_clock(_lunch_start_minute)
		finished = true
		return

	if worked_net >= shift_minutes:
		_finish_reason = "completed shift (%d/%d min)" % [worked_net, shift_minutes]
		finished = true

func finish(world, citizen) -> void:
	var workplace_label = job.workplace.get_display_name() if job != null and job.workplace != null else "Unknown"
	if _finish_reason != "":
		citizen.debug_log("Work shift stopped at %s: %s. worked_today=%d/%d min." % [
			workplace_label,
			_finish_reason,
			citizen.work_minutes_today,
			int(job.shift_hours * 60) if job != null else 0
		])

func _is_lunch_break(hour: int, minute: int) -> bool:
	var now_total: int = hour * 60 + minute
	return now_total >= _lunch_start_minute and now_total <= _lunch_end_minute

func _format_clock(total_minutes: int) -> String:
	var hour: int = int(total_minutes / 60) % 24
	var minute: int = total_minutes % 60
	return "%02d:%02d" % [hour, minute]
