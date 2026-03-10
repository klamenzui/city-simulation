extends CanvasLayer
class_name DebugPanel

@onready var label: Label = $Panel/VBoxContainer/Label
var dbug_data: Dictionary = {}

func update_debug(data: Dictionary) -> void:
	dbug_data = {}

	for key in data.keys():
		dbug_data.set(key, str(data[key]))

	var lines: PackedStringArray = []
	for key in dbug_data.keys():
		lines.append("%s: %s" % [key, str(dbug_data[key])])

	label.text = "\n".join(lines)
