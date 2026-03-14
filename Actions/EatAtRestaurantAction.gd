extends Action
class_name EatAtRestaurantAction

const HUNGER_REDUCE_PER_MIN := 1.15
const ENERGY_RECOVER_PER_MIN := 0.22
const MAX_MEAL_MIN := 80

var restaurant: Restaurant
var _paid := false
var _can_eat := true

func _init(_restaurant: Restaurant) -> void:
	super()
	label = "Eat"
	restaurant = _restaurant

func start(world, citizen) -> void:
	super.start(world, citizen)
	_paid = false
	_can_eat = true
	remaining_minutes = MAX_MEAL_MIN

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
		print("[Citizen %s] Can't afford meal (balance: %d, price: %d)." % [
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
		return Action.DEFAULT_NEEDS_MOD

	return {
		"hunger_mul": 0.15,
		"energy_mul": 0.35,
		"fun_mul": 0.55,
		"hunger_add": -HUNGER_REDUCE_PER_MIN,
		"energy_add": ENERGY_RECOVER_PER_MIN,
		"fun_add": 0.08,
	}

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
