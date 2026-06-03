extends SceneTree

const MiniGameScene = preload("res://Scenes/Minigames/RetailWorkSort/RetailWorkSortMinigame.tscn")
const TARGET_CASH_REGISTER := "cash_register"
const TARGET_RETURN_BIN := "return_bin"
const TARGET_HAZARD_SHELF := "hazard_shelf"
const TARGET_STORAGE := "storage"


func _initialize() -> void:
	var failures: Array[String] = []
	var game = MiniGameScene.instantiate()
	game.auto_start = false
	game.rng_seed = 12345
	root.add_child(game)

	_expect(game.supports_workplace_type("Shop"), "Shop should be supported", failures)
	_expect(game.supports_workplace_type("Supermarket"), "Supermarket should be supported", failures)
	_expect(not game.supports_workplace_type("GasStation"), "GasStation should not use retail sorting", failures)

	_expect_eq(game.get_target_for_item("bread"), TARGET_CASH_REGISTER, "bread target", failures)
	_expect_eq(game.get_target_for_item("milk"), TARGET_CASH_REGISTER, "milk target", failures)
	_expect_eq(game.get_target_for_item("meat"), TARGET_CASH_REGISTER, "meat target", failures)
	_expect_eq(game.get_target_for_item("fruit"), TARGET_CASH_REGISTER, "fruit target", failures)
	_expect_eq(game.get_target_for_item("broken_goods"), TARGET_RETURN_BIN, "broken goods target", failures)
	_expect_eq(game.get_target_for_item("expired_food"), TARGET_RETURN_BIN, "expired food target", failures)
	_expect_eq(game.get_target_for_item("cleaning_supply"), TARGET_HAZARD_SHELF, "cleaning supply target", failures)
	_expect_eq(game.get_target_for_item("wrong_article"), TARGET_STORAGE, "wrong article target", failures)

	var basic_ids: PackedStringArray = game.get_item_ids_for_skill(0)
	var skilled_ids: PackedStringArray = game.get_item_ids_for_skill(2)
	_expect(basic_ids.has("expired_food"), "expired food should be a base item", failures)
	_expect(not basic_ids.has("milk_bottle_similar"), "similar milk bottle should be skill-gated", failures)
	_expect(not basic_ids.has("cleaner_bottle_similar"), "similar cleaner bottle should be skill-gated", failures)
	_expect(skilled_ids.has("milk_bottle_similar"), "skilled run should include similar milk bottle", failures)
	_expect(skilled_ids.has("cleaner_bottle_similar"), "skilled run should include similar cleaner bottle", failures)

	var correct_result: Dictionary = game.debug_sort_item("bread", TARGET_CASH_REGISTER)
	_expect(bool(correct_result.get("correct", false)), "correct sort should pass", failures)
	_expect(int(correct_result.get("score", 0)) > 0, "correct sort should score", failures)
	var wrong_result: Dictionary = game.debug_sort_item("cleaning_supply", TARGET_CASH_REGISTER)
	_expect(not bool(wrong_result.get("correct", true)), "wrong target should fail", failures)
	_expect_eq(int(wrong_result.get("combo", -1)), 0, "wrong target should reset combo", failures)

	game.start_session()
	var start_speed: float = game.debug_get_current_speed()
	game.debug_set_elapsed(game.session_duration_sec)
	var end_speed: float = game.debug_get_current_speed()
	_expect(end_speed > start_speed, "conveyor speed should ramp over the session", failures)

	game.queue_free()
	if failures.is_empty():
		print("RETAIL_WORK_SORT_MINIGAME_TEST OK")
		quit(0)
		return
	print("RETAIL_WORK_SORT_MINIGAME_TEST FAILED:")
	for failure in failures:
		print("  - %s" % failure)
	quit(1)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)


func _expect_eq(actual, expected, message: String, failures: Array[String]) -> void:
	if actual != expected:
		failures.append("%s (expected %s, got %s)" % [message, str(expected), str(actual)])
