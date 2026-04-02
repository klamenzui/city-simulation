extends Action
class_name EatAtRestaurantAction

const BalanceConfig = preload("res://Simulation/Config/BalanceConfig.gd")
const SimLogger = preload("res://Simulation/Logging/SimLogger.gd")

var restaurant: Restaurant
var _paid := false
var _can_eat := true
var _max_meal_min: int = 80
var _needs_modifier: Dictionary = Action.DEFAULT_NEEDS_MOD.duplicate(true)

func _init(_restaurant: Restaurant) -> void:
	super()
	label = "Eat"
	restaurant = _restaurant
	var config: Dictionary = BalanceConfig.get_section("actions.eat_restaurant")
	_max_meal_min = int(config.get("max_minutes", 80))
	_needs_modifier = {
		"hunger_mul": float(config.get("hunger_mul", 0.15)),
		"energy_mul": float(config.get("energy_mul", 0.35)),
		"fun_mul": float(config.get("fun_mul", 0.55)),
		"hunger_add": float(config.get("hunger_add", -1.15)),
		"energy_add": float(config.get("energy_add", 0.22)),
		"fun_add": float(config.get("fun_add", 0.08)),
	}

func start(world, citizen) -> void:
	super.start(world, citizen)
	_paid = false
	_can_eat = true
	remaining_minutes = _max_meal_min

	if restaurant == null:
		finished = true
		return
	if not restaurant.is_open(world.time.get_hour()):
		finished = true
		return

	if not restaurant.try_enter(citizen):
		finished = true
		return

	var meal_price: int = restaurant.meal_price
	if restaurant.has_method("get_meal_price"):
		meal_price = int(restaurant.get_meal_price(world))
	if citizen.wallet.balance < meal_price:
		SimLogger.log("[Citizen %s] Can't afford meal (balance: %d, price: %d)." % [
			citizen.citizen_name, citizen.wallet.balance, meal_price
		])
		restaurant.leave(citizen)
		_can_eat = false
		finished = true
		return

	_paid = restaurant.sell_meal(world, citizen)
	if not _paid:
		restaurant.leave(citizen)
		_can_eat = false
		finished = true

func get_needs_modifier(world, citizen) -> Dictionary:
	if not _can_eat or not _paid:
		return Action.make_default_needs_modifier()
	return _needs_modifier

func tick(world, citizen, dt: int) -> void:
	super.tick(world, citizen, dt)

	if not _can_eat or not _paid:
		finished = true
		return

	if citizen.needs.hunger <= citizen.needs.TARGET_HUNGER_MAX:
		finished = true

func finish(world, citizen) -> void:
	if restaurant and _can_eat:
		restaurant.leave(citizen)
