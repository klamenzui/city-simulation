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

func get_service_type() -> String:
	return "food"

func try_enter(c: Citizen) -> bool:
	return try_add_visitor(c)

func leave(c: Citizen) -> void:
	remove_visitor(c)

func sell_meal(world: World, buyer: Citizen) -> bool:
	if buyer == null:
		return false
	if not is_open(world.time.get_hour()):
		return false
	if not world.economy.transfer(buyer.wallet, account, meal_price):
		return false
	record_income(meal_price)
	return true

func _get_extra_info(_world = null) -> Dictionary:
	return {
		"Meal price": "%d €" % meal_price,
	}
