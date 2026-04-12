extends Action
class_name RelaxAtParkAction

const BalanceConfig = preload("res://Simulation/Config/BalanceConfig.gd")
const SimLogger = preload("res://Simulation/Logging/SimLogger.gd")

const PHASE_MOVE_TO_BENCH := "move_to_bench"
const PHASE_REST := "rest"
const PHASE_EXIT_PARK := "exit_park"
const PHASE_DONE := "done"

var _base_needs_modifier: Dictionary = Action.DEFAULT_NEEDS_MOD.duplicate(true)
var _no_bench_energy_add: float = 0.0
var _bench_energy_add: float = 0.10
var _bench_fun_add_bonus: float = 0.03
var _stop_energy_threshold: float = 18.0
var _stop_health_threshold: float = 35.0
var _using_bench: bool = false
var _bench_reservation: Dictionary = {}
var _park_ref: Park = null
var _phase: String = PHASE_DONE
var _rest_minutes_target: int = 0
var _rest_minutes_elapsed: int = 0
var _rest_min_minutes: int = 10
var _rest_max_minutes: int = 20
var _bench_target_pos: Vector3 = Vector3.ZERO
var _bench_target_yaw: float = 0.0

func _init(max_minutes: int = -1) -> void:
	var config: Dictionary = BalanceConfig.get_section("actions.relax_park")
	super(0)
	label = "RelaxPark"
	_base_needs_modifier = {
		"hunger_mul": float(config.get("hunger_mul", 1.0)),
		"energy_mul": float(config.get("energy_mul", 1.0)),
		"fun_mul": float(config.get("fun_mul", 1.0)),
		"hunger_add": float(config.get("hunger_add", 0.0)),
		"energy_add": 0.0,
		"fun_add": float(config.get("fun_add", 0.22)),
	}
	_no_bench_energy_add = float(config.get("no_bench_energy_add", 0.0))
	_bench_energy_add = float(config.get("bench_energy_add", 0.10))
	_bench_fun_add_bonus = float(config.get("bench_fun_add_bonus", 0.03))
	_stop_energy_threshold = float(config.get("stop_energy_threshold", 18.0))
	_stop_health_threshold = float(config.get("stop_health_threshold", 35.0))
	_rest_min_minutes = int(config.get("min_minutes", 10))
	_rest_max_minutes = int(config.get("max_minutes", 20))
	if _rest_max_minutes < _rest_min_minutes:
		_rest_max_minutes = _rest_min_minutes
	_rest_minutes_target = maxi(max_minutes, 0) if max_minutes >= 0 else randi_range(_rest_min_minutes, _rest_max_minutes)

func start(world, citizen) -> void:
	super.start(world, citizen)
	_using_bench = false
	_bench_reservation = {}
	_park_ref = null
	_phase = PHASE_DONE
	_rest_minutes_elapsed = 0
	_bench_target_pos = Vector3.ZERO
	_bench_target_yaw = 0.0
	if citizen != null and citizen.has_method("clear_rest_pose"):
		citizen.clear_rest_pose(true)

	var park := _get_park(citizen)
	_park_ref = park
	if park == null:
		finished = true
		return

	if park.has_method("get_reserved_bench_for"):
		_bench_reservation = park.get_reserved_bench_for(citizen)
	if _bench_reservation.is_empty() and park.has_method("reserve_bench_for"):
		_bench_reservation = park.reserve_bench_for(citizen, citizen.global_position)

	if not _bench_reservation.is_empty():
		_using_bench = true
		_bench_target_pos = _bench_reservation.get("position", citizen.global_position)
		_bench_target_yaw = float(_bench_reservation.get("yaw", citizen.rotation.y))
		if _is_near_position(citizen.global_position, _bench_target_pos):
			_enter_rest_phase(citizen)
			return
		if _begin_move_to_bench(world, citizen, park):
			return
		_release_park_bench(world, citizen, park)
		_using_bench = false
		_bench_reservation = {}

	_enter_rest_phase(citizen)

func get_needs_modifier(world, citizen) -> Dictionary:
	var modifier := _base_needs_modifier.duplicate(true)
	modifier["energy_add"] = _bench_energy_add if _using_bench else _no_bench_energy_add
	if _using_bench:
		modifier["fun_add"] = float(modifier.get("fun_add", 0.0)) + _bench_fun_add_bonus
	if citizen != null and citizen.current_location is Park:
		var park := citizen.current_location as Park
		var service_mul := park.get_service_multiplier()
		modifier["energy_add"] = float(modifier.get("energy_add", 0.0)) * service_mul
		modifier["fun_add"] = float(modifier.get("fun_add", 0.0)) * service_mul
	return modifier

func tick(world, citizen, dt: int) -> void:
	super.tick(world, citizen, dt)
	if citizen == null:
		finished = true
		return

	var park := _get_owned_park(citizen)
	match _phase:
		PHASE_MOVE_TO_BENCH:
			if park == null:
				finished = true
				return
			if citizen.is_travelling():
				return
			if _using_bench and _is_near_position(citizen.global_position, _bench_target_pos):
				_enter_rest_phase(citizen)
				return
			_release_park_bench(world, citizen, park)
			_using_bench = false
			_bench_reservation = {}
			_enter_rest_phase(citizen)
		PHASE_REST:
			if park == null:
				finished = true
				return
			_rest_minutes_elapsed += dt
			if citizen.needs.hunger >= citizen.hunger_threshold \
				or citizen.needs.energy <= _stop_energy_threshold \
				or citizen.needs.health <= _stop_health_threshold \
				or citizen.needs.fun >= citizen.needs.TARGET_FUN_MIN \
				or _rest_minutes_elapsed >= _rest_minutes_target:
				_begin_exit_phase(world, citizen, park)
		PHASE_EXIT_PARK:
			if citizen.is_travelling():
				return
			if park != null and citizen.current_location == park:
				citizen.leave_current_location(world, true)
			_phase = PHASE_DONE
			finished = true
		_:
			finished = true

func finish(world, citizen) -> void:
	var park := _get_owned_park(citizen)
	if citizen != null and citizen.has_method("clear_rest_pose"):
		citizen.clear_rest_pose(true)
	if citizen != null and citizen.is_travelling():
		citizen.stop_travel()
	if citizen != null and park != null and citizen.current_location == park:
		citizen.leave_current_location(world, false)
	_release_park_bench(world, citizen, park)
	if citizen != null:
		citizen.decision_cooldown_left = 0
	_using_bench = false
	_bench_reservation = {}
	_park_ref = null
	_phase = PHASE_DONE
	_rest_minutes_elapsed = 0
	_bench_target_pos = Vector3.ZERO
	_bench_target_yaw = 0.0

func is_using_bench() -> bool:
	return _using_bench

func _get_park(citizen) -> Park:
	if citizen == null:
		return null
	if citizen.current_location is Park:
		return citizen.current_location as Park
	return null

func _get_owned_park(citizen) -> Park:
	if _park_ref != null and is_instance_valid(_park_ref):
		return _park_ref
	return _get_park(citizen)

func _enter_rest_phase(citizen) -> void:
	_phase = PHASE_REST
	_rest_minutes_elapsed = 0
	if citizen == null:
		return
	citizen.stop_travel()
	if _using_bench and not _bench_reservation.is_empty() and citizen.has_method("set_rest_pose"):
		citizen.set_rest_pose(_bench_target_pos, _bench_target_yaw)
	elif citizen.has_method("clear_rest_pose"):
		citizen.clear_rest_pose(true)

func _begin_move_to_bench(world, citizen, park: Park) -> bool:
	if citizen == null or park == null or not citizen.has_method("begin_custom_travel_route"):
		return false
	var route := _build_bench_route(world, citizen, park)
	if route.is_empty():
		return false
	var started: bool = citizen.begin_custom_travel_route(route)
	if started:
		_phase = PHASE_MOVE_TO_BENCH
		SimLogger.log("[Citizen %s] Park bench route start=%s target=%s route_points=%d" % [
			citizen.citizen_name,
			_format_point(citizen.global_position),
			_format_point(_bench_target_pos),
			route.size()
		])
	return started

func _begin_exit_phase(world, citizen, park: Park) -> void:
	if citizen == null:
		finished = true
		return
	if citizen.has_method("clear_rest_pose"):
		citizen.clear_rest_pose(true)
	if park == null:
		finished = true
		return

	var route := _build_exit_route(world, citizen, park)
	if citizen.has_method("begin_custom_travel_route") and not route.is_empty() and citizen.begin_custom_travel_route(route):
		_phase = PHASE_EXIT_PARK
		SimLogger.log("[Citizen %s] Park exit route start=%s target=%s route_points=%d" % [
			citizen.citizen_name,
			_format_point(citizen.global_position),
			_format_point(route[route.size() - 1]),
			route.size()
		])
		return

	if citizen.current_location == park:
		citizen.leave_current_location(world, true)
	_phase = PHASE_DONE
	finished = true

func _build_bench_route(world, citizen, park: Park) -> PackedVector3Array:
	var route := PackedVector3Array()
	if citizen == null or park == null:
		return route

	var nav_points: Dictionary = citizen.get_navigation_points_for_building(park, world)
	if park.has_method("get_internal_navigation_route"):
		route = park.get_internal_navigation_route(nav_points)
	if route.is_empty():
		_append_route_point(route, _bench_target_pos)
	elif route[route.size() - 1].distance_to(_bench_target_pos) > 0.15:
		_append_route_point(route, _bench_target_pos)
	return route

func _build_exit_route(world, citizen, park: Park) -> PackedVector3Array:
	var route := PackedVector3Array()
	if citizen == null or park == null:
		return route

	var nav_points: Dictionary = citizen.get_navigation_points_for_building(park, world)
	if _using_bench and not _bench_reservation.is_empty() and park.has_method("get_internal_navigation_route"):
		var inward_route := park.get_internal_navigation_route(nav_points)
		for idx in range(inward_route.size() - 1, -1, -1):
			_append_route_point(route, inward_route[idx])
	var spawn_pos: Vector3 = nav_points.get("spawn", nav_points.get("access", citizen.global_position))
	_append_route_point(route, spawn_pos)
	return route

func _append_route_point(route: PackedVector3Array, point: Vector3) -> void:
	if route.is_empty() or route[route.size() - 1].distance_to(point) > 0.15:
		route.append(point)

func _release_park_bench(world, citizen, park: Park) -> void:
	if citizen != null and citizen.has_method("release_reserved_benches"):
		citizen.release_reserved_benches(world, park)
	elif park != null and park.has_method("release_bench_for"):
		park.release_bench_for(citizen)

func _is_near_position(a: Vector3, b: Vector3, tolerance: float = 0.35) -> bool:
	var planar := a - b
	planar.y = 0.0
	return planar.length() <= tolerance

func _format_point(pos: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [pos.x, pos.y, pos.z]
