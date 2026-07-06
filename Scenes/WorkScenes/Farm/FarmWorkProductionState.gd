extends RefCounted
class_name FarmWorkProductionState

signal changed()

var selected_grain_type: String = "wheat"
var required_grain: int = 10
var duration_sec: float = 8.0
var progress_sec: float = 0.0
var running: bool = false
var paused: bool = false
var produced_sacks_pending: int = 0
var total_sacks_produced: int = 0


func reset() -> void:
	progress_sec = 0.0
	running = false
	paused = false
	produced_sacks_pending = 0
	total_sacks_produced = 0
	changed.emit()


func apply_snapshot(data: Dictionary) -> void:
	var grain := str(data.get("selected_grain_type", selected_grain_type)).strip_edges()
	selected_grain_type = grain if not grain.is_empty() else "wheat"
	required_grain = maxi(int(data.get("required_grain", required_grain)), 1)
	duration_sec = maxf(float(data.get("duration_sec", duration_sec)), 0.1)
	progress_sec = clampf(float(data.get("progress_sec", progress_sec)), 0.0, duration_sec)
	running = bool(data.get("running", running))
	paused = bool(data.get("paused", paused)) and running
	produced_sacks_pending = maxi(int(data.get("produced_sacks_pending", produced_sacks_pending)), 0)
	total_sacks_produced = maxi(int(data.get("total_sacks_produced", total_sacks_produced)), produced_sacks_pending)
	changed.emit()


func start(grain_type: String, silo_inventory) -> bool:
	if silo_inventory == null or running:
		return false
	var cleaned := grain_type.strip_edges()
	if cleaned.is_empty():
		cleaned = "wheat"
	var grain_item := "%s_grain" % cleaned
	if silo_inventory.get_amount(grain_item) < required_grain:
		return false
	silo_inventory.remove_item(grain_item, required_grain)
	selected_grain_type = cleaned
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


func tick(delta: float) -> int:
	if not running or paused:
		return 0
	progress_sec = minf(progress_sec + maxf(delta, 0.0), maxf(duration_sec, 0.01))
	if progress_sec < duration_sec:
		changed.emit()
		return 0
	running = false
	paused = false
	progress_sec = duration_sec
	var produced := 3
	produced_sacks_pending += produced
	total_sacks_produced += produced
	changed.emit()
	return produced


func collect_sacks() -> int:
	var collected := produced_sacks_pending
	if collected <= 0:
		return 0
	produced_sacks_pending = 0
	changed.emit()
	return collected


func get_progress_ratio() -> float:
	return clampf(progress_sec / maxf(duration_sec, 0.01), 0.0, 1.0)


func get_snapshot() -> Dictionary:
	return {
		"selected_grain_type": selected_grain_type,
		"required_grain": required_grain,
		"duration_sec": duration_sec,
		"progress_sec": progress_sec,
		"progress_ratio": get_progress_ratio(),
		"running": running,
		"paused": paused,
		"produced_sacks_pending": produced_sacks_pending,
		"total_sacks_produced": total_sacks_produced,
	}
