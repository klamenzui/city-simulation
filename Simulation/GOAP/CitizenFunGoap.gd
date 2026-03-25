extends RefCounted
class_name CitizenFunGoap

const BalanceConfig = preload("res://Simulation/Config/BalanceConfig.gd")
const GoapActionScript = preload("res://Simulation/GOAP/GoapAction.gd")
const GoapPlannerScript = preload("res://Simulation/GOAP/GoapPlanner.gd")
const GoToBuildingActionScript = preload("res://Actions/GoToBuildingAction.gd")
const RelaxAtParkActionScript = preload("res://Actions/RelaxAtParkAction.gd")
const RelaxAtHomeActionScript = preload("res://Actions/RelaxAtHomeAction.gd")
const BuyClothingActionScript = preload("res://Actions/BuyClothingAction.gd")
const WatchCinemaActionScript = preload("res://Actions/WatchCinemaAction.gd")

var _safe_hunger_max: float = BalanceConfig.get_float("goap.fun.safe_hunger_max", 60.0)
var _safe_energy_min: float = BalanceConfig.get_float("goap.fun.safe_energy_min", 25.0)
var _safe_health_min: float = BalanceConfig.get_float("goap.fun.safe_health_min", 35.0)
var _energy_ok_min: float = BalanceConfig.get_float("goap.fun.energy_ok_min", 18.0)
var _go_home_cost: float = BalanceConfig.get_float("goap.fun.go_home_cost", 1.2)
var _go_park_cost: float = BalanceConfig.get_float("goap.fun.go_park_cost", 1.0)
var _go_shop_cost: float = BalanceConfig.get_float("goap.fun.go_shop_cost", 0.95)
var _go_cinema_cost: float = BalanceConfig.get_float("goap.fun.go_cinema_cost", 1.1)
var _relax_park_cost: float = BalanceConfig.get_float("goap.fun.relax_park_cost", 0.75)
var _buy_clothes_cost: float = BalanceConfig.get_float("goap.fun.buy_clothes_cost", 0.65)
var _watch_cinema_cost: float = BalanceConfig.get_float("goap.fun.watch_cinema_cost", 0.7)
var _relax_home_cost: float = BalanceConfig.get_float("goap.fun.relax_home_cost", 1.8)
var _home_travel_minutes: int = BalanceConfig.get_int("goap.fun.home_travel_minutes", 20)
var _park_travel_minutes: int = BalanceConfig.get_int("goap.fun.park_travel_minutes", 22)
var _shop_travel_minutes: int = BalanceConfig.get_int("goap.fun.shop_travel_minutes", 20)
var _cinema_travel_minutes: int = BalanceConfig.get_int("goap.fun.cinema_travel_minutes", 24)
var _night_start_hour: int = BalanceConfig.get_int("schedule.night_start_hour", 22)
var _day_start_hour: int = BalanceConfig.get_int("schedule.day_start_hour", 6)

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
	var safe_for_fun: bool = citizen.needs.hunger < _safe_hunger_max \
		and citizen.needs.energy >= _safe_energy_min \
		and citizen.needs.health > _safe_health_min
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
	state["energy_ok"] = citizen.needs.energy >= _energy_ok_min
	state["safe_for_fun"] = safe_for_fun
	state["is_night"] = _is_night(world.time.get_hour())
	state["fun_recovered"] = citizen.needs.fun >= citizen.needs.TARGET_FUN_MIN
	return state

func _build_actions() -> Array:
	var actions: Array = []
	actions.append(GoapActionScript.new(
		"go_home",
		_go_home_cost,
		{"has_home": true, "at_home": false},
		{"at_home": true, "at_park": false, "at_shop": false, "at_cinema": false}
	))
	actions.append(GoapActionScript.new(
		"go_park",
		_go_park_cost,
		{"has_park": true, "at_park": false, "is_night": false, "energy_ok": true, "safe_for_fun": true},
		{"at_park": true, "at_home": false, "at_shop": false, "at_cinema": false}
	))
	actions.append(GoapActionScript.new(
		"go_shop",
		_go_shop_cost,
		{"has_shop": true, "shop_open": true, "shop_has_stock": true, "at_shop": false, "is_night": false, "can_afford_shop": true, "energy_ok": true, "safe_for_fun": true},
		{"at_shop": true, "at_home": false, "at_park": false, "at_cinema": false}
	))
	actions.append(GoapActionScript.new(
		"go_cinema",
		_go_cinema_cost,
		{"has_cinema": true, "cinema_open": true, "at_cinema": false, "is_night": false, "can_afford_cinema": true, "safe_for_fun": true},
		{"at_cinema": true, "at_home": false, "at_shop": false, "at_park": false}
	))
	actions.append(GoapActionScript.new(
		"relax_park",
		_relax_park_cost,
		{"at_park": true, "safe_for_fun": true},
		{"fun_recovered": true}
	))
	actions.append(GoapActionScript.new(
		"buy_clothes",
		_buy_clothes_cost,
		{"at_shop": true, "shop_has_stock": true, "can_afford_shop": true, "safe_for_fun": true},
		{"fun_recovered": true}
	))
	actions.append(GoapActionScript.new(
		"watch_cinema",
		_watch_cinema_cost,
		{"at_cinema": true, "cinema_open": true, "can_afford_cinema": true, "safe_for_fun": true},
		{"fun_recovered": true}
	))
	actions.append(GoapActionScript.new(
		"relax_home",
		_relax_home_cost,
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
			citizen.start_action(GoToBuildingActionScript.new(citizen.home, _home_travel_minutes), world)
			return true
		"go_park":
			if citizen.favorite_park == null:
				return false
			citizen.start_action(GoToBuildingActionScript.new(citizen.favorite_park, _park_travel_minutes), world)
			return true
		"go_shop":
			if citizen.favorite_shop == null:
				return false
			citizen.start_action(GoToBuildingActionScript.new(citizen.favorite_shop, _shop_travel_minutes), world)
			return true
		"go_cinema":
			if citizen.favorite_cinema == null:
				return false
			citizen.start_action(GoToBuildingActionScript.new(citizen.favorite_cinema, _cinema_travel_minutes), world)
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

func _is_night(hour: int) -> bool:
	return hour >= _night_start_hour or hour < _day_start_hour
