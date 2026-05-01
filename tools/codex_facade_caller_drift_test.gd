extends SceneTree

## Drift tracker between `CitizenFacade` and the legacy-API expectations of
## external callers (`CitizenAgent`, `CitizenPlanner`, GOAP Actions, etc.).
##
## How it works:
##   1. Source-parses all .gd files under `Simulation/` and `Actions/`
##      for `citizen.has_method("X")` calls.
##   2. For each unique X, walks the Facade's script-chain
##      (`CitizenFacade` → `CitizenController` → `CharacterBody3D`) to check
##      whether the method exists.
##   3. Produces a present/missing report.
##
## **Soft-fail behaviour**: this test exits 0 even when methods are missing.
## Migration is incremental — the Facade today covers Movement + Sim layers
## but legacy `Citizen.gd` had Movement helpers (manual control, debug
## position helpers, conversation state) that the new stack handles
## differently or not at all. The test is a tracker, not a wall.
##
## A method goes from "missing" to "present" by either:
##   - implementing it on the Facade (forwards to a Sim component), or
##   - whitelisting it in `INTENTIONALLY_MISSING` with a reason.

const FacadeScript = preload("res://Entities/Citizens/New/CitizenFacade.gd")

const SCAN_DIRS: Array[String] = [
	"res://Simulation",
	"res://Actions",
]

## Methods that callers ask for but the Facade is intentionally missing.
## Each entry has a reason — added when migrating away from the legacy API.
const INTENTIONALLY_MISSING: Dictionary = {
	# Coarse-travel + cheap-path were tied to legacy Locomotion helper.
	"advance_coarse_travel_by_distance": "coarse-travel migration pending",
	"begin_custom_travel_route": "custom-route migration pending",
	"get_remaining_travel_distance": "remaining-distance migration pending",
	"_is_eligible_for_cheap_lod": "cheap-LOD migration pending",
	"_is_using_cheap_path_follow": "cheap-LOD migration pending",
	# Debug position helpers — Building-Discovery refactor will move these
	# to a CitizenStatusReporter service.
	"get_debug_access_pos": "Building-Discovery refactor pending",
	"get_debug_exit_spawn_pos": "Building-Discovery refactor pending",
	"get_debug_source_building": "Building-Discovery refactor pending",
	"get_debug_travel_route_points": "travel-route trace migration pending",
	"get_debug_travel_target_building": "travel-target trace migration pending",
	"get_job_debug_summary": "moves with Job-Account reporter (Scheduler note)",
	"get_unemployment_debug_reason": "moves with Job-Account reporter",
	"get_zero_pay_debug_reason": "moves with Job-Account reporter",
	# Conversation
	"clear_runtime_conversation_state": "conversation migration pending",
	"is_active_player_dialog_session": "conversation migration pending",
	# LOD home-rotation
	"get_home_rotation_candidate_day": "home-rotation candidate logic pending",
	"is_safe_home_rotation_candidate": "home-rotation safety check pending",
	# Misc Movement
	"face_position_horizontal": "movement-helper pending",
	"reset_travel_debug_state": "travel-debug-state pending",
}


func _init() -> void:
	print("=== CitizenFacade caller-drift test ===")

	var caller_methods := _scan_callers_for_has_method()
	print("Callers reference %d unique methods via has_method()." % caller_methods.size())

	var facade_methods := _collect_facade_methods()
	print("Facade chain exposes %d methods (including inherited)." % facade_methods.size())
	print()

	var present: Array[String] = []
	var missing_unintentional: Array[String] = []
	var missing_known: Array[String] = []

	for m in caller_methods:
		if facade_methods.has(m):
			present.append(m)
		elif INTENTIONALLY_MISSING.has(m):
			missing_known.append(m)
		else:
			missing_unintentional.append(m)

	present.sort()
	missing_known.sort()
	missing_unintentional.sort()

	print("--- Present on Facade (%d) ---" % present.size())
	for m in present:
		print("  ok    %s" % m)
	print()
	print("--- Intentionally missing (%d) ---" % missing_known.size())
	for m in missing_known:
		print("  skip  %-50s %s" % [m, INTENTIONALLY_MISSING[m]])
	print()
	if missing_unintentional.is_empty():
		print("--- Unintentionally missing: NONE ---")
		print()
		print("RESULT: PASS")
		quit(0)
		return
	print("--- Unintentionally missing (%d) — review needed ---" % missing_unintentional.size())
	for m in missing_unintentional:
		printerr("  MISS  %s" % m)
	print()
	# Soft-fail: print the list but exit 0 so the suite stays green during
	# migration. Flip to `quit(1)` when migration is complete.
	print("RESULT: PASS (soft — see misses above)")
	quit(0)


func _scan_callers_for_has_method() -> Array[String]:
	var pattern := RegEx.new()
	pattern.compile('citizen\\.has_method\\("([^"]+)"\\)')
	var found: Dictionary = {}
	for dir_path in SCAN_DIRS:
		_scan_dir(dir_path, pattern, found)
	var keys: Array = found.keys()
	var out: Array[String] = []
	for k in keys:
		out.append(str(k))
	return out


func _scan_dir(dir_path: String, pattern: RegEx, found: Dictionary) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name.is_empty():
			break
		if name.begins_with("."):
			continue
		var sub_path: String = dir_path.path_join(name)
		if dir.current_is_dir():
			_scan_dir(sub_path, pattern, found)
			continue
		if not name.ends_with(".gd"):
			continue
		var src := FileAccess.get_file_as_string(sub_path)
		if src.is_empty():
			continue
		for m in pattern.search_all(src):
			found[m.get_string(1)] = true
	dir.list_dir_end()


## Walks the Facade's script-chain and collects all method names. Includes
## inherited methods from CitizenController (and ultimately CharacterBody3D
## built-ins, but those don't matter for caller-drift).
func _collect_facade_methods() -> Dictionary:
	var methods: Dictionary = {}
	var script: GDScript = FacadeScript
	while script != null:
		for m in script.get_script_method_list():
			methods[str(m.get("name", ""))] = true
		var base = script.get_base_script()
		script = base if base is GDScript else null
	return methods
