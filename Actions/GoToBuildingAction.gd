extends Action
class_name GoToBuildingAction

const SimLogger = preload("res://Simulation/Logging/SimLogger.gd")

var target: Building
var travel_minutes: int = 20
var _arrival_target: Vector3 = Vector3.ZERO
var _travel_failed: bool = false

const MAX_TRAVEL_SIM_MIN := 240

func _init(_target: Building = null, _travel: int = 20) -> void:
	super()
	label = "GoTo"
	target = _target
	travel_minutes = _travel

func start(world: World, citizen: Citizen) -> void:
	super.start(world, citizen)
	_travel_failed = false
	if target == null:
		finished = true
		return

	# Use the pedestrian access point so citizens stop at the sidewalk
	# instead of trying to clip into the building footprint.
	_arrival_target = target.get_entrance_pos()
	if world != null and world.has_method("get_pedestrian_access_point"):
		_arrival_target = world.get_pedestrian_access_point(_arrival_target, target)
	var source_building := citizen.current_location
	var source_spawn := citizen.get_debug_exit_spawn_pos(source_building, world) if source_building != null and citizen.has_method("get_debug_exit_spawn_pos") else citizen.global_position
	SimLogger.log("[Citizen %s] GoTo route start=%s start_pos=%s exit=%s -> target=%s entry=%s arrival=%s" % [
		citizen.citizen_name,
		_format_building_endpoint(source_building, world, citizen.global_position),
		_format_point(citizen.global_position),
		_format_exit_endpoint(source_building, world, citizen.global_position, source_spawn),
		_format_building_endpoint(target, world, citizen.global_position),
		_format_entry_endpoint(target, world),
		_format_point(_arrival_target)
	])
	var travel_started := citizen.begin_travel_to(_arrival_target, target)
	if not travel_started:
		_travel_failed = true
		var source_label := citizen.current_location.get_display_name() if citizen.current_location != null else "current position"
		SimLogger.log("[Citizen %s] No pedestrian route to %s. from=%s start=%s end=%s | %s" % [
			citizen.citizen_name,
			target.get_display_name(),
			source_label,
			_format_point(citizen.global_position),
			_format_point(_arrival_target),
			citizen.get_job_debug_summary() if citizen.has_method("get_job_debug_summary") else "job=unknown"
		])
		finished = true
		return

	if world != null and world.has_method("describe_pedestrian_path"):
		SimLogger.log("[Citizen %s] GoTo path %s" % [
			citizen.citizen_name,
			world.describe_pedestrian_path(citizen.get_debug_travel_route_points())
		])

	citizen.current_location = null

	# Path movement now drives completion; keep action timer disabled.
	remaining_minutes = 0

func tick(world: World, citizen: Citizen, dt: int) -> void:
	super.tick(world, citizen, dt)
	if target == null:
		finished = true
		return
	if citizen.has_reached_travel_target():
		finished = true
		return
	if elapsed_minutes >= MAX_TRAVEL_SIM_MIN:
		finished = true

func finish(world: World, citizen: Citizen) -> void:
	if target == null:
		return
	if _travel_failed:
		citizen.stop_travel()
		return
	var reached_target := citizen.has_reached_travel_target()
	citizen.stop_travel()
	if not reached_target:
		return
	citizen.enter_building(target, world)

func _format_point(pos: Vector3) -> String:
	return "(%.1f, %.1f, %.1f)" % [pos.x, pos.y, pos.z]

func _format_building_endpoint(building: Building, world: World, fallback_pos: Vector3) -> String:
	if building == null:
		return "outside pos=%s" % _format_point(fallback_pos)
	if building.has_method("get_navigation_debug_summary"):
		return "%s %s" % [building.get_display_name(), building.get_navigation_debug_summary(world)]
	return "%s entrance=%s" % [building.get_display_name(), _format_point(building.get_entrance_pos())]

func _format_exit_endpoint(building: Building, world: World, fallback_pos: Vector3, spawn_pos: Vector3) -> String:
	if building == null:
		return "outside pos=%s" % _format_point(fallback_pos)
	var exit_access := building.get_entrance_pos()
	if world != null and world.has_method("get_pedestrian_access_point"):
		exit_access = world.get_pedestrian_access_point(building.get_entrance_pos(), building)
	return "%s entrance=%s access=%s spawn=%s" % [
		building.get_display_name(),
		_format_point(building.get_entrance_pos()),
		_format_point(exit_access),
		_format_point(spawn_pos)
	]

func _format_entry_endpoint(building: Building, world: World) -> String:
	if building == null:
		return "none"
	var entry_access := building.get_entrance_pos()
	if world != null and world.has_method("get_pedestrian_access_point"):
		entry_access = world.get_pedestrian_access_point(building.get_entrance_pos(), building)
	return "%s entrance=%s access=%s" % [
		building.get_display_name(),
		_format_point(building.get_entrance_pos()),
		_format_point(entry_access)
	]
