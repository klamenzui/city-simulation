class_name CitizenFacade
extends CitizenController

## Migration scaffold: extends the Movement-only `CitizenController` with a
## composed Sim layer (`CitizenSimulation`) and re-exposes the API surface
## that callers (`CitizenAgent`, `CitizenPlanner`, GOAP Actions, `World`,
## `CitizenSimulationLodController`, Factory) currently expect from the
## legacy `Citizen.gd`.
##
## **Today's status:** scaffold only. The first migrated component is
## `CitizenRestPose`. As more components are extracted out of `Citizen.gd`,
## new pass-through methods are added here.
##
## **Why a Facade and not just adding methods to `CitizenController`?**
## Movement is a self-contained subsystem with its own test-coverage and a
## clear public API (`set_global_target`, `stop_travel`, `is_travelling`).
## Stuffing Sim concerns into the same class would re-create the
## 3000-line monolith we are migrating away from.
##
## **Why a separate file from the legacy `Entities/Citizens/Citizen.gd`?**
## `class_name Citizen` is currently owned by the legacy file and many
## callers reference it. Renaming/replacing in one go would break the
## simulation while migration is in progress. When all components are
## migrated, the legacy file can be archived and this class renamed to
## `Citizen` (and `CitizenNew.tscn` repointed accordingly).
##
## See `Sim/MIGRATION.md` for the full roadmap.

@export_group("Identity")
## Display name. Mirrored into `_sim.identity.citizen_name` on `_ready`.
@export var citizen_name: String = "Alex"

const SimLoggerScript = preload("res://Simulation/Logging/SimLogger.gd")

var _sim: CitizenSimulation = null

# Saved at _ready so Presence-Toggle can restore them on building exit.
var _saved_collision_layer: int = 0
var _saved_collision_mask: int = 0
var _interior_presence_hidden: bool = false


func _ready() -> void:
	super._ready()
	_sim = CitizenSimulation.new(self)
	# Mirror Inspector-set @export values into Identity.
	if _sim != null and _sim.identity != null:
		_sim.identity.citizen_name = citizen_name
	# Initialise personality thresholds from balance.json + jitter.
	if _sim != null and _sim.scheduler != null:
		_sim.scheduler.apply_balance_config()
		_sim.scheduler.init_personality()
	# Snapshot collision layers so building entry/exit can toggle them.
	_saved_collision_layer = collision_layer
	_saved_collision_mask = collision_mask


# ========================================================================
# Identity property forwarding (CitizenAgent / Actions / World read these
# directly via dot-access on the citizen). Each pair forwards into
# `_sim.identity.*`. Null-safe: if the simulation hasn't been built yet,
# getters return null/defaults and setters are no-ops.
# ========================================================================

var home: ResidentialBuilding:
	get:
		if _sim != null and _sim.identity != null:
			return _sim.identity.home
		return null
	set(value):
		if _sim != null and _sim.identity != null:
			_sim.identity.home = value

var job: Job:
	get:
		if _sim != null and _sim.identity != null:
			return _sim.identity.job
		return null
	set(value):
		if _sim != null and _sim.identity != null:
			_sim.identity.job = value

var wallet: Account:
	get:
		if _sim != null and _sim.identity != null:
			return _sim.identity.wallet
		return null
	set(value):
		if _sim != null and _sim.identity != null:
			_sim.identity.wallet = value

var needs: Needs:
	get:
		if _sim != null and _sim.identity != null:
			return _sim.identity.needs
		return null
	set(value):
		if _sim != null and _sim.identity != null:
			_sim.identity.needs = value

var current_location: Building:
	get:
		if _sim != null and _sim.identity != null:
			return _sim.identity.current_location
		return null
	set(value):
		if _sim != null and _sim.identity != null:
			_sim.identity.current_location = value

var home_food_stock: int:
	get:
		if _sim != null and _sim.identity != null:
			return _sim.identity.home_food_stock
		return 0
	set(value):
		if _sim != null and _sim.identity != null:
			_sim.identity.home_food_stock = value

var education_level: int:
	get:
		if _sim != null and _sim.identity != null:
			return _sim.identity.education_level
		return 0
	set(value):
		if _sim != null and _sim.identity != null:
			_sim.identity.education_level = value


# Favorites — accessed via getters/setters rather than property forwarding to
# keep the @export-property cluster small. Plain helpers, identical effect.

func get_favorite_restaurant() -> Restaurant:
	return _sim.identity.favorite_restaurant if _sim != null and _sim.identity != null else null


func set_favorite_restaurant(value: Restaurant) -> void:
	if _sim != null and _sim.identity != null:
		_sim.identity.favorite_restaurant = value


func get_favorite_supermarket() -> Supermarket:
	return _sim.identity.favorite_supermarket if _sim != null and _sim.identity != null else null


func set_favorite_supermarket(value: Supermarket) -> void:
	if _sim != null and _sim.identity != null:
		_sim.identity.favorite_supermarket = value


func get_favorite_shop() -> Shop:
	return _sim.identity.favorite_shop if _sim != null and _sim.identity != null else null


func set_favorite_shop(value: Shop) -> void:
	if _sim != null and _sim.identity != null:
		_sim.identity.favorite_shop = value


func get_favorite_cinema() -> Cinema:
	return _sim.identity.favorite_cinema if _sim != null and _sim.identity != null else null


func set_favorite_cinema(value: Cinema) -> void:
	if _sim != null and _sim.identity != null:
		_sim.identity.favorite_cinema = value


func get_favorite_park() -> Building:
	return _sim.identity.favorite_park if _sim != null and _sim.identity != null else null


func set_favorite_park(value: Building) -> void:
	if _sim != null and _sim.identity != null:
		_sim.identity.favorite_park = value


# ========================================================================
# Scheduler property-forwarding — many fields are written and read directly
# by CitizenAgent / CitizenPlanner. Forwarding keeps the legacy access shape.
# ========================================================================

var schedule_offset: int:
	get: return _sim.scheduler.schedule_offset if _sim != null and _sim.scheduler != null else 0
	set(v):
		if _sim != null and _sim.scheduler != null:
			_sim.scheduler.schedule_offset = v

var schedule_offset_min: int:
	get: return _sim.scheduler.schedule_offset_min if _sim != null and _sim.scheduler != null else 0
	set(v):
		if _sim != null and _sim.scheduler != null:
			_sim.scheduler.schedule_offset_min = v

var schedule_offset_max: int:
	get: return _sim.scheduler.schedule_offset_max if _sim != null and _sim.scheduler != null else 0
	set(v):
		if _sim != null and _sim.scheduler != null:
			_sim.scheduler.schedule_offset_max = v

var decision_cooldown_left: int:
	get: return _sim.scheduler.decision_cooldown_left if _sim != null and _sim.scheduler != null else 0
	set(v):
		if _sim != null and _sim.scheduler != null:
			_sim.scheduler.decision_cooldown_left = v

var decision_cooldown_range_min: int:
	get: return _sim.scheduler.decision_cooldown_range_min if _sim != null and _sim.scheduler != null else 5
	set(v):
		if _sim != null and _sim.scheduler != null:
			_sim.scheduler.decision_cooldown_range_min = v

var decision_cooldown_range_max: int:
	get: return _sim.scheduler.decision_cooldown_range_max if _sim != null and _sim.scheduler != null else 20
	set(v):
		if _sim != null and _sim.scheduler != null:
			_sim.scheduler.decision_cooldown_range_max = v

var hunger_threshold: float:
	get: return _sim.scheduler.hunger_threshold if _sim != null and _sim.scheduler != null else 60.0
	set(v):
		if _sim != null and _sim.scheduler != null:
			_sim.scheduler.hunger_threshold = v

var low_energy_threshold: float:
	get: return _sim.scheduler.low_energy_threshold if _sim != null and _sim.scheduler != null else 35.0
	set(v):
		if _sim != null and _sim.scheduler != null:
			_sim.scheduler.low_energy_threshold = v

var work_motivation: float:
	get: return _sim.scheduler.work_motivation if _sim != null and _sim.scheduler != null else 1.0
	set(v):
		if _sim != null and _sim.scheduler != null:
			_sim.scheduler.work_motivation = v

var park_interest: float:
	get: return _sim.scheduler.park_interest if _sim != null and _sim.scheduler != null else 0.35
	set(v):
		if _sim != null and _sim.scheduler != null:
			_sim.scheduler.park_interest = v

var fun_target: float:
	get: return _sim.scheduler.fun_target if _sim != null and _sim.scheduler != null else 65.0
	set(v):
		if _sim != null and _sim.scheduler != null:
			_sim.scheduler.fun_target = v

var work_minutes_today: int:
	get: return _sim.scheduler.work_minutes_today if _sim != null and _sim.scheduler != null else 0
	set(v):
		if _sim != null and _sim.scheduler != null:
			_sim.scheduler.work_minutes_today = v

## Action ownership — kept directly on the Facade because GOAP-Action object
## has no natural Sim-component home. CitizenAgent reads + writes this.
var current_action: Action = null


func _update_work_day(world: Node) -> void:
	if _sim == null or _sim.scheduler == null:
		return
	_sim.scheduler.update_work_day(world)


## Simplified `prepare_go_to_target` — checks the unreachable cache. Returning
## `null` when blocked. Building-discovery substitution (legacy
## `_find_alternative_for_building`) is NOT yet ported; callers that depend
## on automatic retargeting must check the alternative themselves until a
## Building-Discovery service is extracted.
func prepare_go_to_target(target: Building, world: Node) -> Building:
	if target == null or _sim == null or _sim.scheduler == null:
		return target
	if _sim.scheduler.is_target_temporarily_unreachable(target, world):
		var remaining := _sim.scheduler.get_target_remaining_minutes(target, world)
		debug_log_once_per_day(
				"target_cooldown_%d" % target.get_instance_id(),
				"Skipping temporarily unreachable target (%d sim-min remaining)." % remaining)
		return null
	return target


## Simplified `handle_unreachable_target` — marks the target. Returns null
## (legacy version returned an alternative; building-discovery service to come).
func handle_unreachable_target(target: Building, world: Node, reason: String = "") -> Building:
	if target == null or _sim == null or _sim.scheduler == null:
		return null
	if _sim.scheduler.mark_target_unreachable(target, world):
		debug_log("Marked target unreachable for %d sim-min (%s)." % [
				_sim.scheduler.unreachable_target_cooldown_minutes,
				reason if reason != "" else "navigation failure"])
	return null


# ========================================================================
# LOD API — delegates to CitizenLodComponent.
# Facade owns the side effects: physics_process toggle, presence layer,
# World.notify_citizen_lod_changed. Component owns the state.
# ========================================================================

## Default decision-cooldown range when no LOD profile is active.
## Pulled from the legacy Citizen.gd `@export` defaults — Scheduler
## migration will move these onto the Scheduler component.
const _DEFAULT_DECISION_COOLDOWN_MIN: int = 5
const _DEFAULT_DECISION_COOLDOWN_MAX: int = 20

func get_simulation_lod_tier() -> String:
	if _sim == null or _sim.lod == null:
		return CitizenLodComponent.TIER_FOCUS
	return _sim.lod.tier


func set_simulation_lod_state(p_tier: String, rendered: bool, physics_enabled: bool,
		tick_interval_minutes: int = 1) -> void:
	if _sim == null or _sim.lod == null:
		return
	_sim.lod.set_state(p_tier, rendered, tick_interval_minutes)
	# Side-effects on the CharacterBody3D side:
	_apply_lod_presence_state()
	var should_process_physics := physics_enabled or accept_click_input
	set_physics_process(should_process_physics)
	if not should_process_physics:
		velocity = Vector3.ZERO
	if _sim.world != null and is_instance_valid(_sim.world) \
			and _sim.world.has_method("notify_citizen_lod_changed"):
		_sim.world.notify_citizen_lod_changed(self)


func apply_simulation_lod_runtime_profile(profile: Dictionary, world: Node = null) -> void:
	if _sim == null or _sim.lod == null:
		return
	# Capture defaults once — repath/local-avoidance values are pulled from
	# the new-stack equivalents.
	_sim.lod.capture_runtime_defaults(local_astar_replan_interval, use_local_astar_avoidance)
	var resolved := _sim.lod.apply_runtime_profile(profile)
	# Apply the resolved settings to the new-stack navigation knobs.
	# `repath_interval_sec` (legacy) → `local_astar_replan_interval` (new).
	# `local_avoidance` → `use_local_astar_avoidance` (toggle the whole detour).
	local_astar_replan_interval = float(resolved.get("repath_interval_sec",
			local_astar_replan_interval))
	use_local_astar_avoidance = bool(resolved.get("local_avoidance",
			use_local_astar_avoidance))
	if world != null and _sim != null:
		_sim.set_world(world)


func get_simulation_lod_decision_cooldown_range_minutes(world: Node) -> Vector2i:
	if _sim == null or _sim.lod == null:
		return Vector2i(_DEFAULT_DECISION_COOLDOWN_MIN, _DEFAULT_DECISION_COOLDOWN_MAX)
	return _sim.lod.get_decision_cooldown_range_minutes(world,
			_DEFAULT_DECISION_COOLDOWN_MIN, _DEFAULT_DECISION_COOLDOWN_MAX)


func should_run_simulation_lod_tick(world: Node) -> bool:
	if _sim == null or _sim.lod == null:
		return true
	if world == null:
		return true
	if _sim.lod.tier != CitizenLodComponent.TIER_COARSE:
		return true
	# Coarse tier asks the World scheduler — Facade has the citizen ref World needs.
	if not world.has_method("is_citizen_due_for_simulation"):
		return true
	return world.is_citizen_due_for_simulation(self)


func get_simulation_lod_tick_interval_minutes() -> int:
	if _sim == null or _sim.lod == null:
		return 1
	return _sim.lod.get_tick_interval_minutes()


func get_simulation_lod_tick_interval_ticks(world: Node) -> int:
	if _sim == null or _sim.lod == null:
		return 1
	return _sim.lod.get_tick_interval_ticks(world)


func get_simulation_lod_tick_slot(world: Node) -> int:
	if _sim == null or _sim.lod == null:
		return 0
	return _sim.lod.get_tick_slot(world)


func add_lod_commitment(commitment_type: String, until_day: int, until_minute: int,
		priority: float = 1.0) -> void:
	if _sim == null or _sim.lod == null:
		return
	_sim.lod.add_commitment(commitment_type, until_day, until_minute, priority)


func upsert_lod_commitment(commitment_type: String, until_day: int, until_minute: int,
		priority: float = 1.0, metadata: Dictionary = {}) -> void:
	if _sim == null or _sim.lod == null:
		return
	_sim.lod.upsert_commitment(commitment_type, until_day, until_minute, priority, metadata)


func remove_lod_commitment(commitment_type: String) -> void:
	if _sim == null or _sim.lod == null:
		return
	_sim.lod.remove_commitment(commitment_type)


func remove_lod_commitments(commitment_types: Array) -> void:
	if _sim == null or _sim.lod == null:
		return
	_sim.lod.remove_commitments(commitment_types)


func clear_expired_lod_commitments(world: Node) -> void:
	if _sim == null or _sim.lod == null:
		return
	_sim.lod.clear_expired_commitments(world)


func has_active_lod_commitment(world: Node, required_types: Array = []) -> bool:
	if _sim == null or _sim.lod == null:
		return false
	return _sim.lod.has_active_commitment(world, required_types)


func get_active_lod_commitments(world: Node) -> Array:
	if _sim == null or _sim.lod == null:
		return []
	return _sim.lod.get_active_commitments(world)


## Combines LOD-presence-flag and indoor-presence-flag — both can hide the
## body. The order matters: indoor presence is set via `_set_interior_presence`
## above; LOD presence reuses the same toggle but ORs the flag.
func _apply_lod_presence_state() -> void:
	if _sim == null or _sim.lod == null:
		return
	# When LOD wants to hide and we're not already hidden by indoor presence,
	# trigger the hide path. When LOD wants to show but we ARE indoor, the
	# indoor flag wins.
	var should_hide := _sim.lod.presence_hidden or _interior_presence_hidden
	if should_hide and visible:
		hide()
		velocity = Vector3.ZERO
		collision_layer = 0
		collision_mask = 0
	elif not should_hide and not visible:
		show()
		collision_layer = _saved_collision_layer
		collision_mask = _saved_collision_mask


# ========================================================================
# Bench reservation — delegates to CitizenBenchReservation.
# ========================================================================

func release_reserved_benches(world: Node = null, building: Building = null) -> void:
	if _sim == null or _sim.bench_reservation == null:
		return
	_sim.bench_reservation.release(world, building, current_location)


# ========================================================================
# Location API — delegates to CitizenLocation, orchestrates state on the
# CharacterBody3D side (position, presence toggle, building callbacks).
# ========================================================================

func is_inside_building() -> bool:
	return _sim != null and _sim.location != null and _sim.location.is_inside()


func get_navigation_points_for_building(building: Building, world: Node = null) -> Dictionary:
	if _sim == null or _sim.location == null:
		return {}
	var name_for_offset := _sim.identity.citizen_name if _sim.identity != null else citizen_name
	return CitizenLocation.resolve_navigation_points(
			building, world, name_for_offset, global_position)


func enter_building(building: Building, world: Node = null, emit_log: bool = true) -> void:
	if building == null or _sim == null or _sim.location == null:
		return
	clear_rest_pose(true)
	if current_location != building:
		release_reserved_benches(world, current_location)
	var name_for_offset := _sim.identity.citizen_name if _sim.identity != null else citizen_name
	var nav_points := CitizenLocation.resolve_navigation_points(
			building, world, name_for_offset, global_position)
	var entry_pos := global_position
	stop_travel()
	current_location = building
	var is_outdoor: bool = building.has_method("is_outdoor_destination") and building.is_outdoor_destination()
	if is_outdoor:
		_sim.location.clear_inside_building()
	else:
		if nav_points.has("spawn"):
			_set_position_grounded(nav_points["spawn"] as Vector3)
		_sim.location.set_inside_building(building)
	if building.has_method("on_citizen_entered"):
		building.on_citizen_entered(self)
	_set_interior_presence(not is_outdoor)
	if emit_log and SimLoggerScript != null:
		SimLoggerScript.log("[Citizen %s] Entered %s at %s" % [
				_get_log_name(),
				building.get_display_name() if building.has_method("get_display_name") else "?",
				_fmt_v3(entry_pos)])


func leave_current_location(world: Node = null, emit_log: bool = true) -> void:
	if _sim == null:
		return
	if is_inside_building():
		exit_current_building(world)
		return
	if current_location == null:
		return

	var exit_building := current_location
	clear_rest_pose(true)
	release_reserved_benches(world, exit_building)
	var name_for_offset := _sim.identity.citizen_name if _sim.identity != null else citizen_name
	var nav_points := CitizenLocation.resolve_navigation_points(
			exit_building, world, name_for_offset, global_position)
	var is_outdoor: bool = exit_building.has_method("is_outdoor_destination") \
			and exit_building.is_outdoor_destination()
	var exit_pos: Vector3 = nav_points.get("spawn",
			nav_points.get("access", global_position)) as Vector3
	if is_outdoor:
		_set_position_grounded(exit_pos)
	current_location = null
	if exit_building.has_method("on_citizen_exited"):
		exit_building.on_citizen_exited(self)
	if emit_log and SimLoggerScript != null:
		SimLoggerScript.log("[Citizen %s] Left %s at %s" % [
				_get_log_name(),
				exit_building.get_display_name() if exit_building.has_method("get_display_name") else "?",
				_fmt_v3(global_position)])


func exit_current_building(world: Node = null) -> void:
	if _sim == null or _sim.location == null:
		return
	var exit_building := _sim.location.get_inside_building()
	if exit_building == null:
		return

	clear_rest_pose(true)
	var name_for_offset := _sim.identity.citizen_name if _sim.identity != null else citizen_name
	var nav_points := CitizenLocation.resolve_navigation_points(
			exit_building, world, name_for_offset, global_position)
	var exit_pos: Vector3 = nav_points.get("spawn", global_position) as Vector3

	_sim.location.clear_inside_building()
	if exit_building.has_method("on_citizen_exited"):
		exit_building.on_citizen_exited(self)
	_set_interior_presence(false)
	_set_position_grounded(exit_pos)
	if SimLoggerScript != null:
		SimLoggerScript.log("[Citizen %s] Exited %s at %s" % [
				_get_log_name(),
				exit_building.get_display_name() if exit_building.has_method("get_display_name") else "?",
				_fmt_v3(global_position)])


# ----------------------------- presence toggle -----------------------------
# Hide/show + collision toggle. Simpler than legacy Citizen.gd because the
# new stack has no Sensor-Area/Click-Area sub-nodes that need disabling.

func _set_interior_presence(hidden: bool) -> void:
	_interior_presence_hidden = hidden
	if hidden:
		hide()
		velocity = Vector3.ZERO
		collision_layer = 0
		collision_mask = 0
	else:
		show()
		collision_layer = _saved_collision_layer
		collision_mask = _saved_collision_mask


func _set_position_grounded(pos: Vector3) -> void:
	# Simple variant for the new stack — the legacy Citizen.gd routed this
	# through a Locomotion helper that did snap-to-ground. Movement-layer
	# helper will replace this when we extract it.
	global_position = pos
	velocity = Vector3.ZERO


func _get_log_name() -> String:
	if _sim != null and _sim.identity != null:
		return _sim.identity.citizen_name
	return citizen_name


static func _fmt_v3(v: Vector3) -> String:
	return "(%.2f,%.2f,%.2f)" % [v.x, v.y, v.z]


# ========================================================================
# Trace state — delegates to CitizenTraceState. Method name intentionally
# starts with underscore so the existing `has_method`-guarded caller in
# `CitizenAgent.gd:36` keeps working without modification.
# ========================================================================

func _update_trace_navigation_state(reason: String, desired_dir: Vector3, move_dir: Vector3) -> void:
	if _sim == null or _sim.trace == null:
		return
	_sim.trace.update_navigation(reason, desired_dir, move_dir)


# ========================================================================
# Debug logging — delegates to CitizenDebugFacade. Kept on the Facade as
# `debug_log` / `debug_log_once_per_day` because callers (Actions, GOAP,
# CitizenPlanner) call those names directly.
# ========================================================================

func debug_log(message: String) -> void:
	if _sim == null or _sim.debug_facade == null:
		return
	_sim.debug_facade.emit_log(_get_log_name(), message)


func debug_log_once_per_day(key: String, message: String) -> void:
	if _sim == null or _sim.debug_facade == null:
		return
	# `_sim.world` is set via `set_world_ref` from CitizenAgent before any
	# action runs — null-safe path covers headless tests.
	_sim.debug_facade.log_once_per_day(_sim.world, _get_log_name(), key, message)


## Compact one-line per-citizen summary for `RuntimeDebugLogger`. Reduced
## compared to legacy `get_trace_debug_summary()`: omits the four sensor-ray
## fields (no equivalent in the new stack) and the crowd/repath counters
## (live in not-yet-extracted Scheduler/LocalPerception).
func get_trace_debug_summary() -> String:
	var n := _get_log_name()
	var inside := "-"
	if _sim != null and _sim.location != null and _sim.location.is_inside():
		var b := _sim.location.get_inside_building()
		if b != null and b.has_method("get_display_name"):
			inside = b.get_display_name()
	var loc := "-"
	if current_location != null and current_location.has_method("get_display_name"):
		loc = current_location.get_display_name()
	var reason := _sim.trace.last_decision_reason if _sim != null and _sim.trace != null else "idle"
	var desired := _sim.trace.last_desired_dir if _sim != null and _sim.trace != null else Vector3.ZERO
	var move := _sim.trace.last_move_dir if _sim != null and _sim.trace != null else Vector3.ZERO
	return "citizen=%s pos=%s vel=%s on_floor=%s travelling=%s location=%s inside=%s decision=%s desired=%s move=%s" % [
		n,
		CitizenTraceState.fmt_v3(global_position),
		CitizenTraceState.fmt_v3(velocity),
		str(is_on_floor()),
		str(is_travelling()),
		loc,
		inside,
		reason,
		CitizenTraceState.fmt_v3(desired),
		CitizenTraceState.fmt_v3(move),
	]


# ========================================================================
# Sim API surface — forwarded into CitizenSimulation/components.
# Method names match legacy `Citizen.gd` so existing callers can use this
# Facade as a drop-in once they are pointed at it.
# ========================================================================

func set_world_ref(p_world: Node) -> void:
	if _sim != null:
		_sim.set_world(p_world)


func sim_tick(p_world: Node) -> void:
	if _sim != null:
		_sim.tick(p_world)


# --- Rest pose (delegated to CitizenRestPose) ---

func has_active_rest_pose() -> bool:
	return _sim != null and _sim.rest_pose != null and _sim.rest_pose.is_active()


func set_rest_pose(target_pos: Vector3, yaw: float = 0.0) -> void:
	if _sim == null or _sim.rest_pose == null:
		return
	_sim.rest_pose.set_pose(target_pos, yaw)


func clear_rest_pose(snap_to_ground: bool = false) -> void:
	if _sim == null or _sim.rest_pose == null:
		return
	_sim.rest_pose.clear(snap_to_ground)


func apply_rest_pose() -> void:
	if _sim == null or _sim.rest_pose == null:
		return
	_sim.rest_pose.apply()
