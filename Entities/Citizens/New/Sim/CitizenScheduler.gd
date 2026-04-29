class_name CitizenScheduler
extends RefCounted

## Scheduler/personality state — extracted from old `Citizen.gd` lines
## 189-222, 265-276, 2876-2881, 3165-3187.
##
## Holds:
##   - **Decision cooldown** (CitizenAgent counts down until next GOAP replan)
##   - **Schedule offset** (per-citizen morning routine jitter, sim-minutes)
##   - **Personality thresholds** with jitter — hunger / low_energy /
##     work_motivation / park_interest / fun_target
##   - **Work-day tracking** — `work_minutes_today` reset on day rollover
##   - **Unreachable-target cache** — building_id → sim-minute-of-expiry
##
## Pure data + a few small operations. Side effects (action start/stop,
## building discovery, GOAP planning) live on the Facade or external
## services. The component does not depend on Identity / Location / LOD.
##
## NOTE on "personality thresholds": all five are produced once via
## `init_personality()` (called from the Facade `_ready`). They are seeded
## from `*_base + randf_range(-*_jitter, *_jitter)` so each citizen has a
## slightly different decision-making profile.

const BalanceConfigScript = preload("res://Simulation/Config/BalanceConfig.gd")

# ----------------------------- Schedule offset -----------------------------

var schedule_offset_min: int = -25
var schedule_offset_max: int = 25
## Personality-driven offset added to job.start_hour (in sim-minutes).
## Set by `init_personality`. Read by CitizenPlanner.
var schedule_offset: int = 0

# ----------------------------- Decision cooldown -----------------------------

var decision_cooldown_range_min: int = 5
var decision_cooldown_range_max: int = 20
## Sim-minutes until the next allowed GOAP replan. CitizenAgent decrements
## this every sim-tick and resets it to a fresh roll after each replan.
var decision_cooldown_left: int = 0

# ----------------------------- Personality thresholds -----------------------------

var hunger_threshold_base: float = 60.0
var hunger_threshold_jitter: float = 12.0
var hunger_threshold: float = 60.0

var low_energy_threshold_base: float = 35.0
var low_energy_threshold_jitter: float = 10.0
var low_energy_threshold: float = 35.0

var work_motivation_base: float = 1.0
var work_motivation_jitter: float = 0.4
var work_motivation: float = 1.0

var park_interest_base: float = 0.35
var park_interest_jitter: float = 0.20
var park_interest: float = 0.35

var fun_target_base: float = 65.0
var fun_target_jitter: float = 15.0
var fun_target: float = 65.0

# ----------------------------- Work-day -----------------------------

var work_minutes_today: int = 0
var _work_day_key: int = -1

# ----------------------------- Unreachable cache -----------------------------

var unreachable_target_retry_limit: int = 3
var unreachable_target_no_progress_minutes: int = 18
var unreachable_target_cooldown_minutes: int = 180
## Maps Building-instance-id → sim-minute-of-day (absolute) when cooldown ends.
var _temporarily_unreachable_targets: Dictionary = {}


# =================== Personality init ===================

## Reads jitter values from `config/balance.json` (`citizen.thresholds`).
## Idempotent — values that aren't in balance.json keep their defaults.
func apply_balance_config() -> void:
	var threshold_settings: Dictionary = BalanceConfigScript.get_section("citizen.thresholds")
	hunger_threshold_base = float(threshold_settings.get(
			"hunger_threshold_base", hunger_threshold_base))
	hunger_threshold_jitter = float(threshold_settings.get(
			"hunger_threshold_jitter", hunger_threshold_jitter))
	low_energy_threshold_base = float(threshold_settings.get(
			"low_energy_threshold_base", low_energy_threshold_base))
	low_energy_threshold_jitter = float(threshold_settings.get(
			"low_energy_threshold_jitter", low_energy_threshold_jitter))
	work_motivation_base = float(threshold_settings.get(
			"work_motivation_base", work_motivation_base))
	work_motivation_jitter = float(threshold_settings.get(
			"work_motivation_jitter", work_motivation_jitter))
	park_interest_base = float(threshold_settings.get(
			"park_interest_base", park_interest_base))
	park_interest_jitter = float(threshold_settings.get(
			"park_interest_jitter", park_interest_jitter))
	fun_target_base = float(threshold_settings.get(
			"fun_target_base", fun_target_base))
	fun_target_jitter = float(threshold_settings.get(
			"fun_target_jitter", fun_target_jitter))


## Rolls schedule_offset and the five personality thresholds from their
## base/jitter pairs. Called once from the Facade `_ready` after
## `apply_balance_config`.
func init_personality() -> void:
	schedule_offset = randi_range(schedule_offset_min, schedule_offset_max)
	hunger_threshold = hunger_threshold_base + randf_range(
			-hunger_threshold_jitter, hunger_threshold_jitter)
	low_energy_threshold = low_energy_threshold_base + randf_range(
			-low_energy_threshold_jitter, low_energy_threshold_jitter)
	work_motivation = work_motivation_base + randf_range(
			-work_motivation_jitter, work_motivation_jitter)
	park_interest = clampf(
			park_interest_base + randf_range(-park_interest_jitter, park_interest_jitter),
			0.0, 0.9)
	fun_target = fun_target_base + randf_range(-fun_target_jitter, fun_target_jitter)


# =================== Decision cooldown ===================

## Decrements the cooldown by `tick_minutes`. Returns true when the cooldown
## has just hit zero (caller may run a replan).
func tick_decision_cooldown(tick_minutes: int) -> bool:
	if decision_cooldown_left <= 0:
		return true
	decision_cooldown_left -= tick_minutes
	return decision_cooldown_left <= 0


## Rolls a fresh cooldown from the configured range. Call after each replan.
## Caller may pre-clamp the range (e.g. via LOD profile) by setting
## `decision_cooldown_range_min/max` beforehand.
func roll_decision_cooldown() -> int:
	decision_cooldown_left = randi_range(
			decision_cooldown_range_min, decision_cooldown_range_max)
	return decision_cooldown_left


# =================== Work-day ===================

## Resets `work_minutes_today` when the in-game day changes.
func update_work_day(world: Node) -> void:
	if world == null or not "time" in world or world.time == null:
		return
	var t = world.time
	if not "day" in t:
		return
	var today: int = int(t.day)
	if _work_day_key != today:
		_work_day_key = today
		work_minutes_today = 0


# =================== Unreachable cache ===================

## True when the target's cooldown is still active.
func is_target_temporarily_unreachable(target: Object, world: Node) -> bool:
	if target == null or world == null:
		return false
	var until_minute := int(_temporarily_unreachable_targets.get(target.get_instance_id(), 0))
	if until_minute <= 0:
		return false
	return _get_sim_total_minutes(world) < until_minute


## Adds (or extends) a target's cooldown. Returns true if a NEW cooldown was
## set; false if an existing equal-or-later cooldown was already in place.
func mark_target_unreachable(target: Object, world: Node) -> bool:
	if target == null or world == null:
		return false
	var until_minute := _get_sim_total_minutes(world) + maxi(unreachable_target_cooldown_minutes, 1)
	var key := target.get_instance_id()
	var previous_until := int(_temporarily_unreachable_targets.get(key, 0))
	if previous_until >= until_minute:
		return false
	_temporarily_unreachable_targets[key] = until_minute
	return true


func get_target_remaining_minutes(target: Object, world: Node) -> int:
	if target == null or world == null:
		return 0
	var until_minute := int(_temporarily_unreachable_targets.get(target.get_instance_id(), 0))
	if until_minute <= 0:
		return 0
	return maxi(until_minute - _get_sim_total_minutes(world), 0)


func clear_unreachable_cache() -> void:
	_temporarily_unreachable_targets.clear()


static func _get_sim_total_minutes(world: Node) -> int:
	if world == null or not "time" in world or world.time == null:
		return 0
	var t = world.time
	var day: int = int(t.day) if "day" in t else 1
	var minutes_total: int = int(t.minutes_total) if "minutes_total" in t else 0
	return maxi(day - 1, 0) * 24 * 60 + minutes_total
