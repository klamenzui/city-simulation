extends RefCounted
class_name CitizenOverviewController

## Renders a compact citizen list in an overview panel, paired with
## BuildingOverviewController. HudOverlayController owns construction and
## toggling. Severity is derived from HP, hunger, and energy and remains visible
## in each row while the user chooses the primary list sort.

const UiThemeScript = preload("res://Simulation/UI/UiTheme.gd")
const LocaleServiceScript = preload("res://Simulation/Localization/LocaleService.gd")

const SORT_BY_NAME := "name"
const SORT_BY_JOB := "job"
const SORT_BY_MONEY := "money"

var world: World = null
var panel: PanelContainer = null
var label: RichTextLabel = null
var button: Button = null
var sort_name_button: Button = null
var sort_job_button: Button = null
var sort_money_button: Button = null
var refresh_interval_sec: float = 0.5

var _refresh_left: float = 0.0
var _mark_ui_interacted: Callable = Callable()
var _select_citizen: Callable = Callable()
var _sort_mode: String = SORT_BY_NAME

func setup(
	world_ref: World,
	panel_ref: PanelContainer,
	label_ref: RichTextLabel,
	button_ref: Button,
	mark_ui_interacted: Callable,
	select_citizen: Callable,
	refresh_interval: float = 0.5,
	sort_name_button_ref: Button = null,
	sort_job_button_ref: Button = null,
	sort_money_button_ref: Button = null
) -> void:
	world = world_ref
	panel = panel_ref
	label = label_ref
	button = button_ref
	sort_name_button = sort_name_button_ref
	sort_job_button = sort_job_button_ref
	sort_money_button = sort_money_button_ref
	refresh_interval_sec = maxf(refresh_interval, 0.05)
	_mark_ui_interacted = mark_ui_interacted
	_select_citizen = select_citizen
	if label != null:
		# Rows are formatted as `[url=<instance_id>]...[/url]`; meta_clicked
		# resolves selection through the supplied `select_citizen` callback.
		if not label.meta_clicked.is_connected(_on_meta_clicked):
			label.meta_clicked.connect(_on_meta_clicked)
	_connect_sort_button(sort_name_button, Callable(self, "_on_sort_name_pressed"))
	_connect_sort_button(sort_job_button, Callable(self, "_on_sort_job_pressed"))
	_connect_sort_button(sort_money_button, Callable(self, "_on_sort_money_pressed"))
	_apply_sort_button_state()

func toggle_visibility() -> void:
	_mark_interacted()
	if panel == null:
		return
	panel.visible = not panel.visible
	if button != null:
		# Highlight the sidebar nav button while its panel is open.
		UiThemeScript.apply_accent_state(button, panel.visible)
	_refresh_left = 0.0
	_refresh_citizen_overview()

func is_visible() -> bool:
	return panel != null and panel.visible

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

	var valid_citizens: Array[Citizen] = []
	var name_counts: Dictionary = {}
	for citizen in world.citizens:
		if citizen == null or not is_instance_valid(citizen):
			continue
		valid_citizens.append(citizen)
		var raw_name := citizen.citizen_name.strip_edges()
		var base_name := raw_name if not raw_name.is_empty() else str(citizen.name)
		name_counts[base_name] = int(name_counts.get(base_name, 0)) + 1

	var entries: Array[Dictionary] = []
	var critical_count := 0
	for citizen in valid_citizens:
		var severity := _classify_citizen_severity(citizen)
		var display_name := _get_overview_citizen_name(citizen, name_counts)
		if severity == "critical":
			critical_count += 1
		entries.append({
			"id": int(citizen.get_instance_id()),
			"severity_rank": _severity_rank(severity),
			"name": display_name,
			"job": _get_job_sort_label(citizen),
			"money": _get_wallet_balance(citizen),
			"line": _format_citizen_overview_line(citizen, severity, display_name),
		})

	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _compare_citizen_entries(a, b)
	)

	var lines: PackedStringArray = []
	lines.append(LocaleServiceScript.t("overview.citizens_header") % [critical_count, entries.size()])
	lines.append("")
	for entry in entries:
		lines.append(str(entry.get("line", "")))

	label.clear()
	label.append_text("\n".join(lines))
	label.custom_minimum_size = Vector2(
		332,
		maxf(272.0, label.get_content_height() + 16.0)
	)

func _format_citizen_overview_line(citizen: Citizen, severity: String, display_name: String) -> String:
	var color := _severity_to_hex(severity)
	var icon := _severity_icon(severity)
	var name_text := _overview_escape(display_name)
	var job_label := _format_job_label(citizen)
	var action_label := citizen.current_action.label if citizen.current_action != null else LocaleServiceScript.t("overview.action_idle")
	var needs_label := _format_needs_label(citizen)
	var money := _get_wallet_balance(citizen)
	var body := "%s | %s | %s | %d EUR" % [job_label, action_label, needs_label, money]
	var inner := "[color=%s]%s[/color]  [b]%s[/b]  %s" % [
		color,
		icon,
		name_text,
		_overview_escape(body),
	]
	return "[url=%d]%s[/url]" % [citizen.get_instance_id(), inner]


func _get_overview_citizen_name(citizen: Citizen, name_counts: Dictionary) -> String:
	var raw_name := citizen.citizen_name.strip_edges()
	var base_name := raw_name if not raw_name.is_empty() else str(citizen.name)
	if int(name_counts.get(base_name, 0)) <= 1:
		return base_name
	return "%s #%s" % [base_name, _stable_citizen_suffix(citizen)]

func _stable_citizen_suffix(citizen: Citizen) -> String:
	var node_name := str(citizen.name)
	if node_name.begins_with("Citizen_") and node_name.length() > "Citizen_".length():
		return node_name.substr("Citizen_".length())
	return "%04d" % int(citizen.get_instance_id() % 10000)

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
		return LocaleServiceScript.t("overview.jobless")
	var workplace := citizen.job.workplace
	var workplace_name := workplace.get_display_name() if workplace.has_method("get_display_name") else workplace.building_name
	return "%s @ %s" % [Building.get_job_title_display_label(citizen.job.title), workplace_name]

func _get_job_sort_label(citizen: Citizen) -> String:
	if citizen.job == null or citizen.job.workplace == null:
		return "~%s" % LocaleServiceScript.t("overview.jobless").to_lower()
	return Building.get_job_title_display_label(citizen.job.title).strip_edges().to_lower()

func _get_wallet_balance(citizen: Citizen) -> int:
	return citizen.wallet.balance if citizen.wallet != null else 0

func _compare_citizen_entries(a: Dictionary, b: Dictionary) -> bool:
	match _sort_mode:
		SORT_BY_JOB:
			var job_a := str(a.get("job", ""))
			var job_b := str(b.get("job", ""))
			if job_a != job_b:
				return job_a < job_b
		SORT_BY_MONEY:
			var money_a := int(a.get("money", 0))
			var money_b := int(b.get("money", 0))
			if money_a != money_b:
				return money_a > money_b
		_:
			pass

	var name_a := str(a.get("name", "")).to_lower()
	var name_b := str(b.get("name", "")).to_lower()
	if name_a != name_b:
		return name_a < name_b
	if int(a.get("severity_rank", 99)) != int(b.get("severity_rank", 99)):
		return int(a.get("severity_rank", 99)) < int(b.get("severity_rank", 99))
	return int(a.get("id", 0)) < int(b.get("id", 0))

func _connect_sort_button(sort_button: Button, handler: Callable) -> void:
	if sort_button == null or not handler.is_valid():
		return
	if not sort_button.pressed.is_connected(handler):
		sort_button.pressed.connect(handler)

func _on_sort_name_pressed() -> void:
	_set_sort_mode(SORT_BY_NAME)

func _on_sort_job_pressed() -> void:
	_set_sort_mode(SORT_BY_JOB)

func _on_sort_money_pressed() -> void:
	_set_sort_mode(SORT_BY_MONEY)

func _set_sort_mode(sort_mode: String) -> void:
	_mark_interacted()
	if _sort_mode == sort_mode:
		return
	_sort_mode = sort_mode
	_apply_sort_button_state()
	_refresh_left = 0.0
	_refresh_citizen_overview()

func _apply_sort_button_state() -> void:
	UiThemeScript.apply_accent_state(sort_name_button, _sort_mode == SORT_BY_NAME)
	UiThemeScript.apply_accent_state(sort_job_button, _sort_mode == SORT_BY_JOB)
	UiThemeScript.apply_accent_state(sort_money_button, _sort_mode == SORT_BY_MONEY)

func _format_needs_label(citizen: Citizen) -> String:
	if citizen.needs == null:
		return "?"
	return LocaleServiceScript.t("overview.needs_compact") % [
		int(round(citizen.needs.hunger)),
		int(round(citizen.needs.energy)),
		int(round(citizen.needs.fun)),
		int(round(citizen.needs.social)),
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
