extends RefCounted
class_name CityInventoryAdapter

## Thin project adapter around GLoot's item ids and stack model.
##
## Simulation code keeps compact Dictionary counts for performance. GLoot remains
## the editor/runtime inventory plugin and can materialize those counts into an
## Inventory node when drag/drop UI or item inspection needs it.

const PROTOSET_PATH := "res://Simulation/Inventory/city_inventory_protoset.json"
const GLOOT_INVENTORY_SCRIPT := "res://addons/gloot/core/inventory.gd"
const GLOOT_INVENTORY_ITEM_SCRIPT := "res://addons/gloot/core/inventory_item.gd"


static func normalize_item_id(item_id: String) -> String:
	var clean := item_id.strip_edges()
	match clean:
		"grocery_bundle", "groceries", "supplies":
			return "food"
		"clothes":
			return "clothing"
	return clean


static func get_count(store: Dictionary, item_id: String) -> int:
	var clean := normalize_item_id(item_id)
	if clean.is_empty():
		return 0
	if store.has(clean):
		return maxi(int(store.get(clean, 0)), 0)
	return maxi(int(store.get(item_id, 0)), 0)


static func set_count(store: Dictionary, item_id: String, amount: int) -> void:
	var clean := normalize_item_id(item_id)
	if clean.is_empty():
		return
	var clamped := maxi(amount, 0)
	if clamped <= 0:
		store.erase(clean)
	else:
		store[clean] = clamped


static func add_count(store: Dictionary, item_id: String, amount: int) -> int:
	if amount <= 0:
		return 0
	var clean := normalize_item_id(item_id)
	if clean.is_empty():
		return 0
	var next_count := get_count(store, clean) + amount
	set_count(store, clean, next_count)
	return amount


static func remove_count(store: Dictionary, item_id: String, amount: int) -> int:
	if amount <= 0:
		return 0
	var clean := normalize_item_id(item_id)
	if clean.is_empty():
		return 0
	var current := get_count(store, clean)
	var removed := mini(current, amount)
	set_count(store, clean, current - removed)
	return removed


static func duplicate_counts(store: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in store.keys():
		var raw := str(key)
		var clean := normalize_item_id(raw)
		var amount := get_count(store, raw)
		if amount > 0:
			result[clean] = int(result.get(clean, 0)) + amount
	return result


static func total_count(store: Dictionary) -> int:
	var total := 0
	for key in store.keys():
		total += get_count(store, str(key))
	return total


static func create_gloot_inventory_from_counts(node_name: String, counts: Dictionary) -> Node:
	var inventory_script: Script = load(GLOOT_INVENTORY_SCRIPT)
	var item_script: Script = load(GLOOT_INVENTORY_ITEM_SCRIPT)
	if inventory_script == null or item_script == null:
		return null
	var inventory: Node = inventory_script.new()
	inventory.name = node_name
	inventory.set("protoset", load(PROTOSET_PATH))
	for key in duplicate_counts(counts).keys():
		var item_id := str(key)
		var amount := get_count(counts, item_id)
		var item: Object = item_script.new(inventory.get("protoset"), item_id)
		item.call("set_max_stack_size", maxi(amount, int(item.call("get_max_stack_size"))))
		item.call("set_stack_size", amount)
		inventory.call("add_item_autosplitmerge", item)
	return inventory
