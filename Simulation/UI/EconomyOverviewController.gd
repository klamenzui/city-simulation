extends RefCounted
class_name EconomyOverviewController

## Dashboard with city totals on the left and grouped building finance details
## on the right. Clicking a group selects its representative building so the
## global 3D selection and debug panel stay in sync.

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
		button.text = "Hide Economy" if panel.visible else "Economy"
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
	lines.append("[b]STADT[/b]")
	lines.append("")
	lines.append("[color=#76c68f]EINNAHMEN heute[/color]")
	lines.append("  Aller Gebaeude: %d EUR" % income_today)
	lines.append("  davon Steuern: %d EUR%s" % [
		taxes_today,
		" (offen: %d)" % taxes_unpaid if taxes_unpaid > 0 else ""
	])
	lines.append("")
	lines.append("[color=#d88c57]AUSGABEN heute[/color]")
	lines.append("  Loehne: %d EUR%s" % [
		wages_today,
		" (offen: %d)" % wages_unpaid if wages_unpaid > 0 else ""
	])
	lines.append("  Wartung: %d EUR" % maintenance_today)
	lines.append("  Betrieb: %d EUR" % operating_today)
	lines.append("  Foerderung gezahlt: %d / %d EUR" % [funding_today, funding_requested])
	lines.append("  Summe Ausgaben: %d EUR" % expenses_today)
	lines.append("")
	var profit_color := "#76c68f" if profit > 0 else ("#d95c5c" if profit < 0 else "#909090")
	lines.append("[b]Tagesbilanz: [color=%s]%+d EUR[/color][/b]" % [profit_color, profit])
	lines.append("")
	lines.append("[b]Kassen[/b]")
	lines.append("  City Hall Cash: %d EUR" % city_cash)
	lines.append("  Reserve: %d EUR" % city_reserve)

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
	lines.append("[b]GEBAEUDE-GRUPPEN[/b] (Klick fuer Details)")
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
		building_detail_label.append_text("[color=#909090]Waehle ein Gebaeude aus der Liste...[/color]")
		return
	var group := _get_building_group_by_key(_selected_detail_group_key)
	if group.is_empty():
		building_detail_label.clear()
		building_detail_label.append_text("[color=#909090](Gebaeude nicht mehr verfuegbar)[/color]")
		return

	var profit := int(group.get("profit", 0))
	var profit_color := "#76c68f" if profit > 0 else ("#d95c5c" if profit < 0 else "#909090")
	var count := int(group.get("count", 0))
	var count_text := " x%d" % count if count > 1 else ""

	var lines: PackedStringArray = []
	lines.append("[b]%s%s[/b]" % [_escape(str(group.get("name", ""))), count_text])
	lines.append("[color=#909090]%s[/color]" % _escape(str(group.get("type", ""))))
	lines.append("")
	lines.append("[color=#76c68f]Einnahmen heute[/color]: %d EUR" % int(group.get("income", 0)))
	lines.append("[color=#d88c57]Ausgaben heute[/color]: %d EUR" % int(group.get("expenses", 0)))
	lines.append("[b]Gewinn: [color=%s]%+d EUR[/color][/b]" % [profit_color, profit])
	lines.append("")
	lines.append("[b]Aufschluesselung[/b]")
	lines.append("  Loehne: %d / %d offen" % [int(group.get("wages", 0)), int(group.get("wages_unpaid", 0))])
	lines.append("  Steuern: %d / %d offen" % [int(group.get("taxes", 0)), int(group.get("taxes_unpaid", 0))])
	lines.append("  Wartung: %d / %d offen" % [int(group.get("maintenance", 0)), int(group.get("maintenance_unpaid", 0))])
	lines.append("  Betrieb: %d / %d offen" % [int(group.get("operating", 0)), int(group.get("operating_unpaid", 0))])
	if int(group.get("funding_requested", 0)) > 0:
		lines.append("  Foerderung: %d / %d EUR" % [int(group.get("funding", 0)), int(group.get("funding_requested", 0))])
	lines.append("")
	lines.append("[b]Bilanz gesamt[/b]: %d EUR" % int(group.get("balance", 0)))
	lines.append("[b]Status[/b]: %s" % _escape(_format_state_counts(group.get("state_counts", {}))))

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
