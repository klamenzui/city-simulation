extends Action
class_name RelaxAtParkAction

const BalanceConfig = preload("res://Simulation/Config/BalanceConfig.gd")

var _needs_modifier: Dictionary = Action.DEFAULT_NEEDS_MOD.duplicate(true)
var _stop_energy_threshold: float = 18.0
var _stop_health_threshold: float = 35.0

func _init(max_minutes: int = -1) -> void:
	var config: Dictionary = BalanceConfig.get_section("actions.relax_park")
	var resolved_max_minutes: int = max_minutes
	if resolved_max_minutes < 0:
		resolved_max_minutes = int(config.get("default_minutes", 90))
	super(resolved_max_minutes)
	label = "RelaxPark"
	_needs_modifier = {
		"hunger_mul": float(config.get("hunger_mul", 1.0)),
		"energy_mul": float(config.get("energy_mul", 1.0)),
		"fun_mul": float(config.get("fun_mul", 1.0)),
		"hunger_add": float(config.get("hunger_add", 0.0)),
		"energy_add": float(config.get("energy_add", 0.03)),
		"fun_add": float(config.get("fun_add", 0.22)),
	}
	_stop_energy_threshold = float(config.get("stop_energy_threshold", 18.0))
	_stop_health_threshold = float(config.get("stop_health_threshold", 35.0))

func get_needs_modifier(world, citizen) -> Dictionary:
	return _needs_modifier

func tick(world, citizen, dt: int) -> void:
	super.tick(world, citizen, dt)

	if citizen.needs.hunger >= citizen.hunger_threshold \
		or citizen.needs.energy <= _stop_energy_threshold \
		or citizen.needs.health <= _stop_health_threshold:
		finished = true
		return

	if citizen.needs.fun >= citizen.needs.TARGET_FUN_MIN:
		finished = true
