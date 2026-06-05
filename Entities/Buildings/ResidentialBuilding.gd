extends Building
class_name ResidentialBuilding

const CityInventoryAdapterScript = preload("res://Simulation/Inventory/CityInventoryAdapter.gd")

@export var rent_per_day: int = 50
var tenants: Array[Citizen] = []
var inventory: Dictionary = {}

func _ready() -> void:
	super._ready()
	building_type = BuildingType.RESIDENTIAL
	var settings := apply_balance_settings("residential")
	rent_per_day = int(settings.get("rent_per_day", rent_per_day))
	var ground_floor_businesses := get_ground_floor_businesses()
	if not ground_floor_businesses.is_empty():
		add_to_group("mixed_use")
		for business in ground_floor_businesses:
			business.add_to_group("ground_floor_business")

func get_service_type() -> String:
	return "housing"

func is_mixed_use() -> bool:
	return not get_ground_floor_businesses().is_empty()

func get_ground_floor_businesses() -> Array[Building]:
	var businesses: Array[Building] = []
	_collect_ground_floor_businesses(self, businesses)
	return businesses

func _collect_ground_floor_businesses(node: Node, out: Array[Building]) -> void:
	for child in node.get_children():
		if child is Building:
			var business := child as Building
			if is_supported_ground_floor_business(business):
				out.append(business)
			continue
		_collect_ground_floor_businesses(child, out)

func is_supported_ground_floor_business(business: Building) -> bool:
	if business == null or business is Supermarket:
		return false
	return business is Shop or business is Cafe or business is Restaurant

func get_ground_floor_business_summary() -> String:
	var labels: PackedStringArray = []
	for business in get_ground_floor_businesses():
		labels.append(business.get_building_type_display_label())
	return ", ".join(labels)

func _build_building_identity_section() -> Dictionary:
	var section := super._build_building_identity_section()
	var business_summary := get_ground_floor_business_summary()
	if business_summary.is_empty():
		return section
	var rows: Array = section.get("rows", [])
	rows.append({
		"label": LocaleServiceScript.t("details.label.ground_floor_uses"),
		"value": business_summary,
	})
	section["rows"] = rows
	return section

func has_free_slot() -> bool:
	return tenants.size() < capacity

func add_tenant(c: Citizen) -> bool:
	if c == null:
		return false
	if tenants.has(c):
		return true
	if not has_free_slot():
		return false
	tenants.append(c)
	return true

func remove_tenant(c: Citizen) -> void:
	if c == null:
		return
	tenants.erase(c)

func get_inventory_count(item_id: String) -> int:
	return CityInventoryAdapterScript.get_count(inventory, item_id)

func add_inventory_item(item_id: String, amount: int) -> int:
	return CityInventoryAdapterScript.add_count(inventory, item_id, amount)

func remove_inventory_item(item_id: String, amount: int) -> int:
	return CityInventoryAdapterScript.remove_count(inventory, item_id, amount)

func get_inventory_snapshot() -> Dictionary:
	return CityInventoryAdapterScript.duplicate_counts(inventory)

func apply_inventory_snapshot(data: Dictionary) -> void:
	inventory.clear()
	for key in data.keys():
		CityInventoryAdapterScript.set_count(inventory, str(key), int(data.get(key, 0)))

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
	var info := {
		"Tenants": "%d / %d" % [tenants.size(), max(capacity, 0)],
		"Rent/day": "%d €" % rent_per_day,
	}
	var business_summary := get_ground_floor_business_summary()
	if not business_summary.is_empty():
		info["Ground floor"] = business_summary
	var inventory_parts: PackedStringArray = []
	for key in inventory.keys():
		var item_id := str(key)
		var amount := get_inventory_count(item_id)
		if amount > 0:
			inventory_parts.append("%s:%d" % [item_id, amount])
	if not inventory_parts.is_empty():
		info["Inventory"] = ", ".join(inventory_parts)
	return info
