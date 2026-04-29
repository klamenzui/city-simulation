class_name CitizenDebugFacade
extends RefCounted

## Per-citizen debug-log helper. Extracted from old `Citizen.gd` lines
## 57-58, 2985-2996.
##
## Two outputs:
##   - `emit_log(citizen_name, message)`           — every call goes to SimLogger.
##   - `log_once_per_day(world, citizen_name,
##         key, message)`                          — deduplicates by `key`
##                                                   inside one in-game day.
##
## NOTE: method is called `emit_log` rather than `log` because GDScript's
## built-in `log()` is the natural logarithm and shadowing it with a String
## overload causes a "Too many arguments" parse error.
##
## State held: the in-game day on which the dedup keys were first seen, and
## the set of keys logged on that day. Reset automatically when the day rolls.
##
## NOTE: the legacy `Citizen.gd` also had `get_job_debug_summary`,
## `get_unemployment_debug_reason`, `get_zero_pay_debug_reason` etc. Those
## depend on Job/Account/Scheduler state and migrate together with the
## Scheduler component.

const SimLoggerScript = preload("res://Simulation/Logging/SimLogger.gd")

var _once_day: int = -1
var _once_keys: Dictionary = {}


## Unconditional log. Caller passes the citizen name so this component
## doesn't need to read Identity directly.
func emit_log(citizen_name: String, message: String) -> void:
	SimLoggerScript.log("[Citizen %s] %s" % [citizen_name, message])


## Logs `message` at most once per in-game day for the given `key`.
## `world` provides the day counter via `world_day()`. If `world` is null
## (e.g. headless tests), the day is treated as -1 and dedup is skipped.
func log_once_per_day(world: Node, citizen_name: String,
		key: String, message: String) -> void:
	var today: int = -1
	if world != null and world.has_method("world_day"):
		today = int(world.world_day())
	if _once_day != today:
		_once_day = today
		_once_keys.clear()
	if _once_keys.has(key):
		return
	_once_keys[key] = true
	emit_log(citizen_name, message)


## Resets the dedup cache. Useful for tests or when the citizen rejoins after
## being despawned.
func reset() -> void:
	_once_day = -1
	_once_keys.clear()
