extends SceneTree

const EconomySystemScript = preload("res://Simulation/EconomySystem.gd")
const WorldScript = preload("res://Simulation/World.gd")
const AccountScript = preload("res://Entities/Account.gd")
const JobScript = preload("res://Entities/Job.gd")
const BuildingScript = preload("res://Entities/Buildings/Building.gd")
const CityHallScript = preload("res://Entities/Buildings/CityHall.gd")
const CitizenScript = preload("res://Entities/Citizens/Citizen.gd")

var _checks_run: int = 0
var _current_error: String = ""

func _initialize() -> void:
	var failed: Array[String] = []

	for test_name in [
		"transfer",
		"market_buy_sell",
		"price_and_daily_reset",
		"open_jobs",
		"salary_sources",
		"tax_and_welfare",
	]:
		var error := _run_test(test_name)
		if error != "":
			failed.append("%s: %s" % [test_name, error])

	if failed.is_empty():
		print("ECON_TEST OK checks=%d" % _checks_run)
		quit(0)
		return

	for failure in failed:
		push_error(failure)
	print("ECON_TEST FAIL count=%d" % failed.size())
	quit(1)

func _run_test(test_name: String) -> String:
	_current_error = ""
	match test_name:
		"transfer":
			return _test_transfer()
		"market_buy_sell":
			return _test_market_buy_sell()
		"price_and_daily_reset":
			return _test_price_and_daily_reset()
		"open_jobs":
			return _test_open_jobs()
		"salary_sources":
			return _test_salary_sources()
		"tax_and_welfare":
			return _test_tax_and_welfare()
		_:
			return "unknown test"

func _test_transfer() -> String:
	var economy = _new_economy()
	var alice = _new_account("Alice", 120)
	var bob = _new_account("Bob", 15)

	_expect(economy.transfer(alice, bob, 35), "transfer should succeed")
	_expect_eq(alice.balance, 85, "sender balance after transfer")
	_expect_eq(bob.balance, 50, "receiver balance after transfer")
	_expect(not economy.transfer(alice, bob, 500), "transfer should fail when sender lacks balance")
	_expect_eq(alice.balance, 85, "sender balance should stay unchanged on failed transfer")
	_expect_eq(bob.balance, 50, "receiver balance should stay unchanged on failed transfer")
	_free_node(economy)
	return _current_error

func _test_market_buy_sell() -> String:
	var economy = _new_economy()
	var buyer = _new_account("Buyer", 5000)
	var seller = _new_account("Seller", 100)
	var stock_before: int = economy.commodity_stock["food"]
	var market_before: int = economy.market_account.balance

	var purchase: Dictionary = economy.buy_wholesale(buyer, "food", 120)
	_expect_eq(purchase["qty"], 120, "buyer should receive requested quantity when stock and money allow it")
	_expect(int(purchase["unit_price"]) > 0, "wholesale unit price should be positive")
	_expect_eq(
		int(economy.commodity_stock["food"]),
		stock_before - 120,
		"market stock should shrink after wholesale buy"
	)
	_expect_eq(
		economy.market_account.balance,
		market_before + int(purchase["total_cost"]),
		"market account should receive wholesale payment"
	)

	var sale: Dictionary = economy.sell_wholesale_to_market(seller, "food", 80)
	_expect_eq(sale["qty"], 80, "market should buy offered quantity when it can afford it")
	_expect(int(sale["unit_price"]) > 0, "producer unit price should be positive")
	_expect_eq(
		int(economy.commodity_stock["food"]),
		stock_before - 40,
		"market stock should reflect buy then sell sequence"
	)
	_expect_eq(
		seller.balance,
		100 + int(sale["total_revenue"]),
		"seller should receive market payout"
	)
	_free_node(economy)
	return _current_error

func _test_price_and_daily_reset() -> String:
	var economy = _new_economy()

	var normal_price: int = economy.get_wholesale_unit_price("clothes")
	economy.commodity_stock["clothes"] = 5
	economy.commodity_demand_today["clothes"] = 700
	economy.commodity_supply_today["clothes"] = 0
	var scarcity_price: int = economy.get_wholesale_unit_price("clothes")
	_expect(scarcity_price > normal_price, "scarcity should push prices up")

	economy.commodity_stock["food"] = 10
	economy.commodity_demand_today["food"] = 55
	economy.commodity_supply_today["food"] = 33
	economy.begin_new_day()
	_expect(int(economy.commodity_stock["food"]) > 10, "daily import safety net should refill very low stock")
	_expect_eq(int(economy.commodity_demand_today["food"]), 0, "daily demand should reset")
	_expect_eq(int(economy.commodity_supply_today["food"]), 0, "daily supply should reset")
	_expect((economy.commodity_price_history["food"] as Array).size() >= 1, "price history should record a daily sample")
	_free_node(economy)
	return _current_error

func _test_open_jobs() -> String:
	var economy = _new_economy()
	var building = BuildingScript.new()
	building.job_capacity = 2
	var job = JobScript.new()
	job.workplace = building

	economy.register_job(job)
	economy.register_job(job)
	_expect_eq(economy.jobs.size(), 1, "register_job should deduplicate the same job")
	_expect_eq(economy.get_open_jobs().size(), 1, "job should be open while workplace has capacity")

	var worker_a = CitizenScript.new()
	var worker_b = CitizenScript.new()
	building.workers.append(worker_a)
	building.workers.append(worker_b)
	_expect_eq(economy.get_open_jobs().size(), 0, "job should close when workplace capacity is full")
	job.workplace = null
	_free_node(worker_a)
	_free_node(worker_b)
	_free_node(building)
	_free_node(economy)
	return _current_error

func _test_salary_sources() -> String:
	var world = _new_world()
	var worker = CitizenScript.new()
	worker.wallet.balance = 0
	var job = JobScript.new()
	var workplace = BuildingScript.new()
	workplace.account.balance = 90
	job.workplace = workplace
	worker.job = job

	var city_hall = CityHallScript.new()
	city_hall.account.balance = 50

	var paid_by_work: String = world._pay_salary(worker, 40, city_hall)
	_expect_eq(paid_by_work, "work", "salary should use workplace funds first")
	_expect_eq(worker.wallet.balance, 40, "worker wallet after workplace salary")
	_expect_eq(workplace.account.balance, 50, "workplace balance after salary")
	_expect_eq(workplace.expenses_today, 40, "workplace expense should be tracked")

	workplace.account.balance = 5
	worker.wallet.balance = 0
	var paid_by_hall: String = world._pay_salary(worker, 30, city_hall)
	_expect_eq(paid_by_hall, "city_hall", "salary should fall back to city hall")
	_expect_eq(worker.wallet.balance, 30, "worker wallet after city hall fallback")
	_expect_eq(city_hall.account.balance, 20, "city hall balance after paying salary")

	city_hall.account.balance = 10
	worker.wallet.balance = 0
	world.city_account.balance = 90
	var paid_by_reserve: String = world._pay_salary(worker, 25, city_hall)
	_expect_eq(paid_by_reserve, "reserve", "salary should fall back to reserve account last")
	_expect_eq(worker.wallet.balance, 25, "worker wallet after reserve fallback")
	_expect_eq(world.city_account.balance, 65, "reserve balance after salary fallback")
	worker.job = null
	job.workplace = null
	_free_node(worker)
	_free_node(workplace)
	_free_node(city_hall)
	_free_world(world)
	return _current_error

func _test_tax_and_welfare() -> String:
	var world = _new_world()
	var city_hall = CityHallScript.new()
	city_hall.account.balance = 0

	var shop = BuildingScript.new()
	shop.account.balance = 500
	shop.income_today = 1000

	var citizen = CitizenScript.new()
	citizen.wallet.balance = 200

	world.buildings.append(city_hall)
	world.buildings.append(shop)
	world.citizens.append(citizen)

	city_hall.collect_daily_taxes(world)
	_expect_eq(city_hall.tax_collected_today, 104, "city hall should collect business and citizen tax")
	_expect_eq(city_hall.account.balance, 104, "city hall account after taxes")
	_expect_eq(shop.account.balance, 400, "shop account after business tax")
	_expect_eq(shop.expenses_today, 100, "shop should record tax as expense")
	_expect_eq(citizen.wallet.balance, 196, "citizen wallet after citizen tax")

	_expect(city_hall.pay_welfare(world, citizen, 40), "city hall welfare payment should succeed")
	_expect_eq(citizen.wallet.balance, 236, "citizen wallet after welfare")
	_expect_eq(city_hall.account.balance, 64, "city hall balance after welfare payment")

	city_hall.account.balance = 10
	world.city_account.balance = 70
	_expect(world._pay_welfare(citizen, 40, city_hall), "world welfare should fall back to reserve when city hall is short")
	_expect_eq(citizen.wallet.balance, 276, "citizen wallet after reserve welfare fallback")
	_expect_eq(world.city_account.balance, 30, "reserve balance after welfare fallback")
	_free_node(citizen)
	_free_node(shop)
	_free_node(city_hall)
	_free_world(world)
	return _current_error

func _new_economy():
	var economy = EconomySystemScript.new()
	economy._ready()
	return economy

func _new_world():
	var world = WorldScript.new()
	if world.economy != null:
		_free_node(world.economy)
	world.economy = _new_economy()
	world.city_account.owner_name = "CityReserve"
	world.city_account.balance = 180
	return world

func _new_account(owner_name: String, balance: int):
	var account = AccountScript.new()
	account.owner_name = owner_name
	account.balance = balance
	return account

func _free_node(node: Node) -> void:
	if node != null:
		node.free()

func _free_world(world) -> void:
	if world == null:
		return
	if world.time != null:
		_free_node(world.time)
		world.time = null
	if world.economy != null:
		_free_node(world.economy)
		world.economy = null
	_free_node(world)

func _expect(condition: bool, message: String) -> void:
	_checks_run += 1
	if condition or _current_error != "":
		return
	_current_error = message

func _expect_eq(actual, expected, message: String) -> void:
	_checks_run += 1
	if actual == expected or _current_error != "":
		return
	_current_error = "%s | expected=%s actual=%s" % [message, str(expected), str(actual)]
