extends RefCounted
class_name CitizenHungerGoap

const BalanceConfig = preload("res://Simulation/Config/BalanceConfig.gd")
const GoapActionScript = preload("res://Simulation/GOAP/GoapAction.gd")
const GoapPlannerScript = preload("res://Simulation/GOAP/GoapPlanner.gd")
const GoToBuildingActionScript = preload("res://Actions/GoToBuildingAction.gd")
const EatAtHomeActionScript = preload("res://Actions/EatAtHomeAction.gd")
const EatAtRestaurantActionScript = preload("res://Actions/EatAtRestaurantAction.gd")
const BuyGroceriesActionScript = preload("res://Actions/BuyGroceriesAction.gd")

var _go_home_cost: float = BalanceConfig.get_float("goap.hunger.go_home_cost", 1.3)
var _go_restaurant_cost: float = BalanceConfig.get_float("goap.hunger.go_restaurant_cost", 1.0)
var _go_supermarket_cost: float = BalanceConfig.get_float("goap.hunger.go_supermarket_cost", 1.1)
var _buy_groceries_cost: float = BalanceConfig.get_float("goap.hunger.buy_groceries_cost", 0.8)
var _eat_home_cost: float = BalanceConfig.get_float("goap.hunger.eat_home_cost", 0.9)
var _eat_restaurant_cost: float = BalanceConfig.get_float("goap.hunger.eat_restaurant_cost", 0.8)
var _home_travel_minutes: int = BalanceConfig.get_int("goap.hunger.home_travel_minutes", 20)
var _restaurant_travel_minutes: int = BalanceConfig.get_int("goap.hunger.restaurant_travel_minutes", 15)
var _supermarket_travel_minutes: int = BalanceConfig.get_int("goap.hunger.supermarket_travel_minutes", 18)
var _night_start_hour: int = BalanceConfig.get_int("schedule.night_start_hour", 22)
var _day_start_hour: int = BalanceConfig.get_int("schedule.day_start_hour", 6)

func try_plan(world, citizen) -> bool:
	if world == null or citizen == null:
		return false

	var state: Dictionary = _build_state(world, citizen)
	var goal: Dictionary = {"hunger_satisfied": true}
	var actions: Array = _build_actions()
	var plan: Array = GoapPlannerScript.plan(state, goal, actions, 6)
	if plan.is_empty():
		return false

	return _execute_first_action(plan[0], world, citizen)

func _build_state(world, citizen) -> Dictionary:
	var state: Dictionary = {}
	var restaurant_open: bool = citizen.favorite_restaurant != null and citizen.favorite_restaurant.is_open(world.time.get_hour())
	var supermarket_open: bool = citizen.favorite_supermarket != null and citizen.favorite_supermarket.is_open(world.time.get_hour())
	state["at_home"] = citizen.current_location == citizen.home
	state["at_restaurant"] = citizen.current_location == citizen.favorite_restaurant
	state["at_supermarket"] = citizen.current_location == citizen.favorite_supermarket
	state["has_home"] = citizen.home != null
	state["has_restaurant"] = citizen.favorite_restaurant != null
	state["has_supermarket"] = citizen.favorite_supermarket != null
	state["restaurant_open"] = restaurant_open
	state["restaurant_has_meal"] = restaurant_open and citizen.favorite_restaurant.can_sell_item("meal", 1)
	state["supermarket_open"] = supermarket_open
	state["supermarket_has_groceries"] = supermarket_open and citizen.favorite_supermarket.can_sell_item("grocery_bundle", 1)
	state["can_afford_restaurant"] = citizen.can_afford_restaurant(world)
	state["can_afford_groceries"] = citizen.can_afford_groceries(world)
	state["has_home_food"] = citizen.home_food_stock > 0
	state["hunger_satisfied"] = citizen.needs.hunger <= citizen.needs.TARGET_HUNGER_MAX
	state["is_night"] = _is_night(world.time.get_hour())
	return state

func _build_actions() -> Array:
	var actions: Array = []
	actions.append(GoapActionScript.new(
		"go_home",
		_go_home_cost,
		{"has_home": true, "at_home": false},
		{"at_home": true, "at_restaurant": false, "at_supermarket": false}
	))
	actions.append(GoapActionScript.new(
		"go_restaurant",
		_go_restaurant_cost,
		{"has_restaurant": true, "restaurant_open": true, "restaurant_has_meal": true, "can_afford_restaurant": true, "at_restaurant": false, "is_night": false},
		{"at_restaurant": true, "at_home": false, "at_supermarket": false}
	))
	actions.append(GoapActionScript.new(
		"go_supermarket",
		_go_supermarket_cost,
		{"has_supermarket": true, "supermarket_open": true, "supermarket_has_groceries": true, "can_afford_groceries": true, "at_supermarket": false},
		{"at_supermarket": true, "at_home": false, "at_restaurant": false}
	))
	actions.append(GoapActionScript.new(
		"buy_groceries",
		_buy_groceries_cost,
		{"at_supermarket": true, "supermarket_has_groceries": true, "can_afford_groceries": true},
		{"has_home_food": true}
	))
	actions.append(GoapActionScript.new(
		"eat_home",
		_eat_home_cost,
		{"at_home": true, "has_home_food": true},
		{"hunger_satisfied": true}
	))
	actions.append(GoapActionScript.new(
		"eat_restaurant",
		_eat_restaurant_cost,
		{"at_restaurant": true, "restaurant_has_meal": true, "can_afford_restaurant": true},
		{"hunger_satisfied": true}
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
		"go_restaurant":
			if citizen.favorite_restaurant == null:
				return false
			citizen.start_action(GoToBuildingActionScript.new(citizen.favorite_restaurant, _restaurant_travel_minutes), world)
			return true
		"go_supermarket":
			if citizen.favorite_supermarket == null:
				return false
			citizen.start_action(GoToBuildingActionScript.new(citizen.favorite_supermarket, _supermarket_travel_minutes), world)
			return true
		"buy_groceries":
			if citizen.favorite_supermarket == null:
				return false
			citizen.start_action(BuyGroceriesActionScript.new(citizen.favorite_supermarket), world)
			return true
		"eat_home":
			citizen.start_action(EatAtHomeActionScript.new(), world)
			return true
		"eat_restaurant":
			if citizen.favorite_restaurant == null:
				return false
			citizen.start_action(EatAtRestaurantActionScript.new(citizen.favorite_restaurant), world)
			return true
		_:
			return false

func _is_night(hour: int) -> bool:
	return hour >= _night_start_hour or hour < _day_start_hour
