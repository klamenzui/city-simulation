extends RefCounted
class_name EconomyOverviewController

## Dashboard with city totals on the left and grouped building finance details
## on the right. Clicking a group selects its representative building so the
## global 3D selection and debug panel stay in sync.

const UiThemeScript = preload("res://Simulation/UI/UiTheme.gd")
const LocaleServiceScript = preload("res://Simulation/Localization/LocaleService.gd")

var world: World = null
var panel: PanelContainer = null
var city_label: RichTextLabel = null
var building_list_label: RichTextLabel = null
var building_detail_label: RichTextLabel = null
var button: Button = null
var refresh_interval_sec: float = 0.5

var _refresh_left: float = 0.0
var _mark_ui_interacted: Callable = Callable()
var _select_building: Callable = Callable()
var _selected_detail_building_id: int = 0
var _selected_detail_group_key: String = ""

func setup(
	world_ref: World,
	panel_ref: PanelContainer,
	city_label_ref: RichTextLabel,
	building_list_label_ref: RichTextLabel,
	building_detail_label_ref: RichTextLabel,
	button_ref: Button,
	mark_ui_interacted: Callable,
	select_building: Callable,
	refresh_interval: float = 0.5
) -> void:
	world = world_ref
	panel = panel_ref
	city_label = city_label_ref
	building_list_label = building_list_label_ref
	building_detail_label = building_detail_label_ref
	button = button_ref
	refresh_interval_sec = maxf(refresh_interval, 0.05)
	_mark_ui_interacted = mark_ui_interacted
	_select_building = select_building
	if building_list_label != null and not building_list_label.meta_clicked.is_connected(_on_meta_clicked):
		building_list_label.meta_clicked.connect(_on_meta_clicked)

func toggle_visibility() -> void:
	_mark_interacted()
	if panel == null:
		return
	panel.visible = not panel.visible
	if button != null:
		# Highlight the sidebar nav button while its panel is open.
		UiThemeScript.apply_accent_state(button, panel.visible)
	_refresh_left = 0.0
	_refresh_all()

func is_visible() -> bool:
	return panel != null and panel.visible

func update(delta: float) -> void:
	if panel == null or not panel.visible:
		return
	_refresh_left -= delta
	if _refresh_left > 0.0:
		return
	_refresh_left = refresh_interval_sec
	_refresh_all()

func _refresh_all() -> void:
	if world == null:
		return
	_refresh_city_label()
	_refresh_building_list()
	_refresh_building_detail()

func _refresh_city_label() -> void:
	if city_label == null:
		return
	var income_today := 0
	var expenses_today := 0
	var wages_today := 0
	var wages_unpaid := 0
	var taxes_today := 0
	var taxes_unpaid := 0
	var maintenance_today := 0
	var operating_today := 0
	var funding_today := 0
	var funding_requested := 0
	for b in world.buildings:
		if b == null:
			continue
		income_today += b.income_today
		expenses_today += b.expenses_today
		wages_today += b.wages_today
		wages_unpaid += b.wages_unpaid_today
		taxes_today += b.taxes_today
		taxes_unpaid += b.taxes_unpaid_today
		maintenance_today += b.maintenance_today
		operating_today += b.operating_costs_today
		funding_today += b.public_funding_today
		funding_requested += b.public_funding_requested_today

	var city_hall = world.find_city_hall() if world.has_method("find_city_hall") else null
	var city_cash: int = city_hall.account.balance if city_hall != null else 0
	var city_reserve: int = world.city_account.balance if world.city_account != null else 0
	var profit := income_today - expenses_today

	var lines: PackedStringArray = []
	lines.append(LocaleServiceScript.t("overview.eco_city"))
	lines.append("")
	lines.append(LocaleServiceScript.t("overview.eco_income_today"))
	lines.append(LocaleServiceScript.t("overview.eco_all_buildings") % income_today)
	lines.append(LocaleServiceScript.t("overview.eco_taxes") % [
		taxes_today,
		LocaleServiceScript.t("overview.eco_open_suffix") % taxes_unpaid if taxes_unpaid > 0 else ""
	])
	lines.append("")
	lines.append(LocaleServiceScript.t("overview.eco_expenses_today"))
	lines.append(LocaleServiceScript.t("overview.eco_wages") % [
		wages_today,
		LocaleServiceScript.t("overview.eco_open_suffix") % wages_unpaid if wages_unpaid > 0 else ""
	])
	lines.append(LocaleServiceScript.t("overview.eco_maintenance") % maintenance_today)
	lines.append(LocaleServiceScript.t("overview.eco_operating") % operating_today)
	lines.append(LocaleServiceScript.t("overview.eco_funding_paid") % [funding_today, funding_requested])
	lines.append(LocaleServiceScript.t("overview.eco_expenses_sum") % expenses_today)
	lines.append("")
	var profit_color := "#76c68f" if profit > 0 else ("#d95c5c" if profit < 0 else "#909090")
	lines.append(LocaleServiceScript.t("overview.eco_day_balance") % [profit_color, profit])
	lines.append("")
	lines.append(LocaleServiceScript.t("overview.eco_treasuries"))
	lines.append(LocaleServiceScript.t("overview.eco_cityhall_cash") % city_cash)
	lines.append(LocaleServiceScript.t("overview.eco_reserve") % city_reserve)

	city_label.clear()
	city_label.append_text("\n".join(lines))

func _refresh_building_list() -> void:
	if building_list_label == null:
		return
	var entries := _build_building_groups()

	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("profit", 0)) != int(b.get("profit", 0)):
			return int(a.get("profit", 0)) > int(b.get("profit", 0))
		return str(a.get("name", "")).to_lower() < str(b.get("name", "")).to_lower()
	)

	var lines: PackedStringArray = []
	lines.append(LocaleServiceScript.t("overview.eco_groups_header"))
	lines.append("")
	for entry in entries:
		lines.append(_format_building_list_line(entry))

	building_list_label.clear()
	building_list_label.append_text("\n".join(lines))

func _format_building_list_line(group: Dictionary) -> String:
	var profit := int(group.get("profit", 0))
	var profit_color := "#76c68f" if profit > 0 else ("#d88c57" if profit < 0 else "#909090")
	var group_key := str(group.get("group_key", ""))
	var name_text := _escape(str(group.get("name", "")))
	var count := int(group.get("count", 0))
	var count_text := " x%d" % count if count > 1 else ""
	var marker := ">" if group_key == _selected_detail_group_key else " "
	var state_text := _escape(_format_state_counts(group.get("state_counts", {})))
	var body := "%s %s%s  [color=%s]%+d EUR[/color]  %s" % [
		marker,
		name_text,
		count_text,
		profit_color,
		profit,
		state_text,
	]
	return "[url=%d]%s[/url]" % [int(group.get("representative_id", 0)), body]

func _refresh_building_detail() -> void:
	if building_detail_label == null:
		return
	if _selected_detail_group_key.is_empty():
		building_detail_label.clear()
		building_detail_label.append_text(LocaleServiceScript.t("overview.eco_pick_building"))
		return
	var group := _get_building_group_by_key(_selected_detail_group_key)
	if group.is_empty():
		building_detail_label.clear()
		building_detail_label.append_text(LocaleServiceScript.t("overview.eco_building_gone"))
		return

	var profit := int(group.get("profit", 0))
	var profit_color := "#76c68f" if profit > 0 else ("#d95c5c" if profit < 0 else "#909090")
	var count := int(group.get("count", 0))
	var count_text := " x%d" % count if count > 1 else ""

	var lines: PackedStringArray = []
	lines.append("[b]%s%s[/b]" % [_escape(str(group.get("name", ""))), count_text])
	lines.append("[color=#909090]%s[/color]" % _escape(str(group.get("type", ""))))
	lines.append("")
	lines.append(LocaleServiceScript.t("overview.eco_income_detail") % int(group.get("income", 0)))
	lines.append(LocaleServiceScript.t("overview.eco_expenses_detail") % int(group.get("expenses", 0)))
	lines.append(LocaleServiceScript.t("overview.eco_profit") % [profit_color, profit])
	lines.append("")
	lines.append(LocaleServiceScript.t("overview.eco_breakdown"))
	lines.append(LocaleServiceScript.t("overview.eco_wages_open") % [int(group.get("wages", 0)), int(group.get("wages_unpaid", 0))])
	lines.append(LocaleServiceScript.t("overview.eco_taxes_open") % [int(group.get("taxes", 0)), int(group.get("taxes_unpaid", 0))])
	lines.append(LocaleServiceScript.t("overview.eco_maintenance_open") % [int(group.get("maintenance", 0)), int(group.get("maintenance_unpaid", 0))])
	lines.append(LocaleServiceScript.t("overview.eco_operating_open") % [int(group.get("operating", 0)), int(group.get("operating_unpaid", 0))])
	if int(group.get("funding_requested", 0)) > 0:
		lines.append(LocaleServiceScript.t("overview.eco_funding_detail") % [int(group.get("funding", 0)), int(group.get("funding_requested", 0))])
	lines.append("")
	lines.append(LocaleServiceScript.t("overview.eco_balance_total") % int(group.get("balance", 0)))
	lines.append(LocaleServiceScript.t("overview.eco_status") % _escape(_format_state_counts(group.get("state_counts", {}))))

	building_detail_label.clear()
	building_detail_label.append_text("\n".join(lines))

func _on_meta_clicked(meta: Variant) -> void:
	_mark_interacted()
	var instance_id := int(str(meta))
	if instance_id == 0:
		return
	var entity := instance_from_id(instance_id)
	if not (entity is Building) or not is_instance_valid(entity):
		return
	var building := entity as Building
	_selected_detail_building_id = instance_id
	_selected_detail_group_key = _get_building_group_key(building)
	_refresh_building_detail()
	_refresh_building_list()
	if _select_building.is_valid():
		_select_building.call(building)

func _build_building_groups() -> Array[Dictionary]:
	var groups_by_key: Dictionary = {}
	var group_order: Array[String] = []
	if world == null:
		return []
	for b in world.buildings:
		if b == null or not is_instance_valid(b):
			continue
		var group_key := _get_building_group_key(b)
		var group: Dictionary = groups_by_key.get(group_key, {})
		if group.is_empty():
			group = {
				"group_key": group_key,
				"representative_id": int(b.get_instance_id()),
				"name": b.get_display_name(),
				"type": b.get_building_type_name(),
				"count": 0,
				"balance": 0,
				"income": 0,
				"expenses": 0,
				"wages": 0,
				"wages_unpaid": 0,
				"taxes": 0,
				"taxes_unpaid": 0,
				"maintenance": 0,
				"maintenance_unpaid": 0,
				"operating": 0,
				"operating_unpaid": 0,
				"funding": 0,
				"funding_requested": 0,
				"state_counts": {},
			}
			group_order.append(group_key)

		group["count"] = int(group.get("count", 0)) + 1
		group["balance"] = int(group.get("balance", 0)) + b.account.balance
		group["income"] = int(group.get("income", 0)) + b.income_today
		group["expenses"] = int(group.get("expenses", 0)) + b.expenses_today
		group["wages"] = int(group.get("wages", 0)) + b.wages_today
		group["wages_unpaid"] = int(group.get("wages_unpaid", 0)) + b.wages_unpaid_today
		group["taxes"] = int(group.get("taxes", 0)) + b.taxes_today
		group["taxes_unpaid"] = int(group.get("taxes_unpaid", 0)) + b.taxes_unpaid_today
		group["maintenance"] = int(group.get("maintenance", 0)) + b.maintenance_today
		group["maintenance_unpaid"] = int(group.get("maintenance_unpaid", 0)) + b.maintenance_unpaid_today
		group["operating"] = int(group.get("operating", 0)) + b.operating_costs_today
		group["operating_unpaid"] = int(group.get("operating_unpaid", 0)) + b.operating_unpaid_today
		group["funding"] = int(group.get("funding", 0)) + b.public_funding_today
		group["funding_requested"] = int(group.get("funding_requested", 0)) + b.public_funding_requested_today
		var state_counts: Dictionary = group.get("state_counts", {})
		var state_key := b.get_financial_state_key()
		state_counts[state_key] = int(state_counts.get(state_key, 0)) + 1
		group["state_counts"] = state_counts
		group["profit"] = int(group.get("income", 0)) - int(group.get("expenses", 0))
		groups_by_key[group_key] = group

	var groups: Array[Dictionary] = []
	for group_key in group_order:
		groups.append(groups_by_key[group_key])
	return groups

func _get_building_group_by_key(group_key: String) -> Dictionary:
	for group in _build_building_groups():
		if str(group.get("group_key", "")) == group_key:
			return group
	return {}

func _get_building_group_key(building: Building) -> String:
	return "%s|%s" % [building.get_display_name(), building.get_building_type_name()]

func _format_state_counts(state_counts: Dictionary) -> String:
	if state_counts.is_empty():
		return "UNKNOWN"
	if state_counts.size() == 1:
		return str(state_counts.keys()[0])
	var keys: Array = state_counts.keys()
	keys.sort_custom(func(a, b) -> bool:
		return int(state_counts[a]) > int(state_counts[b])
	)
	var parts: PackedStringArray = []
	for state_key in keys:
		parts.append("%s[x%d]" % [str(state_key), int(state_counts[state_key])])
	return "+".join(parts)

func _escape(value: String) -> String:
	return value.replace("[", "[lb]").replace("]", "[rb]")

func _mark_interacted() -> void:
	if _mark_ui_interacted.is_valid():
		_mark_ui_interacted.call()
