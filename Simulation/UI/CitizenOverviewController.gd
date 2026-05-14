extends RefCounted
class_name CitizenOverviewController

## Renders eine kompakte Citizen-Liste in einem Overview-Panel (Schwester zur
## BuildingOverviewController). Wird vom HudOverlayController instanziiert und
## ueber `toggle_visibility()` per HUD-Button gezeigt/versteckt. Severity wird
## aus HP/Hunger/Energy abgeleitet, kritische Citizens stehen oben.

var world: World = null
var panel: PanelContainer = null
var label: RichTextLabel = null
var button: Button = null
var refresh_interval_sec: float = 0.5

var _refresh_left: float = 0.0
var _mark_ui_interacted: Callable = Callable()
var _select_citizen: Callable = Callable()

func setup(
	world_ref: World,
	panel_ref: PanelContainer,
	label_ref: RichTextLabel,
	button_ref: Button,
	mark_ui_interacted: Callable,
	select_citizen: Callable,
	refresh_interval: float = 0.5
) -> void:
	world = world_ref
	panel = panel_ref
	label = label_ref
	button = button_ref
	refresh_interval_sec = maxf(refresh_interval, 0.05)
	_mark_ui_interacted = mark_ui_interacted
	_select_citizen = select_citizen
	if label != null:
		# Zeilen sind als `[url=<instance_id>]...[/url]` formatiert, meta_clicked
		# loest die Selection ueber den uebergebenen `select_citizen`-Callback aus.
		if not label.meta_clicked.is_connected(_on_meta_clicked):
			label.meta_clicked.connect(_on_meta_clicked)

func toggle_visibility() -> void:
	_mark_interacted()
	if panel == null:
		return
	panel.visible = not panel.visible
	if button != null:
		button.text = "Hide Citizens" if panel.visible else "Citizens"
	_refresh_left = 0.0
	_refresh_citizen_overview()

func update(delta: float) -> void:
	if panel == null or not panel.visible:
		return
	_refresh_left -= delta
	if _refresh_left > 0.0:
		return
	_refresh_left = refresh_interval_sec
	_refresh_citizen_overview()

func _refresh_citizen_overview() -> void:
	if label == null or world == null:
		return

	var entries: Array[Dictionary] = []
	var critical_count := 0
	for citizen in world.citizens:
		if citizen == null or not is_instance_valid(citizen):
			continue
		var severity := _classify_citizen_severity(citizen)
		if severity == "critical":
			critical_count += 1
		entries.append({
			"severity_rank": _severity_rank(severity),
			"name": citizen.citizen_name,
			"line": _format_citizen_overview_line(citizen, severity),
		})

	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("severity_rank", 99)) != int(b.get("severity_rank", 99)):
			return int(a.get("severity_rank", 99)) < int(b.get("severity_rank", 99))
		return str(a.get("name", "")).to_lower() < str(b.get("name", "")).to_lower()
	)

	var lines: PackedStringArray = []
	lines.append("[b]Citizens[/b] %d kritisch / %d gesamt" % [critical_count, entries.size()])
	lines.append("")
	for entry in entries:
		lines.append(str(entry.get("line", "")))

	label.clear()
	label.append_text("\n".join(lines))
	label.custom_minimum_size = Vector2(
		332,
		maxf(272.0, label.get_content_height() + 16.0)
	)

func _format_citizen_overview_line(citizen: Citizen, severity: String) -> String:
	var color := _severity_to_hex(severity)
	var icon := _severity_icon(severity)
	var name_text := _overview_escape(citizen.citizen_name)
	var job_label := _format_job_label(citizen)
	var action_label := citizen.current_action.label if citizen.current_action != null else "Idle"
	var needs_label := _format_needs_label(citizen)
	var money := citizen.wallet.balance if citizen.wallet != null else 0
	var body := "%s | %s | %s | %d EUR" % [job_label, action_label, needs_label, money]
	var inner := "[color=%s]%s[/color]  [b]%s[/b]  %s" % [
		color,
		icon,
		name_text,
		_overview_escape(body),
	]
	return "[url=%d]%s[/url]" % [citizen.get_instance_id(), inner]


func _on_meta_clicked(meta: Variant) -> void:
	_mark_interacted()
	if not _select_citizen.is_valid():
		return
	var instance_id := int(str(meta))
	if instance_id == 0:
		return
	var entity := instance_from_id(instance_id)
	if entity is Citizen and is_instance_valid(entity):
		_select_citizen.call(entity as Citizen)

func _format_job_label(citizen: Citizen) -> String:
	if citizen.job == null or citizen.job.workplace == null:
		return "arbeitslos"
	var workplace := citizen.job.workplace
	var workplace_name := workplace.get_display_name() if workplace.has_method("get_display_name") else workplace.building_name
	return "%s @ %s" % [citizen.job.title, workplace_name]

func _format_needs_label(citizen: Citizen) -> String:
	if citizen.needs == null:
		return "?"
	return "H%d E%d F%d HP%d" % [
		int(round(citizen.needs.hunger)),
		int(round(citizen.needs.energy)),
		int(round(citizen.needs.fun)),
		int(round(citizen.needs.health)),
	]

func _classify_citizen_severity(citizen: Citizen) -> String:
	if citizen.needs == null:
		return "normal"
	var n := citizen.needs
	if n.health <= 20.0 or n.hunger >= 85.0 or n.energy <= 10.0:
		return "critical"
	if n.health <= 50.0 or n.hunger >= 70.0 or n.energy <= 30.0:
		return "warning"
	return "normal"

func _severity_rank(severity: String) -> int:
	match severity:
		"critical":
			return 0
		"warning":
			return 1
		_:
			return 2

func _severity_to_hex(severity: String) -> String:
	match severity:
		"critical":
			return "#d95c5c"
		"warning":
			return "#d0b35f"
		_:
			return "#76c68f"

func _severity_icon(severity: String) -> String:
	match severity:
		"critical":
			return "[!]"
		"warning":
			return "[~]"
		_:
			return "[+]"

func _overview_escape(value: String) -> String:
	return value.replace("[", "[lb]").replace("]", "[rb]")

func _mark_interacted() -> void:
	if _mark_ui_interacted.is_valid():
		_mark_ui_interacted.call()
