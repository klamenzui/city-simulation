extends SceneTree

const CityInventoryAdapterScript = preload("res://Simulation/Inventory/CityInventoryAdapter.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	var counts: Dictionary = {}
	CityInventoryAdapterScript.add_count(counts, "grocery_bundle", 3)
	CityInventoryAdapterScript.add_count(counts, "clothing", 2)
	_expect_eq(CityInventoryAdapterScript.get_count(counts, "food"), 3, "alias grocery_bundle should normalize to food", failures)
	_expect_eq(CityInventoryAdapterScript.get_count(counts, "clothing"), 2, "clothing count should be stored", failures)
	_expect_eq(CityInventoryAdapterScript.remove_count(counts, "food", 1), 1, "remove should report removed food count", failures)
	_expect_eq(CityInventoryAdapterScript.get_count(counts, "food"), 2, "remove should lower food count", failures)

	_expect(FileAccess.file_exists("res://addons/gloot/plugin.cfg"), "GLoot plugin should be installed", failures)
	_expect(FileAccess.file_exists(CityInventoryAdapterScript.PROTOSET_PATH), "city inventory protoset should exist", failures)

	if failures.is_empty():
		print("INVENTORY_ADAPTER_TEST OK")
		quit(0)
		return
	print("INVENTORY_ADAPTER_TEST FAILED:")
	for failure in failures:
		print("  - %s" % failure)
	quit(1)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)


func _expect_eq(actual, expected, message: String, failures: Array[String]) -> void:
	if actual != expected:
		failures.append("%s (expected %s, got %s)" % [message, str(expected), str(actual)])
