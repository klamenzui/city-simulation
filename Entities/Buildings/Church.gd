extends Building
class_name Church


func _ready() -> void:
	if building_name.strip_edges().is_empty() or building_name == "Building":
		building_name = "Church"
	building_type = BuildingType.CHURCH
	apply_balance_settings("church")
	super._ready()
	add_to_group("landmark")
	add_to_group("community")


func get_service_type() -> String:
	return "community"


func _get_extra_info(_world = null) -> Dictionary:
	return {
		"Use": "Community landmark",
	}
