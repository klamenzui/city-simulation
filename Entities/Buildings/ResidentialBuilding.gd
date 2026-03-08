extends Building
class_name ResidentialBuilding

@export var rent_per_day: int = 50
@export var capacity: int = 10
var tenants: Array[Citizen] = []

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
		if c:
			c.pay_rent(world, self, rent_per_day)
