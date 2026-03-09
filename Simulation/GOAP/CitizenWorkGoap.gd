extends RefCounted
class_name CitizenWorkGoap

const GoapActionScript = preload("res://Simulation/GOAP/GoapAction.gd")
const GoapPlannerScript = preload("res://Simulation/GOAP/GoapPlanner.gd")
const GoToBuildingActionScript = preload("res://Actions/GoToBuildingAction.gd")
const WorkActionScript = preload("res://Actions/WorkAction.gd")
const StudyAtUniversityActionScript = preload("res://Actions/StudyAtUniversityAction.gd")

func try_plan(world, citizen) -> bool:
	if world == null or citizen == null:
		return false
	if citizen.job == null:
		return false

	var state: Dictionary = _build_state(world, citizen)
	if not bool(state["work_relevant"]):
		return false

	var goal: Dictionary = {"work_progress": true}
	var actions: Array = _build_actions()
	var plan: Array = GoapPlannerScript.plan(state, goal, actions, 6)
	if plan.is_empty():
		return false

	return _execute_first_action(plan[0], world, citizen)

func _build_state(world, citizen) -> Dictionary:
	var state: Dictionary = {}
	var hour: int = world.time.get_hour()
	var minute: int = world.time.get_minute()
	var now_total: int = hour * 60 + minute
	var weekend: bool = world.time.is_weekend()

	var has_workplace: bool = citizen.job.workplace != null
	var shift_minutes: int = int(citizen.job.shift_hours * 60)
	var work_start: int = citizen.job.start_hour * 60 + citizen.schedule_offset
	var work_end: int = work_start + shift_minutes
	var in_work_window: bool = has_workplace and not weekend and now_total >= work_start and now_total < work_end
	var remaining_work: int = maxi(0, shift_minutes - citizen.work_minutes_today)
	var has_required_education: bool = citizen.job.meets_requirements(citizen)
	var uni: University = citizen._find_nearest_university(citizen.home.get_entrance_pos() if citizen.home else citizen.global_position, true)
	var at_university: bool = uni != null and citizen.current_location == uni

	state["work_relevant"] = in_work_window or not has_required_education
	state["has_workplace"] = has_workplace
	state["at_workplace"] = has_workplace and citizen.current_location == citizen.job.workplace
	state["in_work_window"] = in_work_window
	state["work_remaining"] = remaining_work > 0
	state["work_fit"] = citizen.needs.energy > citizen.low_energy_threshold and citizen.needs.hunger < 75.0
	state["has_required_education"] = has_required_education
	state["has_university"] = uni != null
	state["at_university"] = at_university
	state["can_afford_study"] = uni != null and citizen.wallet.balance >= uni.tuition_fee
	state["work_progress"] = false
	return state

func _build_actions() -> Array:
	var actions: Array = []
	actions.append(GoapActionScript.new(
		"go_university",
		1.2,
		{"has_required_education": false, "has_university": true, "at_university": false},
		{"at_university": true}
	))
	actions.append(GoapActionScript.new(
		"study",
		0.8,
		{"has_required_education": false, "at_university": true, "can_afford_study": true},
		{"work_progress": true}
	))
	actions.append(GoapActionScript.new(
		"go_work",
		0.7,
		{"has_required_education": true, "has_workplace": true, "in_work_window": true, "work_remaining": true, "work_fit": true, "at_workplace": false},
		{"at_workplace": true}
	))
	actions.append(GoapActionScript.new(
		"work_shift",
		0.55,
		{"has_required_education": true, "at_workplace": true, "in_work_window": true, "work_remaining": true, "work_fit": true},
		{"work_progress": true}
	))
	return actions

func _execute_first_action(action, world, citizen) -> bool:
	if action == null:
		return false

	match action.action_id:
		"go_university":
			var uni: University = citizen._find_nearest_university(citizen.home.get_entrance_pos() if citizen.home else citizen.global_position, true)
			if uni == null:
				return false
			citizen.start_action(GoToBuildingActionScript.new(uni, 24), world)
			return true
		"study":
			var uni2: University = citizen._find_nearest_university(citizen.home.get_entrance_pos() if citizen.home else citizen.global_position, true)
			if uni2 == null:
				return false
			citizen.start_action(StudyAtUniversityActionScript.new(uni2), world)
			return true
		"go_work":
			if citizen.job == null or citizen.job.workplace == null:
				return false
			citizen.start_action(GoToBuildingActionScript.new(citizen.job.workplace, 20), world)
			return true
		"work_shift":
			if citizen.job == null:
				return false
			citizen.start_action(WorkActionScript.new(citizen.job), world)
			return true
		_:
			return false