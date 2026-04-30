class_name StuckRecovery
extends RefCounted

## Progress watchdog.  Samples the citizen's planar position every
## `stuck_detection_interval` seconds; if the moved distance is below the
## configured threshold, signals the controller to replan or abort.
##
## Returns one of `ACTION_*` values from `tick()` — caller executes.

const ACTION_NONE: int = 0
const ACTION_REPLAN: int = 1
const ACTION_ABORT: int = 2

var _ctx: NavigationContext

var _check_timer: float = 0.0
var _last_pos: Vector3 = Vector3.ZERO
var _recovery_attempts: int = 0


func _init(context: NavigationContext) -> void:
	_ctx = context


## Called from set_global_target — initial full-interval grace so the stuck
## check does not fire before the citizen had any chance to move.
func reset_for_new_target(pos: Vector3) -> void:
	_check_timer = maxf(_ctx.config.stuck_detection_interval, 0.5)
	_recovery_attempts = 0
	_last_pos = pos


func reset_for_idle(pos: Vector3) -> void:
	_check_timer = 0.0
	_recovery_attempts = 0
	_last_pos = pos


## Per-physics-tick evaluation. `dist_to_target` is the current planar
## distance to the final goal so we can skip the stuck check when very close.
##
## Status strings are passed individually instead of as a `Dictionary` so the
## caller does not allocate a fresh dict every frame just to feed the early-exit
## paths (which is what happens 99% of the time). At 15 citizens × 60 Hz that
## was ~900 dict allocations per second; now we build one dict only when a
## stuck event actually fires (~1× per 1.5 s in the worst case).
func tick(delta: float, current_pos: Vector3, dist_to_target: float,
		status_avoidance: String = "", status_local: String = "",
		status_jump: String = "") -> int:
	var cfg := _ctx.config
	var too_close := dist_to_target <= maxf(cfg.stuck_detection_min_distance * 2.0,
			cfg.final_waypoint_reach_distance * 2.0)
	if too_close:
		return ACTION_NONE

	_check_timer -= delta
	if _check_timer > 0.0:
		return ACTION_NONE

	_check_timer = maxf(cfg.stuck_detection_interval, 0.5)
	var dist := _planar_distance(current_pos, _last_pos)
	_last_pos = current_pos

	if dist >= maxf(cfg.stuck_detection_min_distance, 0.05):
		return ACTION_NONE

	# Stuck detected — only NOW do we build the log dict.
	_recovery_attempts += 1
	var attempts_label := "%d/%d" % [_recovery_attempts, cfg.stuck_max_recovery_attempts]
	var data := {
		"moved": dist,
		"threshold": cfg.stuck_detection_min_distance,
		"pos": current_pos,
		"attempts": attempts_label,
		"avoidance": status_avoidance,
		"local": status_local,
		"jump": status_jump,
	}
	if _recovery_attempts > maxi(cfg.stuck_max_recovery_attempts, 1):
		_ctx.logger.error("STUCK", "EXHAUSTED", data)
		return ACTION_ABORT

	_ctx.logger.warn("STUCK", "REPLAN", data)
	return ACTION_REPLAN


static func _planar_distance(a: Vector3, b: Vector3) -> float:
	var off := a - b
	off.y = 0.0
	return off.length()
