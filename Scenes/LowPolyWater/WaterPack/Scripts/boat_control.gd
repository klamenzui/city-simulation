extends Node3D
## Simple keyboard-driven test boat to check the water wake.
##
## Controls (separate from the camera keys):
##   B     = switch the camera to follow this boat (press again to release)
##   I / K = forward / backward
##   J / L = turn left / right
## WaterBuoyancy floats it on the waves; driving fast leaves a foam wake.

@export var move_speed: float = 18.0
@export var turn_speed: float = 1.9
@export var enabled: bool = true

var _following := false

func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_B:
		_toggle_follow()
		get_viewport().set_input_as_handled()

func _toggle_follow() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or not cam.has_method("set_follow_target"):
		return
	_following = not _following
	if _following:
		cam.call("set_follow_target", self, false)
	elif cam.has_method("clear_follow_target"):
		cam.call("clear_follow_target")

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or not enabled:
		return

	var fwd := 0.0
	var turn := 0.0
	if Input.is_key_pressed(KEY_I):
		fwd += 1.0
	if Input.is_key_pressed(KEY_K):
		fwd -= 1.0
	if Input.is_key_pressed(KEY_J):
		turn += 1.0
	if Input.is_key_pressed(KEY_L):
		turn -= 1.0

	if turn != 0.0:
		rotate_y(turn * turn_speed * delta)
	if fwd != 0.0:
		var dir := -global_transform.basis.z
		dir.y = 0.0
		if dir.length() > 0.0001:
			global_position += dir.normalized() * fwd * move_speed * delta
