extends RefCounted
class_name CitizenPlanner

const CitizenHungerGoapScript = preload("res://Simulation/GOAP/CitizenHungerGoap.gd")
const CitizenFunGoapScript = preload("res://Simulation/GOAP/CitizenFunGoap.gd")
const CitizenEnergyGoapScript = preload("res://Simulation/GOAP/CitizenEnergyGoap.gd")
const CitizenWorkGoapScript = preload("res://Simulation/GOAP/CitizenWorkGoap.gd")
const CitizenEducationGoapScript = preload("res://Simulation/GOAP/CitizenEducationGoap.gd")
const GoToBuildingActionScript = preload("res://Actions/GoToBuildingAction.gd")
const RelaxAtHomeActionScript = preload("res://Actions/RelaxAtHomeAction.gd")
const SleepActionScript = preload("res://Actions/SleepAction.gd")

var _hunger_goap = CitizenHungerGoapScript.new()
var _fun_goap = CitizenFunGoapScript.new()
var _energy_goap = CitizenEnergyGoapScript.new()
var _work_goap = CitizenWorkGoapScript.new()
var _education_goap = CitizenEducationGoapScript.new()

func plan_next_action(world, citizen) -> bool:
	if world == null or citizen == null:
		return false

	var candidates = _build_goal_candidates(world, citizen)
	candidates.sort_custom(_sort_goal_candidates)

	for candidate in candidates:
		var score: float = float(candidate.get("priority", 0.0))
		if score <= 0.01:
			continue

		var goal_id: String = str(candidate.get("id", ""))
		if _try_goal(goal_id, world, citizen):
			return true

	var hour: int = world.time.get_hour()
	var is_night: bool = hour >= 22 or hour < 6
	return _fallback_idle(world, citizen, is_night)

func _build_goal_candidates(world, citizen) -> Array:
	var hour: int = world.time.get_hour()
	var minute: int = world.time.get_minute()
	var now_total: int = hour * 60 + minute
	var weekend: bool = world.time.is_weekend()
	var is_night: bool = hour >= 22 or hour < 6

	var hunger_deficit: float = clamp((citizen.needs.hunger - citizen.hunger_threshold) / 40.0, 0.0, 1.0)
	if citizen.needs.hunger >= 80.0:
		hunger_deficit = maxf(hunger_deficit, 1.0)

	var energy_deficit: float = clamp((citizen.low_energy_threshold - citizen.needs.energy) / 40.0, 0.0, 1.0)
	if citizen.needs.energy <= 8.0:
		energy_deficit = maxf(energy_deficit, 1.0)

	var fun_deficit: float = clamp((citizen.needs.TARGET_FUN_MIN - citizen.needs.fun) / 35.0, 0.0, 1.0)
	if is_night:
		fun_deficit *= 0.3

	var education_need: float = 0.0
	if citizen.job != null and not citizen.job.meets_requirements(citizen) and not is_night:
		education_need = 1.0

	var work_need: float = 0.0
	if citizen.job != null and citizen.job.workplace != null and citizen.job.meets_requirements(citizen) and not weekend:
		var shift_minutes: int = int(citizen.job.shift_hours * 60)
		var work_start: int = citizen.job.start_hour * 60 + citizen.schedule_offset
		var work_end: int = work_start + shift_minutes
		var in_work_window: bool = now_total >= work_start and now_total < work_end
		var remaining_work: int = maxi(0, shift_minutes - citizen.work_minutes_today)
		if in_work_window and remaining_work > 0:
			var ratio_left: float = float(remaining_work) / float(maxi(shift_minutes, 1))
			work_need = clamp(0.45 + ratio_left * 0.55, 0.0, 1.0)

	return [
		{"id": "hunger", "priority": hunger_deficit * 1.25},
		{"id": "energy", "priority": energy_deficit * 1.1},
		{"id": "education", "priority": education_need * 0.95},
		{"id": "work", "priority": work_need * 0.9},
		{"id": "fun", "priority": fun_deficit * 0.65},
	]

func _sort_goal_candidates(a, b) -> bool:
	return float(a.get("priority", 0.0)) > float(b.get("priority", 0.0))

func _try_goal(goal_id: String, world, citizen) -> bool:
	match goal_id:
		"hunger":
			return _hunger_goap.try_plan(world, citizen)
		"energy":
			return _energy_goap.try_plan(world, citizen)
		"education":
			return _education_goap.try_plan(world, citizen)
		"work":
			return _work_goap.try_plan(world, citizen)
		"fun":
			return _fun_goap.try_plan(world, citizen)
		_:
			return false

func _fallback_idle(world, citizen, is_night: bool) -> bool:
	if citizen.home == null:
		return false

	if is_night and citizen.needs.energy < citizen.needs.TARGET_ENERGY_MIN:
		if citizen.current_location != citizen.home:
			citizen.start_action(GoToBuildingActionScript.new(citizen.home, 20), world)
			return true
		citizen.start_action(SleepActionScript.new(), world)
		return true

	if citizen.current_location != citizen.home:
		citizen.start_action(GoToBuildingActionScript.new(citizen.home, 20), world)
		return true
	citizen.start_action(RelaxAtHomeActionScript.new(), world)
	return true