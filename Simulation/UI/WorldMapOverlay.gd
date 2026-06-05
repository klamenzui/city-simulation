extends CanvasLayer
class_name WorldMapOverlay

signal destination_selected(world_position: Vector3)
signal closed

const UiThemeScript = preload("res://Simulation/UI/UiTheme.gd")
const WorldMapCanvasScript = preload("res://Simulation/UI/WorldMapCanvas.gd")

const PANEL_WIDTH := 400.0
const PANEL_HEIGHT := 360.0
const RIGHT_MARGIN := 16.0
const BOTTOM_MARGIN := UiThemeScript.BOTTOMBAR_HEIGHT + 14.0

var world: World = null
var target_node: Node3D = null

var _root: Control = null
var _panel: PanelContainer = null
var _title_label: Label = null
var _status_label: Label = null
var _map_canvas = null
var _zoom_reset_button: Button = null
var _theme: Theme = null


func _ready() -> void:
	if _root == null:
		_build()
	hide_map()


func setup(world_ref: World, target_ref: Node3D = null) -> void:
	world = world_ref
	target_node = target_ref
	if _root == null:
		_build()
	if _map_canvas != null:
		_map_canvas.set_world(world)
		_map_canvas.set_target_node(target_node)


func show_map(title: String, status_text: String, allow_selection: bool = true) -> void:
	if _root == null:
		_build()
	if _map_canvas != null:
		_map_canvas.reset_view()
	if _title_label != null:
		_title_label.text = title
	if _status_label != null:
		_status_label.text = status_text
	set_selection_enabled(allow_selection)
	visible = true
	if _map_canvas != null:
		_map_canvas.queue_redraw()


func hide_map() -> void:
	visible = false


func set_target_node(target_ref: Node3D) -> void:
	target_node = target_ref
	if _map_canvas != null:
		_map_canvas.set_target_node(target_node)


func set_status_text(status_text: String) -> void:
	if _status_label != null:
		_status_label.text = status_text


func set_selection_enabled(enabled: bool) -> void:
	if _map_canvas != null:
		_map_canvas.set_selection_enabled(enabled)


func set_selected_position(world_position: Vector3) -> void:
	if _map_canvas != null:
		_map_canvas.set_selected_position(world_position)


func clear_selected_position() -> void:
	if _map_canvas != null:
		_map_canvas.clear_selected_position()


func set_route_points(points: PackedVector3Array) -> void:
	if _map_canvas != null:
		_map_canvas.set_route_points(points)


func clear_route() -> void:
	if _map_canvas != null:
		_map_canvas.set_route_points(PackedVector3Array())


func set_extra_markers(markers: Array) -> void:
	if _map_canvas != null:
		_map_canvas.set_extra_markers(markers)


func get_zoom_level() -> float:
	if _map_canvas == null:
		return 3.3
	return float(_map_canvas.get_zoom_level())


func get_default_zoom_level() -> float:
	if _map_canvas == null:
		return 3.3
	return float(_map_canvas.get_default_zoom_level())


func zoom_in() -> void:
	if _map_canvas != null:
		_map_canvas.zoom_in()


func zoom_out() -> void:
	if _map_canvas != null:
		_map_canvas.zoom_out()


func reset_zoom() -> void:
	if _map_canvas != null:
		_map_canvas.reset_zoom()


func refresh() -> void:
	if _map_canvas != null:
		_map_canvas.queue_redraw()


func _build() -> void:
	layer = 40
	_theme = UiThemeScript.get_or_build()

	_root = Control.new()
	_root.name = "WorldMapOverlayRoot"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	_panel = PanelContainer.new()
	_panel.name = "WorldMapPanel"
	_panel.theme = _theme
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_panel.offset_left = -PANEL_WIDTH - RIGHT_MARGIN
	_panel.offset_top = -PANEL_HEIGHT - BOTTOM_MARGIN
	_panel.offset_right = -RIGHT_MARGIN
	_panel.offset_bottom = -BOTTOM_MARGIN
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_panel)

	var panel_box := UiThemeScript._make_panel_box(UiThemeScript.RADIUS_PANEL, UiThemeScript.BG_900, UiThemeScript.BORDER)
	panel_box.content_margin_left = 10
	panel_box.content_margin_right = 10
	panel_box.content_margin_top = 8
	panel_box.content_margin_bottom = 10
	_panel.add_theme_stylebox_override("panel", panel_box)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_panel.add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	vbox.add_child(header)

	_title_label = Label.new()
	_title_label.text = "Map"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.add_theme_color_override("font_color", UiThemeScript.TEXT_PRIMARY)
	_title_label.add_theme_font_size_override("font_size", UiThemeScript.FONT_SIZE_LABEL)
	header.add_child(_title_label)

	var zoom_out_button := Button.new()
	zoom_out_button.text = "-"
	zoom_out_button.tooltip_text = "Herauszoomen"
	zoom_out_button.focus_mode = Control.FOCUS_NONE
	zoom_out_button.custom_minimum_size = Vector2(30, 28)
	zoom_out_button.pressed.connect(_on_zoom_out_pressed)
	header.add_child(zoom_out_button)

	_zoom_reset_button = Button.new()
	_zoom_reset_button.text = "1x"
	_zoom_reset_button.tooltip_text = "Zoom zuruecksetzen"
	_zoom_reset_button.focus_mode = Control.FOCUS_NONE
	_zoom_reset_button.custom_minimum_size = Vector2(44, 28)
	_zoom_reset_button.pressed.connect(_on_zoom_reset_pressed)
	header.add_child(_zoom_reset_button)

	var zoom_in_button := Button.new()
	zoom_in_button.text = "+"
	zoom_in_button.tooltip_text = "Hineinzoomen"
	zoom_in_button.focus_mode = Control.FOCUS_NONE
	zoom_in_button.custom_minimum_size = Vector2(30, 28)
	zoom_in_button.pressed.connect(_on_zoom_in_pressed)
	header.add_child(zoom_in_button)

	var close_button := Button.new()
	close_button.text = "X"
	close_button.tooltip_text = "Map ausblenden"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.custom_minimum_size = Vector2(32, 28)
	close_button.pressed.connect(_on_close_pressed)
	header.add_child(close_button)

	_status_label = Label.new()
	_status_label.text = ""
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_color_override("font_color", UiThemeScript.TEXT_SECONDARY)
	_status_label.add_theme_font_size_override("font_size", UiThemeScript.FONT_SIZE_SMALL)
	_status_label.custom_minimum_size = Vector2(0, 30)
	vbox.add_child(_status_label)

	var map_canvas := Control.new()
	map_canvas.set_script(WorldMapCanvasScript)
	_map_canvas = map_canvas
	_map_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map_canvas.destination_selected.connect(_on_canvas_destination_selected)
	_map_canvas.zoom_changed.connect(_on_map_zoom_changed)
	vbox.add_child(_map_canvas)
	_map_canvas.set_world(world)
	_map_canvas.set_target_node(target_node)
	_on_map_zoom_changed(_map_canvas.get_zoom_level())


func _on_canvas_destination_selected(world_position: Vector3) -> void:
	destination_selected.emit(world_position)


func _on_zoom_out_pressed() -> void:
	zoom_out()


func _on_zoom_reset_pressed() -> void:
	reset_zoom()


func _on_zoom_in_pressed() -> void:
	zoom_in()


func _on_map_zoom_changed(value: float) -> void:
	if _zoom_reset_button == null:
		return
	_zoom_reset_button.text = _format_zoom(value)


func _format_zoom(value: float) -> String:
	return "%.1fx" % value


func _on_close_pressed() -> void:
	hide_map()
	closed.emit()
