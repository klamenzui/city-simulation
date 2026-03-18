extends RefCounted
class_name CitizenPlanner

const CitizenHungerGoapScript = preload("res://Simulation/GOAP/CitizenHungerGoap.gd")
const CitizenFunGoapScript = preload("res://Simulation/GOAP/CitizenFunGoap.gd")
const CitizenEnergyGoapScript = preload("res://Simulation/GOAP/CitizenEnergyGoap.gd")
const CitizenWorkGoapScript = preload("res://Simulation/GOAP/CitizenWorkGoap.gd")
const CitizenEducationGoapScript = preload("res://Simulation/GOAP/CitizenEducationGoap.gd")
const BuyGroceriesActionScript = preload("res://Actions/BuyGroceriesAction.gd")
const EatAtHomeActionScript = preload("res://Actions/EatAtHomeAction.gd")
const EatAtRestaurantActionScript = preload("res://Actions/EatAtRestaurantAction.gd")
const GoToBuildingActionScript = preload("res://Actions/GoToBuildingAction.gd")
const RelaxAtHomeActionScript = preload("res://Actions/RelaxAtHomeAction.gd")
const SleepActionScript = preload("res://Actions/SleepAction.gd")
const WorkActionScript = preload("res://Actions/WorkAction.gd")

const CRITICAL_HUNGER := 80.0
const CRITICAL_ENERGY := 10.0
const LOW_HEALTH := 35.0
const CRITICAL_HEALTH := 20.0
const WORK_COMMUTE_BUFFER_MIN := 30

var _hunger_goap = CitizenHungerGoapScript.new()
var _fun_goap = CitizenFunGoapScript.new()
var _energy_goap = CitizenEnergyGoapScript.new()
var _work_goap = CitizenWorkGoapScript.new()
var _education_goap = CitizenEducationGoapScript.new()

func plan_next_action(world, citizen) -> bool:
	if world == null or citizen == null:
		return false

	if _try_survival_override(world, citizen):
		return true

	if _try_work_schedule(world, citizen):
		return true

	var candidates = _build_goal_candidates(world, citizen)
	candidates.sort_custom(_sort_goal_candidates)

	for candidate in candidates:
		var score: float = float(candidate.get("priority", 0.0))
		if score <= 0.01:
			continue

		var goal_id: String = str(candidate.get("id", ""))
		if _try_goal(goal_id, world, citizen):
			return true

	var hour: int = world.time.get_hour()
	var is_night: bool = hour >= 22 or hour < 6
	return _fallback_idle(world, citizen, is_night)

func _build_goal_candidates(world, citizen) -> Array:
	var hour: int = world.time.get_hour()
	var minute: int = world.time.get_minute()
	var now_total: int = hour * 60 + minute
	var weekend: bool = world.time.is_weekend()
	var is_night: bool = hour >= 22 or hour < 6
	var low_health: bool = citizen.needs.health <= LOW_HEALTH

	var hunger_deficit: float = clamp((citizen.needs.hunger - citizen.hunger_threshold) / 40.0, 0.0, 1.0)
	if citizen.needs.hunger >= CRITICAL_HUNGER:
		hunger_deficit = maxf(hunger_deficit, 1.0)
	if low_health and citizen.needs.hunger >= 65.0:
		hunger_deficit = maxf(hunger_deficit, 1.15)

	var energy_deficit: float = clamp((citizen.low_energy_threshold - citizen.needs.energy) / 40.0, 0.0, 1.0)
	if citizen.needs.energy <= 8.0:
		energy_deficit = maxf(energy_deficit, 1.0)
	if low_health and citizen.needs.energy <= 35.0:
		energy_deficit = maxf(energy_deficit, 1.05)

	var fun_deficit: float = clamp((citizen.needs.TARGET_FUN_MIN - citizen.needs.fun) / 35.0, 0.0, 1.0)
	if is_night:
		fun_deficit *= 0.3
	if citizen.needs.hunger >= 60.0 or citizen.needs.energy <= 25.0 or low_health:
		fun_deficit = 0.0

	var education_need: float = 0.0
	if citizen.job != null and not citizen.job.meets_requirements(citizen) and not is_night and not low_health:
		education_need = 1.0

	var work_need: float = 0.0
	if citizen.job != null and citizen.job.workplace != null and citizen.job.meets_requirements(citizen) and not weekend and not low_health:
		var shift_minutes: int = int(citizen.job.shift_hours * 60)
		var work_start: int = citizen.job.start_hour * 60 + citizen.schedule_offset
		var work_end: int = work_start + shift_minutes
		var in_work_window: bool = now_total >= work_start and now_total < work_end
		var remaining_work: int = maxi(0, shift_minutes - citizen.work_minutes_today)
		if in_work_window and remaining_work > 0:
			var ratio_left: float = float(remaining_work) / float(maxi(shift_minutes, 1))
			work_need = clamp(0.45 + ratio_left * 0.55, 0.0, 1.0)

	return [
		{"id": "hunger", "priority": hunger_deficit * 1.25},
		{"id": "energy", "priority": energy_deficit * 1.1},
		{"id": "education", "priority": education_need * 0.95},
		{"id": "work", "priority": work_need * 0.9},
		{"id": "fun", "priority": fun_deficit * 0.65},
	]

func _sort_goal_candidates(a, b) -> bool:
	return float(a.get("priority", 0.0)) > float(b.get("priority", 0.0))

func _try_goal(goal_id: String, world, citizen) -> bool:
	match goal_id:
		"hunger":
			return _hunger_goap.try_plan(world, citizen)
		"energy":
			return _energy_goap.try_plan(world, citizen)
		"education":
			return _education_goap.try_plan(world, citizen)
		"work":
			return _work_goap.try_plan(world, citizen)
		"fun":
			return _fun_goap.try_plan(world, citizen)
		_:
			return false

func _fallback_idle(world, citizen, is_night: bool) -> bool:
	if citizen.home == null:
		return false

	if _try_survival_override(world, citizen):
		return true

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

func _try_survival_override(world, citizen) -> bool:
	var critical_hunger: bool = citizen.needs.hunger >= CRITICAL_HUNGER
	var critical_energy: bool = citizen.needs.energy <= CRITICAL_ENERGY
	var critical_health: bool = citizen.needs.health <= CRITICAL_HEALTH

	if not critical_hunger and not critical_energy and not critical_health:
		return false

	if critical_hunger:
		if citizen.current_location == citizen.home and citizen.home_food_stock > 0:
			citizen.start_action(EatAtHomeActionScript.new(), world)
			return true

		if citizen.home_food_stock > 0 and citizen.home != null and citizen.current_location != citizen.home:
			citizen.start_action(GoToBuildingActionScript.new(citizen.home, 20), world)
			return true

		if _can_eat_at_restaurant(world, citizen):
			if citizen.current_location == citizen.favorite_restaurant:
				citizen.start_action(EatAtRestaurantActionScript.new(citizen.favorite_restaurant), world)
			else:
				citizen.start_action(GoToBuildingActionScript.new(citizen.favorite_restaurant, 15), world)
			return true

		if _can_buy_groceries(world, citizen):
			if citizen.current_location == citizen.favorite_supermarket:
				citizen.start_action(BuyGroceriesActionScript.new(citizen.favorite_supermarket), world)
			else:
				citizen.start_action(GoToBuildingActionScript.new(citizen.favorite_supermarket, 18), world)
			return true

	if citizen.home == null:
		return false

	if citizen.current_location != citizen.home:
		citizen.start_action(GoToBuildingActionScript.new(citizen.home, 20), world)
		return true

	if citizen.needs.fun < citizen.needs.TARGET_FUN_MIN and citizen.needs.hunger < citizen.hunger_threshold and citizen.needs.energy >= 20.0:
		citizen.start_action(RelaxAtHomeActionScript.new(), world)
		return true

	if citizen.needs.energy < citizen.needs.TARGET_ENERGY_MIN or critical_energy:
		citizen.start_action(SleepActionScript.new(), world)
		return true

	citizen.start_action(RelaxAtHomeActionScript.new(), world)
	return true

func _try_work_schedule(world, citizen) -> bool:
	if citizen == null or citizen.job == null or citizen.job.workplace == null:
		return false
	if not citizen.job.meets_requirements(citizen):
		return false
	if world.time.is_weekend():
		return false
	if citizen.needs.health <= LOW_HEALTH:
		return false

	var shift_minutes: int = int(citizen.job.shift_hours * 60)
	var remaining_work: int = maxi(0, shift_minutes - citizen.work_minutes_today)
	if remaining_work <= 0:
		return false

	var now_total: int = world.time.get_hour() * 60 + world.time.get_minute()
	var work_start: int = citizen.job.start_hour * 60 + citizen.schedule_offset
	var work_end: int = work_start + shift_minutes
	var in_commute_window: bool = now_total >= maxi(work_start - WORK_COMMUTE_BUFFER_MIN, 0) and now_total < work_start
	var in_work_window: bool = now_total >= work_start and now_total < work_end
	if not in_commute_window and not in_work_window:
		return false

	var work_fit: bool = citizen.needs.health > LOW_HEALTH \
		and citizen.needs.energy > citizen.low_energy_threshold \
		and citizen.needs.hunger < 75.0
	if not work_fit:
		var reason := "unknown blocker"
		if citizen.needs.health <= LOW_HEALTH:
			reason = "health %.0f <= %d" % [citizen.needs.health, LOW_HEALTH]
		elif citizen.needs.energy <= citizen.low_energy_threshold:
			reason = "energy %.0f <= %.0f" % [citizen.needs.energy, citizen.low_energy_threshold]
		elif citizen.needs.hunger >= 75.0:
			reason = "hunger %.0f >= 75" % citizen.needs.hunger
		citizen.debug_log_once_per_day(
			"work_blocked_%s" % citizen.job.title,
			"Skipping work window for %s: %s. %s" % [
				citizen.job.title,
				reason,
				citizen.get_job_debug_summary()
			]
		)
		return false

	if citizen.current_location == citizen.job.workplace:
		if in_work_window:
			citizen.start_action(WorkActionScript.new(citizen.job), world)
		return true

	citizen.start_action(GoToBuildingActionScript.new(citizen.job.workplace, 20), world)
	return true

func _can_eat_at_restaurant(world, citizen) -> bool:
	if citizen.favorite_restaurant == null:
		return false
	if not citizen.favorite_restaurant.is_open(world.time.get_hour()):
		return false
	if not citizen.favorite_restaurant.can_sell_item("meal", 1):
		return false
	return citizen.can_afford_restaurant(world)

func _can_buy_groceries(world, citizen) -> bool:
	if citizen.favorite_supermarket == null:
		return false
	if not citizen.favorite_supermarket.is_open(world.time.get_hour()):
		return false
	if not citizen.favorite_supermarket.can_sell_item("grocery_bundle", 1):
		return false
	return citizen.can_afford_groceries(world)
