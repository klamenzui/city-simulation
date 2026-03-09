extends Building
class_name University

@export var tuition_fee: int = 25
@export var education_gain: int = 1

func _ready() -> void:
	super._ready()
	building_type = BuildingType.UNIVERSITY
	open_hour = 7
	close_hour = 21
	capacity = max(capacity, 40)
	if job_capacity <= 0:
		job_capacity = 8
	add_to_group("work")

func get_service_type() -> String:
	return "education"

func can_study(citizen: Citizen) -> bool:
	if citizen == null:
		return false
	if not is_open():
		return false
	if citizen.wallet.balance < tuition_fee:
		return false
	return true

func begin_study(citizen: Citizen) -> bool:
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
	}
