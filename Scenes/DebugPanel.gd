extends CanvasLayer
class_name DebugPanel

@onready var label: RichTextLabel = $Panel/VBoxContainer/Label
var dbug_data: Dictionary = {}

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

func _format_value(key: String, value: String) -> String:
	var escaped := _escape_bbcode(value)
	if key == "Status" or key == "Open":
		if value.contains("kein Personal") or value.contains("UNSTAFFED"):
			return "[color=#d95c5c]%s[/color]" % escaped
		if value.contains("Geschlossen") or value.contains("CLOSED"):
			return "[color=#d4a05a]%s[/color]" % escaped
		if value.contains("Offen") or value.contains("OPEN"):
			return "[color=#76c68f]%s[/color]" % escaped
	return escaped

func _escape_bbcode(value: String) -> String:
	return value.replace("[", "[lb]").replace("]", "[rb]")
