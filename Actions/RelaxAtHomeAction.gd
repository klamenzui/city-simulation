extends Action
class_name RelaxAtHomeAction

const FUN_GAIN_PER_MIN    := 0.45
const ENERGY_GAIN_PER_MIN := 0.10  # BUG FIX: Relaxing at home now also restores a bit of energy.
									# Previously only fun was gained, which was unrealistic.

func _init() -> void:
	super()
	label = "Relax"

# English comment: Relaxing restores fun and a bit of energy.
func get_needs_modifier(world, citizen) -> Dictionary:
	return {
		"hunger_mul": 1.0,
		"energy_mul": 1.0,
		"fun_mul": 1.0,
		"hunger_add": 0.0,
		"energy_add": 0.10,
		"fun_add": 0.45,
	}
	
func tick(world, citizen, dt: int) -> void:
	super.tick(world, citizen, dt)

	if citizen.needs.fun >= citizen.needs.TARGET_FUN_MIN:
		finished = true
