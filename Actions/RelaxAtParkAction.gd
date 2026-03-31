extends Action
class_name RelaxAtParkAction

const BalanceConfig = preload("res://Simulation/Config/BalanceConfig.gd")

var _base_needs_modifier: Dictionary = Action.DEFAULT_NEEDS_MOD.duplicate(true)
var _no_bench_energy_add: float = 0.0
var _bench_energy_add: float = 0.10
var _bench_fun_add_bonus: float = 0.03
var _stop_energy_threshold: float = 18.0
var _stop_health_threshold: float = 35.0
var _using_bench: bool = false
var _bench_reservation: Dictionary = {}

func _init(max_minutes: int = -1) -> void:
	var config: Dictionary = BalanceConfig.get_section("actions.relax_park")
	var resolved_max_minutes: int = max_minutes
	if resolved_max_minutes < 0:
		resolved_max_minutes = int(config.get("default_minutes", 90))
	super(resolved_max_minutes)
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

func start(world, citizen) -> void:
	super.start(world, citizen)
	_using_bench = false
	_bench_reservation = {}
	var park := _get_park(citizen)
	if park == null:
		if citizen != null and citizen.has_method("clear_rest_pose"):
			citizen.clear_rest_pose(true)
		return
	if park.has_method("get_reserved_bench_for"):
		_bench_reservation = park.get_reserved_bench_for(citizen)
	if _bench_reservation.is_empty() and park.has_method("reserve_bench_for"):
		_bench_reservation = park.reserve_bench_for(citizen, citizen.global_position)
	if _bench_reservation.is_empty():
		if citizen != null and citizen.has_method("clear_rest_pose"):
			citizen.clear_rest_pose(true)
		return
	_using_bench = true
	if citizen != null and citizen.has_method("set_rest_pose"):
		citizen.set_rest_pose(
			_bench_reservation.get("position", citizen.global_position),
			float(_bench_reservation.get("yaw", citizen.rotation.y))
		)

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
	if _get_park(citizen) == null:
		finished = true
		return

	if citizen.needs.hunger >= citizen.hunger_threshold \
		or citizen.needs.energy <= _stop_energy_threshold \
		or citizen.needs.health <= _stop_health_threshold:
		finished = true
		return

	if citizen.needs.fun >= citizen.needs.TARGET_FUN_MIN:
		finished = true

func finish(world, citizen) -> void:
	var park := _get_park(citizen)
	if citizen != null and citizen.has_method("clear_rest_pose"):
		citizen.clear_rest_pose(true)
	if park != null and park.has_method("release_bench_for"):
		park.release_bench_for(citizen)
	_using_bench = false
	_bench_reservation = {}

func is_using_bench() -> bool:
	return _using_bench

func _get_park(citizen) -> Park:
	if citizen == null:
		return null
	if citizen.current_location is Park:
		return citizen.current_location as Park
	return null
