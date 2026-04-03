extends Node3D

@onready var world: World = $World
@onready var _city_camera: CityBuilderCamera = $Camera3D as CityBuilderCamera

const CITIZEN_COUNT := 15
const SELECTED_CITIZEN_TRACE_INTERVAL_SEC := 1.0
const ALL_CITIZEN_TRACE_INTERVAL_SEC := 0.5
const SEARCH_RESULT_LIMIT := 12
const SceneBootstrapControllerScript = preload("res://Simulation/Bootstrap/SceneBootstrapController.gd")
const SceneRuntimeControllerScript = preload("res://Simulation/Bootstrap/SceneRuntimeController.gd")
const BalanceConfig = preload("res://Simulation/Config/BalanceConfig.gd")
const SimLogger = preload("res://Simulation/Logging/SimLogger.gd")
const BUILDING_OVERVIEW_REFRESH_INTERVAL_SEC := 0.5

var _runtime_controller = null
var _enable_all_citizen_trace: bool = false
var _enable_map_snapshot_log: bool = false

func _ready() -> void:
	SimLogger.start_new_session(false)
	get_viewport().physics_object_picking = true
	_load_debug_runtime_flags()

	SceneBootstrapControllerScript.setup_scene(self, world)
	_runtime_controller = SceneRuntimeControllerScript.new()
	_runtime_controller.setup(
		self,
		world,
		_city_camera,
		_enable_all_citizen_trace,
		_enable_map_snapshot_log,
		SELECTED_CITIZEN_TRACE_INTERVAL_SEC,
		ALL_CITIZEN_TRACE_INTERVAL_SEC,
		SEARCH_RESULT_LIMIT,
		BUILDING_OVERVIEW_REFRESH_INTERVAL_SEC,
		BalanceConfig.get_int("simulation.initial_citizen_count", CITIZEN_COUNT)
	)
	call_deferred("_log_initial_debug_snapshot")

func _load_debug_runtime_flags() -> void:
	_enable_all_citizen_trace = BalanceConfig.get_bool("debug.enable_all_citizen_trace", false)
	_enable_map_snapshot_log = BalanceConfig.get_bool("debug.enable_map_snapshot_log", false)

func _process(delta: float) -> void:
	if _runtime_controller != null:
		_runtime_controller.update(delta)

func _log_initial_debug_snapshot() -> void:
	if _runtime_controller != null:
		_runtime_controller.log_initial_debug_snapshot()

func _input(event: InputEvent) -> void:
	if _runtime_controller != null:
		_runtime_controller.handle_input(event)
