extends Action
class_name EatAtHomeAction

const BalanceConfig = preload("res://Simulation/Config/BalanceConfig.gd")

var _ate_meal: bool = false
var _max_meal_min: int = 70
var _needs_modifier: Dictionary = Action.DEFAULT_NEEDS_MOD.duplicate(true)

func _init() -> void:
	super()
	label = "EatHome"
	var config: Dictionary = BalanceConfig.get_section("actions.eat_home")
	_max_meal_min = int(config.get("max_minutes", 70))
	_needs_modifier = {
		"hunger_mul": float(config.get("hunger_mul", 0.25)),
		"energy_mul": float(config.get("energy_mul", 0.45)),
		"fun_mul": float(config.get("fun_mul", 1.0)),
		"hunger_add": float(config.get("hunger_add", -0.95)),
		"energy_add": float(config.get("energy_add", 0.14)),
		"fun_add": float(config.get("fun_add", -0.02)),
	}

func start(world, citizen) -> void:
	super.start(world, citizen)
	_ate_meal = false
	remaining_minutes = _max_meal_min
	if citizen.home_food_stock <= 0:
		finished = true
		return
	citizen.home_food_stock -= 1
	_ate_meal = true

func get_needs_modifier(world, citizen) -> Dictionary:
	if not _ate_meal:
		return Action.DEFAULT_NEEDS_MOD
	return _needs_modifier

func tick(world, citizen, dt: int) -> void:
	super.tick(world, citizen, dt)
	if citizen.needs.hunger <= citizen.needs.TARGET_HUNGER_MAX:
		finished = true
