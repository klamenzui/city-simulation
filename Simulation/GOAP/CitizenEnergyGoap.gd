extends RefCounted
class_name CitizenEnergyGoap

const GoapActionScript = preload("res://Simulation/GOAP/GoapAction.gd")
const GoapPlannerScript = preload("res://Simulation/GOAP/GoapPlanner.gd")
const GoToBuildingActionScript = preload("res://Actions/GoToBuildingAction.gd")
const SleepActionScript = preload("res://Actions/SleepAction.gd")
const RelaxAtHomeActionScript = preload("res://Actions/RelaxAtHomeAction.gd")

func try_plan(world, citizen) -> bool:
	if world == null or citizen == null:
		return false

	var state: Dictionary = _build_state(world, citizen)
	var goal: Dictionary = {"energy_restored": true}
	var actions: Array = _build_actions()
	var plan: Array = GoapPlannerScript.plan(state, goal, actions, 5)
	if plan.is_empty():
		return false

	return _execute_first_action(plan[0], world, citizen)

func _build_state(world, citizen) -> Dictionary:
	var state: Dictionary = {}
	state["at_home"] = citizen.current_location == citizen.home
	state["has_home"] = citizen.home != null
	state["is_night"] = world.time.get_hour() >= 22 or world.time.get_hour() < 6
	state["energy_restored"] = citizen.needs.energy >= citizen.needs.TARGET_ENERGY_MIN
	return state

func _build_actions() -> Array:
	var actions: Array = []
	actions.append(GoapActionScript.new(
		"go_home",
		0.9,
		{"has_home": true, "at_home": false},
		{"at_home": true}
	))
	actions.append(GoapActionScript.new(
		"sleep_home",
		0.6,
		{"at_home": true},
		{"energy_restored": true}
	))
	actions.append(GoapActionScript.new(
		"relax_home",
		1.1,
		{"at_home": true, "is_night": false},
		{"energy_restored": true}
	))
	return actions

func _execute_first_action(action, world, citizen) -> bool:
	if action == null:
		return false

	match action.action_id:
		"go_home":
			if citizen.home == null:
				return false
			citizen.start_action(GoToBuildingActionScript.new(citizen.home, 20), world)
			return true
		"sleep_home":
			citizen.start_action(SleepActionScript.new(), world)
			return true
		"relax_home":
			citizen.start_action(RelaxAtHomeActionScript.new(), world)
			return true
		_:
			return false