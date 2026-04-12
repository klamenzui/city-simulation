extends Action
class_name GoToBuildingAction

const SimLogger = preload("res://Simulation/Logging/SimLogger.gd")
const RelaxAtParkActionScript = preload("res://Actions/RelaxAtParkAction.gd")

var target: Building
var travel_minutes: int = 20
var _arrival_target: Vector3 = Vector3.ZERO
var _travel_failed: bool = false
var _start_repath_count: int = 0
var _last_progress_pos: Vector3 = Vector3.ZERO
var _no_progress_minutes: int = 0
var _reroute_attempts: int = 0

const MAX_TRAVEL_SIM_MIN := 240
const MAX_DYNAMIC_REROUTES := 2
const PARK_ENTRY_ARRIVAL_TOLERANCE := 0.15

func _init(_target: Building = null, _travel: int = 20) -> void:
	super()
	label = "GoTo"
	target = _target
	travel_minutes = _travel

func start(world: World, citizen: Citizen) -> void:
	super.start(world, citizen)
	_travel_failed = false
	_no_progress_minutes = 0
	if target == null:
		finished = true
		return
	if citizen != null and citizen.has_method("prepare_go_to_target"):
		target = citizen.prepare_go_to_target(target, world)
		if target == null:
			_travel_failed = true
			finished = true
			return
	_reserve_park_bench(citizen, target)
	_start_repath_count = citizen._debug_repath_count if citizen != null else 0
	_last_progress_pos = citizen.global_position if citizen != null else Vector3.ZERO

	var nav_points := citizen.get_navigation_points_for_building(target, world) if citizen != null and citizen.has_method("get_navigation_points_for_building") else {}
	var is_outdoor := target.has_method("is_outdoor_destination") and target.is_outdoor_destination()
	var is_park_target := _is_park_target(target)
	if is_park_target:
		_arrival_target = nav_points.get("access", target.get_entrance_pos())
	elif is_outdoor:
		_arrival_target = nav_points.get("visit", nav_points.get("access", target.get_entrance_pos()))
	else:
		# Use the pedestrian access point so citizens stop at the sidewalk
		# instead of trying to clip into the building footprint.
		_arrival_target = nav_points.get("access", target.get_entrance_pos())
	var source_building := citizen.current_location
	var source_spawn := citizen.get_debug_exit_spawn_pos(source_building, world) if source_building != null and citizen.has_method("get_debug_exit_spawn_pos") else citizen.global_position
	SimLogger.log("[Citizen %s] GoTo route start=%s start_pos=%s exit=%s -> target=%s entry=%s arrival=%s" % [
		citizen.citizen_name,
		_format_building_endpoint(source_building, world, citizen.global_position),
		_format_point(citizen.global_position),
		_format_exit_endpoint(source_building, world, citizen.global_position, source_spawn),
		_format_building_endpoint(target, world, citizen.global_position),
		_format_entry_endpoint(target, world),
		_format_point(_arrival_target)
	])
	var travel_target_building: Building = null if is_park_target else target
	var travel_started := citizen.begin_travel_to(_arrival_target, travel_target_building)
	if not travel_started:
		_travel_failed = true
		_release_reserved_park_bench(citizen, target)
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

	if world != null and world.has_method("describe_pedestrian_path"):
		SimLogger.log("[Citizen %s] GoTo path %s" % [
			citizen.citizen_name,
			world.describe_pedestrian_path(citizen.get_debug_travel_route_points())
		])

	citizen.current_location = null

	# Path movement now drives completion; keep action timer disabled.
	remaining_minutes = 0

func tick(world: World, citizen: Citizen, dt: int) -> void:
	super.tick(world, citizen, dt)
	if target == null:
		finished = true
		return
	_update_progress_state(citizen, dt)
	if _has_arrived_at_destination(citizen):
		finished = true
		return
	if _should_abort_for_unreachable(citizen):
		if _attempt_dynamic_reroute(world, citizen):
			return
		_travel_failed = true
		finished = true
		return
	if elapsed_minutes >= MAX_TRAVEL_SIM_MIN:
		finished = true

func finish(world: World, citizen: Citizen) -> void:
	if target == null:
		_release_reserved_park_bench(citizen, target)
		return
	if _travel_failed:
		citizen.stop_travel()
		citizen.decision_cooldown_left = 0
		_release_reserved_park_bench(citizen, target)
		return
	var reached_target := _has_arrived_at_destination(citizen)
	citizen.stop_travel()
	if not reached_target:
		citizen.decision_cooldown_left = 0
		_release_reserved_park_bench(citizen, target)
		return
	_reserve_park_bench(citizen, target)
	citizen.enter_building(target, world)
	if _is_park_target(target) and _should_use_park_bench(citizen, target):
		citizen.start_action(RelaxAtParkActionScript.new(), world)
		citizen.decision_cooldown_left = 0
		return
	citizen.decision_cooldown_left = 0

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

func _attempt_dynamic_reroute(world: World, citizen: Citizen) -> bool:
	if citizen == null or target == null:
		return false
	if _reroute_attempts >= MAX_DYNAMIC_REROUTES:
		return false
	if not citizen.has_method("handle_unreachable_target"):
		return false
	var reason := "repaths=%d no_progress=%dmin" % [
		maxi(citizen._debug_repath_count - _start_repath_count, 0),
		_no_progress_minutes
	]
	var replacement := citizen.handle_unreachable_target(target, world, reason)
	if replacement == null or replacement == target:
		return false
	_reroute_attempts += 1
	_release_reserved_park_bench(citizen, target)
	target = replacement
	citizen.stop_travel()
	start(world, citizen)
	return true

func _reserve_park_bench(citizen: Citizen, building: Building) -> void:
	if not _should_use_park_bench(citizen, building):
		return
	building.reserve_bench_for(citizen, citizen.global_position)

func _release_reserved_park_bench(citizen: Citizen, building: Building) -> void:
	if not _should_use_park_bench(citizen, building):
		return
	building.release_bench_for(citizen)

func _should_use_park_bench(citizen: Citizen, building: Building) -> bool:
	if building == null or citizen == null:
		return false
	if not building.has_method("reserve_bench_for") or not building.has_method("release_bench_for"):
		return false
	# Park staff should not block visitor benches during the work commute.
	if citizen.job != null and citizen.job.workplace == building:
		return false
	return true

func _is_park_target(building: Building) -> bool:
	if building == null:
		return false
	return building is Park or building.is_in_group("parks")

func _has_arrived_at_destination(citizen: Citizen) -> bool:
	if citizen == null:
		return false
	if not _is_park_target(target) and citizen.has_reached_travel_target():
		return true
	var remaining := _arrival_target - citizen.global_position
	remaining.y = 0.0
	var tolerance := citizen.final_arrival_distance + 0.05
	if _is_park_target(target):
		tolerance = PARK_ENTRY_ARRIVAL_TOLERANCE
	return remaining.length() <= tolerance

func _format_point(pos: Vector3) -> String:
	return "(%.1f, %.1f, %.1f)" % [pos.x, pos.y, pos.z]

func _format_building_endpoint(building: Building, world: World, fallback_pos: Vector3) -> String:
	if building == null:
		return "outside pos=%s" % _format_point(fallback_pos)
	if building.has_method("get_navigation_debug_summary"):
		return "%s %s" % [building.get_display_name(), building.get_navigation_debug_summary(world)]
	return "%s entrance=%s" % [building.get_display_name(), _format_point(building.get_entrance_pos())]

func _format_exit_endpoint(building: Building, world: World, fallback_pos: Vector3, spawn_pos: Vector3) -> String:
	if building == null:
		return "outside pos=%s" % _format_point(fallback_pos)
	var exit_access := building.get_entrance_pos()
	if world != null and world.has_method("get_pedestrian_access_point"):
		exit_access = world.get_pedestrian_access_point(building.get_entrance_pos(), building)
	return "%s entrance=%s access=%s spawn=%s" % [
		building.get_display_name(),
		_format_point(building.get_entrance_pos()),
		_format_point(exit_access),
		_format_point(spawn_pos)
	]

func _format_entry_endpoint(building: Building, world: World) -> String:
	if building == null:
		return "none"
	var entry_access := building.get_entrance_pos()
	if world != null and world.has_method("get_pedestrian_access_point"):
		entry_access = world.get_pedestrian_access_point(building.get_entrance_pos(), building)
	return "%s entrance=%s access=%s" % [
		building.get_display_name(),
		_format_point(building.get_entrance_pos()),
		_format_point(entry_access)
	]
