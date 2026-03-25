extends RefCounted
class_name CitizenPlanner

const BalanceConfig = preload("res://Simulation/Config/BalanceConfig.gd")
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

var _hunger_goap = CitizenHungerGoapScript.new()
var _fun_goap = CitizenFunGoapScript.new()
var _energy_goap = CitizenEnergyGoapScript.new()
var _work_goap = CitizenWorkGoapScript.new()
var _education_goap = CitizenEducationGoapScript.new()

var _critical_hunger: float = BalanceConfig.get_float("planner.critical_hunger", 80.0)
var _critical_energy: float = BalanceConfig.get_float("planner.critical_energy", 10.0)
var _low_health: float = BalanceConfig.get_float("planner.low_health", 35.0)
var _critical_health: float = BalanceConfig.get_float("planner.critical_health", 20.0)
var _work_commute_buffer_min: int = BalanceConfig.get_int("planner.work_commute_buffer_min", 30)
var _hunger_priority_scale: float = BalanceConfig.get_float("planner.hunger_priority_scale", 40.0)
var _energy_priority_scale: float = BalanceConfig.get_float("planner.energy_priority_scale", 40.0)
var _fun_priority_scale: float = BalanceConfig.get_float("planner.fun_priority_scale", 35.0)
var _goal_priority_hunger_weight: float = BalanceConfig.get_float("planner.goal_priority_hunger_weight", 1.25)
var _goal_priority_energy_weight: float = BalanceConfig.get_float("planner.goal_priority_energy_weight", 1.1)
var _goal_priority_education_weight: float = BalanceConfig.get_float("planner.goal_priority_education_weight", 0.95)
var _goal_priority_work_weight: float = BalanceConfig.get_float("planner.goal_priority_work_weight", 0.9)
var _goal_priority_fun_weight: float = BalanceConfig.get_float("planner.goal_priority_fun_weight", 0.65)
var _work_need_base_priority: float = BalanceConfig.get_float("planner.work_need_base_priority", 0.45)
var _work_need_remaining_weight: float = BalanceConfig.get_float("planner.work_need_remaining_weight", 0.55)
var _low_health_hunger_alert_threshold: float = BalanceConfig.get_float("planner.low_health_hunger_alert_threshold", 65.0)
var _low_health_energy_alert_threshold: float = BalanceConfig.get_float("planner.low_health_energy_alert_threshold", 35.0)
var _emergency_energy_threshold: float = BalanceConfig.get_float("planner.emergency_energy_threshold", 8.0)
var _fun_block_hunger_threshold: float = BalanceConfig.get_float("planner.fun_block_hunger_threshold", 60.0)
var _fun_block_energy_threshold: float = BalanceConfig.get_float("planner.fun_block_energy_threshold", 25.0)
var _relax_home_min_energy_threshold: float = BalanceConfig.get_float("planner.relax_home_min_energy_threshold", 20.0)
var _work_fit_hunger_threshold: float = BalanceConfig.get_float("planner.work_fit_hunger_threshold", 75.0)
var _fallback_home_travel_minutes: int = BalanceConfig.get_int("planner.fallback_home_travel_minutes", 20)
var _survival_home_travel_minutes: int = BalanceConfig.get_int("planner.survival_home_travel_minutes", 20)
var _survival_restaurant_travel_minutes: int = BalanceConfig.get_int("planner.survival_restaurant_travel_minutes", 15)
var _survival_supermarket_travel_minutes: int = BalanceConfig.get_int("planner.survival_supermarket_travel_minutes", 18)
var _work_travel_minutes: int = BalanceConfig.get_int("planner.work_travel_minutes", 20)
var _night_start_hour: int = BalanceConfig.get_int("schedule.night_start_hour", 22)
var _day_start_hour: int = BalanceConfig.get_int("schedule.day_start_hour", 6)

func plan_next_action(world, citizen) -> bool:
	if world == null or citizen == null:
		return false

	if _try_survival_override(world, citizen):
		return true

	if _try_work_schedule(world, citizen):
		return true

	var candidates: Array = _build_goal_candidates(world, citizen)
	candidates.sort_custom(_sort_goal_candidates)

	for candidate in candidates:
		var score: float = float(candidate.get("priority", 0.0))
		if score <= 0.01:
			continue

		var goal_id: String = str(candidate.get("id", ""))
		if _try_goal(goal_id, world, citizen):
			return true

	var hour: int = world.time.get_hour()
	return _fallback_idle(world, citizen, _is_night(hour))

func _build_goal_candidates(world, citizen) -> Array:
	var hour: int = world.time.get_hour()
	var minute: int = world.time.get_minute()
	var now_total: int = hour * 60 + minute
	var weekend: bool = world.time.is_weekend()
	var is_night: bool = _is_night(hour)
	var low_health: bool = citizen.needs.health <= _low_health

	var hunger_priority_scale: float = maxf(_hunger_priority_scale, 0.001)
	var energy_priority_scale: float = maxf(_energy_priority_scale, 0.001)
	var fun_priority_scale: float = maxf(_fun_priority_scale, 0.001)

	var hunger_deficit: float = clamp((citizen.needs.hunger - citizen.hunger_threshold) / hunger_priority_scale, 0.0, 1.0)
	if citizen.needs.hunger >= _critical_hunger:
		hunger_deficit = maxf(hunger_deficit, 1.0)
	if low_health and citizen.needs.hunger >= _low_health_hunger_alert_threshold:
		hunger_deficit = maxf(hunger_deficit, 1.15)

	var energy_deficit: float = clamp((citizen.low_energy_threshold - citizen.needs.energy) / energy_priority_scale, 0.0, 1.0)
	if citizen.needs.energy <= _emergency_energy_threshold:
		energy_deficit = maxf(energy_deficit, 1.0)
	if low_health and citizen.needs.energy <= _low_health_energy_alert_threshold:
		energy_deficit = maxf(energy_deficit, 1.05)

	var fun_deficit: float = clamp((citizen.needs.TARGET_FUN_MIN - citizen.needs.fun) / fun_priority_scale, 0.0, 1.0)
	if is_night:
		fun_deficit *= 0.3
	if citizen.needs.hunger >= _fun_block_hunger_threshold or citizen.needs.energy <= _fun_block_energy_threshold or low_health:
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
			work_need = clamp(_work_need_base_priority + ratio_left * _work_need_remaining_weight, 0.0, 1.0)

	return [
		{"id": "hunger", "priority": hunger_deficit * _goal_priority_hunger_weight},
		{"id": "energy", "priority": energy_deficit * _goal_priority_energy_weight},
		{"id": "education", "priority": education_need * _goal_priority_education_weight},
		{"id": "work", "priority": work_need * _goal_priority_work_weight},
		{"id": "fun", "priority": fun_deficit * _goal_priority_fun_weight},
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
			citizen.start_action(GoToBuildingActionScript.new(citizen.home, _fallback_home_travel_minutes), world)
			return true
		citizen.start_action(SleepActionScript.new(), world)
		return true

	if citizen.current_location != citizen.home:
		citizen.start_action(GoToBuildingActionScript.new(citizen.home, _fallback_home_travel_minutes), world)
		return true
	citizen.start_action(RelaxAtHomeActionScript.new(), world)
	return true

func _try_survival_override(world, citizen) -> bool:
	var critical_hunger: bool = citizen.needs.hunger >= _critical_hunger
	var critical_energy: bool = citizen.needs.energy <= _critical_energy
	var critical_health: bool = citizen.needs.health <= _critical_health

	if not critical_hunger and not critical_energy and not critical_health:
		return false

	if critical_hunger:
		if citizen.current_location == citizen.home and citizen.home_food_stock > 0:
			citizen.start_action(EatAtHomeActionScript.new(), world)
			return true

		if citizen.home_food_stock > 0 and citizen.home != null and citizen.current_location != citizen.home:
			citizen.start_action(GoToBuildingActionScript.new(citizen.home, _survival_home_travel_minutes), world)
			return true

		if _can_eat_at_restaurant(world, citizen):
			if citizen.current_location == citizen.favorite_restaurant:
				citizen.start_action(EatAtRestaurantActionScript.new(citizen.favorite_restaurant), world)
			else:
				citizen.start_action(GoToBuildingActionScript.new(citizen.favorite_restaurant, _survival_restaurant_travel_minutes), world)
			return true

		if _can_buy_groceries(world, citizen):
			if citizen.current_location == citizen.favorite_supermarket:
				citizen.start_action(BuyGroceriesActionScript.new(citizen.favorite_supermarket), world)
			else:
				citizen.start_action(GoToBuildingActionScript.new(citizen.favorite_supermarket, _survival_supermarket_travel_minutes), world)
			return true

	if citizen.home == null:
		return false

	if citizen.current_location != citizen.home:
		citizen.start_action(GoToBuildingActionScript.new(citizen.home, _survival_home_travel_minutes), world)
		return true

	if citizen.needs.fun < citizen.needs.TARGET_FUN_MIN \
		and citizen.needs.hunger < citizen.hunger_threshold \
		and citizen.needs.energy >= _relax_home_min_energy_threshold:
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
	if citizen.needs.health <= _low_health:
		return false

	var shift_minutes: int = int(citizen.job.shift_hours * 60)
	var remaining_work: int = maxi(0, shift_minutes - citizen.work_minutes_today)
	if remaining_work <= 0:
		return false

	var now_total: int = world.time.get_hour() * 60 + world.time.get_minute()
	var work_start: int = citizen.job.start_hour * 60 + citizen.schedule_offset
	var work_end: int = work_start + shift_minutes
	var in_commute_window: bool = now_total >= maxi(work_start - _work_commute_buffer_min, 0) and now_total < work_start
	var in_work_window: bool = now_total >= work_start and now_total < work_end
	if not in_commute_window and not in_work_window:
		return false

	var work_fit: bool = citizen.needs.health > _low_health \
		and citizen.needs.energy > citizen.low_energy_threshold \
		and citizen.needs.hunger < _work_fit_hunger_threshold
	if not work_fit:
		var reason := "unknown blocker"
		if citizen.needs.health <= _low_health:
			reason = "health %.0f <= %.0f" % [citizen.needs.health, _low_health]
		elif citizen.needs.energy <= citizen.low_energy_threshold:
			reason = "energy %.0f <= %.0f" % [citizen.needs.energy, citizen.low_energy_threshold]
		elif citizen.needs.hunger >= _work_fit_hunger_threshold:
			reason = "hunger %.0f >= %.0f" % [citizen.needs.hunger, _work_fit_hunger_threshold]
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

	citizen.start_action(GoToBuildingActionScript.new(citizen.job.workplace, _work_travel_minutes), world)
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

func _is_night(hour: int) -> bool:
	return hour >= _night_start_hour or hour < _day_start_hour
