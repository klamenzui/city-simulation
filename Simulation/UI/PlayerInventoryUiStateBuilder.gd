extends RefCounted
class_name PlayerInventoryUiStateBuilder

const PlayerInventoryCatalogScript = preload("res://Simulation/UI/PlayerInventoryCatalog.gd")
const LocaleServiceScript = preload("res://Simulation/Localization/LocaleService.gd")


static func build(citizen: Citizen, world: Node = null, mode: String = "player") -> Dictionary:
	if citizen == null:
		return {}
	var clean_mode := mode.strip_edges()
	if clean_mode.is_empty():
		return {}

	var resolved_world := citizen._resolve_world_arg(world)
	var location := citizen._get_player_current_building()
	var show_shop := clean_mode == "shop" and location is Shop
	var resolved_mode := "shop" if show_shop else "player"
	var status_lines: PackedStringArray = []
	status_lines.append(LocaleServiceScript.t("player.money") % (citizen.wallet.balance if citizen.wallet != null else 0))
	if show_shop:
		var shop_for_status := location as Shop
		status_lines.append(LocaleServiceScript.t("player.shop") % citizen._building_label(shop_for_status))
		if resolved_world != null:
			status_lines.append(LocaleServiceScript.t("player.status") % shop_for_status.get_open_status_display_label(resolved_world.time.get_hour()))
	else:
		status_lines.append(LocaleServiceScript.t("player.status_location") % (citizen._building_label(location) if location != null else LocaleServiceScript.t("player.location_travelling")))
	if not citizen.get_player_action_notice().is_empty():
		status_lines.append(citizen.get_player_action_notice())

	var title := LocaleServiceScript.t("player.shop_title") if show_shop else LocaleServiceScript.t("player.inventory_title")
	if show_shop:
		title = LocaleServiceScript.t("player.shop_title_named") % citizen._building_label(location)

	return {
		"visible": true,
		"mode": resolved_mode,
		"title": title,
		"status_text": "\n".join(status_lines),
		"player_slots": _build_player_inventory_slots(citizen),
		"containers": _build_inventory_containers(citizen, location, resolved_world, show_shop),
		"categories": _build_shop_inventory_categories(citizen, location, resolved_world) if show_shop else [],
	}


static func _build_player_inventory_slots(citizen: Citizen) -> Array:
	var slots: Array = []
	for id_var in PlayerInventoryCatalogScript.item_ids():
		var id := str(id_var)
		slots.append({
			"id": id,
			"label": PlayerInventoryCatalogScript.get_label(id),
			"icon": PlayerInventoryCatalogScript.get_icon(id),
			"count": citizen.get_inventory_count(id),
			"home_count": citizen.get_home_inventory_count(id),
		})
	return slots


static func _build_inventory_containers(citizen: Citizen, location: Building, resolved_world: Node, show_shop: bool) -> Array:
	var containers: Array = []
	if show_shop and location is CommercialBuilding:
		containers.append(_build_building_inventory_container(citizen, location as CommercialBuilding, resolved_world))
	containers.append({
		"id": "player",
		"title": LocaleServiceScript.t("inventory.container_player", "Player inventory"),
		"slots": _build_player_inventory_slots(citizen),
	})
	if citizen.home != null:
		containers.append({
			"id": "home",
			"title": LocaleServiceScript.t("inventory.container_home", "Home inventory"),
			"slots": _build_home_inventory_slots(citizen),
		})
	return containers


static func _build_home_inventory_slots(citizen: Citizen) -> Array:
	var slots: Array = []
	for id_var in PlayerInventoryCatalogScript.item_ids():
		var id := str(id_var)
		slots.append({
			"id": id,
			"label": PlayerInventoryCatalogScript.get_label(id),
			"icon": PlayerInventoryCatalogScript.get_icon(id),
			"count": citizen.get_home_inventory_count(id),
		})
	return slots


static func _build_building_inventory_container(citizen: Citizen, building: CommercialBuilding, resolved_world: Node) -> Dictionary:
	var slots: Array = []
	var action_running := not citizen._active_player_action_id().is_empty()
	for key in building.inventory.keys():
		var stock_key := str(key)
		slots.append(_build_building_stock_slot(citizen, building, stock_key, resolved_world, action_running))
	return {
		"id": "building",
		"title": LocaleServiceScript.t("inventory.container_building", "Building inventory"),
		"subtitle": citizen._building_label(building),
		"slots": slots,
	}


static func _build_building_stock_slot(citizen: Citizen, building: CommercialBuilding, stock_key: String, resolved_world: Node, action_running: bool) -> Dictionary:
	var item_id := PlayerInventoryCatalogScript.get_shop_item_id_for_stock(stock_key)
	var label := PlayerInventoryCatalogScript.get_label(item_id) if not item_id.is_empty() else stock_key.replace("_", " ").capitalize()
	var icon := PlayerInventoryCatalogScript.get_icon(item_id) if not item_id.is_empty() else "[]"
	var price := building.get_item_price(stock_key, 1)
	var owned := citizen.get_carried_inventory_count(item_id) if not item_id.is_empty() else 0
	var action_id := ""
	var enabled := false
	var tooltip := ""
	var typed_world := resolved_world as World
	if stock_key == "grocery_bundle" and building is Supermarket:
		var market := building as Supermarket
		action_id = "buy_groceries"
		price = market.get_grocery_price(typed_world) if typed_world != null else price
		enabled = not action_running and typed_world != null and citizen.can_buy_groceries_at(market, typed_world)
		tooltip = citizen._shop_buy_disabled_reason(market, typed_world, stock_key, price) if not enabled else ""
	elif stock_key == "clothing" and building is Shop:
		var shop := building as Shop
		action_id = "buy_shop_item"
		price = citizen._get_shop_item_price(shop)
		enabled = not action_running and typed_world != null and citizen.can_buy_shop_item_at(shop, typed_world)
		tooltip = citizen._shop_buy_disabled_reason(shop, typed_world, stock_key, price) if not enabled else ""
	return {
		"id": stock_key,
		"label": label,
		"icon": icon,
		"count": building.get_stock(stock_key),
		"price": price,
		"owned": owned,
		"enabled": enabled,
		"tooltip": tooltip,
		"button_text": LocaleServiceScript.t("inventory.buy"),
		"action_id": action_id,
	}


static func _build_shop_inventory_categories(citizen: Citizen, location: Building, resolved_world: Node) -> Array:
	if location == null or location is not Shop:
		return []
	var shop := location as Shop
	var categories: Array = []
	var active := not citizen._active_player_action_id().is_empty()
	if shop is Supermarket:
		categories.append(_build_shop_food_category(citizen, shop as Supermarket, resolved_world, active))
	categories.append(_build_shop_clothing_category(citizen, shop, resolved_world, active))
	return categories


static func _build_shop_food_category(citizen: Citizen, market: Supermarket, resolved_world: Node, action_running: bool) -> Dictionary:
	var typed_world := resolved_world as World
	var price := market.get_grocery_price(typed_world) if typed_world != null else 0
	var enabled := not action_running and typed_world != null and citizen.can_buy_groceries_at(market, typed_world)
	var tooltip := citizen._shop_buy_disabled_reason(market, typed_world, "grocery_bundle", price) if not enabled else ""
	return {
		"id": "food",
		"label": PlayerInventoryCatalogScript.get_tab_label("food"),
		"icon": PlayerInventoryCatalogScript.get_icon("food"),
		"items": [
			{
				"id": "food",
				"label": PlayerInventoryCatalogScript.get_label("food"),
				"icon": PlayerInventoryCatalogScript.get_icon("food"),
				"price": price,
				"stock": market.get_stock("grocery_bundle"),
				"owned": citizen.get_carried_inventory_count("food"),
				"enabled": enabled,
				"tooltip": tooltip,
				"button_text": LocaleServiceScript.t("inventory.buy"),
				"action_id": "buy_groceries",
			},
		],
	}


static func _build_shop_clothing_category(citizen: Citizen, shop: Shop, resolved_world: Node, action_running: bool) -> Dictionary:
	var typed_world := resolved_world as World
	var price := citizen._get_shop_item_price(shop)
	var enabled := not action_running and typed_world != null and citizen.can_buy_shop_item_at(shop, typed_world)
	var tooltip := citizen._shop_buy_disabled_reason(shop, typed_world, "clothing", price) if not enabled else ""
	return {
		"id": "clothing",
		"label": PlayerInventoryCatalogScript.get_tab_label("clothing"),
		"icon": PlayerInventoryCatalogScript.get_icon("clothing"),
		"items": [
			{
				"id": "clothing",
				"label": PlayerInventoryCatalogScript.get_label("clothing"),
				"icon": PlayerInventoryCatalogScript.get_icon("clothing"),
				"price": price,
				"stock": shop.get_stock("clothing"),
				"owned": citizen.get_carried_inventory_count("clothing"),
				"enabled": enabled,
				"tooltip": tooltip,
				"button_text": LocaleServiceScript.t("inventory.buy"),
				"action_id": "buy_shop_item",
			},
		],
	}
