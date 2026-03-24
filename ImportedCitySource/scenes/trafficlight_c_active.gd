extends Node3D
enum LightColors {
	GREEN,
	YELLOW,
	RED
}

const GREEN_DURATION_SEC := 5.0
const YELLOW_DURATION_SEC := 2.0
const RED_DURATION_SEC := 5.0

@onready var green_light := %green
@onready var yellow_light := %yellow
@onready var red_light := %red
var _cycle_timer: Timer = null
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

func _start_auto_swith(val: bool):
	auto_switch = val
	if is_inside_tree():
		_restart_cycle_timer()

func _ready() -> void:
	_ensure_cycle_timer()
	var grad = abs(int(rad_to_deg(rotation.y)))
	var color = 0
	if grad == 90:
		color = 2
	light_color = color
	_restart_cycle_timer()

func _exit_tree() -> void:
	if _cycle_timer != null:
		_cycle_timer.stop()

func _ensure_cycle_timer() -> void:
	if _cycle_timer != null:
		return
	_cycle_timer = Timer.new()
	_cycle_timer.name = "CycleTimer"
	_cycle_timer.one_shot = true
	_cycle_timer.autostart = false
	add_child(_cycle_timer)
	if not _cycle_timer.timeout.is_connected(_on_cycle_timer_timeout):
		_cycle_timer.timeout.connect(_on_cycle_timer_timeout)

func _restart_cycle_timer() -> void:
	if _cycle_timer == null:
		return
	_cycle_timer.stop()
	if not auto_switch:
		return
	_cycle_timer.start(_get_phase_duration(light_color))

func _on_cycle_timer_timeout() -> void:
	if not auto_switch:
		return
	match light_color:
		LightColors.RED:
			light_color = LightColors.GREEN
		LightColors.GREEN:
			light_color = LightColors.YELLOW
		_:
			light_color = LightColors.RED
	_restart_cycle_timer()

func _get_phase_duration(current_light: LightColors) -> float:
	match current_light:
		LightColors.GREEN:
			return GREEN_DURATION_SEC
		LightColors.YELLOW:
			return YELLOW_DURATION_SEC
		_:
			return RED_DURATION_SEC
