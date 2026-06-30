@tool
extends Node3D
class_name WaterBuoyancy

## Makes an object float and bob on the LowPolyWaterPlane.
##
## Drop this as a child of the floating object (or point target_path at it) and
## set water_path to the water plane. Each physics frame it lifts the target to
## the wave surface (LowPolyWaterPlane.get_height) and gently tilts it to the
## wave normal. Heavy-physics buoyancy is out of scope; this is a cheap visual
## bob meant for decorative boats.

@export var water_path: NodePath
## Node to float. Leave empty to float this node's parent.
@export var target_path: NodePath
@export var height_offset: float = 0.0
@export var follow_smoothing: float = 6.0
@export var align_to_waves: bool = true
@export_range(0.0, 45.0, 1.0) var max_tilt_deg: float = 10.0
## World-space distance used to sample the wave slope for tilting.
@export var sample_spread: float = 1.5

@export_category("Wake Foam")
## Report a wake to the water when this object moves. Static objects do not need
## this (they get the depth intersection-foam rim automatically).
@export var wake_enabled: bool = true
@export var wake_radius: float = 4.0
## Planar speed (units/sec) where the wake starts / reaches full strength.
@export var wake_speed_threshold: float = 1.5
@export var wake_speed_full: float = 8.0

var _water: Node = null
var _target: Node3D = null
var _last_pos: Vector3 = Vector3.ZERO

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_water = get_node_or_null(water_path)
	if target_path.is_empty():
		_target = get_parent() as Node3D
	else:
		_target = get_node_or_null(target_path) as Node3D
	if _target != null:
		_last_pos = _target.global_position

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _water == null or _target == null or not _water.has_method("get_height"):
		return

	var pos := _target.global_position
	var target_h: float = float(_water.get_height(pos)) + height_offset
	var t := 1.0 - exp(-follow_smoothing * delta)
	pos.y = lerpf(pos.y, target_h, t)
	_target.global_position = pos

	# Wake foam when moving fast enough across the surface.
	if wake_enabled and _water.has_method("report_disturbance"):
		var planar := Vector2(pos.x - _last_pos.x, pos.z - _last_pos.z).length() / maxf(delta, 0.0001)
		var strength := clampf((planar - wake_speed_threshold) / maxf(wake_speed_full - wake_speed_threshold, 0.001), 0.0, 1.0)
		if strength > 0.01:
			_water.report_disturbance(pos, wake_radius, strength)
	_last_pos = pos

	if not align_to_waves or not _water.has_method("get_normal"):
		return

	var n: Vector3 = _water.get_normal(pos, sample_spread)
	# Limit tilt: blend the surface normal toward straight up past the max angle.
	var up_angle := Vector3.UP.angle_to(n)
	var max_rad := deg_to_rad(max_tilt_deg)
	if up_angle > max_rad and up_angle > 0.0001:
		n = Vector3.UP.slerp(n, max_rad / up_angle).normalized()

	# Keep the boat's heading, just re-level its up axis onto the waves.
	var basis := _target.global_transform.basis.orthonormalized()
	var fwd := basis.z
	var right := n.cross(fwd)
	if right.length() < 0.0001:
		right = basis.x
	right = right.normalized()
	fwd = right.cross(n).normalized()
	var target_basis := Basis(right, n, fwd)
	_target.global_transform.basis = basis.slerp(target_basis, t).orthonormalized()
