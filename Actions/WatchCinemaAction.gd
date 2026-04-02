extends Action
class_name WatchCinemaAction

const BalanceConfig = preload("res://Simulation/Config/BalanceConfig.gd")

var cinema: Cinema
var watch_minutes: int = 80
var _ticket_paid := false
var _needs_modifier: Dictionary = Action.DEFAULT_NEEDS_MOD.duplicate(true)
var _stop_hunger_threshold: float = 70.0
var _stop_energy_threshold: float = 18.0
var _stop_health_threshold: float = 35.0

func _init(_cinema: Cinema, _watch_minutes: int = -1) -> void:
	super()
	label = "Cinema"
	cinema = _cinema
	var config: Dictionary = BalanceConfig.get_section("actions.watch_cinema")
	watch_minutes = _watch_minutes
	if watch_minutes < 0:
		watch_minutes = int(config.get("default_minutes", 80))
	_needs_modifier = {
		"hunger_mul": float(config.get("hunger_mul", 1.0)),
		"energy_mul": float(config.get("energy_mul", 1.0)),
		"fun_mul": float(config.get("fun_mul", 1.0)),
		"hunger_add": float(config.get("hunger_add", 0.0)),
		"energy_add": float(config.get("energy_add", -0.01)),
		"fun_add": float(config.get("fun_add", 0.34)),
	}
	_stop_hunger_threshold = float(config.get("stop_hunger_threshold", 70.0))
	_stop_energy_threshold = float(config.get("stop_energy_threshold", 18.0))
	_stop_health_threshold = float(config.get("stop_health_threshold", 35.0))

func start(world, citizen) -> void:
	super.start(world, citizen)
	_ticket_paid = false

	if cinema == null:
		finished = true
		return
	if not cinema.is_open(world.time.get_hour()):
		finished = true
		return
	if not cinema.try_enter(citizen):
		finished = true
		return

	_ticket_paid = cinema.buy_ticket(world, citizen)
	if not _ticket_paid:
		cinema.leave(citizen)
		finished = true

func get_needs_modifier(world, citizen) -> Dictionary:
	if not _ticket_paid:
		return Action.make_default_needs_modifier()
	return _needs_modifier

func tick(world, citizen, dt: int) -> void:
	super.tick(world, citizen, dt)
	if not _ticket_paid:
		finished = true
		return
	if citizen.needs.hunger >= _stop_hunger_threshold \
		or citizen.needs.energy <= _stop_energy_threshold \
		or citizen.needs.health <= _stop_health_threshold:
		finished = true
		return
	if elapsed_minutes >= watch_minutes:
		finished = true
	elif citizen.needs.fun >= citizen.needs.TARGET_FUN_MIN:
		finished = true

func finish(world, citizen) -> void:
	if cinema != null:
		cinema.leave(citizen)
