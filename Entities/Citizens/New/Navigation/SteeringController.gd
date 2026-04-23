class_name SteeringController
extends RefCounted

## Layer 4 of the 4-layer navigation pipeline (Navigation.md §Motion / Steering).
##
## Pure motion/smoothing — no pathfinding, no perception.  Consumed direction
## is one of:
##   - the direct-to-waypoint vector (normal following), or
##   - the first edge of the local A* detour path (avoidance active).
##
## The caller decides which; this module only smooths, blends corners and
## produces a stable output direction.

var _smoothed_direction: Vector3 = Vector3.ZERO


## Returns a unit vector — the smoothed move direction for this frame.
## `target_direction` is the freshly chosen direction; `fallback` is used when
## the target has zero magnitude (waypoint exactly at citizen position).
## `smoothing` is the exponential smoothing strength from config.
func smooth(target_direction: Vector3, fallback: Vector3, delta: float, smoothing: float) -> Vector3:
	var target := target_direction
	target.y = 0.0
	if target.length_squared() <= 0.0001:
		target = fallback
		target.y = 0.0
	if target.length_squared() <= 0.0001:
		return Vector3.ZERO

	target = target.normalized()
	if _smoothed_direction.length_squared() <= 0.0001:
		_smoothed_direction = target
		return target

	if smoothing <= 0.0:
		_smoothed_direction = target
		return target

	var blend := 1.0 - exp(-maxf(smoothing, 0.0) * delta)
	_smoothed_direction = _smoothed_direction.lerp(target, blend)
	_smoothed_direction.y = 0.0
	if _smoothed_direction.length_squared() <= 0.0001:
		_smoothed_direction = target
	else:
		_smoothed_direction = _smoothed_direction.normalized()
	return _smoothed_direction


func reset() -> void:
	_smoothed_direction = Vector3.ZERO


func last_direction() -> Vector3:
	return _smoothed_direction


## Corner-blend: when the citizen approaches a waypoint that is NOT the final
## one, biases the aim-point toward the NEXT waypoint so the turn becomes a
## curve instead of a hard angle.
##
## Called by the controller when computing the per-frame `move_target`.
static func blend_corner(
		global_path: PackedVector3Array,
		path_index: int,
		owner_pos: Vector3,
		blend_distance: float,
		blend_strength: float) -> Vector3:
	if global_path.is_empty() or path_index < 0 or path_index >= global_path.size():
		return global_path[global_path.size() - 1] if not global_path.is_empty() else owner_pos

	var move_target := global_path[path_index]
	if path_index >= global_path.size() - 1:
		return move_target

	var current_delta := move_target - owner_pos
	current_delta.y = 0.0
	var current_distance := current_delta.length()
	var bd := maxf(blend_distance, 0.05)
	if current_distance >= bd:
		return move_target

	var next_point := global_path[path_index + 1]
	var blend_t := 1.0 - clampf(current_distance / bd, 0.0, 1.0)
	var blend_weight := clampf(blend_t * blend_strength, 0.0, 0.8)
	var blended := move_target.lerp(next_point, blend_weight)
	blended.y = lerpf(move_target.y, next_point.y, blend_weight)
	return blended
