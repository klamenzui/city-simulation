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
const _STEP_UP_MIN_HEIGHT: float = 0.02
const _STEP_UP_MAX_HEIGHT: float = 0.04
const _STEP_UP_VERTICAL_VELOCITY: float = 0.9


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
func try_jump(move_direction: Vector3, is_on_floor: bool, allow_road_collider: bool = false) -> bool:
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
	if collider is Node:
		var surface_kind := SurfaceClassifier.classify_node(collider as Node)
		if surface_kind == SurfaceClassifier.KIND_CROSSWALK:
			_last_status = "crosswalk"
			return false
		if surface_kind == SurfaceClassifier.KIND_ROAD and not allow_road_collider:
			_last_status = "road"
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
	var max_h := maxf(minf(cfg.max_jump_obstacle_height,
			cfg.local_astar_height_block_threshold), min_h)
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

	if obstacle_height < _STEP_UP_MIN_HEIGHT:
		_last_status = "seam h %.3f" % obstacle_height
		logger.trace("JUMP", "SEAM_IGNORED", {
			"h": obstacle_height,
			"collider": (collider as Node).name if collider is Node else "?",
			"pos": owner_pos,
		})
		return false

	if obstacle_height < _STEP_UP_MAX_HEIGHT:
		if not allow_road_collider:
			_last_status = "low step ignored h %.3f" % obstacle_height
			logger.trace("JUMP", "LOW_STEP_IGNORED", {
				"h": obstacle_height,
				"collider": (collider as Node).name if collider is Node else "?",
				"pos": owner_pos,
			})
			return false
		var step_velocity := minf(_STEP_UP_VERTICAL_VELOCITY, maxf(cfg.jump_velocity, 0.0))
		_ctx.owner_body.velocity.y = maxf(_ctx.owner_body.velocity.y, step_velocity)
		_cooldown_timer = minf(maxf(cfg.jump_cooldown, 0.0), 0.12)
		_last_status = "step h %.3f" % obstacle_height
		logger.debug("JUMP", "STEP_UP", {
			"h": obstacle_height,
			"collider": (collider as Node).name if collider is Node else "?",
			"pos": owner_pos,
			"dir": planar,
		})
		return true

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


func try_stuck_escape_jump(strong: bool) -> bool:
	var cfg := _ctx.config
	if not cfg.jump_low_obstacles:
		_last_status = "escape off"
		return false
	if _cooldown_timer > 0.0:
		_last_status = "escape cooldown %.2f" % _cooldown_timer
		return false
	if _ctx.owner_body == null:
		_last_status = "escape no body"
		return false
	if not _ctx.owner_body.is_on_floor() and _coyote_time <= 0.0:
		_last_status = "escape air"
		return false

	var base_velocity := maxf(cfg.jump_velocity, 0.0)
	if base_velocity <= 0.0:
		_last_status = "escape no velocity"
		return false

	var min_multiplier := 0.85
	var max_multiplier := 1.22
	if strong:
		min_multiplier = 1.05
		max_multiplier = 1.45
	var impulse := base_velocity * randf_range(min_multiplier, max_multiplier)
	_ctx.owner_body.velocity.y = maxf(_ctx.owner_body.velocity.y, impulse)
	_cooldown_timer = maxf(cfg.jump_cooldown, 0.0)
	_last_status = "escape jump %.2f" % impulse
	_ctx.logger.info("JUMP", "STUCK_ESCAPE", {
		"velocity": impulse,
		"strong": strong,
		"pos": _ctx.get_owner_position(),
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
