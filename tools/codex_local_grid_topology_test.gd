extends SceneTree

## Topology-only test for LocalGridPlanner's neighbour connectivity.
##
## Builds the same doubled-coord cell set the planner would build (all cells
## free, no physics, no scene). Compares two connectivity variants:
##
##   8-NEIGHBOUR (current code):  diagonals + 4 axial
##   6-NEIGHBOUR (Option C fix):  diagonals + horizontal axial only
##
## For a forward-go (start cell at origin, goal cell at the front edge of the
## ring), prints:
##   - waypoints
##   - total length (world units)
##   - max single step (world units)
##   - direction-change count (steps where heading flips by > 5°)
##
## Pure AStar2D — no Godot world, no Main.tscn. Runs in milliseconds.

const CELL_SIZE: float = 0.24      # CitizenConfig defaults
const SUBDIVISIONS: int = 2
const RADIUS: float = 1.2

const NEIGHBOURS_8: Array[Vector2i] = [
	Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1),
	Vector2i(2, 0), Vector2i(-2, 0),
	Vector2i(0, 2), Vector2i(0, -2),
]

const NEIGHBOURS_6: Array[Vector2i] = [
	Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1),
	Vector2i(2, 0), Vector2i(-2, 0),
]


func _init() -> void:
	var step: float = CELL_SIZE / float(SUBDIVISIONS)
	var cell_radius: int = int(ceil(RADIUS / step))
	var doubled_radius: int = cell_radius * 2

	print("=== LocalGridPlanner topology test ===")
	print("cell_size=%.3f  subdivisions=%d  step=%.3f  radius=%.3f  cell_radius=%d" % [
		CELL_SIZE, SUBDIVISIONS, step, RADIUS, cell_radius])
	print()

	# Build the same cell set the planner builds (all free, no obstacles).
	var cells: Array[Vector2i] = _build_cell_set(cell_radius, step)
	print("total cells in ring: %d" % cells.size())

	# Goal: cell with maximum positive Y offset on the forward axis (front edge).
	var goal: Vector2i = _pick_front_goal(cells, step)
	var goal_offset := _cell_offset(goal, step)
	print("goal cell %s  offset=(%.3f, %.3f)  euclid=%.3f" % [
		_fmt_cell(goal), goal_offset.x, goal_offset.y, goal_offset.length()])
	print()

	_run_variant("8-NEIGHBOUR (current code)", cells, NEIGHBOURS_8,
			Vector2i.ZERO, goal, doubled_radius, step)
	print()
	_run_variant("6-NEIGHBOUR (Option C fix)", cells, NEIGHBOURS_6,
			Vector2i.ZERO, goal, doubled_radius, step)
	print()

	# Sweep multiple goals around the front half-circle for a more representative
	# picture (forward, forward-right, hard-right, forward-left, hard-left).
	print("=== Sweep over 5 forward-arc goals ===")
	var sweep_goals: Array[Vector2i] = _pick_arc_goals(cells, step)
	for variant in [
		{"label": "8-NEIGHBOUR", "neighbours": NEIGHBOURS_8},
		{"label": "6-NEIGHBOUR", "neighbours": NEIGHBOURS_6},
	]:
		var label: String = variant["label"]
		var neighbours: Array[Vector2i] = variant["neighbours"]
		var sums := {"waypoints": 0, "length": 0.0, "max_step": 0.0, "dir_changes": 0}
		var ran := 0
		for sweep_goal in sweep_goals:
			var metrics := _measure(cells, neighbours, Vector2i.ZERO,
					sweep_goal, doubled_radius, step)
			if metrics.is_empty():
				continue
			sums["waypoints"] = int(sums["waypoints"]) + int(metrics["waypoints"])
			sums["length"] = float(sums["length"]) + float(metrics["length"])
			sums["max_step"] = maxf(float(sums["max_step"]), float(metrics["max_step"]))
			sums["dir_changes"] = int(sums["dir_changes"]) + int(metrics["dir_changes"])
			ran += 1
		if ran > 0:
			print("%s  avg_waypoints=%.2f  avg_length=%.3f  worst_max_step=%.3f  total_dir_changes=%d  (n=%d)" % [
				label,
				float(sums["waypoints"]) / float(ran),
				float(sums["length"]) / float(ran),
				float(sums["max_step"]),
				int(sums["dir_changes"]),
				ran,
			])

	print()
	print("=== Regression assertions ===")
	var failures := 0
	failures += _assert_better(
			"forward path length",
			_measure(cells, NEIGHBOURS_8, Vector2i.ZERO, goal, doubled_radius, step),
			_measure(cells, NEIGHBOURS_6, Vector2i.ZERO, goal, doubled_radius, step),
			"length")
	failures += _assert_better(
			"forward dir changes",
			_measure(cells, NEIGHBOURS_8, Vector2i.ZERO, goal, doubled_radius, step),
			_measure(cells, NEIGHBOURS_6, Vector2i.ZERO, goal, doubled_radius, step),
			"dir_changes")
	# Hard upper bounds — guard against any future change degrading the 8-NEIGHBOUR
	# path beyond what is acceptable.
	var fwd_metrics := _measure(cells, NEIGHBOURS_8, Vector2i.ZERO, goal, doubled_radius, step)
	failures += _assert_le("forward length",
			float(fwd_metrics["length"]), 1.20)
	failures += _assert_le("forward dir_changes",
			float(fwd_metrics["dir_changes"]), 3.0)
	failures += _assert_le("forward max_step",
			float(fwd_metrics["max_step"]), 0.13)

	if failures > 0:
		push_error("LocalGrid topology test: %d assertion(s) failed" % failures)
		print("RESULT: FAIL (%d assertion(s))" % failures)
		quit(1)
		return
	print("RESULT: PASS")
	print("=== End topology test ===")
	quit(0)


func _assert_better(label: String, a: Dictionary, b: Dictionary, key: String) -> int:
	# 8-NEIGHBOUR (a) must be <= 6-NEIGHBOUR (b) on `key`.
	if a.is_empty() or b.is_empty():
		printerr("  ASSERT %s: empty metrics" % label)
		return 1
	var av: float = float(a[key])
	var bv: float = float(b[key])
	if av <= bv:
		print("  OK    %s: 8-NB=%.4f ≤ 6-NB=%.4f" % [label, av, bv])
		return 0
	printerr("  FAIL  %s: 8-NB=%.4f > 6-NB=%.4f (8-NB should be the better variant)" % [label, av, bv])
	return 1


func _assert_le(label: String, value: float, limit: float) -> int:
	if value <= limit:
		print("  OK    %s: %.4f ≤ %.4f" % [label, value, limit])
		return 0
	printerr("  FAIL  %s: %.4f > %.4f" % [label, value, limit])
	return 1


func _build_cell_set(cell_radius: int, step: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var radius_world: float = float(cell_radius) * step
	for z in range(-cell_radius, cell_radius + 1):
		for x in range(-cell_radius, cell_radius + 1):
			_maybe_add(out, Vector2i(x * 2, z * 2), step, radius_world)
		if z < cell_radius:
			for x in range(-cell_radius, cell_radius):
				_maybe_add(out, Vector2i(x * 2 + 1, z * 2 + 1), step, radius_world)
	return out


func _maybe_add(out: Array[Vector2i], cell: Vector2i, step: float, radius_world: float) -> void:
	var off := _cell_offset(cell, step)
	if off.length() > radius_world:
		return
	out.append(cell)


func _cell_offset(cell: Vector2i, step: float) -> Vector2:
	return Vector2(float(cell.x) * step * 0.5, float(cell.y) * step * 0.5)


func _cell_id(cell: Vector2i, doubled_radius: int) -> int:
	var width := doubled_radius * 2 + 1
	return (cell.y + doubled_radius) * width + cell.x + doubled_radius + 1


func _pick_front_goal(cells: Array[Vector2i], step: float) -> Vector2i:
	# The cell with the highest positive Y offset, ties broken by smallest |X|.
	var best := Vector2i.ZERO
	var best_y := -INF
	var best_abs_x := INF
	for cell in cells:
		var off := _cell_offset(cell, step)
		if off.y < best_y - 0.001:
			continue
		if off.y > best_y + 0.001:
			best_y = off.y
			best_abs_x = absf(off.x)
			best = cell
		else:
			if absf(off.x) < best_abs_x:
				best_abs_x = absf(off.x)
				best = cell
	return best


func _pick_arc_goals(cells: Array[Vector2i], step: float) -> Array[Vector2i]:
	# Goals at ~ -75°, -35°, 0° (forward), +35°, +75° on the front half-circle,
	# closest cell to each direction at near-radius distance.
	var goals: Array[Vector2i] = []
	for angle_deg in [-75.0, -35.0, 0.0, 35.0, 75.0]:
		var rad := deg_to_rad(angle_deg) + PI * 0.5  # 0° = forward (Y+)
		var dir_x: float = cos(rad)
		var dir_y: float = sin(rad)
		var best := Vector2i.ZERO
		var best_dot := -INF
		for cell in cells:
			var off := _cell_offset(cell, step)
			if off.length() < step * 1.5:
				continue
			var dot_val: float = (off.x * dir_x + off.y * dir_y) / off.length()
			if dot_val > best_dot:
				best_dot = dot_val
				best = cell
		goals.append(best)
	return goals


func _run_variant(label: String, cells: Array[Vector2i], neighbours: Array[Vector2i],
		start: Vector2i, goal: Vector2i, doubled_radius: int, step: float) -> void:
	print("--- %s ---" % label)
	var metrics := _measure(cells, neighbours, start, goal, doubled_radius, step)
	if metrics.is_empty():
		print("  no path")
		return
	var path: PackedVector2Array = metrics["path"]
	print("  waypoints       = %d" % int(metrics["waypoints"]))
	print("  total length    = %.4f" % float(metrics["length"]))
	print("  max single step = %.4f" % float(metrics["max_step"]))
	print("  dir changes >5° = %d" % int(metrics["dir_changes"]))
	for idx in range(path.size()):
		var p := path[idx]
		print("    [%d] (%.3f, %.3f)" % [idx, p.x, p.y])


func _measure(cells: Array[Vector2i], neighbours: Array[Vector2i],
		start: Vector2i, goal: Vector2i, doubled_radius: int, step: float) -> Dictionary:
	var astar := AStar2D.new()
	var ids: Dictionary = {}
	for cell in cells:
		var pid := _cell_id(cell, doubled_radius)
		ids[cell] = pid
		astar.add_point(pid, _cell_offset(cell, step))
	for cell in cells:
		var pid: int = ids[cell]
		for off in neighbours:
			var nb: Vector2i = cell + off
			if not ids.has(nb):
				continue
			var nb_id: int = ids[nb]
			if pid < nb_id:
				astar.connect_points(pid, nb_id, true)

	if not ids.has(start) or not ids.has(goal):
		return {}
	var path: PackedVector2Array = astar.get_point_path(ids[start], ids[goal])
	if path.size() < 2:
		return {}

	var total_len := 0.0
	var max_step := 0.0
	var dir_changes := 0
	var prev_dir := Vector2.ZERO
	for idx in range(1, path.size()):
		var seg: Vector2 = path[idx] - path[idx - 1]
		var seg_len := seg.length()
		total_len += seg_len
		if seg_len > max_step:
			max_step = seg_len
		if seg_len > 0.0001:
			var dir_now := seg.normalized()
			if prev_dir != Vector2.ZERO:
				var dot_val: float = clampf(dir_now.dot(prev_dir), -1.0, 1.0)
				if acos(dot_val) > deg_to_rad(5.0):
					dir_changes += 1
			prev_dir = dir_now

	return {
		"path": path,
		"waypoints": path.size(),
		"length": total_len,
		"max_step": max_step,
		"dir_changes": dir_changes,
	}


func _fmt_cell(cell: Vector2i) -> String:
	return "(%d,%d)" % [cell.x, cell.y]
