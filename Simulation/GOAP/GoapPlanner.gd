extends RefCounted
class_name GoapPlanner

static func plan(initial_state: Dictionary, goal_state: Dictionary, actions: Array, max_depth: int = 5) -> Array:
	var best: Dictionary = {
		"cost": INF,
		"plan": []
	}
	var visited: Dictionary = {}
	var path: Array = []
	_search(initial_state, goal_state, actions, path, 0.0, max_depth, best, visited)
	return best["plan"] as Array

static func _search(
	state: Dictionary,
	goal_state: Dictionary,
	actions: Array,
	path: Array,
	cost_so_far: float,
	depth_left: int,
	best: Dictionary,
	visited: Dictionary
) -> void:
	if _goal_reached(state, goal_state):
		if cost_so_far < float(best["cost"]):
			best["cost"] = cost_so_far
			best["plan"] = path.duplicate()
		return

	if depth_left <= 0:
		return
	if cost_so_far >= float(best["cost"]):
		return

	var signature: String = _state_signature(state)
	if visited.has(signature) and float(visited[signature]) <= cost_so_far:
		return
	visited[signature] = cost_so_far

	for action in actions:
		if action == null:
			continue
		if not action.check_preconditions(state):
			continue

		var next_state: Dictionary = action.apply_effects(state)
		if next_state.hash() == state.hash():
			continue

		path.append(action)
		_search(next_state, goal_state, actions, path, cost_so_far + action.cost, depth_left - 1, best, visited)
		path.pop_back()

static func _goal_reached(state: Dictionary, goal_state: Dictionary) -> bool:
	for key in goal_state.keys():
		if not state.has(key):
			return false
		if state[key] != goal_state[key]:
			return false
	return true

static func _state_signature(state: Dictionary) -> String:
	var keys: Array = state.keys()
	keys.sort()
	var parts: PackedStringArray = []
	for key in keys:
		parts.append("%s=%s" % [str(key), str(state[key])])
	return "|".join(parts)
