extends Resource
class_name Action

const DEFAULT_NEEDS_MOD := {
	"hunger_mul": 1.0,
	"energy_mul": 1.0,
	"fun_mul": 1.0,
	"hunger_add": 0.0,
	"energy_add": 0.0,
	"fun_add": 0.0
}

var label: String = "Action"

var elapsed_minutes: int = 0
var finished: bool = false
var remaining_minutes: int = 0

func _init(max_minutes: int = 0) -> void:
	remaining_minutes = max_minutes

func start(world, citizen) -> void:
	elapsed_minutes = 0
	finished = false

func tick(world, citizen, dt: int) -> void:
	elapsed_minutes += dt

	if remaining_minutes > 0:
		remaining_minutes -= dt
		if remaining_minutes <= 0:
			finished = true

func finish(world, citizen) -> void:
	pass

func is_done() -> bool:
	return finished

static func make_default_needs_modifier() -> Dictionary:
	return DEFAULT_NEEDS_MOD.duplicate(true)

func get_needs_modifier(world, citizen) -> Dictionary:
	return make_default_needs_modifier()
