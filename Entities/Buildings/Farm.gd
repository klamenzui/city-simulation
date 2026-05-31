extends CommercialBuilding
class_name Farm

enum CropState {
	GROWING,
	READY,
}

const MINUTES_PER_DAY := 24 * 60
const HARVEST_PHASE_NONE := ""
const HARVEST_PHASE_TO_FIELD := "to_field"
const HARVEST_PHASE_HARVESTING := "harvesting"
const HARVEST_PHASE_TO_STORAGE := "to_storage"
const DELIVERY_PHASE_NONE := ""
const DELIVERY_PHASE_TO_STORAGE := "to_storage"
const DELIVERY_PHASE_TO_VEHICLE := "to_vehicle"
const DELIVERY_PHASE_DRIVING_TO_TARGET := "driving_to_target"
const DELIVERY_PHASE_UNLOADING := "unloading"
const DELIVERY_PHASE_DRIVING_RETURN := "driving_return"
const TRUCK_SCENE_PATH := "res://Entities/Transport/Truck_NormalTrailler_001.tscn"
const DeliveryTruckScene := preload("res://Entities/Transport/Truck_NormalTrailler_001.tscn")

@export var base_food_output_per_day: int = 60
@export var production_cost_per_unit: int = 1
@export var crop_growth_days: int = 2
@export var harvest_duration_minutes: int = 45
@export var storage_capacity: int = 300
@export var initial_stored_food: int = 0
@export var product_commodity: String = "food"
@export var product_display_name: String = "food"
@export var supermarket_delivery_item: String = "grocery_bundle"
@export var direct_supermarket_delivery_enabled: bool = true
@export var direct_delivery_batch_per_supermarket: int = 35
@export var delivery_unload_duration_minutes: int = 10
@export var direct_delivery_price_multiplier: float = 0.85
@export var market_export_enabled: bool = true
@export var market_export_limit_per_day: int = 0

var output_today: int = 0
var shipped_food_today: int = 0
var delivered_food_today: int = 0
var market_exported_food_today: int = 0
var stored_food: int = 0
var crop_growth_minutes: int = 0
var crop_state: CropState = CropState.GROWING

var _crop_stem_nodes: Array[Node3D] = []
var _crop_leaf_a_nodes: Array[Node3D] = []
var _crop_leaf_b_nodes: Array[Node3D] = []
var _last_visual_stage: int = -1
var _harvest_worker: Citizen = null
var _harvest_phase: String = HARVEST_PHASE_NONE
var _harvest_minutes_left: int = 0
var _delivery_worker: Citizen = null
var _delivery_target: Supermarket = null
var _delivery_phase: String = DELIVERY_PHASE_NONE
var _delivery_quantity: int = 0
var _delivery_minutes_left: int = 0
var _delivery_vehicle = null

func _ready() -> void:
	super._ready()
	building_type = BuildingType.FARM
	var settings := apply_balance_settings("farm")
	base_food_output_per_day = int(settings.get("base_food_output_per_day", base_food_output_per_day))
	production_cost_per_unit = int(settings.get("production_cost_per_unit", production_cost_per_unit))
	crop_growth_days = maxi(int(settings.get("crop_growth_days", crop_growth_days)), 1)
	harvest_duration_minutes = maxi(int(settings.get("harvest_duration_minutes", harvest_duration_minutes)), 1)
	storage_capacity = maxi(int(settings.get("storage_capacity", storage_capacity)), 1)
	initial_stored_food = clampi(int(settings.get("initial_stored_food", initial_stored_food)), 0, storage_capacity)
	product_commodity = str(settings.get("product_commodity", product_commodity)).strip_edges()
	product_display_name = str(settings.get("product_display_name", product_display_name)).strip_edges()
	supermarket_delivery_item = str(settings.get("supermarket_delivery_item", supermarket_delivery_item)).strip_edges()
	direct_supermarket_delivery_enabled = bool(settings.get("direct_supermarket_delivery_enabled", direct_supermarket_delivery_enabled))
	direct_delivery_batch_per_supermarket = maxi(int(settings.get("direct_delivery_batch_per_supermarket", direct_delivery_batch_per_supermarket)), 1)
	delivery_unload_duration_minutes = maxi(int(settings.get("delivery_unload_duration_minutes", delivery_unload_duration_minutes)), 1)
	direct_delivery_price_multiplier = maxf(float(settings.get("direct_delivery_price_multiplier", direct_delivery_price_multiplier)), 0.01)
	market_export_enabled = bool(settings.get("market_export_enabled", market_export_enabled))
	market_export_limit_per_day = maxi(int(settings.get("market_export_limit_per_day", market_export_limit_per_day)), 0)
	restock_enabled = false
	if initial_stored_food > 0 and stored_food <= 0:
		stored_food = initial_stored_food
	_ensure_product_inventory_registered()
	_collect_crop_visual_nodes()
	_refresh_crop_visuals(true)

func get_service_type() -> String:
	return "production_food"

func get_product_commodity() -> String:
	if product_commodity.strip_edges().is_empty():
		return "food"
	return product_commodity.strip_edges()

func get_product_display_name() -> String:
	if product_display_name.strip_edges().is_empty():
		return get_product_commodity()
	return product_display_name.strip_edges()

func get_supermarket_delivery_item() -> String:
	if supermarket_delivery_item.strip_edges().is_empty():
		return "grocery_bundle"
	return supermarket_delivery_item.strip_edges()

func get_product_inventory_snapshot() -> Dictionary:
	_sync_active_product_from_legacy()
	var snapshot: Dictionary = {}
	for key in inventory.keys():
		var product_key := str(key).strip_edges()
		if product_key.is_empty():
			continue
		var amount := _get_inventory_amount(product_key)
		if amount > 0 or product_key == get_product_commodity():
			snapshot[product_key] = amount
	return snapshot

func get_product_inventory_amount(product_key: String = "") -> int:
	_sync_active_product_from_legacy()
	return _get_inventory_amount(_resolve_product_key(product_key))

func set_product_inventory_amount(product_key: String, amount: int) -> void:
	_set_inventory_amount_clamped(_resolve_product_key(product_key), amount)
	_sync_legacy_stored_product_from_inventory()

func sim_tick(_world: World, tick_minutes: int) -> void:
	if is_financially_closed():
		return
	advance_crop_growth(tick_minutes)

func run_daily_production(world: World) -> void:
	if world == null:
		return
	shipped_food_today = 0
	delivered_food_today = 0
	market_exported_food_today = 0
	if is_financially_closed():
		return
	if requires_staff_to_operate() and not has_required_staff():
		return
	if market_export_enabled:
		if direct_supermarket_delivery_enabled and has_delivery_staff() and not _find_supermarket_delivery_targets(world).is_empty():
			return
		_export_stored_food_to_market(world)

func begin_new_day() -> void:
	super.begin_new_day()
	output_today = 0
	shipped_food_today = 0
	delivered_food_today = 0
	market_exported_food_today = 0

func advance_crop_growth(minutes: int) -> void:
	if minutes <= 0:
		return
	if crop_state == CropState.READY:
		return
	crop_growth_minutes = mini(crop_growth_minutes + minutes, get_crop_growth_total_minutes())
	if crop_growth_minutes >= get_crop_growth_total_minutes():
		crop_state = CropState.READY
	_refresh_crop_visuals()

func get_crop_growth_total_minutes() -> int:
	return maxi(crop_growth_days, 1) * MINUTES_PER_DAY

func get_crop_visual_stage() -> int:
	if crop_state == CropState.READY:
		return 3
	var total_minutes := maxi(get_crop_growth_total_minutes(), 1)
	var ratio := clampf(float(crop_growth_minutes) / float(total_minutes), 0.0, 1.0)
	return clampi(int(floor(ratio * 3.0)), 0, 2)

func is_crop_ready() -> bool:
	return crop_state == CropState.READY

func has_harvest_in_progress() -> bool:
	return _harvest_worker != null and is_instance_valid(_harvest_worker)

func has_delivery_in_progress() -> bool:
	return _delivery_worker != null and is_instance_valid(_delivery_worker)

func has_delivery_staff() -> bool:
	return not get_workers_by_titles(["Fahrer"]).is_empty()

func on_work_tick(world: World, citizen: Citizen, tick_minutes: int) -> void:
	if world == null or citizen == null:
		return
	if citizen.job == null or citizen.job.workplace != self:
		return
	_prune_invalid_harvest_worker()
	_prune_invalid_delivery_worker()
	if _is_delivery_worker(citizen):
		_tick_delivery_activity(world, citizen, maxi(tick_minutes, 1))
		return
	if _harvest_worker != null and _harvest_worker != citizen:
		return
	if crop_state != CropState.READY:
		return
	if _get_available_storage() <= 0:
		return
	if _harvest_worker == null:
		_assign_harvest_worker(world, citizen)
	_tick_harvest_worker(world, citizen, maxi(tick_minutes, 1))

func on_work_finished(world: World, citizen: Citizen) -> void:
	if citizen == null:
		return
	if citizen == _harvest_worker:
		if citizen.has_method("stop_travel"):
			citizen.stop_travel()
		if citizen.has_method("clear_rest_pose"):
			citizen.clear_rest_pose(true)
		_release_harvest_worker()
	if citizen == _delivery_worker:
		if citizen.has_method("stop_travel"):
			citizen.stop_travel()
		if citizen.has_method("clear_rest_pose"):
			citizen.clear_rest_pose(true)
		if _delivery_vehicle != null and is_instance_valid(_delivery_vehicle) and citizen.has_method("is_inside_vehicle") and citizen.is_inside_vehicle():
			_delivery_vehicle.unboard_driver(world, _delivery_vehicle.get_entry_point_global())
		_release_delivery_worker()

func get_harvest_point_global() -> Vector3:
	var point := get_node_or_null("HarvestPoint") as Node3D
	if point != null:
		return point.global_position
	return to_global(Vector3(0.0, 0.0, 1.4))

func get_storage_point_global() -> Vector3:
	var point := get_node_or_null("StoragePoint") as Node3D
	if point != null:
		return point.global_position
	return get_entrance_pos()

func get_farm_state_snapshot() -> Dictionary:
	_sync_active_product_from_legacy()
	return {
		"stored_food": stored_food,
		"product_inventory": get_product_inventory_snapshot(),
		"product_commodity": get_product_commodity(),
		"product_display_name": get_product_display_name(),
		"supermarket_delivery_item": get_supermarket_delivery_item(),
		"crop_growth_minutes": crop_growth_minutes,
		"crop_state": int(crop_state),
		"output_today": output_today,
		"shipped_food_today": shipped_food_today,
		"delivered_food_today": delivered_food_today,
		"market_exported_food_today": market_exported_food_today,
	}

func apply_farm_state_snapshot(data: Dictionary) -> void:
	if data.is_empty():
		return
	if data.has("product_commodity"):
		product_commodity = str(data.get("product_commodity", product_commodity)).strip_edges()
	if data.has("product_display_name"):
		product_display_name = str(data.get("product_display_name", product_display_name)).strip_edges()
	if data.has("supermarket_delivery_item"):
		supermarket_delivery_item = str(data.get("supermarket_delivery_item", supermarket_delivery_item)).strip_edges()
	stored_food = clampi(int(data.get("stored_food", stored_food)), 0, storage_capacity)
	if data.get("product_inventory", null) is Dictionary:
		inventory.clear()
		var inventory_data := data.get("product_inventory", {}) as Dictionary
		for key in inventory_data.keys():
			var product_key := str(key).strip_edges()
			if product_key.is_empty():
				continue
			_set_inventory_amount_clamped(product_key, int(inventory_data.get(key, 0)))
	else:
		inventory[get_product_commodity()] = stored_food
	_ensure_product_inventory_registered()
	crop_growth_minutes = clampi(
		int(data.get("crop_growth_minutes", crop_growth_minutes)),
		0,
		get_crop_growth_total_minutes()
	)
	var saved_state := int(data.get("crop_state", crop_state))
	crop_state = CropState.READY if saved_state == CropState.READY else CropState.GROWING
	if crop_growth_minutes >= get_crop_growth_total_minutes():
		crop_state = CropState.READY
	output_today = maxi(int(data.get("output_today", output_today)), 0)
	shipped_food_today = maxi(int(data.get("shipped_food_today", shipped_food_today)), 0)
	delivered_food_today = maxi(int(data.get("delivered_food_today", delivered_food_today)), 0)
	market_exported_food_today = maxi(int(data.get("market_exported_food_today", market_exported_food_today)), 0)
	_release_harvest_worker()
	_release_delivery_worker()
	_refresh_crop_visuals(true)

func _compute_harvest_yield() -> int:
	var labor_ratio: float = clamp(float(get_employed_worker_count()) / float(maxi(job_capacity, 1)), 0.15, 1.25)
	labor_ratio *= get_operating_efficiency_multiplier()
	var grown_days := maxi(crop_growth_days, 1)
	return maxi(int(round(float(base_food_output_per_day * grown_days) * labor_ratio)), 1)

func _assign_harvest_worker(world: World, citizen: Citizen) -> void:
	_harvest_worker = citizen
	_harvest_phase = HARVEST_PHASE_TO_FIELD
	_harvest_minutes_left = 0
	_start_worker_travel_to(world, citizen, get_harvest_point_global())

func _tick_harvest_worker(world: World, citizen: Citizen, tick_minutes: int) -> void:
	match _harvest_phase:
		HARVEST_PHASE_TO_FIELD:
			if not _worker_reached(citizen, get_harvest_point_global()):
				return
			if citizen.has_method("stop_travel"):
				citizen.stop_travel()
			if citizen.has_method("set_rest_pose"):
				citizen.set_rest_pose(get_harvest_point_global(), citizen.rotation.y)
			_harvest_phase = HARVEST_PHASE_HARVESTING
			_harvest_minutes_left = harvest_duration_minutes
		HARVEST_PHASE_HARVESTING:
			_harvest_minutes_left -= tick_minutes
			if _harvest_minutes_left > 0:
				return
			if citizen.has_method("clear_rest_pose"):
				citizen.clear_rest_pose(true)
			_harvest_phase = HARVEST_PHASE_TO_STORAGE
			_start_worker_travel_to(world, citizen, get_storage_point_global())
		HARVEST_PHASE_TO_STORAGE:
			if not _worker_reached(citizen, get_storage_point_global()):
				return
			if citizen.has_method("stop_travel"):
				citizen.stop_travel()
			_complete_harvest(world, citizen)

func _complete_harvest(world: World, citizen: Citizen) -> void:
	var harvested := mini(_compute_harvest_yield(), _get_available_storage())
	if harvested <= 0:
		_release_harvest_worker()
		return

	var production_cost: int = harvested * maxi(production_cost_per_unit, 0)
	if production_cost > 0:
		if not world.economy.pay_production_cost(account, production_cost):
			close_due_to_finance(world, "unpaid production costs")
			_release_harvest_worker()
			return
		record_production_expense(production_cost)

	_add_product_to_inventory(get_product_commodity(), harvested)
	output_today += harvested
	crop_growth_minutes = 0
	crop_state = CropState.GROWING
	_refresh_crop_visuals(true)
	_release_harvest_worker()

	if citizen != null and is_instance_valid(citizen) and citizen.has_method("enter_building"):
		citizen.enter_building(self, world, true, true)

func _tick_delivery_activity(world: World, citizen: Citizen, tick_minutes: int) -> void:
	if not direct_supermarket_delivery_enabled:
		return
	if _delivery_worker != null and _delivery_worker != citizen:
		return
	if _delivery_worker == null and get_product_inventory_amount() <= 0:
		return
	if _delivery_worker == null:
		var target := _select_delivery_target(world)
		if target == null:
			return
		_assign_delivery_worker(world, citizen, target)
	_tick_delivery_worker(world, citizen, tick_minutes)

func _assign_delivery_worker(world: World, citizen: Citizen, target: Supermarket) -> void:
	_delivery_worker = citizen
	_delivery_target = target
	_delivery_phase = DELIVERY_PHASE_TO_STORAGE
	_delivery_quantity = 0
	_delivery_minutes_left = 0
	_start_worker_travel_to(world, citizen, get_storage_point_global())

func _tick_delivery_worker(world: World, citizen: Citizen, tick_minutes: int) -> void:
	match _delivery_phase:
		DELIVERY_PHASE_TO_STORAGE:
			if not _worker_reached(citizen, get_storage_point_global()):
				return
			if citizen.has_method("stop_travel"):
				citizen.stop_travel()
			_delivery_quantity = _calculate_delivery_quantity(world, _delivery_target)
			if _delivery_quantity <= 0:
				_release_delivery_worker()
				return
			if not _ensure_delivery_vehicle(world):
				_release_delivery_worker()
				return
			_delivery_phase = DELIVERY_PHASE_TO_VEHICLE
			_start_worker_travel_to(world, citizen, _delivery_vehicle.get_entry_point_global())
		DELIVERY_PHASE_TO_VEHICLE:
			if _delivery_target == null or not is_instance_valid(_delivery_target):
				_release_delivery_worker()
				return
			if _delivery_vehicle == null or not is_instance_valid(_delivery_vehicle):
				_release_delivery_worker()
				return
			if not _worker_reached(citizen, _delivery_vehicle.get_entry_point_global()):
				return
			if citizen.has_method("stop_travel"):
				citizen.stop_travel()
			if not _delivery_vehicle.assign_delivery_driver(citizen, _delivery_target, world):
				_release_delivery_worker()
				return
			_delivery_phase = DELIVERY_PHASE_DRIVING_TO_TARGET
		DELIVERY_PHASE_DRIVING_TO_TARGET:
			if _delivery_vehicle == null or not is_instance_valid(_delivery_vehicle):
				_release_delivery_worker()
				return
			if _delivery_vehicle.is_driving():
				return
			if citizen.has_method("is_inside_vehicle") and citizen.is_inside_vehicle():
				return
			if citizen.has_method("set_rest_pose"):
				citizen.set_rest_pose(citizen.global_position, citizen.rotation.y)
			_delivery_phase = DELIVERY_PHASE_UNLOADING
			_delivery_minutes_left = delivery_unload_duration_minutes
		DELIVERY_PHASE_UNLOADING:
			_delivery_minutes_left -= tick_minutes
			if _delivery_minutes_left > 0:
				return
			if citizen.has_method("clear_rest_pose"):
				citizen.clear_rest_pose(true)
			_complete_delivery_to_supermarket(world, _delivery_target, _delivery_quantity)
			_delivery_quantity = 0
			if _delivery_vehicle == null or not is_instance_valid(_delivery_vehicle):
				_release_delivery_worker()
				return
			if not _delivery_vehicle.assign_delivery_driver_to_position(citizen, get_storage_point_global(), world, self):
				_release_delivery_worker()
				return
			_delivery_phase = DELIVERY_PHASE_DRIVING_RETURN
		DELIVERY_PHASE_DRIVING_RETURN:
			if _delivery_vehicle != null and is_instance_valid(_delivery_vehicle) and _delivery_vehicle.is_driving():
				return
			if citizen.has_method("is_inside_vehicle") and citizen.is_inside_vehicle():
				return
			if citizen.has_method("enter_building"):
				citizen.enter_building(self, world, true, true)
			_release_delivery_worker()

func _complete_delivery_to_supermarket(world: World, market: Supermarket, requested_qty: int) -> int:
	if world == null or market == null or not is_instance_valid(market):
		return 0
	var qty := _calculate_delivery_quantity(world, market, requested_qty)
	if qty <= 0:
		return 0

	var unit_price := _get_direct_delivery_unit_price(world)
	var total_cost := qty * unit_price
	if not world.economy.transfer(market.account, account, total_cost):
		return 0
	var accepted := market.receive_direct_supply(get_supermarket_delivery_item(), qty, total_cost)
	if accepted <= 0:
		world.economy.transfer(account, market.account, total_cost)
		return 0
	if accepted < qty:
		var refund := (qty - accepted) * unit_price
		world.economy.transfer(account, market.account, refund)
		total_cost = accepted * unit_price

	_remove_product_from_inventory(get_product_commodity(), accepted)
	shipped_food_today += accepted
	delivered_food_today += accepted
	record_income(total_cost)
	return accepted

func _select_delivery_target(world: World) -> Supermarket:
	var targets := _find_supermarket_delivery_targets(world)
	if targets.is_empty():
		return null
	return targets[0]

func _calculate_delivery_quantity(world: World, market: Supermarket, max_qty: int = -1) -> int:
	if world == null or market == null or not is_instance_valid(market):
		return 0
	var need := market.get_restock_need(get_supermarket_delivery_item())
	if need <= 0:
		return 0
	var limit := direct_delivery_batch_per_supermarket if max_qty < 0 else mini(max_qty, direct_delivery_batch_per_supermarket)
	var unit_price := _get_direct_delivery_unit_price(world)
	var affordable_qty: int = market.account.balance / unit_price
	var available_stock := get_product_inventory_amount()
	return maxi(mini(available_stock, mini(need, mini(limit, affordable_qty))), 0)

func _get_delivery_target_position() -> Vector3:
	if _delivery_target != null and is_instance_valid(_delivery_target):
		return _delivery_target.get_entrance_pos()
	return get_storage_point_global()

func _ensure_delivery_vehicle(world: World) -> bool:
	if _delivery_vehicle != null and is_instance_valid(_delivery_vehicle):
		return true
	var instance := DeliveryTruckScene.instantiate()
	if instance == null or instance is not Node3D or not instance.has_method("assign_delivery_driver"):
		push_warning("Farm: Could not instantiate delivery truck from %s." % TRUCK_SCENE_PATH)
		if instance != null:
			instance.queue_free()
		return false
	_delivery_vehicle = instance as Node3D
	_delivery_vehicle.name = "%s_DeliveryTruck" % get_display_name().replace(" ", "_")
	var parent: Node = world.get_parent() if world != null and world.get_parent() != null else world
	if parent == null:
		parent = self
	parent.add_child(_delivery_vehicle)
	_delivery_vehicle.global_position = get_storage_point_global()
	if world != null and world.has_method("register_vehicle"):
		world.register_vehicle(_delivery_vehicle)
	return true

func _find_supermarket_delivery_targets(world: World) -> Array[Supermarket]:
	var targets: Array[Supermarket] = []
	if world == null:
		return targets
	for building in world.buildings:
		var market := building as Supermarket
		if market == null or not is_instance_valid(market):
			continue
		if market.is_financially_closed():
			continue
		if not market.restock_enabled:
			continue
		if market.get_restock_need(get_supermarket_delivery_item()) <= 0:
			continue
		targets.append(market)
	targets.sort_custom(func(a: Supermarket, b: Supermarket) -> bool:
		return global_position.distance_squared_to(a.global_position) < global_position.distance_squared_to(b.global_position)
	)
	return targets

func _get_direct_delivery_unit_price(world: World) -> int:
	if world == null or world.economy == null:
		return 1
	var wholesale_price := world.economy.get_wholesale_unit_price(get_product_commodity())
	return maxi(int(round(float(wholesale_price) * direct_delivery_price_multiplier)), 1)

func _export_stored_food_to_market(world: World) -> void:
	var product_key := get_product_commodity()
	var available_stock := get_product_inventory_amount(product_key)
	if available_stock <= 0:
		return
	var offered := available_stock
	if market_export_limit_per_day > 0:
		offered = mini(offered, market_export_limit_per_day)
	if offered <= 0:
		return

	var result: Dictionary = world.economy.sell_wholesale_to_market(account, get_product_commodity(), offered)
	var accepted_qty: int = int(result.get("qty", 0))
	_remove_product_from_inventory(product_key, accepted_qty)
	shipped_food_today += accepted_qty
	market_exported_food_today += accepted_qty
	var total_revenue: int = int(result.get("total_revenue", 0))
	if total_revenue > 0:
		record_income(total_revenue)

func _start_worker_travel_to(world: World, citizen: Citizen, target_pos: Vector3) -> void:
	if citizen == null:
		return
	if citizen.has_method("is_inside_building") and citizen.is_inside_building():
		citizen.exit_current_building(world)
	elif citizen.current_location != self:
		citizen.current_location = self
	if citizen.has_method("stop_travel"):
		citizen.stop_travel()
	if citizen.has_method("begin_travel_to") and citizen.is_inside_tree():
		if citizen.begin_travel_to(target_pos, null):
			return
	if citizen is Node3D:
		(citizen as Node3D).global_position = target_pos

func _worker_reached(citizen: Citizen, target_pos: Vector3) -> bool:
	if citizen == null:
		return false
	if citizen.has_method("has_reached_travel_target") and citizen.has_reached_travel_target():
		return true
	var delta := citizen.global_position - target_pos
	delta.y = 0.0
	return delta.length() <= 0.45

func _get_available_storage() -> int:
	return maxi(storage_capacity - _get_total_inventory_units(), 0)

func _prune_invalid_harvest_worker() -> void:
	if _harvest_worker == null:
		return
	if not is_instance_valid(_harvest_worker):
		_release_harvest_worker()
		return
	if _harvest_worker.job == null or _harvest_worker.job.workplace != self:
		_release_harvest_worker()

func _prune_invalid_delivery_worker() -> void:
	if _delivery_worker == null:
		return
	if not is_instance_valid(_delivery_worker):
		_release_delivery_worker()
		return
	if _delivery_worker.job == null or _delivery_worker.job.workplace != self:
		_release_delivery_worker()

func _release_harvest_worker() -> void:
	_harvest_worker = null
	_harvest_phase = HARVEST_PHASE_NONE
	_harvest_minutes_left = 0

func _release_delivery_worker() -> void:
	_delivery_worker = null
	_delivery_target = null
	_delivery_phase = DELIVERY_PHASE_NONE
	_delivery_quantity = 0
	_delivery_minutes_left = 0

func _is_delivery_worker(citizen: Citizen) -> bool:
	if citizen == null or citizen.job == null:
		return false
	return citizen.job.title.strip_edges().to_lower() == "fahrer"

func _ensure_product_inventory_registered() -> void:
	var product_key := get_product_commodity()
	if not inventory.has(product_key):
		inventory[product_key] = maxi(stored_food, 0)
	_sync_active_product_from_legacy()

func _resolve_product_key(product_key: String) -> String:
	var cleaned := product_key.strip_edges()
	if cleaned.is_empty():
		return get_product_commodity()
	return cleaned

func _get_inventory_amount(product_key: String) -> int:
	if product_key.strip_edges().is_empty():
		return 0
	return maxi(int(inventory.get(product_key, 0)), 0)

func _set_inventory_amount_clamped(product_key: String, amount: int) -> void:
	var cleaned := _resolve_product_key(product_key)
	var current := _get_inventory_amount(cleaned)
	var other_products := _get_total_inventory_units_raw() - current
	var allowed := maxi(storage_capacity - other_products, 0)
	inventory[cleaned] = mini(maxi(amount, 0), allowed)

func _add_product_to_inventory(product_key: String, amount: int) -> int:
	if amount <= 0:
		return 0
	var cleaned := _resolve_product_key(product_key)
	var accepted := mini(maxi(amount, 0), _get_available_storage())
	if accepted <= 0:
		return 0
	inventory[cleaned] = _get_inventory_amount(cleaned) + accepted
	_sync_legacy_stored_product_from_inventory()
	return accepted

func _remove_product_from_inventory(product_key: String, amount: int) -> int:
	if amount <= 0:
		return 0
	var cleaned := _resolve_product_key(product_key)
	var current := _get_inventory_amount(cleaned)
	var removed := mini(maxi(amount, 0), current)
	if removed <= 0:
		return 0
	inventory[cleaned] = current - removed
	_sync_legacy_stored_product_from_inventory()
	return removed

func _sync_active_product_from_legacy() -> void:
	var product_key := get_product_commodity()
	var current := _get_inventory_amount(product_key)
	if stored_food > current:
		_set_inventory_amount_clamped(product_key, stored_food)
	elif not inventory.has(product_key):
		inventory[product_key] = current
	_sync_legacy_stored_product_from_inventory()

func _sync_legacy_stored_product_from_inventory() -> void:
	stored_food = _get_inventory_amount(get_product_commodity())

func _get_total_inventory_units() -> int:
	_sync_active_product_from_legacy()
	return _get_total_inventory_units_raw()

func _get_total_inventory_units_raw() -> int:
	var total := 0
	for key in inventory.keys():
		total += _get_inventory_amount(str(key))
	return total

func _format_product_inventory() -> String:
	_sync_active_product_from_legacy()
	var parts: PackedStringArray = []
	for key in inventory.keys():
		var product_key := str(key).strip_edges()
		if product_key.is_empty():
			continue
		parts.append("%s:%d" % [product_key, _get_inventory_amount(product_key)])
	if parts.is_empty():
		return "-"
	return ", ".join(parts)

func _collect_crop_visual_nodes() -> void:
	_crop_stem_nodes.clear()
	_crop_leaf_a_nodes.clear()
	_crop_leaf_b_nodes.clear()
	_collect_crop_visual_nodes_recursive(self)

func _collect_crop_visual_nodes_recursive(node: Node) -> void:
	for child in node.get_children():
		if child is MultiMeshInstance3D:
			var child_name := child.name.to_lower()
			if child_name.begins_with("cropstem"):
				_crop_stem_nodes.append(child as Node3D)
			elif child_name.begins_with("cropleafa"):
				_crop_leaf_a_nodes.append(child as Node3D)
			elif child_name.begins_with("cropleafb"):
				_crop_leaf_b_nodes.append(child as Node3D)
		_collect_crop_visual_nodes_recursive(child)

func _refresh_crop_visuals(force: bool = false) -> void:
	var stage := get_crop_visual_stage()
	if not force and stage == _last_visual_stage:
		return
	_last_visual_stage = stage

	var stem_scale: float = float([0.28, 0.48, 0.72, 1.0][stage])
	var leaf_a_scale: float = float([0.0, 0.42, 0.72, 1.0][stage])
	var leaf_b_scale: float = float([0.0, 0.0, 0.68, 1.0][stage])
	_apply_crop_nodes_stage(_crop_stem_nodes, true, stem_scale)
	_apply_crop_nodes_stage(_crop_leaf_a_nodes, stage >= 1, leaf_a_scale)
	_apply_crop_nodes_stage(_crop_leaf_b_nodes, stage >= 2, leaf_b_scale)

func _apply_crop_nodes_stage(nodes: Array[Node3D], visible: bool, scale_value: float) -> void:
	for node in nodes:
		if node == null or not is_instance_valid(node):
			continue
		node.visible = visible
		if visible:
			node.scale = Vector3.ONE * maxf(scale_value, 0.01)

func _get_extra_info(_world = null) -> Dictionary:
	var info: Dictionary = {}
	var product_name := get_product_display_name()
	info["Crop"] = "ready" if crop_state == CropState.READY else "stage %d/3" % get_crop_visual_stage()
	info["Product"] = product_name
	info["Inventory"] = _format_product_inventory()
	info["Stored %s" % product_name] = "%d / %d" % [stored_food, storage_capacity]
	info["Harvested today"] = "%d %s" % [output_today, product_name]
	info["Delivered today"] = "%d %s" % [delivered_food_today, product_name]
	info["Market export today"] = "%d %s" % [market_exported_food_today, product_name]
	info["Shipped today"] = "%d %s" % [shipped_food_today, product_name]
	info["Delivery staff"] = str(get_workers_by_titles(["Fahrer"]).size())
	if _delivery_target != null and is_instance_valid(_delivery_target):
		info["Delivery target"] = _delivery_target.get_display_name()
	return info
