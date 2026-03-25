extends Resource
class_name Needs

const BalanceConfig = preload("res://Simulation/Config/BalanceConfig.gd")

var TARGET_HUNGER_MAX: float = 20.0
var TARGET_ENERGY_MIN: float = 80.0
var TARGET_FUN_MIN: float = 30.0
var TARGET_HEALTH: float = 100.0

var hunger_rate_per_min: float = 0.10
var energy_rate_per_min: float = 0.08
var fun_rate_per_min: float = 0.03
var health_hunger_threshold: float = 80.0
var health_hunger_penalty_per_min: float = 0.10
var health_energy_threshold: float = 10.0
var health_energy_penalty_per_min: float = 0.06
var health_fun_threshold: float = 0.0
var health_fun_penalty_per_min: float = 0.02
var health_recovery_hunger_threshold: float = 60.0
var health_recovery_energy_threshold: float = 40.0
var health_recovery_fun_threshold: float = 20.0
var health_recovery_per_min: float = 0.015

var hunger: float = 0.0
var energy: float = 100.0
var fun: float = 70.0
var health: float = 100.0

var _last_health: float = 100.0

func _init() -> void:
	var settings := BalanceConfig.get_section("citizen.needs")
	TARGET_HUNGER_MAX = float(settings.get("target_hunger_max", TARGET_HUNGER_MAX))
	TARGET_ENERGY_MIN = float(settings.get("target_energy_min", TARGET_ENERGY_MIN))
	TARGET_FUN_MIN = float(settings.get("target_fun_min", TARGET_FUN_MIN))
	TARGET_HEALTH = float(settings.get("target_health", TARGET_HEALTH))
	hunger_rate_per_min = float(settings.get("hunger_rate_per_min", hunger_rate_per_min))
	energy_rate_per_min = float(settings.get("energy_rate_per_min", energy_rate_per_min))
	fun_rate_per_min = float(settings.get("fun_rate_per_min", fun_rate_per_min))
	health_hunger_threshold = float(settings.get("health_hunger_threshold", health_hunger_threshold))
	health_hunger_penalty_per_min = float(settings.get("health_hunger_penalty_per_min", health_hunger_penalty_per_min))
	health_energy_threshold = float(settings.get("health_energy_threshold", health_energy_threshold))
	health_energy_penalty_per_min = float(settings.get("health_energy_penalty_per_min", health_energy_penalty_per_min))
	health_fun_threshold = float(settings.get("health_fun_threshold", health_fun_threshold))
	health_fun_penalty_per_min = float(settings.get("health_fun_penalty_per_min", health_fun_penalty_per_min))
	health_recovery_hunger_threshold = float(settings.get("health_recovery_hunger_threshold", health_recovery_hunger_threshold))
	health_recovery_energy_threshold = float(settings.get("health_recovery_energy_threshold", health_recovery_energy_threshold))
	health_recovery_fun_threshold = float(settings.get("health_recovery_fun_threshold", health_recovery_fun_threshold))
	health_recovery_per_min = float(settings.get("health_recovery_per_min", health_recovery_per_min))

func advance(
	minutes: int,
	hunger_mul: float = 1.0,
	energy_mul: float = 1.0,
	fun_mul: float = 1.0,
	hunger_add: float = 0.0,
	energy_add: float = 0.0,
	fun_add: float = 0.0
) -> void:
	var m := float(minutes)

	# English comment: Base per-minute metabolism (scaled by action multipliers).
	hunger += hunger_rate_per_min * m * hunger_mul
	energy -= energy_rate_per_min * m * energy_mul
	fun    -= fun_rate_per_min * m * fun_mul

	# English comment: Additive deltas per minute (can be negative), e.g. sleep regen or eating.
	hunger += hunger_add * m
	energy += energy_add * m
	fun    += fun_add * m

	# --- HEALTH SYSTEM (unchanged) ---
	var health_delta := 0.0
	if hunger >= health_hunger_threshold:
		health_delta -= health_hunger_penalty_per_min * m
	if energy <= health_energy_threshold:
		health_delta -= health_energy_penalty_per_min * m
	if fun <= health_fun_threshold:
		health_delta -= health_fun_penalty_per_min * m

	var all_ok := (
		hunger < health_recovery_hunger_threshold
		and energy > health_recovery_energy_threshold
		and fun > health_recovery_fun_threshold
	)
	if all_ok and health < TARGET_HEALTH:
		health_delta += health_recovery_per_min * m

	health += health_delta
	_clamp()

func get_health_delta() -> float:
	var delta := health - _last_health
	_last_health = health
	return delta

func _clamp() -> void:
	hunger = clamp(hunger, 0.0, 100.0)
	energy = clamp(energy, 0.0, 100.0)
	fun    = clamp(fun,    0.0, 100.0)
	health = clamp(health, 0.0, 100.0)
