extends SceneTree

const CitizenScene := preload("res://Entities/Citizens/CitizenNew.tscn")

var _checks_run: int = 0
var _current_error: String = ""


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== Citizen stuck escape test ===")

	var citizen := CitizenScene.instantiate() as Citizen
	if citizen == null:
		printerr("FAIL: cannot instantiate CitizenNew.tscn")
		quit(1)
		return
	get_root().add_child(citizen)
	await process_frame
	await physics_frame

	citizen.global_position = Vector3.ZERO
	citizen.force_update_transform()
	citizen._target_position = Vector3(3.0, 0.0, 0.0)
	citizen._global_path = PackedVector3Array([
		Vector3.ZERO,
		Vector3(0.8, 0.0, 0.0),
		Vector3(3.0, 0.0, 0.0),
	])
	citizen._path_index = 1
	citizen._is_travelling = true
	citizen.velocity = Vector3.ZERO
	citizen._jump._coyote_time = 0.1

	var started: bool = citizen._begin_stuck_escape(false)
	_expect(started, "stuck escape should start from a valid global path")
	_expect(citizen._stuck_escape_timer > 0.0, "escape timer should be active")
	_expect(citizen._stuck_escape_target != Vector3.ZERO, "escape should create a temporary local target")
	_expect(citizen.velocity.y > 0.0, "escape should add a vertical jump impulse when floor grace is available")

	var global_direction := Vector3.RIGHT
	var steered: Vector3 = citizen._choose_steered_direction(global_direction, 1.0 / 60.0)
	_expect(steered.length_squared() > 0.0001, "escape steering should return a movement direction")
	_expect(steered.dot(global_direction) < 0.98, "escape steering should not blindly keep following the global path")
	_expect_eq(citizen._debug_avoidance_status, "stuck escape", "debug status should expose escape mode")

	citizen._clear_stuck_escape()
	citizen.global_position = Vector3(0.75, 0.0, 0.0)
	citizen.force_update_transform()
	var skipped: bool = citizen._try_skip_stuck_waypoint()
	_expect(skipped, "stuck recovery should skip a nearby non-crosswalk waypoint")
	_expect_eq(citizen._path_index, 2, "path index should advance after waypoint skip")

	citizen.free()

	if _current_error.is_empty():
		print("STUCK_ESCAPE_TEST OK checks=%d" % _checks_run)
		print("=== End stuck escape test ===")
		quit(0)
		return

	push_error(_current_error)
	print("STUCK_ESCAPE_TEST FAIL checks=%d" % _checks_run)
	print("=== End stuck escape test ===")
	quit(1)


func _expect(condition: bool, message: String) -> void:
	_checks_run += 1
	if not condition and _current_error.is_empty():
		_current_error = message


func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	_checks_run += 1
	if actual != expected and _current_error.is_empty():
		_current_error = "%s (expected=%s actual=%s)" % [message, str(expected), str(actual)]
