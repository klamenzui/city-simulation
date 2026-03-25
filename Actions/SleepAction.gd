extends Action
class_name SleepAction

const BalanceConfig = preload("res://Simulation/Config/BalanceConfig.gd")

var _wake_hour_min: int = 6
var _night_start_hour: int = 22
var _starvation_wake_hunger: float = 65.0
var _min_sleep_before_starvation_check_min: int = 30
var _needs_modifier: Dictionary = Action.DEFAULT_NEEDS_MOD.duplicate(true)

func _init() -> void:
	super()
	label = "Sleep"
	var config: Dictionary = BalanceConfig.get_section("actions.sleep")
	_wake_hour_min = int(config.get("wake_hour_min", BalanceConfig.get_int("schedule.day_start_hour", 6)))
	_night_start_hour = int(config.get("night_start_hour", BalanceConfig.get_int("schedule.night_start_hour", 22)))
	_starvation_wake_hunger = float(config.get("starvation_wake_hunger", 65.0))
	_min_sleep_before_starvation_check_min = int(config.get("min_sleep_before_starvation_check_min", 30))
	_needs_modifier = {
		"hunger_mul": float(config.get("hunger_mul", 0.35)),
		"energy_mul": float(config.get("energy_mul", 1.0)),
		"fun_mul": float(config.get("fun_mul", 0.0)),
		"hunger_add": float(config.get("hunger_add", 0.0)),
		"energy_add": float(config.get("energy_add", 0.6)),
		"fun_add": float(config.get("fun_add", 0.0)),
	}

func get_needs_modifier(world, citizen) -> Dictionary:
	return _needs_modifier

func tick(world, citizen, dt: int) -> void:
	super.tick(world, citizen, dt)

	var hour: int = world.time.get_hour()
	var is_night: bool = _is_night(hour)

	if citizen.needs.energy >= citizen.needs.TARGET_ENERGY_MIN and not is_night:
		finished = true
		return

	if citizen.needs.hunger >= _starvation_wake_hunger and elapsed_minutes >= _min_sleep_before_starvation_check_min:
		finished = true
		return

func _is_night(hour: int) -> bool:
	return hour >= _night_start_hour or hour < _wake_hour_min
