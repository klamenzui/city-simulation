class_name CitizenSimulation
extends RefCounted

## Top-level orchestrator for the Sim layer of the new Citizen stack.
##
## Holds every Sim component as a member, dispatches `tick()` to them in
## a stable order, and exposes a single API surface for the Facade
## (`CitizenFacade.gd`) to forward into.
##
## Migration note: this class starts small — only the components that have
## been extracted from old `Citizen.gd` are wired in. Each tick adds whatever
## components are present; missing ones are no-ops. See `Sim/MIGRATION.md`
## for the full roadmap.

var owner_node: Node = null
var world: Node = null

# Components — created in `_init`, never reseated. Nullable until extraction.
var rest_pose: CitizenRestPose = null
var identity: CitizenIdentity = null
var location: CitizenLocation = null
var bench_reservation: CitizenBenchReservation = null
var trace: CitizenTraceState = null
var debug_facade: CitizenDebugFacade = null
var lod: CitizenLodComponent = null
var scheduler: CitizenScheduler = null
var manual_control: CitizenManualControl = null


func _init(p_owner: Node) -> void:
	owner_node = p_owner
	if p_owner is Node3D:
		rest_pose = CitizenRestPose.new(p_owner as Node3D)
	identity = CitizenIdentity.new()
	location = CitizenLocation.new()
	bench_reservation = CitizenBenchReservation.new(p_owner)
	trace = CitizenTraceState.new()
	debug_facade = CitizenDebugFacade.new()
	lod = CitizenLodComponent.new()
	scheduler = CitizenScheduler.new()
	manual_control = CitizenManualControl.new()


## Set by `set_world_ref` from the Facade. Components that need the world
## (LOD, Scheduler) read from here.
func set_world(p_world: Node) -> void:
	world = p_world


## Per-sim-tick dispatch. Called from `Citizen.sim_tick(world)` (Facade →
## CitizenAgent path). Today a placeholder; each new component adds its own
## `tick()` call here.
func tick(p_world: Node) -> void:
	world = p_world
	# Future:
	# scheduler.tick(p_world)
	# lod.tick(p_world)
	# location.tick(p_world)
	pass
