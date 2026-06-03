extends SceneTree

const MiniGameScene = preload("res://Scenes/Minigames/ServiceFlow/ServiceFlowMinigame.tscn")

const ACTION_TAKE_ORDER := "take_order"
const ACTION_DELIVER_FOOD := "deliver_food"
const ACTION_REFILL_DRINK := "refill_drink"
const ACTION_COLLECT_PAYMENT := "collect_payment"
const ACTION_CLEAN_TABLE := "clean_table"

const STATE_EMPTY := "empty"
const STATE_NEW_ARRIVAL := "new_arrival"
const STATE_WAITING_FOOD := "waiting_food"
const STATE_LOW_DRINK := "low_drink"
const STATE_WANTS_PAY := "wants_pay"
const STATE_DIRTY := "dirty"
const STATE_WRONG_FOOD := "wrong_food"


func _initialize() -> void:
	var failures: Array[String] = []
	var game = MiniGameScene.instantiate()
	game.auto_start = false
	game.rng_seed = 12345
	root.add_child(game)

	_expect(game.supports_workplace_type("Restaurant"), "Restaurant should be supported", failures)
	_expect(game.supports_workplace_type("Cafe"), "Cafe should be supported", failures)
	_expect(game.supports_workplace_type("Bakery"), "Bakery should be supported", failures)
	_expect(game.supports_workplace_type("Baeckerei"), "Baeckerei alias should be supported", failures)
	_expect(not game.supports_workplace_type("Shop"), "Shop should not use service flow", failures)

	_expect_eq(game.get_required_action_for_state(STATE_NEW_ARRIVAL), ACTION_TAKE_ORDER, "new table action", failures)
	_expect_eq(game.get_required_action_for_state(STATE_WAITING_FOOD), ACTION_DELIVER_FOOD, "food action", failures)
	_expect_eq(game.get_required_action_for_state(STATE_LOW_DRINK), ACTION_REFILL_DRINK, "drink action", failures)
	_expect_eq(game.get_required_action_for_state(STATE_WANTS_PAY), ACTION_COLLECT_PAYMENT, "payment action", failures)
	_expect_eq(game.get_required_action_for_state(STATE_DIRTY), ACTION_CLEAN_TABLE, "clean action", failures)
	_expect_eq(game.get_required_action_for_state(STATE_WRONG_FOOD), ACTION_DELIVER_FOOD, "wrong food action", failures)

	var action_ids: PackedStringArray = game.get_action_ids()
	_expect(action_ids.has(ACTION_TAKE_ORDER), "action list should include ordering", failures)
	_expect(action_ids.has(ACTION_CLEAN_TABLE), "action list should include cleaning", failures)

	game.start_session()
	_expect_eq(game.get_table_state(1), STATE_WAITING_FOOD, "table 1 starts waiting for food", failures)
	_expect_eq(game.get_table_state(2), STATE_WANTS_PAY, "table 2 starts wanting payment", failures)
	_expect_eq(game.get_table_state(3), STATE_WRONG_FOOD, "table 3 starts with wrong food", failures)
	_expect_eq(game.get_table_state(4), STATE_NEW_ARRIVAL, "table 4 starts newly arrived", failures)
	_expect_eq(game.get_required_action_for_table(1), ACTION_DELIVER_FOOD, "table 1 required action", failures)
	_expect(game.get_priority_for_table(1) > game.get_priority_for_table(4), "long-waiting table should outrank new arrival", failures)
	_expect_eq(game.get_highest_priority_table_number(), 1, "table 1 should be top priority at start", failures)

	var correct_food: Dictionary = game.debug_perform_action(1, ACTION_DELIVER_FOOD)
	_expect(bool(correct_food.get("correct", false)), "correct food action should pass", failures)
	_expect_eq(game.get_table_state(1), STATE_LOW_DRINK, "food delivery should move table 1 to drink refill", failures)
	_expect(int(correct_food.get("score", 0)) > 0, "correct food action should score", failures)

	var wrong_payment: Dictionary = game.debug_perform_action(2, ACTION_DELIVER_FOOD)
	_expect(not bool(wrong_payment.get("correct", true)), "wrong action should fail", failures)
	_expect_eq(str(wrong_payment.get("required_action", "")), ACTION_COLLECT_PAYMENT, "wrong payment required action", failures)
	_expect_eq(int(wrong_payment.get("combo", -1)), 0, "wrong action should reset combo", failures)

	var collect_payment: Dictionary = game.debug_perform_action(2, ACTION_COLLECT_PAYMENT)
	_expect(bool(collect_payment.get("correct", false)), "payment should be collectable", failures)
	_expect_eq(game.get_table_state(2), STATE_DIRTY, "payment should leave dirty table", failures)
	var clean_table: Dictionary = game.debug_perform_action(2, ACTION_CLEAN_TABLE)
	_expect(bool(clean_table.get("correct", false)), "dirty table should be cleanable", failures)
	_expect_eq(game.get_table_state(2), STATE_EMPTY, "cleaning should free table", failures)

	game.start_session()
	for pair in [
		[1, ACTION_DELIVER_FOOD],
		[1, ACTION_REFILL_DRINK],
		[1, ACTION_COLLECT_PAYMENT],
		[1, ACTION_CLEAN_TABLE],
		[4, ACTION_TAKE_ORDER],
		[4, ACTION_DELIVER_FOOD],
	]:
		var result: Dictionary = game.debug_perform_action(int(pair[0]), str(pair[1]))
		_expect(bool(result.get("correct", false)), "scripted good service should pass for %s" % str(pair), failures)
	var final_result: Dictionary = game.get_result()
	_expect(float(final_result.get("service_quality", 0.0)) >= 0.65, "solid service should create quality", failures)
	_expect(float(final_result.get("work_bonus_multiplier", 0.0)) >= 1.0, "solid service should create work bonus", failures)
	_expect(int(final_result.get("customer_satisfaction_delta", 0)) > 0, "solid service should improve satisfaction", failures)

	game.start_session()
	var start_interval: float = game.debug_get_current_event_interval()
	var start_patience: float = game.debug_get_current_patience_multiplier()
	game.debug_set_elapsed(game.session_duration_sec)
	var end_interval: float = game.debug_get_current_event_interval()
	var end_patience: float = game.debug_get_current_patience_multiplier()
	_expect(end_interval < start_interval, "event interval should shrink over the session", failures)
	_expect(end_patience < start_patience, "table patience should shrink over the session", failures)

	game.start_session()
	_expect(game.debug_force_table_state(4, STATE_NEW_ARRIVAL, 999.0), "force table state should work", failures)
	game.debug_advance_time(0.5)
	_expect_eq(game.get_table_state(4), STATE_DIRTY, "timeout should turn abandoned table dirty", failures)

	game.queue_free()
	if failures.is_empty():
		print("SERVICE_FLOW_MINIGAME_TEST OK")
		quit(0)
		return
	print("SERVICE_FLOW_MINIGAME_TEST FAILED:")
	for failure in failures:
		print("  - %s" % failure)
	quit(1)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)


func _expect_eq(actual, expected, message: String, failures: Array[String]) -> void:
	if actual != expected:
		failures.append("%s (expected %s, got %s)" % [message, str(expected), str(actual)])
