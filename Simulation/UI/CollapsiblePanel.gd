extends RefCounted
class_name CollapsiblePanel

## Wraps a right-anchored HUD panel so the player can collapse it down to a
## single icon button and expand it again. The expanded panel and the
## collapsed icon share the same top-right anchor, so the panel tucks away
## into its own corner instead of jumping around the screen.
##
## Usage:
##   _panel = CollapsiblePanel.new()
##   _panel.build(canvas, "SEARCH", "Suche", -312.0, top, -12.0, bottom, true)
##   _panel.content.add_child(my_widget)   # fill the panel body
##
## The caller MUST keep the instance in a member variable: this is a
## RefCounted and its collapse/expand button callbacks die with it.

const UiThemeScript = preload("res://Simulation/UI/UiTheme.gd")

# Triangles point toward the action: collapse pushes the panel to the screen
# edge, the collapsed icon pulls it back out. Both glyphs are covered by
# Godot's default font (the HUD already relies on block/box glyphs).
const _COLLAPSE_GLYPH := "▶"
const _EXPAND_GLYPH := "◀"
const _ICON_WIDTH: float = 132.0
const _ICON_HEIGHT: float = 30.0

var panel: PanelContainer = null
var content: VBoxContainer = null

var _icon_button: Button = null
var _collapsed: bool = false


func build(
		canvas: CanvasLayer,
		title: String,
		icon_label: String,
		offset_left: float,
		offset_top: float,
		offset_right: float,
		offset_bottom: float,
		start_collapsed: bool = true
) -> void:
	if canvas == null:
		return
	var safe_name := title.strip_edges().replace(" ", "")

	# --- Expanded panel ---------------------------------------------------
	panel = PanelContainer.new()
	panel.name = "%sPanel" % safe_name
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = offset_left
	panel.offset_top = offset_top
	panel.offset_right = offset_right
	panel.offset_bottom = offset_bottom
	# CanvasLayer can't carry a Theme; every top-level Control sets it itself.
	panel.theme = UiThemeScript.get_or_build()
	canvas.add_child(panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", UiThemeScript.SEPARATION_DENSE)
	panel.add_child(outer)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", UiThemeScript.SEPARATION_DENSE)
	outer.add_child(header)

	var heading := Label.new()
	heading.text = title
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_color_override("font_color", UiThemeScript.TEXT_MUTED)
	heading.add_theme_font_size_override("font_size", UiThemeScript.FONT_SIZE_SMALL)
	header.add_child(heading)

	var collapse_button := Button.new()
	collapse_button.text = _COLLAPSE_GLYPH
	collapse_button.tooltip_text = "Einklappen"
	collapse_button.focus_mode = Control.FOCUS_NONE
	collapse_button.custom_minimum_size = Vector2(30, 24)
	collapse_button.pressed.connect(_collapse)
	header.add_child(collapse_button)

	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", UiThemeScript.SEPARATION_DENSE)
	outer.add_child(content)

	# --- Collapsed icon ---------------------------------------------------
	_icon_button = Button.new()
	_icon_button.name = "%sIcon" % safe_name
	_icon_button.text = "%s %s" % [_EXPAND_GLYPH, icon_label]
	_icon_button.tooltip_text = "%s aufklappen" % title
	_icon_button.focus_mode = Control.FOCUS_NONE
	_icon_button.clip_text = true
	_icon_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_icon_button.offset_left = offset_right - _ICON_WIDTH
	_icon_button.offset_top = offset_top
	_icon_button.offset_right = offset_right
	_icon_button.offset_bottom = offset_top + _ICON_HEIGHT
	_icon_button.theme = UiThemeScript.get_or_build()
	_icon_button.pressed.connect(_expand)
	canvas.add_child(_icon_button)

	_set_collapsed(start_collapsed)


func is_collapsed() -> bool:
	return _collapsed


func set_collapsed(collapsed: bool) -> void:
	_set_collapsed(collapsed)


func _collapse() -> void:
	_set_collapsed(true)


func _expand() -> void:
	_set_collapsed(false)


func _set_collapsed(collapsed: bool) -> void:
	_collapsed = collapsed
	if panel != null:
		panel.visible = not collapsed
	if _icon_button != null:
		_icon_button.visible = collapsed
