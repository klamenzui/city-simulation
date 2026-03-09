extends Action
class_name EatAtHomeAction

func _init() -> void:
	super()
	label = "EatHome"

func start(world, citizen) -> void:
	super.start(world, citizen)
	if citizen.home_food_stock <= 0:
		finished = true
		return
	citizen.home_food_stock -= 1

func get_needs_modifier(world, citizen) -> Dictionary:
	if citizen.home_food_stock < 0:
		return Action.DEFAULT_NEEDS_MOD
	return {
		"hunger_mul": -3.6,
		"energy_mul": 1.0,
		"fun_mul": 1.0,
		"hunger_add": 0.0,
		"energy_add": 0.0,
		"fun_add": -0.02,
	}

func tick(world, citizen, dt: int) -> void:
	super.tick(world, citizen, dt)
	if citizen.needs.hunger <= citizen.needs.TARGET_HUNGER_MAX:
		finished = true
