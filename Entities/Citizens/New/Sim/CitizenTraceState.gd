class_name CitizenTraceState
extends RefCounted

## Per-citizen debug-trace state for the runtime debug logger.
## Extracted from old `Citizen.gd` lines 161-168, 2485-2494, 2549-2558.
##
## Holds the most recent navigation decision and move directions so
## `RuntimeDebugLogger.update()` can sample a per-citizen one-line summary.
##
## The legacy class also tracked `_trace_last_*_hit` strings derived from
## the four sensor RayCasts of the old Citizen scene. The new stack has no
## such sensor cluster — `LocalPerception` answers the same questions
## differently. Those fields are NOT carried over here; they will be added
## back as a separate field set if `RuntimeDebugLogger` ever needs them.

const _DEFAULT_REASON: String = "idle"

var last_decision_reason: String = _DEFAULT_REASON
var last_desired_dir: Vector3 = Vector3.ZERO
var last_move_dir: Vector3 = Vector3.ZERO


func update_navigation(reason: String, desired_dir: Vector3, move_dir: Vector3) -> void:
	last_decision_reason = reason
	last_desired_dir = desired_dir
	last_move_dir = move_dir


func reset() -> void:
	last_decision_reason = _DEFAULT_REASON
	last_desired_dir = Vector3.ZERO
	last_move_dir = Vector3.ZERO


## Compact Vector3 → "(x.xx, y.yy, z.zz)" — same format the legacy logger used.
static func fmt_v3(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]


## Returns "forward"/"back"/"left"/"right"/"none" relative to a citizen's
## orientation. `basis_inverse` is the citizen's `global_transform.basis.inverse()`
## (caller computes once, passes in to keep this side effect-free).
static func relative_label(direction: Vector3, basis_inverse: Basis) -> String:
	if direction.length_squared() <= 0.0001:
		return "none"
	var local_dir := basis_inverse * direction
	if absf(local_dir.x) > absf(local_dir.z):
		return "right" if local_dir.x > 0.0 else "left"
	return "back" if local_dir.z > 0.0 else "forward"
