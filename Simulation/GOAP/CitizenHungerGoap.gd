extends RefCounted
class_name CitizenHungerGoap

const GoapActionScript = preload("res://Simulation/GOAP/GoapAction.gd")
const GoapPlannerScript = preload("res://Simulation/GOAP/GoapPlanner.gd")
const GoToBuildingActionScript = preload("res://Actions/GoToBuildingAction.gd")
const EatAtHomeActionScript = preload("res://Actions/EatAtHomeAction.gd")
const EatAtRestaurantActionScript = preload("res://Actions/EatAtRestaurantAction.gd")
const BuyGroceriesActionScript = preload("res://Actions/BuyGroceriesAction.gd")

func try_plan(world, citizen) -> bool:
	if world == null or citizen == null:
		return false

	var state: Dictionary = _build_state(world, citizen)
	var goal: Dictionary = {"hunger_satisfied": true}
	var actions: Array = _build_actions(citizen)
	var plan: Array = GoapPlannerScript.plan(state, goal, actions, 6)
	if plan.is_empty():
		return false

	return _execute_first_action(plan[0], world, citizen)

func _build_state(world, citizen) -> Dictionary:
	var state: Dictionary = {}
	state["at_home"] = citizen.current_location == citizen.home
	state["at_restaurant"] = citizen.current_location == citizen.favorite_restaurant
	state["at_supermarket"] = citizen.current_location == citizen.favorite_supermarket
	state["has_home"] = citizen.home != null
	state["has_restaurant"] = citizen.favorite_restaurant != null
	state["has_supermarket"] = citizen.favorite_supermarket != null
	state["can_afford_restaurant"] = citizen.favorite_restaurant != null and citizen.wallet.balance >= citizen.favorite_restaurant.meal_price
	state["can_afford_groceries"] = citizen.favorite_supermarket != null and citizen.wallet.balance >= citizen.favorite_supermarket.grocery_price
	state["has_home_food"] = citizen.home_food_stock > 0
	state["hunger_satisfied"] = citizen.needs.hunger <= citizen.needs.TARGET_HUNGER_MAX
	state["is_night"] = world.time.get_hour() >= 22 or world.time.get_hour() < 6
	return state

func _build_actions(_citizen) -> Array:
	var actions: Array = []
	actions.append(GoapActionScript.new(
		"go_home",
		1.3,
		{"has_home": true, "at_home": false},
		{"at_home": true, "at_restaurant": false, "at_supermarket": false}
	))
	actions.append(GoapActionScript.new(
		"go_restaurant",
		1.0,
		{"has_restaurant": true, "can_afford_restaurant": true, "at_restaurant": false, "is_night": false},
		{"at_restaurant": true, "at_home": false, "at_supermarket": false}
	))
	actions.append(GoapActionScript.new(
		"go_supermarket",
		1.1,
		{"has_supermarket": true, "can_afford_groceries": true, "at_supermarket": false},
		{"at_supermarket": true, "at_home": false, "at_restaurant": false}
	))
	actions.append(GoapActionScript.new(
		"buy_groceries",
		0.8,
		{"at_supermarket": true, "can_afford_groceries": true},
		{"has_home_food": true}
	))
	actions.append(GoapActionScript.new(
		"eat_home",
		0.9,
		{"at_home": true, "has_home_food": true},
		{"hunger_satisfied": true}
	))
	actions.append(GoapActionScript.new(
		"eat_restaurant",
		0.8,
		{"at_restaurant": true, "can_afford_restaurant": true},
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
			citizen.start_action(GoToBuildingActionScript.new(citizen.home, 20), world)
			return true
		"go_restaurant":
			if citizen.favorite_restaurant == null:
				return false
			citizen.start_action(GoToBuildingActionScript.new(citizen.favorite_restaurant, 15), world)
			return true
		"go_supermarket":
			if citizen.favorite_supermarket == null:
				return false
			citizen.start_action(GoToBuildingActionScript.new(citizen.favorite_supermarket, 18), world)
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
