extends Action
class_name GoToBuildingAction

var target: Building
var travel_minutes: int = 20
var _arrival_target: Vector3 = Vector3.ZERO

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
	if target == null:
		finished = true
		return

	citizen.current_location = null  # in transit

	var base := target.get_entrance_pos()
	var offset := Vector3(
		randf_range(-ARRIVAL_SCATTER, ARRIVAL_SCATTER),
		0.0,
		randf_range(-ARRIVAL_SCATTER, ARRIVAL_SCATTER)
	)
	_arrival_target = base + offset
	citizen.begin_travel_to(_arrival_target)

	# Path movement now drives completion; keep action timer disabled.
	remaining_minutes = 0

func tick(world: World, citizen: Citizen, dt: int) -> void:
	super.tick(world, citizen, dt)
	if target == null:
		finished = true
		return
	if citizen.has_reached_travel_target():
		finished = true

func finish(world: World, citizen: Citizen) -> void:
	if target == null:
		return
	citizen.stop_travel()
	citizen.current_location = target
	citizen.set_position_grounded(_arrival_target)
