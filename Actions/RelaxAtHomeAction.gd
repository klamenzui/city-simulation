extends Action
class_name RelaxAtHomeAction

const BalanceConfig = preload("res://Simulation/Config/BalanceConfig.gd")

var _needs_modifier: Dictionary = Action.DEFAULT_NEEDS_MOD.duplicate(true)

func _init() -> void:
	super()
	label = "Relax"
	var config: Dictionary = BalanceConfig.get_section("actions.relax_home")
	_needs_modifier = {
		"hunger_mul": float(config.get("hunger_mul", 1.0)),
		"energy_mul": float(config.get("energy_mul", 1.0)),
		"fun_mul": float(config.get("fun_mul", 1.0)),
		"hunger_add": float(config.get("hunger_add", 0.0)),
		"energy_add": float(config.get("energy_add", 0.10)),
		"fun_add": float(config.get("fun_add", 0.45)),
	}

func get_needs_modifier(world, citizen) -> Dictionary:
	return _needs_modifier

func tick(world, citizen, dt: int) -> void:
	super.tick(world, citizen, dt)

	if citizen.needs.hunger >= citizen.hunger_threshold:
		finished = true
		return

	if citizen.needs.fun >= citizen.needs.TARGET_FUN_MIN:
		finished = true
