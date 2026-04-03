extends RefCounted
class_name BuildingOverviewController

var world: World = null
var panel: PanelContainer = null
var label: RichTextLabel = null
var button: Button = null
var refresh_interval_sec: float = 0.5

var _refresh_left: float = 0.0
var _status_color_resolver: Callable = Callable()
var _status_icon_resolver: Callable = Callable()
var _mark_ui_interacted: Callable = Callable()

func setup(
	world_ref: World,
	panel_ref: PanelContainer,
	label_ref: RichTextLabel,
	button_ref: Button,
	status_color_resolver: Callable,
	status_icon_resolver: Callable,
	mark_ui_interacted: Callable,
	refresh_interval: float = 0.5
) -> void:
	world = world_ref
	panel = panel_ref
	label = label_ref
	button = button_ref
	refresh_interval_sec = maxf(refresh_interval, 0.05)
	_status_color_resolver = status_color_resolver
	_status_icon_resolver = status_icon_resolver
	_mark_ui_interacted = mark_ui_interacted

func toggle_visibility() -> void:
	_mark_interacted()
	if panel == null:
		return
	panel.visible = not panel.visible
	if button != null:
		button.text = "Hide Buildings" if panel.visible else "Buildings"
	_refresh_left = 0.0
	_refresh_building_overview()

func update(delta: float) -> void:
	if panel == null or not panel.visible:
		return
	_refresh_left -= delta
	if _refresh_left > 0.0:
		return
	_refresh_left = refresh_interval_sec
	_refresh_building_overview()

func _refresh_building_overview() -> void:
	if label == null or world == null:
		return

	var hour := world.time.get_hour() if world.time != null else -1
	var entries: Array[Dictionary] = []
	for building in world.buildings:
		if building == null or not is_instance_valid(building):
			continue
		var status_key := building.get_open_status_label(hour)
		var active := building.is_open(hour)
		entries.append({
			"active": active,
			"state_rank": _get_building_state_rank(status_key),
			"name": building.get_display_name(),
			"line": _format_building_overview_line(building, status_key, active, hour),
		})

	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if bool(a.get("active", false)) != bool(b.get("active", false)):
			return bool(a.get("active", false))
		if int(a.get("state_rank", 99)) != int(b.get("state_rank", 99)):
			return int(a.get("state_rank", 99)) < int(b.get("state_rank", 99))
		return str(a.get("name", "")).to_lower() < str(b.get("name", "")).to_lower()
	)

	var active_count := 0
	for entry in entries:
		if bool(entry.get("active", false)):
			active_count += 1

	var lines: PackedStringArray = []
	lines.append("[b]Gebaeude[/b] %d aktiv / %d gesamt" % [active_count, entries.size()])
	lines.append("")
	for entry in entries:
		lines.append(str(entry.get("line", "")))

	label.clear()
	label.append_text("\n".join(lines))
	label.custom_minimum_size = Vector2(
		332,
		maxf(272.0, label.get_content_height() + 16.0)
	)

func _format_building_overview_line(building: Building, status_key: String, active: bool, hour: int) -> String:
	var status_text := building.get_open_status_display_label(hour)
	var color := _status_key_to_hex(status_key)
	var line := "[color=%s]%s[/color]  %s  (%d EUR)" % [
		color,
		_status_icon_for_overview(status_key),
		_building_overview_escape("%s | %s" % [building.get_display_name(), status_text]),
		building.account.balance
	]
	return "[b]%s[/b]" % line if active else line

func _get_building_state_rank(status_key: String) -> int:
	match status_key:
		"OPEN":
			return 0
		"UNDERFUNDED":
			return 1
		"STRUGGLING":
			return 2
		"UNSTAFFED":
			return 3
		"CLOSED":
			return 4
		"NO_FUNDS":
			return 5
		_:
			return 6

func _status_key_to_hex(status_key: String) -> String:
	var color := Color.WHITE
	if _status_color_resolver.is_valid():
		color = _status_color_resolver.call(status_key) as Color
	return "#" + color.to_html(false)

func _status_icon_for_overview(status_key: String) -> String:
	if _status_icon_resolver.is_valid():
		return str(_status_icon_resolver.call(status_key))
	return "[+]"

func _building_overview_escape(value: String) -> String:
	return value.replace("[", "[lb]").replace("]", "[rb]")

func _mark_interacted() -> void:
	if _mark_ui_interacted.is_valid():
		_mark_ui_interacted.call()
