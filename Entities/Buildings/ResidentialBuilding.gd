extends Building
class_name ResidentialBuilding

@export var rent_per_day: int = 50
var tenants: Array[Citizen] = []

func _ready() -> void:
	super._ready()
	building_type = BuildingType.RESIDENTIAL
	var settings := apply_balance_settings("residential")
	rent_per_day = int(settings.get("rent_per_day", rent_per_day))

func get_service_type() -> String:
	return "housing"

func has_free_slot() -> bool:
	return tenants.size() < capacity

func add_tenant(c: Citizen) -> bool:
	if c == null:
		return false
	if not has_free_slot():
		return false
	if tenants.has(c):
		return true
	tenants.append(c)
	return true

func charge_rent(world: World) -> void:
	for c in tenants:
		if c == null:
			continue
		var before := account.balance
		c.pay_rent(world, self, rent_per_day)
		var collected := account.balance - before
		if collected > 0:
			record_income(collected)

func _get_extra_info(_world = null) -> Dictionary:
	return {
		"Tenants": "%d / %d" % [tenants.size(), max(capacity, 0)],
		"Rent/day": "%d €" % rent_per_day,
	}
