extends RefCounted
class_name CitizenHealthGoap

const BalanceConfig = preload("res://Simulation/Config/BalanceConfig.gd")
const GoapActionScript = preload("res://Simulation/GOAP/GoapAction.gd")
const GoapPlannerScript = preload("res://Simulation/GOAP/GoapPlanner.gd")
const GoToBuildingActionScript = preload("res://Actions/GoToBuildingAction.gd")
const TaxiToBuildingActionScript = preload("res://Actions/TaxiToBuildingAction.gd")
const TreatAtHospitalActionScript = preload("res://Actions/TreatAtHospitalAction.gd")

const HOSPITAL_DEPOT_MARKER_NAME := "HospitalVehicleDepot"

var _treatment_threshold: float = BalanceConfig.get_float("planner.health.visit_threshold", 20.0)
var _emergency_threshold: float = BalanceConfig.get_float("planner.health.emergency_threshold", 5.0)
var _taxi_threshold: float = BalanceConfig.get_float("planner.health.taxi_threshold", _treatment_threshold)
var _go_hospital_cost: float = BalanceConfig.get_float("goap.health.go_hospital_cost", 0.45)
var _treatment_cost: float = BalanceConfig.get_float("goap.health.treatment_cost", 0.25)
var _travel_minutes: int = BalanceConfig.get_int("goap.health.travel_minutes", 18)

func try_plan(world, citizen) -> bool:
	if world == null or citizen == null or citizen.needs == null:
		return false
	if citizen.needs.health >= _treatment_threshold:
		return false

	var hospital = _select_hospital(citizen)
	if hospital == null:
		citizen.debug_log_once_per_day(
			"health_no_hospital",
			"Health treatment blocked: no reachable hospital found."
		)
		return false
	if not hospital.has_core_medical_staff():
		citizen.debug_log_once_per_day(
			"health_no_medical_staff_%d" % hospital.get_instance_id(),
			"Health treatment blocked at %s: no Doctor/Nurse." % hospital.get_display_name()
		)
		return false
	if not hospital.can_accept_patient(citizen):
		citizen.debug_log_once_per_day(
			"health_hospital_full_%d" % hospital.get_instance_id(),
			"Health treatment blocked at %s: patient capacity full." % hospital.get_display_name()
		)
		return false

	var state := _build_state(world, citizen, hospital)
	var goal := {"health_treated": true}
	var actions := _build_actions()
	var plan := GoapPlannerScript.plan(state, goal, actions, 4)
	if plan.is_empty():
		return false
	return _execute_first_action(plan[0], world, citizen, hospital)

func _build_state(world, citizen, hospital) -> Dictionary:
	return {
		"has_hospital": hospital != null,
		"at_hospital": hospital != null and citizen.current_location == hospital,
		"hospital_operational": hospital != null and hospital.is_open(world.time.get_hour()) and hospital.has_core_medical_staff(),
		"hospital_has_capacity": hospital != null and hospital.can_accept_patient(citizen),
		"needs_treatment": citizen.needs.health < _treatment_threshold,
		"health_treated": false,
	}

func _build_actions() -> Array:
	return [
		GoapActionScript.new(
			"go_hospital",
			_go_hospital_cost,
			{"has_hospital": true, "at_hospital": false, "hospital_operational": true, "hospital_has_capacity": true},
			{"at_hospital": true}
		),
		GoapActionScript.new(
			"treat",
			_treatment_cost,
			{"at_hospital": true, "hospital_operational": true, "hospital_has_capacity": true, "needs_treatment": true},
			{"health_treated": true}
		),
	]

func _execute_first_action(action, world, citizen, hospital) -> bool:
	if action == null or hospital == null:
		return false
	match action.action_id:
		"go_hospital":
			if _should_take_taxi_to_hospital(world, citizen, hospital):
				citizen.start_action(TaxiToBuildingActionScript.new(hospital, HOSPITAL_DEPOT_MARKER_NAME), world)
				return true
			citizen.start_action(GoToBuildingActionScript.new(hospital, _travel_minutes), world)
			return true
		"treat":
			var emergency: bool = citizen.needs != null and citizen.needs.health < _emergency_threshold
			citizen.start_action(TreatAtHospitalActionScript.new(hospital, emergency), world)
			return true
		_:
			return false

func _select_hospital(citizen):
	if citizen == null:
		return null
	if citizen.current_location is Building and citizen.current_location.building_type == Building.BuildingType.HOSPITAL:
		return citizen.current_location
	if citizen.has_method("_find_nearest_hospital"):
		return citizen._find_nearest_hospital(citizen.global_position, true)
	return null

func _should_take_taxi_to_hospital(world, citizen, hospital) -> bool:
	if world == null or citizen == null or hospital == null:
		return false
	if citizen.current_location == hospital:
		return false
	if citizen.needs == null or citizen.needs.health > _taxi_threshold:
		return false
	if citizen.has_method("is_inside_vehicle") and citizen.is_inside_vehicle():
		return false
	if not world.has_method("get_taxi_service"):
		return false
	var taxi_service = world.get_taxi_service()
	if taxi_service == null:
		return false
	if taxi_service.has_method("get_state"):
		var state := str(taxi_service.get_state())
		if state != "idle" and state != "return_to_depot":
			return false
	return true
