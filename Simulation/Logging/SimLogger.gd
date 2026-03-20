extends RefCounted
class_name SimLogger

const PROJECT_LOG_PATH := "res://logs.log"
const FALLBACK_LOG_PATH := "user://logs.log"

static var _log_path: String = PROJECT_LOG_PATH
static var _mirror_to_stdout: bool = false
static var _session_started: bool = false
static var _session_tag: String = ""

static func start_new_session(mirror_to_stdout: bool = false) -> void:
	_mirror_to_stdout = mirror_to_stdout
	_log_path = _resolve_log_path()
	_session_started = true
	_session_tag = _build_session_tag()

	var file := FileAccess.open(_log_path, FileAccess.WRITE)
	if file == null:
		_log_path = FALLBACK_LOG_PATH
		file = FileAccess.open(_log_path, FileAccess.WRITE)
	if file == null:
		_session_started = false
		return

	file.store_string("=== Simulation Log ===\n")
	file.store_string("Started: %s\n" % Time.get_datetime_string_from_system())
	file.store_string("Session: %s\n" % _session_tag)
	file.store_string("Path: %s\n\n" % get_log_path())
	file.close()

static func log(message: String) -> void:
	if not _session_started:
		start_new_session()
	if _mirror_to_stdout:
		print(_format_log_message(message))

	var file := FileAccess.open(_log_path, FileAccess.READ_WRITE)
	if file == null:
		return

	file.seek_end()
	var formatted := _format_log_message(message)
	file.store_string(formatted)
	if not formatted.ends_with("\n"):
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

static func _build_session_tag() -> String:
	var unix_time := int(Time.get_unix_time_from_system())
	return "sid=%d pid=%d" % [unix_time, OS.get_process_id()]

static func _format_log_message(message: String) -> String:
	if message.is_empty():
		return "[%s]" % _session_tag

	var lines := message.split("\n", true)
	for i in range(lines.size()):
		lines[i] = "[%s] %s" % [_session_tag, lines[i]]
	return "\n".join(lines)
