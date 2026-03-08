extends Resource
class_name Needs

const TARGET_HUNGER_MAX := 20.0
const TARGET_ENERGY_MIN := 80.0
const TARGET_FUN_MIN    := 30.0
const TARGET_HEALTH     := 100.0

var hunger: float = 0.0
var energy: float = 100.0
var fun: float = 70.0
var health: float = 100.0

var _last_health: float = 100.0

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
	hunger += 0.10 * m * hunger_mul
	energy -= 0.08 * m * energy_mul
	fun    -= 0.03 * m * fun_mul

	# English comment: Additive deltas per minute (can be negative), e.g. sleep regen or eating.
	hunger += hunger_add * m
	energy += energy_add * m
	fun    += fun_add * m

	# --- HEALTH SYSTEM (unchanged) ---
	var health_delta := 0.0
	if hunger >= 80.0:
		health_delta -= 0.10 * m
	if energy <= 10.0:
		health_delta -= 0.06 * m
	if fun <= 0.0:
		health_delta -= 0.02 * m

	var all_ok := (hunger < 60.0 and energy > 40.0 and fun > 20.0)
	if all_ok and health < 100.0:
		health_delta += 0.015 * m

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
