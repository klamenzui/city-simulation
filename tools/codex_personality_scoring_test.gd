extends SceneTree

## Focused test for personality factors in CitizenPlanner soft goal scoring
## (Step 1b). Verifies that work_motivation / fun_interest scale the work /
## fun goal priorities, that the midpoint is neutral, and that the
## planner.personality config block is loaded from balance.json.
##
## Uses lightweight duck-typed stubs so no scene bootstrap is required.
## _build_goal_candidates only needs world.time + a citizen with needs.

const CitizenPlannerScript = preload("res://Simulation/Citizens/CitizenPlanner.gd")

var failures: int = 0


class StubTime:
	var hour: int = 12
	var minute: int = 0
	var weekend: bool = false
	func get_hour() -> int: return hour
	func get_minute() -> int: return minute
	func is_weekend() -> bool: return weekend


class StubWorld:
	var time


class StubNeeds:
	var hunger: float = 10.0
	var energy: float = 90.0
	var fun: float = 0.0
	var health: float = 100.0
	var TARGET_FUN_MIN: float = 30.0


class StubJob:
	var workplace
	var shift_hours: int = 8
	var start_hour: int = 9
	func meets_requirements(_c) -> bool: return true


class StubCitizen:
	var needs
	var hunger_threshold: float = 60.0
	var low_energy_threshold: float = 35.0
	var job = null
	var schedule_offset: int = 0
	var work_minutes_today: int = 0
	var work_motivation: float = 1.0
	var fun_interest: float = 0.35


func _make_world() -> StubWorld:
	var w := StubWorld.new()
	w.time = StubTime.new()
	return w


func _make_citizen() -> StubCitizen:
	var c := StubCitizen.new()
	c.needs = StubNeeds.new()
	return c


func _priority_of(candidates: Array, id: String) -> float:
	for entry in candidates:
		if str(entry.get("id", "")) == id:
			return float(entry.get("priority", 0.0))
	return -1.0


func _init() -> void:
	print("=== Personality scoring test ===")
	var planner = CitizenPlannerScript.new()

	_assert_eq("config: personality enabled", planner._personality_enabled, true)
	_assert_approx("config: fun scale loaded", planner._pers_fun_scale, 0.6, 0.0001)

	var world := _make_world()

	# --- Fun multiplier (job = null isolates the fun goal) ---
	var c_mid := _make_citizen()
	c_mid.fun_interest = 0.35
	var p_mid := _priority_of(planner._build_goal_candidates(world, c_mid), "fun")

	var c_high := _make_citizen()
	c_high.fun_interest = 0.9
	var p_high := _priority_of(planner._build_goal_candidates(world, c_high), "fun")

	var c_low := _make_citizen()
	c_low.fun_interest = 0.0
	var p_low := _priority_of(planner._build_goal_candidates(world, c_low), "fun")

	_assert_true("fun: mid priority > 0", p_mid > 0.0)
	_assert_approx("fun: high ~ mid * 1.3", p_high, p_mid * 1.3, 0.0005)
	_assert_approx("fun: low ~ mid * 0.79", p_low, p_mid * 0.79, 0.0005)
	_assert_true("fun: high > low (monotonic)", p_high > p_low)

	# --- Work multiplier (job stub puts the citizen inside the work window) ---
	var c_wm1 := _make_citizen()
	c_wm1.job = StubJob.new()
	c_wm1.job.workplace = RefCounted.new()
	c_wm1.work_motivation = 1.0
	var w1 := _priority_of(planner._build_goal_candidates(world, c_wm1), "work")

	var c_wm14 := _make_citizen()
	c_wm14.job = StubJob.new()
	c_wm14.job.workplace = RefCounted.new()
	c_wm14.work_motivation = 1.4
	var w14 := _priority_of(planner._build_goal_candidates(world, c_wm14), "work")

	_assert_true("work: base priority > 0", w1 > 0.0)
	_assert_approx("work: wm1.4 ~ wm1.0 * 1.4", w14, w1 * 1.4, 0.0005)

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


func _assert_approx(name: String, got: float, expected: float, eps: float) -> void:
	if absf(got - expected) <= eps:
		print("  OK   %s (%.5f ~ %.5f)" % [name, got, expected])
	else:
		failures += 1
		print("  FAIL %s: got %.5f expected %.5f" % [name, got, expected])
