extends Action
class_name RelaxAtParkAction

# BUG FIX: super(max_minutes) now works correctly because Action._init(max_minutes)
# is properly defined. Previously Action had no _init so the arg was silently dropped
# and max_minutes was never applied.
func _init(max_minutes: int = 90) -> void:
	super(max_minutes)
	label = "RelaxPark"

# English comment: Park relax restores fun and a small amount of energy.
func get_needs_modifier(world, citizen) -> Dictionary:
	return {
		"hunger_mul": 1.0,
		"energy_mul": 1.0,
		"fun_mul": 1.0,
		"hunger_add": 0.0,
		"energy_add": 0.03,
		"fun_add": 0.22,
	}

func tick(world, citizen, dt: int) -> void:
	super.tick(world, citizen, dt)

	if citizen.needs.fun >= citizen.needs.TARGET_FUN_MIN:
		finished = true
