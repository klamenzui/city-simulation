extends RefCounted
class_name CitizenNeedsComponent

func tick_needs(world, citizen) -> float:
	if world == null or citizen == null:
		return 0.0

	var mod: Dictionary = Action.DEFAULT_NEEDS_MOD.duplicate()
	if citizen.current_action != null:
		mod = citizen.current_action.get_needs_modifier(world, citizen)

	citizen.needs.advance(
		world.minutes_per_tick,
		mod.hunger_mul,
		mod.energy_mul,
		mod.fun_mul,
		mod.get("hunger_add", 0.0),
		mod.energy_add,
		mod.fun_add
	)
	return citizen.needs.get_health_delta()