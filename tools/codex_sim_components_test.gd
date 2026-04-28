extends SceneTree

## Smoke test for the Sim-layer components.
##
## Covers (standalone, no scene bootstrap required):
##   CitizenIdentity — defaults, wallet/needs eager construction, slot writes
##   CitizenRestPose — set/clear/state lifecycle
##
## Not covered here (because they need the Main-Scene class registry):
##   CitizenSimulation wiring + apply() on a tree-attached Node3D — those
##   are exercised by the `parse` test (Main.tscn loads the full registry)
##   and by `navroute` (real CharacterBody3D in the tree).
##
## Uses preload (not class_name lookup) — `--script` headless mode does
## not populate the global class registry, so `CitizenIdentity.new()` fails.

const CitizenIdentityScript = preload("res://Entities/Citizens/New/Sim/CitizenIdentity.gd")
const CitizenRestPoseScript = preload("res://Entities/Citizens/New/Sim/CitizenRestPose.gd")
const CitizenLocationScript = preload("res://Entities/Citizens/New/Sim/CitizenLocation.gd")

var failures: int = 0


func _init() -> void:
	print("=== Sim components smoke test ===")
	_test_identity_defaults()
	_test_identity_writes()
	_test_rest_pose_lifecycle()
	_test_location_state()
	_test_location_lane_offset()
	_test_location_nav_points_null_building()
	print()
	if failures == 0:
		print("RESULT: PASS")
		quit(0)
		return
	print("RESULT: FAIL (%d assertion(s))" % failures)
	quit(1)


func _test_identity_defaults() -> void:
	print("-- CitizenIdentity defaults --")
	var identity = CitizenIdentityScript.new()
	_assert_eq("citizen_name default", identity.citizen_name, "Alex")
	_assert_not_null("wallet eager-constructed", identity.wallet)
	_assert_not_null("needs eager-constructed", identity.needs)
	_assert_null("home default null", identity.home)
	_assert_null("job default null", identity.job)
	_assert_null("favorite_park default null", identity.favorite_park)
	_assert_eq("home_food_stock default", identity.home_food_stock, 2)
	_assert_eq("education_level default", identity.education_level, 0)


func _test_identity_writes() -> void:
	print("-- CitizenIdentity slot writes --")
	var identity = CitizenIdentityScript.new()
	identity.citizen_name = "Marie"
	identity.home_food_stock = 7
	identity.education_level = 3
	_assert_eq("citizen_name set", identity.citizen_name, "Marie")
	_assert_eq("home_food_stock set", identity.home_food_stock, 7)
	_assert_eq("education_level set", identity.education_level, 3)


func _test_rest_pose_lifecycle() -> void:
	print("-- CitizenRestPose lifecycle --")
	var owner_node := Node3D.new()
	var pose = CitizenRestPoseScript.new(owner_node)
	_assert_eq("inactive on construct", pose.is_active(), false)

	pose.set_pose(Vector3(1.5, 0.0, 2.0), 1.2)
	_assert_eq("active after set", pose.is_active(), true)
	_assert_eq("position stored", pose.get_position(), Vector3(1.5, 0.0, 2.0))
	_assert_eq("yaw stored", pose.get_yaw(), 1.2)

	pose.clear()
	_assert_eq("inactive after clear", pose.is_active(), false)
	# apply() while inactive must be a no-op, not a crash.
	pose.apply()

	owner_node.free()


func _test_location_state() -> void:
	print("-- CitizenLocation state --")
	var loc = CitizenLocationScript.new()
	_assert_eq("not inside on construct", loc.is_inside(), false)
	_assert_null("inside_building null", loc.get_inside_building())
	# Cannot pass a real Building (needs scene), but set/clear still trackable
	# via subsequent is_inside.
	loc.clear_inside_building()
	_assert_eq("clear is idempotent", loc.is_inside(), false)


func _test_location_lane_offset() -> void:
	print("-- CitizenLocation lane offset (deterministic) --")
	var first := CitizenLocationScript.get_lane_offset("Alex")
	var second := CitizenLocationScript.get_lane_offset("Alex")
	_assert_eq("same name -> same offset", first, second)
	var allowed: Array[float] = [-0.12, -0.04, 0.04, 0.12]
	_assert_eq("offset is in lane set",
			first in allowed, true)
	# Different names should at least cover more than one lane in a small set.
	var offsets: Array = []
	for n in ["Alex", "Marie", "Jonas", "Lara", "Ben", "Chris", "Dana", "Eli"]:
		var o := CitizenLocationScript.get_lane_offset(n)
		if not offsets.has(o):
			offsets.append(o)
	_assert_eq("8 names use at least 2 lanes", offsets.size() >= 2, true)


func _test_location_nav_points_null_building() -> void:
	print("-- CitizenLocation nav points (null building) --")
	var nav := CitizenLocationScript.resolve_navigation_points(
			null, null, "Alex", Vector3.ZERO)
	_assert_eq("null building returns empty dict", nav.is_empty(), true)


# ------------------------- assertion helpers -------------------------

func _assert_eq(label: String, actual: Variant, expected: Variant) -> void:
	if actual == expected:
		print("  OK   %s: %s" % [label, str(actual)])
		return
	printerr("  FAIL %s: got %s, expected %s" % [label, str(actual), str(expected)])
	failures += 1


func _assert_null(label: String, value: Variant) -> void:
	if value == null:
		print("  OK   %s" % label)
		return
	printerr("  FAIL %s: expected null, got %s" % [label, str(value)])
	failures += 1


func _assert_not_null(label: String, value: Variant) -> void:
	if value != null:
		print("  OK   %s" % label)
		return
	printerr("  FAIL %s: expected non-null" % label)
	failures += 1
