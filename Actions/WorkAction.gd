extends Action
class_name WorkAction

var job
var worked_net := 0
var current_day := -1
var _finish_reason: String = ""

func _init(_job) -> void:
	super()
	label = "Work"
	job = _job

func start(world, citizen) -> void:
	super.start(world, citizen)
	current_day = world.time.day
	worked_net = 0
	_finish_reason = ""
	var workplace_label = job.workplace.get_display_name() if job != null and job.workplace != null else "Unknown"
	citizen.debug_log("Work shift started at %s for %s (worked_today=%d/%d min, wage=%d/h)." % [
		workplace_label,
		job.title if job != null else "Unknown",
		citizen.work_minutes_today,
		int(job.shift_hours * 60) if job != null else 0,
		job.wage_per_hour if job != null else 0
	])

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
		_finish_reason = "health %.0f <= 35" % citizen.needs.health
		finished = true
		return

	if citizen.needs.energy <= citizen.low_energy_threshold:
		# Too tired to work safely → go home.
		_finish_reason = "energy %.0f <= %.0f" % [citizen.needs.energy, citizen.low_energy_threshold]
		finished = true
		return

	if citizen.needs.hunger >= 70.0:
		# Hungry enough to warrant a meal break. plan_next_action will handle eating,
		# then re-check work window and return to work if shift is not yet complete.
		_finish_reason = "hunger %.0f >= 70" % citizen.needs.hunger
		finished = true
		return

	if is_lunch and now_total == (11 * 60 + 30):
		# Start of lunch window → break. Only trigger once (at the boundary minute).
		_finish_reason = "lunch break at 11:30"
		finished = true
		return

	if worked_net >= shift_minutes:
		_finish_reason = "completed shift (%d/%d min)" % [worked_net, shift_minutes]
		finished = true

func finish(world, citizen) -> void:
	var workplace_label = job.workplace.get_display_name() if job != null and job.workplace != null else "Unknown"
	if _finish_reason != "":
		citizen.debug_log("Work shift stopped at %s: %s. worked_today=%d/%d min." % [
			workplace_label,
			_finish_reason,
			citizen.work_minutes_today,
			int(job.shift_hours * 60) if job != null else 0
		])
