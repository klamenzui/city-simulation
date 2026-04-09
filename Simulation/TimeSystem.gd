extends Node
class_name TimeSystem

signal day_changed(day: int)
signal hour_changed(hour: int)
signal time_advanced(day: int, hour: int, minute: int)
signal rent_due()
signal payday()

@export var start_hour: int = 7

var day: int = 1
var minutes_total: int = 0

func _ready() -> void:
	minutes_total = start_hour * 60
	time_advanced.emit(day, get_hour(), get_minute())

func get_hour() -> int:
	return int(minutes_total / 60) % 24

func get_minute() -> int:
	return minutes_total % 60

func advance(minutes: int) -> void:
	if minutes <= 0:
		time_advanced.emit(day, get_hour(), get_minute())
		return

	var remaining := minutes
	while remaining > 0:
		var minutes_until_next_hour := 60 - get_minute()
		if minutes_until_next_hour <= 0:
			minutes_until_next_hour = 60
		var minutes_until_next_day := 24 * 60 - minutes_total
		var step := mini(remaining, mini(minutes_until_next_hour, minutes_until_next_day))
		minutes_total += step
		remaining -= step

		if minutes_total >= 24 * 60:
			minutes_total -= 24 * 60
			day += 1
			day_changed.emit(day)
			rent_due.emit()
			payday.emit()

		if step > 0 and get_minute() == 0:
			hour_changed.emit(get_hour())

	time_advanced.emit(day, get_hour(), get_minute())
		
func get_time_string() -> String:
	return "%02d:%02d" % [get_hour(), get_minute()]

func get_weekday_name_short_de() -> String:
	var names = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]
	return names[get_weekday_index()]

#"Time"     : "%s (%s)" % [world.time.get_time_string(), world.time.get_weekday_name()],
#"Weekend"  : str(world.time.is_weekend()),
func get_ui_date_string() -> String:
	return "%s | Tag %d (Weekend %s)" % [get_weekday_name_short_de(), day, str(is_weekend())]

# --- Weekday / Weekend ---
# English: day=1 -> Monday (0=Mon..6=Sun)
func get_weekday_index() -> int:
	return int((day - 1) % 7)

func get_weekday_name() -> String:
	var names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
	return names[get_weekday_index()]

func is_weekend() -> bool:
	return get_weekday_index() >= 5  # Sat/Sun
