extends RefCounted
class_name SceneRuntimeController

const RuntimeDebugLoggerScript = preload("res://Simulation/Debug/RuntimeDebugLogger.gd")
const SelectionDebugControllerScript = preload("res://Simulation/Debug/SelectionDebugController.gd")
const SelectionStateControllerScript = preload("res://Simulation/Debug/SelectionStateController.gd")
const BuildingStatusStyleResolverScript = preload("res://Simulation/UI/BuildingStatusStyleResolver.gd")
const HudOverlayControllerScript = preload("res://Simulation/UI/HudOverlayController.gd")
const SimulationInteractionControllerScript = preload("res://Simulation/UI/SimulationInteractionController.gd")
const SimulationHudControllerScript = preload("res://Simulation/UI/SimulationHudController.gd")
const CoordinatePickerControllerScript = preload("res://Simulation/UI/CoordinatePickerController.gd")
const BuildingStatusBadgeControllerScript = preload("res://Simulation/UI/BuildingStatusBadgeController.gd")
const CitizenSimulationLodControllerScript = preload("res://Simulation/Citizens/CitizenSimulationLodController.gd")
const CitizenConversationManagerScript = preload("res://Simulation/Conversation/CitizenConversationManager.gd")
const LocalDialogueRuntimeServiceScript = preload("res://Simulation/AI/LocalDialogueRuntimeService.gd")

var owner_node: Node = null
var world: World = null
var city_camera: Camera3D = null
var runtime_debug_logger = null
var selection_debug_controller = null
var building_status_style_resolver = null
var interaction_controller = null
var building_status_badge_controller = null
var hud_controller = null
var hud_overlay_controller = null
var coordinate_picker_controller = null
var selection_state_controller = null
var citizen_lod_controller = null
var citizen_conversation_manager = null
var dialogue_runtime_service = null
var multiplayer_session = null

func setup(
	owner_ref: Node,
	world_ref: World,
	camera_ref: Camera3D,
	enable_all_citizen_trace: bool,
	enable_map_snapshot_log: bool,
	selected_trace_interval_sec: float,
	all_trace_interval_sec: float,
	search_result_limit: int,
	building_overview_refresh_interval_sec: float,
	initial_citizen_count: int,
	multiplayer_session_ref = null
) -> void:
	owner_node = owner_ref
	world = world_ref
	city_camera = camera_ref
	multiplayer_session = multiplayer_session_ref
	if world != null and world.has_method("set_citizen_spawn_parent"):
		world.set_citizen_spawn_parent(owner_node)
	var headless_runtime := _is_headless_runtime()

	_setup_runtime_debug_logger(
		enable_all_citizen_trace,
		enable_map_snapshot_log,
		selected_trace_interval_sec,
		all_trace_interval_sec
	)
	_spawn_citizens(initial_citizen_count)
	if world != null and world.has_method("capture_population_target_floor"):
		world.capture_population_target_floor()
	_setup_selection_state_controller()
	_setup_dialogue_runtime(headless_runtime)
	_setup_conversation_manager()
	_setup_citizen_lod_controller()
	if headless_runtime:
		return
	_setup_selection_debug_controller()
	_setup_building_status_style_resolver()
	_setup_interaction_controller()
	_bind_world_citizen_registration()
	_bind_citizen_clicks()
	_setup_building_status_badge_controller()
	_bind_building_clicks()
	_build_hud(search_result_limit, building_overview_refresh_interval_sec)
	_setup_coordinate_picker()
	if selection_state_controller != null:
		selection_state_controller.setup(
			world,
			city_camera,
			interaction_controller.get_debug_panel() if interaction_controller != null else null,
			hud_controller,
			runtime_debug_logger,
			selection_debug_controller,
			building_status_badge_controller
		)
	if interaction_controller != null:
		interaction_controller.bind_selection_state(selection_state_controller, hud_overlay_controller)

func update(delta: float) -> void:
	var selected_citizen = null
	var selected_building = null
	if selection_state_controller != null:
		selection_state_controller.ensure_valid_control_target()
		selected_citizen = selection_state_controller.get_selected_citizen()
		selected_building = selection_state_controller.get_selected_building()
	if dialogue_runtime_service != null:
		dialogue_runtime_service.update(delta)
	if citizen_conversation_manager != null:
		citizen_conversation_manager.update(delta)
	if citizen_lod_controller != null:
		citizen_lod_controller.update(delta)
	if runtime_debug_logger != null:
		runtime_debug_logger.update(delta, selected_citizen)
	if selection_debug_controller != null:
		selection_debug_controller.update(selected_citizen, selected_building, world)
	if building_status_badge_controller != null:
		building_status_badge_controller.update(selected_building, world)
	if hud_controller != null and hud_controller.has_method("update"):
		hud_controller.update(delta)
	if hud_overlay_controller != null:
		hud_overlay_controller.update(delta)
	if interaction_controller != null:
		interaction_controller.update(delta)

func handle_input(event: InputEvent) -> bool:
	# Coordinate picker has priority — when active it consumes left-clicks so
	# the standard interaction controller does not also try to select citizens
	# or buildings on the same click.
	if coordinate_picker_controller != null and coordinate_picker_controller.handle_input(event):
		var picker_viewport := owner_node.get_viewport() if owner_node != null else null
		if picker_viewport != null:
			picker_viewport.set_input_as_handled()
		return true

	if interaction_controller == null:
		return false
	if not interaction_controller.handle_input(event):
		return false

	var viewport := owner_node.get_viewport() if owner_node != null else null
	if viewport != null:
		viewport.set_input_as_handled()
	return true

func log_initial_debug_snapshot() -> void:
	if runtime_debug_logger != null:
		runtime_debug_logger.log_initial_snapshot()

func _is_headless_runtime() -> bool:
	return DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server")

func _setup_runtime_debug_logger(
	enable_all_citizen_trace: bool,
	enable_map_snapshot_log: bool,
	selected_trace_interval_sec: float,
	all_trace_interval_sec: float
) -> void:
	runtime_debug_logger = RuntimeDebugLoggerScript.new()
	runtime_debug_logger.setup(
		owner_node,
		world,
		enable_all_citizen_trace,
		enable_map_snapshot_log,
		selected_trace_interval_sec,
		all_trace_interval_sec
	)

func _setup_selection_debug_controller() -> void:
	selection_debug_controller = SelectionDebugControllerScript.new()
	selection_debug_controller.setup(owner_node)

func _setup_building_status_style_resolver() -> void:
	building_status_style_resolver = BuildingStatusStyleResolverScript.new()

func _setup_interaction_controller() -> void:
	interaction_controller = SimulationInteractionControllerScript.new()
	interaction_controller.setup(owner_node, world, multiplayer_session)
	if dialogue_runtime_service != null and interaction_controller.has_method("bind_dialogue_runtime_service"):
		interaction_controller.bind_dialogue_runtime_service(dialogue_runtime_service)
	if citizen_conversation_manager != null and interaction_controller.has_method("bind_conversation_manager"):
		interaction_controller.bind_conversation_manager(citizen_conversation_manager)

func _setup_building_status_badge_controller() -> void:
	if building_status_style_resolver == null:
		_setup_building_status_style_resolver()
	building_status_badge_controller = BuildingStatusBadgeControllerScript.new()
	building_status_badge_controller.setup(
		owner_node,
		city_camera,
		Callable(building_status_style_resolver, "get_badge_color"),
		Callable(building_status_style_resolver, "get_badge_background"),
		Callable(building_status_style_resolver, "get_badge_icon"),
		building_status_style_resolver.get_default_border_color()
	)

func _build_hud(search_result_limit: int, building_overview_refresh_interval_sec: float) -> void:
	hud_controller = SimulationHudControllerScript.new()
	hud_controller.setup(
		owner_node,
		world,
		Callable(interaction_controller, "on_pause_pressed"),
		Callable(interaction_controller, "on_speed_pressed"),
		Callable(interaction_controller, "on_building_overview_pressed"),
		Callable(interaction_controller, "on_citizen_overview_pressed"),
		Callable(interaction_controller, "on_economy_overview_pressed"),
		Callable(interaction_controller, "on_search_overview_pressed"),
		Callable(interaction_controller, "on_debug_tools_pressed"),
		Callable(interaction_controller, "on_player_control_pressed"),
		Callable(interaction_controller, "on_ai_runtime_pressed"),
		multiplayer_session
	)
	if dialogue_runtime_service != null and hud_controller.has_method("bind_dialogue_runtime_service"):
		hud_controller.bind_dialogue_runtime_service(dialogue_runtime_service)

	var canvas: CanvasLayer = hud_controller.get_canvas()
	if canvas == null:
		return

	hud_overlay_controller = HudOverlayControllerScript.new()
	hud_overlay_controller.setup(
		world,
		city_camera,
		canvas,
		hud_controller.get_building_overview_button(),
		hud_controller.get_citizen_overview_button(),
		hud_controller.get_economy_overview_button(),
		hud_controller.get_search_overview_button(),
		Callable(interaction_controller, "handle_citizen_clicked"),
		Callable(interaction_controller, "handle_building_clicked"),
		Callable(building_status_style_resolver, "get_badge_color"),
		Callable(building_status_style_resolver, "get_badge_icon"),
		Callable(interaction_controller, "mark_ui_interacted"),
		search_result_limit,
		building_overview_refresh_interval_sec
	)

func _setup_coordinate_picker() -> void:
	if hud_controller == null or owner_node == null:
		return
	var canvas: CanvasLayer = hud_controller.get_canvas()
	if canvas == null:
		return
	coordinate_picker_controller = CoordinatePickerControllerScript.new()
	coordinate_picker_controller.setup(owner_node, world, city_camera, canvas,
			hud_controller.get_debug_tools_button())
	if interaction_controller != null:
		interaction_controller.bind_coordinate_picker(coordinate_picker_controller)


func _setup_selection_state_controller() -> void:
	if selection_state_controller != null:
		return
	selection_state_controller = SelectionStateControllerScript.new()
	selection_state_controller.setup(
		world,
		city_camera,
		interaction_controller.get_debug_panel() if interaction_controller != null else null,
		hud_controller,
		runtime_debug_logger,
		selection_debug_controller,
		building_status_badge_controller
	)
	if interaction_controller != null:
		interaction_controller.bind_selection_state(selection_state_controller, hud_overlay_controller)

func _setup_citizen_lod_controller() -> void:
	if world != null and world.has_method("has_simulation_authority") and not world.has_simulation_authority():
		return
	if selection_state_controller == null:
		return
	citizen_lod_controller = CitizenSimulationLodControllerScript.new()
	citizen_lod_controller.setup(world, city_camera, selection_state_controller)

func _setup_dialogue_runtime(headless_runtime: bool) -> void:
	dialogue_runtime_service = LocalDialogueRuntimeServiceScript.new()
	owner_node.add_child(dialogue_runtime_service)
	dialogue_runtime_service.setup({}, headless_runtime)

func _setup_conversation_manager() -> void:
	if selection_state_controller == null:
		return
	citizen_conversation_manager = CitizenConversationManagerScript.new()
	citizen_conversation_manager.setup(world, city_camera, selection_state_controller)
	if dialogue_runtime_service != null and citizen_conversation_manager.has_method("bind_dialogue_runtime"):
		citizen_conversation_manager.bind_dialogue_runtime(dialogue_runtime_service)

func _bind_building_clicks() -> void:
	if interaction_controller == null:
		return
	var building_clicked_cb := Callable(interaction_controller, "handle_building_clicked")
	var clickable_buildings := _get_clickable_scene_buildings()
	for building in clickable_buildings:
		if building == null:
			continue
		if not building.clicked.is_connected(building_clicked_cb):
			building.clicked.connect(building_clicked_cb)

func _get_clickable_scene_buildings() -> Array[Building]:
	var result: Array[Building] = []
	if world != null:
		for building in world.buildings:
			if building != null and not result.has(building):
				result.append(building)
	var tree := owner_node.get_tree() if owner_node != null else null
	if tree == null:
		return result
	for node in tree.get_nodes_in_group("buildings"):
		if node is Building and not result.has(node):
			result.append(node as Building)
	return result

func _bind_citizen_clicks() -> void:
	if interaction_controller == null:
		return
	for citizen in world.citizens:
		if citizen == null:
			continue
		_bind_citizen_click(citizen)

func _bind_citizen_click(citizen: Citizen) -> void:
	if interaction_controller == null or citizen == null:
		return
	var clicked_cb := Callable(interaction_controller, "handle_citizen_clicked").bind(citizen)
	if not citizen.clicked.is_connected(clicked_cb):
		citizen.clicked.connect(clicked_cb)

func _bind_world_citizen_registration() -> void:
	if world == null or interaction_controller == null:
		return
	var registered_cb := Callable(self, "_on_world_citizen_registered")
	if not world.citizen_registered.is_connected(registered_cb):
		world.citizen_registered.connect(registered_cb)

func _on_world_citizen_registered(citizen: Citizen) -> void:
	_bind_citizen_click(citizen)

func _spawn_citizens(initial_citizen_count: int) -> void:
	var spawned := CitizenFactory.spawn_citizens(owner_node, world, initial_citizen_count)
	if interaction_controller == null:
		return
	for citizen in spawned:
		_bind_citizen_click(citizen)
