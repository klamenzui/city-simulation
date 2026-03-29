extends Node
class_name EconomySystem

const BalanceConfig = preload("res://Simulation/Config/BalanceConfig.gd")

var jobs: Array[Job] = []
var market_account: Account = Account.new()

var commodity_stock: Dictionary = {}
var commodity_target_stock: Dictionary = {}
var commodity_base_price: Dictionary = {}
var commodity_demand_today: Dictionary = {}
var commodity_supply_today: Dictionary = {}
var commodity_price_history: Dictionary = {}

func _ready() -> void:
	market_account.owner_name = "RegionalMarket"
	market_account.balance = BalanceConfig.get_int("economy.market_account_balance", 250000)

	var commodity_settings := BalanceConfig.get_section("economy.commodities")
	for key in commodity_settings.keys():
		var commodity_key := str(key)
		var config_value: Variant = commodity_settings.get(commodity_key, {})
		if config_value is not Dictionary:
			continue
		var commodity_config := config_value as Dictionary
		_define_commodity(
			commodity_key,
			int(commodity_config.get("stock", 400)),
			int(commodity_config.get("target_stock", 600)),
			int(commodity_config.get("base_price", 5))
		)

	if commodity_stock.is_empty():
		_define_commodity("food", 900, 1200, 4)
		_define_commodity("clothes", 480, 700, 7)
		_define_commodity("entertainment", 2000, 2500, 2)

func _define_commodity(key: String, stock: int, target_stock: int, base_price: int) -> void:
	commodity_stock[key] = maxi(stock, 0)
	commodity_target_stock[key] = maxi(target_stock, 1)
	commodity_base_price[key] = maxi(base_price, 1)
	commodity_demand_today[key] = 0
	commodity_supply_today[key] = 0
	if not commodity_price_history.has(key):
		commodity_price_history[key] = []

func transfer(from_acc: Account, to_acc: Account, amount: int) -> bool:
	if amount <= 0:
		return true
	if from_acc == null or to_acc == null:
		return false
	if from_acc.balance < amount:
		return false
	from_acc.balance -= amount
	to_acc.balance += amount
	return true

func pay_to_wallet(from_acc: Account, citizen: Citizen, amount: int) -> bool:
	if citizen == null:
		return false
	return transfer(from_acc, citizen.wallet, amount)

func collect_tax(payer: Account, collector: Account, amount: int) -> bool:
	return transfer(payer, collector, amount)

func fund_public_building(payer: Account, receiver: Account, amount: int) -> bool:
	return transfer(payer, receiver, amount)

func pay_production_cost(payer: Account, amount: int) -> bool:
	return transfer(payer, market_account, amount)

func pay_public_operating_cost(payer: Account, sink: Account, amount: int) -> bool:
	return transfer(payer, sink, amount)

func register_job(job: Job) -> void:
	if job == null:
		return
	if jobs.has(job):
		return
	jobs.append(job)

func get_open_jobs() -> Array[Job]:
	var open_jobs: Array[Job] = []
	for job in jobs:
		if job == null:
			continue
		if job.workplace != null and job.workplace.has_free_job_slots():
			open_jobs.append(job)
	return open_jobs

func get_wholesale_unit_price(commodity: String) -> int:
	var key: String = commodity
	if not commodity_base_price.has(key):
		_define_commodity(key, 400, 600, 5)

	var base: float = float(maxi(int(commodity_base_price.get(key, 1)), 1))
	var stock: float = float(maxi(int(commodity_stock.get(key, 0)), 0))
	var target: float = float(maxi(int(commodity_target_stock.get(key, 1)), 1))
	var demand: float = float(maxi(int(commodity_demand_today.get(key, 0)), 0))
	var supply: float = float(maxi(int(commodity_supply_today.get(key, 0)), 0))

	var scarcity: float = clamp((target - stock) / target, -0.2, 1.0)
	var demand_pressure: float = clamp(demand / target, 0.0, 1.8)
	var supply_relief: float = clamp(supply / target, 0.0, 1.8)
	var imbalance: float = clamp((demand - supply) / target, -1.5, 1.5)

	var multiplier: float = 1.0 + maxf(scarcity, 0.0) * 0.55 + demand_pressure * 0.22 + maxf(imbalance, 0.0) * 0.2 - supply_relief * 0.18
	multiplier = clamp(multiplier, 0.5, 3.0)
	return maxi(int(round(base * multiplier)), 1)

func buy_wholesale(buyer: Account, commodity: String, requested_qty: int) -> Dictionary:
	var result: Dictionary = {
		"qty": 0,
		"unit_price": 0,
		"total_cost": 0,
	}
	if buyer == null:
		return result

	var request: int = maxi(requested_qty, 0)
	if request <= 0:
		return result

	var key: String = commodity
	if not commodity_stock.has(key):
		_define_commodity(key, 400, 600, 5)

	var unit_price: int = get_wholesale_unit_price(key)
	var available: int = maxi(int(commodity_stock.get(key, 0)), 0)
	if available <= 0:
		return result

	var affordable: int = buyer.balance / unit_price
	var qty: int = mini(request, mini(available, affordable))
	if qty <= 0:
		return result

	var total: int = qty * unit_price
	if not transfer(buyer, market_account, total):
		return result

	commodity_stock[key] = available - qty
	commodity_demand_today[key] = int(commodity_demand_today.get(key, 0)) + qty

	result["qty"] = qty
	result["unit_price"] = unit_price
	result["total_cost"] = total
	return result

func sell_wholesale_to_market(seller: Account, commodity: String, offered_qty: int) -> Dictionary:
	var result: Dictionary = {
		"qty": 0,
		"unit_price": 0,
		"total_revenue": 0,
	}
	if seller == null:
		return result

	var qty: int = maxi(offered_qty, 0)
	if qty <= 0:
		return result

	var key: String = commodity
	if not commodity_stock.has(key):
		_define_commodity(key, 400, 600, 5)

	var market_price: int = get_wholesale_unit_price(key)
	var producer_price: int = maxi(int(round(float(market_price) * 0.72)), 1)
	var max_affordable: int = market_account.balance / producer_price
	var accepted_qty: int = mini(qty, max_affordable)
	if accepted_qty <= 0:
		return result

	var payout: int = accepted_qty * producer_price
	if not transfer(market_account, seller, payout):
		return result

	commodity_stock[key] = int(commodity_stock.get(key, 0)) + accepted_qty
	commodity_supply_today[key] = int(commodity_supply_today.get(key, 0)) + accepted_qty

	result["qty"] = accepted_qty
	result["unit_price"] = producer_price
	result["total_revenue"] = payout
	return result

func get_market_snapshot() -> Dictionary:
	var stock_parts: PackedStringArray = []
	var price_parts: PackedStringArray = []
	for key in commodity_stock.keys():
		var commodity: String = str(key)
		stock_parts.append("%s:%d" % [commodity, int(commodity_stock.get(commodity, 0))])
		price_parts.append("%s:%d" % [commodity, get_wholesale_unit_price(commodity)])
	return {
		"stock": ", ".join(stock_parts),
		"price": ", ".join(price_parts),
	}

func begin_new_day() -> void:
	for key in commodity_stock.keys():
		var commodity: String = str(key)
		var stock: int = int(commodity_stock.get(commodity, 0))
		var target: int = int(commodity_target_stock.get(commodity, 1))

		# Small external import safety net to avoid complete deadlocks.
		if stock < int(round(float(target) * 0.15)):
			var import_qty: int = int(round(float(target - stock) * 0.12))
			if import_qty > 0:
				commodity_stock[commodity] = stock + import_qty
				stock += import_qty

		var history = commodity_price_history.get(commodity, [])
		history.append(get_wholesale_unit_price(commodity))
		while history.size() > 10:
			history.pop_front()
		commodity_price_history[commodity] = history

		commodity_demand_today[commodity] = 0
		commodity_supply_today[commodity] = 0
