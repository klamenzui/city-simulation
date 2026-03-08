extends Action
class_name GoToBuildingAction

var target: Building
var travel_minutes: int = 20

# Small XZ scatter so multiple citizens arriving at the same building
# don't all land on exactly the same world position.
const ARRIVAL_SCATTER := 0.6

func _init(_target: Building = null, _travel: int = 20) -> void:
	super()
	label = "GoTo"
	target = _target
	travel_minutes = _travel

func start(world: World, citizen: Citizen) -> void:
	super.start(world, citizen)
	remaining_minutes = travel_minutes
	citizen.current_location = null  # in transit

func tick(world: World, citizen: Citizen, dt: int) -> void:
	super.tick(world, citizen, dt)

func finish(world: World, citizen: Citizen) -> void:
	if target == null:
		return
	citizen.current_location = target

	# BUG FIX: All citizens arrived at target.get_entrance_pos() — the exact same
	# Vector3 — so every citizen visually stacked on top of each other.
	# Fix: add a small random XZ offset per citizen so they spread out slightly.
	var base := target.get_entrance_pos()
	var offset := Vector3(
		randf_range(-ARRIVAL_SCATTER, ARRIVAL_SCATTER),
		0.0,
		randf_range(-ARRIVAL_SCATTER, ARRIVAL_SCATTER)
	)
	citizen.global_position = base + offset
