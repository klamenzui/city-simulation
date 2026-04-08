extends CanvasLayer
class_name DebugPanel

signal citizen_control_toggled
signal citizen_click_move_toggled
signal citizen_dialog_toggled
signal citizen_dialog_message_submitted(message: String)
signal ui_interacted

@onready var panel_root: Panel = $Panel
@onready var label: RichTextLabel = $Panel/VBoxContainer/Label
@onready var citizen_control_button: Button = $Panel/VBoxContainer/CitizenControlButton
@onready var citizen_click_move_button: Button = $Panel/VBoxContainer/CitizenClickMoveButton
@onready var citizen_dialog_button: Button = $Panel/VBoxContainer/CitizenDialogButton
@onready var citizen_dialog_status_label: Label = $Panel/VBoxContainer/CitizenDialogStatusLabel
@onready var citizen_dialog_log: RichTextLabel = $Panel/VBoxContainer/CitizenDialogLog
@onready var citizen_dialog_input_row: HBoxContainer = $Panel/VBoxContainer/CitizenDialogInputRow
@onready var citizen_dialog_line_edit: LineEdit = $Panel/VBoxContainer/CitizenDialogInputRow/CitizenDialogLineEdit
@onready var citizen_dialog_send_button: Button = $Panel/VBoxContainer/CitizenDialogInputRow/CitizenDialogSendButton
var dbug_data: Dictionary = {}

func _ready() -> void:
	if panel_root != null:
		panel_root.gui_input.connect(_on_panel_gui_input)
	if citizen_control_button != null:
		citizen_control_button.visible = false
		citizen_control_button.focus_mode = Control.FOCUS_NONE
		citizen_control_button.gui_input.connect(_on_panel_gui_input)
		citizen_control_button.pressed.connect(_on_citizen_control_button_pressed)
	if citizen_click_move_button != null:
		citizen_click_move_button.visible = false
		citizen_click_move_button.focus_mode = Control.FOCUS_NONE
		citizen_click_move_button.gui_input.connect(_on_panel_gui_input)
		citizen_click_move_button.pressed.connect(_on_citizen_click_move_button_pressed)
	if citizen_dialog_button != null:
		citizen_dialog_button.visible = false
		citizen_dialog_button.focus_mode = Control.FOCUS_NONE
		citizen_dialog_button.gui_input.connect(_on_panel_gui_input)
		citizen_dialog_button.pressed.connect(_on_citizen_dialog_button_pressed)
	if citizen_dialog_status_label != null:
		citizen_dialog_status_label.visible = false
	if citizen_dialog_log != null:
		citizen_dialog_log.visible = false
	if citizen_dialog_input_row != null:
		citizen_dialog_input_row.visible = false
	if citizen_dialog_line_edit != null:
		citizen_dialog_line_edit.gui_input.connect(_on_panel_gui_input)
		citizen_dialog_line_edit.text_submitted.connect(_on_citizen_dialog_text_submitted)
	if citizen_dialog_send_button != null:
		citizen_dialog_send_button.focus_mode = Control.FOCUS_NONE
		citizen_dialog_send_button.gui_input.connect(_on_panel_gui_input)
		citizen_dialog_send_button.pressed.connect(_on_citizen_dialog_send_button_pressed)

func update_debug(data: Dictionary) -> void:
	dbug_data = {}

	for key in data.keys():
		dbug_data.set(key, str(data[key]))

	var lines: PackedStringArray = []
	for key in dbug_data.keys():
		var formatted_key := "[b]%s:[/b]" % _escape_bbcode(str(key))
		var formatted_value := _format_value(str(key), str(dbug_data[key]))
		lines.append("%s %s" % [formatted_key, formatted_value])

	label.clear()
	label.append_text("\n".join(lines))

func set_citizen_control_button_visible(is_visible: bool) -> void:
	if citizen_control_button == null:
		return
	citizen_control_button.visible = is_visible

func set_citizen_control_active(is_active: bool) -> void:
	if citizen_control_button == null:
		return
	citizen_control_button.text = "Exit Control Mode" if is_active else "Control Citizen"

func set_citizen_click_move_button_visible(is_visible: bool) -> void:
	if citizen_click_move_button == null:
		return
	citizen_click_move_button.visible = is_visible

func set_citizen_click_move_active(is_active: bool) -> void:
	if citizen_click_move_button == null:
		return
	citizen_click_move_button.text = "Exit Click Move" if is_active else "Click Move Citizen"

func update_citizen_dialog(ui_state: Dictionary) -> void:
	var visible := bool(ui_state.get("visible", false))
	if citizen_dialog_button != null:
		citizen_dialog_button.visible = visible and bool(ui_state.get("button_visible", true))
		citizen_dialog_button.disabled = not bool(ui_state.get("button_enabled", false))
		citizen_dialog_button.text = str(ui_state.get("button_text", "Start Dialog"))
	if citizen_dialog_status_label != null:
		citizen_dialog_status_label.visible = visible
		citizen_dialog_status_label.text = str(ui_state.get("status_text", ""))
	if citizen_dialog_log != null:
		citizen_dialog_log.visible = visible and bool(ui_state.get("log_visible", false))
		_refresh_citizen_dialog_log(ui_state)
	if citizen_dialog_input_row != null:
		citizen_dialog_input_row.visible = visible and bool(ui_state.get("input_visible", false))
	if citizen_dialog_line_edit != null:
		citizen_dialog_line_edit.editable = bool(ui_state.get("input_enabled", false))
		citizen_dialog_line_edit.placeholder_text = str(ui_state.get("input_placeholder", "Type a message..."))
	if citizen_dialog_send_button != null:
		citizen_dialog_send_button.disabled = not bool(ui_state.get("send_enabled", false))

func clear_citizen_dialog_input() -> void:
	if citizen_dialog_line_edit != null:
		citizen_dialog_line_edit.clear()

func focus_citizen_dialog_input() -> void:
	if citizen_dialog_line_edit == null or not citizen_dialog_line_edit.editable:
		return
	citizen_dialog_line_edit.grab_focus()
	citizen_dialog_line_edit.caret_column = citizen_dialog_line_edit.text.length()

func _on_citizen_control_button_pressed() -> void:
	ui_interacted.emit()
	citizen_control_toggled.emit()
	citizen_control_button.visible = false

func _on_citizen_click_move_button_pressed() -> void:
	ui_interacted.emit()
	citizen_click_move_toggled.emit()
	citizen_click_move_button.visible = false

func _on_citizen_dialog_button_pressed() -> void:
	ui_interacted.emit()
	citizen_dialog_toggled.emit()

func _on_citizen_dialog_send_button_pressed() -> void:
	_submit_citizen_dialog_message()

func _on_citizen_dialog_text_submitted(_text: String) -> void:
	_submit_citizen_dialog_message()

func _on_panel_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		ui_interacted.emit()

func _submit_citizen_dialog_message() -> void:
	if citizen_dialog_line_edit == null:
		return
	var text := citizen_dialog_line_edit.text.strip_edges()
	if text.is_empty():
		return
	ui_interacted.emit()
	citizen_dialog_message_submitted.emit(text)
	citizen_dialog_line_edit.clear()

func _refresh_citizen_dialog_log(ui_state: Dictionary) -> void:
	if citizen_dialog_log == null:
		return
	var lines: PackedStringArray = []
	var recent_summary := str(ui_state.get("recent_summary", "")).strip_edges()
	if not recent_summary.is_empty():
		lines.append("[i]Earlier:[/i] %s" % _escape_bbcode(recent_summary))
	var messages: Variant = ui_state.get("messages", [])
	if messages is Array:
		for raw_message in messages:
			if raw_message is not Dictionary:
				continue
			var message := raw_message as Dictionary
			lines.append("[b]%s:[/b] %s" % [
				_escape_bbcode(str(message.get("speaker", ""))),
				_escape_bbcode(str(message.get("text", "")))
			])
	var pending_error := str(ui_state.get("pending_error", "")).strip_edges()
	if not pending_error.is_empty():
		lines.append("[color=#d88c57]%s[/color]" % _escape_bbcode(pending_error))
	citizen_dialog_log.clear()
	citizen_dialog_log.append_text("\n".join(lines))

func _format_value(key: String, value: String) -> String:
	var escaped := _escape_bbcode(value)
	if key == "Status" or key == "Open":
		if value.contains("kein Budget") or value.contains("NO_FUNDS"):
			return "[color=#c64d4d]%s[/color]" % escaped
		if value.contains("unterfinanziert") or value.contains("UNDERFUNDED"):
			return "[color=#d0b35f]%s[/color]" % escaped
		if value.contains("angeschlagen") or value.contains("STRUGGLING"):
			return "[color=#d88c57]%s[/color]" % escaped
		if value.contains("kein Personal") or value.contains("UNSTAFFED"):
			return "[color=#d95c5c]%s[/color]" % escaped
		if value.contains("Geschlossen") or value.contains("CLOSED"):
			return "[color=#d4a05a]%s[/color]" % escaped
		if value.contains("Offen") or value.contains("OPEN"):
			return "[color=#76c68f]%s[/color]" % escaped
	if key == "Financial state":
		if value.contains("Unterfinanziert"):
			return "[color=#d0b35f]%s[/color]" % escaped
		if value.contains("Angeschlagen"):
			return "[color=#d88c57]%s[/color]" % escaped
		if value.contains("Geschlossen"):
			return "[color=#c64d4d]%s[/color]" % escaped
		if value.contains("Stabil"):
			return "[color=#76c68f]%s[/color]" % escaped
	return escaped

func _escape_bbcode(value: String) -> String:
	return value.replace("[", "[lb]").replace("]", "[rb]")
