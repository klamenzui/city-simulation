extends SceneTree

const CitizenPlannerScript = preload("res://Simulation/Citizens/CitizenPlanner.gd")
const ShopScript = preload("res://Entities/Buildings/Shop.gd")
const SupermarketScript = preload("res://Entities/Buildings/Supermarket.gd")

var failures: int = 0


class StubTime:
	var day: int = 1
	var minutes_total: int = 0

	func get_hour() -> int:
		return int(minutes_total / 60) % 24

	func get_minute() -> int:
		return minutes_total % 60


class StubWorld:
	var time

	func _init() -> void:
		time = StubTime.new()


class StubCitizen:
	var current_location = null

	func can_afford_groceries_at(_supermarket, _world) -> bool:
		return true


func _init() -> void:
	print("=== Service arrival window test ===")
	_test_building_minute_windows()
	_test_planner_rejects_service_target_closing_before_arrival()

	print()
	if failures == 0:
		print("RESULT: PASS")
		quit(0)
		return
	print("RESULT: FAIL (%d assertion(s))" % failures)
	quit(1)


func _test_building_minute_windows() -> void:
	var shop: Shop = ShopScript.new()
	shop.job_capacity = 0
	shop.open_hour = 8
	shop.close_hour = 18

	_assert_true("open one minute before close", shop.is_open_at_minute(17 * 60 + 59))
	_assert_true("closed exactly at close minute", not shop.is_open_at_minute(18 * 60))
	_assert_true("arrival buffer allows 17:59", shop.is_open_for_arrival(17 * 60 + 40, 14, 5))
	_assert_true("arrival buffer rejects 18:00", not shop.is_open_for_arrival(17 * 60 + 40, 15, 5))

	shop.open_hour = 20
	shop.close_hour = 2
	_assert_true("overnight shop open before midnight", shop.is_open_for_arrival(23 * 60 + 40, 15, 5))
	_assert_true("overnight shop closed at end boundary", not shop.is_open_for_arrival(1 * 60 + 40, 10, 10))
	shop.free()


func _test_planner_rejects_service_target_closing_before_arrival() -> void:
	var world := StubWorld.new()
	var citizen := StubCitizen.new()
	var market: Supermarket = SupermarketScript.new()
	market.job_capacity = 0
	market.open_hour = 8
	market.close_hour = 18
	market.define_stock_item("grocery_bundle", 4, 10, 8, 4, "food")

	var planner = CitizenPlannerScript.new()
	planner._service_arrival_buffer_minutes = 5
	planner._survival_supermarket_travel_minutes = 18

	world.time.minutes_total = 17 * 60 + 30
	_assert_true("planner accepts market with travel plus buffer before close",
			planner._can_buy_groceries(world, citizen, market))

	world.time.minutes_total = 17 * 60 + 45
	_assert_true("planner rejects market that closes before travel plus buffer",
			not planner._can_buy_groceries(world, citizen, market))

	citizen.current_location = market
	world.time.minutes_total = 17 * 60 + 58
	_assert_true("planner still allows immediate purchase for citizen already inside",
			planner._can_buy_groceries(world, citizen, market))
	market.free()


func _assert_true(name: String, cond: bool) -> void:
	if cond:
		print("  OK   %s" % name)
		return
	failures += 1
	print("  FAIL %s" % name)
