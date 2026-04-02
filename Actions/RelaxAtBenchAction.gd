extends Action
class_name RelaxAtBenchAction

const BalanceConfig = preload("res://Simulation/Config/BalanceConfig.gd")

var bench_minutes: int = 45
var _needs_modifier: Dictionary = Action.DEFAULT_NEEDS_MOD.duplicate(true)
var _stop_hunger_threshold: float = 70.0
var _stop_health_threshold: float = 35.0

func _init(_bench_minutes: int = -1) -> void:
	super()
	label = "RelaxBench"
	var config: Dictionary = BalanceConfig.get_section("actions.relax_bench")
	bench_minutes = _bench_minutes
	if bench_minutes < 0:
		bench_minutes = int(config.get("default_minutes", 45))
	_needs_modifier = {
		"hunger_mul": float(config.get("hunger_mul", 1.0)),
		"energy_mul": float(config.get("energy_mul", 1.0)),
		"fun_mul": float(config.get("fun_mul", 1.0)),
		"hunger_add": float(config.get("hunger_add", 0.0)),
		"energy_add": float(config.get("energy_add", 0.18)),
		"fun_add": float(config.get("fun_add", 0.0)),
	}
	_stop_hunger_threshold = float(config.get("stop_hunger_threshold", 70.0))
	_stop_health_threshold = float(config.get("stop_health_threshold", 35.0))

func start(world, citizen) -> void:
	super.start(world, citizen)
	if world == null or citizen == null:
		finished = true
		return
	var bench: Dictionary = world.get_reserved_city_bench_for(citizen)
	if bench.is_empty():
		bench = world.reserve_city_bench_for(citizen, citizen.global_position)
	if bench.is_empty():
		finished = true
		return
	citizen.set_rest_pose(
		bench.get("position", citizen.global_position),
		float(bench.get("yaw", citizen.rotation.y))
	)

func get_needs_modifier(world, citizen) -> Dictionary:
	return _needs_modifier

func tick(world, citizen, dt: int) -> void:
	super.tick(world, citizen, dt)
	if world == null or citizen == null:
		finished = true
		return
	if world.get_reserved_city_bench_for(citizen).is_empty():
		finished = true
		return
	if citizen.needs.hunger >= _stop_hunger_threshold or citizen.needs.health <= _stop_health_threshold:
		finished = true
		return
	if elapsed_minutes >= bench_minutes:
		finished = true
		return
	if citizen.needs.energy >= citizen.low_energy_threshold:
		finished = true

func finish(world, citizen) -> void:
	if citizen != null and citizen.has_method("clear_rest_pose"):
		citizen.clear_rest_pose(true)
	if citizen != null and citizen.has_method("release_reserved_benches"):
		citizen.release_reserved_benches(world)
	elif world != null and citizen != null:
		world.release_city_bench_for(citizen)
	if citizen != null:
		citizen.decision_cooldown_left = 0

func is_using_bench(world, citizen) -> bool:
	if world == null or citizen == null:
		return false
	return not world.get_reserved_city_bench_for(citizen).is_empty()
