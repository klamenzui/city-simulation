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

func get_service_type() -> String:
	return "food"

func _get_extra_info(_world = null) -> Dictionary:
	return {
		"Drink price": "%d €" % drink_price,
	}
