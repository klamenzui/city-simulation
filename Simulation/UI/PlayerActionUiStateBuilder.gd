extends RefCounted
class_name PlayerActionUiStateBuilder

const LocaleServiceScript = preload("res://Simulation/Localization/LocaleService.gd")


static func build(citizen: Citizen, world: Node = null) -> Dictionary:
	if citizen == null:
		return {}

	var resolved_world := citizen._resolve_world_arg(world)
	var typed_world := resolved_world as World
	var location := citizen._get_player_current_building()
	var buttons: Array = []
	var status_lines: PackedStringArray = []
	var location_label := citizen._building_label(location) if location != null else LocaleServiceScript.t("player.location_travelling")
	var active_id := citizen._active_player_action_id()
	var action_running := not active_id.is_empty()
	status_lines.append(LocaleServiceScript.t("player.status_location") % location_label)
	status_lines.append(LocaleServiceScript.t("player.status_home") % (citizen._building_label(citizen.home) if citizen.home != null else LocaleServiceScript.t("player.none")))
	var owned_count := citizen.get_owned_building_count(resolved_world)
	if owned_count > 0:
		status_lines.append(LocaleServiceScript.t("player.status_owned_buildings") % owned_count)
	buttons.append(_make_button("inventory", LocaleServiceScript.t("action.inventory"), true))
	if action_running:
		status_lines.append(LocaleServiceScript.t("player.status_active") % citizen._active_player_action_label())
		buttons.append(_make_button("stop", LocaleServiceScript.t("action.stop"), true))

	if location != null:
		_append_location_actions(citizen, typed_world, location, buttons, status_lines, active_id, action_running)

	if not citizen.get_player_action_notice().is_empty():
		status_lines.append(citizen.get_player_action_notice())

	if buttons.is_empty():
		return {}
	for spec_var in buttons:
		var spec := spec_var as Dictionary
		spec["active"] = not active_id.is_empty() and str(spec.get("id", "")) == active_id
	return {
		"visible": true,
		"title": LocaleServiceScript.t("player.actions_title"),
		"status_text": "\n".join(status_lines),
		"buttons": buttons,
	}


static func _append_location_actions(
	citizen: Citizen,
	world: World,
	location: Building,
	buttons: Array,
	status_lines: PackedStringArray,
	active_id: String,
	action_running: bool
) -> void:
	if location.is_citizen_ownable():
		status_lines.append(LocaleServiceScript.t("player.status_owner") % location.get_owner_display_name())
		if not location.has_citizen_owner():
			var purchase_price := location.get_purchase_price()
			status_lines.append(LocaleServiceScript.t("player.status_purchase_price") % purchase_price)
			var can_buy := not action_running \
				and world != null \
				and location.can_be_bought_by(citizen, world)
			buttons.append(_make_button(
				"buy_building",
				LocaleServiceScript.t("action.buy_building"),
				can_buy,
				_buy_building_disabled_reason(citizen, location, world, action_running)
			))
	if citizen._is_player_home_location(location):
		buttons.append(_make_button("eat", LocaleServiceScript.t("action.eat"), citizen.home_food_stock > 0, LocaleServiceScript.t("player_disabled.no_home_food")))
		buttons.append(_make_button("sleep", LocaleServiceScript.t("action.sleep"), true))
		buttons.append(_make_button("relax", LocaleServiceScript.t("action.relax"), true))
		buttons.append(_make_button("quit_home", LocaleServiceScript.t("action.quit_home"), not action_running, LocaleServiceScript.t("player_disabled.action_running")))
	elif location is ResidentialBuilding:
		var residential := location as ResidentialBuilding
		var can_rent := not action_running and (residential.tenants.has(citizen) or residential.has_free_slot())
		var rent_label := LocaleServiceScript.t("action.move_home") if citizen.home != null else LocaleServiceScript.t("action.rent_home_short")
		buttons.append(_make_button("rent_home", rent_label, can_rent, LocaleServiceScript.t("player_disabled.no_free_home")))
	elif location is Restaurant:
		var restaurant := location as Restaurant
		var can_eat := world != null \
			and restaurant.is_open(world.time.get_hour()) \
			and citizen.can_afford_restaurant_at(restaurant, world)
		buttons.append(_make_button("eat", LocaleServiceScript.t("action.eat"), can_eat, LocaleServiceScript.t("player_disabled.restaurant_closed_or_poor")))
	elif location is Cafe:
		var cafe := location as Cafe
		var can_eat := world != null \
			and cafe.is_open(world.time.get_hour()) \
			and cafe.can_sell_snack() \
			and citizen.can_afford_cafe_at(cafe, world)
		buttons.append(_make_button("eat", LocaleServiceScript.t("action.eat"), can_eat, LocaleServiceScript.t("player_disabled.cafe_closed_or_poor_or_empty")))
	elif location is University:
		var university := location as University
		var can_study := world != null and university.can_study(citizen)
		buttons.append(_make_button("study", LocaleServiceScript.t("action.study"), can_study, LocaleServiceScript.t("player_disabled.university_unavailable")))
	elif location is Park:
		var can_socialize := citizen.needs == null or (citizen.needs.hunger < 70.0 and citizen.needs.health > 35.0)
		buttons.append(_make_button("relax", LocaleServiceScript.t("action.relax"), true))
		buttons.append(_make_button("socialize", LocaleServiceScript.t("action.socialize"), can_socialize, LocaleServiceScript.t("player_disabled.social_blocked")))
	elif location is Cinema:
		var cinema := location as Cinema
		var can_watch := world != null \
			and cinema.is_open(world.time.get_hour()) \
			and citizen.wallet != null \
			and citizen.wallet.balance >= cinema.ticket_price
		buttons.append(_make_button("watch_cinema", LocaleServiceScript.t("action.watch_cinema"), can_watch, LocaleServiceScript.t("player_disabled.cinema_closed_or_poor")))

	if location is Shop:
		buttons.append(_make_button("shop", LocaleServiceScript.t("action.shop"), true))

	if int(location.job_capacity) > 0:
		_append_work_actions(citizen, world, location, buttons, status_lines, active_id, action_running)


static func _append_work_actions(
	citizen: Citizen,
	world: World,
	location: Building,
	buttons: Array,
	status_lines: PackedStringArray,
	active_id: String,
	action_running: bool
) -> void:
	var prospective_title := Building.get_job_title_display_label(location.get_default_job_title())
	var required_edu := location.get_required_education_level()
	var qualifies := citizen.education_level >= required_edu
	var employed_here := citizen._player_has_accepted_job_at(location)
	if required_edu > 0:
		status_lines.append(LocaleServiceScript.t("player.status_job_requirement") % [prospective_title, citizen.education_level, required_edu])
	else:
		status_lines.append(LocaleServiceScript.t("player.status_job_no_education") % prospective_title)
	if employed_here:
		if world != null:
			var prog: Dictionary = world.get_wage_progression(citizen)
			var base_wage: int = citizen.job.wage_per_hour if citizen.job != null else 0
			var eff_wage: int = int(round(float(base_wage) * float(prog.get("multiplier", 1.0))))
			var edu_pct: int = int(round(float(prog.get("education_bonus", 0.0)) * 100.0))
			var exp_pct: int = int(round(float(prog.get("experience_bonus", 0.0)) * 100.0))
			status_lines.append(LocaleServiceScript.t("player.status_wage_progression") % [eff_wage, base_wage, edu_pct, exp_pct])
			var max_note := " (max)" if bool(prog.get("at_max_experience", false)) else ""
			status_lines.append(LocaleServiceScript.t("player.status_company_tenure") % [
				citizen._profit_tier_label(int(prog.get("profit_tier", 1))),
				max_note,
				int(prog.get("tenure_days", 0)),
			])
			var absence_days := int(prog.get("absence_days", 0))
			if absence_days > 0:
				status_lines.append(LocaleServiceScript.t("player.status_absence") % [
					absence_days,
					int(prog.get("absence_limit", 3)),
				])
		var can_work := not action_running or active_id == "work"
		buttons.append(_make_button("work", LocaleServiceScript.t("action.work"), can_work, LocaleServiceScript.t("player_disabled.action_running")))
	else:
		buttons.append(_make_button("apply_work", LocaleServiceScript.t("action.apply_work"), not action_running, LocaleServiceScript.t("player_disabled.action_running")))
	if not qualifies:
		buttons.append(_make_button("training", LocaleServiceScript.t("action.training"), true))
	if employed_here:
		buttons.append(_make_button("quit_job", LocaleServiceScript.t("action.quit_job"), true))


static func _buy_building_disabled_reason(citizen: Citizen, building: Building, world: World, action_running: bool) -> String:
	if action_running:
		return LocaleServiceScript.t("player_disabled.action_running")
	if building == null or not building.is_citizen_ownable():
		return LocaleServiceScript.t("player_disabled.building_not_buyable")
	if building.is_owned_by(citizen):
		return LocaleServiceScript.t("player_disabled.already_owned")
	if building.has_citizen_owner():
		return LocaleServiceScript.t("player_disabled.already_sold")
	if building.is_financially_closed():
		return LocaleServiceScript.t("player_disabled.closed_not_for_sale")
	if world == null:
		return LocaleServiceScript.t("player_disabled.world_not_ready")
	var price := building.get_purchase_price()
	if citizen.wallet == null or citizen.wallet.balance < price:
		return LocaleServiceScript.t("player_disabled.not_enough_money_price") % price
	return LocaleServiceScript.t("player_disabled.purchase_not_possible")


static func _make_button(action_id: String, text: String, enabled: bool, disabled_reason: String = "") -> Dictionary:
	return {
		"id": action_id,
		"text": text,
		"enabled": enabled,
		"tooltip": "" if enabled else disabled_reason,
	}
