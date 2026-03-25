extends CommercialBuilding
class_name Cafe

@export var drink_price: int = 8

func _ready() -> void:
	super._ready()
	building_type = BuildingType.CAFE
	var settings := apply_balance_settings("cafe")
	drink_price = int(settings.get("drink_price", drink_price))
	define_stock_item(
		"drink",
		int(settings.get("drink_start_stock", 45)),
		drink_price,
		int(settings.get("drink_restock_target", 70)),
		int(settings.get("drink_restock_batch", 26)),
		"food"
	)

func get_service_type() -> String:
	return "food"

func _get_extra_info(_world = null) -> Dictionary:
	var info := get_commercial_info()
	info["Drink price"] = "%d EUR" % get_item_price("drink", 1)
	info["Drink stock"] = str(get_stock("drink"))
	return info
