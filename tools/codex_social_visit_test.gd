extends SceneTree

## Focused test for the social_visit goal + CitizenSocialGoap (Step 3b).
## Verifies config load, that CitizenPlanner emits a `social` candidate
## whose priority tracks the social deficit, and that CitizenSocialGoap
## produces a valid go_park -> socialize plan (and none at night unless
## already at the park). Pure stub/plan-level test — no scene bootstrap,
## no action instantiation.

const CitizenPlannerScript = preload("res://Simulation/Citizens/CitizenPlanner.gd")
const CitizenFunGoapScript = preload("res://Simulation/GOAP/CitizenFunGoap.gd")
const CitizenSocialGoapScript = preload("res://Simulation/GOAP/CitizenSocialGoap.gd")
const GoapPlannerScript = preload("res://Simulation/GOAP/GoapPlanner.gd")
const GoToBuildingActionScript = preload("res://Actions/GoToBuildingAction.gd")
const ParkScript = preload("res://Entities/Buildings/Park.gd")

var failures: int = 0


class StubTime:
	var hour: int = 12
	var weekend: bool = false
	func get_hour() -> int: return hour
	func get_minute() -> int: return 0
	func is_weekend() -> bool: return weekend


class StubWorld:
	var time


class StubNeeds:
	var hunger: float = 10.0
	var energy: float = 90.0
	var fun: float = 80.0
	var health: float = 100.0
	var social: float = 0.0
	var TARGET_FUN_MIN: float = 30.0
	var TARGET_SOCIAL_MIN: float = 30.0


class StubCitizen:
	var needs
	var hunger_threshold: float = 60.0
	var low_energy_threshold: float = 35.0
	var job = null
	var schedule_offset: int = 0
	var work_minutes_today: int = 0
	var work_motivation: float = 1.0
	var fun_interest: float = 0.35
	var home = null
	var favorite_park = null
	var favorite_shop = null
	var favorite_cinema = null
	var current_location = null
	var started_action = null

	func start_action(action, _world) -> void:
		started_action = action

	func can_afford_discretionary_shop_item(_world) -> bool:
		return false

	func can_afford_discretionary_cinema(_world) -> bool:
		return false


func _make_world(h: int = 12, weekend: bool = false) -> StubWorld:
	var w := StubWorld.new()
	var t := StubTime.new()
	t.hour = h
	t.weekend = weekend
	w.time = t
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
	print("=== Social visit test ===")
	var planner = CitizenPlannerScript.new()

	_assert_approx("config: social weight", planner._goal_priority_social_weight, 0.6, 0.0001)
	_assert_approx("config: social scale", planner._social_priority_scale, 35.0, 0.0001)
	_assert_eq("config: social cooldown", int(planner._goal_cooldown_minutes.get("social", -1)), 25)

	# --- planner emits a `social` candidate that tracks the deficit ---
	var world := _make_world(12)

	var c_low := _make_citizen()
	c_low.needs.social = 0.0
	var p_low := _priority_of(planner._build_goal_candidates(world, c_low), "social")

	var c_full := _make_citizen()
	c_full.needs.social = 100.0
	var p_full := _priority_of(planner._build_goal_candidates(world, c_full), "social")

	_assert_true("social candidate exists", p_low >= 0.0)
	_assert_true("low social -> positive priority", p_low > 0.0)
	_assert_true("full social -> zero priority", p_full == 0.0)
	_assert_true("low social outranks full", p_low > p_full)

	# --- CitizenSocialGoap produces a valid plan ---
	var goap = CitizenSocialGoapScript.new()
	var park := RefCounted.new()

	var c_no_park := _make_citizen()
	c_no_park.favorite_park = null
	c_no_park.current_location = null
	var no_park_state: Dictionary = goap._build_state(world, c_no_park)
	_assert_eq("no favorite park is not at park", no_park_state.get("at_park"), false)
	var no_park_plan: Array = GoapPlannerScript.plan(no_park_state, {"social_recovered": true}, goap._build_actions(), 6)
	_assert_true("no favorite park has no social plan", no_park_plan.is_empty())
	_assert_eq("social GOAP refuses no-park citizen", goap.try_plan(world, c_no_park), false)

	var c := _make_citizen()
	c.favorite_park = park
	c.current_location = null
	var state: Dictionary = goap._build_state(world, c)
	_assert_eq("state has_park", state.get("has_park"), true)
	_assert_eq("state at_park false", state.get("at_park"), false)
	_assert_eq("state safe_for_social", state.get("safe_for_social"), true)
	_assert_eq("state social_recovered false", state.get("social_recovered"), false)

	var plan: Array = GoapPlannerScript.plan(state, {"social_recovered": true}, goap._build_actions(), 6)
	_assert_true("plan found from away", not plan.is_empty())
	if not plan.is_empty():
		_assert_eq("first step go_park", plan[0].action_id, "go_park")
		var default_park: Park = ParkScript.new()
		var default_trip: GoToBuildingAction = GoToBuildingActionScript.new(default_park, 22)
		_assert_eq("default park trip keeps auto-relax", default_trip.auto_relax_at_park, true)
		var c_exec := _make_citizen()
		c_exec.favorite_park = default_park
		_assert_true("go_park action starts", goap._execute_first_action(plan[0], world, c_exec))
		_assert_true("go_park created travel action", c_exec.started_action != null)
		if c_exec.started_action != null:
			_assert_eq("social park trip suppresses auto-relax",
				bool(c_exec.started_action.auto_relax_at_park), false)
		c_exec.started_action = null
		default_trip = null
		default_park.free()

	var weekend_world := _make_world(14, true)
	var c_weekend := _make_citizen()
	c_weekend.favorite_park = park
	c_weekend.current_location = null
	c_weekend.needs.social = 0.0
	var weekend_priority := _priority_of(planner._build_goal_candidates(weekend_world, c_weekend), "social")
	_assert_true("weekend social remains a positive candidate", weekend_priority > 0.0)
	var weekend_state: Dictionary = goap._build_state(weekend_world, c_weekend)
	var weekend_plan: Array = GoapPlannerScript.plan(weekend_state, {"social_recovered": true}, goap._build_actions(), 6)
	_assert_true("weekend plan found from away", not weekend_plan.is_empty())
	if not weekend_plan.is_empty():
		_assert_eq("weekend first step go_park", weekend_plan[0].action_id, "go_park")

	c.current_location = park
	var state_at: Dictionary = goap._build_state(world, c)
	var plan_at: Array = GoapPlannerScript.plan(state_at, {"social_recovered": true}, goap._build_actions(), 6)
	_assert_true("plan found at park", not plan_at.is_empty())
	if not plan_at.is_empty():
		_assert_eq("first step socialize", plan_at[0].action_id, "socialize")

	# --- at night, cannot start a park trip ---
	var night := _make_world(23)
	var c_night := _make_citizen()
	c_night.favorite_park = park
	c_night.current_location = null
	var night_state: Dictionary = goap._build_state(night, c_night)
	_assert_eq("state is_night", night_state.get("is_night"), true)
	var night_plan: Array = GoapPlannerScript.plan(night_state, {"social_recovered": true}, goap._build_actions(), 6)
	_assert_true("no plan at night when away", night_plan.is_empty())

	var fun_goap = CitizenFunGoapScript.new()
	var c_no_fun_targets := _make_citizen()
	c_no_fun_targets.needs.fun = 0.0
	c_no_fun_targets.current_location = null
	var no_fun_state: Dictionary = fun_goap._build_state(world, c_no_fun_targets)
	_assert_eq("no home is not at home", no_fun_state.get("at_home"), false)
	_assert_eq("no park is not at park for fun", no_fun_state.get("at_park"), false)
	_assert_eq("no shop is not at shop", no_fun_state.get("at_shop"), false)
	_assert_eq("no cinema is not at cinema", no_fun_state.get("at_cinema"), false)
	var no_fun_plan: Array = GoapPlannerScript.plan(no_fun_state, {"fun_recovered": true}, fun_goap._build_actions(), 6)
	_assert_true("no fun destinations has no fun plan", no_fun_plan.is_empty())

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
