extends RefCounted
class_name BuildingStatusBadgeController

var owner_node: Node = null
var camera: Camera3D = null

var _layer: CanvasLayer = null
var _panel: PanelContainer = null
var _label: Label = null
var _style: StyleBoxFlat = null
var _status_color_resolver: Callable = Callable()
var _status_background_resolver: Callable = Callable()
var _status_icon_resolver: Callable = Callable()

func setup(
	owner_ref: Node,
	camera_ref: Camera3D,
	status_color_resolver: Callable,
	status_background_resolver: Callable,
	status_icon_resolver: Callable,
	default_border_color: Color
) -> void:
	owner_node = owner_ref
	camera = camera_ref
	_status_color_resolver = status_color_resolver
	_status_background_resolver = status_background_resolver
	_status_icon_resolver = status_icon_resolver
	_build_ui(default_border_color)

func update(building: Building, world: World) -> void:
	if _panel == null or _label == null or camera == null:
		return
	if building == null or not is_instance_valid(building):
		hide()
		return

	var badge_world_pos := _get_badge_world_position(building)
	if camera.is_position_behind(badge_world_pos):
		hide()
		return

	var viewport := owner_node.get_viewport() if owner_node != null else null
	if viewport == null:
		hide()
		return

	var screen_pos := camera.unproject_position(badge_world_pos)
	var viewport_rect := viewport.get_visible_rect()
	if screen_pos.x < -40.0 or screen_pos.x > viewport_rect.size.x + 40.0 or screen_pos.y < -40.0 or screen_pos.y > viewport_rect.size.y + 40.0:
		hide()
		return

	var hour := world.time.get_hour() if world != null and world.time != null else -1
	var status_key := building.get_open_status_label(hour) if hour >= 0 else building.get_open_status_label()
	var status_text := building.get_open_status_display_label(hour) if hour >= 0 else building.get_open_status_display_label()
	var badge_color := _resolve_badge_color(status_key)
	var status_icon := _resolve_badge_icon(status_key)

	_label.text = "%s\n%s %s" % [building.get_display_name(), status_icon, status_text]
	_label.add_theme_color_override("font_color", badge_color)
	_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.55))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	_style.border_color = badge_color
	_style.bg_color = _resolve_badge_background(status_key)

	var panel_size := _panel.get_combined_minimum_size()
	_panel.size = panel_size
	_panel.position = Vector2(
		screen_pos.x - panel_size.x * 0.5,
		screen_pos.y - panel_size.y
	)
	_panel.visible = true

func hide() -> void:
	if _panel != null:
		_panel.visible = false

func _build_ui(default_border_color: Color) -> void:
	if owner_node == null:
		return
	if _layer != null and is_instance_valid(_layer):
		return

	_layer = CanvasLayer.new()
	_layer.name = "SelectedBuildingStatusBadge"
	owner_node.add_child(_layer)

	_panel = PanelContainer.new()
	_panel.visible = false
	_layer.add_child(_panel)

	_style = StyleBoxFlat.new()
	_style.bg_color = Color(0.11, 0.12, 0.16, 0.92)
	_style.border_color = default_border_color
	_style.set_border_width_all(2)
	_style.corner_radius_top_left = 10
	_style.corner_radius_top_right = 10
	_style.corner_radius_bottom_right = 10
	_style.corner_radius_bottom_left = 10
	_style.content_margin_left = 10
	_style.content_margin_right = 10
	_style.content_margin_top = 6
	_style.content_margin_bottom = 6
	_panel.add_theme_stylebox_override("panel", _style)

	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 15)
	_panel.add_child(_label)

func _get_badge_world_position(building: Building) -> Vector3:
	var bounds := building.get_footprint_bounds()
	var local_badge_pos := bounds.position + Vector3(bounds.size.x * 0.5, bounds.size.y + 1.15, bounds.size.z * 0.5)
	return building.to_global(local_badge_pos)

func _resolve_badge_color(status_key: String) -> Color:
	if _status_color_resolver.is_valid():
		return _status_color_resolver.call(status_key) as Color
	return Color.WHITE

func _resolve_badge_background(status_key: String) -> Color:
	if _status_background_resolver.is_valid():
		return _status_background_resolver.call(status_key) as Color
	return Color(0.11, 0.12, 0.16, 0.92)

func _resolve_badge_icon(status_key: String) -> String:
	if _status_icon_resolver.is_valid():
		return str(_status_icon_resolver.call(status_key))
	return "[+]"
