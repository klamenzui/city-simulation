extends Building
class_name LogisticsDepot

func _ready() -> void:
	super._ready()
	building_type = BuildingType.LOGISTICS_DEPOT
	apply_balance_settings("logistics_depot")
	add_to_group("work")

func get_service_type() -> String:
	return "logistics"
