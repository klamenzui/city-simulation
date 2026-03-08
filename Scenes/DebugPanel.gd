extends CanvasLayer
class_name DebugPanel

@onready var label: Label = $Panel/VBoxContainer/Label
var dbug_data: Dictionary = {}

func update_debug(data: Dictionary):
	var text := ""
	for key in data.keys():
		dbug_data.set(key, str(data[key]))
	for key in dbug_data.keys():
		text += "%s: %s\n" % [key, str(dbug_data[key])]
	label.text = text
	#print(text)
