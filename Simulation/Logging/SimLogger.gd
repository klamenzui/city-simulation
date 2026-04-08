extends RefCounted
class_name SimLogger

const PROJECT_LOG_PATH := "res://logs.log"
const FALLBACK_LOG_PATH := "user://logs.log"
const PROJECT_AI_LOG_PATH := "res://ai.log"
const FALLBACK_AI_LOG_PATH := "user://ai.log"

static var _log_path: String = PROJECT_LOG_PATH
static var _ai_log_path: String = PROJECT_AI_LOG_PATH
static var _mirror_to_stdout: bool = false
static var _session_started: bool = false
static var _session_tag: String = ""

static func start_new_session(mirror_to_stdout: bool = false) -> void:
	_mirror_to_stdout = mirror_to_stdout
	_log_path = _resolve_log_path(PROJECT_LOG_PATH, FALLBACK_LOG_PATH)
	_ai_log_path = _resolve_log_path(PROJECT_AI_LOG_PATH, FALLBACK_AI_LOG_PATH)
	_session_started = true
	_session_tag = _build_session_tag()
	var main_started := _initialize_log_file(_log_path, "Simulation Log", get_log_path())
	var ai_started := _initialize_log_file(_ai_log_path, "AI Log", get_ai_log_path())
	if not main_started and not ai_started:
		_session_started = false

static func log(message: String) -> void:
	if not _session_started:
		start_new_session()
	_write_message(_log_path, message)

static func log_ai(message: String) -> void:
	if not _session_started:
		start_new_session()
	_write_message(_ai_log_path, message)

static func get_log_path() -> String:
	return ProjectSettings.globalize_path(_log_path)

static func get_ai_log_path() -> String:
	return ProjectSettings.globalize_path(_ai_log_path)

static func _resolve_log_path(preferred_path: String, fallback_path: String) -> String:
	var project_file := FileAccess.open(preferred_path, FileAccess.WRITE)
	if project_file != null:
		project_file.close()
		return preferred_path
	return fallback_path

static func _initialize_log_file(path: String, title: String, absolute_path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string("=== %s ===\n" % title)
	file.store_string("Started: %s\n" % Time.get_datetime_string_from_system())
	file.store_string("Session: %s\n" % _session_tag)
	file.store_string("Path: %s\n\n" % absolute_path)
	file.close()
	return true

static func _write_message(path: String, message: String) -> void:
	if _mirror_to_stdout:
		print(_format_log_message(message))
	var file := FileAccess.open(path, FileAccess.READ_WRITE)
	if file == null:
		return
	file.seek_end()
	var formatted := _format_log_message(message)
	file.store_string(formatted)
	if not formatted.ends_with("\n"):
		file.store_string("\n")
	file.close()

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
