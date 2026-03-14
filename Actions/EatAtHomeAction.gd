extends Action
class_name EatAtHomeAction

const HUNGER_REDUCE_PER_MIN := 0.95
const ENERGY_RECOVER_PER_MIN := 0.14
const MAX_MEAL_MIN := 70

var _ate_meal: bool = false

func _init() -> void:
	super()
	label = "EatHome"

func start(world, citizen) -> void:
	super.start(world, citizen)
	_ate_meal = false
	remaining_minutes = MAX_MEAL_MIN
	if citizen.home_food_stock <= 0:
		finished = true
		return
	citizen.home_food_stock -= 1
	_ate_meal = true

func get_needs_modifier(world, citizen) -> Dictionary:
	if not _ate_meal:
		return Action.DEFAULT_NEEDS_MOD
	return {
		"hunger_mul": 0.25,
		"energy_mul": 0.45,
		"fun_mul": 1.0,
		"hunger_add": -HUNGER_REDUCE_PER_MIN,
		"energy_add": ENERGY_RECOVER_PER_MIN,
		"fun_add": -0.02,
	}

func tick(world, citizen, dt: int) -> void:
	super.tick(world, citizen, dt)
	if citizen.needs.hunger <= citizen.needs.TARGET_HUNGER_MAX:
		finished = true
