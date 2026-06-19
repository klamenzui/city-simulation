extends RefCounted
class_name FarmWorkFieldData

enum FieldState {
	PREPARED,
	SEEDED,
	GROWING,
	MATURE,
	HARVESTED,
}

const CROP_WHEAT := "wheat"
const CROP_CORN := "corn"
const CROP_SUNFLOWER := "sunflower"

var field_id: String = ""
var display_name: String = "Field"
var allowed_crop_type: String = CROP_WHEAT
var crop_type: String = ""
var state: FieldState = FieldState.PREPARED
var growth: float = 0.0
var water: float = 0.0
var harvested_units: int = 0


func configure(id: String, label: String, crop: String, initial_state: FieldState = FieldState.PREPARED) -> void:
	field_id = id.strip_edges()
	display_name = label.strip_edges() if not label.strip_edges().is_empty() else "Field"
	allowed_crop_type = crop.strip_edges() if not crop.strip_edges().is_empty() else CROP_WHEAT
	crop_type = "" if initial_state == FieldState.PREPARED else allowed_crop_type
	state = initial_state
	growth = 1.0 if initial_state == FieldState.MATURE else 0.0
	water = 0.0
	harvested_units = 0


func sow(selected_crop_type: String) -> bool:
	var selected := selected_crop_type.strip_edges()
	if selected.is_empty() or selected != allowed_crop_type:
		return false
	if state != FieldState.PREPARED and state != FieldState.HARVESTED:
		return false
	crop_type = selected
	state = FieldState.SEEDED
	growth = 0.0
	water = 0.0
	harvested_units = 0
	return true


func water_field() -> bool:
	if state != FieldState.SEEDED and state != FieldState.GROWING:
		return false
	water = 1.0
	state = FieldState.GROWING
	return true


func tick_growth(delta: float, growth_duration_sec: float) -> bool:
	if state != FieldState.GROWING:
		return false
	if growth_duration_sec <= 0.0:
		growth = 1.0
	else:
		growth = clampf(growth + delta / growth_duration_sec, 0.0, 1.0)
	water = maxf(water - delta / maxf(growth_duration_sec * 1.4, 1.0), 0.0)
	if growth >= 1.0:
		state = FieldState.MATURE
		water = 0.0
		return true
	return false


func harvest(units: int) -> int:
	if state != FieldState.MATURE:
		return 0
	harvested_units = maxi(units, 0)
	state = FieldState.HARVESTED
	growth = 0.0
	water = 0.0
	return harvested_units


func can_sow(selected_crop_type: String) -> bool:
	return selected_crop_type.strip_edges() == allowed_crop_type \
		and (state == FieldState.PREPARED or state == FieldState.HARVESTED)


func can_water() -> bool:
	return state == FieldState.SEEDED or state == FieldState.GROWING


func can_harvest() -> bool:
	return state == FieldState.MATURE


func get_state_label() -> String:
	match state:
		FieldState.PREPARED:
			return "prepared"
		FieldState.SEEDED:
			return "seeded"
		FieldState.GROWING:
			return "growing"
		FieldState.MATURE:
			return "mature"
		FieldState.HARVESTED:
			return "harvested"
	return "unknown"


func get_crop_label() -> String:
	match crop_type if not crop_type.is_empty() else allowed_crop_type:
		CROP_WHEAT:
			return "Wheat"
		CROP_CORN:
			return "Corn"
		CROP_SUNFLOWER:
			return "Sunflower"
	return crop_type


func get_snapshot() -> Dictionary:
	return {
		"field_id": field_id,
		"display_name": display_name,
		"allowed_crop_type": allowed_crop_type,
		"crop_type": crop_type,
		"crop_label": get_crop_label(),
		"state": int(state),
		"state_label": get_state_label(),
		"growth": growth,
		"water": water,
		"harvested_units": harvested_units,
	}
