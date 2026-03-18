extends Action
class_name GoToBuildingAction

const SimLogger = preload("res://Simulation/Logging/SimLogger.gd")

var target: Building
var travel_minutes: int = 20
var _arrival_target: Vector3 = Vector3.ZERO
var _travel_failed: bool = false

const MAX_TRAVEL_SIM_MIN := 240

func _init(_target: Building = null, _travel: int = 20) -> void:
	super()
	label = "GoTo"
	target = _target
	travel_minutes = _travel

func start(world: World, citizen: Citizen) -> void:
	super.start(world, citizen)
	_travel_failed = false
	if target == null:
		finished = true
		return

	# Use the exact entrance as arrival point. Random scatter produced
	# unreachable targets for some imported buildings and could leave
	# citizens stuck in GoTo forever.
	_arrival_target = target.get_entrance_pos()
	var travel_started := citizen.begin_travel_to(_arrival_target, target)
	if not travel_started:
		_travel_failed = true
		var source_label := citizen.current_location.get_display_name() if citizen.current_location != null else "current position"
		SimLogger.log("[Citizen %s] No pedestrian route to %s. from=%s start=%s end=%s | %s" % [
			citizen.citizen_name,
			target.get_display_name(),
			source_label,
			_format_point(citizen.global_position),
			_format_point(_arrival_target),
			citizen.get_job_debug_summary() if citizen.has_method("get_job_debug_summary") else "job=unknown"
		])
		finished = true
		return

	citizen.current_location = null

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
	if _travel_failed:
		citizen.stop_travel()
		return
	var reached_target := citizen.has_reached_travel_target()
	citizen.stop_travel()
	if not reached_target:
		return
	citizen.current_location = target

func _format_point(pos: Vector3) -> String:
	return "(%.1f, %.1f, %.1f)" % [pos.x, pos.y, pos.z]
