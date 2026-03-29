extends CanvasLayer
class_name DebugPanel

signal citizen_control_toggled
signal ui_interacted

@onready var panel_root: Panel = $Panel
@onready var label: RichTextLabel = $Panel/VBoxContainer/Label
@onready var citizen_control_button: Button = $Panel/VBoxContainer/CitizenControlButton
var dbug_data: Dictionary = {}

func _ready() -> void:
	if panel_root != null:
		panel_root.gui_input.connect(_on_panel_gui_input)
	if citizen_control_button != null:
		citizen_control_button.visible = false
		citizen_control_button.gui_input.connect(_on_panel_gui_input)
		citizen_control_button.pressed.connect(_on_citizen_control_button_pressed)

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

func _on_citizen_control_button_pressed() -> void:
	ui_interacted.emit()
	citizen_control_toggled.emit()
	citizen_control_button.visible = false

func _on_panel_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		ui_interacted.emit()

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
