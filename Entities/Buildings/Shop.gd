extends CommercialBuilding
class_name Shop

@export var item_price: int = 18
@export var fun_gain: float = 5.0

func _ready() -> void:
	super._ready()
	building_type = BuildingType.SHOP
	if capacity <= 0:
		capacity = 25
	if job_capacity <= 0:
		job_capacity = 4
	open_hour = 9
	close_hour = 20

func get_service_type() -> String:
	return "shopping"

func buy_item(world: World, buyer: Citizen, multiplier: float = 1.0) -> bool:
	if buyer == null:
		return false
	if not is_open(world.time.get_hour()):
		return false
	var price := int(round(item_price * multiplier))
	if price <= 0:
		price = 1
	if not world.economy.transfer(buyer.wallet, account, price):
		return false
	record_income(price)
	buyer.needs.fun = clamp(buyer.needs.fun + fun_gain, 0.0, 100.0)
	return true

func _get_extra_info(_world = null) -> Dictionary:
	return {
		"Base item price": "%d €" % item_price,
	}
