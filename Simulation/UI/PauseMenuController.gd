extends RefCounted
class_name PauseMenuController

## In-game pause modal opened with ESC during a running session.
##
## Mirrors MainMenuController's layout but lives on top of the active runtime
## instead of in front of the bootstrap. It only renders buttons and fires owner
## callbacks — main.gd owns pausing the simulation, saving and the scene reload
## that returns to the title screen. "Speichern" is disabled in network sessions
## (save_enabled=false), matching the F5/F6 hotkey restriction.

const UiThemeScript = preload("res://Simulation/UI/UiTheme.gd")
const LocaleServiceScript = preload("res://Simulation/Localization/LocaleService.gd")

var owner_node: Node = null

var _on_resume: Callable = Callable()
var _on_save: Callable = Callable()
var _on_main_menu: Callable = Callable()
var _on_quit: Callable = Callable()
var _save_enabled: bool = true
var _theme: Theme = null
var _canvas: CanvasLayer = null

func setup(
	owner_ref: Node,
	on_resume: Callable,
	on_save: Callable,
	on_main_menu: Callable,
	on_quit: Callable,
	save_enabled: bool
) -> void:
	owner_node = owner_ref
	_on_resume = on_resume
	_on_save = on_save
	_on_main_menu = on_main_menu
	_on_quit = on_quit
	_save_enabled = save_enabled
	_build_menu()

func close() -> void:
	if _canvas != null and is_instance_valid(_canvas):
		_canvas.queue_free()
	_canvas = null

func _build_menu() -> void:
	if owner_node == null:
		return

	_canvas = CanvasLayer.new()
	# Below the save-slot picker (layer 130) so "Speichern" can stack on top.
	_canvas.layer = 127
	owner_node.add_child(_canvas)

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
	title.text = LocaleServiceScript.t("menu.pause_title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", UiThemeScript.FONT_SIZE_HEADING)
	title.add_theme_color_override("font_color", UiThemeScript.ACCENT)
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	var resume_btn := Button.new()
	resume_btn.text = LocaleServiceScript.t("menu.resume")
	resume_btn.custom_minimum_size = Vector2(0, 44)
	resume_btn.pressed.connect(Callable(self, "_on_resume_pressed"))
	vbox.add_child(resume_btn)
	UiThemeScript.apply_accent_state(resume_btn, true)

	var save_btn := Button.new()
	save_btn.text = LocaleServiceScript.t("menu.save")
	save_btn.custom_minimum_size = Vector2(0, 40)
	save_btn.disabled = not _save_enabled
	save_btn.pressed.connect(Callable(self, "_on_save_pressed"))
	vbox.add_child(save_btn)

	var menu_btn := Button.new()
	menu_btn.text = LocaleServiceScript.t("menu.return_to_menu")
	menu_btn.custom_minimum_size = Vector2(0, 40)
	menu_btn.pressed.connect(Callable(self, "_on_main_menu_pressed"))
	vbox.add_child(menu_btn)

	vbox.add_child(HSeparator.new())

	var quit_btn := Button.new()
	quit_btn.text = LocaleServiceScript.t("menu.quit")
	quit_btn.custom_minimum_size = Vector2(0, 36)
	quit_btn.pressed.connect(Callable(self, "_on_quit_pressed"))
	vbox.add_child(quit_btn)

	resume_btn.grab_focus.call_deferred()

func _on_resume_pressed() -> void:
	if _on_resume.is_valid():
		_on_resume.call()

func _on_save_pressed() -> void:
	if _on_save.is_valid():
		_on_save.call()

func _on_main_menu_pressed() -> void:
	if _on_main_menu.is_valid():
		_on_main_menu.call()

func _on_quit_pressed() -> void:
	if _on_quit.is_valid():
		_on_quit.call()
