extends Node3D
class_name PlayerThirdPersonCamera

## Decoupled 3rd-person camera rig for the locally controlled player citizen.
##
## The rig follows the player's POSITION only; it owns its own yaw/pitch so the
## citizen body's per-frame look_at() does not rotate the camera. A SpringArm3D
## prevents wall/building clipping. Built fully in code (project has no UI/.tscn
## convention for runtime nodes). The inner Camera3D is the node that becomes
## `current`; CameraModeManager owns the activation so exactly one camera is
## ever current.
##
## Scene shape built on setup():
##   PlayerThirdPersonCamera (Node3D, this)
##    └── SpringArm3D
##         └── Camera3D

## Initial SpringArm distance from the player focus point. Runtime zoom clamps
## this value into the min/max distance range.
@export var follow_distance: float = 0.8
@export var min_distance: float = 0.5
@export var max_distance: float = 9.0
@export var zoom_step: float = 0.6
@export var focus_height: float = 0.7
@export var pitch_deg: float = 16.0
@export var min_pitch_deg: float = -8.0
@export var max_pitch_deg: float = 62.0
@export var position_smoothing: float = 16.0
@export var rotation_smoothing: float = 14.0
@export var mouse_sensitivity: float = 0.006
@export var stick_sensitivity: float = 2.6
@export var stick_deadzone: float = 0.15
## Static-world layers the spring arm collides against. Defaults to layer 1
## (city/world static geometry). The target body is excluded explicitly.
@export_flags_3d_physics var spring_collision_mask: int = 1

var _spring_arm: SpringArm3D = null
var _camera: Camera3D = null
var _target: Node3D = null

var _yaw: float = 0.0
var _target_yaw: float = 0.0
var _pitch: float = 16.0
var _target_pitch: float = 16.0
var _distance: float = 5.2
var _target_distance: float = 5.2
var _rotating: bool = false
var _input_locked: bool = false
var _built: bool = false


func setup() -> void:
	_ensure_built()


func _ready() -> void:
	_ensure_built()
	set_process(true)


func _ensure_built() -> void:
	if _built:
		return
	_target_pitch = pitch_deg
	_pitch = pitch_deg
	_target_distance = follow_distance
	_distance = follow_distance

	_spring_arm = SpringArm3D.new()
	_spring_arm.name = "SpringArm3D"
	_spring_arm.spring_length = _distance
	_spring_arm.collision_mask = spring_collision_mask
	_spring_arm.margin = 0.2
	add_child(_spring_arm)

	_camera = Camera3D.new()
	_camera.name = "ThirdPersonCamera"
	_camera.current = false
	_spring_arm.add_child(_camera)
	_built = true


func get_camera() -> Camera3D:
	_ensure_built()
	return _camera


func set_target(target: Node3D) -> void:
	if target == _target:
		return
	_target = target
	if _target == null or not is_instance_valid(_target):
		return
	_ensure_built()
	# Start behind the target's current facing so the first frame is stable.
	var forward := -_target.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() > 0.0001:
		_target_yaw = atan2(forward.x, forward.z)
		_yaw = _target_yaw
	global_position = _focus_point()


func get_target() -> Node3D:
	if _target == null or not is_instance_valid(_target):
		return null
	return _target


func has_target() -> bool:
	return get_target() != null


func activate() -> void:
	_ensure_built()
	_camera.current = true


func deactivate() -> void:
	if _camera != null:
		_camera.current = false


func is_active() -> bool:
	return _camera != null and _camera.current


func set_input_locked(locked: bool) -> void:
	_input_locked = locked
	if locked:
		_rotating = false


func is_input_locked() -> bool:
	return _input_locked


func _process(delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		return
	if not _should_block_input():
		_apply_stick_look(delta)

	_target_pitch = clampf(_target_pitch, min_pitch_deg, max_pitch_deg)
	_target_distance = clampf(_target_distance, min_distance, max_distance)

	var rot_t := 1.0 - exp(-rotation_smoothing * delta)
	var pos_t := 1.0 - exp(-position_smoothing * delta)
	_yaw = lerp_angle(_yaw, _target_yaw, rot_t)
	_pitch = lerpf(_pitch, _target_pitch, rot_t)
	_distance = lerpf(_distance, _target_distance, rot_t)

	global_position = global_position.lerp(_focus_point(), pos_t)
	rotation = Vector3(0.0, _yaw, 0.0)
	_spring_arm.rotation = Vector3(deg_to_rad(_pitch), 0.0, 0.0)
	_spring_arm.spring_length = _distance

	# SpringArm3D positions the camera; re-aim it at the focus point so it
	# always frames the player regardless of spring retraction.
	var pivot := global_position
	var cam_pos := _camera.global_position
	if cam_pos.distance_squared_to(pivot) > 0.0009:
		_camera.look_at(pivot, Vector3.UP)


func _focus_point() -> Vector3:
	return _target.global_position + Vector3.UP * focus_height


func _apply_stick_look(delta: float) -> void:
	var stick_x := Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var stick_y := Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	if absf(stick_x) <= stick_deadzone:
		stick_x = 0.0
	if absf(stick_y) <= stick_deadzone:
		stick_y = 0.0
	if stick_x == 0.0 and stick_y == 0.0:
		return
	_target_yaw -= stick_x * stick_sensitivity * delta
	_target_pitch -= stick_y * stick_sensitivity * delta * 40.0


func _unhandled_input(event: InputEvent) -> void:
	if not is_active():
		return
	if _should_block_input():
		_rotating = false
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_rotating = mb.pressed
			get_viewport().set_input_as_handled()
			return
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_target_distance -= zoom_step
			get_viewport().set_input_as_handled()
			return
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_target_distance += zoom_step
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseMotion and _rotating:
		var mm := event as InputEventMouseMotion
		_target_yaw -= mm.relative.x * mouse_sensitivity
		_target_pitch -= mm.relative.y * mouse_sensitivity * 40.0
		get_viewport().set_input_as_handled()


func _should_block_input() -> bool:
	if _input_locked:
		return true
	var viewport := get_viewport()
	if viewport == null:
		return false
	var focus_owner: Control = viewport.gui_get_focus_owner()
	return focus_owner is LineEdit or focus_owner is TextEdit
