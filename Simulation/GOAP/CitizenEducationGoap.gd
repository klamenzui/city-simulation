extends RefCounted
class_name CitizenEducationGoap

const BalanceConfig = preload("res://Simulation/Config/BalanceConfig.gd")
const GoapActionScript = preload("res://Simulation/GOAP/GoapAction.gd")
const GoapPlannerScript = preload("res://Simulation/GOAP/GoapPlanner.gd")
const GoToBuildingActionScript = preload("res://Actions/GoToBuildingAction.gd")
const StudyAtUniversityActionScript = preload("res://Actions/StudyAtUniversityAction.gd")

var _health_min: float = BalanceConfig.get_float("goap.education.health_min", 35.0)
var _hunger_max: float = BalanceConfig.get_float("goap.education.hunger_max", 70.0)
var _go_university_cost: float = BalanceConfig.get_float("goap.education.go_university_cost", 1.0)
var _study_cost: float = BalanceConfig.get_float("goap.education.study_cost", 0.65)
var _travel_minutes: int = BalanceConfig.get_int("goap.education.travel_minutes", 24)
var _night_start_hour: int = BalanceConfig.get_int("schedule.night_start_hour", 22)
var _day_start_hour: int = BalanceConfig.get_int("schedule.day_start_hour", 6)

func try_plan(world, citizen) -> bool:
	if world == null or citizen == null:
		return false
	if citizen.job == null:
		return false
	if citizen.job.meets_requirements(citizen):
		return false
	if citizen.needs.health <= _health_min:
		return false
	if citizen.needs.hunger >= _hunger_max:
		return false
	if citizen.needs.energy <= citizen.low_energy_threshold:
		return false

	var from_pos = citizen.home.get_entrance_pos() if citizen.home else citizen.global_position
	var uni: University = citizen._find_nearest_university(from_pos, true)
	if uni == null:
		citizen.debug_log_once_per_day(
			"education_no_university_%s" % citizen.job.title,
			"Education blocked for %s: no reachable open university. %s" % [
				citizen.job.title,
				citizen.get_job_debug_summary()
			]
		)
		return false
	if citizen.wallet.balance < uni.tuition_fee:
		citizen.debug_log_once_per_day(
			"education_funds_%s" % citizen.job.title,
			"Education blocked for %s: tuition %d EUR at %s, balance %d EUR." % [
				citizen.job.title,
				uni.tuition_fee,
				uni.get_display_name(),
				citizen.wallet.balance
			]
		)
		return false

	var state = _build_state(world, citizen)
	var goal = {"education_progress": true}
	var actions = _build_actions()
	var plan = GoapPlannerScript.plan(state, goal, actions, 5)
	if plan.is_empty():
		return false

	return _execute_first_action(plan[0], world, citizen)

func _build_state(world, citizen) -> Dictionary:
	var state = {}
	var hour: int = world.time.get_hour()
	var is_night: bool = _is_night(hour)
	var anchor = citizen.home.get_entrance_pos() if citizen.home else citizen.global_position
	var uni: University = citizen._find_nearest_university(anchor, true)

	state["has_university"] = uni != null
	state["at_university"] = uni != null and citizen.current_location == uni
	state["is_night"] = is_night
	state["can_afford_study"] = uni != null and citizen.wallet.balance >= uni.tuition_fee
	state["education_progress"] = false
	return state

func _build_actions() -> Array:
	var actions: Array = []
	actions.append(GoapActionScript.new(
		"go_university",
		_go_university_cost,
		{"has_university": true, "at_university": false, "is_night": false},
		{"at_university": true}
	))
	actions.append(GoapActionScript.new(
		"study",
		_study_cost,
		{"at_university": true, "can_afford_study": true},
		{"education_progress": true}
	))
	return actions

func _execute_first_action(action, world, citizen) -> bool:
	if action == null:
		return false

	match action.action_id:
		"go_university":
			var anchor = citizen.home.get_entrance_pos() if citizen.home else citizen.global_position
			var uni: University = citizen._find_nearest_university(anchor, true)
			if uni == null:
				return false
			citizen.debug_log("Education plan: heading to %s for %s (education %d/%d)." % [
				uni.get_display_name(),
				citizen.job.title,
				citizen.education_level,
				citizen.job.required_education_level
			])
			citizen.start_action(GoToBuildingActionScript.new(uni, _travel_minutes), world)
			return true
		"study":
			var anchor2 = citizen.home.get_entrance_pos() if citizen.home else citizen.global_position
			var uni2: University = citizen._find_nearest_university(anchor2, true)
			if uni2 == null:
				return false
			citizen.debug_log("Education plan: starting study at %s for %s." % [
				uni2.get_display_name(),
				citizen.job.title
			])
			citizen.start_action(StudyAtUniversityActionScript.new(uni2), world)
			return true
		_:
			return false

func _is_night(hour: int) -> bool:
	return hour >= _night_start_hour or hour < _day_start_hour
