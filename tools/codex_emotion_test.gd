extends SceneTree

## Focused test for the derived-emotion model (Step 3c).
## Verifies CitizenEmotion.compute() stress/loneliness math + clamps, the
## social-priority multiplier (loneliness gain + high-stress damp + clamp),
## that planner.emotion config is loaded, and that the emotion multiplier
## actually scales the soft `social` candidate (enabled vs disabled).
## Pure stub/math test — no scene bootstrap.

const CitizenEmotionScript = preload("res://Simulation/Citizens/CitizenEmotion.gd")
const CitizenPlannerScript = preload("res://Simulation/Citizens/CitizenPlanner.gd")

var failures: int = 0

var _cfg := {
	"stress_hunger_threshold": 75.0,
	"stress_hunger_add": 0.30,
	"stress_energy_threshold": 20.0,
	"stress_energy_add": 0.30,
	"loneliness_base": 0.2,
	"loneliness_social_threshold": 30.0,
	"loneliness_social_add": 0.25,
	"loneliness_home_night_add": 0.05,
	"loneliness_social_gain": 0.6,
	"stress_social_damp_threshold": 0.85,
	"stress_social_damp_mul": 0.5,
	"social_mult_min": 0.3,
	"social_mult_max": 2.0,
}


class StubTime:
	var hour: int = 12
	func get_hour() -> int: return hour
	func get_minute() -> int: return 0
	func is_weekend() -> bool: return false


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
	var current_location = null


func _priority_of(candidates: Array, id: String) -> float:
	for entry in candidates:
		if str(entry.get("id", "")) == id:
			return float(entry.get("priority", 0.0))
	return -1.0


func _init() -> void:
	print("=== Emotion model test ===")

	# --- compute(): baseline ---
	var calm: Dictionary = CitizenEmotionScript.compute(10.0, 90.0, 100.0, false, false, _cfg)
	_assert_approx("calm stress 0", calm["stress"], 0.0, 0.0001)
	_assert_approx("calm loneliness = base", calm["loneliness"], 0.2, 0.0001)

	# --- compute(): hungry + tired -> stress 0.6 ---
	var tense: Dictionary = CitizenEmotionScript.compute(80.0, 15.0, 100.0, false, false, _cfg)
	_assert_approx("stress hunger+energy", tense["stress"], 0.6, 0.0001)

	# --- compute(): lonely at home at night ---
	var lonely: Dictionary = CitizenEmotionScript.compute(10.0, 90.0, 10.0, true, true, _cfg)
	_assert_approx("loneliness base+social+homenight", lonely["loneliness"], 0.5, 0.0001)

	# --- multiplier: loneliness gain ---
	_assert_approx("mult loneliness 0.5",
		CitizenEmotionScript.social_priority_multiplier({"stress": 0.0, "loneliness": 0.5}, _cfg),
		1.0 + 0.5 * 0.6, 0.0001)

	# --- multiplier: high stress damp ---
	_assert_approx("mult high-stress damp",
		CitizenEmotionScript.social_priority_multiplier({"stress": 0.9, "loneliness": 0.5}, _cfg),
		(1.0 + 0.5 * 0.6) * 0.5, 0.0001)

	# --- multiplier: clamp to social_mult_max ---
	var clamp_cfg := _cfg.duplicate()
	clamp_cfg["social_mult_max"] = 1.2
	_assert_approx("mult clamped to max",
		CitizenEmotionScript.social_priority_multiplier({"stress": 0.0, "loneliness": 1.0}, clamp_cfg),
		1.2, 0.0001)

	# --- planner integration: emotion scales the social candidate ---
	var planner = CitizenPlannerScript.new()
	_assert_eq("config: emotion enabled", planner._emotion_enabled, true)
	_assert_true("config: emotion cfg loaded",
		planner._emotion_cfg.has("loneliness_social_gain"))

	var world := StubWorld.new()
	world.time = StubTime.new()  # hour 12 -> not night, social_deficit not reduced

	var c := StubCitizen.new()
	c.needs = StubNeeds.new()
	c.needs.social = 0.0  # lonely (loneliness = base 0.2 + 0.25 = 0.45)

	planner._emotion_enabled = true
	var p_on := _priority_of(planner._build_goal_candidates(world, c), "social")
	planner._emotion_enabled = false
	var p_off := _priority_of(planner._build_goal_candidates(world, c), "social")

	_assert_true("emotion raises social priority", p_on > p_off)
	_assert_approx("social scaled by loneliness mult", p_on, p_off * (1.0 + 0.45 * 0.6), 0.0005)

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
