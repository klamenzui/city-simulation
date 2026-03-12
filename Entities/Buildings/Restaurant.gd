extends CommercialBuilding
class_name Restaurant

@export var meal_price: int = 15

func _ready() -> void:
	super._ready()
	building_type = BuildingType.RESTAURANT
	if capacity <= 0:
		capacity = 20
	if job_capacity <= 0:
		job_capacity = 5
	open_hour = 8
	close_hour = 22
	define_stock_item("meal", 48, meal_price, 70, 30, "food")

func get_service_type() -> String:
	return "food"

func get_meal_price(_world = null) -> int:
	return get_item_price("meal", 1)

func try_enter(c: Citizen) -> bool:
	return try_add_visitor(c)

func leave(c: Citizen) -> void:
	remove_visitor(c)

func sell_meal(world: World, buyer: Citizen) -> bool:
	if buyer == null:
		return false
	return sell_item(world, buyer, "meal", 1) > 0

func _get_extra_info(_world = null) -> Dictionary:
	var info := get_commercial_info()
	info["Meal price"] = "%d EUR" % get_meal_price(_world)
	info["Meal stock"] = str(get_stock("meal"))
	return info
