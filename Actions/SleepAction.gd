extends Action
class_name SleepAction

const WAKE_HOUR_MIN := 6
# BUG FIX: Was 75. At 75 citizens could go to sleep with hunger=73, then
# by the time they woke (after energy recovered) hunger was already 100.
# Lowered to 65 so they wake up earlier with time to safely go eat.
const STARVATION_WAKE_HUNGER := 65.0

func _init() -> void:
	super()
	label = "Sleep"
	
# Sleeping reduces hunger burn and restores energy.
func get_needs_modifier(world, citizen) -> Dictionary:
	return {
		"hunger_mul": 0.35,
		"energy_mul": 1,
		"fun_mul": 0.0,
		"hunger_add": 0.0,
		"energy_add": 0.6,
		"fun_add": 0.0
	}

func tick(world, citizen, dt: int) -> void:
	super.tick(world, citizen, dt)

	var hour = world.time.get_hour()
	var is_night = (hour >= 22 or hour < WAKE_HOUR_MIN)

	# Normal wake: rested + morning.
	if citizen.needs.energy >= citizen.needs.TARGET_ENERGY_MIN and not is_night:
		finished = true
		return

	# STARVATION WAKE: hunger is getting dangerously high.
	# Only trigger after at least 30min of sleep (avoid micro-interrupts at bedtime).
	if citizen.needs.hunger >= STARVATION_WAKE_HUNGER and elapsed_minutes >= 30:
		finished = true
		return
