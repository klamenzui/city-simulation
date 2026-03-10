extends RefCounted
class_name CitizenWorkGoap

const GoapActionScript = preload("res://Simulation/GOAP/GoapAction.gd")
const GoapPlannerScript = preload("res://Simulation/GOAP/GoapPlanner.gd")
const GoToBuildingActionScript = preload("res://Actions/GoToBuildingAction.gd")
const WorkActionScript = preload("res://Actions/WorkAction.gd")

func try_plan(world, citizen) -> bool:
	if world == null or citizen == null:
		return false
	if citizen.job == null:
		return false
	if citizen.job.workplace == null:
		return false
	if not citizen.job.meets_requirements(citizen):
		return false

	var state = _build_state(world, citizen)
	var goal = {"work_progress": true}
	var actions = _build_actions()
	var plan = GoapPlannerScript.plan(state, goal, actions, 5)
	if plan.is_empty():
		return false

	return _execute_first_action(plan[0], world, citizen)

func _build_state(world, citizen) -> Dictionary:
	var state = {}
	var hour: int = world.time.get_hour()
	var minute: int = world.time.get_minute()
	var now_total: int = hour * 60 + minute
	var weekend: bool = world.time.is_weekend()

	var shift_minutes: int = int(citizen.job.shift_hours * 60)
	var work_start: int = citizen.job.start_hour * 60 + citizen.schedule_offset
	var work_end: int = work_start + shift_minutes
	var in_work_window: bool = not weekend and now_total >= work_start and now_total < work_end
	var remaining_work: int = maxi(0, shift_minutes - citizen.work_minutes_today)

	state["at_workplace"] = citizen.current_location == citizen.job.workplace
	state["in_work_window"] = in_work_window
	state["work_remaining"] = remaining_work > 0
	state["work_fit"] = citizen.needs.energy > citizen.low_energy_threshold and citizen.needs.hunger < 75.0
	state["work_progress"] = false
	return state

func _build_actions() -> Array:
	var actions: Array = []
	actions.append(GoapActionScript.new(
		"go_work",
		0.65,
		{"at_workplace": false, "in_work_window": true, "work_remaining": true, "work_fit": true},
		{"at_workplace": true}
	))
	actions.append(GoapActionScript.new(
		"work_shift",
		0.5,
		{"at_workplace": true, "in_work_window": true, "work_remaining": true, "work_fit": true},
		{"work_progress": true}
	))
	return actions

func _execute_first_action(action, world, citizen) -> bool:
	if action == null:
		return false

	match action.action_id:
		"go_work":
			citizen.start_action(GoToBuildingActionScript.new(citizen.job.workplace, 20), world)
			return true
		"work_shift":
			citizen.start_action(WorkActionScript.new(citizen.job), world)
			return true
		_:
			return false