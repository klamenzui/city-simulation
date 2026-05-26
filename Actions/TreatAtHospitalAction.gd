extends Action
class_name TreatAtHospitalAction

const BalanceConfig = preload("res://Simulation/Config/BalanceConfig.gd")
const SimLogger = preload("res://Simulation/Logging/SimLogger.gd")

var hospital = null
var emergency: bool = false

var _registered: bool = false
var _treating: bool = false
var _treatment_minutes: int = 0
var _wait_minutes: int = 0
var _min_treatment_minutes: int = 20
var _max_treatment_minutes: int = 70
var _target_health: float = 80.0
var _needs_modifier: Dictionary = Action.make_default_needs_modifier()

func _init(_hospital = null, _emergency: bool = false) -> void:
	super()
	hospital = _hospital
	emergency = _emergency
	label = "EmergencyCare" if emergency else "Treatment"
	var config := BalanceConfig.get_section("actions.hospital_treatment")
	_min_treatment_minutes = int(config.get("emergency_min_minutes", 15)) if emergency \
		else int(config.get("min_minutes", 20))
	_max_treatment_minutes = int(config.get("emergency_max_minutes", 55)) if emergency \
		else int(config.get("max_minutes", 70))
	_target_health = float(config.get("emergency_target_health", 85.0)) if emergency \
		else float(config.get("target_health", 75.0))

func start(world, citizen) -> void:
	super.start(world, citizen)
	_registered = false
	_treating = false
	_treatment_minutes = 0
	_wait_minutes = 0
	remaining_minutes = 0
	if hospital == null or citizen == null or world == null:
		finished = true
		return
	if citizen.current_location != hospital:
		finished = true
		return
	if not hospital.request_treatment(citizen, world, emergency):
		SimLogger.log("[Citizen %s] Treatment refused at %s." % [
			citizen.citizen_name,
			hospital.get_display_name(),
		])
		finished = true
		return
	_registered = true

func tick(world, citizen, dt: int) -> void:
	super.tick(world, citizen, dt)
	if hospital == null or citizen == null or not _registered:
		finished = true
		return
	if hospital.is_financially_closed():
		finished = true
		return

	if not _treating:
		_wait_minutes += maxi(dt, 0)
		if hospital.can_start_treatment(citizen):
			var payment: Dictionary = hospital.begin_treatment(citizen, world, emergency)
			if bool(payment.get("started", false)):
				_treating = true
				_refresh_needs_modifier()
				SimLogger.log("[Citizen %s] %s started at %s | paid=%d subsidy=%d charity=%d quality=%.2f" % [
					citizen.citizen_name,
					"Emergency treatment" if emergency else "Treatment",
					hospital.get_display_name(),
					int(payment.get("paid", 0)),
					int(payment.get("subsidy", 0)),
					int(payment.get("charity", 0)),
					hospital.get_service_quality(),
				])
				return
		if _wait_minutes >= hospital.patient_wait_timeout_minutes:
			SimLogger.log("[Citizen %s] Left %s after waiting %d minutes for treatment." % [
				citizen.citizen_name,
				hospital.get_display_name(),
				_wait_minutes,
			])
			finished = true
		return

	_treatment_minutes += maxi(dt, 0)
	if citizen.needs != null and citizen.needs.health >= _target_health and _treatment_minutes >= _min_treatment_minutes:
		finished = true
		return
	if _treatment_minutes >= _max_treatment_minutes:
		finished = true

func finish(world, citizen) -> void:
	if hospital != null and citizen != null:
		if _treating:
			hospital.finish_treatment(citizen)
		else:
			hospital.cancel_treatment(citizen)
		hospital.remove_visitor(citizen)
	_registered = false
	_treating = false

func get_needs_modifier(world, citizen) -> Dictionary:
	if not _treating or hospital == null:
		return Action.make_default_needs_modifier()
	_refresh_needs_modifier()
	return _needs_modifier

func _refresh_needs_modifier() -> void:
	_needs_modifier = {
		"hunger_mul": 0.75,
		"energy_mul": 0.55,
		"fun_mul": 0.25,
		"hunger_add": 0.0,
		"energy_add": 0.04,
		"fun_add": -0.01,
		"health_add": hospital.get_effective_healing_per_minute(emergency) if hospital != null else 0.0,
	}
