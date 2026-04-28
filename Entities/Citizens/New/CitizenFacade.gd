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

var _sim: CitizenSimulation = null


func _ready() -> void:
	super._ready()
	_sim = CitizenSimulation.new(self)


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
