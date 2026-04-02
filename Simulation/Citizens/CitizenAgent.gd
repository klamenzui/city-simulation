extends RefCounted
class_name CitizenAgent

const NeedsComponentScript = preload("res://Simulation/Citizens/CitizenNeedsComponent.gd")
const LocomotionScript = preload("res://Simulation/Citizens/CitizenLocomotion.gd")
const PlannerScript = preload("res://Simulation/Citizens/CitizenPlanner.gd")
const RelaxAtBenchActionScript = preload("res://Actions/RelaxAtBenchAction.gd")
const RelaxAtParkActionScript = preload("res://Actions/RelaxAtParkAction.gd")

var needs_component = NeedsComponentScript.new()
var locomotion = LocomotionScript.new()
var planner = PlannerScript.new()

func setup(citizen) -> void:
	if citizen == null:
		return
	locomotion.setup(citizen)

func physics_step(citizen, delta: float, world) -> void:
	locomotion.physics_step(citizen, delta, world)

func sim_tick(citizen, world) -> void:
	if citizen == null or world == null:
		return
	if citizen._world_ref == null:
		citizen.set_world_ref(world)

	var h_delta := needs_component.tick_needs(world, citizen)
	citizen._update_work_day(world)
	citizen._update_debug(world, h_delta)
	if citizen.has_method("is_manual_control_enabled") and citizen.is_manual_control_enabled():
		return
	_clear_stale_rest_pose(citizen, world)

	if citizen.current_action != null:
		_tick_current_action(citizen, world)
		return

	if citizen.decision_cooldown_left > 0:
		citizen.decision_cooldown_left -= world.minutes_per_tick
		if citizen.decision_cooldown_left > 0:
			return

	planner.plan_next_action(world, citizen)
	citizen.decision_cooldown_left = randi_range(citizen.decision_cooldown_range_min, citizen.decision_cooldown_range_max)

func _tick_current_action(citizen, world) -> void:
	var action = citizen.current_action
	if action == null:
		return
	action.tick(world, citizen, world.minutes_per_tick)
	if citizen.current_action != action:
		return
	if not action.is_done():
		return
	action.finish(world, citizen)
	if citizen.current_action == action:
		citizen.current_action = null
	_clear_stale_rest_pose(citizen, world)

func _clear_stale_rest_pose(citizen, world) -> void:
	if citizen == null or not citizen.has_method("has_active_rest_pose") or not citizen.has_active_rest_pose():
		return
	if citizen.current_action is RelaxAtParkActionScript or citizen.current_action is RelaxAtBenchActionScript:
		return
	citizen.clear_rest_pose(true)
	if citizen.has_method("release_reserved_benches"):
		citizen.release_reserved_benches(world)
