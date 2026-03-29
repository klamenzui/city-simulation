extends Building
class_name University

@export var education_gain: int = 1

func _ready() -> void:
	super._ready()
	building_type = BuildingType.UNIVERSITY
	var settings := apply_balance_settings("university")
	education_gain = int(settings.get("education_gain", education_gain))
	add_to_group("work")

func get_service_type() -> String:
	return "education"

func has_teaching_staff() -> bool:
	return not get_workers_by_titles(["Professor", "Teacher"]).is_empty()

func has_required_staff() -> bool:
	return has_teaching_staff()

func get_staff_requirement_label() -> String:
	return "keine Lehrkraft"

func can_study(citizen: Citizen) -> bool:
	if citizen == null:
		return false
	if not is_open():
		return false
	if not has_teaching_staff():
		return false
	return true

func begin_study(citizen: Citizen) -> bool:
	if citizen == null:
		return false
	if not is_open():
		return false
	return try_add_visitor(citizen)

func finish_study(citizen: Citizen) -> void:
	remove_visitor(citizen)

func study_session(_world: World, citizen: Citizen) -> bool:
	if citizen == null:
		return false
	if not can_study(citizen):
		return false
	var effective_gain := maxi(int(round(float(education_gain) * get_operating_efficiency_multiplier())), 1)
	citizen.education_level += effective_gain
	return true

func _get_extra_info(_world = null) -> Dictionary:
	return {
		"Education gain": "+%d" % education_gain,
		"Teaching staff": "%d" % get_workers_by_titles(["Professor", "Teacher"]).size(),
		"Base operating cost": "%d EUR" % get_base_operating_cost_per_day(),
		"Payroll due": "%d EUR" % get_payroll_due_today(),
	}
