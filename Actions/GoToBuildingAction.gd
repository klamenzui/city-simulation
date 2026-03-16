extends Action
class_name GoToBuildingAction

var target: Building
var travel_minutes: int = 20
var _arrival_target: Vector3 = Vector3.ZERO

const MAX_TRAVEL_SIM_MIN := 240

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

	# Use the exact entrance as arrival point. Random scatter produced
	# unreachable targets for some imported buildings and could leave
	# citizens stuck in GoTo forever.
	_arrival_target = target.get_entrance_pos()
	citizen.begin_travel_to(_arrival_target, target)
	citizen.current_location = null  # in transit after we snapped out of the source building

	# Path movement now drives completion; keep action timer disabled.
	remaining_minutes = 0

func tick(world: World, citizen: Citizen, dt: int) -> void:
	super.tick(world, citizen, dt)
	if target == null:
		finished = true
		return
	if citizen.has_reached_travel_target():
		finished = true
		return
	if elapsed_minutes >= MAX_TRAVEL_SIM_MIN:
		finished = true

func finish(world: World, citizen: Citizen) -> void:
	if target == null:
		return
	var reached_target := citizen.has_reached_travel_target()
	citizen.stop_travel()
	if not reached_target:
		return
	citizen.current_location = target
