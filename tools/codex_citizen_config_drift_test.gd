extends SceneTree

## Drift guard between CitizenController @export vars and CitizenConfig fields.
##
## `_build_config` no longer copies fields one by one — it calls
## `CitizenConfig.populate_from(self)` which iterates `CitizenConfig.FIELD_NAMES`.
## A field that exists as @export but isn't in FIELD_NAMES never reaches the
## navigation modules — silently. A field in FIELD_NAMES without a matching
## @export silently keeps its default. This test fails on either drift.
##
## Implementation parses CitizenController.gd's source for `@export` lines
## (avoids needing to instantiate a CharacterBody3D in headless mode) and
## compares against CitizenConfig.FIELD_NAMES + property reflection.

const CONTROLLER_PATH: String = "res://Entities/Citizens/New/CitizenController.gd"
const CONFIG_PATH: String = "res://Entities/Citizens/New/Navigation/CitizenConfig.gd"

## Names that exist as @export on the Controller intentionally but are NOT
## supposed to be mirrored into CitizenConfig (scene-bound runtime knobs).
const CONTROLLER_ONLY_EXPORTS: Array[String] = [
	"accept_click_input",      # input gate, scene-instance flag, see C1 fix
	"obstacle_down_ray_path",  # NodePath, resolved into JumpController directly
	"enable_file_log",         # logger toggle, separate from navigation config
	"log_min_level",           # logger level, separate
	"log_flush_interval",      # logger flush, separate
	"log_file_path",           # logger path, separate
]


func _init() -> void:
	print("=== CitizenConfig drift test ===")

	var controller_exports := _parse_exports(CONTROLLER_PATH)
	if controller_exports.is_empty():
		printerr("FAIL: cannot parse @export vars from %s" % CONTROLLER_PATH)
		quit(1)
		return

	var config_fields := _get_config_field_names()
	if config_fields.is_empty():
		printerr("FAIL: CitizenConfig.FIELD_NAMES is empty")
		quit(1)
		return

	print("controller @export vars: %d" % controller_exports.size())
	print("config FIELD_NAMES:      %d" % config_fields.size())
	print("controller-only exempt:  %d" % CONTROLLER_ONLY_EXPORTS.size())
	print()

	var failures := 0

	# (1) Every FIELD_NAMES entry must have a matching @export on the controller.
	for field in config_fields:
		if not controller_exports.has(field):
			printerr("  FAIL  CitizenConfig.FIELD_NAMES has '%s' but CitizenController has no matching @export" % field)
			failures += 1

	# (2) Every controller @export not in CONTROLLER_ONLY_EXPORTS must be in FIELD_NAMES.
	for export_var in controller_exports:
		if CONTROLLER_ONLY_EXPORTS.has(export_var):
			continue
		if not config_fields.has(export_var):
			printerr("  FAIL  CitizenController @export '%s' is missing from CitizenConfig.FIELD_NAMES" % export_var)
			printerr("        (add to FIELD_NAMES + add `var %s` to CitizenConfig, or whitelist in CONTROLLER_ONLY_EXPORTS)" % export_var)
			failures += 1

	# (3) Every FIELD_NAMES entry must be a real property on a CitizenConfig instance.
	var config_instance := CitizenConfig.new()
	var actual_props := _collect_property_names(config_instance)
	for field in config_fields:
		if not actual_props.has(field):
			printerr("  FAIL  CitizenConfig.FIELD_NAMES has '%s' but no matching `var %s`" % [field, field])
			failures += 1

	if failures > 0:
		print("RESULT: FAIL (%d drift issue(s))" % failures)
		quit(1)
		return

	print("RESULT: PASS")
	print("=== End drift test ===")
	quit(0)


func _parse_exports(path: String) -> Array[String]:
	var source := FileAccess.get_file_as_string(path)
	if source.is_empty():
		return []
	var pattern := RegEx.new()
	# Matches: @export, @export_range(...), @export_flags_3d_physics, @export_node_path("..."), etc.
	# Captures the variable name in group 1.
	pattern.compile("(?m)^@export(?:_\\w+(?:\\([^)]*\\))?)?\\s+var\\s+(\\w+)")
	var found: Array[String] = []
	for m in pattern.search_all(source):
		var name := m.get_string(1)
		if not found.has(name):
			found.append(name)
	return found


func _get_config_field_names() -> Array[String]:
	var instance := CitizenConfig.new()
	var raw_value: Variant = instance.get("FIELD_NAMES")
	if raw_value == null:
		# FIELD_NAMES is a const — read via class
		return CitizenConfig.FIELD_NAMES
	return raw_value as Array[String]


func _collect_property_names(obj: Object) -> Array[String]:
	var names: Array[String] = []
	for prop in obj.get_property_list():
		var n: String = str(prop.get("name", ""))
		if n.is_empty() or n.begins_with("_") or n == "script":
			continue
		names.append(n)
	return names
