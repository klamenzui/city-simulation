extends Building
class_name University

@export var tuition_fee: int = 25
@export var education_gain: int = 1

func _ready() -> void:
	super._ready()
	building_type = BuildingType.UNIVERSITY
	var settings := apply_balance_settings("university")
	tuition_fee = int(settings.get("tuition_fee", tuition_fee))
	education_gain = int(settings.get("education_gain", education_gain))
	add_to_group("work")

func get_service_type() -> String:
	return "education"

func has_teaching_staff() -> bool:
	return workers.size() > 0

func can_study(citizen: Citizen) -> bool:
	if citizen == null:
		return false
	if not is_open():
		return false
	if not has_teaching_staff():
		return false
	if citizen.wallet.balance < tuition_fee:
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

func study_session(world: World, citizen: Citizen) -> bool:
	if citizen == null:
		return false
	if not world.economy.transfer(citizen.wallet, account, tuition_fee):
		return false
	record_income(tuition_fee)
	citizen.education_level += education_gain
	return true

func _get_extra_info(_world = null) -> Dictionary:
	return {
		"Tuition": "%d €" % tuition_fee,
		"Education gain": "+%d" % education_gain,
		"Teaching staff": "%d / 1" % mini(workers.size(), 1),
	}
