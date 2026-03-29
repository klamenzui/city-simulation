extends Camera3D
class_name CityBuilderCamera

@export var pan_speed: float = 14.0
@export var fast_pan_multiplier: float = 2.5
@export var edge_scroll_enabled: bool = true
@export var edge_margin_px: int = 14
@export var edge_pan_factor: float = 1.0

@export var zoom_step: float = 2.2
@export var min_distance: float = 8.0
@export var max_distance: float = 60.0

@export var mouse_rotate_speed: float = 0.006
@export var key_rotate_speed: float = 1.7
@export var min_pitch_deg: float = 28.0
@export var max_pitch_deg: float = 78.0
@export var follow_distance: float = 4.8
@export var follow_pitch_deg: float = 20.0
@export var follow_focus_height: float = 1.25

@export var smoothing: float = 12.0
@export var world_padding: float = 8.0
@export var use_manual_bounds: bool = false
@export var bounds_min_xz: Vector2 = Vector2(-40.0, -40.0)
@export var bounds_max_xz: Vector2 = Vector2(40.0, 40.0)

var _target_center: Vector3 = Vector3.ZERO
var _center: Vector3 = Vector3.ZERO
var _target_yaw: float = 0.0
var _yaw: float = 0.0
var _target_pitch: float = 45.0
var _pitch: float = 45.0
var _target_distance: float = 24.0
var _distance: float = 24.0

var _bounds_min: Vector2 = Vector2(-40.0, -40.0)
var _bounds_max: Vector2 = Vector2(40.0, 40.0)
var _ground_y: float = 0.0
var _rotating: bool = false
var _follow_mode: bool = false
var _follow_target: Node3D = null

func _ready() -> void:
	current = true
	_resolve_ground_height()
	_resolve_bounds()
	_initialize_from_transform()

func _process(delta: float) -> void:
	if _follow_mode:
		_update_follow_targets(delta)
		return

	_update_pan(delta)
	_update_key_rotation(delta)
	_clamp_targets()

	var t: float = 1.0 - exp(-smoothing * delta)
	_center = _center.lerp(_target_center, t)
	_yaw = lerp_angle(_yaw, _target_yaw, t)
	_pitch = lerpf(_pitch, _target_pitch, t)
	_distance = lerpf(_distance, _target_distance, t)

	_apply_camera_transform()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
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
		_target_yaw -= mm.relative.x * mouse_rotate_speed
		_target_pitch += mm.relative.y * mouse_rotate_speed * 0.8
		get_viewport().set_input_as_handled()

func _update_pan(delta: float) -> void:
	var move := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		move.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		move.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		move.y += 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		move.y -= 1.0

	if edge_scroll_enabled and not _rotating:
		move += _edge_scroll_vector() * edge_pan_factor

	if move.length_squared() <= 0.0001:
		return

	move = move.normalized()
	var speed: float = pan_speed
	if Input.is_key_pressed(KEY_SHIFT):
		speed *= fast_pan_multiplier

	var forward := Vector3.FORWARD.rotated(Vector3.UP, _target_yaw).normalized()
	var right := Vector3.RIGHT.rotated(Vector3.UP, _target_yaw).normalized()
	var delta_move := (right * move.x + forward * move.y) * speed * delta
	_target_center += delta_move

func _update_key_rotation(delta: float) -> void:
	if Input.is_key_pressed(KEY_Q):
		_target_yaw += key_rotate_speed * delta
	if Input.is_key_pressed(KEY_E):
		_target_yaw -= key_rotate_speed * delta

func _edge_scroll_vector() -> Vector2:
	var view := get_viewport()
	if view == null:
		return Vector2.ZERO

	var size: Vector2 = view.get_visible_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		return Vector2.ZERO

	var mouse: Vector2 = view.get_mouse_position()
	var rect := Rect2(Vector2.ZERO, size)
	if not rect.has_point(mouse):
		return Vector2.ZERO

	var dir := Vector2.ZERO
	if mouse.x <= edge_margin_px:
		dir.x -= 1.0
	elif mouse.x >= size.x - edge_margin_px:
		dir.x += 1.0

	if mouse.y <= edge_margin_px:
		dir.y += 1.0
	elif mouse.y >= size.y - edge_margin_px:
		dir.y -= 1.0

	return dir

func _clamp_targets() -> void:
	_target_pitch = clampf(_target_pitch, min_pitch_deg, max_pitch_deg)
	_target_distance = clampf(_target_distance, min_distance, max_distance)

	_target_center.y = _ground_y
	_target_center.x = clampf(_target_center.x, _bounds_min.x, _bounds_max.x)
	_target_center.z = clampf(_target_center.z, _bounds_min.y, _bounds_max.y)

func _apply_camera_transform() -> void:
	var pitch_rad := deg_to_rad(_pitch)
	var horizontal := cos(pitch_rad) * _distance
	var offset := Vector3(
		sin(_yaw) * horizontal,
		sin(pitch_rad) * _distance,
		cos(_yaw) * horizontal
	)

	global_position = _center + offset
	look_at(_center, Vector3.UP)

func _update_follow_targets(delta: float) -> void:
	if _follow_target == null or not is_instance_valid(_follow_target):
		clear_follow_target()
		return

	_update_key_rotation(delta)
	_target_pitch = clampf(follow_pitch_deg, min_pitch_deg, max_pitch_deg)
	_target_distance = clampf(follow_distance, min_distance, max_distance)
	_target_center = _follow_target.global_position + Vector3.UP * follow_focus_height

	var t: float = 1.0 - exp(-smoothing * delta)
	_center = _center.lerp(_target_center, t)
	_yaw = lerp_angle(_yaw, _target_yaw, t)
	_pitch = lerpf(_pitch, _target_pitch, t)
	_distance = lerpf(_distance, _target_distance, t)

	_apply_camera_transform()

func _resolve_ground_height() -> void:
	_ground_y = 0.0
	var root := get_parent()
	if root == null:
		return
	var world := root.get_node_or_null("World")
	if world != null and world.has_method("get_ground_fallback_y"):
		_ground_y = float(world.call("get_ground_fallback_y"))

func _resolve_bounds() -> void:
	if use_manual_bounds:
		_bounds_min = Vector2(
			minf(bounds_min_xz.x, bounds_max_xz.x),
			minf(bounds_min_xz.y, bounds_max_xz.y)
		)
		_bounds_max = Vector2(
			maxf(bounds_min_xz.x, bounds_max_xz.x),
			maxf(bounds_min_xz.y, bounds_max_xz.y)
		)
		return

	var has_points := false
	var min_x := 0.0
	var max_x := 0.0
	var min_z := 0.0
	var max_z := 0.0

	for group_name in ["buildings", "road_group"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if node is not Node3D:
				continue
			var p := (node as Node3D).global_position
			if not has_points:
				has_points = true
				min_x = p.x
				max_x = p.x
				min_z = p.z
				max_z = p.z
			else:
				min_x = minf(min_x, p.x)
				max_x = maxf(max_x, p.x)
				min_z = minf(min_z, p.z)
				max_z = maxf(max_z, p.z)

	if not has_points:
		var root := get_parent()
		var world_node: Node = null
		if root != null:
			world_node = root.get_node_or_null("World")
		if world_node != null and world_node.has_method("get_world_bounds"):
			var bounds: AABB = world_node.call("get_world_bounds")
			min_x = bounds.position.x
			max_x = bounds.position.x + bounds.size.x
			min_z = bounds.position.z
			max_z = bounds.position.z + bounds.size.z
			has_points = true

	if not has_points:
		min_x = global_position.x - 40.0
		max_x = global_position.x + 40.0
		min_z = global_position.z - 40.0
		max_z = global_position.z + 40.0

	_bounds_min = Vector2(min_x - world_padding, min_z - world_padding)
	_bounds_max = Vector2(max_x + world_padding, max_z + world_padding)

func _initialize_from_transform() -> void:
	var forward := -global_transform.basis.z.normalized()
	if absf(forward.y) < 0.02:
		forward.y = -0.35
		forward = forward.normalized()

	var t := 0.0
	if absf(forward.y) > 0.001:
		t = (_ground_y - global_position.y) / forward.y
	if t <= 0.1:
		t = 24.0

	_target_center = global_position + forward * t
	_target_center.y = _ground_y

	_target_distance = clampf(global_position.distance_to(_target_center), min_distance, max_distance)

	var offset := global_position - _target_center
	_target_yaw = atan2(offset.x, offset.z)
	var safe_distance := maxf(_target_distance, 0.001)
	_target_pitch = rad_to_deg(asin(clampf(offset.y / safe_distance, -0.99, 0.99)))
	_target_pitch = clampf(_target_pitch, min_pitch_deg, max_pitch_deg)

	_center = _target_center
	_yaw = _target_yaw
	_pitch = _target_pitch
	_distance = _target_distance
	_clamp_targets()
	_apply_camera_transform()

func focus_on_world_position(pos: Vector3) -> void:
	clear_follow_target()
	_target_center = Vector3(pos.x, _ground_y, pos.z)
	_clamp_targets()

func set_follow_target(target: Node3D) -> void:
	_follow_target = target
	_follow_mode = target != null
	if not _follow_mode:
		return
	var focus := target.global_position + Vector3.UP * follow_focus_height
	_target_center = focus
	_center = focus
	_target_pitch = clampf(follow_pitch_deg, min_pitch_deg, max_pitch_deg)
	_pitch = _target_pitch
	_target_distance = clampf(follow_distance, min_distance, max_distance)
	_distance = _target_distance
	var target_forward := -target.global_transform.basis.z
	target_forward.y = 0.0
	if target_forward.length_squared() <= 0.0001:
		target_forward = Vector3.FORWARD
	else:
		target_forward = target_forward.normalized()
	var behind_dir := -target_forward
	_target_yaw = atan2(behind_dir.x, behind_dir.z)
	_yaw = _target_yaw
	_apply_camera_transform()

func clear_follow_target() -> void:
	_follow_mode = false
	_follow_target = null
	_resolve_ground_height()
	_clamp_targets()

func is_follow_mode() -> bool:
	return _follow_mode
