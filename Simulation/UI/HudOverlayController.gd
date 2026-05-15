extends RefCounted
class_name HudOverlayController

const BuildingOverviewControllerScript = preload("res://Simulation/UI/BuildingOverviewController.gd")
const CitizenOverviewControllerScript = preload("res://Simulation/UI/CitizenOverviewController.gd")
const EconomyOverviewControllerScript = preload("res://Simulation/UI/EconomyOverviewController.gd")
const EntitySearchControllerScript = preload("res://Simulation/UI/EntitySearchController.gd")
const UiThemeScript = preload("res://Simulation/UI/UiTheme.gd")

var world: World = null
var city_camera: CityBuilderCamera = null
var canvas: CanvasLayer = null
var search_input: LineEdit = null
var search_results_list: ItemList = null
var building_overview_controller = null
var citizen_overview_controller = null
var economy_overview_controller = null
var search_controller = null

func setup(
	world_ref: World,
	camera_ref: CityBuilderCamera,
	canvas_ref: CanvasLayer,
	building_overview_button_ref: Button,
	citizen_overview_button_ref: Button,
	economy_overview_button_ref: Button,
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
		select_building,
		building_overview_refresh_interval_sec
	)
	_build_citizen_overview_overlay(
		citizen_overview_button_ref,
		mark_ui_interacted,
		select_citizen,
		building_overview_refresh_interval_sec
	)
	_build_economy_overview_overlay(
		economy_overview_button_ref,
		mark_ui_interacted,
		select_building,
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
	if citizen_overview_controller != null:
		citizen_overview_controller.update(delta)
	if economy_overview_controller != null:
		economy_overview_controller.update(delta)

func toggle_building_overview() -> void:
	if building_overview_controller != null:
		_hide_economy_overview_if_visible()
		building_overview_controller.toggle_visibility()

func toggle_citizen_overview() -> void:
	if citizen_overview_controller != null:
		_hide_economy_overview_if_visible()
		citizen_overview_controller.toggle_visibility()

func toggle_economy_overview() -> void:
	if economy_overview_controller != null:
		if not _is_controller_visible(economy_overview_controller):
			_hide_compact_overviews_if_visible()
		economy_overview_controller.toggle_visibility()

func get_search_input() -> LineEdit:
	return search_input

func get_search_results_list() -> ItemList:
	return search_results_list

func _build_building_overview_overlay(
	building_overview_button_ref: Button,
	status_color_resolver: Callable,
	status_icon_resolver: Callable,
	mark_ui_interacted: Callable,
	select_building: Callable,
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
		select_building,
		refresh_interval_sec
	)

func _build_citizen_overview_overlay(
	citizen_overview_button_ref: Button,
	mark_ui_interacted: Callable,
	select_citizen: Callable,
	refresh_interval_sec: float
) -> void:
	# Positioned to the right of the building overview panel.
	var citizen_overview_panel := PanelContainer.new()
	citizen_overview_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	citizen_overview_panel.position = Vector2(12 + 380 + 12, -380)
	citizen_overview_panel.size = Vector2(380, 300)
	citizen_overview_panel.visible = false
	citizen_overview_panel.theme = UiThemeScript.get_or_build()
	canvas.add_child(citizen_overview_panel)

	var citizen_vbox := VBoxContainer.new()
	citizen_vbox.add_theme_constant_override("separation", UiThemeScript.SEPARATION_DENSE)
	citizen_overview_panel.add_child(citizen_vbox)

	var citizen_heading := Label.new()
	citizen_heading.text = "CITIZENS"
	citizen_heading.add_theme_color_override("font_color", UiThemeScript.TEXT_MUTED)
	citizen_heading.add_theme_font_size_override("font_size", UiThemeScript.FONT_SIZE_SMALL)
	citizen_vbox.add_child(citizen_heading)

	var citizen_overview_scroll := ScrollContainer.new()
	citizen_overview_scroll.custom_minimum_size = Vector2(354, 256)
	citizen_overview_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	citizen_vbox.add_child(citizen_overview_scroll)

	var citizen_overview_label := RichTextLabel.new()
	citizen_overview_label.bbcode_enabled = true
	citizen_overview_label.fit_content = true
	citizen_overview_label.scroll_active = false
	citizen_overview_label.custom_minimum_size = Vector2(340, 240)
	citizen_overview_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	citizen_overview_scroll.add_child(citizen_overview_label)

	citizen_overview_controller = CitizenOverviewControllerScript.new()
	citizen_overview_controller.setup(
		world,
		citizen_overview_panel,
		citizen_overview_label,
		citizen_overview_button_ref,
		mark_ui_interacted,
		select_citizen,
		refresh_interval_sec
	)

func _build_economy_overview_overlay(
	economy_overview_button_ref: Button,
	mark_ui_interacted: Callable,
	select_building: Callable,
	refresh_interval_sec: float
) -> void:
	# Wide bottom dashboard. It uses the available viewport width and stays
	# above the action bar instead of relying on a fixed pixel rectangle.
	var viewport := canvas.get_viewport()
	var viewport_height := viewport.get_visible_rect().size.y if viewport != null else 720.0
	var panel_height := minf(420.0, maxf(300.0, viewport_height - 120.0))

	var economy_panel := PanelContainer.new()
	economy_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	economy_panel.offset_left = 12.0
	economy_panel.offset_right = -12.0
	economy_panel.offset_top = -panel_height - 80.0
	economy_panel.offset_bottom = -80.0
	economy_panel.custom_minimum_size = Vector2(620, panel_height)
	economy_panel.visible = false
	economy_panel.theme = UiThemeScript.get_or_build()
	canvas.add_child(economy_panel)

	var outer_vbox := VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", UiThemeScript.SEPARATION_DENSE)
	economy_panel.add_child(outer_vbox)

	var economy_heading := Label.new()
	economy_heading.text = "ECONOMY"
	economy_heading.add_theme_color_override("font_color", UiThemeScript.TEXT_MUTED)
	economy_heading.add_theme_font_size_override("font_size", UiThemeScript.FONT_SIZE_SMALL)
	outer_vbox.add_child(economy_heading)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", UiThemeScript.SEPARATION_NORMAL)
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer_vbox.add_child(columns)

	# Left column: city aggregate.
	var city_scroll := ScrollContainer.new()
	city_scroll.custom_minimum_size = Vector2(280, maxf(240.0, panel_height - 72.0))
	city_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_child(city_scroll)

	var city_label := RichTextLabel.new()
	city_label.bbcode_enabled = true
	city_label.fit_content = true
	city_label.scroll_active = false
	city_label.custom_minimum_size = Vector2(260, maxf(220.0, panel_height - 88.0))
	city_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	city_scroll.add_child(city_label)

	# Right column: grouped building list above, detail panel below.
	var right_vbox := VBoxContainer.new()
	right_vbox.add_theme_constant_override("separation", UiThemeScript.SEPARATION_DENSE)
	right_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_child(right_vbox)

	var list_scroll := ScrollContainer.new()
	list_scroll.custom_minimum_size = Vector2(340, maxf(140.0, panel_height * 0.52))
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_vbox.add_child(list_scroll)

	var building_list_label := RichTextLabel.new()
	building_list_label.bbcode_enabled = true
	building_list_label.fit_content = true
	building_list_label.scroll_active = false
	building_list_label.custom_minimum_size = Vector2(320, maxf(128.0, panel_height * 0.50))
	building_list_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.add_child(building_list_label)

	var detail_scroll := ScrollContainer.new()
	detail_scroll.custom_minimum_size = Vector2(340, maxf(110.0, panel_height * 0.32))
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_vbox.add_child(detail_scroll)

	var building_detail_label := RichTextLabel.new()
	building_detail_label.bbcode_enabled = true
	building_detail_label.fit_content = true
	building_detail_label.scroll_active = false
	building_detail_label.custom_minimum_size = Vector2(320, maxf(100.0, panel_height * 0.30))
	building_detail_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.add_child(building_detail_label)

	economy_overview_controller = EconomyOverviewControllerScript.new()
	economy_overview_controller.setup(
		world,
		economy_panel,
		city_label,
		building_list_label,
		building_detail_label,
		economy_overview_button_ref,
		mark_ui_interacted,
		select_building,
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

func _hide_economy_overview_if_visible() -> void:
	if _is_controller_visible(economy_overview_controller):
		economy_overview_controller.toggle_visibility()

func _hide_compact_overviews_if_visible() -> void:
	if _is_controller_visible(building_overview_controller):
		building_overview_controller.toggle_visibility()
	if _is_controller_visible(citizen_overview_controller):
		citizen_overview_controller.toggle_visibility()

func _is_controller_visible(controller) -> bool:
	return controller != null and controller.has_method("is_visible") and bool(controller.is_visible())
