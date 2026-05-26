extends Building
class_name Hospital

const MEDICAL_ROLE_TITLES: Array[String] = ["Doctor", "Nurse", "Pharmacist", "Therapist"]
const CORE_MEDICAL_ROLE_TITLES: Array[String] = ["Doctor", "Nurse"]

@export var patient_capacity: int = 20
@export var treatment_capacity_per_hour: int = 6
@export var is_public_service: bool = true
@export_range(0.1, 2.0, 0.01) var service_quality: float = 1.0
@export var treatment_price: int = 25
@export var emergency_treatment_price: int = 60
@export var daily_operating_cost: int = 250
@export var patient_wait_timeout_minutes: int = 180
@export_range(0.0, 1.0, 0.01) var charity_care_city_subsidy_ratio: float = 1.0
@export var citizen_payment_reserve: int = 35

var patient_queue: Array[Citizen] = []
var emergency_queue: Array[Citizen] = []
var active_patients: Array[Citizen] = []
var treatments_today: int = 0
var emergency_treatments_today: int = 0
var patients_turned_away_today: int = 0
var treatment_income_today: int = 0
var charity_care_today: int = 0
var average_wait_minutes_today: float = 0.0

var _patient_wait_minutes_by_id: Dictionary = {}
var _treatment_tokens: float = 0.0
var _warned_no_staff_day: int = -1

func _ready() -> void:
	building_name = "Hospital"
	building_type = BuildingType.HOSPITAL
	capacity = 20
	job_capacity = 5
	open_hour = 0
	close_hour = 24
	base_operating_cost = daily_operating_cost
	super._ready()
	var settings := apply_balance_settings("hospital")
	patient_capacity = int(settings.get("patient_capacity", patient_capacity))
	treatment_capacity_per_hour = int(settings.get("treatment_capacity_per_hour", treatment_capacity_per_hour))
	is_public_service = bool(settings.get("is_public_service", is_public_service))
	service_quality = float(settings.get("service_quality", service_quality))
	treatment_price = int(settings.get("treatment_price", treatment_price))
	emergency_treatment_price = int(settings.get("emergency_treatment_price", emergency_treatment_price))
	daily_operating_cost = int(settings.get("daily_operating_cost", get_base_operating_cost_per_day()))
	patient_wait_timeout_minutes = int(settings.get("patient_wait_timeout_minutes", patient_wait_timeout_minutes))
	charity_care_city_subsidy_ratio = float(settings.get("charity_care_city_subsidy_ratio", charity_care_city_subsidy_ratio))
	citizen_payment_reserve = int(settings.get("citizen_payment_reserve", citizen_payment_reserve))
	base_operating_cost = daily_operating_cost
	_treatment_tokens = float(maxi(treatment_capacity_per_hour, 1))
	add_to_group("work")
	add_to_group("service")
	add_to_group("public_service")
	add_to_group("healthcare")

func get_service_type() -> String:
	return "healthcare"

func get_default_job_title() -> String:
	return "Doctor"

func has_required_staff() -> bool:
	if not requires_staff_to_operate():
		return true
	return has_core_medical_staff()

func get_staff_requirement_label() -> String:
	return LocaleServiceScript.t("details.staff_requirement.medical")

func begin_new_day() -> void:
	super.begin_new_day()
	treatments_today = 0
	emergency_treatments_today = 0
	patients_turned_away_today = 0
	treatment_income_today = 0
	charity_care_today = 0
	average_wait_minutes_today = 0.0
	_warned_no_staff_day = -1

func sim_tick(world: World, elapsed_minutes: int) -> void:
	var refill := (float(maxi(treatment_capacity_per_hour, 1)) / 60.0) * float(maxi(elapsed_minutes, 0))
	_treatment_tokens = minf(float(maxi(treatment_capacity_per_hour, 1)), _treatment_tokens + refill)
	_prune_patient_lists()
	_tick_queue_waits(elapsed_minutes)
	if get_queued_patient_count() > 0 and not has_core_medical_staff():
		_log_no_staff_once(world)

func can_accept_patient(citizen: Citizen) -> bool:
	if citizen == null:
		return false
	if is_financially_closed():
		return false
	if _is_patient_known(citizen):
		return true
	if get_total_patient_load() >= get_effective_patient_capacity():
		return false
	return true

func request_treatment(citizen: Citizen, world: World, emergency: bool = false) -> bool:
	if citizen == null:
		return false
	if not is_open(_get_world_hour(world)):
		patients_turned_away_today += 1
		return false
	if not can_accept_patient(citizen):
		patients_turned_away_today += 1
		return false
	if _is_patient_known(citizen):
		return true
	if emergency:
		emergency_queue.append(citizen)
	else:
		patient_queue.append(citizen)
	_patient_wait_minutes_by_id[citizen.get_instance_id()] = 0
	return true

func can_start_treatment(citizen: Citizen) -> bool:
	if citizen == null:
		return false
	if active_patients.has(citizen):
		return true
	if not has_core_medical_staff():
		return false
	if active_patients.size() >= get_concurrent_treatment_slots():
		return false
	if _treatment_tokens < 1.0:
		return false
	var next_patient := _peek_next_patient()
	return next_patient == citizen

func begin_treatment(citizen: Citizen, world: World, emergency: bool = false) -> Dictionary:
	if not can_start_treatment(citizen):
		return {"started": false, "paid": 0, "subsidy": 0, "charity": 0}
	_remove_from_queues(citizen)
	active_patients.append(citizen)
	_treatment_tokens = maxf(_treatment_tokens - 1.0, 0.0)
	var wait_minutes := int(_patient_wait_minutes_by_id.get(citizen.get_instance_id(), 0))
	_record_wait_time(wait_minutes)
	_patient_wait_minutes_by_id.erase(citizen.get_instance_id())
	var payment := _charge_for_treatment(world, citizen, emergency)
	treatments_today += 1
	if emergency:
		emergency_treatments_today += 1
	return payment

func finish_treatment(citizen: Citizen) -> void:
	if citizen == null:
		return
	active_patients.erase(citizen)

func cancel_treatment(citizen: Citizen) -> void:
	if citizen == null:
		return
	_remove_from_queues(citizen)
	active_patients.erase(citizen)
	_patient_wait_minutes_by_id.erase(citizen.get_instance_id())

func leave(citizen: Citizen) -> void:
	cancel_treatment(citizen)
	remove_visitor(citizen)

func get_effective_patient_capacity() -> int:
	if patient_capacity <= 0:
		return 0
	return maxi(int(round(float(patient_capacity) * get_service_multiplier())), 1)

func get_queued_patient_count() -> int:
	return patient_queue.size() + emergency_queue.size()

func get_total_patient_load() -> int:
	return get_queued_patient_count() + active_patients.size()

func get_concurrent_treatment_slots() -> int:
	var staff_weight := _get_medical_staff_weight()
	if staff_weight <= 0.0:
		return 0
	var staff_slots := maxi(int(round(staff_weight * 2.0)), 1)
	return maxi(mini(staff_slots, get_effective_patient_capacity()), 1)

func has_core_medical_staff() -> bool:
	return not get_workers_by_titles(CORE_MEDICAL_ROLE_TITLES).is_empty()

func has_medical_staff() -> bool:
	return not get_workers_by_titles(MEDICAL_ROLE_TITLES).is_empty()

func get_service_quality() -> float:
	if not has_core_medical_staff():
		return 0.0
	var quality := service_quality
	quality *= get_condition_efficiency_multiplier()
	quality *= get_service_multiplier()
	quality *= _get_staff_quality_multiplier()
	if public_funding_requested_today > 0 and public_funding_shortfall_today > 0:
		var funded_ratio := float(public_funding_today) / float(maxi(public_funding_requested_today, 1))
		quality *= clampf(0.5 + funded_ratio * 0.5, 0.45, 1.0)
	return clampf(quality, 0.1, 1.4)

func get_effective_healing_per_minute(emergency: bool = false) -> float:
	var settings := BalanceConfig.get_section("actions.hospital_treatment")
	var base_rate := float(settings.get("emergency_health_add_per_min", 1.7)) if emergency \
		else float(settings.get("health_add_per_min", 0.95))
	return base_rate * get_service_quality()

func get_treatment_price(emergency: bool = false) -> int:
	return emergency_treatment_price if emergency else treatment_price

func _get_extra_info_sections(_world = null) -> Array:
	var rows: Array = [
		{"label": LocaleServiceScript.t("details.label.patients"), "value": "%d / %d" % [get_total_patient_load(), get_effective_patient_capacity()]},
		{"label": LocaleServiceScript.t("details.label.queue"), "value": "%d (%d emergency)" % [get_queued_patient_count(), emergency_queue.size()]},
		{"label": LocaleServiceScript.t("details.label.treatment_capacity"), "value": "%d / h" % treatment_capacity_per_hour},
		{"label": LocaleServiceScript.t("details.label.service_quality"), "value": "%.0f%%" % (get_service_quality() * 100.0)},
		{"label": LocaleServiceScript.t("details.label.treatments_today"), "value": "%d (%d emergency)" % [treatments_today, emergency_treatments_today]},
		{"label": LocaleServiceScript.t("details.label.charity_care"), "value": "%d EUR" % charity_care_today},
	]
	return [{"title": LocaleServiceScript.t("details.section.healthcare"), "rows": rows}]

func _charge_for_treatment(world: World, citizen: Citizen, emergency: bool) -> Dictionary:
	var price := maxi(get_treatment_price(emergency), 0)
	var result := {"started": true, "paid": 0, "subsidy": 0, "charity": 0}
	if price <= 0 or world == null or world.economy == null:
		return result

	var paid := 0
	if citizen != null and citizen.wallet != null:
		var affordable := maxi(citizen.wallet.balance - maxi(citizen_payment_reserve, 0), 0)
		paid = mini(price, affordable)
		if paid > 0 and world.economy.transfer(citizen.wallet, account, paid):
			record_income(paid)
			treatment_income_today += paid
			result["paid"] = paid
		else:
			paid = 0

	var shortfall := price - paid
	if shortfall <= 0:
		return result

	var subsidy_target := int(round(float(shortfall) * clampf(charity_care_city_subsidy_ratio, 0.0, 1.0)))
	var subsidy := 0
	if subsidy_target > 0:
		record_public_funding_request(subsidy_target)
	var city_hall := world.find_city_hall() if world.has_method("find_city_hall") else null
	if subsidy_target > 0 and city_hall != null and city_hall.has_method("subsidize_healthcare"):
		subsidy = int(city_hall.subsidize_healthcare(world, self, subsidy_target))
		if subsidy > 0:
			treatment_income_today += subsidy
			result["subsidy"] = subsidy

	var charity := shortfall - subsidy
	if charity > 0:
		charity_care_today += charity
		record_public_funding_shortfall(charity)
		result["charity"] = charity
	return result

func _tick_queue_waits(elapsed_minutes: int) -> void:
	for citizen in patient_queue + emergency_queue:
		if citizen == null:
			continue
		var id := citizen.get_instance_id()
		_patient_wait_minutes_by_id[id] = int(_patient_wait_minutes_by_id.get(id, 0)) + maxi(elapsed_minutes, 0)

func _prune_patient_lists() -> void:
	_prune_queue(patient_queue)
	_prune_queue(emergency_queue)
	_prune_queue(active_patients)

func _prune_queue(queue: Array[Citizen]) -> void:
	var invalid: Array[Citizen] = []
	for citizen in queue:
		if citizen == null or not is_instance_valid(citizen):
			invalid.append(citizen)
	for citizen in invalid:
		queue.erase(citizen)
		if citizen != null:
			_patient_wait_minutes_by_id.erase(citizen.get_instance_id())

func _peek_next_patient() -> Citizen:
	if not emergency_queue.is_empty():
		return emergency_queue[0]
	if not patient_queue.is_empty():
		return patient_queue[0]
	return null

func _is_patient_known(citizen: Citizen) -> bool:
	return active_patients.has(citizen) or emergency_queue.has(citizen) or patient_queue.has(citizen)

func _remove_from_queues(citizen: Citizen) -> void:
	emergency_queue.erase(citizen)
	patient_queue.erase(citizen)

func _record_wait_time(wait_minutes: int) -> void:
	var total_before := average_wait_minutes_today * float(maxi(treatments_today, 0))
	average_wait_minutes_today = (total_before + float(maxi(wait_minutes, 0))) / float(maxi(treatments_today + 1, 1))

func _get_staff_quality_multiplier() -> float:
	var worker_capacity := maxi(job_capacity, 1)
	var weighted_staff := _get_medical_staff_weight()
	return clampf(0.45 + weighted_staff / float(worker_capacity), 0.55, 1.25)

func _get_medical_staff_weight() -> float:
	var weight := 0.0
	for worker in workers:
		if worker == null or worker.job == null:
			continue
		match worker.job.title:
			"Doctor":
				weight += 1.0
			"Nurse":
				weight += 0.8
			"Pharmacist", "Therapist":
				weight += 0.5
	return weight

func _get_world_hour(world: World) -> int:
	if world != null and world.time != null:
		return world.time.get_hour()
	return -1

func _log_no_staff_once(world: World) -> void:
	var day := world.world_day() if world != null and world.has_method("world_day") else 0
	if _warned_no_staff_day == day:
		return
	_warned_no_staff_day = day
	SimLogger.log("[Hospital] Patients waiting but no Doctor/Nurse is employed at %s." % get_display_name())
