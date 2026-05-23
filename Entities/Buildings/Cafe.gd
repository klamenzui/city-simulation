extends CommercialBuilding
class_name Cafe

@export var drink_price: int = 8
@export var snack_price: int = 9

func _ready() -> void:
	super._ready()
	building_type = BuildingType.CAFE
	var settings := apply_balance_settings("cafe")
	drink_price = int(settings.get("drink_price", drink_price))
	snack_price = int(settings.get("snack_price", snack_price))
	define_stock_item(
		"drink",
		int(settings.get("drink_start_stock", 45)),
		drink_price,
		int(settings.get("drink_restock_target", 70)),
		int(settings.get("drink_restock_batch", 26)),
		"food"
	)
	define_stock_item(
		"snack",
		int(settings.get("snack_start_stock", 36)),
		snack_price,
		int(settings.get("snack_restock_target", 60)),
		int(settings.get("snack_restock_batch", 22)),
		"food"
	)

func get_service_type() -> String:
	return "food"

func get_snack_price(_world = null) -> int:
	return get_item_price("snack", 1)

func can_sell_snack() -> bool:
	return can_sell_item("snack", 1)

func try_enter(c: Citizen) -> bool:
	return try_add_visitor(c)

func leave(c: Citizen) -> void:
	remove_visitor(c)

func sell_snack(world: World, buyer: Citizen) -> bool:
	if buyer == null:
		return false
	return sell_item(world, buyer, "snack", 1) > 0

func _get_extra_info(_world = null) -> Dictionary:
	var info := get_commercial_info()
	info["Drink price"] = "%d EUR" % get_item_price("drink", 1)
	info["Drink stock"] = str(get_stock("drink"))
	info["Snack price"] = "%d EUR" % get_snack_price(_world)
	info["Snack stock"] = str(get_stock("snack"))
	return info
