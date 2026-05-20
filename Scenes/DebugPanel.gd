extends CanvasLayer
class_name DebugPanel

const UiThemeScript = preload("res://Simulation/UI/UiTheme.gd")

signal citizen_dialog_toggled
signal citizen_dialog_message_submitted(message: String)
signal player_action_pressed(action_id: String)
signal ui_interacted

@onready var panel_root: Panel = $Panel
@onready var label: RichTextLabel = $Panel/VBoxContainer/Label
@onready var citizen_dialog_button: Button = $Panel/VBoxContainer/CitizenDialogButton
@onready var citizen_dialog_status_label: Label = $Panel/VBoxContainer/CitizenDialogStatusLabel
@onready var citizen_dialog_log: RichTextLabel = $Panel/VBoxContainer/CitizenDialogLog
@onready var citizen_dialog_input_row: HBoxContainer = $Panel/VBoxContainer/CitizenDialogInputRow
@onready var citizen_dialog_line_edit: LineEdit = $Panel/VBoxContainer/CitizenDialogInputRow/CitizenDialogLineEdit
@onready var citizen_dialog_send_button: Button = $Panel/VBoxContainer/CitizenDialogInputRow/CitizenDialogSendButton
var dbug_data: Dictionary = {}
var player_action_container: VBoxContainer = null
var player_action_title_label: Label = null
var player_action_status_label: Label = null
var player_action_button_grid: GridContainer = null
var _player_action_signature: String = ""

func _ready() -> void:
	_apply_theme_and_layout()
	_ensure_player_action_ui()
	if panel_root != null:
		panel_root.gui_input.connect(_on_panel_gui_input)
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


## Applies the shared UI theme and reflows the panel so it matches the rest
## of the HUD (margins, section heading, typography). Called once on _ready.
##
## The .tscn defines absolute offsets (360×760, no margin to the screen edge);
## doing the cleanup in code keeps the scene resource untouched while still
## letting the panel inherit the project-wide Theme via its root Panel node.
func _apply_theme_and_layout() -> void:
	if panel_root == null:
		return

	# Theme on the root Panel; children inherit it through the Control tree.
	panel_root.theme = UiThemeScript.get_or_build()

	var viewport := get_viewport()
	var viewport_width := viewport.get_visible_rect().size.x if viewport != null else 1280.0
	var panel_width := minf(380.0, maxf(300.0, viewport_width * 0.36))

	# Left side panel: top below the time panel, bottom above the action bar.
	panel_root.anchor_left = 0.0
	panel_root.anchor_top = 0.0
	panel_root.anchor_right = 0.0
	panel_root.anchor_bottom = 1.0
	panel_root.offset_left = 12
	panel_root.offset_top = 80
	panel_root.offset_right = 12 + panel_width
	panel_root.offset_bottom = -84
	panel_root.custom_minimum_size = Vector2(panel_width, 0)

	# Internal VBox: anchor full-rect with padding so children breathe.
	var vbox: VBoxContainer = $Panel/VBoxContainer
	if vbox != null:
		vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
		vbox.offset_left = UiThemeScript.PADDING_PANEL_H
		vbox.offset_top = UiThemeScript.PADDING_PANEL_V
		vbox.offset_right = -UiThemeScript.PADDING_PANEL_H
		vbox.offset_bottom = -UiThemeScript.PADDING_PANEL_V
		vbox.add_theme_constant_override("separation", UiThemeScript.SEPARATION_DENSE)

		# Section heading at the top of the VBox.
		var heading := Label.new()
		heading.text = "DETAILS"
		heading.add_theme_color_override("font_color", UiThemeScript.TEXT_MUTED)
		heading.add_theme_font_size_override("font_size", UiThemeScript.FONT_SIZE_SMALL)
		vbox.add_child(heading)
		vbox.move_child(heading, 0)

	# Body typography on the main info RichTextLabel.
	if label != null:
		label.custom_minimum_size = Vector2(maxf(240.0, panel_width - float(UiThemeScript.PADDING_PANEL_H * 2)), 260.0)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.size_flags_vertical = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("normal_font_size", UiThemeScript.FONT_SIZE_BODY)
		label.add_theme_font_size_override("bold_font_size", UiThemeScript.FONT_SIZE_BODY)
		label.add_theme_color_override("default_color", UiThemeScript.TEXT_PRIMARY)
		label.add_theme_constant_override("line_separation", 2)

	# Dialog status label — dimmer than primary so it reads as meta-info.
	if citizen_dialog_status_label != null:
		citizen_dialog_status_label.add_theme_color_override(
				"font_color", UiThemeScript.TEXT_SECONDARY)
		citizen_dialog_status_label.add_theme_font_size_override(
				"font_size", UiThemeScript.FONT_SIZE_SMALL)

	# Dialog log gets a recessed dark background to separate it from the
	# panel's main scroll area.
	if citizen_dialog_log != null:
		citizen_dialog_log.custom_minimum_size = Vector2(maxf(240.0, panel_width - float(UiThemeScript.PADDING_PANEL_H * 2)), 150.0)
		citizen_dialog_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var log_box := StyleBoxFlat.new()
		log_box.bg_color = UiThemeScript.BG_800
		log_box.border_color = UiThemeScript.BORDER
		log_box.border_width_left = UiThemeScript.BORDER_WIDTH
		log_box.border_width_top = UiThemeScript.BORDER_WIDTH
		log_box.border_width_right = UiThemeScript.BORDER_WIDTH
		log_box.border_width_bottom = UiThemeScript.BORDER_WIDTH
		log_box.corner_radius_top_left = UiThemeScript.RADIUS_INPUT
		log_box.corner_radius_top_right = UiThemeScript.RADIUS_INPUT
		log_box.corner_radius_bottom_left = UiThemeScript.RADIUS_INPUT
		log_box.corner_radius_bottom_right = UiThemeScript.RADIUS_INPUT
		log_box.content_margin_left = UiThemeScript.PADDING_INPUT_H
		log_box.content_margin_right = UiThemeScript.PADDING_INPUT_H
		log_box.content_margin_top = UiThemeScript.PADDING_INPUT_V
		log_box.content_margin_bottom = UiThemeScript.PADDING_INPUT_V
		citizen_dialog_log.add_theme_stylebox_override("normal", log_box)
		citizen_dialog_log.add_theme_font_size_override(
				"normal_font_size", UiThemeScript.FONT_SIZE_SMALL)

	# Dialog input row — a bit of breathing room between input and send.
	if citizen_dialog_input_row != null:
		citizen_dialog_input_row.add_theme_constant_override(
				"separation", UiThemeScript.SEPARATION_DENSE)

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


# Structured render path. `sections` is an array of dictionaries:
#   { "title": String, "rows": Array[Dict] }
# Each row:
#   { "label": String, "value": String, "severity": "normal|good|warning|critical" }
# Empty labels render without a prefix. Empty values are skipped so callers can
# pass optional rows without extra call-site branching.
func update_sections(sections: Array) -> void:
	if label == null:
		return
	var lines: PackedStringArray = []
	var first := true
	for section_var in sections:
		if section_var is not Dictionary:
			continue
		var section := section_var as Dictionary
		var rows: Array = section.get("rows", [])
		var rendered_rows := _render_section_rows(rows)
		if rendered_rows.is_empty():
			continue
		if not first:
			lines.append("")
		first = false
		var title := str(section.get("title", ""))
		if not title.is_empty():
			lines.append("[color=#909090]── %s ──[/color]" % _escape_bbcode(title))
		for line in rendered_rows:
			lines.append(line)
	label.clear()
	label.append_text("\n".join(lines))


func update_player_actions(ui_state: Dictionary) -> void:
	_ensure_player_action_ui()
	if player_action_container == null:
		return
	var visible := bool(ui_state.get("visible", false))
	var buttons: Array = ui_state.get("buttons", [])
	player_action_container.visible = visible and not buttons.is_empty()
	if not player_action_container.visible:
		if not _player_action_signature.is_empty():
			_player_action_signature = ""
			_clear_player_action_buttons()
		return
	if player_action_title_label != null:
		player_action_title_label.text = str(ui_state.get("title", "Aktionen"))
	if player_action_status_label != null:
		player_action_status_label.text = str(ui_state.get("status_text", ""))
	# Buttons are only rebuilt when their set/labels/state actually change.
	# update_player_actions runs every frame, so rebuilding unconditionally
	# would destroy/recreate the buttons each frame and kill hover/press
	# feedback (the user can't tell a click registered).
	var signature := _player_action_signature_for(buttons)
	if signature == _player_action_signature:
		return
	_player_action_signature = signature
	_clear_player_action_buttons()
	for spec_var in buttons:
		if spec_var is not Dictionary:
			continue
		var spec := spec_var as Dictionary
		var action_id := str(spec.get("id", ""))
		if action_id.is_empty():
			continue
		var btn := _create_player_panel_button(spec, action_id)
		player_action_button_grid.add_child(btn)
		# The currently-running action is accent-highlighted so it is obvious
		# which action is active vs. merely available.
		if bool(spec.get("active", false)):
			UiThemeScript.apply_accent_state(btn, true)


func _create_player_panel_button(spec: Dictionary, action_id: String) -> Button:
	var btn := Button.new()
	btn.text = str(spec.get("text", action_id))
	btn.disabled = not bool(spec.get("enabled", true))
	btn.tooltip_text = str(spec.get("tooltip", ""))
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(128, 34)
	btn.gui_input.connect(_on_panel_gui_input)
	btn.pressed.connect(_on_player_action_button_pressed.bind(action_id))
	return btn


func _render_section_rows(rows: Array) -> PackedStringArray:
	var out: PackedStringArray = []
	for row_var in rows:
		if row_var is not Dictionary:
			continue
		var row := row_var as Dictionary
		var value_text := str(row.get("value", ""))
		if value_text.is_empty():
			continue
		var label_text := str(row.get("label", ""))
		var severity := str(row.get("severity", "normal"))
		var rendered_value := _format_by_severity(value_text, severity)
		if label_text.is_empty():
			out.append(rendered_value)
		else:
			out.append("[b]%s:[/b] %s" % [_escape_bbcode(label_text), rendered_value])
	return out


func _format_by_severity(value: String, severity: String) -> String:
	var escaped := _escape_bbcode(value)
	match severity:
		"critical":
			return "[color=#d95c5c]%s[/color]" % escaped
		"warning":
			return "[color=#d0b35f]%s[/color]" % escaped
		"good":
			return "[color=#76c68f]%s[/color]" % escaped
		_:
			return escaped


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

func _ensure_player_action_ui() -> void:
	if player_action_container != null:
		return
	var vbox := $Panel/VBoxContainer as VBoxContainer
	if vbox == null:
		return
	player_action_container = VBoxContainer.new()
	player_action_container.visible = false
	player_action_container.add_theme_constant_override("separation", UiThemeScript.SEPARATION_DENSE)
	vbox.add_child(player_action_container)
	if label != null:
		vbox.move_child(player_action_container, label.get_index() + 1)

	player_action_title_label = Label.new()
	player_action_title_label.text = "Aktionen"
	player_action_title_label.add_theme_color_override("font_color", UiThemeScript.TEXT_MUTED)
	player_action_title_label.add_theme_font_size_override("font_size", UiThemeScript.FONT_SIZE_SMALL)
	player_action_container.add_child(player_action_title_label)

	player_action_status_label = Label.new()
	player_action_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	player_action_status_label.add_theme_color_override("font_color", UiThemeScript.TEXT_SECONDARY)
	player_action_status_label.add_theme_font_size_override("font_size", UiThemeScript.FONT_SIZE_SMALL)
	player_action_container.add_child(player_action_status_label)

	player_action_button_grid = GridContainer.new()
	player_action_button_grid.columns = 2
	player_action_button_grid.add_theme_constant_override("h_separation", UiThemeScript.SEPARATION_DENSE)
	player_action_button_grid.add_theme_constant_override("v_separation", UiThemeScript.SEPARATION_DENSE)
	player_action_container.add_child(player_action_button_grid)

func _player_action_signature_for(buttons: Array) -> String:
	var parts: PackedStringArray = []
	for spec_var in buttons:
		if spec_var is not Dictionary:
			continue
		var spec := spec_var as Dictionary
		parts.append("%s|%s|%d|%d|%s" % [
			str(spec.get("id", "")),
			str(spec.get("text", "")),
			1 if bool(spec.get("enabled", true)) else 0,
			1 if bool(spec.get("active", false)) else 0,
			str(spec.get("tooltip", "")),
		])
	return "\n".join(parts)

func _clear_player_action_buttons() -> void:
	if player_action_button_grid == null:
		return
	for child in player_action_button_grid.get_children():
		child.queue_free()

func clear_citizen_dialog_input() -> void:
	if citizen_dialog_line_edit != null:
		citizen_dialog_line_edit.clear()

func focus_citizen_dialog_input() -> void:
	if citizen_dialog_line_edit == null or not citizen_dialog_line_edit.editable:
		return
	citizen_dialog_line_edit.grab_focus()
	citizen_dialog_line_edit.caret_column = citizen_dialog_line_edit.text.length()

func _on_citizen_dialog_button_pressed() -> void:
	ui_interacted.emit()
	citizen_dialog_toggled.emit()

func _on_player_action_button_pressed(action_id: String) -> void:
	ui_interacted.emit()
	player_action_pressed.emit(action_id)

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
