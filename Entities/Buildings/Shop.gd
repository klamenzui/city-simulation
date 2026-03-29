extends CommercialBuilding
class_name Shop

@export var item_price: int = 18
@export var fun_gain: float = 5.0

func _ready() -> void:
	super._ready()
	building_type = BuildingType.SHOP
	var settings := apply_balance_settings("shop")
	item_price = int(settings.get("item_price", item_price))
	fun_gain = float(settings.get("fun_gain", fun_gain))
	define_stock_item(
		"clothing",
		int(settings.get("clothing_start_stock", 34)),
		item_price,
		int(settings.get("clothing_restock_target", 56)),
		int(settings.get("clothing_restock_batch", 20)),
		"clothes"
	)

func get_service_type() -> String:
	return "shopping"

func get_item_price_quote(multiplier: float = 1.0) -> int:
	var base := get_item_price("clothing", 1)
	return maxi(int(round(float(base) * multiplier)), 1)

func buy_item(world: World, buyer: Citizen, multiplier: float = 1.0) -> bool:
	if world == null or buyer == null:
		return false
	if not is_open(world.time.get_hour()):
		return false
	if not can_sell_item("clothing", 1):
		return false

	var price := get_item_price_quote(multiplier)
	if not world.economy.transfer(buyer.wallet, account, price):
		return false

	_finalize_sale("clothing", 1, price)
	buyer.needs.fun = clamp(buyer.needs.fun + fun_gain * get_attractiveness_multiplier(), 0.0, 100.0)
	return true

func _get_extra_info(_world = null) -> Dictionary:
	var info := get_commercial_info()
	info["Base item price"] = "%d EUR" % get_item_price_quote(1.0)
	info["Clothing stock"] = str(get_stock("clothing"))
	return info
