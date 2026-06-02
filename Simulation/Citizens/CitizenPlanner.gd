extends RefCounted
class_name CitizenPlanner

const BalanceConfig = preload("res://Simulation/Config/BalanceConfig.gd")
const CitizenHungerGoapScript = preload("res://Simulation/GOAP/CitizenHungerGoap.gd")
const CitizenFunGoapScript = preload("res://Simulation/GOAP/CitizenFunGoap.gd")
const CitizenEnergyGoapScript = preload("res://Simulation/GOAP/CitizenEnergyGoap.gd")
const CitizenWorkGoapScript = preload("res://Simulation/GOAP/CitizenWorkGoap.gd")
const CitizenEducationGoapScript = preload("res://Simulation/GOAP/CitizenEducationGoap.gd")
const CitizenSocialGoapScript = preload("res://Simulation/GOAP/CitizenSocialGoap.gd")
const CitizenHealthGoapScript = preload("res://Simulation/GOAP/CitizenHealthGoap.gd")
const CitizenEmotionScript = preload("res://Simulation/Citizens/CitizenEmotion.gd")
const CitizenWorkRulesScript = preload("res://Simulation/Citizens/CitizenWorkRules.gd")
const BuyGroceriesActionScript = preload("res://Actions/BuyGroceriesAction.gd")
const EatAtHomeActionScript = preload("res://Actions/EatAtHomeAction.gd")
const EatAtRestaurantActionScript = preload("res://Actions/EatAtRestaurantAction.gd")
const EatAtCafeActionScript = preload("res://Actions/EatAtCafeAction.gd")
const GoToBuildingActionScript = preload("res://Actions/GoToBuildingAction.gd")
const RelaxAtHomeActionScript = preload("res://Actions/RelaxAtHomeAction.gd")
const SleepActionScript = preload("res://Actions/SleepAction.gd")
const WorkActionScript = preload("res://Actions/WorkAction.gd")

const FOOD_ROUTE_HOME := "home"
const FOOD_ROUTE_RESTAURANT := "restaurant"
const FOOD_ROUTE_CAFE := "cafe"
const FOOD_ROUTE_SUPERMARKET := "supermarket"

var _hunger_goap = CitizenHungerGoapScript.new()
var _fun_goap = CitizenFunGoapScript.new()
var _energy_goap = CitizenEnergyGoapScript.new()
var _work_goap = CitizenWorkGoapScript.new()
var _education_goap = CitizenEducationGoapScript.new()
var _social_goap = CitizenSocialGoapScript.new()
var _health_goap = CitizenHealthGoapScript.new()

var _critical_hunger: float = BalanceConfig.get_float("planner.critical_hunger", 80.0)
var _critical_energy: float = BalanceConfig.get_float("planner.critical_energy", 10.0)
var _low_health: float = BalanceConfig.get_float("planner.low_health", 35.0)
var _critical_health: float = BalanceConfig.get_float("planner.critical_health", 20.0)
var _hunger_priority_scale: float = BalanceConfig.get_float("planner.hunger_priority_scale", 40.0)
var _energy_priority_scale: float = BalanceConfig.get_float("planner.energy_priority_scale", 40.0)
var _fun_priority_scale: float = BalanceConfig.get_float("planner.fun_priority_scale", 35.0)
var _social_priority_scale: float = BalanceConfig.get_float("planner.social_priority_scale", 35.0)
var _goal_priority_hunger_weight: float = BalanceConfig.get_float("planner.goal_priority_hunger_weight", 1.25)
var _goal_priority_energy_weight: float = BalanceConfig.get_float("planner.goal_priority_energy_weight", 1.1)
var _goal_priority_education_weight: float = BalanceConfig.get_float("planner.goal_priority_education_weight", 0.95)
var _goal_priority_work_weight: float = BalanceConfig.get_float("planner.goal_priority_work_weight", 0.9)
var _goal_priority_fun_weight: float = BalanceConfig.get_float("planner.goal_priority_fun_weight", 0.65)
var _goal_priority_social_weight: float = BalanceConfig.get_float("planner.goal_priority_social_weight", 0.6)
var _goal_priority_health_weight: float = BalanceConfig.get_float("planner.goal_priority_health_weight", 1.6)
var _goal_priority_food_reserve_weight: float = BalanceConfig.get_float("planner.goal_priority_food_reserve_weight", 0.72)
var _min_home_food_reserve: int = BalanceConfig.get_int("planner.min_home_food_reserve", 2)
var _health_priority_scale: float = BalanceConfig.get_float("planner.health.priority_scale", 20.0)
var _health_visit_threshold: float = BalanceConfig.get_float("planner.health.visit_threshold", 20.0)
var _health_emergency_threshold: float = BalanceConfig.get_float("planner.health.emergency_threshold", 5.0)
var _work_need_base_priority: float = BalanceConfig.get_float("planner.work_need_base_priority", 0.45)
var _work_need_remaining_weight: float = BalanceConfig.get_float("planner.work_need_remaining_weight", 0.55)
var _low_health_hunger_alert_threshold: float = BalanceConfig.get_float("planner.low_health_hunger_alert_threshold", 65.0)
var _low_health_energy_alert_threshold: float = BalanceConfig.get_float("planner.low_health_energy_alert_threshold", 35.0)
var _emergency_energy_threshold: float = BalanceConfig.get_float("planner.emergency_energy_threshold", 8.0)
var _fun_block_hunger_threshold: float = BalanceConfig.get_float("planner.fun_block_hunger_threshold", 60.0)
var _fun_block_energy_threshold: float = BalanceConfig.get_float("planner.fun_block_energy_threshold", 25.0)
var _relax_home_min_energy_threshold: float = BalanceConfig.get_float("planner.relax_home_min_energy_threshold", 20.0)
var _fallback_home_travel_minutes: int = BalanceConfig.get_int("planner.fallback_home_travel_minutes", 20)
var _survival_home_travel_minutes: int = BalanceConfig.get_int("planner.survival_home_travel_minutes", 20)
var _survival_restaurant_travel_minutes: int = BalanceConfig.get_int("planner.survival_restaurant_travel_minutes", 15)
var _survival_cafe_travel_minutes: int = BalanceConfig.get_int("planner.survival_cafe_travel_minutes", 12)
var _survival_supermarket_travel_minutes: int = BalanceConfig.get_int("planner.survival_supermarket_travel_minutes", 18)
var _service_arrival_buffer_minutes: int = BalanceConfig.get_int("planner.service_arrival_buffer_minutes", 5)
var _night_start_hour: int = BalanceConfig.get_int("schedule.night_start_hour", 22)
var _day_start_hour: int = BalanceConfig.get_int("schedule.day_start_hour", 6)
var _personality_enabled: bool = BalanceConfig.get_bool("planner.personality.enabled", true)
var _pers_work_weight: float = BalanceConfig.get_float("planner.personality.work_motivation_weight", 1.0)
var _pers_work_min: float = BalanceConfig.get_float("planner.personality.work_motivation_min", 0.5)
var _pers_work_max: float = BalanceConfig.get_float("planner.personality.work_motivation_max", 1.5)
var _pers_fun_mid: float = BalanceConfig.get_float("planner.personality.fun_interest_midpoint", 0.35)
var _pers_fun_scale: float = BalanceConfig.get_float("planner.personality.fun_interest_scale", 0.6)
var _pers_fun_min: float = BalanceConfig.get_float("planner.personality.fun_personality_min", 0.7)
var _pers_fun_max: float = BalanceConfig.get_float("planner.personality.fun_personality_max", 1.3)
var _pers_social_mid: float = BalanceConfig.get_float("planner.personality.sociability_midpoint", 0.5)
var _pers_social_scale: float = BalanceConfig.get_float("planner.personality.sociability_scale", 0.6)
var _pers_social_min: float = BalanceConfig.get_float("planner.personality.social_personality_min", 0.7)
var _pers_social_max: float = BalanceConfig.get_float("planner.personality.social_personality_max", 1.3)
var _goal_cooldowns_enabled: bool = BalanceConfig.get_bool("planner.goal_cooldowns.enabled", true)
var _goal_cooldown_minutes: Dictionary = {
	"hunger": BalanceConfig.get_int("planner.goal_cooldowns.hunger", 0),
	"energy": BalanceConfig.get_int("planner.goal_cooldowns.energy", 0),
	"education": BalanceConfig.get_int("planner.goal_cooldowns.education", 0),
	"health": BalanceConfig.get_int("planner.goal_cooldowns.health", 0),
	"work": BalanceConfig.get_int("planner.goal_cooldowns.work", 0),
	"fun": BalanceConfig.get_int("planner.goal_cooldowns.fun", 0),
	"social": BalanceConfig.get_int("planner.goal_cooldowns.social", 0),
}
var _goal_cooldown_until: Dictionary = {}
var _emotion_enabled: bool = BalanceConfig.get_bool("planner.emotion.enabled", true)
var _emotion_cfg: Dictionary = BalanceConfig.get_section("planner.emotion")

func plan_next_action(world, citizen) -> bool:
	if world == null or citizen == null:
		return false

	if _try_survival_override(world, citizen):
		return true

	if _try_work_schedule(world, citizen):
		return true

	var candidates: Array = _build_goal_candidates(world, citizen)
	candidates.sort_custom(_sort_goal_candidates)

	var sim_now: int = _sim_total_minutes(world)
	for candidate in candidates:
		var score: float = float(candidate.get("priority", 0.0))
		if score <= 0.01:
			continue

		var goal_id: String = str(candidate.get("id", ""))
		if _is_goal_on_cooldown(citizen, goal_id, sim_now):
			continue
		if _try_goal(goal_id, world, citizen):
			if not _should_defer_goal_cooldown(citizen):
				_set_goal_cooldown(citizen, goal_id, sim_now)
			return true

	var hour: int = world.time.get_hour()
	return _fallback_idle(world, citizen, _is_night(hour))

func _build_goal_candidates(world, citizen) -> Array:
	var hour: int = world.time.get_hour()
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

	var social_priority_scale: float = maxf(_social_priority_scale, 0.001)
	var social_deficit: float = clamp((citizen.needs.TARGET_SOCIAL_MIN - citizen.needs.social) / social_priority_scale, 0.0, 1.0)
	if is_night:
		social_deficit *= 0.3
	if citizen.needs.hunger >= _fun_block_hunger_threshold or citizen.needs.energy <= _fun_block_energy_threshold or low_health:
		social_deficit = 0.0

	var health_deficit: float = clamp((_health_visit_threshold - citizen.needs.health) / maxf(_health_priority_scale, 0.001), 0.0, 1.0)
	if citizen.needs.health < _health_emergency_threshold:
		health_deficit = maxf(health_deficit, 1.25)

	var education_need: float = 0.0
	if citizen.job != null and not citizen.job.meets_requirements(citizen) and not is_night and not low_health:
		education_need = 1.0

	var food_reserve_need: float = 0.0
	if not is_night and not low_health \
			and citizen.needs.hunger < citizen.hunger_threshold \
			and _should_build_food_reserve(world, citizen):
		food_reserve_need = 1.0

	var work_need: float = 0.0
	if not low_health:
		var work_context := CitizenWorkRulesScript.build_context(world, citizen)
		if CitizenWorkRulesScript.is_goal_available(work_context):
			var shift_minutes: int = int(work_context.get("shift_minutes", 0))
			var remaining_work: int = int(work_context.get("remaining_work", 0))
			var ratio_left: float = float(remaining_work) / float(maxi(shift_minutes, 1))
			work_need = clamp(_work_need_base_priority + ratio_left * _work_need_remaining_weight, 0.0, 1.0)

	var work_pers := 1.0
	var fun_pers := 1.0
	var social_pers := 1.0
	if _personality_enabled:
		var wm: float = float(citizen.work_motivation) if "work_motivation" in citizen else 1.0
		work_pers = clampf(wm * _pers_work_weight, _pers_work_min, _pers_work_max)
		var fi: float = float(citizen.fun_interest) if "fun_interest" in citizen else _pers_fun_mid
		fun_pers = clampf(1.0 + (fi - _pers_fun_mid) * _pers_fun_scale, _pers_fun_min, _pers_fun_max)
		var soc: float = float(citizen.sociability) if "sociability" in citizen else _pers_social_mid
		social_pers = clampf(1.0 + (soc - _pers_social_mid) * _pers_social_scale, _pers_social_min, _pers_social_max)

	var social_emo_mult := 1.0
	if _emotion_enabled:
		var is_home: bool = "home" in citizen and "current_location" in citizen \
			and citizen.home != null and citizen.current_location == citizen.home
		var emo: Dictionary = CitizenEmotionScript.compute(
			citizen.needs.hunger, citizen.needs.energy, citizen.needs.social,
			is_home, is_night, _emotion_cfg)
		social_emo_mult = CitizenEmotionScript.social_priority_multiplier(emo, _emotion_cfg)

	return [
		{"id": "health", "priority": health_deficit * _goal_priority_health_weight},
		{"id": "hunger", "priority": hunger_deficit * _goal_priority_hunger_weight},
		{"id": "energy", "priority": energy_deficit * _goal_priority_energy_weight},
		{"id": "education", "priority": education_need * _goal_priority_education_weight},
		{"id": "work", "priority": work_need * _goal_priority_work_weight * work_pers},
		{"id": "food_reserve", "priority": food_reserve_need * _goal_priority_food_reserve_weight},
		{"id": "fun", "priority": fun_deficit * _goal_priority_fun_weight * fun_pers},
		{"id": "social", "priority": social_deficit * _goal_priority_social_weight * social_emo_mult * social_pers},
	]

func _sort_goal_candidates(a, b) -> bool:
	return float(a.get("priority", 0.0)) > float(b.get("priority", 0.0))

func _try_goal(goal_id: String, world, citizen) -> bool:
	match goal_id:
		"health":
			return _health_goap.try_plan(world, citizen)
		"hunger":
			return _hunger_goap.try_plan(world, citizen)
		"energy":
			return _energy_goap.try_plan(world, citizen)
		"education":
			return _education_goap.try_plan(world, citizen)
		"work":
			return _work_goap.try_plan(world, citizen)
		"food_reserve":
			return _try_food_reserve(world, citizen)
		"fun":
			return _fun_goap.try_plan(world, citizen)
		"social":
			return _social_goap.try_plan(world, citizen)
		_:
			return false

func _fallback_idle(world, citizen, is_night: bool) -> bool:
	if citizen.home == null:
		return false

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

func _try_food_reserve(world, citizen) -> bool:
	var supermarket := _select_food_reserve_supermarket(world, citizen)
	if supermarket == null:
		return false
	if citizen.current_location == supermarket:
		citizen.start_action(BuyGroceriesActionScript.new(supermarket), world)
	else:
		citizen.start_action(GoToBuildingActionScript.new(supermarket, _survival_supermarket_travel_minutes), world)
	return true

func _try_survival_override(world, citizen) -> bool:
	var critical_hunger: bool = citizen.needs.hunger >= _critical_hunger
	var critical_energy: bool = citizen.needs.energy <= _critical_energy
	var critical_health: bool = citizen.needs.health <= _critical_health

	if not critical_hunger and not critical_energy and not critical_health:
		return false

	if critical_health and _health_goap.try_plan(world, citizen):
		return true

	if critical_hunger:
		var food_route := _select_nearest_survival_food_route(world, citizen)
		if not food_route.is_empty():
			if _start_survival_food_route(world, citizen, food_route):
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

func _select_nearest_survival_food_route(world, citizen) -> Dictionary:
	var best: Dictionary = {"route": "", "target": null, "distance": INF}
	var from_pos: Vector3 = citizen.global_position
	if citizen.home != null and citizen.get_home_inventory_count("food") > 0:
		_consider_survival_food_route(best, FOOD_ROUTE_HOME, citizen.home, from_pos)

	var survival_restaurant := _select_survival_restaurant(world, citizen)
	if survival_restaurant != null:
		_consider_survival_food_route(best, FOOD_ROUTE_RESTAURANT, survival_restaurant, from_pos)

	var survival_cafe := _select_survival_cafe(world, citizen)
	if survival_cafe != null:
		_consider_survival_food_route(best, FOOD_ROUTE_CAFE, survival_cafe, from_pos)

	var survival_supermarket := _select_survival_supermarket(world, citizen)
	if survival_supermarket != null and citizen.home != null and citizen.get_home_inventory_count("food") <= 0:
		_consider_survival_food_route(best, FOOD_ROUTE_SUPERMARKET, survival_supermarket, from_pos)

	return best if not str(best.get("route", "")).is_empty() else {}


func _start_survival_food_route(world, citizen, food_route: Dictionary) -> bool:
	var route_id := str(food_route.get("route", ""))
	var target = food_route.get("target", null)
	match route_id:
		FOOD_ROUTE_HOME:
			if citizen.current_location == citizen.home:
				citizen.start_action(EatAtHomeActionScript.new(), world)
			else:
				citizen.start_action(GoToBuildingActionScript.new(citizen.home, _survival_home_travel_minutes), world)
			return true
		FOOD_ROUTE_RESTAURANT:
			var restaurant := target as Restaurant
			if restaurant == null:
				return false
			if citizen.current_location == restaurant:
				citizen.start_action(EatAtRestaurantActionScript.new(restaurant), world)
			else:
				citizen.start_action(GoToBuildingActionScript.new(restaurant, _survival_restaurant_travel_minutes), world)
			return true
		FOOD_ROUTE_CAFE:
			var cafe := target as Cafe
			if cafe == null:
				return false
			if citizen.current_location == cafe:
				citizen.start_action(EatAtCafeActionScript.new(cafe), world)
			else:
				citizen.start_action(GoToBuildingActionScript.new(cafe, _survival_cafe_travel_minutes), world)
			return true
		FOOD_ROUTE_SUPERMARKET:
			var supermarket := target as Supermarket
			if supermarket == null:
				return false
			if citizen.current_location == supermarket:
				citizen.start_action(BuyGroceriesActionScript.new(supermarket), world)
			else:
				citizen.start_action(GoToBuildingActionScript.new(supermarket, _survival_supermarket_travel_minutes), world)
			return true
	return false


func _consider_survival_food_route(best: Dictionary, route_id: String, target: Building, from_pos: Vector3) -> void:
	if target == null:
		return
	var distance := _distance_to_food_target(from_pos, target)
	if distance < float(best.get("distance", INF)):
		best["route"] = route_id
		best["target"] = target
		best["distance"] = distance


func _distance_to_food_target(from_pos: Vector3, building: Building) -> float:
	var target_pos := building.get_entrance_pos() if building.has_method("get_entrance_pos") else building.global_position
	var delta := target_pos - from_pos
	delta.y = 0.0
	return delta.length()

func _try_work_schedule(world, citizen) -> bool:
	var work_context := CitizenWorkRulesScript.build_context(world, citizen)
	if not bool(work_context.get("valid_job", false)):
		return false
	if bool(work_context.get("weekend", false)):
		return false
	if int(work_context.get("remaining_work", 0)) <= 0:
		return false
	if not CitizenWorkRulesScript.is_schedule_window(work_context):
		return false
	if bool(work_context.get("sick_skip", false)):
		_log_sick_work_skip(citizen)
		return false
	if not bool(work_context.get("work_fit", false)):
		var reason := str(work_context.get("block_reason", "unknown blocker"))
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
		if bool(work_context.get("in_work_window", false)):
			citizen.start_action(WorkActionScript.new(citizen.job), world)
			return true
		# Already at workplace but shift hasn't started yet (commute buffer).
		# Release control so the planner can find a short activity (eat, relax)
		# rather than freezing with no active action until the window opens.
		return false

	citizen.start_action(GoToBuildingActionScript.new(citizen.job.workplace, CitizenWorkRulesScript.get_travel_minutes()), world)
	return true

func _select_survival_restaurant(world, citizen) -> Restaurant:
	var current := citizen.current_location as Restaurant
	if _can_eat_at_restaurant(world, citizen, current):
		return current

	var nearest: Restaurant = null
	if citizen.has_method("_find_nearest_restaurant_with_meal"):
		nearest = citizen._find_nearest_restaurant_with_meal(citizen.global_position, true)
	if _can_eat_at_restaurant(world, citizen, nearest):
		return nearest

	if _can_eat_at_restaurant(world, citizen, citizen.favorite_restaurant):
		return citizen.favorite_restaurant
	return null

func _select_survival_cafe(world, citizen) -> Cafe:
	var current := citizen.current_location as Cafe
	if _can_eat_at_cafe(world, citizen, current):
		return current

	var nearest: Cafe = null
	if citizen.has_method("_find_nearest_cafe_with_snack"):
		nearest = citizen._find_nearest_cafe_with_snack(citizen.global_position, true)
	if _can_eat_at_cafe(world, citizen, nearest):
		return nearest
	return null

func _select_survival_supermarket(world, citizen) -> Supermarket:
	var current := citizen.current_location as Supermarket
	if _can_buy_groceries(world, citizen, current):
		return current

	var nearest: Supermarket = null
	if citizen.has_method("_find_nearest_supermarket_with_groceries"):
		nearest = citizen._find_nearest_supermarket_with_groceries(citizen.global_position, true)
	if _can_buy_groceries(world, citizen, nearest):
		return nearest

	if _can_buy_groceries(world, citizen, citizen.favorite_supermarket):
		return citizen.favorite_supermarket
	return null

func _should_build_food_reserve(world, citizen) -> bool:
	if _min_home_food_reserve <= 0:
		return false
	if citizen == null or not ("home" in citizen) or citizen.home == null:
		return false
	if _get_home_food_count(citizen) >= _min_home_food_reserve:
		return false
	return _select_food_reserve_supermarket(world, citizen) != null

func _select_food_reserve_supermarket(world, citizen) -> Supermarket:
	return _select_survival_supermarket(world, citizen)

func _get_home_food_count(citizen) -> int:
	if citizen == null:
		return 0
	if citizen.has_method("get_home_inventory_count"):
		return int(citizen.get_home_inventory_count("food"))
	if "home_food_stock" in citizen:
		return int(citizen.home_food_stock)
	return 0

func _can_eat_at_restaurant(world, citizen, restaurant: Restaurant) -> bool:
	if restaurant == null:
		return false
	if not _service_open_for_plan(world, citizen, restaurant, _survival_restaurant_travel_minutes):
		return false
	if not restaurant.can_sell_item("meal", 1):
		return false
	return citizen.can_afford_restaurant_at(restaurant, world)

func _can_eat_at_cafe(world, citizen, cafe: Cafe) -> bool:
	if cafe == null:
		return false
	if not _service_open_for_plan(world, citizen, cafe, _survival_cafe_travel_minutes):
		return false
	if not cafe.can_sell_snack():
		return false
	return citizen.can_afford_cafe_at(cafe, world)

func _can_buy_groceries(world, citizen, supermarket: Supermarket) -> bool:
	if supermarket == null:
		return false
	if not _service_open_for_plan(world, citizen, supermarket, _survival_supermarket_travel_minutes):
		return false
	if not supermarket.can_sell_item("grocery_bundle", 1):
		return false
	return citizen.can_afford_groceries_at(supermarket, world)

func _service_open_for_plan(world, citizen, building: Building, travel_minutes: int) -> bool:
	if world == null or building == null:
		return false
	if citizen != null and "current_location" in citizen and citizen.current_location == building:
		return building.is_open_at_minute(_current_day_minute(world))
	return building.is_open_for_arrival(_current_day_minute(world), travel_minutes, _service_arrival_buffer_minutes)

func _current_day_minute(world) -> int:
	if world == null or not "time" in world or world.time == null:
		return -1
	var t = world.time
	if "minutes_total" in t:
		return int(t.minutes_total)
	if t.has_method("get_hour") and t.has_method("get_minute"):
		return int(t.get_hour()) * 60 + int(t.get_minute())
	if t.has_method("get_hour"):
		return int(t.get_hour()) * 60
	return -1

func _log_sick_work_skip(citizen) -> void:
	citizen.debug_log_once_per_day(
		"work_sick_skip_%s" % citizen.job.title,
		"Skipping work due to sickness: health %.0f. %s" % [
			citizen.needs.health,
			citizen.get_job_debug_summary()
		]
	)

func _is_night(hour: int) -> bool:
	return hour >= _night_start_hour or hour < _day_start_hour

## Per-goal cooldown - suppresses re-selecting a soft goal for N sim-minutes
## after it starts a fulfilling action. Pure travel setup steps are allowed to
## replan at arrival so a GOAP chain can continue. Hard overrides
## (_try_survival_override, _try_work_schedule) run before the candidate loop
## and are NOT affected.
## Keyed by citizen instance id so it stays per-citizen even if the planner
## is ever shared. A goal with 0 configured minutes is never throttled.
func _is_goal_on_cooldown(citizen, goal_id: String, sim_now: int) -> bool:
	if not _goal_cooldowns_enabled or citizen == null:
		return false
	var per: Dictionary = _goal_cooldown_until.get(citizen.get_instance_id(), {})
	return sim_now < int(per.get(goal_id, 0))

func _set_goal_cooldown(citizen, goal_id: String, sim_now: int) -> void:
	if not _goal_cooldowns_enabled or citizen == null:
		return
	var minutes: int = int(_goal_cooldown_minutes.get(goal_id, 0))
	if minutes <= 0:
		return
	var cid: int = citizen.get_instance_id()
	var per: Dictionary = _goal_cooldown_until.get(cid, {})
	per[goal_id] = sim_now + minutes
	_goal_cooldown_until[cid] = per

func _should_defer_goal_cooldown(citizen) -> bool:
	if citizen == null or not "current_action" in citizen:
		return false
	var action = citizen.current_action
	if action == null:
		return false
	return action is GoToBuildingActionScript

static func _sim_total_minutes(world) -> int:
	if world == null or not "time" in world or world.time == null:
		return 0
	var t = world.time
	var day: int = int(t.day) if "day" in t else 1
	var minutes_total: int = 0
	if "minutes_total" in t:
		minutes_total = int(t.minutes_total)
	elif t.has_method("get_hour") and t.has_method("get_minute"):
		minutes_total = t.get_hour() * 60 + t.get_minute()
	return maxi(day - 1, 0) * 24 * 60 + minutes_total
