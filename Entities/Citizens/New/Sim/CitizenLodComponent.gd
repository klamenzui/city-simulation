class_name CitizenLodComponent
extends RefCounted

## LOD tier state + commitments + runtime-profile parameters.
## Extracted from old `Citizen.gd` lines 36-49, 352-527.
##
## Responsibilities:
##   - Hold the citizen's current LOD tier ("focus" / "active" / "coarse")
##     and the tick interval/phase that drives the World's bucket scheduler.
##   - Hold the runtime profile parameters set by `apply_runtime_profile`
##     (path_mode, decision_interval_sec, repath fallback). Side-effects on
##     navigation (Cluster B) are applied by the Facade, not here.
##   - Track active commitments (player_dialog, npc_dialog_materialized, …)
##     with day+minute expiration; lazy cleanup via `clear_expired_commitments`.
##
## Does NOT:
##   - Toggle Node visibility, collision layers, or physics_process — those
##     are Facade orchestration in `set_simulation_lod_state`.
##   - Notify World — Facade does that after the component state is updated.
##   - Read Scheduler's `decision_cooldown_range_*` — caller passes them in.

const TIER_FOCUS: String = "focus"
const TIER_ACTIVE: String = "active"
const TIER_COARSE: String = "coarse"

const PATH_MODE_DEFAULT: String = "default"
const PATH_MODE_FULL: String = "full"
const PATH_MODE_CHEAP: String = "cheap"

# ----------------------------- Tier state -----------------------------

var tier: String = TIER_FOCUS
var tick_interval_minutes: int = 1
var tick_phase_seed: int = 0

# Marks whether the citizen has been hidden via the LOD pipeline (separate
# from indoor presence; both can hide the body).
var presence_hidden: bool = false

# ----------------------------- Runtime profile -----------------------------

var path_mode: String = PATH_MODE_DEFAULT
var decision_interval_sec: float = 0.0
var runtime_defaults_captured: bool = false
var default_repath_interval_sec: float = 0.6
var default_local_navigation_enabled: bool = true

# ----------------------------- Commitments -----------------------------

## Each commitment is `{type, until_day, until_minute, priority, ...metadata}`.
var _commitments: Array = []


# =================== Tier state ===================

## Updates tier + tick-interval + presence flag. Phase seed is randomised
## on every tier change so the World scheduler distributes ticks evenly.
func set_state(new_tier: String, rendered: bool, p_tick_interval_minutes: int = 1) -> void:
	tier = new_tier
	tick_interval_minutes = maxi(p_tick_interval_minutes, 1)
	tick_phase_seed = randi()
	presence_hidden = not rendered


## Stable tick interval in minutes (≥ 1).
func get_tick_interval_minutes() -> int:
	return maxi(tick_interval_minutes, 1)


## Tick interval converted to whole World-ticks. `world.minutes_per_tick`
## decides how many sim-minutes pass per tick.
func get_tick_interval_ticks(world: Node) -> int:
	if world == null:
		return 1
	var minutes_per_tick: int = 1
	if "minutes_per_tick" in world:
		minutes_per_tick = maxi(int(world.minutes_per_tick), 1)
	return maxi(ceili(float(get_tick_interval_minutes()) / float(minutes_per_tick)), 1)


## Slot inside the tick interval — used by World to schedule which citizens
## tick on which physics frame (load distribution).
func get_tick_slot(world: Node) -> int:
	var interval_ticks := get_tick_interval_ticks(world)
	if interval_ticks <= 1:
		return 0
	return posmod(tick_phase_seed, interval_ticks)


## True when the citizen is due for a sim-tick this frame. Coarse tier asks
## the World scheduler; focus/active always run.
func should_run_tick(world: Node) -> bool:
	if world == null:
		return true
	if tier != TIER_COARSE:
		return true
	if not world.has_method("is_citizen_due_for_simulation"):
		return true
	# Caller is the Facade — it knows the citizen ref, which World needs.
	# This component only forwards the tier policy.
	return true  # decision delegated to Facade.is_citizen_due_for_simulation_call


# =================== Runtime profile ===================

## Captures the citizen's pre-LOD navigation defaults so future
## `apply_runtime_profile` calls can resolve "use default" entries.
## `current_repath` and `current_local_nav` come from the Facade — the
## component does not read CitizenController fields directly.
func capture_runtime_defaults(current_repath: float, current_local_nav: bool) -> void:
	if runtime_defaults_captured:
		return
	runtime_defaults_captured = true
	default_repath_interval_sec = current_repath
	default_local_navigation_enabled = current_local_nav


## Updates path_mode + decision_interval_sec from a runtime profile. Returns
## a result Dictionary the Facade applies to the new-stack navigation:
##   { path_mode, local_avoidance, repath_interval_sec, decision_interval_sec }
func apply_runtime_profile(profile: Dictionary) -> Dictionary:
	var resolved_profile := profile.duplicate(true)
	var resolved_path_mode := PATH_MODE_DEFAULT
	if bool(resolved_profile.get("full_navigation", false)):
		resolved_path_mode = PATH_MODE_FULL
	elif bool(resolved_profile.get("cheap_path_follow", false)) \
			or not bool(resolved_profile.get("full_navigation", true)):
		resolved_path_mode = PATH_MODE_CHEAP
	path_mode = resolved_path_mode

	var local_avoidance_enabled := bool(resolved_profile.get(
			"local_avoidance", default_local_navigation_enabled))
	var repath_override := float(resolved_profile.get(
			"path_refresh_interval_sec", default_repath_interval_sec))
	repath_override = maxf(repath_override, 0.05)
	decision_interval_sec = maxf(float(resolved_profile.get("decision_interval_sec", 0.0)), 0.0)

	return {
		"path_mode": resolved_path_mode,
		"local_avoidance": local_avoidance_enabled,
		"repath_interval_sec": repath_override,
		"decision_interval_sec": decision_interval_sec,
	}


## Decision-cooldown range (in sim-minutes). When LOD has set
## `decision_interval_sec`, the range is derived from that; otherwise the
## fallback range comes from the Scheduler defaults (caller passes them).
func get_decision_cooldown_range_minutes(world: Node, fallback_min: int, fallback_max: int) -> Vector2i:
	var fallback := Vector2i(fallback_min, fallback_max)
	if decision_interval_sec <= 0.0 or world == null:
		return fallback
	var tick_wait_sec: float = 0.001
	if "tick_interval_sec" in world:
		tick_wait_sec = maxf(float(world.tick_interval_sec), 0.001)
	var ticks_needed: int = maxi(ceili(decision_interval_sec / tick_wait_sec), 1)
	var minutes_per_tick: int = 1
	if "minutes_per_tick" in world:
		minutes_per_tick = maxi(int(world.minutes_per_tick), 1)
	var base_minutes: int = ticks_needed * minutes_per_tick
	if base_minutes <= fallback.x:
		return fallback
	var jitter_minutes: int = minutes_per_tick
	return Vector2i(
			maxi(base_minutes - jitter_minutes, minutes_per_tick),
			maxi(base_minutes + jitter_minutes, fallback.x))


# =================== Commitments ===================

func add_commitment(commitment_type: String, until_day: int, until_minute: int,
		priority: float = 1.0) -> void:
	_commitments.append({
		"type": commitment_type,
		"until_day": until_day,
		"until_minute": until_minute,
		"priority": priority,
	})


## Insert-or-update by type. Returns true if an existing entry was replaced.
func upsert_commitment(commitment_type: String, until_day: int, until_minute: int,
		priority: float = 1.0, metadata: Dictionary = {}) -> bool:
	for i in _commitments.size():
		var existing: Variant = _commitments[i]
		if existing is not Dictionary:
			continue
		if str((existing as Dictionary).get("type", "")) != commitment_type:
			continue
		var merged := (existing as Dictionary).duplicate(true)
		merged["until_day"] = until_day
		merged["until_minute"] = until_minute
		merged["priority"] = priority
		for key in metadata.keys():
			merged[key] = metadata[key]
		_commitments[i] = merged
		return true
	var entry := {
		"type": commitment_type,
		"until_day": until_day,
		"until_minute": until_minute,
		"priority": priority,
	}
	for key in metadata.keys():
		entry[key] = metadata[key]
	_commitments.append(entry)
	return false


func remove_commitment(commitment_type: String) -> void:
	var remaining: Array = []
	for commitment in _commitments:
		if commitment is Dictionary and str((commitment as Dictionary).get("type", "")) == commitment_type:
			continue
		remaining.append(commitment)
	_commitments = remaining


func remove_commitments(commitment_types: Array) -> void:
	if commitment_types.is_empty():
		return
	var remaining: Array = []
	for commitment in _commitments:
		if commitment is Dictionary and commitment_types.has(str((commitment as Dictionary).get("type", ""))):
			continue
		remaining.append(commitment)
	_commitments = remaining


## Removes commitments whose `until_day/until_minute` is past `world`'s clock.
func clear_expired_commitments(world: Node) -> void:
	if world == null:
		return
	var current_day: int = 0
	if world.has_method("world_day"):
		current_day = int(world.world_day())
	var current_minute: int = 0
	if "time" in world and world.time != null:
		var t = world.time
		if t.has_method("get_hour") and t.has_method("get_minute"):
			current_minute = int(t.get_hour()) * 60 + int(t.get_minute())
	var remaining: Array = []
	for commitment in _commitments:
		if commitment is not Dictionary:
			continue
		var c := commitment as Dictionary
		var until_day: int = int(c.get("until_day", current_day))
		var until_minute: int = int(c.get("until_minute", current_minute))
		if until_day > current_day or (until_day == current_day and until_minute > current_minute):
			remaining.append(commitment)
	_commitments = remaining


func has_active_commitment(world: Node, required_types: Array = []) -> bool:
	clear_expired_commitments(world)
	if required_types.is_empty():
		return not _commitments.is_empty()
	for commitment in _commitments:
		if commitment is not Dictionary:
			continue
		if required_types.has(str((commitment as Dictionary).get("type", ""))):
			return true
	return false


func get_active_commitments(world: Node) -> Array:
	clear_expired_commitments(world)
	return _commitments.duplicate(true)


## Read-only access for tests / inspection.
func snapshot_commitments() -> Array:
	return _commitments.duplicate(true)
