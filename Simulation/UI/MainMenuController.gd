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

var owner_node: Node = null

var _on_singleplayer: Callable = Callable()
var _on_load: Callable = Callable()
var _on_multiplayer: Callable = Callable()
var _theme: Theme = null
var _canvas: CanvasLayer = null
var _buttons: Array[Button] = []
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
	subtitle.text = "Hauptmenü"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_color_override("font_color", UiThemeScript.TEXT_MUTED)
	subtitle.add_theme_font_size_override("font_size", UiThemeScript.FONT_SIZE_SMALL)
	vbox.add_child(subtitle)

	vbox.add_child(_make_separator())

	var play_btn := Button.new()
	play_btn.text = "Spiel starten"
	play_btn.custom_minimum_size = Vector2(0, 44)
	play_btn.pressed.connect(Callable(self, "_on_play_pressed"))
	vbox.add_child(play_btn)
	_buttons.append(play_btn)
	UiThemeScript.apply_accent_state(play_btn, true)

	var load_btn := Button.new()
	load_btn.text = "Spiel laden"
	load_btn.custom_minimum_size = Vector2(0, 40)
	load_btn.pressed.connect(Callable(self, "_on_load_pressed"))
	load_btn.disabled = not _any_save_exists()
	vbox.add_child(load_btn)
	_buttons.append(load_btn)

	var mp_btn := Button.new()
	mp_btn.text = "Multiplayer"
	mp_btn.custom_minimum_size = Vector2(0, 40)
	mp_btn.pressed.connect(Callable(self, "_on_multiplayer_pressed"))
	vbox.add_child(mp_btn)
	_buttons.append(mp_btn)

	vbox.add_child(_make_separator())

	var quit_btn := Button.new()
	quit_btn.text = "Beenden"
	quit_btn.custom_minimum_size = Vector2(0, 36)
	quit_btn.pressed.connect(Callable(self, "_on_quit_pressed"))
	vbox.add_child(quit_btn)
	_buttons.append(quit_btn)

	# Keyboard focus so Enter triggers "Spiel starten" by default.
	play_btn.grab_focus.call_deferred()

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
