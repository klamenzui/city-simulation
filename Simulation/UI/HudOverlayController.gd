extends RefCounted
class_name HudOverlayController

const BuildingOverviewControllerScript = preload("res://Simulation/UI/BuildingOverviewController.gd")
const EntitySearchControllerScript = preload("res://Simulation/UI/EntitySearchController.gd")
const UiThemeScript = preload("res://Simulation/UI/UiTheme.gd")

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
	# Sits above the action bar; height grows from bottom.
	building_overview_panel.position = Vector2(12, -380)
	building_overview_panel.size = Vector2(380, 300)
	building_overview_panel.visible = false
	# CanvasLayer can't hold a Theme — assign it explicitly on each top-level
	# Control we attach to it. Children inherit normally.
	building_overview_panel.theme = UiThemeScript.get_or_build()
	canvas.add_child(building_overview_panel)

	var building_vbox := VBoxContainer.new()
	building_vbox.add_theme_constant_override("separation", UiThemeScript.SEPARATION_DENSE)
	building_overview_panel.add_child(building_vbox)

	var building_heading := Label.new()
	building_heading.text = "BUILDINGS"
	building_heading.add_theme_color_override("font_color", UiThemeScript.TEXT_MUTED)
	building_heading.add_theme_font_size_override("font_size", UiThemeScript.FONT_SIZE_SMALL)
	building_vbox.add_child(building_heading)

	var building_overview_scroll := ScrollContainer.new()
	building_overview_scroll.custom_minimum_size = Vector2(354, 256)
	building_overview_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	building_vbox.add_child(building_overview_scroll)

	var building_overview_label := RichTextLabel.new()
	building_overview_label.bbcode_enabled = true
	building_overview_label.fit_content = true
	building_overview_label.scroll_active = false
	building_overview_label.custom_minimum_size = Vector2(340, 240)
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
	search_margin.offset_left = -312
	search_margin.offset_top = 12
	search_margin.offset_right = -12
	search_margin.offset_bottom = 240
	search_margin.theme = UiThemeScript.get_or_build()
	canvas.add_child(search_margin)

	var search_panel := PanelContainer.new()
	search_margin.add_child(search_panel)

	var search_vbox := VBoxContainer.new()
	search_vbox.add_theme_constant_override("separation", UiThemeScript.SEPARATION_DENSE)
	search_panel.add_child(search_vbox)

	var search_heading := Label.new()
	search_heading.text = "SEARCH"
	search_heading.add_theme_color_override("font_color", UiThemeScript.TEXT_MUTED)
	search_heading.add_theme_font_size_override("font_size", UiThemeScript.FONT_SIZE_SMALL)
	search_vbox.add_child(search_heading)

	search_input = LineEdit.new()
	search_input.placeholder_text = "Citizen or building name…"
	search_input.clear_button_enabled = true
	search_input.custom_minimum_size = Vector2(266, 32)
	search_vbox.add_child(search_input)

	search_results_list = ItemList.new()
	search_results_list.custom_minimum_size = Vector2(266, 168)
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
