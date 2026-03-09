extends Building
class_name CommercialBuilding

func _ready() -> void:
	super._ready()
	add_to_group("work")
	if open_hour == 8 and close_hour == 22:
		open_hour = 8
		close_hour = 21

func get_service_type() -> String:
	return "commerce"
