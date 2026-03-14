extends RefCounted
class_name CitizenFunGoap

const GoapActionScript = preload("res://Simulation/GOAP/GoapAction.gd")
const GoapPlannerScript = preload("res://Simulation/GOAP/GoapPlanner.gd")
const GoToBuildingActionScript = preload("res://Actions/GoToBuildingAction.gd")
const RelaxAtParkActionScript = preload("res://Actions/RelaxAtParkAction.gd")
const RelaxAtHomeActionScript = preload("res://Actions/RelaxAtHomeAction.gd")
const BuyClothingActionScript = preload("res://Actions/BuyClothingAction.gd")
const WatchCinemaActionScript = preload("res://Actions/WatchCinemaAction.gd")

func try_plan(world, citizen) -> bool:
	if world == null or citizen == null:
		return false

	var state: Dictionary = _build_state(world, citizen)
	var goal: Dictionary = {"fun_recovered": true}
	var actions: Array = _build_actions()
	var plan: Array = GoapPlannerScript.plan(state, goal, actions, 6)
	if plan.is_empty():
		return false

	return _execute_first_action(plan[0], world, citizen)

func _build_state(world, citizen) -> Dictionary:
	var state: Dictionary = {}
	var shop_open: bool = citizen.favorite_shop != null and citizen.favorite_shop.is_open(world.time.get_hour())
	var cinema_open: bool = citizen.favorite_cinema != null and citizen.favorite_cinema.is_open(world.time.get_hour())
	var safe_for_fun: bool = citizen.needs.hunger < 60.0 and citizen.needs.energy >= 25.0 and citizen.needs.health > 35.0
	state["at_home"] = citizen.current_location == citizen.home
	state["at_park"] = citizen.current_location == citizen.favorite_park
	state["at_shop"] = citizen.current_location == citizen.favorite_shop
	state["at_cinema"] = citizen.current_location == citizen.favorite_cinema

	state["has_home"] = citizen.home != null
	state["has_park"] = citizen.favorite_park != null
	state["has_shop"] = citizen.favorite_shop != null
	state["has_cinema"] = citizen.favorite_cinema != null

	state["can_afford_shop"] = citizen.can_afford_shop_item(world)
	state["can_afford_cinema"] = citizen.can_afford_cinema(world)
	state["shop_open"] = shop_open
	state["shop_has_stock"] = shop_open and citizen.favorite_shop.can_sell_item("clothing", 1)
	state["cinema_open"] = cinema_open
	state["energy_ok"] = citizen.needs.energy >= 18.0
	state["safe_for_fun"] = safe_for_fun
	state["is_night"] = world.time.get_hour() >= 22 or world.time.get_hour() < 6
	state["fun_recovered"] = citizen.needs.fun >= citizen.needs.TARGET_FUN_MIN
	return state

func _build_actions() -> Array:
	var actions: Array = []
	actions.append(GoapActionScript.new(
		"go_home",
		1.2,
		{"has_home": true, "at_home": false},
		{"at_home": true, "at_park": false, "at_shop": false, "at_cinema": false}
	))
	actions.append(GoapActionScript.new(
		"go_park",
		1.0,
		{"has_park": true, "at_park": false, "is_night": false, "energy_ok": true, "safe_for_fun": true},
		{"at_park": true, "at_home": false, "at_shop": false, "at_cinema": false}
	))
	actions.append(GoapActionScript.new(
		"go_shop",
		0.95,
		{"has_shop": true, "shop_open": true, "shop_has_stock": true, "at_shop": false, "is_night": false, "can_afford_shop": true, "energy_ok": true, "safe_for_fun": true},
		{"at_shop": true, "at_home": false, "at_park": false, "at_cinema": false}
	))
	actions.append(GoapActionScript.new(
		"go_cinema",
		1.1,
		{"has_cinema": true, "cinema_open": true, "at_cinema": false, "is_night": false, "can_afford_cinema": true, "safe_for_fun": true},
		{"at_cinema": true, "at_home": false, "at_shop": false, "at_park": false}
	))
	actions.append(GoapActionScript.new(
		"relax_park",
		0.75,
		{"at_park": true, "safe_for_fun": true},
		{"fun_recovered": true}
	))
	actions.append(GoapActionScript.new(
		"buy_clothes",
		0.65,
		{"at_shop": true, "shop_has_stock": true, "can_afford_shop": true, "safe_for_fun": true},
		{"fun_recovered": true}
	))
	actions.append(GoapActionScript.new(
		"watch_cinema",
		0.7,
		{"at_cinema": true, "cinema_open": true, "can_afford_cinema": true, "safe_for_fun": true},
		{"fun_recovered": true}
	))
	actions.append(GoapActionScript.new(
		"relax_home",
		1.8,
		{"at_home": true, "safe_for_fun": true},
		{"fun_recovered": true}
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
		"go_park":
			if citizen.favorite_park == null:
				return false
			citizen.start_action(GoToBuildingActionScript.new(citizen.favorite_park, 22), world)
			return true
		"go_shop":
			if citizen.favorite_shop == null:
				return false
			citizen.start_action(GoToBuildingActionScript.new(citizen.favorite_shop, 20), world)
			return true
		"go_cinema":
			if citizen.favorite_cinema == null:
				return false
			citizen.start_action(GoToBuildingActionScript.new(citizen.favorite_cinema, 24), world)
			return true
		"relax_park":
			citizen.start_action(RelaxAtParkActionScript.new(), world)
			return true
		"buy_clothes":
			if citizen.favorite_shop == null:
				return false
			citizen.start_action(BuyClothingActionScript.new(citizen.favorite_shop), world)
			return true
		"watch_cinema":
			if citizen.favorite_cinema == null:
				return false
			citizen.start_action(WatchCinemaActionScript.new(citizen.favorite_cinema), world)
			return true
		"relax_home":
			citizen.start_action(RelaxAtHomeActionScript.new(), world)
			return true
		_:
			return false
