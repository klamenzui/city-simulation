extends RefCounted
class_name CitizenAgent

const NeedsComponentScript = preload("res://Simulation/Citizens/CitizenNeedsComponent.gd")
const LocomotionScript = preload("res://Simulation/Citizens/CitizenLocomotion.gd")
const PlannerScript = preload("res://Simulation/Citizens/CitizenPlanner.gd")

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

	if citizen.current_action != null:
		citizen.current_action.tick(world, citizen, world.minutes_per_tick)
		if citizen.current_action.is_done():
			citizen.current_action.finish(world, citizen)
			citizen.current_action = null
		return

	if citizen.decision_cooldown_left > 0:
		citizen.decision_cooldown_left -= world.minutes_per_tick
		if citizen.decision_cooldown_left > 0:
			return

	planner.plan_next_action(world, citizen)
	citizen.decision_cooldown_left = randi_range(citizen.decision_cooldown_range_min, citizen.decision_cooldown_range_max)