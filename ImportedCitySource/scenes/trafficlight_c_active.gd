extends Node3D
enum LightColors {
	GREEN,
	YELLOW,
	RED
}

@onready var green_light := %green
@onready var yellow_light := %yellow
@onready var red_light := %red
@export var light_color : LightColors = LightColors.GREEN: set = _switch_light
@export var auto_switch : bool = false: set = _start_auto_swith
func _switch_light(val: LightColors):
	light_color = val
	if not green_light or not yellow_light or not red_light:
		return
	green_light.hide()
	yellow_light.hide()
	red_light.hide()
	if val == LightColors.GREEN:
		green_light.show()
	elif val == LightColors.YELLOW:
		yellow_light.show()
	elif val == LightColors.RED:
		red_light.show()

func _auto_swith():
	if !auto_switch or !get_tree(): return
	if light_color == LightColors.RED:
		light_color = LightColors.GREEN
		await get_tree().create_timer(5.0).timeout
	if light_color == LightColors.GREEN:
		light_color = LightColors.YELLOW
		await get_tree().create_timer(2.0).timeout
	if light_color == LightColors.YELLOW:
		light_color = LightColors.RED
		await get_tree().create_timer(5.0).timeout
	_auto_swith()
	
func _start_auto_swith(val: bool):
	auto_switch = val
	#if val:
	#	_auto_swith()
		
func _ready() -> void:
	var grad = abs(int(rad_to_deg(rotation.y)))
	var color = 0
	if grad == 90:
		color = 2
	light_color = color
	_auto_swith()
