extends RefCounted
class_name CitizenPlanner

const CitizenHungerGoapScript = preload("res://Simulation/GOAP/CitizenHungerGoap.gd")
const CitizenFunGoapScript = preload("res://Simulation/GOAP/CitizenFunGoap.gd")
const CitizenEnergyGoapScript = preload("res://Simulation/GOAP/CitizenEnergyGoap.gd")
const CitizenWorkGoapScript = preload("res://Simulation/GOAP/CitizenWorkGoap.gd")
const GoToBuildingActionScript = preload("res://Actions/GoToBuildingAction.gd")
const RelaxAtHomeActionScript = preload("res://Actions/RelaxAtHomeAction.gd")
const SleepActionScript = preload("res://Actions/SleepAction.gd")

var _hunger_goap = CitizenHungerGoapScript.new()
var _fun_goap = CitizenFunGoapScript.new()
var _energy_goap = CitizenEnergyGoapScript.new()
var _work_goap = CitizenWorkGoapScript.new()

func plan_next_action(world, citizen) -> bool:
	if world == null or citizen == null:
		return false

	var hour: int = world.time.get_hour()
	var is_night: bool = hour >= 22 or hour < 6

	if citizen.needs.hunger >= citizen.hunger_threshold:
		if _hunger_goap.try_plan(world, citizen):
			return true

	if citizen.needs.energy <= citizen.low_energy_threshold:
		if _energy_goap.try_plan(world, citizen):
			return true

	if _work_goap.try_plan(world, citizen):
		return true

	if citizen.needs.fun < citizen.needs.TARGET_FUN_MIN and not is_night:
		if _fun_goap.try_plan(world, citizen):
			return true

	return _fallback_idle(world, citizen, is_night)

func _fallback_idle(world, citizen, is_night: bool) -> bool:
	if citizen.home == null:
		return false

	if is_night and citizen.needs.energy < citizen.needs.TARGET_ENERGY_MIN:
		if citizen.current_location != citizen.home:
			citizen.start_action(GoToBuildingActionScript.new(citizen.home, 20), world)
			return true
		citizen.start_action(SleepActionScript.new(), world)
		return true

	if citizen.current_location != citizen.home:
		citizen.start_action(GoToBuildingActionScript.new(citizen.home, 20), world)
		return true
	citizen.start_action(RelaxAtHomeActionScript.new(), world)
	return true