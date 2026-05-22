extends RefCounted
class_name MainMenuController

## Title-screen modal shown once at startup.
##
## Sits in front of the MultiplayerMenuController and decides the high-level
## entry path: jump straight into offline play, drill into the multiplayer
## sub-menu, or quit the game. The 3D scene is already bootstrapped behind the
## modal, so "Spiel starten" can immediately hand control to the runtime via
## MultiplayerSession.start_offline. Headless / CLI launches skip this UI
## entirely; main.gd only builds the menu when no role flag is present.

const UiThemeScript = preload("res://Simulation/UI/UiTheme.gd")
const SaveGameServiceScript = preload("res://Simulation/Persistence/SaveGameService.gd")
const LocaleServiceScript = preload("res://Simulation/Localization/LocaleService.gd")

var owner_node: Node = null

var _on_singleplayer: Callable = Callable()
var _on_load: Callable = Callable()
var _on_multiplayer: Callable = Callable()
var _theme: Theme = null
var _canvas: CanvasLayer = null
var _buttons: Array[Button] = []
var _language_button: OptionButton = null
var _consumed: bool = false

func setup(
	owner_ref: Node,
	on_singleplayer: Callable,
	on_load: Callable,
	on_multiplayer: Callable
) -> void:
	owner_node = owner_ref
	_on_singleplayer = on_singleplayer
	_on_load = on_load
	_on_multiplayer = on_multiplayer
	_build_menu()

func close() -> void:
	if _canvas != null and is_instance_valid(_canvas):
		_canvas.queue_free()
	_canvas = null

func _build_menu() -> void:
	if owner_node == null:
		return

	_canvas = CanvasLayer.new()
	# Sit just below MultiplayerMenuController (layer 128) so the sub-menu can
	# render on top without us tearing down first.
	_canvas.layer = 127
	owner_node.add_child(_canvas)

	# CanvasLayer cannot hold a Theme; top-level Controls must set it explicitly.
	_theme = UiThemeScript.get_or_build()

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.theme = _theme
	_canvas.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 0)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", UiThemeScript.SEPARATION_NORMAL)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "City Simulation"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", UiThemeScript.FONT_SIZE_HEADING)
	title.add_theme_color_override("font_color", UiThemeScript.ACCENT)
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = LocaleServiceScript.t("menu.subtitle")
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_color_override("font_color", UiThemeScript.TEXT_MUTED)
	subtitle.add_theme_font_size_override("font_size", UiThemeScript.FONT_SIZE_SMALL)
	vbox.add_child(subtitle)

	vbox.add_child(_make_separator())

	var play_btn := Button.new()
	play_btn.text = LocaleServiceScript.t("menu.play")
	play_btn.custom_minimum_size = Vector2(0, 44)
	play_btn.pressed.connect(Callable(self, "_on_play_pressed"))
	vbox.add_child(play_btn)
	_buttons.append(play_btn)
	UiThemeScript.apply_accent_state(play_btn, true)

	var load_btn := Button.new()
	load_btn.text = LocaleServiceScript.t("menu.load")
	load_btn.custom_minimum_size = Vector2(0, 40)
	load_btn.pressed.connect(Callable(self, "_on_load_pressed"))
	load_btn.disabled = not _any_save_exists()
	vbox.add_child(load_btn)
	_buttons.append(load_btn)

	var mp_btn := Button.new()
	mp_btn.text = LocaleServiceScript.t("menu.multiplayer")
	mp_btn.custom_minimum_size = Vector2(0, 40)
	mp_btn.pressed.connect(Callable(self, "_on_multiplayer_pressed"))
	vbox.add_child(mp_btn)
	_buttons.append(mp_btn)

	vbox.add_child(_make_separator())

	vbox.add_child(_build_language_row())

	var quit_btn := Button.new()
	quit_btn.text = LocaleServiceScript.t("menu.quit")
	quit_btn.custom_minimum_size = Vector2(0, 36)
	quit_btn.pressed.connect(Callable(self, "_on_quit_pressed"))
	vbox.add_child(quit_btn)
	_buttons.append(quit_btn)

	# Keyboard focus so Enter triggers "Spiel starten" by default.
	play_btn.grab_focus.call_deferred()

# Label + dropdown row. Selecting a language persists it and rebuilds the menu
# in place so every string re-resolves through the new locale immediately.
func _build_language_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiThemeScript.SEPARATION_DENSE)

	var label := Label.new()
	label.text = LocaleServiceScript.t("menu.language")
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", UiThemeScript.TEXT_SECONDARY)
	row.add_child(label)

	_language_button = OptionButton.new()
	_language_button.custom_minimum_size = Vector2(160, 34)
	var active := LocaleServiceScript.get_language()
	for entry in LocaleServiceScript.available():
		var idx := _language_button.item_count
		_language_button.add_item(str((entry as Dictionary).get("name", "")))
		_language_button.set_item_metadata(idx, str((entry as Dictionary).get("code", "")))
		if str((entry as Dictionary).get("code", "")) == active:
			_language_button.select(idx)
	_language_button.item_selected.connect(Callable(self, "_on_language_selected"))
	row.add_child(_language_button)
	return row

func _on_language_selected(index: int) -> void:
	if _language_button == null:
		return
	var code := str(_language_button.get_item_metadata(index))
	if code.is_empty() or code == LocaleServiceScript.get_language():
		return
	LocaleServiceScript.set_language(code)
	_rebuild()

# Tears down the current canvas and rebuilds from scratch. The old canvas is
# queue_free'd (not freed inline) because we are still inside the OptionButton's
# item_selected callback — freeing its ancestor synchronously would be unsafe.
func _rebuild() -> void:
	if _consumed:
		return
	if _canvas != null and is_instance_valid(_canvas):
		_canvas.queue_free()
	_canvas = null
	_buttons.clear()
	_language_button = null
	_build_menu()

func _on_play_pressed() -> void:
	if _consumed:
		return
	_consumed = true
	_set_buttons_disabled(true)
	if _on_singleplayer.is_valid():
		_on_singleplayer.call()

func _on_multiplayer_pressed() -> void:
	if _consumed:
		return
	_consumed = true
	_set_buttons_disabled(true)
	if _on_multiplayer.is_valid():
		_on_multiplayer.call()

# Opens the load picker. We do NOT mark the menu consumed — if the user cancels
# the picker, the main menu stays usable underneath it.
func _on_load_pressed() -> void:
	if _consumed:
		return
	if _on_load.is_valid():
		_on_load.call()

# Re-enables the menu after a sub-flow (e.g. load picker) cancelled.
func reactivate() -> void:
	_consumed = false
	_set_buttons_disabled(false)

func _any_save_exists() -> bool:
	for entry in SaveGameServiceScript.list_slots():
		if bool((entry as Dictionary).get("exists", false)):
			return true
	var qs := SaveGameServiceScript.describe_quicksave()
	return bool(qs.get("exists", false))

func _on_quit_pressed() -> void:
	if owner_node == null:
		return
	var tree := owner_node.get_tree()
	if tree != null:
		tree.quit()

func _set_buttons_disabled(is_disabled: bool) -> void:
	for button in _buttons:
		if button != null:
			button.disabled = is_disabled

func _make_separator() -> HSeparator:
	return HSeparator.new()
