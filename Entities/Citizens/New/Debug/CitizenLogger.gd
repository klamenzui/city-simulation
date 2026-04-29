class_name CitizenLogger
extends RefCounted

## Structured, buffered per-citizen file logger.
##
## Format: [HH:MM:SS.mmm][LEVEL][LAYER] EVENT | k=v k=v ...
##   - One file per citizen (so multi-citizen sessions don't interleave)
##   - Buffered writes, flushed every `flush_interval` seconds or
##     immediately on WARN / ERROR.
##   - Dedup set for per-rebuild probe-hit spam.
##
## Dependency-free (RefCounted, no scene tree, no signals). Safe to build
## in _init before the owner enters the tree.
const LEVEL_TRACE := 0
const LEVEL_DEBUG := 1
const LEVEL_INFO  := 2
const LEVEL_WARN  := 3
const LEVEL_ERROR := 4

const LEVEL_NAMES := [
	"TRACE", "DEBUG", "INFO", "WARN", "ERROR"
]
var min_level: int = LEVEL_TRACE
var flush_interval: float = 0.25
var enabled: bool = true
var owner_name: String = "?"

var _file_path: String = ""
var _buffer: PackedStringArray = PackedStringArray()
var _flush_timer: float = 0.0
## Persistent file handle, kept open from `open()` until the logger is freed.
## Refactored from per-flush open/seek_end/close (4×/sec × 15 citizens = 60
## file IOs per second) to single-open + per-flush `_file.flush()` (just an
## OS write-out, no fd cycling).
var _file: FileAccess = null
## Dedup cache used by `probe_hit_seen` / `clear_probe_hit_dedup`.
## Scoped to one local-A* rebuild so each rebuild snapshot is complete but
## repeat hits from the same collider don't flood the log.
var _probe_hit_seen: Dictionary = {}
## Event counts for headless tests / runtime stats. Counted regardless of
## `enabled` and `min_level` so tests can assert on counts even when file
## logging is disabled. Reset on `open()` and via `reset_event_counts()`.
## Key format: "LAYER|EVENT".
var _event_counts: Dictionary = {}


func open(path: String, owner: String) -> bool:
	_file_path = path
	owner_name = owner
	_event_counts.clear()
	# Close any handle from a previous open() call before re-opening.
	if _file != null:
		_file.close()
		_file = null
	if not enabled:
		return false
	# WRITE truncates — fresh log per session.
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null:
		push_warning("CitizenLogger: cannot open '%s' (err %d)" % [
				path, FileAccess.get_open_error()])
		enabled = false
		return false
	_file.store_string("=== session start %s | owner=%s ===\n" % [
			Time.get_datetime_string_from_system(), owner_name])
	# Don't flush here — it's only one line; the next periodic flush picks it up.
	return true


## Explicit close. Called from tests; production code relies on RefCounted
## auto-close when the Logger is freed.
func close() -> void:
	if _file == null:
		return
	# Drain any remaining buffered lines before releasing the handle.
	if not _buffer.is_empty():
		for line in _buffer:
			_file.store_string(line)
		_buffer.clear()
	_file.close()
	_file = null


func set_level(level: int) -> void:
	min_level = clampi(level, LEVEL_TRACE, LEVEL_ERROR)


## Main entry. `data` is appended as "key=value" pairs in insertion order.
## Vector3 values are compact-formatted. Use `info`/`debug`/... helpers below
## for a terser call site.
##
## Name avoids the GDScript built-in `log(x)` (natural logarithm).
func write(level: int, layer: String, event: String, data: Dictionary = {}) -> void:
	# Count regardless of enabled/level — counts are observable for tests.
	var count_key := "%s|%s" % [layer, event]
	_event_counts[count_key] = int(_event_counts.get(count_key, 0)) + 1
	if not enabled or level < min_level:
		return
	var ms := Time.get_ticks_msec()
	var line := "[%02d:%02d:%02d.%03d][%s][%s] %s" % [
		(ms / 3600000) % 24,
		(ms / 60000) % 60,
		(ms / 1000) % 60,
		ms % 1000,
		LEVEL_NAMES[level],
		layer,
		event,
	]
	if not data.is_empty():
		line += " |"
		for k in data.keys():
			line += " %s=%s" % [str(k), _fmt_value(data[k])]
	line += "\n"
	_buffer.append(line)
	if level >= LEVEL_WARN:
		_flush()


func trace(layer: String, event: String, data: Dictionary = {}) -> void:
	write(LEVEL_TRACE, layer, event, data)


func debug(layer: String, event: String, data: Dictionary = {}) -> void:
	write(LEVEL_DEBUG, layer, event, data)


func info(layer: String, event: String, data: Dictionary = {}) -> void:
	write(LEVEL_INFO, layer, event, data)


func warn(layer: String, event: String, data: Dictionary = {}) -> void:
	write(LEVEL_WARN, layer, event, data)


func error(layer: String, event: String, data: Dictionary = {}) -> void:
	write(LEVEL_ERROR, layer, event, data)


## Call once per physics_process; handles timed flushes.
func tick(delta: float) -> void:
	_flush_timer -= delta
	if _flush_timer <= 0.0:
		_flush_timer = maxf(flush_interval, 0.05)
		_flush()


## Probe-hit dedup helpers — returns true if this key has NOT been logged
## this rebuild, marking it as seen.  Caller passes a stable key like
## "physics|<node path>".
func probe_hit_seen(key: String) -> bool:
	if _probe_hit_seen.has(key):
		return false
	_probe_hit_seen[key] = true
	return true


func clear_probe_hit_dedup() -> void:
	_probe_hit_seen.clear()


## Returns how often `LAYER|EVENT` has been written this session. Counts are
## live and increment on every `write()` call regardless of `enabled`/level.
func get_event_count(layer: String, event: String) -> int:
	return int(_event_counts.get("%s|%s" % [layer, event], 0))


## Snapshot of all event counts. Useful for test assertions and stats dumps.
func snapshot_event_counts() -> Dictionary:
	return _event_counts.duplicate()


func reset_event_counts() -> void:
	_event_counts.clear()


## Compact Vector3 → "(x.xx,y.yy,z.zz)"
static func fmt_v3(v: Vector3) -> String:
	return "(%.2f,%.2f,%.2f)" % [v.x, v.y, v.z]


func _fmt_value(v) -> String:
	if v is Vector3:
		return fmt_v3(v)
	if v is Vector2:
		return "(%.2f,%.2f)" % [v.x, v.y]
	if v is float:
		return "%.3f" % v
	if v is String:
		if (v as String).contains(" "):
			return "'" + v + "'"
		return v
	return str(v)


func _flush() -> void:
	if not enabled or _buffer.is_empty() or _file == null:
		return
	for line in _buffer:
		_file.store_string(line)
	# `flush()` forces the OS to write out the buffered data without
	# releasing the handle — much cheaper than the legacy open/close cycle.
	_file.flush()
	_buffer.clear()
