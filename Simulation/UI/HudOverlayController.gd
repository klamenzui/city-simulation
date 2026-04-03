extends RefCounted
class_name HudOverlayController

const BuildingOverviewControllerScript = preload("res://Simulation/UI/BuildingOverviewController.gd")
const EntitySearchControllerScript = preload("res://Simulation/UI/EntitySearchController.gd")

var world: World = null
var city_camera: CityBuilderCamera = null
var canvas: CanvasLayer = null
var search_input: LineEdit = null
var search_results_list: ItemList = null
var building_overview_controller = null
var search_controller = null

func setup(
	world_ref: World,
	camera_ref: CityBuilderCamera,
	canvas_ref: CanvasLayer,
	building_overview_button_ref: Button,
	select_citizen: Callable,
	select_building: Callable,
	status_color_resolver: Callable,
	status_icon_resolver: Callable,
	mark_ui_interacted: Callable,
	search_result_limit: int = 12,
	building_overview_refresh_interval_sec: float = 0.5
) -> void:
	world = world_ref
	city_camera = camera_ref
	canvas = canvas_ref
	if canvas == null:
		return

	_build_building_overview_overlay(
		building_overview_button_ref,
		status_color_resolver,
		status_icon_resolver,
		mark_ui_interacted,
		building_overview_refresh_interval_sec
	)
	_build_search_overlay(
		select_citizen,
		select_building,
		mark_ui_interacted,
		search_result_limit
	)

func update(delta: float) -> void:
	if building_overview_controller != null:
		building_overview_controller.update(delta)

func toggle_building_overview() -> void:
	if building_overview_controller != null:
		building_overview_controller.toggle_visibility()

func get_search_input() -> LineEdit:
	return search_input

func get_search_results_list() -> ItemList:
	return search_results_list

func _build_building_overview_overlay(
	building_overview_button_ref: Button,
	status_color_resolver: Callable,
	status_icon_resolver: Callable,
	mark_ui_interacted: Callable,
	refresh_interval_sec: float
) -> void:
	var building_overview_panel := PanelContainer.new()
	building_overview_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	building_overview_panel.position = Vector2(10, -360)
	building_overview_panel.size = Vector2(350, 290)
	building_overview_panel.visible = false
	canvas.add_child(building_overview_panel)

	var building_overview_scroll := ScrollContainer.new()
	building_overview_scroll.custom_minimum_size = Vector2(350, 290)
	building_overview_panel.add_child(building_overview_scroll)

	var building_overview_label := RichTextLabel.new()
	building_overview_label.bbcode_enabled = true
	building_overview_label.fit_content = true
	building_overview_label.scroll_active = false
	building_overview_label.custom_minimum_size = Vector2(332, 272)
	building_overview_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	building_overview_scroll.add_child(building_overview_label)

	building_overview_controller = BuildingOverviewControllerScript.new()
	building_overview_controller.setup(
		world,
		building_overview_panel,
		building_overview_label,
		building_overview_button_ref,
		status_color_resolver,
		status_icon_resolver,
		mark_ui_interacted,
		refresh_interval_sec
	)

func _build_search_overlay(
	select_citizen: Callable,
	select_building: Callable,
	mark_ui_interacted: Callable,
	search_result_limit: int
) -> void:
	var search_margin := MarginContainer.new()
	search_margin.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	search_margin.offset_left = -360
	search_margin.offset_top = 10
	search_margin.offset_right = -10
	search_margin.offset_bottom = 236
	canvas.add_child(search_margin)

	var search_panel := PanelContainer.new()
	search_margin.add_child(search_panel)

	var search_vbox := VBoxContainer.new()
	search_vbox.add_theme_constant_override("separation", 6)
	search_panel.add_child(search_vbox)

	search_input = LineEdit.new()
	search_input.placeholder_text = "Search citizen or building..."
	search_input.clear_button_enabled = true
	search_input.custom_minimum_size = Vector2(320, 36)
	search_vbox.add_child(search_input)

	search_results_list = ItemList.new()
	search_results_list.custom_minimum_size = Vector2(320, 168)
	search_results_list.select_mode = ItemList.SELECT_SINGLE
	search_results_list.visible = false
	search_vbox.add_child(search_results_list)

	search_controller = EntitySearchControllerScript.new()
	search_controller.setup(
		world,
		city_camera,
		search_input,
		search_results_list,
		select_citizen,
		select_building,
		mark_ui_interacted,
		search_result_limit
	)
