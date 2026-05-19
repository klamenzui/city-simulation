extends SceneTree

## Focused test for per-goal cooldowns in CitizenPlanner (Step 2).
## Verifies the planner.goal_cooldowns config is loaded, that a picked
## goal is throttled for its configured sim-minutes, that 0-minute goals
## are never throttled, that cooldown state is per-citizen, that the
## enabled flag disables the whole mechanism, and that the sim-minute
## helper computes an absolute monotone minute (with hour/minute fallback).
##
## Pure helper-level test with lightweight stubs — no scene bootstrap.

const CitizenPlannerScript = preload("res://Simulation/Citizens/CitizenPlanner.gd")
const GoToBuildingActionScript = preload("res://Actions/GoToBuildingAction.gd")
const RelaxAtHomeActionScript = preload("res://Actions/RelaxAtHomeAction.gd")

var failures: int = 0


class StubTimeAbsolute:
	var day: int = 2
	var minutes_total: int = 100


class StubTimeFallback:
	var day: int = 3
	func get_hour() -> int: return 9
	func get_minute() -> int: return 30


class StubWorld:
	var time


class StubCitizenWithAction:
	var current_action = null


func _init() -> void:
	print("=== Goal cooldown test ===")
	var planner = CitizenPlannerScript.new()

	_assert_eq("config: cooldowns enabled", planner._goal_cooldowns_enabled, true)
	_assert_eq("config: fun cooldown minutes", int(planner._goal_cooldown_minutes.get("fun", -1)), 20)
	_assert_eq("config: hunger cooldown minutes", int(planner._goal_cooldown_minutes.get("hunger", -1)), 0)

	# --- _sim_total_minutes ---
	var w_abs := StubWorld.new()
	w_abs.time = StubTimeAbsolute.new()
	var now: int = CitizenPlannerScript._sim_total_minutes(w_abs)
	_assert_eq("sim minutes absolute (day2 +100)", now, (2 - 1) * 24 * 60 + 100)

	var w_fb := StubWorld.new()
	w_fb.time = StubTimeFallback.new()
	_assert_eq("sim minutes fallback (day3, 09:30)",
			CitizenPlannerScript._sim_total_minutes(w_fb), (3 - 1) * 24 * 60 + 9 * 60 + 30)

	# --- per-goal throttle window ---
	var a := RefCounted.new()
	var b := RefCounted.new()

	_assert_true("fun not on cooldown initially", not planner._is_goal_on_cooldown(a, "fun", now))
	planner._set_goal_cooldown(a, "fun", now)
	_assert_true("fun on cooldown +10", planner._is_goal_on_cooldown(a, "fun", now + 10))
	_assert_true("fun on cooldown +19", planner._is_goal_on_cooldown(a, "fun", now + 19))
	_assert_true("fun free again at +20 (boundary)", not planner._is_goal_on_cooldown(a, "fun", now + 20))
	_assert_true("fun free at +25", not planner._is_goal_on_cooldown(a, "fun", now + 25))

	# --- 0-minute goal is never throttled ---
	planner._set_goal_cooldown(a, "hunger", now)
	_assert_true("hunger never on cooldown (0 min)", not planner._is_goal_on_cooldown(a, "hunger", now))

	# --- per-citizen isolation ---
	_assert_true("other citizen unaffected", not planner._is_goal_on_cooldown(b, "fun", now + 5))

	# --- enabled flag disables the mechanism ---
	planner._goal_cooldowns_enabled = false
	_assert_true("disabled flag bypasses cooldown",
			not planner._is_goal_on_cooldown(a, "fun", now + 5))

	# --- travel actions are only setup steps, not goal completion ---
	var actor := StubCitizenWithAction.new()
	_assert_true("no action does not defer cooldown",
			not planner._should_defer_goal_cooldown(actor))
	actor.current_action = GoToBuildingActionScript.new(null, 20)
	_assert_true("GoToBuilding defers goal cooldown",
			planner._should_defer_goal_cooldown(actor))
	actor.current_action = RelaxAtHomeActionScript.new()
	_assert_true("fulfilling action can start cooldown",
			not planner._should_defer_goal_cooldown(actor))

	print()
	if failures == 0:
		print("RESULT: PASS")
		quit(0)
		return
	print("RESULT: FAIL (%d assertion(s))" % failures)
	quit(1)


func _assert_true(name: String, cond: bool) -> void:
	if cond:
		print("  OK   %s" % name)
	else:
		failures += 1
		print("  FAIL %s" % name)


func _assert_eq(name: String, got, expected) -> void:
	if got == expected:
		print("  OK   %s: %s" % [name, str(got)])
	else:
		failures += 1
		print("  FAIL %s: got %s expected %s" % [name, str(got), str(expected)])
