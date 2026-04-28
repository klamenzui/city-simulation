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
# Location API — delegates to CitizenLocation, orchestrates state on the
# CharacterBody3D side (position, presence toggle, building callbacks).
#
# Stubs (TODO when their components migrate):
#   - bench-reservation release (Bench component, not yet extracted)
#   - trace navigation state (TraceState component, not yet extracted)
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
	# TODO: bench release — release_reserved_benches(world, current_location)
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
	# TODO: bench release — release_reserved_benches(world, exit_building)
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
