extends Node3D

@onready var world: World = $World
@onready var _city_camera: CityBuilderCamera = $Camera3D as CityBuilderCamera

const CITIZEN_COUNT := 15
const SELECTED_CITIZEN_TRACE_INTERVAL_SEC := 1.0
const ALL_CITIZEN_TRACE_INTERVAL_SEC := 0.5
const SEARCH_RESULT_LIMIT := 12
const SceneBootstrapControllerScript = preload("res://Simulation/Bootstrap/SceneBootstrapController.gd")
const BalanceConfig = preload("res://Simulation/Config/BalanceConfig.gd")
const RuntimeDebugLoggerScript = preload("res://Simulation/Debug/RuntimeDebugLogger.gd")
const SelectionDebugControllerScript = preload("res://Simulation/Debug/SelectionDebugController.gd")
const SelectionStateControllerScript = preload("res://Simulation/Debug/SelectionStateController.gd")
const BuildingStatusStyleResolverScript = preload("res://Simulation/UI/BuildingStatusStyleResolver.gd")
const HudOverlayControllerScript = preload("res://Simulation/UI/HudOverlayController.gd")
const SimulationInteractionControllerScript = preload("res://Simulation/UI/SimulationInteractionController.gd")
const SimulationHudControllerScript = preload("res://Simulation/UI/SimulationHudController.gd")
const BuildingStatusBadgeControllerScript = preload("res://Simulation/UI/BuildingStatusBadgeController.gd")
const SimLogger = preload("res://Simulation/Logging/SimLogger.gd")
const BUILDING_OVERVIEW_REFRESH_INTERVAL_SEC := 0.5

var _building_status_style_resolver = null
var _interaction_controller = null
var _hud_controller = null
var _hud_overlay_controller = null
var _selection_state_controller = null
var _runtime_debug_logger = null
var _selection_debug_controller = null
var _building_status_badge_controller = null
var _enable_all_citizen_trace: bool = false
var _enable_map_snapshot_log: bool = false

func _ready() -> void:
	SimLogger.start_new_session(false)
	get_viewport().physics_object_picking = true
	_load_debug_runtime_flags()

	_setup_world_systems()
	_setup_runtime_debug_logger()
	_setup_selection_debug_controller()
	_setup_building_status_style_resolver()
	_setup_building_status_badge_controller()
	_setup_interaction_controller()
	_bind_building_clicks()
	_spawn_citizens()
	call_deferred("_log_initial_debug_snapshot")
	_build_hud()
	_setup_selection_state_controller()

func _load_debug_runtime_flags() -> void:
	_enable_all_citizen_trace = BalanceConfig.get_bool("debug.enable_all_citizen_trace", false)
	_enable_map_snapshot_log = BalanceConfig.get_bool("debug.enable_map_snapshot_log", false)

func _process(delta: float) -> void:
	var selected_citizen: Citizen = null
	var selected_building: Building = null
	if _selection_state_controller != null:
		_selection_state_controller.ensure_valid_control_target()
		selected_citizen = _selection_state_controller.get_selected_citizen()
		selected_building = _selection_state_controller.get_selected_building()
	if _runtime_debug_logger != null:
		_runtime_debug_logger.update(delta, selected_citizen)
	if _selection_debug_controller != null:
		_selection_debug_controller.update(selected_citizen, selected_building, world)
	if _building_status_badge_controller != null:
		_building_status_badge_controller.update(selected_building, world)
	if _hud_overlay_controller != null:
		_hud_overlay_controller.update(delta)
	if _interaction_controller != null:
		_interaction_controller.update(delta)

func _setup_world_systems() -> void:
	SceneBootstrapControllerScript.setup_scene(self, world)

func _setup_runtime_debug_logger() -> void:
	_runtime_debug_logger = RuntimeDebugLoggerScript.new()
	_runtime_debug_logger.setup(
		self,
		world,
		_enable_all_citizen_trace,
		_enable_map_snapshot_log,
		SELECTED_CITIZEN_TRACE_INTERVAL_SEC,
		ALL_CITIZEN_TRACE_INTERVAL_SEC
	)

func _setup_selection_debug_controller() -> void:
	_selection_debug_controller = SelectionDebugControllerScript.new()
	_selection_debug_controller.setup(self)

func _setup_building_status_style_resolver() -> void:
	_building_status_style_resolver = BuildingStatusStyleResolverScript.new()

func _setup_interaction_controller() -> void:
	_interaction_controller = SimulationInteractionControllerScript.new()
	_interaction_controller.setup(self, world)

func _setup_building_status_badge_controller() -> void:
	if _building_status_style_resolver == null:
		_setup_building_status_style_resolver()
	_building_status_badge_controller = BuildingStatusBadgeControllerScript.new()
	_building_status_badge_controller.setup(
		self,
		_city_camera,
		Callable(_building_status_style_resolver, "get_badge_color"),
		Callable(_building_status_style_resolver, "get_badge_background"),
		Callable(_building_status_style_resolver, "get_badge_icon"),
		_building_status_style_resolver.get_default_border_color()
	)

func _setup_selection_state_controller() -> void:
	_selection_state_controller = SelectionStateControllerScript.new()
	_selection_state_controller.setup(
		world,
		_city_camera,
		_interaction_controller.get_debug_panel() if _interaction_controller != null else null,
		_hud_controller,
		_runtime_debug_logger,
		_selection_debug_controller,
		_building_status_badge_controller
	)
	if _interaction_controller != null:
		_interaction_controller.bind_selection_state(_selection_state_controller, _hud_overlay_controller)

func _bind_building_clicks() -> void:
	if _interaction_controller == null:
		return
	var building_clicked_cb := Callable(_interaction_controller, "handle_building_clicked")
	for building in world.buildings:
		if building == null:
			continue
		if not building.clicked.is_connected(building_clicked_cb):
			building.clicked.connect(building_clicked_cb)

func _spawn_citizens() -> void:
	var citizen_count := BalanceConfig.get_int("simulation.initial_citizen_count", CITIZEN_COUNT)
	var spawned := CitizenFactory.spawn_citizens(self, world, citizen_count)
	if _interaction_controller == null:
		return
	for citizen in spawned:
		var cb := Callable(_interaction_controller, "handle_citizen_clicked").bind(citizen)
		if not citizen.clicked.is_connected(cb):
			citizen.clicked.connect(cb)

func _log_initial_debug_snapshot() -> void:
	if _runtime_debug_logger != null:
		_runtime_debug_logger.log_initial_snapshot()

func _build_hud() -> void:
	_hud_controller = SimulationHudControllerScript.new()
	_hud_controller.setup(
		self,
		world,
		Callable(_interaction_controller, "on_pause_pressed"),
		Callable(_interaction_controller, "on_speed_pressed"),
		Callable(_interaction_controller, "on_building_overview_pressed")
	)

	var canvas: CanvasLayer = _hud_controller.get_canvas()
	if canvas == null:
		return

	_hud_overlay_controller = HudOverlayControllerScript.new()
	_hud_overlay_controller.setup(
		world,
		_city_camera,
		canvas,
		_hud_controller.get_building_overview_button(),
		Callable(_interaction_controller, "handle_citizen_clicked"),
		Callable(_interaction_controller, "handle_building_clicked"),
		Callable(_building_status_style_resolver, "get_badge_color"),
		Callable(_building_status_style_resolver, "get_badge_icon"),
		Callable(_interaction_controller, "mark_ui_interacted"),
		SEARCH_RESULT_LIMIT,
		BUILDING_OVERVIEW_REFRESH_INTERVAL_SEC
	)

func _input(event: InputEvent) -> void:
	if _interaction_controller != null and _interaction_controller.handle_input(event):
		get_viewport().set_input_as_handled()
