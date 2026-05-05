extends SceneTree

## Headless scan-tool diagnostic — runs `LocalGridPlanner.scan_at` at a
## known pedzone point and prints what surface kind / collider every cell
## sees. Goal: pinpoint why the live scan returns "all green" on positions
## where road / wall geometry should clearly be picked up.
##
## User-supplied known-pedzone:  Vector3(13.77, 0.14, 19.26)
## Plus a few sample positions across the map for context.

const PEDZONE_PROBE: Vector3 = Vector3(13.77, 0.14, 19.26)

# Ein paar weitere Punkte zur Kalibrierung. Y aus dem Map-Klick wird
# durch Multi-Hit ground-snap überschrieben, der echte Boden steht im Log.
const SAMPLE_POINTS: Array[Dictionary] = [
	{"label": "user pedzone (mid park-walk)", "pos": Vector3(13.77, 0.14, 19.26)},
	{"label": "near park-wall corner",        "pos": Vector3(11.21, 0.16, 16.26)},
	{"label": "crosswalk transit",             "pos": Vector3(18.87, 0.16, 17.78)},
	{"label": "south sidewalk near target",    "pos": Vector3(20.67, 0.13, 17.11)},
]


func _init() -> void:
	print("=== Scan-tool surface-classification diagnostic ===")

	var main_scene := load("res://Main.tscn")
	if main_scene == null:
		printerr("FAIL: cannot load Main.tscn")
		quit(1)
		return
	var main_instance: Node = main_scene.instantiate()
	root.add_child(main_instance)
	for _i in range(8):
		await process_frame
	await physics_frame
	await physics_frame

	var citizen := main_instance.get_node_or_null("Citizen")
	if citizen == null or not "_local_grid" in citizen:
		printerr("FAIL: $Citizen not found or no _local_grid")
		quit(1)
		return

	for sample in SAMPLE_POINTS:
		var label: String = sample["label"]
		var pos: Vector3 = sample["pos"] as Vector3
		print()
		print("=== ", label, " — ", pos, " ===")
		await _diagnose_at(citizen, pos)

	print()
	print("=== End diagnostic ===")
	quit(0)


func _diagnose_at(citizen: Node, world_pos: Vector3) -> void:
	# Teleport citizen so the surface-probe origin & ground-classification
	# both run with realistic Y. Wait a few frames for landing.
	citizen.global_position = Vector3(world_pos.x, world_pos.y + 3.0, world_pos.z)
	if "velocity" in citizen:
		citizen.velocity = Vector3(0.0, -1.0, 0.0)
	if citizen.has_method("stop_travel"):
		citizen.stop_travel()
	for _i in range(60):
		await physics_frame
		if citizen.has_method("is_on_floor") and citizen.is_on_floor():
			break

	var landed_pos: Vector3 = citizen.global_position
	print("  citizen landed at: (%.3f, %.3f, %.3f)" % [
		landed_pos.x, landed_pos.y, landed_pos.z])

	# Run TWO scans at the same position for A/B comparison:
	#   A) top-hit + height (user idea, sphere off)
	#   B) sphere only (legacy)
	var local_grid = citizen._local_grid
	print("  --- A) top-hit + height ---")
	var result_top: Dictionary = local_grid.scan_at(
			landed_pos, Vector3.FORWARD,
			0.6, 0.10,
			true, 0.25)        # skip_physics=true, height threshold
	_print_scan_summary(result_top)

	print("  --- B) sphere-probe (full radius 0.16) ---")
	var result_sphere: Dictionary = local_grid.scan_at(
			landed_pos, Vector3.FORWARD,
			0.6, 0.10,
			false, NAN,        # skip_physics=false, no height
			NAN)               # default sphere radius
	_print_scan_summary(result_sphere)

	print("  --- C) top-hit + sphere narrow (0.06 = citizen) ---")
	var result_combined: Dictionary = local_grid.scan_at(
			landed_pos, Vector3.FORWARD,
			0.6, 0.10,
			false, 0.25,       # skip_physics=false (sphere on), height threshold
			0.06)              # sphere radius matches citizen capsule
	_print_scan_summary(result_combined)
	# Use top-hit for the cardinal-probe table below.
	var result := result_top

	var cells: Array = result.get("debug_cells", [])
	print("  cells: %d  radius_world: %.2f  step: %.3f" % [
		cells.size(),
		float(result.get("radius_world", 0.0)),
		float(result.get("step", 0.0)),
	])

	var by_surface: Dictionary = {}
	var by_reason: Dictionary = {}
	var by_collider_top: Dictionary = {}  # last path segment of physics collider
	var blocked := 0
	for c in cells:
		var s := str(c.get("surface", "?"))
		by_surface[s] = int(by_surface.get(s, 0)) + 1
		if bool(c.get("blocked", false)):
			blocked += 1
			var r := str(c.get("blocked_reason", "?"))
			by_reason[r] = int(by_reason.get(r, 0)) + 1
			# Top-level collider name = last segment after the last '/' minus the trailing /StaticBody3D.
			var col := str(c.get("collider", ""))
			if not col.is_empty():
				var parts := col.split("/")
				# Walk up two levels: usually .../<asset_name>/StaticBody3D
				var key := col
				if parts.size() >= 2:
					key = parts[parts.size() - 2]
				by_collider_top[key] = int(by_collider_top.get(key, 0)) + 1

	print("  surfaces: %s" % _fmt_count(by_surface))
	print("  blocked: %d  reasons: %s" % [blocked, _fmt_count(by_reason)])
	if not by_collider_top.is_empty():
		print("  blocking colliders (top): %s" % _fmt_count_top(by_collider_top, 6))


func _print_scan_summary(result: Dictionary) -> void:
	var cells: Array = result.get("debug_cells", [])
	var blocked := 0
	var by_reason: Dictionary = {}
	var by_collider_top: Dictionary = {}
	for c in cells:
		if not bool(c.get("blocked", false)):
			continue
		blocked += 1
		var r := str(c.get("blocked_reason", "?"))
		by_reason[r] = int(by_reason.get(r, 0)) + 1
		var col := str(c.get("collider", ""))
		if col.is_empty():
			continue
		var parts := col.split("/")
		var key := parts[parts.size() - 2] if parts.size() >= 2 else col
		by_collider_top[key] = int(by_collider_top.get(key, 0)) + 1
	print("    cells: %d  blocked: %d  reasons: %s" % [
		cells.size(), blocked, _fmt_count(by_reason)])
	if not by_collider_top.is_empty():
		print("    colliders: %s" % _fmt_count_top(by_collider_top, 5))


func _dump_raw_hit(label: String, hit: Dictionary) -> void:
	if hit.is_empty():
		print(label, ": empty")
		return
	var collider: Variant = hit.get("collider", null)
	var collider_path := "?"
	if collider is Node and (collider as Node).is_inside_tree():
		collider_path = str((collider as Node).get_path())
	var pos: Vector3 = hit.get("position", Vector3.ZERO) as Vector3
	# Walk up the chain to see groups + classification.
	var classification := "?"
	if collider is Node:
		classification = SurfaceClassifier.classify_node(collider as Node)
	print(label, ":")
	print("    pos=(%.3f, %.3f, %.3f)  classify=%s" % [pos.x, pos.y, pos.z, classification])
	print("    collider=", collider_path)


func _fmt_count(m: Dictionary) -> String:
	var keys: Array = m.keys()
	keys.sort()
	var parts: Array[String] = []
	for k in keys:
		parts.append("%s=%d" % [str(k), int(m[k])])
	return ", ".join(parts) if parts.size() > 0 else "-"


## Top-N entries by count, descending.
func _fmt_count_top(m: Dictionary, n: int) -> String:
	var entries: Array = []
	for k in m.keys():
		entries.append({"k": k, "v": int(m[k])})
	entries.sort_custom(func(a, b): return a["v"] > b["v"])
	var parts: Array[String] = []
	for i in range(mini(n, entries.size())):
		parts.append("%s=%d" % [str(entries[i]["k"]), int(entries[i]["v"])])
	return ", ".join(parts)
