class_name JumpController
extends RefCounted

## Low-obstacle jump system.  Owns the down-ray reference and the cooldown
## timer.  Drives the vertical velocity on the owner body when firing.
##
## Design notes carried over from the monolith (all still load-bearing):
##   - Crosswalks never trigger a jump (raised stripe geometry sits in the
##     jump window but walking over it is valid).
##   - Coyote time (0.1s) absorbs 1-2 frame floor gaps at step edges.
##   - Probe is fired in the DIRECT-TO-WAYPOINT direction, not the steered
##     direction — otherwise sideways avoidance makes the ray miss the curb.

var _ctx: NavigationContext
var _down_ray: RayCast3D = null
var _cooldown_timer: float = 0.0
var _coyote_time: float = 0.0
var _last_status: String = "-"


func _init(context: NavigationContext) -> void:
	_ctx = context


## Called by controller once the scene is ready.
func bind_ray(ray: RayCast3D) -> void:
	_down_ray = ray
	if _ctx.config.jump_low_obstacles:
		if _down_ray == null:
			push_warning("JumpController: jump_low_obstacles enabled but ray is null")
			_ctx.logger.error("JUMP", "RAY_MISSING", {})
		else:
			_down_ray.enabled = true


func update_timers(delta: float, is_on_floor: bool) -> void:
	if _cooldown_timer > 0.0:
		_cooldown_timer = maxf(_cooldown_timer - delta, 0.0)
	if is_on_floor:
		_coyote_time = 0.1
	else:
		_coyote_time = maxf(_coyote_time - delta, 0.0)


func is_cooling_down() -> bool:
	return _cooldown_timer > 0.0


func cooldown_remaining() -> float:
	return _cooldown_timer


func status() -> String:
	return _last_status


## Returns true when the close-range down-ray sees a tall obstacle (above jump
## height) ahead.  Used by Perception as one of two probes that decide whether
## a detected obstacle is jumpable — combined with the far-sphere check in
## `LocalPerception.is_obstacle_below_jump_height`, this guards the original
## "low stoop in front of tall wall" stall bug.
##
## `flat_direction` must be planar + normalized.
func near_ray_blocks_above_height(flat_direction: Vector3) -> bool:
	if _down_ray == null or not _down_ray.enabled:
		return false
	_update_ray_target(flat_direction)
	_down_ray.force_raycast_update()
	if not _down_ray.is_colliding():
		return false
	var collider := _down_ray.get_collider()
	# Crosswalks are always walkable — the raised stripe sits in the jump
	# window but must never gate avoidance.
	if collider is Node and SurfaceClassifier.classify_node(collider as Node) == SurfaceClassifier.KIND_CROSSWALK:
		return false
	var ray_h := _down_ray.get_collision_point().y - _ctx.get_owner_position().y
	return ray_h > maxf(_ctx.config.max_jump_obstacle_height, 0.0)


## Tries to fire a jump.  If fired, mutates `owner.velocity.y` and returns true.
## `move_direction` must be the direct-to-waypoint direction (NOT the steered
## avoidance direction) — see class note.
func try_jump(move_direction: Vector3, is_on_floor: bool) -> bool:
	var cfg := _ctx.config
	var logger := _ctx.logger
	if not cfg.jump_low_obstacles:
		_last_status = "off"
		return false
	if _down_ray == null or not _down_ray.enabled:
		_last_status = "no ray"
		return false

	var planar := move_direction
	planar.y = 0.0
	if planar.length_squared() <= 0.0001:
		_last_status = "no move"
		return false
	planar = planar.normalized()

	if _cooldown_timer > 0.0:
		_last_status = "cooldown %.2f" % _cooldown_timer
		return false
	if not is_on_floor and _coyote_time <= 0.0:
		_last_status = "air"
		return false

	_update_ray_target(planar)
	_down_ray.force_raycast_update()
	if not _down_ray.is_colliding():
		_last_status = "no hit"
		logger.trace("JUMP", "MISS_NO_HIT", {
			"pos": _ctx.get_owner_position(),
			"dir": planar,
		})
		return false

	var collider := _down_ray.get_collider()
	if collider == _ctx.owner_body:
		_last_status = "self"
		return false
	if collider is Node and SurfaceClassifier.classify_node(collider as Node) == SurfaceClassifier.KIND_CROSSWALK:
		_last_status = "crosswalk"
		return false

	var hit_point := _down_ray.get_collision_point()
	var owner_pos := _ctx.get_owner_position()
	var to_hit := hit_point - owner_pos
	to_hit.y = 0.0
	if to_hit.length_squared() > 0.0001 and planar.dot(to_hit.normalized()) <= 0.0:
		_last_status = "behind"
		logger.trace("JUMP", "BEHIND", {
			"hit": hit_point,
			"pos": owner_pos,
		})
		return false

	var obstacle_height := hit_point.y - owner_pos.y
	var min_h := maxf(cfg.min_jump_obstacle_height, 0.0)
	var max_h := maxf(cfg.max_jump_obstacle_height, min_h)
	if obstacle_height < min_h or obstacle_height > max_h:
		_last_status = "h %.3f" % obstacle_height
		# Only log above half the minimum threshold — below is floor noise.
		if obstacle_height >= min_h * 0.5:
			logger.debug("JUMP", "HEIGHT_OOB", {
				"h": obstacle_height,
				"min": min_h,
				"max": max_h,
				"collider": (collider as Node).name if collider is Node else "?",
				"pos": owner_pos,
			})
		return false

	_ctx.owner_body.velocity.y = maxf(cfg.jump_velocity, 0.0)
	_cooldown_timer = maxf(cfg.jump_cooldown, 0.0)
	_last_status = "jump h %.3f" % obstacle_height
	logger.info("JUMP", "FIRED", {
		"h": obstacle_height,
		"collider": (collider as Node).name if collider is Node else "?",
		"pos": owner_pos,
		"dir": planar,
	})
	return true


func _update_ray_target(planar_move_direction: Vector3) -> void:
	var cfg := _ctx.config
	var probe_distance := maxf(cfg.jump_probe_distance, 0.05)
	var drop_distance := maxf(cfg.max_jump_obstacle_height + 0.25, 0.3)
	var target_world := _down_ray.global_position \
			+ planar_move_direction * probe_distance \
			+ Vector3.DOWN * drop_distance
	_down_ray.target_position = _down_ray.to_local(target_world)
