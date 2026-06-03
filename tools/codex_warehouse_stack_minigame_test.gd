extends SceneTree

const MiniGameScene = preload("res://Scenes/Minigames/WarehouseStack/WarehouseStackMinigame.tscn")


func _initialize() -> void:
	var failures: Array[String] = []
	var game = MiniGameScene.instantiate()
	game.auto_start = false
	game.rng_seed = 12345
	root.add_child(game)

	_expect(game.supports_workplace_type("Factory"), "Factory should be supported", failures)
	_expect(game.supports_workplace_type("Fabrik"), "Fabrik alias should be supported", failures)
	_expect(game.supports_workplace_type("Warehouse"), "Warehouse should be supported", failures)
	_expect(game.supports_workplace_type("Lager"), "Lager alias should be supported", failures)
	_expect(not game.supports_workplace_type("Shop"), "Shop should not use warehouse stack gameplay", failures)

	var base_ids: PackedStringArray = game.get_package_ids_for_skill(0)
	var skilled_ids: PackedStringArray = game.get_package_ids_for_skill(2)
	_expect(base_ids.has("long_crate"), "base run should include long crate", failures)
	_expect(base_ids.has("small_box"), "base run should include small box", failures)
	_expect(base_ids.has("fragile_goods"), "base run should include fragile goods", failures)
	_expect(base_ids.has("cold_goods"), "base run should include cold goods", failures)
	_expect(not base_ids.has("heavy_crate"), "heavy crate should be skill-gated", failures)
	_expect(skilled_ids.has("heavy_crate"), "skilled run should include heavy crate", failures)
	_expect(skilled_ids.has("frozen_pallet"), "skilled run should include frozen pallet", failures)

	var horizontal_cells: Array[Vector2i] = game.get_package_cells("long_crate", 0)
	var vertical_cells: Array[Vector2i] = game.get_package_cells("long_crate", 1)
	_expect_eq(horizontal_cells.size(), 3, "long crate should have three horizontal cells", failures)
	_expect(horizontal_cells.has(Vector2i(2, 0)), "long crate should extend horizontally before rotation", failures)
	_expect(vertical_cells.has(Vector2i(0, 2)), "long crate should extend vertically after rotation", failures)
	_expect(game.package_requires_cold("cold_goods"), "cold goods should require cooling", failures)
	_expect(game.is_cold_cell(Vector2i(6, 0)), "right-side cell should be cold zone", failures)
	_expect(not game.is_cold_cell(Vector2i(5, 0)), "non-cold column should not be cold zone", failures)

	game.start_session()
	var unsupported: Dictionary = game.debug_place_package("small_box", Vector2i(0, 2), 0)
	_expect(not bool(unsupported.get("placed", true)), "floating box should be rejected", failures)
	_expect_eq(str(unsupported.get("reason", "")), "unsupported", "floating box reason", failures)

	game.start_session()
	var cold_outside: Dictionary = game.debug_place_package("cold_goods", Vector2i(0, 0), 0)
	_expect(not bool(cold_outside.get("placed", true)), "cold goods outside cold zone should be rejected", failures)
	_expect_eq(str(cold_outside.get("reason", "")), "cold_zone_required", "cold zone reason", failures)
	var cold_inside: Dictionary = game.debug_place_package("cold_goods", Vector2i(6, 0), 0)
	_expect(bool(cold_inside.get("placed", false)), "cold goods should fit inside cold zone", failures)

	game.start_session()
	var light_floor: Dictionary = game.debug_place_package("small_box", Vector2i(0, 0), 0)
	_expect(bool(light_floor.get("placed", false)), "small box should fit on floor", failures)
	var heavy_on_light: Dictionary = game.debug_place_package("heavy_crate", Vector2i(0, 1), 0)
	_expect(not bool(heavy_on_light.get("placed", true)), "heavy crate should not sit on light box", failures)
	_expect_eq(str(heavy_on_light.get("reason", "")), "heavy_on_light", "heavy-on-light reason", failures)

	game.start_session()
	var fragile_floor: Dictionary = game.debug_place_package("fragile_goods", Vector2i(0, 0), 0)
	_expect(bool(fragile_floor.get("placed", false)), "fragile goods should fit on floor", failures)
	var heavy_over_fragile: Dictionary = game.debug_place_package("heavy_crate", Vector2i(0, 1), 0)
	_expect(not bool(heavy_over_fragile.get("placed", true)), "heavy crate should not be placed above fragile goods", failures)
	_expect_eq(str(heavy_over_fragile.get("reason", "")), "fragile_under_heavy", "fragile-under-heavy reason", failures)

	game.start_session()
	game.debug_place_package("heavy_crate", Vector2i(0, 0), 0)
	game.debug_place_package("heavy_crate", Vector2i(1, 0), 0)
	game.debug_place_package("fragile_goods", Vector2i(0, 1), 0)
	game.debug_place_package("long_crate", Vector2i(2, 0), 0)
	game.debug_place_package("l_package", Vector2i(5, 0), 0)
	game.debug_place_package("cold_goods", Vector2i(7, 0), 0)
	var result: Dictionary = game.get_result()
	_expect(int(result.get("placed_packages", 0)) >= 5, "successful pack should place several packages", failures)
	_expect(float(result.get("storage_efficiency", 0.0)) > 0.2, "successful pack should use meaningful space", failures)
	_expect(float(result.get("packing_quality", 0.0)) > 0.45, "successful pack should produce quality", failures)
	_expect(float(result.get("work_bonus_multiplier", 0.0)) >= 1.0, "successful pack should produce a work bonus", failures)

	game.queue_free()
	if failures.is_empty():
		print("WAREHOUSE_STACK_MINIGAME_TEST OK")
		quit(0)
		return
	print("WAREHOUSE_STACK_MINIGAME_TEST FAILED:")
	for failure in failures:
		print("  - %s" % failure)
	quit(1)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)


func _expect_eq(actual, expected, message: String, failures: Array[String]) -> void:
	if actual != expected:
		failures.append("%s (expected %s, got %s)" % [message, str(expected), str(actual)])
