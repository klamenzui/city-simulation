extends AudioStreamPlayer3D
class_name ShoreWaveAudio

@export_category("Universal Shore Waves")
@export var listener_path: NodePath
@export var shore_points_path: NodePath
@export var shore_points: PackedVector2Array = PackedVector2Array()
@export var closed_loop: bool = true
@export var audio_height: float = 0.12
@export var follow_nearest_shore_point: bool = true
@export var use_camera_target_position: bool = true

@export_group("Fade")
@export var audible_inner: float = 0.0
@export var audible_outer: float = 5.5
@export var max_volume_db: float = -8.0
@export var min_volume_db: float = -80.0
@export var fade_speed: float = 7.0

@export_group("3D Audio")
@export var spatial_max_distance: float = 34.0
@export var spatial_unit_size: float = 1.0

var _listener: Node3D
var _wanted_volume_db: float = -80.0

func _ready() -> void:
	_listener = get_node_or_null(listener_path) as Node3D
	volume_db = min_volume_db
	max_distance = spatial_max_distance
	unit_size = spatial_unit_size
	if not playing:
		play()
	if not finished.is_connected(_restart_loop):
		finished.connect(_restart_loop)

func _process(delta: float) -> void:
	if _listener == null or not is_instance_valid(_listener):
		_listener = _find_listener()
	if _listener == null:
		return

	var points := _get_points()
	if points.size() < 2:
		volume_db = lerpf(volume_db, min_volume_db, 1.0 - exp(-fade_speed * delta))
		return

	var focus_position := _get_focus_position(_listener)
	var nearest := _nearest_point_on_shore(points, Vector2(focus_position.x, focus_position.z))
	var nearest_point: Vector2 = nearest[0]
	var distance_to_shore: float = nearest[1]

	if follow_nearest_shore_point:
		global_position = Vector3(nearest_point.x, audio_height, nearest_point.y)

	var shore_amount := 1.0 - smoothstep(audible_inner, audible_outer, distance_to_shore)
	_wanted_volume_db = lerpf(min_volume_db, max_volume_db, shore_amount)
	volume_db = lerpf(volume_db, _wanted_volume_db, 1.0 - exp(-fade_speed * delta))

func _restart_loop() -> void:
	play()

func _find_listener() -> Node3D:
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		return camera
	return null

func _get_focus_position(listener: Node3D) -> Vector3:
	if use_camera_target_position:
		var target_value = listener.get("target_position")
		if typeof(target_value) == TYPE_VECTOR3:
			return target_value
	return listener.global_position

func _get_points() -> PackedVector2Array:
	var result := PackedVector2Array()
	if str(shore_points_path) != "":
		var root := get_node_or_null(shore_points_path)
		if root != null:
			_collect_points_from_node(root, result)
	if result.size() > 0:
		return result
	return shore_points.duplicate()

func _collect_points_from_node(node: Node, result: PackedVector2Array) -> void:
	for child in node.get_children():
		if child is Marker3D:
			var marker_pos := (child as Marker3D).global_position
			result.append(Vector2(marker_pos.x, marker_pos.z))
		_collect_points_from_node(child, result)

func _nearest_point_on_shore(points: PackedVector2Array, position_xz: Vector2) -> Array:
	var best_point := points[0]
	var best_distance := INF
	var segment_count := points.size() if closed_loop else points.size() - 1
	for i in range(segment_count):
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		var p := _closest_point_on_segment(position_xz, a, b)
		var d := position_xz.distance_to(p)
		if d < best_distance:
			best_distance = d
			best_point = p
	return [best_point, best_distance]

func _closest_point_on_segment(p: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var ab := b - a
	var denom := ab.length_squared()
	if denom < 0.000001:
		return a
	var t := clampf((p - a).dot(ab) / denom, 0.0, 1.0)
	return a + ab * t
