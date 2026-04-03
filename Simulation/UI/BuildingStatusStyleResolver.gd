extends RefCounted
class_name BuildingStatusStyleResolver

const OPEN_COLOR := Color(0.46, 0.78, 0.56, 1.0)
const UNDERFUNDED_COLOR := Color(0.82, 0.72, 0.36, 1.0)
const STRUGGLING_COLOR := Color(0.86, 0.56, 0.32, 1.0)
const CLOSED_COLOR := Color(0.86, 0.65, 0.35, 1.0)
const UNSTAFFED_COLOR := Color(0.86, 0.36, 0.36, 1.0)
const NO_FUNDS_COLOR := Color(0.78, 0.28, 0.28, 1.0)
const UNSTAFFED_PULSE_SPEED := 5.0
const UNSTAFFED_PULSE_MIN_ALPHA := 0.72

func get_default_border_color() -> Color:
	return OPEN_COLOR

func get_badge_color(status_key: String) -> Color:
	match status_key:
		"NO_FUNDS":
			return NO_FUNDS_COLOR
		"UNDERFUNDED":
			return UNDERFUNDED_COLOR
		"STRUGGLING":
			return STRUGGLING_COLOR
		"UNSTAFFED":
			return UNSTAFFED_COLOR
		"CLOSED":
			return CLOSED_COLOR
		_:
			return OPEN_COLOR

func get_badge_background(status_key: String) -> Color:
	if status_key == "NO_FUNDS":
		return Color(0.26, 0.07, 0.07, 0.95)
	if status_key == "UNDERFUNDED":
		return Color(0.26, 0.20, 0.06, 0.94)
	if status_key == "STRUGGLING":
		return Color(0.29, 0.15, 0.08, 0.94)
	if status_key != "UNSTAFFED":
		return Color(0.10, 0.11, 0.15, 0.92)

	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.001 * UNSTAFFED_PULSE_SPEED)
	var alpha := lerpf(UNSTAFFED_PULSE_MIN_ALPHA, 0.98, pulse)
	return Color(0.24, 0.08, 0.09, alpha)

func get_badge_icon(status_key: String) -> String:
	match status_key:
		"NO_FUNDS":
			return "[$]"
		"UNDERFUNDED":
			return "[~]"
		"STRUGGLING":
			return "[!]"
		"UNSTAFFED":
			return "[!]"
		"CLOSED":
			return "[-]"
		_:
			return "[+]"
