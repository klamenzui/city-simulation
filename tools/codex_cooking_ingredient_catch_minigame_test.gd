extends SceneTree

const MiniGameScene = preload("res://Scenes/Minigames/CookingIngredientCatch/CookingIngredientCatchMinigame.tscn")


func _initialize() -> void:
	var failures: Array[String] = []
	var game = MiniGameScene.instantiate()
	game.auto_start = false
	game.rng_seed = 12345
	root.add_child(game)

	_expect(game.supports_workplace_type("Restaurant"), "Restaurant should be supported", failures)
	_expect(game.supports_workplace_type("Cafe"), "Cafe should be supported", failures)
	_expect(game.supports_workplace_type("Bakery"), "future Bakery alias should be supported", failures)
	_expect(not game.supports_workplace_type("Shop"), "Shop should not use cooking catch gameplay", failures)

	var restaurant_base_ids: PackedStringArray = game.get_recipe_ids_for_workplace("Restaurant", 0)
	var cafe_base_ids: PackedStringArray = game.get_recipe_ids_for_workplace("Cafe", 0)
	var restaurant_skilled_ids: PackedStringArray = game.get_recipe_ids_for_workplace("Restaurant", 2)
	_expect(restaurant_base_ids.has("sandwich"), "restaurant base run should include sandwich", failures)
	_expect(restaurant_base_ids.has("soup"), "restaurant base run should include soup", failures)
	_expect(restaurant_base_ids.has("burger"), "restaurant base run should include burger", failures)
	_expect(not restaurant_base_ids.has("cake"), "restaurant base run should not include cafe cake", failures)
	_expect(cafe_base_ids.has("cake"), "cafe base run should include cake", failures)
	_expect(not cafe_base_ids.has("pizza"), "cafe base run should not include pizza", failures)
	_expect(restaurant_skilled_ids.has("pizza"), "skilled restaurant run should include pizza", failures)
	_expect(restaurant_skilled_ids.has("pasta"), "skilled restaurant run should include pasta", failures)

	var hearty_soup: Dictionary = game.get_recipe_requirement("hearty_soup")
	_expect_eq(int(hearty_soup.get("carrot", 0)), 2, "hearty soup should require two carrots", failures)
	_expect_eq(int(hearty_soup.get("potato", 0)), 2, "hearty soup should require two potatoes", failures)

	var base_products: PackedStringArray = game.get_product_ids_for_skill(0)
	var skilled_products: PackedStringArray = game.get_product_ids_for_skill(2)
	_expect(base_products.has("bread"), "base products should include bread", failures)
	_expect(base_products.has("sugar"), "base products should include sugar for cake", failures)
	_expect(not base_products.has("butter"), "butter should be skill-gated", failures)
	_expect(skilled_products.has("butter"), "skilled products should include butter", failures)
	_expect(skilled_products.has("spoiled_meat"), "skilled products should include harder harmful distractors", failures)

	game.start_session("sandwich")
	_expect_eq(str(game.current_recipe.get("id", "")), "sandwich", "requested sandwich should start", failures)
	var correct_bread: Dictionary = game.debug_catch_product("bread")
	_expect(bool(correct_bread.get("correct", false)), "bread should be a correct sandwich catch", failures)
	_expect(int(correct_bread.get("score", 0)) > 0, "correct catch should score", failures)
	_expect_eq(int(game.remaining_ingredients.get("bread", -1)), 0, "bread should be completed", failures)

	var missed_cheese: Dictionary = game.debug_miss_product("cheese")
	_expect_eq(int(missed_cheese.get("missed_required_items", -1)), 1, "missing a required item should count as missed", failures)
	_expect_eq(int(missed_cheese.get("mistakes", -1)), 0, "missing a required item should not count as a mistake", failures)

	var wrong_tool: Dictionary = game.debug_catch_product("tool")
	_expect(not bool(wrong_tool.get("correct", true)), "tool should be a wrong product", failures)
	_expect_eq(int(wrong_tool.get("combo", -1)), 0, "wrong product should reset combo", failures)
	_expect(float(wrong_tool.get("quality", 100.0)) < 100.0, "wrong product should reduce quality", failures)

	game.start_session("sandwich")
	for product_id in ["bread", "cheese", "lettuce", "tomato"]:
		game.debug_catch_product(product_id)
	var result: Dictionary = game.get_result()
	_expect(bool(result.get("success", false)), "completed sandwich should succeed", failures)
	_expect_eq(int(result.get("completed_recipes", 0)), 1, "completed sandwich should count one recipe", failures)
	_expect(float(result.get("work_bonus_multiplier", 0.0)) >= 1.0, "successful dish should produce a work bonus multiplier", failures)
	_expect(int(result.get("customer_satisfaction_delta", 0)) > 0, "successful dish should improve customer satisfaction", failures)

	game.start_session("sandwich")
	var start_speed: float = game.debug_get_current_fall_speed()
	var start_interval: float = game.debug_get_current_spawn_interval()
	game.debug_set_elapsed(game.session_duration_sec)
	var end_speed: float = game.debug_get_current_fall_speed()
	var end_interval: float = game.debug_get_current_spawn_interval()
	_expect(end_speed > start_speed, "fall speed should ramp over the session", failures)
	_expect(end_interval < start_interval, "spawn interval should shrink over the session", failures)

	game.queue_free()
	if failures.is_empty():
		print("COOKING_INGREDIENT_CATCH_MINIGAME_TEST OK")
		quit(0)
		return
	print("COOKING_INGREDIENT_CATCH_MINIGAME_TEST FAILED:")
	for failure in failures:
		print("  - %s" % failure)
	quit(1)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)


func _expect_eq(actual, expected, message: String, failures: Array[String]) -> void:
	if actual != expected:
		failures.append("%s (expected %s, got %s)" % [message, str(expected), str(actual)])
