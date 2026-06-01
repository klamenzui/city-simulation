extends RefCounted
class_name GraphSearch

## Shared deterministic A* for small in-memory navigation graphs.
## Graph owners keep topology, positions, and cost rules; this helper only
## owns the queue and path reconstruction mechanics.

static func find_path(
	start_idx: int,
	end_idx: int,
	neighbors: Dictionary,
	heuristic: Callable,
	edge_cost: Callable
) -> Array:
	if start_idx == end_idx:
		return [start_idx]
	if not heuristic.is_valid() or not edge_cost.is_valid():
		return []

	var open: Array = [start_idx]
	var came_from: Dictionary = {}
	var g_score: Dictionary = {start_idx: 0.0}
	var f_score: Dictionary = {start_idx: float(heuristic.call(start_idx, end_idx))}

	while not open.is_empty():
		var current = _pop_best(open, f_score)
		if current == end_idx:
			return _reconstruct_path(came_from, current)

		for raw_neighbor in neighbors.get(current, []):
			var neighbor_idx := int(raw_neighbor)
			var tentative := float(g_score.get(current, INF)) + float(edge_cost.call(current, neighbor_idx))
			if tentative >= float(g_score.get(neighbor_idx, INF)):
				continue

			came_from[neighbor_idx] = current
			g_score[neighbor_idx] = tentative
			f_score[neighbor_idx] = tentative + float(heuristic.call(neighbor_idx, end_idx))
			if not open.has(neighbor_idx):
				open.append(neighbor_idx)

	return []


static func _pop_best(open: Array, f_score: Dictionary):
	var best_idx := 0
	var best_node = open[0]
	var best_val := float(f_score.get(best_node, INF))

	for i in range(1, open.size()):
		var candidate = open[i]
		var candidate_val := float(f_score.get(candidate, INF))
		if candidate_val < best_val:
			best_val = candidate_val
			best_node = candidate
			best_idx = i

	open.remove_at(best_idx)
	return best_node


static func _reconstruct_path(came_from: Dictionary, current) -> Array:
	var path: Array = [current]
	var node = current
	while came_from.has(node):
		node = came_from[node]
		path.push_front(node)
	return path
