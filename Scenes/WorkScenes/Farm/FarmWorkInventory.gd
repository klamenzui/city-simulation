extends RefCounted
class_name FarmWorkInventory

signal changed()

var _items: Dictionary = {}


func clear() -> void:
	_items.clear()
	changed.emit()


func add_item(item_id: String, amount: int) -> int:
	var cleaned := item_id.strip_edges()
	if cleaned.is_empty() or amount <= 0:
		return 0
	_items[cleaned] = get_amount(cleaned) + amount
	changed.emit()
	return amount


func remove_item(item_id: String, amount: int) -> int:
	var cleaned := item_id.strip_edges()
	if cleaned.is_empty() or amount <= 0:
		return 0
	var current := get_amount(cleaned)
	var removed := mini(current, amount)
	if removed <= 0:
		return 0
	var remaining := current - removed
	if remaining > 0:
		_items[cleaned] = remaining
	else:
		_items.erase(cleaned)
	changed.emit()
	return removed


func transfer_to(target: FarmWorkInventory, item_id: String, amount: int) -> int:
	if target == null:
		return 0
	var removed := remove_item(item_id, amount)
	if removed <= 0:
		return 0
	return target.add_item(item_id, removed)


func get_amount(item_id: String) -> int:
	var cleaned := item_id.strip_edges()
	if cleaned.is_empty():
		return 0
	return maxi(int(_items.get(cleaned, 0)), 0)


func has_item(item_id: String, amount: int = 1) -> bool:
	return get_amount(item_id) >= maxi(amount, 1)


func get_total_units() -> int:
	var total := 0
	for key in _items.keys():
		total += get_amount(str(key))
	return total


func get_snapshot() -> Dictionary:
	var snapshot: Dictionary = {}
	for key in _items.keys():
		var cleaned := str(key).strip_edges()
		if cleaned.is_empty():
			continue
		var amount := get_amount(cleaned)
		if amount > 0:
			snapshot[cleaned] = amount
	return snapshot


func get_category_snapshot(prefixes: PackedStringArray) -> Dictionary:
	var snapshot: Dictionary = {}
	for key in _items.keys():
		var cleaned := str(key).strip_edges()
		if cleaned.is_empty():
			continue
		for prefix in prefixes:
			if cleaned.begins_with(prefix):
				snapshot[cleaned] = get_amount(cleaned)
				break
	return snapshot


func format_contents(labels: Dictionary = {}) -> String:
	var parts: PackedStringArray = []
	for key in _items.keys():
		var item_id := str(key)
		var amount := get_amount(item_id)
		if amount <= 0:
			continue
		var label := str(labels.get(item_id, item_id))
		parts.append("%s x%d" % [label, amount])
	if parts.is_empty():
		return "-"
	return ", ".join(parts)
