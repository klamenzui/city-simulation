extends RefCounted
class_name CitizenHungerGoap

const BalanceConfig = preload("res://Simulation/Config/BalanceConfig.gd")
const GoapActionScript = preload("res://Simulation/GOAP/GoapAction.gd")
const GoapPlannerScript = preload("res://Simulation/GOAP/GoapPlanner.gd")
const GoToBuildingActionScript = preload("res://Actions/GoToBuildingAction.gd")
const EatAtHomeActionScript = preload("res://Actions/EatAtHomeAction.gd")
const EatAtRestaurantActionScript = preload("res://Actions/EatAtRestaurantAction.gd")
const EatAtCafeActionScript = preload("res://Actions/EatAtCafeAction.gd")
const BuyGroceriesActionScript = preload("res://Actions/BuyGroceriesAction.gd")

const FOOD_ROUTE_HOME := "home"
const FOOD_ROUTE_RESTAURANT := "restaurant"
const FOOD_ROUTE_CAFE := "cafe"
const FOOD_ROUTE_SUPERMARKET := "supermarket"

var _go_home_cost: float = BalanceConfig.get_float("goap.hunger.go_home_cost", 1.3)
var _go_restaurant_cost: float = BalanceConfig.get_float("goap.hunger.go_restaurant_cost", 1.0)
var _go_cafe_cost: float = BalanceConfig.get_float("goap.hunger.go_cafe_cost", 1.15)
var _go_supermarket_cost: float = BalanceConfig.get_float("goap.hunger.go_supermarket_cost", 1.1)
var _buy_groceries_cost: float = BalanceConfig.get_float("goap.hunger.buy_groceries_cost", 0.8)
var _eat_home_cost: float = BalanceConfig.get_float("goap.hunger.eat_home_cost", 0.9)
var _eat_restaurant_cost: float = BalanceConfig.get_float("goap.hunger.eat_restaurant_cost", 0.8)
var _eat_cafe_cost: float = BalanceConfig.get_float("goap.hunger.eat_cafe_cost", 1.0)
var _home_travel_minutes: int = BalanceConfig.get_int("goap.hunger.home_travel_minutes", 20)
var _restaurant_travel_minutes: int = BalanceConfig.get_int("goap.hunger.restaurant_travel_minutes", 15)
var _cafe_travel_minutes: int = BalanceConfig.get_int("goap.hunger.cafe_travel_minutes", 12)
var _supermarket_travel_minutes: int = BalanceConfig.get_int("goap.hunger.supermarket_travel_minutes", 18)
var _service_arrival_buffer_minutes: int = BalanceConfig.get_int("planner.service_arrival_buffer_minutes", 5)
var _night_start_hour: int = BalanceConfig.get_int("schedule.night_start_hour", 22)
var _day_start_hour: int = BalanceConfig.get_int("schedule.day_start_hour", 6)

func try_plan(world, citizen) -> bool:
	if world == null or citizen == null:
		return false

	var target_restaurant := _select_restaurant(world, citizen)
	var target_cafe := _select_cafe(world, citizen)
	var target_supermarket := _select_supermarket(world, citizen)
	var preferred_food_route := _select_preferred_food_route(world, citizen, target_restaurant, target_cafe, target_supermarket)
	if preferred_food_route.is_empty():
		return false

	var state: Dictionary = _build_state(world, citizen, target_restaurant, target_cafe, target_supermarket, preferred_food_route)
	var goal: Dictionary = {"hunger_satisfied": true}
	var actions: Array = _build_actions()
	var plan: Array = GoapPlannerScript.plan(state, goal, actions, 6)
	if plan.is_empty():
		return false

	return _execute_first_action(plan[0], world, citizen, target_restaurant, target_cafe, target_supermarket)

func _build_state(
	world,
	citizen,
	target_restaurant: Restaurant,
	target_cafe: Cafe,
	target_supermarket: Supermarket,
	preferred_food_route: String
) -> Dictionary:
	var state: Dictionary = {}
	var restaurant_open: bool = _service_open_for_plan(world, citizen, target_restaurant, _restaurant_travel_minutes)
	var cafe_open: bool = _service_open_for_plan(world, citizen, target_cafe, _cafe_travel_minutes)
	var supermarket_open: bool = _service_open_for_plan(world, citizen, target_supermarket, _supermarket_travel_minutes)
	state["preferred_food_route"] = preferred_food_route
	state["at_home"] = citizen.current_location == citizen.home
	state["at_restaurant"] = citizen.current_location == target_restaurant
	state["at_cafe"] = citizen.current_location == target_cafe
	state["at_supermarket"] = citizen.current_location == target_supermarket
	state["has_home"] = citizen.home != null
	state["has_restaurant"] = target_restaurant != null
	state["has_cafe"] = target_cafe != null
	state["has_supermarket"] = target_supermarket != null
	state["restaurant_open"] = restaurant_open
	state["restaurant_has_meal"] = restaurant_open and target_restaurant.can_sell_item("meal", 1)
	state["cafe_open"] = cafe_open
	state["cafe_has_snack"] = cafe_open and target_cafe.can_sell_snack()
	state["supermarket_open"] = supermarket_open
	state["supermarket_has_groceries"] = supermarket_open and target_supermarket.can_sell_item("grocery_bundle", 1)
	state["can_afford_restaurant"] = citizen.can_afford_restaurant_at(target_restaurant, world)
	state["can_afford_cafe"] = citizen.can_afford_cafe_at(target_cafe, world)
	state["can_afford_groceries"] = citizen.can_afford_groceries_at(target_supermarket, world)
	state["has_home_food"] = citizen.get_home_inventory_count("food") > 0
	state["hunger_satisfied"] = citizen.needs.hunger <= citizen.needs.TARGET_HUNGER_MAX
	state["is_night"] = _is_night(world.time.get_hour())
	return state

func _build_actions() -> Array:
	var actions: Array = []
	actions.append(GoapActionScript.new(
		"go_home",
		_go_home_cost,
		{"has_home": true, "at_home": false, "preferred_food_route": FOOD_ROUTE_HOME},
		{"at_home": true, "at_restaurant": false, "at_cafe": false, "at_supermarket": false}
	))
	actions.append(GoapActionScript.new(
		"go_home_after_groceries",
		_go_home_cost,
		{"has_home": true, "has_home_food": true, "at_home": false, "preferred_food_route": FOOD_ROUTE_SUPERMARKET},
		{"at_home": true, "at_restaurant": false, "at_cafe": false, "at_supermarket": false}
	))
	actions.append(GoapActionScript.new(
		"go_restaurant",
		_go_restaurant_cost,
		{"has_restaurant": true, "restaurant_open": true, "restaurant_has_meal": true, "can_afford_restaurant": true, "at_restaurant": false, "is_night": false, "preferred_food_route": FOOD_ROUTE_RESTAURANT},
		{"at_restaurant": true, "at_home": false, "at_cafe": false, "at_supermarket": false}
	))
	actions.append(GoapActionScript.new(
		"go_cafe",
		_go_cafe_cost,
		{"has_cafe": true, "cafe_open": true, "cafe_has_snack": true, "can_afford_cafe": true, "at_cafe": false, "is_night": false, "preferred_food_route": FOOD_ROUTE_CAFE},
		{"at_cafe": true, "at_home": false, "at_restaurant": false, "at_supermarket": false}
	))
	actions.append(GoapActionScript.new(
		"go_supermarket",
		_go_supermarket_cost,
		{"has_supermarket": true, "supermarket_open": true, "supermarket_has_groceries": true, "can_afford_groceries": true, "at_supermarket": false, "preferred_food_route": FOOD_ROUTE_SUPERMARKET},
		{"at_supermarket": true, "at_home": false, "at_restaurant": false, "at_cafe": false}
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
	actions.append(GoapActionScript.new(
		"eat_cafe",
		_eat_cafe_cost,
		{"at_cafe": true, "cafe_has_snack": true, "can_afford_cafe": true},
		{"hunger_satisfied": true}
	))
	return actions

func _execute_first_action(action, world, citizen, target_restaurant: Restaurant, target_cafe: Cafe, target_supermarket: Supermarket) -> bool:
	if action == null:
		return false

	match action.action_id:
		"go_home":
			if citizen.home == null:
				return false
			citizen.start_action(GoToBuildingActionScript.new(citizen.home, _home_travel_minutes), world)
			return true
		"go_home_after_groceries":
			if citizen.home == null:
				return false
			citizen.start_action(GoToBuildingActionScript.new(citizen.home, _home_travel_minutes), world)
			return true
		"go_restaurant":
			if target_restaurant == null:
				return false
			citizen.start_action(GoToBuildingActionScript.new(target_restaurant, _restaurant_travel_minutes), world)
			return true
		"go_cafe":
			if target_cafe == null:
				return false
			citizen.start_action(GoToBuildingActionScript.new(target_cafe, _cafe_travel_minutes), world)
			return true
		"go_supermarket":
			if target_supermarket == null:
				return false
			citizen.start_action(GoToBuildingActionScript.new(target_supermarket, _supermarket_travel_minutes), world)
			return true
		"buy_groceries":
			if target_supermarket == null:
				return false
			citizen.start_action(BuyGroceriesActionScript.new(target_supermarket), world)
			return true
		"eat_home":
			citizen.start_action(EatAtHomeActionScript.new(), world)
			return true
		"eat_restaurant":
			if target_restaurant == null:
				return false
			citizen.start_action(EatAtRestaurantActionScript.new(target_restaurant), world)
			return true
		"eat_cafe":
			if target_cafe == null:
				return false
			citizen.start_action(EatAtCafeActionScript.new(target_cafe), world)
			return true
		_:
			return false

func _select_restaurant(world, citizen) -> Restaurant:
	var current := citizen.current_location as Restaurant
	if _restaurant_can_feed(world, citizen, current):
		return current

	var nearest: Restaurant = null
	if citizen.has_method("_find_nearest_restaurant_with_meal"):
		nearest = citizen._find_nearest_restaurant_with_meal(citizen.global_position, true)
	if _restaurant_can_feed(world, citizen, nearest):
		return nearest

	if _restaurant_can_feed(world, citizen, citizen.favorite_restaurant):
		return citizen.favorite_restaurant
	return null


func _select_cafe(world, citizen) -> Cafe:
	var current := citizen.current_location as Cafe
	if _cafe_can_feed(world, citizen, current):
		return current

	var nearest: Cafe = null
	if citizen.has_method("_find_nearest_cafe_with_snack"):
		nearest = citizen._find_nearest_cafe_with_snack(citizen.global_position, true)
	if _cafe_can_feed(world, citizen, nearest):
		return nearest
	return null


func _select_supermarket(world, citizen) -> Supermarket:
	var current := citizen.current_location as Supermarket
	if _supermarket_can_feed_home(world, citizen, current):
		return current

	var nearest: Supermarket = null
	if citizen.has_method("_find_nearest_supermarket_with_groceries"):
		nearest = citizen._find_nearest_supermarket_with_groceries(citizen.global_position, true)
	if _supermarket_can_feed_home(world, citizen, nearest):
		return nearest

	if _supermarket_can_feed_home(world, citizen, citizen.favorite_supermarket):
		return citizen.favorite_supermarket
	return null

func _select_preferred_food_route(
	world,
	citizen,
	target_restaurant: Restaurant,
	target_cafe: Cafe,
	target_supermarket: Supermarket
) -> String:
	var best: Dictionary = {"route": "", "distance": INF}
	var from_pos: Vector3 = citizen.global_position
	if citizen.home != null and citizen.get_home_inventory_count("food") > 0:
		_consider_food_route(best, FOOD_ROUTE_HOME, from_pos, citizen.home)
	if target_restaurant != null:
		_consider_food_route(best, FOOD_ROUTE_RESTAURANT, from_pos, target_restaurant)
	if target_cafe != null:
		_consider_food_route(best, FOOD_ROUTE_CAFE, from_pos, target_cafe)
	if target_supermarket != null and citizen.home != null and citizen.get_home_inventory_count("food") <= 0:
		_consider_food_route(best, FOOD_ROUTE_SUPERMARKET, from_pos, target_supermarket)
	return str(best.get("route", ""))


func _consider_food_route(best: Dictionary, route_id: String, from_pos: Vector3, building: Building) -> void:
	if building == null:
		return
	var distance := _distance_to_food_target(from_pos, building)
	if distance < float(best.get("distance", INF)):
		best["route"] = route_id
		best["distance"] = distance


func _distance_to_food_target(from_pos: Vector3, building: Building) -> float:
	var target_pos := building.get_entrance_pos() if building.has_method("get_entrance_pos") else building.global_position
	var delta := target_pos - from_pos
	delta.y = 0.0
	return delta.length()


func _restaurant_can_feed(world, citizen, restaurant: Restaurant) -> bool:
	if restaurant == null:
		return false
	if not _service_open_for_plan(world, citizen, restaurant, _restaurant_travel_minutes):
		return false
	if not restaurant.can_sell_item("meal", 1):
		return false
	return citizen.can_afford_restaurant_at(restaurant, world)


func _cafe_can_feed(world, citizen, cafe: Cafe) -> bool:
	if cafe == null:
		return false
	if not _service_open_for_plan(world, citizen, cafe, _cafe_travel_minutes):
		return false
	if not cafe.can_sell_snack():
		return false
	return citizen.can_afford_cafe_at(cafe, world)


func _supermarket_can_feed_home(world, citizen, supermarket: Supermarket) -> bool:
	if supermarket == null:
		return false
	if not _service_open_for_plan(world, citizen, supermarket, _supermarket_travel_minutes):
		return false
	if not supermarket.can_sell_item("grocery_bundle", 1):
		return false
	return citizen.can_afford_groceries_at(supermarket, world)

func _service_open_for_plan(world, citizen, building: Building, travel_minutes: int) -> bool:
	if world == null or building == null:
		return false
	if citizen != null and "current_location" in citizen and citizen.current_location == building:
		return building.is_open_at_minute(_current_day_minute(world))
	return building.is_open_for_arrival(_current_day_minute(world), travel_minutes, _service_arrival_buffer_minutes)

func _current_day_minute(world) -> int:
	if world == null or not "time" in world or world.time == null:
		return -1
	var t = world.time
	if "minutes_total" in t:
		return int(t.minutes_total)
	if t.has_method("get_hour") and t.has_method("get_minute"):
		return int(t.get_hour()) * 60 + int(t.get_minute())
	if t.has_method("get_hour"):
		return int(t.get_hour()) * 60
	return -1

func _is_night(hour: int) -> bool:
	return hour >= _night_start_hour or hour < _day_start_hour
