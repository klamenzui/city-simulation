extends Camera3D
class_name StrategyCameraController

@export_category("Strategy Camera")
@export var target_position: Vector3 = Vector3.ZERO
@export_range(2.0, 100.0, 0.1) var distance: float = 18.0
@export_range(2.0, 100.0, 0.1) var min_distance: float = 5.0
@export_range(2.0, 140.0, 0.1) var max_distance: float = 55.0
@export_range(-180.0, 180.0, 0.1) var yaw_degrees: float = 0.0
@export_range(-89.0, -10.0, 0.1) var pitch_degrees: float = -52.0
@export_range(-89.0, -20.0, 0.1) var min_pitch_degrees: float = -78.0
@export_range(-60.0, -5.0, 0.1) var max_pitch_degrees: float = -25.0

@export_group("Focus And Reset")
@export var focus_target_path: NodePath
@export var focus_distance: float = 18.0
@export var reset_to_initial_state: bool = true
@export var reset_target_position: Vector3 = Vector3.ZERO
@export var reset_distance: float = 18.0

@export_group("Movement")
@export var movement_enabled: bool = true
@export var movement_speed: float = 15.0
@export var sprint_multiplier: float = 2.0
@export var zoom_speed_scaling: bool = true
@export var edge_scroll_enabled: bool = true
@export var edge_scroll_margin: int = 22
@export var edge_scroll_speed: float = 16.0
@export var use_bounds: bool = false
@export var bounds_min: Vector2 = Vector2(-80.0, -80.0)
@export var bounds_max: Vector2 = Vector2(80.0, 80.0)

@export_group("Mouse")
@export var rotate_mouse_button: MouseButton = MOUSE_BUTTON_RIGHT
@export var pan_mouse_button: MouseButton = MOUSE_BUTTON_MIDDLE
@export var rotate_sensitivity: float = 0.22
@export var pan_sensitivity: float = 0.0035
@export var invert_rotation_x: bool = false
@export var invert_rotation_y: bool = false

@export_group("Zoom")
@export var zoom_step: float = 2.2
@export var zoom_smoothing: float = 12.0
@export var position_smoothing: float = 12.0

@export_group("Keyboard")
@export var keyboard_rotation_enabled: bool = true
@export var keyboard_rotation_speed_degrees: float = 75.0
@export var reset_key: Key = KEY_HOME
@export var focus_key: Key = KEY_F

var _initial_target_position: Vector3 = Vector3.ZERO
var _initial_distance: float = 18.0
var _initial_yaw_degrees: float = 0.0
var _initial_pitch_degrees: float = -52.0

var _wanted_target: Vector3 = Vector3.ZERO
var _wanted_distance: float = 18.0
var _yaw: float = 0.0
var _pitch: float = 0.0
var _wanted_yaw: float = 0.0
var _wanted_pitch: float = 0.0
var _rotating: bool = false
var _panning: bool = false

func _ready() -> void:
	_initial_target_position = target_position
	_initial_distance = distance
	_initial_yaw_degrees = yaw_degrees
	_initial_pitch_degrees = pitch_degrees

	_wanted_target = target_position
	_wanted_distance = clampf(distance, min_distance, max_distance)
	_yaw = deg_to_rad(yaw_degrees)
	_pitch = deg_to_rad(clampf(pitch_degrees, min_pitch_degrees, max_pitch_degrees))
	_wanted_yaw = _yaw
	_wanted_pitch = _pitch
	_apply_camera(true)

func _process(delta: float) -> void:
	if movement_enabled:
		_handle_keyboard_movement(delta)
		_handle_edge_scroll(delta)
		_handle_keyboard_rotation(delta)

	_clamp_target()

	var position_weight := _smooth_weight(position_smoothing, delta)
	var zoom_weight := _smooth_weight(zoom_smoothing, delta)

	target_position = target_position.lerp(_wanted_target, position_weight)
	distance = lerpf(distance, _wanted_distance, zoom_weight)
	_yaw = lerp_angle(_yaw, _wanted_yaw, position_weight)
	_pitch = lerpf(_pitch, _wanted_pitch, position_weight)

	_apply_camera(false)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)
	elif event is InputEventKey and event.pressed and not event.echo:
		_handle_key_press(event)

func reset_camera() -> void:
	if reset_to_initial_state:
		_wanted_target = _initial_target_position
		_wanted_distance = clampf(_initial_distance, min_distance, max_distance)
		_wanted_yaw = deg_to_rad(_initial_yaw_degrees)
		_wanted_pitch = deg_to_rad(clampf(_initial_pitch_degrees, min_pitch_degrees, max_pitch_degrees))
	else:
		_wanted_target = reset_target_position
		_wanted_distance = clampf(reset_distance, min_distance, max_distance)
		_wanted_yaw = deg_to_rad(yaw_degrees)
		_wanted_pitch = deg_to_rad(clampf(pitch_degrees, min_pitch_degrees, max_pitch_degrees))

func focus_on(point: Vector3, new_distance: float = -1.0) -> void:
	_wanted_target = point
	if new_distance > 0.0:
		_wanted_distance = clampf(new_distance, min_distance, max_distance)

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == rotate_mouse_button:
		_rotating = event.pressed
	elif event.button_index == pan_mouse_button:
		_panning = event.pressed
	elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_wanted_distance = clampf(_wanted_distance - zoom_step, min_distance, max_distance)
	elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_wanted_distance = clampf(_wanted_distance + zoom_step, min_distance, max_distance)

func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _rotating:
		var x_factor := -1.0 if invert_rotation_x else 1.0
		var y_factor := -1.0 if invert_rotation_y else 1.0
		_wanted_yaw -= event.relative.x * rotate_sensitivity * 0.01 * x_factor
		_wanted_pitch -= event.relative.y * rotate_sensitivity * 0.01 * y_factor
		_wanted_pitch = clampf(_wanted_pitch, deg_to_rad(min_pitch_degrees), deg_to_rad(max_pitch_degrees))
	elif _panning:
		var axes := _ground_axes()
		var drag_scale := pan_sensitivity * maxf(_wanted_distance, 1.0)
		_wanted_target += (-axes[0] * event.relative.x + axes[1] * event.relative.y) * drag_scale

func _handle_key_press(event: InputEventKey) -> void:
	if event.keycode == reset_key:
		reset_camera()
	elif event.keycode == focus_key:
		_focus_key_target()

func _focus_key_target() -> void:
	if str(focus_target_path) != "":
		var target := get_node_or_null(focus_target_path)
		if target is Node3D:
			focus_on((target as Node3D).global_position, focus_distance)
			return
	focus_on(target_position, focus_distance)

func _handle_keyboard_movement(delta: float) -> void:
	var axes := _ground_axes()
	var direction := Vector3.ZERO

	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		direction += axes[1]
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		direction -= axes[1]
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		direction += axes[0]
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		direction -= axes[0]

	if direction.length_squared() <= 0.0:
		return

	var speed := movement_speed
	if Input.is_key_pressed(KEY_SHIFT):
		speed *= sprint_multiplier
	if zoom_speed_scaling:
		speed *= clampf(_wanted_distance / 18.0, 0.45, 2.5)

	_wanted_target += direction.normalized() * speed * delta

func _handle_edge_scroll(delta: float) -> void:
	if not edge_scroll_enabled:
		return

	var viewport := get_viewport()
	if viewport == null:
		return

	var rect := viewport.get_visible_rect()
	var mouse_pos := viewport.get_mouse_position()
	if not rect.has_point(mouse_pos):
		return

	var axes := _ground_axes()
	var direction := Vector3.ZERO

	if mouse_pos.x <= edge_scroll_margin:
		direction -= axes[0]
	elif mouse_pos.x >= rect.size.x - edge_scroll_margin:
		direction += axes[0]

	if mouse_pos.y <= edge_scroll_margin:
		direction += axes[1]
	elif mouse_pos.y >= rect.size.y - edge_scroll_margin:
		direction -= axes[1]

	if direction.length_squared() > 0.0:
		var speed := edge_scroll_speed
		if zoom_speed_scaling:
			speed *= clampf(_wanted_distance / 18.0, 0.45, 2.5)
		_wanted_target += direction.normalized() * speed * delta

func _handle_keyboard_rotation(delta: float) -> void:
	if not keyboard_rotation_enabled:
		return

	var rotation_speed := deg_to_rad(keyboard_rotation_speed_degrees) * delta
	if Input.is_key_pressed(KEY_Q):
		_wanted_yaw += rotation_speed
	if Input.is_key_pressed(KEY_E):
		_wanted_yaw -= rotation_speed

func _apply_camera(force: bool) -> void:
	var used_target := _wanted_target if force else target_position
	var used_distance := _wanted_distance if force else distance
	var used_yaw := _wanted_yaw if force else _yaw
	var used_pitch := _wanted_pitch if force else _pitch

	var orbit_offset := _orbit_offset(used_yaw, used_pitch, used_distance)
	global_position = used_target + orbit_offset
	look_at(used_target, Vector3.UP)

func _orbit_offset(yaw: float, pitch: float, used_distance: float) -> Vector3:
	var cos_pitch := cos(pitch)
	return Vector3(
		sin(yaw) * cos_pitch,
		-sin(pitch),
		cos(yaw) * cos_pitch
	) * used_distance

func _ground_axes() -> Array[Vector3]:
	var back := Vector3(sin(_wanted_yaw), 0.0, cos(_wanted_yaw)).normalized()
	var forward := -back
	var right := Vector3(cos(_wanted_yaw), 0.0, -sin(_wanted_yaw)).normalized()
	return [right, forward]

func _clamp_target() -> void:
	if not use_bounds:
		return
	_wanted_target.x = clampf(_wanted_target.x, bounds_min.x, bounds_max.x)
	_wanted_target.z = clampf(_wanted_target.z, bounds_min.y, bounds_max.y)
	target_position.x = clampf(target_position.x, bounds_min.x, bounds_max.x)
	target_position.z = clampf(target_position.z, bounds_min.y, bounds_max.y)

func _smooth_weight(speed: float, delta: float) -> float:
	if speed <= 0.0:
		return 1.0
	return 1.0 - exp(-speed * delta)
