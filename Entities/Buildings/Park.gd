extends Building
class_name Park

func _ready() -> void:
	super._ready()
	building_type = BuildingType.PARK
	open_hour = 6
	close_hour = 23
	capacity = max(capacity, 40)
	add_to_group("parks")

func get_service_type() -> String:
	return "fun"
