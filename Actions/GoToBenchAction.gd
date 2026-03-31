extends Action
class_name GoToBenchAction

const SimLogger = preload("res://Simulation/Logging/SimLogger.gd")

var _arrival_target: Vector3 = Vector3.ZERO
var _travel_failed: bool = false
var _start_repath_count: int = 0
var _last_progress_pos: Vector3 = Vector3.ZERO
var _no_progress_minutes: int = 0

const MAX_TRAVEL_SIM_MIN := 180

func _init() -> void:
	super()
	label = "GoToBench"

func start(world: World, citizen: Citizen) -> void:
	super.start(world, citizen)
	_travel_failed = false
	_no_progress_minutes = 0
	if world == null or citizen == null:
		_travel_failed = true
		finished = true
		return

	var bench := world.reserve_city_bench_for(citizen, citizen.global_position)
	if bench.is_empty():
		_travel_failed = true
		finished = true
		return

	_arrival_target = bench.get("position", citizen.global_position)
	_start_repath_count = citizen._debug_repath_count
	_last_progress_pos = citizen.global_position
	SimLogger.log("[Citizen %s] GoToBench arrival=%s bench=%s" % [
		citizen.citizen_name,
		_format_point(_arrival_target),
		str(bench.get("name", "Bench"))
	])

	var travel_started := citizen.begin_travel_to(_arrival_target, null)
	if not travel_started:
		_travel_failed = true
		world.release_city_bench_for(citizen)
		finished = true
		return

	citizen.current_location = null
	remaining_minutes = 0

func tick(world: World, citizen: Citizen, dt: int) -> void:
	super.tick(world, citizen, dt)
	if citizen == null:
		finished = true
		return
	_update_progress_state(citizen, dt)
	if citizen.has_reached_travel_target():
		finished = true
		return
	if _should_abort_for_unreachable(citizen):
		_travel_failed = true
		finished = true
		return
	if elapsed_minutes >= MAX_TRAVEL_SIM_MIN:
		_travel_failed = true
		finished = true

func finish(world: World, citizen: Citizen) -> void:
	if world == null or citizen == null:
		return
	if _travel_failed:
		citizen.stop_travel()
		world.release_city_bench_for(citizen)
		citizen.decision_cooldown_left = 0
		return

	var reached_target := citizen.has_reached_travel_target()
	citizen.stop_travel()
	if not reached_target:
		world.release_city_bench_for(citizen)
		citizen.decision_cooldown_left = 0
		return

	var bench := world.get_reserved_city_bench_for(citizen)
	if not bench.is_empty():
		citizen.set_rest_pose(
			bench.get("position", citizen.global_position),
			float(bench.get("yaw", citizen.rotation.y))
		)

func _update_progress_state(citizen: Citizen, dt: int) -> void:
	if citizen == null:
		return
	var moved := citizen.global_position.distance_to(_last_progress_pos)
	if moved > 0.35:
		_last_progress_pos = citizen.global_position
		_no_progress_minutes = 0
		return
	if citizen._is_travelling:
		_no_progress_minutes += dt

func _should_abort_for_unreachable(citizen: Citizen) -> bool:
	if citizen == null or not citizen._is_travelling:
		return false
	if citizen.did_debug_last_travel_fail():
		return true
	var repaths_used := maxi(citizen._debug_repath_count - _start_repath_count, 0)
	return repaths_used >= citizen.unreachable_target_retry_limit \
		and _no_progress_minutes >= citizen.unreachable_target_no_progress_minutes

func _format_point(pos: Vector3) -> String:
	return "(%.1f, %.1f, %.1f)" % [pos.x, pos.y, pos.z]
