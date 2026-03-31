extends RefCounted
class_name BalanceConfig

const CONFIG_PATH := "res://config/balance.json"

static var _loaded: bool = false
static var _data: Dictionary = {}

static func reload() -> void:
	_loaded = false
	_data = {}
	_ensure_loaded()

static func get_value(path: String, default_value = null):
	_ensure_loaded()
	if path.strip_edges().is_empty():
		return _data

	var current: Variant = _data
	for part in path.split("."):
		if part.is_empty():
			continue
		if current is Dictionary and current.has(part):
			current = current[part]
			continue
		return default_value
	return current

static func get_section(path: String) -> Dictionary:
	var value: Variant = get_value(path, {})
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}

static func get_int(path: String, default_value: int) -> int:
	return int(get_value(path, default_value))

static func get_float(path: String, default_value: float) -> float:
	return float(get_value(path, default_value))

static func get_bool(path: String, default_value: bool) -> bool:
	return bool(get_value(path, default_value))

static func get_string(path: String, default_value: String = "") -> String:
	return str(get_value(path, default_value))

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_data = _default_data()

	if not FileAccess.file_exists(CONFIG_PATH):
		return

	var file: FileAccess = FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_warning("BalanceConfig: Could not open %s." % CONFIG_PATH)
		return

	var raw_text: String = file.get_as_text()
	var parsed: Variant = JSON.parse_string(raw_text)
	if parsed is Dictionary:
		_deep_merge(_data, parsed as Dictionary)
		return

	push_warning("BalanceConfig: Invalid JSON in %s. Using defaults." % CONFIG_PATH)

static func _deep_merge(base: Dictionary, override: Dictionary) -> void:
	for key in override.keys():
		var override_value: Variant = override[key]
		if base.has(key) and base[key] is Dictionary and override_value is Dictionary:
			_deep_merge(base[key], override_value)
			continue
		base[key] = override_value

static func _default_data() -> Dictionary:
	return {
		"simulation": {
			"initial_citizen_count": 15,
		},
		"world": {
			"minutes_per_tick": 1,
			"tick_interval_sec": 0.5,
			"speed_multiplier": 1.0,
			"city_reserve_start_balance": 18000,
		},
		"economy": {
			"market_account_balance": 250000,
			"commodities": {
				"food": {
					"stock": 900,
					"target_stock": 1200,
					"base_price": 4,
				},
				"clothes": {
					"stock": 480,
					"target_stock": 700,
					"base_price": 7,
				},
				"entertainment": {
					"stock": 2000,
					"target_stock": 2500,
					"base_price": 2,
				},
			},
			"jobs": {
				"wage_per_hour_min": 10,
				"wage_per_hour_max": 26,
				"wage_per_hour_by_title": {
					"Baecker": 12,
					"Kellner": 12,
					"Programmierer": 24,
					"Fahrer": 15,
					"Mechaniker": 18,
					"Verkaeufer": 13,
					"Designer": 19,
					"Doctor": 30,
					"Teacher": 18,
					"Engineer": 26,
					"Professor": 28,
					"Janitor": 13,
					"Gardener": 14,
					"MaintenanceWorker": 16,
					"Technician": 22,
				},
				"required_education": {
					"Doctor": 1,
					"Teacher": 0,
					"Engineer": 1,
					"Professor": 2,
					"Janitor": 0,
					"Gardener": 0,
					"MaintenanceWorker": 0,
					"Technician": 1,
				},
				"allowed_building_types": {
					"Teacher": ["UNIVERSITY"],
					"Professor": ["UNIVERSITY"],
					"Janitor": ["UNIVERSITY", "CITY_HALL", "PARK"],
					"Gardener": ["PARK"],
					"MaintenanceWorker": ["CAFE", "CINEMA", "FACTORY", "FARM", "RESIDENTIAL", "RESTAURANT", "SHOP", "SUPERMARKET", "CITY_HALL", "UNIVERSITY", "PARK"],
					"Technician": ["FACTORY", "CITY_HALL"],
				},
			},
			"city_hall": {
				"business_tax_rate": 0.10,
				"citizen_tax_rate": 0.02,
				"infrastructure_cost_per_day": 120,
				"unemployment_support": 40,
				"start_balance": 4500,
				"min_operating_balance": 500,
				"reserve_transfer_target_balance": 1600,
				"reserve_transfer_daily_limit": 900,
				"max_underfunded_days_before_closure": 3,
				"underfunded_efficiency_multiplier": 0.82,
				"underfunded_service_multiplier": 0.76,
			},
			"buildings": {
				"start_balance": 320,
				"max_missed_payment_days_before_closure": 3,
				"struggling_efficiency_multiplier": 0.72,
				"struggling_customer_multiplier": 0.78,
			},
		},
		"world_setup": {
			"default_rent_per_day": 15,
			"default_work_capacity": 1,
			"university_job_capacity_override": 8,
		},
		"schedule": {
			"night_start_hour": 22,
			"day_start_hour": 6,
		},
		"citizen": {
			"wallet_start_balance": 200,
			"home_food_stock_start": 2,
			"education_level_start": 0,
			"thresholds": {
				"hunger_threshold_base": 60.0,
				"hunger_threshold_jitter": 12.0,
				"low_energy_threshold_base": 35.0,
				"low_energy_threshold_jitter": 10.0,
				"work_motivation_base": 1.0,
				"work_motivation_jitter": 0.4,
				"park_interest_base": 0.35,
				"park_interest_jitter": 0.20,
				"fun_target_base": 65.0,
				"fun_target_jitter": 15.0,
			},
			"needs": {
				"target_hunger_max": 20.0,
				"target_energy_min": 80.0,
				"target_fun_min": 30.0,
				"target_health": 100.0,
				"hunger_rate_per_min": 0.10,
				"energy_rate_per_min": 0.08,
				"fun_rate_per_min": 0.03,
				"health_hunger_threshold": 80.0,
				"health_hunger_penalty_per_min": 0.10,
				"health_energy_threshold": 10.0,
				"health_energy_penalty_per_min": 0.06,
				"health_fun_threshold": 0.0,
				"health_fun_penalty_per_min": 0.02,
				"health_recovery_hunger_threshold": 60.0,
				"health_recovery_energy_threshold": 40.0,
				"health_recovery_fun_threshold": 20.0,
				"health_recovery_per_min": 0.015,
			},
		},
		"building": {
			"condition_start": 100.0,
			"daily_decay": 1.0,
			"maintenance_cost_per_day": 14,
			"repair_threshold": 60.0,
		},
		"actions": {
			"eat_home": {
				"max_minutes": 70,
				"hunger_mul": 0.25,
				"energy_mul": 0.45,
				"fun_mul": 1.0,
				"hunger_add": -0.95,
				"energy_add": 0.14,
				"fun_add": -0.02,
			},
			"eat_restaurant": {
				"max_minutes": 80,
				"hunger_mul": 0.15,
				"energy_mul": 0.35,
				"fun_mul": 0.55,
				"hunger_add": -1.15,
				"energy_add": 0.22,
				"fun_add": 0.08,
			},
			"relax_home": {
				"hunger_mul": 1.0,
				"energy_mul": 1.0,
				"fun_mul": 1.0,
				"hunger_add": 0.0,
				"energy_add": 0.10,
				"fun_add": 0.45,
			},
			"relax_park": {
				"default_minutes": 90,
				"hunger_mul": 1.0,
				"energy_mul": 1.0,
				"fun_mul": 1.0,
				"hunger_add": 0.0,
				"fun_add": 0.22,
				"no_bench_energy_add": 0.0,
				"bench_energy_add": 0.10,
				"bench_fun_add_bonus": 0.03,
				"stop_energy_threshold": 18.0,
				"stop_health_threshold": 35.0,
			},
			"relax_bench": {
				"default_minutes": 45,
				"hunger_mul": 1.0,
				"energy_mul": 1.0,
				"fun_mul": 1.0,
				"hunger_add": 0.0,
				"energy_add": 0.18,
				"fun_add": 0.0,
				"stop_hunger_threshold": 70.0,
				"stop_health_threshold": 35.0,
			},
			"sleep": {
				"wake_hour_min": 6,
				"night_start_hour": 22,
				"starvation_wake_hunger": 65.0,
				"min_sleep_before_starvation_check_min": 30,
				"hunger_mul": 0.35,
				"energy_mul": 1.0,
				"fun_mul": 0.0,
				"hunger_add": 0.0,
				"energy_add": 0.6,
				"fun_add": 0.0,
			},
			"watch_cinema": {
				"default_minutes": 80,
				"hunger_mul": 1.0,
				"energy_mul": 1.0,
				"fun_mul": 1.0,
				"hunger_add": 0.0,
				"energy_add": -0.01,
				"fun_add": 0.34,
				"stop_hunger_threshold": 70.0,
				"stop_energy_threshold": 18.0,
				"stop_health_threshold": 35.0,
			},
			"study": {
				"default_minutes": 90,
				"stop_hunger_threshold": 70.0,
				"stop_health_threshold": 35.0,
			},
			"work": {
				"lunch_start_minute": 690,
				"lunch_end_minute": 810,
				"needs_hunger_mul": 1.8,
				"needs_energy_mul": 1.625,
				"needs_fun_mul": 2.0,
				"needs_hunger_add": 0.0,
				"needs_energy_add": 0.0,
				"needs_fun_add": 0.0,
				"extra_energy_drain_per_min": 0.05,
				"extra_hunger_gain_per_min": 0.08,
				"extra_fun_drain_per_min": 0.03,
				"stop_health_threshold": 35.0,
				"stop_hunger_threshold": 70.0,
			},
		},
		"planner": {
			"critical_hunger": 80.0,
			"critical_energy": 10.0,
			"low_health": 35.0,
			"critical_health": 20.0,
			"work_commute_buffer_min": 30,
			"hunger_priority_scale": 40.0,
			"energy_priority_scale": 40.0,
			"fun_priority_scale": 35.0,
			"goal_priority_hunger_weight": 1.25,
			"goal_priority_energy_weight": 1.1,
			"goal_priority_education_weight": 0.95,
			"goal_priority_work_weight": 0.9,
			"goal_priority_fun_weight": 0.65,
			"work_need_base_priority": 0.45,
			"work_need_remaining_weight": 0.55,
			"low_health_hunger_alert_threshold": 65.0,
			"low_health_energy_alert_threshold": 35.0,
			"emergency_energy_threshold": 8.0,
			"fun_block_hunger_threshold": 60.0,
			"fun_block_energy_threshold": 25.0,
			"relax_home_min_energy_threshold": 20.0,
			"work_fit_hunger_threshold": 75.0,
			"fallback_home_travel_minutes": 20,
			"survival_home_travel_minutes": 20,
			"survival_restaurant_travel_minutes": 15,
			"survival_supermarket_travel_minutes": 18,
			"work_travel_minutes": 20,
		},
		"goap": {
			"education": {
				"health_min": 35.0,
				"hunger_max": 70.0,
				"go_university_cost": 1.0,
				"study_cost": 0.65,
				"travel_minutes": 24,
			},
			"work": {
				"health_min": 35.0,
				"hunger_max": 75.0,
				"go_work_cost": 0.65,
				"work_shift_cost": 0.5,
				"travel_minutes": 20,
			},
			"fun": {
				"safe_hunger_max": 60.0,
				"safe_energy_min": 25.0,
				"safe_health_min": 35.0,
				"energy_ok_min": 18.0,
				"go_home_cost": 1.2,
				"go_park_cost": 1.0,
				"go_shop_cost": 0.95,
				"go_cinema_cost": 1.1,
				"relax_park_cost": 0.75,
				"buy_clothes_cost": 0.65,
				"watch_cinema_cost": 0.7,
				"relax_home_cost": 1.8,
				"home_travel_minutes": 20,
				"park_travel_minutes": 22,
				"shop_travel_minutes": 20,
				"cinema_travel_minutes": 24,
			},
			"hunger": {
				"go_home_cost": 1.3,
				"go_restaurant_cost": 1.0,
				"go_supermarket_cost": 1.1,
				"buy_groceries_cost": 0.8,
				"eat_home_cost": 0.9,
				"eat_restaurant_cost": 0.8,
				"home_travel_minutes": 20,
				"restaurant_travel_minutes": 15,
				"supermarket_travel_minutes": 18,
			},
			"energy": {
				"go_home_cost": 0.9,
				"go_bench_cost": 1.0,
				"sleep_cost": 0.6,
				"relax_bench_cost": 0.85,
				"relax_home_cost": 1.1,
				"home_travel_minutes": 20,
			},
		},
		"buildings": {
			"residential": {
				"capacity": 10,
				"rent_per_day": 15,
			},
			"restaurant": {
				"capacity": 20,
				"job_capacity": 5,
				"open_hour": 8,
				"close_hour": 22,
				"meal_price": 15,
				"meal_start_stock": 48,
				"meal_restock_target": 70,
				"meal_restock_batch": 30,
			},
			"cafe": {
				"capacity": 18,
				"job_capacity": 3,
				"open_hour": 7,
				"close_hour": 20,
				"drink_price": 8,
				"drink_start_stock": 45,
				"drink_restock_target": 70,
				"drink_restock_batch": 26,
			},
			"shop": {
				"capacity": 25,
				"job_capacity": 4,
				"open_hour": 9,
				"close_hour": 20,
				"item_price": 18,
				"fun_gain": 5.0,
				"clothing_start_stock": 34,
				"clothing_restock_target": 56,
				"clothing_restock_batch": 20,
			},
			"supermarket": {
				"capacity": 30,
				"job_capacity": 6,
				"open_hour": 7,
				"close_hour": 22,
				"grocery_price": 10,
				"groceries_per_purchase": 3,
				"clothing_price": 24,
				"grocery_start_stock": 60,
				"grocery_restock_target": 90,
				"grocery_restock_batch": 35,
			},
			"cinema": {
				"capacity": 35,
				"job_capacity": 5,
				"open_hour": 12,
				"close_hour": 23,
				"ticket_price": 14,
			},
			"city_hall": {
				"capacity": 15,
				"job_capacity": 5,
				"open_hour": 6,
				"close_hour": 19,
			},
			"university": {
				"capacity": 40,
				"job_capacity": 8,
				"open_hour": 7,
				"close_hour": 21,
				"base_operating_cost": 110,
				"education_gain": 1,
			},
			"park": {
				"capacity": 40,
				"job_capacity": 2,
				"open_hour": 6,
				"close_hour": 23,
				"base_operating_cost": 32,
				"navigation_blocker_margin": 1.35,
				"entrance_clearance_width": 2.6,
				"entrance_clearance_depth": 1.9,
				"entrance_trigger_radius": 0.9,
				"entrance_trigger_outset": 0.8,
			},
			"farm": {
				"capacity": 8,
				"job_capacity": 6,
				"open_hour": 5,
				"close_hour": 19,
				"base_food_output_per_day": 140,
				"production_cost_per_unit": 1,
			},
			"factory": {
				"capacity": 10,
				"job_capacity": 8,
				"open_hour": 6,
				"close_hour": 21,
				"clothes_output_per_day": 55,
				"entertainment_output_per_day": 90,
				"production_cost_per_unit": 2,
			},
		},
	}
