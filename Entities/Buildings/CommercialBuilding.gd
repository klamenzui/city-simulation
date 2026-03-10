extends Building
class_name CommercialBuilding

const HISTORY_DAYS := 7

@export var restock_enabled: bool = true

var inventory: Dictionary = {}
var base_prices: Dictionary = {}
var restock_targets: Dictionary = {}
var restock_batches: Dictionary = {}
var source_commodities: Dictionary = {}
var demand_today: Dictionary = {}
var supply_today: Dictionary = {}
var sold_today: Dictionary = {}

var price_history: Dictionary = {}
var stock_history: Dictionary = {}

func _ready() -> void:
	super._ready()
	add_to_group("work")
	if open_hour == 8 and close_hour == 22:
		open_hour = 8
		close_hour = 21

func get_service_type() -> String:
	return "commerce"

func define_stock_item(item: String, start_stock: int, base_price: int, restock_target: int, restock_batch: int, source_commodity: String = "") -> void:
	if item == "":
		return
	inventory[item] = maxi(start_stock, 0)
	base_prices[item] = maxi(base_price, 1)
	restock_targets[item] = maxi(restock_target, 1)
	restock_batches[item] = maxi(restock_batch, 1)
	source_commodities[item] = source_commodity if source_commodity != "" else item
	demand_today[item] = int(demand_today.get(item, 0))
	supply_today[item] = int(supply_today.get(item, 0))
	sold_today[item] = int(sold_today.get(item, 0))
	if not price_history.has(item):
		price_history[item] = []
	if not stock_history.has(item):
		stock_history[item] = []

func set_item_base_price(item: String, price: int) -> void:
	if item == "":
		return
	base_prices[item] = maxi(price, 1)

func get_stock(item: String) -> int:
	return maxi(int(inventory.get(item, 0)), 0)

func can_sell_item(item: String, quantity: int = 1) -> bool:
	if quantity <= 0:
		return true
	return get_stock(item) >= quantity

func get_item_price(item: String, quantity: int = 1) -> int:
	var unit_base: int = maxi(int(base_prices.get(item, 1)), 1)
	var stock: float = float(maxi(get_stock(item), 0))
	var target: float = float(maxi(int(restock_targets.get(item, 1)), 1))
	var demand: float = float(maxi(int(demand_today.get(item, 0)), 0))
	var supply: float = float(maxi(int(supply_today.get(item, 0)), 0))

	var scarcity: float = clamp((target - stock) / target, -0.25, 1.0)
	var demand_pressure: float = clamp(demand / target, 0.0, 2.0)
	var supply_relief: float = clamp(supply / target, 0.0, 2.0)
	var multiplier: float = 1.0 + maxf(scarcity, 0.0) * 0.45 + demand_pressure * 0.20 - supply_relief * 0.12
	multiplier = clamp(multiplier, 0.55, 2.5)

	var unit_price: int = maxi(int(round(float(unit_base) * multiplier)), 1)
	return unit_price * maxi(quantity, 1)

func estimate_can_afford(citizen: Citizen, item: String, quantity: int = 1) -> bool:
	if citizen == null:
		return false
	return citizen.wallet.balance >= get_item_price(item, quantity)

func sell_item(world: World, buyer: Citizen, item: String, quantity: int = 1) -> int:
	if world == null or buyer == null:
		return 0
	if not is_open(world.time.get_hour()):
		return 0
	if not can_sell_item(item, quantity):
		return 0

	var total_price: int = get_item_price(item, quantity)
	if not world.economy.transfer(buyer.wallet, account, total_price):
		return 0

	_finalize_sale(item, quantity, total_price)
	return total_price

func _finalize_sale(item: String, quantity: int, total_revenue: int) -> void:
	inventory[item] = maxi(get_stock(item) - maxi(quantity, 0), 0)
	demand_today[item] = int(demand_today.get(item, 0)) + maxi(quantity, 0)
	sold_today[item] = int(sold_today.get(item, 0)) + maxi(quantity, 0)
	record_income(total_revenue)

func run_daily_production(_world: World) -> void:
	# Overridden by producers (Farm / Factory).
	pass

func run_daily_supply(world: World) -> void:
	if world == null or not restock_enabled:
		return

	for item in restock_targets.keys():
		var item_key: String = str(item)
		var target: int = maxi(int(restock_targets.get(item_key, 0)), 0)
		if target <= 0:
			continue

		var stock: int = get_stock(item_key)
		if stock >= int(round(float(target) * 0.45)):
			continue

		var batch: int = maxi(int(restock_batches.get(item_key, 1)), 1)
		var commodity: String = str(source_commodities.get(item_key, item_key))
		var quote: Dictionary = world.economy.buy_wholesale(account, commodity, batch)
		var qty: int = maxi(int(quote.get("qty", 0)), 0)
		var total_cost: int = maxi(int(quote.get("total_cost", 0)), 0)
		if qty <= 0:
			continue

		inventory[item_key] = stock + qty
		supply_today[item_key] = int(supply_today.get(item_key, 0)) + qty
		record_expense(total_cost)

func begin_new_day() -> void:
	_record_daily_history()
	super.begin_new_day()
	for key in demand_today.keys():
		demand_today[key] = 0
	for key2 in supply_today.keys():
		supply_today[key2] = 0
	for key3 in sold_today.keys():
		sold_today[key3] = 0

func _record_daily_history() -> void:
	for key in inventory.keys():
		var item: String = str(key)
		_append_history(price_history, item, get_item_price(item, 1))
		_append_history(stock_history, item, get_stock(item))

func _append_history(history_map: Dictionary, key: String, value: int) -> void:
	var series = []
	if history_map.has(key):
		series = history_map[key]
	series.append(value)
	while series.size() > HISTORY_DAYS:
		series.pop_front()
	history_map[key] = series

func _format_history_line(history_map: Dictionary) -> String:
	if history_map.is_empty():
		return "-"
	var parts: PackedStringArray = []
	for key in history_map.keys():
		var item: String = str(key)
		var values = history_map[item]
		var formatted: PackedStringArray = []
		for v in values:
			formatted.append(str(v))
		parts.append("%s[%s]" % [item, ", ".join(formatted)])
	return " | ".join(parts)

func get_commercial_info() -> Dictionary:
	var info: Dictionary = {}
	if inventory.is_empty():
		return info

	var stock_parts: PackedStringArray = []
	var price_parts: PackedStringArray = []
	for key in inventory.keys():
		var item: String = str(key)
		stock_parts.append("%s:%d" % [item, get_stock(item)])
		price_parts.append("%s:%d" % [item, get_item_price(item, 1)])

	info["Stock"] = ", ".join(stock_parts)
	info["Price now"] = ", ".join(price_parts)
	info["Price history"] = _format_history_line(price_history)
	info["Stock history"] = _format_history_line(stock_history)
	return info