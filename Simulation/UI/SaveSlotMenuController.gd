extends RefCounted
class_name SaveSlotMenuController

## Slot picker modal for save (mode=MODE_SAVE) and load (mode=MODE_LOAD).
##
## Three slots, each row shows day / wall-clock label / citizen count if the
## slot is filled, otherwise "(leer)". In save mode every row is actionable
## (filled slots get a one-step overwrite confirmation). In load mode only
## filled slots are actionable. Owner gets a callback with the chosen slot
## index, then closes the modal itself — the menu does not own session state.

const UiThemeScript = preload("res://Simulation/UI/UiTheme.gd")
const SaveGameServiceScript = preload("res://Simulation/Persistence/SaveGameService.gd")
const LocaleServiceScript = preload("res://Simulation/Localization/LocaleService.gd")

enum Mode { SAVE, LOAD }

var owner_node: Node = null
var mode: int = Mode.SAVE

var _on_slot_chosen: Callable = Callable()
var _on_cancelled: Callable = Callable()
var _theme: Theme = null
var _canvas: CanvasLayer = null
var _pending_overwrite_slot: int = -1
var _status_label: Label = null
var _row_buttons: Array[Button] = []

func setup(owner_ref: Node, menu_mode: int, on_chosen: Callable, on_cancelled: Callable) -> void:
	owner_node = owner_ref
	mode = menu_mode
	_on_slot_chosen = on_chosen
	_on_cancelled = on_cancelled
	_build_menu()

func close() -> void:
	if _canvas != null and is_instance_valid(_canvas):
		_canvas.queue_free()
	_canvas = null
	_row_buttons.clear()

func _build_menu() -> void:
	if owner_node == null:
		return

	_canvas = CanvasLayer.new()
	_canvas.layer = 130
	owner_node.add_child(_canvas)

	_theme = UiThemeScript.get_or_build()

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.theme = _theme
	_canvas.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(480, 0)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", UiThemeScript.SEPARATION_NORMAL)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = LocaleServiceScript.t("save.title_save") if mode == Mode.SAVE else LocaleServiceScript.t("save.title_load")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", UiThemeScript.FONT_SIZE_HEADING)
	title.add_theme_color_override("font_color", UiThemeScript.ACCENT)
	vbox.add_child(title)

	vbox.add_child(_make_separator())

	_render_rows(vbox)

	vbox.add_child(_make_separator())

	_status_label = Label.new()
	_status_label.text = ""
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_color_override("font_color", UiThemeScript.TEXT_SECONDARY)
	_status_label.add_theme_font_size_override("font_size", UiThemeScript.FONT_SIZE_SMALL)
	_status_label.custom_minimum_size = Vector2(0, 28)
	vbox.add_child(_status_label)

	var cancel_btn := Button.new()
	cancel_btn.text = LocaleServiceScript.t("save.button_cancel")
	cancel_btn.custom_minimum_size = Vector2(0, 36)
	cancel_btn.pressed.connect(Callable(self, "_on_cancel_pressed"))
	vbox.add_child(cancel_btn)

func _render_rows(vbox: VBoxContainer) -> void:
	_row_buttons.clear()
	var slots := SaveGameServiceScript.list_slots()
	for entry in slots:
		var slot_info := entry as Dictionary
		var slot := int(slot_info.get("slot", 0))
		var exists := bool(slot_info.get("exists", false))

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", UiThemeScript.SEPARATION_DENSE)
		vbox.add_child(row)

		var info := Label.new()
		info.text = _format_slot_label(slot, slot_info)
		info.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_color_override(
			"font_color",
			UiThemeScript.TEXT_PRIMARY if exists else UiThemeScript.TEXT_MUTED
		)
		info.add_theme_font_size_override("font_size", UiThemeScript.FONT_SIZE_BODY)
		row.add_child(info)

		var action := Button.new()
		action.custom_minimum_size = Vector2(140, 34)
		var enabled := true
		if mode == Mode.SAVE:
			action.text = LocaleServiceScript.t("save.button_save") if not exists else LocaleServiceScript.t("save.button_overwrite")
		else:
			action.text = LocaleServiceScript.t("save.button_load")
			enabled = exists
		action.disabled = not enabled
		action.pressed.connect(Callable(self, "_on_slot_pressed").bind(slot))
		if mode == Mode.SAVE and not exists:
			UiThemeScript.apply_accent_state(action, true)
		row.add_child(action)
		_row_buttons.append(action)

func _format_slot_label(slot: int, info: Dictionary) -> String:
	if not bool(info.get("exists", false)):
		return LocaleServiceScript.t("save.slot_empty") % slot
	var day := int(info.get("day", 1))
	var hour := int(info.get("hour", 0))
	var minute := int(info.get("minute", 0))
	var label := str(info.get("label", ""))
	var citizens := int(info.get("citizen_count", 0))
	return LocaleServiceScript.t("save.slot_filled") % [slot, day, hour, minute, citizens, label]

func _on_slot_pressed(slot: int) -> void:
	if mode == Mode.SAVE:
		var info := SaveGameServiceScript._describe_slot(slot)
		if bool(info.get("exists", false)) and _pending_overwrite_slot != slot:
			_pending_overwrite_slot = slot
			_set_status(LocaleServiceScript.t("save.status_overwrite") % slot)
			return
	_pending_overwrite_slot = -1
	_set_buttons_disabled(true)
	if _on_slot_chosen.is_valid():
		_on_slot_chosen.call(slot)

func _on_cancel_pressed() -> void:
	if _on_cancelled.is_valid():
		_on_cancelled.call()

func set_status(text: String) -> void:
	_set_status(text)

func set_interaction_enabled(is_enabled: bool) -> void:
	_set_buttons_disabled(not is_enabled)

func _set_status(text: String) -> void:
	if _status_label != null:
		_status_label.text = text

func _set_buttons_disabled(is_disabled: bool) -> void:
	for button in _row_buttons:
		if button != null:
			button.disabled = is_disabled

func _make_separator() -> HSeparator:
	return HSeparator.new()
