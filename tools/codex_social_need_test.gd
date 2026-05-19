extends SceneTree

## Focused test for the new `social` need (Step 3a).
## Verifies: defaults + balance.json config load, base per-minute decay,
## clamp to [0,100], and that `social` is decision/health-NEUTRAL — a low
## social value must not drain health (no coupling in advance()).
##
## Needs is a Resource; Needs.new() runs _init() which reads balance.json.

const NeedsScript = preload("res://Actions/Needs.gd")

var failures: int = 0


func _init() -> void:
	print("=== Social need test ===")

	var n = NeedsScript.new()
	_assert_approx("default social", n.social, 70.0, 0.0001)
	_assert_approx("TARGET_SOCIAL_MIN from config", n.TARGET_SOCIAL_MIN, 30.0, 0.0001)
	_assert_approx("social_rate_per_min from config", n.social_rate_per_min, 0.03, 0.0001)

	# Base decay: 10 min * 0.03 = 0.3
	var n2 = NeedsScript.new()
	n2.advance(10)
	_assert_approx("social decays at base rate", n2.social, 70.0 - 0.3, 0.0005)

	# Clamp to 0 (never negative)
	var n3 = NeedsScript.new()
	n3.social = 1.0
	n3.advance(100)
	_assert_approx("social clamped at 0", n3.social, 0.0, 0.0001)

	# Decision/health-neutral: social at 0 must not reduce health.
	var n4 = NeedsScript.new()
	n4.health = 80.0
	n4.hunger = 0.0
	n4.energy = 100.0
	n4.fun = 100.0
	n4.social = 0.0
	n4.advance(60)
	_assert_true("low social does not drain health", n4.health >= 80.0)

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


func _assert_approx(name: String, got: float, expected: float, eps: float) -> void:
	if absf(got - expected) <= eps:
		print("  OK   %s (%.5f ~ %.5f)" % [name, got, expected])
	else:
		failures += 1
		print("  FAIL %s: got %.5f expected %.5f" % [name, got, expected])
