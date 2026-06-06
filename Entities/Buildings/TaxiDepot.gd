extends Building
class_name TaxiDepot

func _ready() -> void:
	super._ready()
	building_type = BuildingType.TAXI_DEPOT
	apply_balance_settings("taxi_depot")
	add_to_group("work")

func get_service_type() -> String:
	return "transport"
