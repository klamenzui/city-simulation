extends Shop
class_name Supermarket

@export var grocery_price: int = 10
@export var groceries_per_purchase: int = 3
@export var clothing_price: int = 24

func _ready() -> void:
	super._ready()
	building_type = BuildingType.SUPERMARKET
	if capacity <= 0:
		capacity = 30
	if job_capacity <= 0:
		job_capacity = 6
	open_hour = 7
	close_hour = 22
	define_stock_item("grocery_bundle", 60, grocery_price, 90, 35, "food")
	set_item_base_price("clothing", clothing_price)

func get_service_type() -> String:
	return "food_market"

func get_grocery_price(_world = null) -> int:
	return get_item_price("grocery_bundle", 1)

func buy_groceries(world: World, buyer: Citizen) -> int:
	if world == null or buyer == null:
		return 0
	if not is_open(world.time.get_hour()):
		return 0
	if not can_sell_item("grocery_bundle", 1):
		return 0

	var price := get_grocery_price(world)
	if not world.economy.transfer(buyer.wallet, account, price):
		return 0

	_finalize_sale("grocery_bundle", 1, price)
	return groceries_per_purchase

func buy_clothes(world: World, buyer: Citizen) -> bool:
	if not buy_item(world, buyer, 1.0):
		return false
	buyer.needs.fun = clamp(buyer.needs.fun + 9.0, 0.0, 100.0)
	return true

func _get_extra_info(_world = null) -> Dictionary:
	var info := get_commercial_info()
	info["Grocery price"] = "%d EUR" % get_grocery_price(_world)
	info["Groceries/visit"] = str(groceries_per_purchase)
	info["Clothing price"] = "%d EUR" % get_item_price_quote(1.0)
	info["Grocery stock"] = str(get_stock("grocery_bundle"))
	return info
