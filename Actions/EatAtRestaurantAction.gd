extends Action
class_name EatAtRestaurantAction

# How fast hunger drops while eating (per minute).
# From 85 hunger to 20 = 65 / 1.5 ≈ 43 minutes. Feels right for a restaurant.
const HUNGER_REDUCE_PER_MIN := 1.5

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

	if restaurant == null:
		finished = true
		return

	# Respect restaurant capacity.
	if not restaurant.try_enter(citizen):
		finished = true
		return

	if citizen.wallet.balance < restaurant.meal_price:
		print("[Citizen %s] Can't afford meal (balance: %d, price: %d)." % [
			citizen.citizen_name, citizen.wallet.balance, restaurant.meal_price
		])
		restaurant.leave(citizen)
		_can_eat = false
		finished = true
		return

	world.economy.transfer(citizen.wallet, restaurant.account, restaurant.meal_price)
	_paid = true

# English comment: Eating should reduce hunger net (overriding baseline hunger increase).
func get_needs_modifier(world, citizen) -> Dictionary:
	if not _can_eat or not _paid:
		return Action.DEFAULT_NEEDS_MOD

	# Base hunger rises +0.10/min; we want net -1.5/min → add about -1.6/min.
	return {
		"hunger_mul": -5.0,
		"energy_mul": 1.0,
		"fun_mul": 1.0,
		"hunger_add": 0.0,
		"energy_add": 0.0,
		"fun_add": 0.05,
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
