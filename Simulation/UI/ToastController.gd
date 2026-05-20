extends RefCounted
class_name ToastController

const UiThemeScript = preload("res://Simulation/UI/UiTheme.gd")

const DEFAULT_DURATION_SEC := 3.2
const FADE_OUT_SEC := 0.35
const MAX_TOASTS := 5
const TOP_MARGIN := UiThemeScript.TOPBAR_HEIGHT + 14
const RIGHT_MARGIN := 16.0
const MIN_WIDTH := 220.0
const MAX_WIDTH := 420.0

var _canvas: CanvasLayer = null
var _root: Control = null
var _stack: VBoxContainer = null
var _theme: Theme = null
var _toasts: Array[Dictionary] = []


func setup(canvas_ref: CanvasLayer) -> void:
	_canvas = canvas_ref
	_theme = UiThemeScript.get_or_build()
	if _canvas == null:
		return
	if _root != null and is_instance_valid(_root):
		return
	_build_root()


func show_toast(message: String, kind: String = "info", duration_sec: float = DEFAULT_DURATION_SEC) -> void:
	var clean_message := message.strip_edges()
	if clean_message.is_empty() or _stack == null:
		return
	_refresh_root_layout()
	var panel := _make_toast_panel(clean_message, kind)
	_stack.add_child(panel)
	_stack.move_child(panel, 0)
	_toasts.push_front({
		"node": panel,
		"message": clean_message,
		"kind": _normalize_kind(kind),
		"time_left": duration_sec if duration_sec > 0.0 else DEFAULT_DURATION_SEC,
	})
	while _toasts.size() > MAX_TOASTS:
		_remove_toast(_toasts.size() - 1)


func update(delta: float) -> void:
	_refresh_root_layout()
	for i in range(_toasts.size() - 1, -1, -1):
		var entry := _toasts[i]
		var node := entry.get("node", null) as Control
		if node == null or not is_instance_valid(node):
			_toasts.remove_at(i)
			continue
		var time_left := float(entry.get("time_left", 0.0)) - delta
		if time_left <= 0.0:
			_remove_toast(i)
			continue
		entry["time_left"] = time_left
		_toasts[i] = entry
		if time_left <= FADE_OUT_SEC:
			node.modulate.a = clampf(time_left / FADE_OUT_SEC, 0.0, 1.0)


func clear() -> void:
	for i in range(_toasts.size() - 1, -1, -1):
		_remove_toast(i)


func get_active_toast_count() -> int:
	return _toasts.size()


func get_active_toast_messages() -> PackedStringArray:
	var result := PackedStringArray()
	for entry in _toasts:
		result.append(str(entry.get("message", "")))
	return result


func _build_root() -> void:
	_root = Control.new()
	_root.name = "ToastRoot"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_canvas.add_child(_root)

	_stack = VBoxContainer.new()
	_stack.name = "ToastStack"
	_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stack.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stack.alignment = BoxContainer.ALIGNMENT_BEGIN
	_stack.add_theme_constant_override("separation", UiThemeScript.SEPARATION_DENSE)
	_root.add_child(_stack)
	_refresh_root_layout()


func _refresh_root_layout() -> void:
	if _root == null or not is_instance_valid(_root):
		return
	var viewport_width := 1280.0
	var viewport := _root.get_viewport()
	if viewport != null:
		viewport_width = viewport.get_visible_rect().size.x
	var available_width := maxf(MIN_WIDTH, viewport_width - RIGHT_MARGIN * 2.0)
	var width := minf(MAX_WIDTH, available_width)
	_root.offset_left = -width - RIGHT_MARGIN
	_root.offset_top = TOP_MARGIN
	_root.offset_right = -RIGHT_MARGIN
	_root.offset_bottom = TOP_MARGIN + 480.0


func _make_toast_panel(message: String, kind: String) -> PanelContainer:
	var normalized_kind := _normalize_kind(kind)
	var accent := _kind_color(normalized_kind)
	var panel := PanelContainer.new()
	panel.name = "Toast"
	panel.theme = _theme
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.modulate.a = 1.0

	var box := UiThemeScript._make_panel_box(
		UiThemeScript.RADIUS_PANEL,
		UiThemeScript.BG_900,
		accent.darkened(0.2)
	)
	box.content_margin_left = 10
	box.content_margin_right = 12
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	box.shadow_size = 8
	panel.add_theme_stylebox_override("panel", box)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", UiThemeScript.SEPARATION_DENSE)
	panel.add_child(row)

	var stripe := ColorRect.new()
	stripe.color = accent
	stripe.custom_minimum_size = Vector2(4, 0)
	stripe.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(stripe)

	var label := Label.new()
	label.text = message
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", UiThemeScript.TEXT_PRIMARY)
	label.add_theme_font_size_override("font_size", UiThemeScript.FONT_SIZE_BODY)
	row.add_child(label)
	return panel


func _remove_toast(index: int) -> void:
	if index < 0 or index >= _toasts.size():
		return
	var entry := _toasts[index]
	var node := entry.get("node", null) as Node
	if node != null and is_instance_valid(node):
		node.queue_free()
	_toasts.remove_at(index)


func _normalize_kind(kind: String) -> String:
	var clean_kind := kind.strip_edges().to_lower()
	match clean_kind:
		"success", "warning", "error":
			return clean_kind
	return "info"


func _kind_color(kind: String) -> Color:
	match _normalize_kind(kind):
		"success":
			return UiThemeScript.SUCCESS
		"warning":
			return UiThemeScript.WARNING
		"error":
			return UiThemeScript.DANGER
	return UiThemeScript.ACCENT
