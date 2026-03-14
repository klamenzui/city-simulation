extends Action
class_name WatchCinemaAction

var cinema: Cinema
var watch_minutes: int = 80
var _ticket_paid := false

func _init(_cinema: Cinema, _watch_minutes: int = 80) -> void:
	super()
	label = "Cinema"
	cinema = _cinema
	watch_minutes = _watch_minutes

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
		return Action.DEFAULT_NEEDS_MOD
	return {
		"hunger_mul": 1.0,
		"energy_mul": 1.0,
		"fun_mul": 1.0,
		"hunger_add": 0.0,
		"energy_add": -0.01,
		"fun_add": 0.34,
	}

func tick(world, citizen, dt: int) -> void:
	super.tick(world, citizen, dt)
	if not _ticket_paid:
		finished = true
		return
	if citizen.needs.hunger >= 70.0 or citizen.needs.energy <= 18.0 or citizen.needs.health <= 35.0:
		finished = true
		return
	if elapsed_minutes >= watch_minutes:
		finished = true
	elif citizen.needs.fun >= citizen.needs.TARGET_FUN_MIN:
		finished = true

func finish(world, citizen) -> void:
	if cinema != null:
		cinema.leave(citizen)
