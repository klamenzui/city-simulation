extends RefCounted
class_name CitizenInfoSectionBuilder

const LocaleServiceScript = preload("res://Simulation/Localization/LocaleService.gd")
const CityInventoryAdapterScript = preload("res://Simulation/Inventory/CityInventoryAdapter.gd")
const PlayerInventoryCatalogScript = preload("res://Simulation/UI/PlayerInventoryCatalog.gd")


static func build(citizen: Citizen, world = null) -> Array:
	if citizen == null:
		return []
	return [
		_build_identity_section(citizen),
		_build_needs_section(citizen),
		_build_activity_section(citizen),
		_build_current_building_section(citizen, world),
		_build_finance_section(citizen, world),
	]


static func format_location_text(citizen: Citizen) -> String:
	if citizen == null or citizen.current_location == null:
		return LocaleServiceScript.t("player.location_travelling")
	if citizen.current_location.has_method("get_display_name"):
		return citizen.current_location.get_display_name()
	return citizen.current_location.building_name


static func _build_identity_section(citizen: Citizen) -> Dictionary:
	var rows: Array = [{"label": LocaleServiceScript.t("details.label.name"), "value": citizen.citizen_name}]
	rows.append({"label": LocaleServiceScript.t("details.label.home"), "value": citizen._building_label(citizen.home) if citizen.home != null else LocaleServiceScript.t("player.none")})
	var job_str := _format_job_status_text(citizen)
	if not job_str.is_empty():
		rows.append({"label": LocaleServiceScript.t("details.label.job"), "value": job_str})
	var edu_str := _format_education_status_text(citizen)
	if not edu_str.is_empty():
		rows.append({"label": LocaleServiceScript.t("details.label.education"), "value": edu_str})
	return {"title": LocaleServiceScript.t("details.section.identity"), "rows": rows}


static func _format_job_status_text(citizen: Citizen) -> String:
	if citizen.job == null:
		return LocaleServiceScript.t("details.value.job_unemployed")
	var job_title_display := Building.get_job_title_display_label(citizen.job.title)
	if citizen.job.workplace == null:
		return LocaleServiceScript.t("details.value.job_unemployed_with_title") % job_title_display
	return LocaleServiceScript.t("details.value.job_with_workplace") % [
		job_title_display,
		citizen._building_label(citizen.job.workplace),
		citizen.job.wage_per_hour,
	]


static func _format_education_status_text(citizen: Citizen) -> String:
	if citizen.job != null and citizen.job.required_education_level > citizen.education_level:
		return LocaleServiceScript.t("details.value.education_for_job") % [
			citizen.education_level,
			citizen.job.required_education_level,
			Building.get_job_title_display_label(citizen.job.title),
		]
	if citizen.education_level > 0:
		return LocaleServiceScript.t("details.value.education_level") % citizen.education_level
	return ""


static func _build_needs_section(citizen: Citizen) -> Dictionary:
	if citizen.needs == null:
		return {"title": LocaleServiceScript.t("details.section.needs"), "rows": []}
	return {
		"title": LocaleServiceScript.t("details.section.needs"),
		"rows": [
			_build_need_row(LocaleServiceScript.t("needs.hunger.title"), citizen.needs.hunger, true),
			_build_need_row(LocaleServiceScript.t("needs.energy.title"), citizen.needs.energy, false),
			_build_need_row(LocaleServiceScript.t("needs.fun.title"), citizen.needs.fun, false),
			_build_need_row(LocaleServiceScript.t("needs.social.title"), citizen.needs.social, false),
			_build_need_row(LocaleServiceScript.t("needs.health.title"), citizen.needs.health, false),
		],
	}


static func _build_need_row(label_text: String, value: float, high_is_bad: bool) -> Dictionary:
	return {
		"label": label_text,
		"value": "%s  %3d / 100" % [_format_need_bar(value), int(round(value))],
		"severity": _classify_need_severity(value, high_is_bad),
	}


static func _classify_need_severity(value: float, high_is_bad: bool) -> String:
	if high_is_bad:
		if value >= 85:
			return "critical"
		if value >= 70:
			return "warning"
		return "normal"
	if value <= 10:
		return "critical"
	if value <= 30:
		return "warning"
	return "normal"


static func _format_need_bar(value: float, width: int = 10) -> String:
	var clamped := clampf(value, 0.0, 100.0)
	var fill := clampi(int(round(clamped / 100.0 * width)), 0, width)
	return "█".repeat(fill) + "░".repeat(width - fill)


static func _build_activity_section(citizen: Citizen) -> Dictionary:
	var rows: Array = []
	var action_label := citizen.current_action.label if citizen.current_action != null else LocaleServiceScript.t("overview.action_idle")
	if citizen.current_action == null and not citizen._server_interaction_label.is_empty():
		action_label = citizen._server_interaction_label
	if citizen.network_replica_mode and not citizen._network_action_label.is_empty():
		action_label = citizen._network_action_label
	rows.append({"label": LocaleServiceScript.t("details.label.action"), "value": action_label})
	var location_text := format_location_text(citizen)
	if not location_text.is_empty():
		rows.append({"label": LocaleServiceScript.t("details.label.location"), "value": location_text})
	if citizen.is_travelling():
		var target_label := _format_travel_target_label(citizen)
		if not target_label.is_empty():
			rows.append({"label": LocaleServiceScript.t("details.label.target"), "value": LocaleServiceScript.t("details.value.travel_target") % target_label})
	rows.append({"label": "LOD", "value": citizen.get_simulation_lod_tier()})
	return {"title": LocaleServiceScript.t("details.section.activity"), "rows": rows}


static func _build_current_building_section(citizen: Citizen, world = null) -> Dictionary:
	var location := citizen._get_player_current_building()
	if location == null:
		return {"title": LocaleServiceScript.t("details.section.current_building"), "rows": []}
	var rows: Array = [
		{"label": LocaleServiceScript.t("details.label.name"), "value": location.get_display_name()},
		{"label": LocaleServiceScript.t("details.label.type"), "value": location.get_building_type_display_label()},
	]
	var service := location.get_service_type()
	if not service.is_empty() and service != "housing":
		rows.append({"label": LocaleServiceScript.t("details.label.service"), "value": location.get_service_type_display_label()})
	if location.is_citizen_ownable() or location.has_citizen_owner():
		rows.append({"label": LocaleServiceScript.t("details.label.owner"), "value": location.get_owner_display_name()})
	var hour := -1
	if world != null and world.time != null:
		hour = world.time.get_hour()
	if location.open_hour != location.close_hour:
		rows.append({
			"label": LocaleServiceScript.t("details.label.opening_hours"),
			"value": "%02d:00 - %02d:00 (%s)" % [
				location.open_hour,
				location.close_hour,
				location.get_open_status_display_label(hour),
			],
		})
	if location is CommercialBuilding:
		var stock_text := _format_commercial_building_stock(location as CommercialBuilding)
		if not stock_text.is_empty():
			rows.append({"label": LocaleServiceScript.t("details.label.stock"), "value": stock_text})
		var price_text := _format_commercial_building_prices(location as CommercialBuilding)
		if not price_text.is_empty():
			rows.append({"label": LocaleServiceScript.t("details.label.prices"), "value": price_text})
	elif location is ResidentialBuilding:
		var home_stock_text := _format_residential_building_inventory(location as ResidentialBuilding)
		if not home_stock_text.is_empty():
			rows.append({"label": LocaleServiceScript.t("details.label.stock"), "value": home_stock_text})
	return {"title": LocaleServiceScript.t("details.section.current_building"), "rows": rows}


static func _format_commercial_building_stock(building: CommercialBuilding) -> String:
	if building == null:
		return ""
	var parts: PackedStringArray = []
	for key in building.inventory.keys():
		var stock_key := str(key)
		parts.append("%s:%d" % [_inventory_label_for_stock_key(stock_key), building.get_stock(stock_key)])
	return ", ".join(parts)


static func _format_commercial_building_prices(building: CommercialBuilding) -> String:
	if building == null:
		return ""
	var parts: PackedStringArray = []
	for key in building.inventory.keys():
		var stock_key := str(key)
		parts.append("%s:%d EUR" % [_inventory_label_for_stock_key(stock_key), building.get_item_price(stock_key, 1)])
	return ", ".join(parts)


static func _format_residential_building_inventory(building: ResidentialBuilding) -> String:
	if building == null or not building.has_method("get_inventory_snapshot"):
		return ""
	var snapshot: Dictionary = building.get_inventory_snapshot()
	var parts: PackedStringArray = []
	for key in snapshot.keys():
		var item_id := str(key)
		var amount := int(snapshot.get(key, 0))
		if amount > 0:
			parts.append("%s:%d" % [_inventory_label_for_item_id(item_id), amount])
	return ", ".join(parts)


static func _inventory_label_for_stock_key(stock_key: String) -> String:
	var item_id := PlayerInventoryCatalogScript.get_shop_item_id_for_stock(stock_key)
	if not item_id.is_empty():
		return PlayerInventoryCatalogScript.get_label(item_id)
	return stock_key.replace("_", " ").capitalize()


static func _inventory_label_for_item_id(item_id: String) -> String:
	var clean := CityInventoryAdapterScript.normalize_item_id(item_id)
	if not clean.is_empty():
		return PlayerInventoryCatalogScript.get_label(clean)
	return item_id.replace("_", " ").capitalize()


static func _format_travel_target_label(citizen: Citizen) -> String:
	var target_building: Building = null
	if citizen._debug_travel_target_building != null:
		target_building = citizen._debug_travel_target_building
	elif citizen._travel_target_building != null:
		target_building = citizen._travel_target_building
	if target_building == null:
		return ""
	if target_building.has_method("get_display_name"):
		return target_building.get_display_name()
	return target_building.building_name


static func _build_finance_section(citizen: Citizen, world = null) -> Dictionary:
	var rows: Array = [{"label": LocaleServiceScript.t("details.label.money"), "value": "%d EUR" % (citizen.wallet.balance if citizen.wallet != null else 0)}]
	if citizen.job != null and citizen.job.workplace != null:
		var base_wage: int = citizen.job.wage_per_hour
		if world != null and world.has_method("get_wage_progression"):
			var prog: Dictionary = world.get_wage_progression(citizen)
			var eff_wage: int = int(round(float(base_wage) * float(prog.get("multiplier", 1.0))))
			rows.append({"label": LocaleServiceScript.t("details.label.wage_per_hour"), "value": LocaleServiceScript.t("details.value.wage_with_base") % [eff_wage, base_wage]})
			rows.append({"label": LocaleServiceScript.t("details.label.education_bonus"), "value": "+%d%%" % int(round(float(prog.get("education_bonus", 0.0)) * 100.0))})
			rows.append({"label": LocaleServiceScript.t("details.label.experience"), "value": LocaleServiceScript.t("details.value.percent_with_days") % [
				int(round(float(prog.get("experience_bonus", 0.0)) * 100.0)),
				int(prog.get("tenure_days", 0)),
			]})
			rows.append({"label": LocaleServiceScript.t("details.label.absence_days"), "value": "%d / %d" % [
				int(prog.get("absence_days", 0)),
				int(prog.get("absence_limit", 3)),
			]})
			rows.append({"label": LocaleServiceScript.t("details.label.company"), "value": citizen._profit_tier_label(int(prog.get("profit_tier", 1)))})
		else:
			rows.append({"label": LocaleServiceScript.t("details.label.wage_per_hour"), "value": "%d EUR" % base_wage})
	var owned_count := citizen.get_owned_building_count(world)
	if owned_count > 0:
		rows.append({"label": LocaleServiceScript.t("details.label.owned"), "value": LocaleServiceScript.t("details.value.owned_buildings") % owned_count})
	if citizen.home != null:
		rows.append({"label": LocaleServiceScript.t("details.label.rent_per_day"), "value": "%d EUR" % citizen.home.rent_per_day})
	var home_food := citizen.get_home_inventory_count("food")
	if home_food > 0:
		rows.append({"label": LocaleServiceScript.t("details.label.food_stock"), "value": str(home_food)})
	if citizen.clothing_items > 0:
		rows.append({"label": LocaleServiceScript.t("details.label.clothing"), "value": str(citizen.clothing_items)})
	return {"title": LocaleServiceScript.t("details.section.finance"), "rows": rows}
