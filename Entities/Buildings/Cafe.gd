extends CommercialBuilding
class_name Cafe

@export var drink_price: int = 8

func _ready() -> void:
	super._ready()
	building_type = BuildingType.CAFE
	if capacity <= 0:
		capacity = 18
	if job_capacity <= 0:
		job_capacity = 3
	open_hour = 7
	close_hour = 20
	define_stock_item("drink", 45, drink_price, 70, 26, "food")

func get_service_type() -> String:
	return "food"

func _get_extra_info(_world = null) -> Dictionary:
	var info := get_commercial_info()
	info["Drink price"] = "%d EUR" % get_item_price("drink", 1)
	info["Drink stock"] = str(get_stock("drink"))
	return info