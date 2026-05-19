extends RefCounted
class_name CitizenSocialGoap

## Soft `social` need planner (Step 3b). Mirrors CitizenFunGoap but minimal:
## the only social venue is the citizen's favorite park. Plan: go_park ->
## socialize -> social_recovered. Hard survival/work overrides in
## CitizenPlanner run before this is ever reached.

const BalanceConfig = preload("res://Simulation/Config/BalanceConfig.gd")
const GoapActionScript = preload("res://Simulation/GOAP/GoapAction.gd")
const GoapPlannerScript = preload("res://Simulation/GOAP/GoapPlanner.gd")
const GoToBuildingActionScript = preload("res://Actions/GoToBuildingAction.gd")
const SocializeActionScript = preload("res://Actions/SocializeAction.gd")

var _safe_hunger_max: float = BalanceConfig.get_float("goap.social.safe_hunger_max", 60.0)
var _safe_energy_min: float = BalanceConfig.get_float("goap.social.safe_energy_min", 25.0)
var _safe_health_min: float = BalanceConfig.get_float("goap.social.safe_health_min", 35.0)
var _energy_ok_min: float = BalanceConfig.get_float("goap.social.energy_ok_min", 18.0)
var _go_park_cost: float = BalanceConfig.get_float("goap.social.go_park_cost", 1.0)
var _socialize_cost: float = BalanceConfig.get_float("goap.social.socialize_cost", 0.75)
var _park_travel_minutes: int = BalanceConfig.get_int("goap.social.park_travel_minutes", 22)
var _night_start_hour: int = BalanceConfig.get_int("schedule.night_start_hour", 22)
var _day_start_hour: int = BalanceConfig.get_int("schedule.day_start_hour", 6)

func try_plan(world, citizen) -> bool:
	if world == null or citizen == null:
		return false

	var state: Dictionary = _build_state(world, citizen)
	var goal: Dictionary = {"social_recovered": true}
	var actions: Array = _build_actions()
	var plan: Array = GoapPlannerScript.plan(state, goal, actions, 6)
	if plan.is_empty():
		return false

	return _execute_first_action(plan[0], world, citizen)

func _build_state(world, citizen) -> Dictionary:
	var state: Dictionary = {}
	var safe_for_social: bool = citizen.needs.hunger < _safe_hunger_max \
		and citizen.needs.energy >= _safe_energy_min \
		and citizen.needs.health > _safe_health_min
	state["at_park"] = citizen.current_location == citizen.favorite_park
	state["has_park"] = citizen.favorite_park != null
	state["energy_ok"] = citizen.needs.energy >= _energy_ok_min
	state["safe_for_social"] = safe_for_social
	state["is_night"] = _is_night(world.time.get_hour())
	state["social_recovered"] = citizen.needs.social >= citizen.needs.TARGET_SOCIAL_MIN
	return state

func _build_actions() -> Array:
	var actions: Array = []
	actions.append(GoapActionScript.new(
		"go_park",
		_go_park_cost,
		{"has_park": true, "at_park": false, "is_night": false, "energy_ok": true, "safe_for_social": true},
		{"at_park": true}
	))
	actions.append(GoapActionScript.new(
		"socialize",
		_socialize_cost,
		{"at_park": true, "safe_for_social": true},
		{"social_recovered": true}
	))
	return actions

func _execute_first_action(action, world, citizen) -> bool:
	if action == null:
		return false

	match action.action_id:
		"go_park":
			if citizen.favorite_park == null:
				return false
			citizen.start_action(GoToBuildingActionScript.new(citizen.favorite_park, _park_travel_minutes, false), world)
			return true
		"socialize":
			citizen.start_action(SocializeActionScript.new(), world)
			return true
		_:
			return false

func _is_night(hour: int) -> bool:
	return hour >= _night_start_hour or hour < _day_start_hour
