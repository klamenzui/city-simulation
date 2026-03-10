extends RefCounted
class_name CitizenEducationGoap

const GoapActionScript = preload("res://Simulation/GOAP/GoapAction.gd")
const GoapPlannerScript = preload("res://Simulation/GOAP/GoapPlanner.gd")
const GoToBuildingActionScript = preload("res://Actions/GoToBuildingAction.gd")
const StudyAtUniversityActionScript = preload("res://Actions/StudyAtUniversityAction.gd")

func try_plan(world, citizen) -> bool:
	if world == null or citizen == null:
		return false
	if citizen.job == null:
		return false
	if citizen.job.meets_requirements(citizen):
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
	var is_night: bool = hour >= 22 or hour < 6
	var uni: University = citizen._find_nearest_university(citizen.home.get_entrance_pos() if citizen.home else citizen.global_position, true)

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
		1.0,
		{"has_university": true, "at_university": false, "is_night": false},
		{"at_university": true}
	))
	actions.append(GoapActionScript.new(
		"study",
		0.65,
		{"at_university": true, "can_afford_study": true},
		{"education_progress": true}
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
		_:
			return false