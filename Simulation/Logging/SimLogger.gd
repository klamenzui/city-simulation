extends RefCounted
class_name SimLogger

const PROJECT_LOG_PATH := "res://logs.txt"
const FALLBACK_LOG_PATH := "user://logs.txt"

static var _log_path: String = PROJECT_LOG_PATH
static var _mirror_to_stdout: bool = false
static var _session_started: bool = false

static func start_new_session(mirror_to_stdout: bool = false) -> void:
	_mirror_to_stdout = mirror_to_stdout
	_log_path = _resolve_log_path()
	_session_started = true

	var file := FileAccess.open(_log_path, FileAccess.WRITE)
	if file == null:
		_log_path = FALLBACK_LOG_PATH
		file = FileAccess.open(_log_path, FileAccess.WRITE)
	if file == null:
		_session_started = false
		return

	file.store_string("=== Simulation Log ===\n")
	file.store_string("Started: %s\n" % Time.get_datetime_string_from_system())
	file.store_string("Path: %s\n\n" % get_log_path())
	file.close()

static func log(message: String) -> void:
	if not _session_started:
		start_new_session()
	if _mirror_to_stdout:
		print(message)

	var file := FileAccess.open(_log_path, FileAccess.READ_WRITE)
	if file == null:
		return

	file.seek_end()
	file.store_string(message)
	if not message.ends_with("\n"):
		file.store_string("\n")
	file.close()

static func get_log_path() -> String:
	return ProjectSettings.globalize_path(_log_path)

static func _resolve_log_path() -> String:
	var project_file := FileAccess.open(PROJECT_LOG_PATH, FileAccess.WRITE)
	if project_file != null:
		project_file.close()
		return PROJECT_LOG_PATH
	return FALLBACK_LOG_PATH
