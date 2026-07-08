extends RefCounted
class_name FarmWorkProductionState

signal changed()

const DEFAULT_GRAIN_TYPE := "wheat"
const DEFAULT_INPUT_ITEM := "wheat_grain"
const DEFAULT_OUTPUT_ITEM := "flour_sack"
const DEFAULT_REQUIRED_GRAIN := 10
const DEFAULT_OUTPUT_AMOUNT := 3

var selected_grain_type: String = DEFAULT_GRAIN_TYPE
var input_item_id: String = DEFAULT_INPUT_ITEM
var output_item_id: String = DEFAULT_OUTPUT_ITEM
var required_grain: int = DEFAULT_REQUIRED_GRAIN
var output_amount: int = DEFAULT_OUTPUT_AMOUNT
var duration_sec: float = 8.0
var progress_sec: float = 0.0
var running: bool = false
var paused: bool = false
var produced_items_pending: Dictionary = {}
var total_items_produced: Dictionary = {}
var produced_sacks_pending: int = 0
var total_sacks_produced: int = 0


func reset() -> void:
	selected_grain_type = DEFAULT_GRAIN_TYPE
	input_item_id = DEFAULT_INPUT_ITEM
	output_item_id = DEFAULT_OUTPUT_ITEM
	required_grain = DEFAULT_REQUIRED_GRAIN
	output_amount = DEFAULT_OUTPUT_AMOUNT
	progress_sec = 0.0
	running = false
	paused = false
	produced_items_pending.clear()
	total_items_produced.clear()
	_sync_legacy_flour_counts()
	changed.emit()


func apply_snapshot(data: Dictionary) -> void:
	var grain := str(data.get("selected_grain_type", selected_grain_type)).strip_edges()
	selected_grain_type = grain if not grain.is_empty() else DEFAULT_GRAIN_TYPE
	input_item_id = _clean_item_id(data.get("input_item_id", "%s_grain" % selected_grain_type), DEFAULT_INPUT_ITEM)
	output_item_id = _clean_item_id(data.get("output_item_id", DEFAULT_OUTPUT_ITEM), DEFAULT_OUTPUT_ITEM)
	required_grain = maxi(int(data.get("required_grain", required_grain)), 1)
	output_amount = maxi(int(data.get("output_amount", output_amount)), 1)
	duration_sec = maxf(float(data.get("duration_sec", duration_sec)), 0.1)
	progress_sec = clampf(float(data.get("progress_sec", progress_sec)), 0.0, duration_sec)
	running = bool(data.get("running", running))
	paused = bool(data.get("paused", paused)) and running
	produced_items_pending = _sanitize_item_counts(data.get("produced_items_pending", {}))
	total_items_produced = _sanitize_item_counts(data.get("total_items_produced", {}))
	var legacy_pending := maxi(int(data.get("produced_sacks_pending", 0)), 0)
	if produced_items_pending.is_empty() and legacy_pending > 0:
		produced_items_pending[DEFAULT_OUTPUT_ITEM] = legacy_pending
	var legacy_total := maxi(int(data.get("total_sacks_produced", 0)), legacy_pending)
	if total_items_produced.is_empty() and legacy_total > 0:
		total_items_produced[DEFAULT_OUTPUT_ITEM] = legacy_total
	_sync_legacy_flour_counts()
	changed.emit()


func start(grain_type: String, silo_inventory, recipe: Dictionary = {}) -> bool:
	if silo_inventory == null or running:
		return false
	var cleaned := grain_type.strip_edges()
	if cleaned.is_empty():
		cleaned = DEFAULT_GRAIN_TYPE
	var next_input := _clean_item_id(recipe.get("input_item_id", recipe.get("input_item", "%s_grain" % cleaned)), "%s_grain" % cleaned)
	var next_required := maxi(int(recipe.get("required_grain", recipe.get("required", required_grain))), 1)
	var next_output := _clean_item_id(recipe.get("output_item_id", recipe.get("output_item", DEFAULT_OUTPUT_ITEM)), DEFAULT_OUTPUT_ITEM)
	var next_output_amount := maxi(int(recipe.get("output_amount", output_amount)), 1)
	var next_duration := maxf(float(recipe.get("duration_sec", duration_sec)), 0.1)
	if silo_inventory.get_amount(next_input) < next_required:
		return false
	silo_inventory.remove_item(next_input, next_required)
	selected_grain_type = cleaned
	input_item_id = next_input
	output_item_id = next_output
	required_grain = next_required
	output_amount = next_output_amount
	duration_sec = next_duration
	progress_sec = 0.0
	running = true
	paused = false
	changed.emit()
	return true


func pause() -> bool:
	if not running:
		return false
	paused = not paused
	changed.emit()
	return true


func tick(delta: float) -> Dictionary:
	if not running or paused:
		return {}
	progress_sec = minf(progress_sec + maxf(delta, 0.0), maxf(duration_sec, 0.01))
	if progress_sec < duration_sec:
		changed.emit()
		return {}
	running = false
	paused = false
	progress_sec = duration_sec
	_add_item_count(produced_items_pending, output_item_id, output_amount)
	_add_item_count(total_items_produced, output_item_id, output_amount)
	_sync_legacy_flour_counts()
	changed.emit()
	return {output_item_id: output_amount}


func collect_items() -> Dictionary:
	if produced_items_pending.is_empty():
		return {}
	var collected := produced_items_pending.duplicate(true)
	produced_items_pending.clear()
	_sync_legacy_flour_counts()
	changed.emit()
	return collected


func collect_sacks() -> int:
	var collected := maxi(int(produced_items_pending.get(DEFAULT_OUTPUT_ITEM, 0)), 0)
	if collected <= 0:
		return 0
	produced_items_pending.erase(DEFAULT_OUTPUT_ITEM)
	_sync_legacy_flour_counts()
	changed.emit()
	return collected


func get_progress_ratio() -> float:
	return clampf(progress_sec / maxf(duration_sec, 0.01), 0.0, 1.0)


func get_total_produced_units() -> int:
	return _dict_total(total_items_produced)


func get_pending_units() -> int:
	return _dict_total(produced_items_pending)


func get_snapshot() -> Dictionary:
	return {
		"selected_grain_type": selected_grain_type,
		"input_item_id": input_item_id,
		"output_item_id": output_item_id,
		"required_grain": required_grain,
		"output_amount": output_amount,
		"duration_sec": duration_sec,
		"progress_sec": progress_sec,
		"progress_ratio": get_progress_ratio(),
		"running": running,
		"paused": paused,
		"produced_items_pending": produced_items_pending.duplicate(true),
		"total_items_produced": total_items_produced.duplicate(true),
		"produced_sacks_pending": produced_sacks_pending,
		"total_sacks_produced": total_sacks_produced,
	}


func _clean_item_id(value, fallback: String) -> String:
	var item_id := str(value).strip_edges()
	return item_id if not item_id.is_empty() else fallback


func _sanitize_item_counts(value) -> Dictionary:
	var source := value as Dictionary
	if source == null:
		return {}
	var sanitized: Dictionary = {}
	for key in source.keys():
		var item_id := str(key).strip_edges()
		if item_id.is_empty():
			continue
		var amount := maxi(int(source.get(key, 0)), 0)
		if amount > 0:
			sanitized[item_id] = amount
	return sanitized


func _add_item_count(target: Dictionary, item_id: String, amount: int) -> void:
	var cleaned := item_id.strip_edges()
	if cleaned.is_empty() or amount <= 0:
		return
	target[cleaned] = maxi(int(target.get(cleaned, 0)), 0) + amount


func _dict_total(data: Dictionary) -> int:
	var total := 0
	for key in data.keys():
		total += maxi(int(data.get(key, 0)), 0)
	return total


func _sync_legacy_flour_counts() -> void:
	produced_sacks_pending = maxi(int(produced_items_pending.get(DEFAULT_OUTPUT_ITEM, 0)), 0)
	total_sacks_produced = maxi(int(total_items_produced.get(DEFAULT_OUTPUT_ITEM, 0)), produced_sacks_pending)
