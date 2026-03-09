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

func get_service_type() -> String:
	return "food_market"

func buy_groceries(world: World, buyer: Citizen) -> int:
	if buyer == null:
		return 0
	if not is_open(world.time.get_hour()):
		return 0
	if not world.economy.transfer(buyer.wallet, account, grocery_price):
		return 0
	record_income(grocery_price)
	return groceries_per_purchase

func buy_clothes(world: World, buyer: Citizen) -> bool:
	if buyer == null:
		return false
	if not is_open(world.time.get_hour()):
		return false
	if not world.economy.transfer(buyer.wallet, account, clothing_price):
		return false
	record_income(clothing_price)
	buyer.needs.fun = clamp(buyer.needs.fun + 9.0, 0.0, 100.0)
	return true

func _get_extra_info(_world = null) -> Dictionary:
	return {
		"Grocery price": "%d €" % grocery_price,
		"Groceries/visit": str(groceries_per_purchase),
		"Clothing price": "%d €" % clothing_price,
	}
