extends Action
class_name EatAtCafeAction

const BalanceConfig = preload("res://Simulation/Config/BalanceConfig.gd")
const SimLogger = preload("res://Simulation/Logging/SimLogger.gd")

var cafe: Cafe
var _paid := false
var _can_eat := true
var _max_snack_min: int = 35
var _stop_hunger_threshold: float = 45.0
var _needs_modifier: Dictionary = Action.DEFAULT_NEEDS_MOD.duplicate(true)

func _init(_cafe: Cafe) -> void:
	super()
	label = "Eat"
	cafe = _cafe
	var config: Dictionary = BalanceConfig.get_section("actions.eat_cafe")
	_max_snack_min = int(config.get("max_minutes", 35))
	_stop_hunger_threshold = float(config.get("stop_hunger_threshold", 45.0))
	_needs_modifier = {
		"hunger_mul": float(config.get("hunger_mul", 0.25)),
		"energy_mul": float(config.get("energy_mul", 0.55)),
		"fun_mul": float(config.get("fun_mul", 0.75)),
		"hunger_add": float(config.get("hunger_add", -0.72)),
		"energy_add": float(config.get("energy_add", 0.08)),
		"fun_add": float(config.get("fun_add", 0.05)),
	}

func start(world, citizen) -> void:
	super.start(world, citizen)
	_paid = false
	_can_eat = true
	remaining_minutes = _max_snack_min

	if cafe == null:
		_can_eat = false
		finished = true
		return
	if not cafe.is_open(world.time.get_hour()):
		_can_eat = false
		finished = true
		return
	if not cafe.try_enter(citizen):
		_can_eat = false
		finished = true
		return

	var snack_price: int = cafe.get_snack_price(world)
	if citizen.wallet.balance < snack_price:
		SimLogger.log("[Citizen %s] Can't afford cafe snack (balance: %d, price: %d)." % [
			citizen.citizen_name, citizen.wallet.balance, snack_price
		])
		cafe.leave(citizen)
		_can_eat = false
		finished = true
		return

	_paid = cafe.sell_snack(world, citizen)
	if not _paid:
		cafe.leave(citizen)
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

	if citizen.needs.hunger <= _stop_hunger_threshold:
		finished = true

func finish(world, citizen) -> void:
	if cafe != null and _can_eat:
		cafe.leave(citizen)
