extends RefCounted
class_name UiTheme

## Zentrales Theme für das gesamte In-Game-HUD.
##
## Wird auf den Root-`CanvasLayer` gesetzt — alle darunter liegenden Control-
## Nodes erben das Theme automatisch (Panel, Button, Label, LineEdit, ItemList,
## RichTextLabel, ScrollContainer). Einzelne Controller müssen NICHTS mit
## StyleBoxen tun, außer sie wollen einen "aktiven" State (z. B. Pick-Button
## ON) explizit hervorheben — dafür gibt es `apply_accent_state(button, on)`.
##
## Designziele:
##   * Dunkles Stadt-Sim-Look (Cities-Skylines / Anno-Style)
##   * Eine Akzentfarbe (Cyan) für Interaktion + aktive Toggles
##   * Klare Hierarchie: Heading > Label > Body > Muted
##   * Generös Padding/Spacing damit nichts gequetscht aussieht

# ============================================================================
# Color palette — single source of truth.
# ============================================================================
const BG_900: Color = Color8(20, 24, 32, 235)        # primary panel
const BG_800: Color = Color8(27, 32, 43, 235)        # nested panel / list
const BG_700: Color = Color8(35, 41, 56, 255)        # input field
const BG_600: Color = Color8(44, 51, 68, 255)        # button normal
const BG_500: Color = Color8(53, 61, 82, 255)        # button hover
const BG_400: Color = Color8(67, 76, 100, 255)       # button pressed
const BORDER: Color = Color8(58, 66, 85, 255)
const BORDER_STRONG: Color = Color8(82, 92, 117, 255)

const ACCENT: Color = Color8(79, 195, 247, 255)      # cyan — primary action
const ACCENT_DIM: Color = Color8(41, 165, 217, 255)
const ACCENT_BG: Color = Color8(79, 195, 247, 35)    # hover-tint w/ accent

const SUCCESS: Color = Color8(102, 187, 106, 255)    # green — toggle ON
const SUCCESS_BG: Color = Color8(102, 187, 106, 35)
const WARNING: Color = Color8(255, 167, 38, 255)
const DANGER: Color = Color8(239, 83, 80, 255)

const TEXT_PRIMARY: Color = Color8(231, 235, 242, 255)
const TEXT_SECONDARY: Color = Color8(173, 182, 200, 255)
const TEXT_MUTED: Color = Color8(123, 131, 150, 255)
const TEXT_ON_ACCENT: Color = Color8(10, 14, 22, 255)

# ============================================================================
# Sizes / spacing.
# ============================================================================
const RADIUS_BUTTON: int = 6
const RADIUS_PANEL: int = 8
const RADIUS_INPUT: int = 4

const BORDER_WIDTH: int = 1
const FOCUS_BORDER_WIDTH: int = 2

const PADDING_PANEL_H: int = 14
const PADDING_PANEL_V: int = 12
const PADDING_BUTTON_H: int = 16
const PADDING_BUTTON_V: int = 8
const PADDING_INPUT_H: int = 10
const PADDING_INPUT_V: int = 6

const FONT_SIZE_SMALL: int = 11
const FONT_SIZE_BODY: int = 13
const FONT_SIZE_LABEL: int = 14
const FONT_SIZE_HEADING: int = 17

const SEPARATION_DENSE: int = 6
const SEPARATION_NORMAL: int = 10
const SEPARATION_LOOSE: int = 16


# ============================================================================
# Public API — build a Theme resource and reuse it across the whole HUD.
# ============================================================================

## Singleton-style cache. `CanvasLayer` is NOT a Control and refuses
## `canvas.theme = ...`; we therefore cannot attach the theme once and let
## CanvasLayer-children inherit it. Instead, every top-level Control built
## under a CanvasLayer must explicitly set `.theme = UiTheme.get_or_build()`.
## That call returns the same instance each time so multiple panels share one
## resource. Children of a themed Control still inherit normally.
static var _cached_theme: Theme = null


## Returns the shared theme — builds it the first time, reuses it afterwards.
## Safe to call from any UI controller; the cost is one `Theme.new()` plus a
## handful of StyleBox allocations, paid once per session.
static func get_or_build() -> Theme:
	if _cached_theme == null:
		_cached_theme = build()
	return _cached_theme


## Forces a fresh build on next `get_or_build()`. Mostly useful for editor
## live-reload scenarios; production code does not need this.
static func reset_cache() -> void:
	_cached_theme = null


## Builds a Theme without consulting the cache. Prefer `get_or_build()` —
## this is exposed for tests / one-off panels that want a private theme.
static func build() -> Theme:
	var theme := Theme.new()
	_apply_panel(theme)
	_apply_panel_container(theme)
	_apply_button(theme)
	_apply_label(theme)
	_apply_line_edit(theme)
	_apply_item_list(theme)
	_apply_rich_text_label(theme)
	_apply_scroll_container(theme)
	_apply_separator(theme)
	return theme


## Switches a Button between accent-on and neutral-off styling. Use for
## toggle buttons (Pick / Scan / Pause). The button's `text` is NOT
## modified — caller stays in charge of the label.
static func apply_accent_state(button: Button, is_on: bool) -> void:
	if button == null:
		return
	if is_on:
		button.add_theme_color_override("font_color", TEXT_ON_ACCENT)
		button.add_theme_color_override("font_hover_color", TEXT_ON_ACCENT)
		button.add_theme_color_override("font_pressed_color", TEXT_ON_ACCENT)
		button.add_theme_stylebox_override("normal", _make_button_box(ACCENT, ACCENT_DIM, false))
		button.add_theme_stylebox_override("hover", _make_button_box(ACCENT.lightened(0.06), ACCENT, false))
		button.add_theme_stylebox_override("pressed", _make_button_box(ACCENT_DIM, ACCENT_DIM.darkened(0.2), false))
	else:
		button.remove_theme_color_override("font_color")
		button.remove_theme_color_override("font_hover_color")
		button.remove_theme_color_override("font_pressed_color")
		button.remove_theme_stylebox_override("normal")
		button.remove_theme_stylebox_override("hover")
		button.remove_theme_stylebox_override("pressed")


## Convenience for a small "status" badge on a Label (e.g. inline ON/OFF
## marker, traffic-light state). Sets background via StyleBox + bumped padding.
static func apply_pill_label(label: Label, fg: Color, bg: Color) -> void:
	if label == null:
		return
	label.add_theme_color_override("font_color", fg)
	var pill := StyleBoxFlat.new()
	pill.bg_color = bg
	pill.corner_radius_top_left = 10
	pill.corner_radius_top_right = 10
	pill.corner_radius_bottom_left = 10
	pill.corner_radius_bottom_right = 10
	pill.content_margin_left = 10
	pill.content_margin_right = 10
	pill.content_margin_top = 2
	pill.content_margin_bottom = 2
	label.add_theme_stylebox_override("normal", pill)


# ============================================================================
# Internal: StyleBox factories.
# ============================================================================

static func _make_panel_box(corner_radius: int = RADIUS_PANEL,
		bg: Color = BG_900, border: Color = BORDER) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.border_width_left = BORDER_WIDTH
	box.border_width_top = BORDER_WIDTH
	box.border_width_right = BORDER_WIDTH
	box.border_width_bottom = BORDER_WIDTH
	box.corner_radius_top_left = corner_radius
	box.corner_radius_top_right = corner_radius
	box.corner_radius_bottom_left = corner_radius
	box.corner_radius_bottom_right = corner_radius
	box.content_margin_left = PADDING_PANEL_H
	box.content_margin_right = PADDING_PANEL_H
	box.content_margin_top = PADDING_PANEL_V
	box.content_margin_bottom = PADDING_PANEL_V
	box.shadow_color = Color(0, 0, 0, 0.45)
	box.shadow_size = 6
	box.shadow_offset = Vector2(0, 3)
	return box


static func _make_button_box(bg: Color, border: Color, accent_border: bool = false) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = ACCENT if accent_border else border
	box.border_width_left = FOCUS_BORDER_WIDTH if accent_border else BORDER_WIDTH
	box.border_width_top = FOCUS_BORDER_WIDTH if accent_border else BORDER_WIDTH
	box.border_width_right = FOCUS_BORDER_WIDTH if accent_border else BORDER_WIDTH
	box.border_width_bottom = FOCUS_BORDER_WIDTH if accent_border else BORDER_WIDTH
	box.corner_radius_top_left = RADIUS_BUTTON
	box.corner_radius_top_right = RADIUS_BUTTON
	box.corner_radius_bottom_left = RADIUS_BUTTON
	box.corner_radius_bottom_right = RADIUS_BUTTON
	box.content_margin_left = PADDING_BUTTON_H
	box.content_margin_right = PADDING_BUTTON_H
	box.content_margin_top = PADDING_BUTTON_V
	box.content_margin_bottom = PADDING_BUTTON_V
	return box


static func _make_input_box(bg: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.border_width_left = BORDER_WIDTH
	box.border_width_top = BORDER_WIDTH
	box.border_width_right = BORDER_WIDTH
	box.border_width_bottom = BORDER_WIDTH
	box.corner_radius_top_left = RADIUS_INPUT
	box.corner_radius_top_right = RADIUS_INPUT
	box.corner_radius_bottom_left = RADIUS_INPUT
	box.corner_radius_bottom_right = RADIUS_INPUT
	box.content_margin_left = PADDING_INPUT_H
	box.content_margin_right = PADDING_INPUT_H
	box.content_margin_top = PADDING_INPUT_V
	box.content_margin_bottom = PADDING_INPUT_V
	return box


static func _make_empty_box() -> StyleBoxEmpty:
	var box := StyleBoxEmpty.new()
	return box


# ============================================================================
# Internal: per-control wiring.
# ============================================================================

static func _apply_panel(theme: Theme) -> void:
	theme.set_stylebox("panel", "Panel", _make_panel_box(RADIUS_PANEL, BG_900, BORDER))


static func _apply_panel_container(theme: Theme) -> void:
	theme.set_stylebox("panel", "PanelContainer", _make_panel_box(RADIUS_PANEL, BG_900, BORDER))


static func _apply_button(theme: Theme) -> void:
	theme.set_stylebox("normal", "Button", _make_button_box(BG_600, BORDER))
	theme.set_stylebox("hover", "Button", _make_button_box(BG_500, BORDER_STRONG))
	theme.set_stylebox("pressed", "Button", _make_button_box(BG_400, ACCENT_DIM))
	theme.set_stylebox("disabled", "Button", _make_button_box(BG_700, BORDER))
	theme.set_stylebox("focus", "Button", _make_button_box(BG_600, ACCENT, true))

	theme.set_color("font_color", "Button", TEXT_PRIMARY)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", TEXT_PRIMARY)
	theme.set_color("font_disabled_color", "Button", TEXT_MUTED)
	theme.set_color("font_focus_color", "Button", Color.WHITE)
	theme.set_font_size("font_size", "Button", FONT_SIZE_BODY)


static func _apply_label(theme: Theme) -> void:
	theme.set_color("font_color", "Label", TEXT_PRIMARY)
	theme.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.55))
	theme.set_constant("outline_size", "Label", 0)
	theme.set_font_size("font_size", "Label", FONT_SIZE_LABEL)


static func _apply_line_edit(theme: Theme) -> void:
	theme.set_stylebox("normal", "LineEdit", _make_input_box(BG_700, BORDER))
	theme.set_stylebox("focus", "LineEdit", _make_input_box(BG_700, ACCENT))
	theme.set_color("font_color", "LineEdit", TEXT_PRIMARY)
	theme.set_color("font_placeholder_color", "LineEdit", TEXT_MUTED)
	theme.set_color("caret_color", "LineEdit", ACCENT)
	theme.set_color("selection_color", "LineEdit", ACCENT_BG)
	theme.set_font_size("font_size", "LineEdit", FONT_SIZE_BODY)


static func _apply_item_list(theme: Theme) -> void:
	theme.set_stylebox("panel", "ItemList", _make_panel_box(RADIUS_INPUT, BG_800, BORDER))
	theme.set_stylebox("focus", "ItemList", _make_panel_box(RADIUS_INPUT, BG_800, ACCENT))

	var selected_box := StyleBoxFlat.new()
	selected_box.bg_color = ACCENT_BG
	selected_box.border_color = ACCENT_DIM
	selected_box.border_width_left = BORDER_WIDTH
	selected_box.border_width_top = BORDER_WIDTH
	selected_box.border_width_right = BORDER_WIDTH
	selected_box.border_width_bottom = BORDER_WIDTH
	selected_box.corner_radius_top_left = 3
	selected_box.corner_radius_top_right = 3
	selected_box.corner_radius_bottom_left = 3
	selected_box.corner_radius_bottom_right = 3
	theme.set_stylebox("selected", "ItemList", selected_box)
	theme.set_stylebox("selected_focus", "ItemList", selected_box)
	theme.set_stylebox("hovered", "ItemList", _make_input_box(BG_700, BORDER))

	theme.set_color("font_color", "ItemList", TEXT_PRIMARY)
	theme.set_color("font_selected_color", "ItemList", Color.WHITE)
	theme.set_color("font_hovered_color", "ItemList", Color.WHITE)
	theme.set_font_size("font_size", "ItemList", FONT_SIZE_BODY)
	theme.set_constant("v_separation", "ItemList", 4)


static func _apply_rich_text_label(theme: Theme) -> void:
	theme.set_color("default_color", "RichTextLabel", TEXT_PRIMARY)
	theme.set_font_size("normal_font_size", "RichTextLabel", FONT_SIZE_BODY)
	theme.set_stylebox("normal", "RichTextLabel", _make_empty_box())


static func _apply_scroll_container(theme: Theme) -> void:
	# Thin vertical scrollbar.
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = BG_500
	grabber.corner_radius_top_left = 3
	grabber.corner_radius_top_right = 3
	grabber.corner_radius_bottom_left = 3
	grabber.corner_radius_bottom_right = 3

	var grabber_hover := StyleBoxFlat.new()
	grabber_hover.bg_color = BG_400
	grabber_hover.corner_radius_top_left = 3
	grabber_hover.corner_radius_top_right = 3
	grabber_hover.corner_radius_bottom_left = 3
	grabber_hover.corner_radius_bottom_right = 3

	var scroll_bg := StyleBoxFlat.new()
	scroll_bg.bg_color = Color(0, 0, 0, 0.18)
	scroll_bg.corner_radius_top_left = 3
	scroll_bg.corner_radius_top_right = 3
	scroll_bg.corner_radius_bottom_left = 3
	scroll_bg.corner_radius_bottom_right = 3

	for scroll_type in ["VScrollBar", "HScrollBar"]:
		theme.set_stylebox("scroll", scroll_type, scroll_bg)
		theme.set_stylebox("grabber", scroll_type, grabber)
		theme.set_stylebox("grabber_highlight", scroll_type, grabber_hover)
		theme.set_stylebox("grabber_pressed", scroll_type, grabber_hover)


static func _apply_separator(theme: Theme) -> void:
	var sep := StyleBoxFlat.new()
	sep.bg_color = BORDER
	sep.content_margin_left = 0
	sep.content_margin_right = 0
	sep.content_margin_top = 0
	sep.content_margin_bottom = 0
	theme.set_stylebox("separator", "HSeparator", sep)
	theme.set_stylebox("separator", "VSeparator", sep)
	theme.set_constant("separation", "HSeparator", 1)
	theme.set_constant("separation", "VSeparator", 1)
