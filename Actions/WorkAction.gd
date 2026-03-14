extends Action
class_name WorkAction

var job
var worked_net := 0
var current_day := -1

func _init(_job) -> void:
	super()
	label = "Work"
	job = _job

func start(world, citizen) -> void:
	super.start(world, citizen)
	current_day = world.time.day
	worked_net = 0

# English comment: Work increases need drain compared to idle.
# Base (per minute): hunger +0.10, energy -0.08, fun -0.03.
# Target totals at work (not lunch): hunger +0.18, energy -0.13, fun -0.06.
func get_needs_modifier(world, citizen) -> Dictionary:
	var now_total = world.time.get_hour() * 60 + world.time.get_minute()
	var is_lunch = (now_total >= 11 * 60 + 30 and now_total <= 13 * 60 + 30)
	if is_lunch:
		return Action.DEFAULT_NEEDS_MOD

	return {
		"hunger_mul": 1.8,      # 0.10 * 1.8 = 0.18
		"energy_mul": 1.625,    # 0.08 * 1.625 = 0.13
		"fun_mul": 2.0,         # 0.03 * 2.0 = 0.06
		"hunger_add": 0.0,
		"energy_add": 0.0,
		"fun_add": 0.0,
	}
	
func tick(world, citizen, dt: int) -> void:
	super.tick(world, citizen, dt)

	var day_id: int = world.time.day
	if day_id != current_day:
		current_day = day_id
		worked_net = 0

	var now_total = world.time.get_hour() * 60 + world.time.get_minute()
	var is_lunch = (now_total >= 11 * 60 + 30 and now_total <= 13 * 60 + 30)

	if not is_lunch:
		worked_net += dt
		citizen.work_minutes_today += dt

	# BUG FIX: Previously the work drain STACKED on top of the passive drain in Needs.advance().
	# This meant during work: energy drains 0.08 (passive) + 0.15 (work) = 0.23/min
	# and hunger drains 0.15 (passive) + 0.30 (work) = 0.45/min.
	# Over 8h: energy lost = 110 → impossible to finish a shift. Hunger gained = 216 → always starving.
	#
	# Fix: work drain values are now NET extras on top of passive.
	# Energy: +0.05/min extra (total 0.13/min). 8h shift → ~62 energy lost. Realistic. ✓
	# Hunger: +0.08/min extra (total 0.23/min). 8h → ~111 hunger. Needs ~2 meals/day. ✓
	# Fun:    +0.03/min extra (total 0.06/min). Work is slightly less fun than sitting home. ✓
	citizen.needs.energy -= 0.05 * float(dt)
	citizen.needs.hunger += 0.08 * float(dt)
	citizen.needs.fun    -= 0.03 * float(dt)

	var shift_minutes := int(job.shift_hours * 60)

	# IMPROVEMENT: Self-interrupt when the citizen needs a break, so plan_next_action
	# can handle eating/resting. Without this, WorkAction runs for the entire shift
	# with no pauses → hunger=100 and energy=0 by end of day.
	#
	# Interrupt conditions (priority order):
	if citizen.needs.health <= 35.0:
		finished = true
		return

	if citizen.needs.energy <= citizen.low_energy_threshold:
		# Too tired to work safely → go home.
		finished = true
		return

	if citizen.needs.hunger >= 70.0:
		# Hungry enough to warrant a meal break. plan_next_action will handle eating,
		# then re-check work window and return to work if shift is not yet complete.
		finished = true
		return

	if is_lunch and now_total == (11 * 60 + 30):
		# Start of lunch window → break. Only trigger once (at the boundary minute).
		finished = true
		return

	if worked_net >= shift_minutes:
		finished = true
