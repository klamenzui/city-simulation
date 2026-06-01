extends RefCounted
class_name CitizenWorkGoap

const BalanceConfig = preload("res://Simulation/Config/BalanceConfig.gd")
const CitizenWorkRulesScript = preload("res://Simulation/Citizens/CitizenWorkRules.gd")
const GoapActionScript = preload("res://Simulation/GOAP/GoapAction.gd")
const GoapPlannerScript = preload("res://Simulation/GOAP/GoapPlanner.gd")
const GoToBuildingActionScript = preload("res://Actions/GoToBuildingAction.gd")
const WorkActionScript = preload("res://Actions/WorkAction.gd")

var _go_work_cost: float = BalanceConfig.get_float("goap.work.go_work_cost", 0.65)
var _work_shift_cost: float = BalanceConfig.get_float("goap.work.work_shift_cost", 0.5)

func try_plan(world, citizen) -> bool:
	if world == null or citizen == null:
		return false
	var context := CitizenWorkRulesScript.build_context(world, citizen)
	if not bool(context.get("valid_job", false)):
		return false

	var state = _build_state(context)
	var goal = {"work_progress": true}
	var actions = _build_actions()
	var plan = GoapPlannerScript.plan(state, goal, actions, 5)
	if plan.is_empty():
		return false

	return _execute_first_action(plan[0], world, citizen)

func _build_state(context: Dictionary) -> Dictionary:
	var state = {}
	state["at_workplace"] = bool(context.get("at_workplace", false))
	state["in_work_window"] = bool(context.get("in_work_window", false)) and not bool(context.get("weekend", false))
	state["work_remaining"] = int(context.get("remaining_work", 0)) > 0
	state["work_fit"] = bool(context.get("work_fit", false))
	state["work_progress"] = false
	return state

func _build_actions() -> Array:
	var actions: Array = []
	actions.append(GoapActionScript.new(
		"go_work",
		_go_work_cost,
		{"at_workplace": false, "in_work_window": true, "work_remaining": true, "work_fit": true},
		{"at_workplace": true}
	))
	actions.append(GoapActionScript.new(
		"work_shift",
		_work_shift_cost,
		{"at_workplace": true, "in_work_window": true, "work_remaining": true, "work_fit": true},
		{"work_progress": true}
	))
	return actions

func _execute_first_action(action, world, citizen) -> bool:
	if action == null:
		return false

	match action.action_id:
		"go_work":
			citizen.start_action(GoToBuildingActionScript.new(citizen.job.workplace, CitizenWorkRulesScript.get_travel_minutes()), world)
			return true
		"work_shift":
			citizen.start_action(WorkActionScript.new(citizen.job), world)
			return true
		_:
			return false
