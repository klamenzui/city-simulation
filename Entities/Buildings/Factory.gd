extends CommercialBuilding
class_name Factory

const DELIVERY_PHASE_NONE := ""
const DELIVERY_PHASE_TO_STORAGE := "to_storage"
const DELIVERY_PHASE_TO_VEHICLE := "to_vehicle"
const DELIVERY_PHASE_EXITING_DEPOT := "exiting_depot"
const DELIVERY_PHASE_DRIVING_TO_TARGET := "driving_to_target"
const DELIVERY_PHASE_UNLOADING := "unloading"
const DELIVERY_PHASE_DRIVING_RETURN := "driving_return"
const DELIVERY_PHASE_PARKING_DEPOT := "parking_depot"
const DELIVERY_DEPOT_MARKER_NAME := "DeliveryVehicleDepot"
const DELIVERY_DEPOT_MAX_LOCAL_MANEUVER_DISTANCE := 16.0
const VehicleDepotAccessScript := preload("res://Simulation/Transport/VehicleDepotAccess.gd")

@export var clothes_output_per_day: int = 55
@export var entertainment_output_per_day: int = 90
@export var production_cost_per_unit: int = 2
@export var storage_capacity: int = 360
@export var initial_clothes_stock: int = 0
@export var initial_entertainment_stock: int = 0
@export var direct_shop_delivery_enabled: bool = true
@export var direct_delivery_batch_per_retailer: int = 24
@export var delivery_unload_duration_minutes: int = 8
@export var direct_delivery_price_multiplier: float = 0.85
@export var market_export_enabled: bool = true
@export var market_export_limit_per_day: int = 0

var output_clothes_today: int = 0
var output_entertainment_today: int = 0
var shipped_goods_today: int = 0
var delivered_goods_today: int = 0
var market_exported_goods_today: int = 0

var _delivery_worker: Citizen = null
var _delivery_target: CommercialBuilding = null
var _delivery_target_item: String = ""
var _delivery_source_commodity: String = ""
var _delivery_phase: String = DELIVERY_PHASE_NONE
var _delivery_quantity: int = 0
var _delivery_minutes_left: int = 0
var _delivery_vehicle = null
var _delivery_depot_parking_position: Vector3 = Vector3.INF
var _delivery_depot_road_access_position: Vector3 = Vector3.INF

func _ready() -> void:
	super._ready()
	building_type = BuildingType.FACTORY
	var settings := apply_balance_settings("factory")
	clothes_output_per_day = int(settings.get("clothes_output_per_day", clothes_output_per_day))
	entertainment_output_per_day = int(settings.get("entertainment_output_per_day", entertainment_output_per_day))
	production_cost_per_unit = int(settings.get("production_cost_per_unit", production_cost_per_unit))
	storage_capacity = maxi(int(settings.get("storage_capacity", storage_capacity)), 1)
	initial_clothes_stock = clampi(int(settings.get("initial_clothes_stock", initial_clothes_stock)), 0, storage_capacity)
	initial_entertainment_stock = clampi(int(settings.get("initial_entertainment_stock", initial_entertainment_stock)), 0, storage_capacity)
	direct_shop_delivery_enabled = bool(settings.get("direct_shop_delivery_enabled", direct_shop_delivery_enabled))
	direct_delivery_batch_per_retailer = maxi(int(settings.get("direct_delivery_batch_per_retailer", direct_delivery_batch_per_retailer)), 1)
	delivery_unload_duration_minutes = maxi(int(settings.get("delivery_unload_duration_minutes", delivery_unload_duration_minutes)), 1)
	direct_delivery_price_multiplier = maxf(float(settings.get("direct_delivery_price_multiplier", direct_delivery_price_multiplier)), 0.01)
	market_export_enabled = bool(settings.get("market_export_enabled", market_export_enabled))
	market_export_limit_per_day = maxi(int(settings.get("market_export_limit_per_day", market_export_limit_per_day)), 0)
	restock_enabled = false
	_ensure_factory_inventory_registered()

func get_service_type() -> String:
	return "production_goods"

func get_factory_inventory_snapshot() -> Dictionary:
	var snapshot: Dictionary = {}
	for key in inventory.keys():
		var commodity := str(key).strip_edges()
		if commodity.is_empty():
			continue
		var amount := _get_inventory_amount(commodity)
		if amount > 0 or commodity == "clothes" or commodity == "entertainment":
			snapshot[commodity] = amount
	return snapshot

func get_factory_inventory_amount(commodity: String = "") -> int:
	return _get_inventory_amount(_resolve_commodity_key(commodity))

func set_factory_inventory_amount(commodity: String, amount: int) -> void:
	_set_inventory_amount_clamped(_resolve_commodity_key(commodity), amount)

func run_daily_production(world: World) -> void:
	if world == null:
		return
	output_clothes_today = 0
	output_entertainment_today = 0
	if is_financially_closed():
		return
	if requires_staff_to_operate() and not has_required_staff():
		return

	var labor_ratio: float = clamp(float(workers.size()) / float(maxi(job_capacity, 1)), 0.2, 1.3)
	labor_ratio *= get_operating_efficiency_multiplier()
	var clothes_qty: int = maxi(int(round(float(clothes_output_per_day) * labor_ratio)), 0)
	var entertainment_qty: int = maxi(int(round(float(entertainment_output_per_day) * labor_ratio)), 0)
	var planned_total := clothes_qty + entertainment_qty
	if planned_total <= 0:
		return

	var accepted_clothes := mini(clothes_qty, _get_available_storage())
	var accepted_entertainment := mini(entertainment_qty, _get_available_storage() - accepted_clothes)
	var accepted_total := accepted_clothes + accepted_entertainment
	if accepted_total <= 0:
		_export_factory_inventory_to_market(world, _get_delivery_reserved_commodities(world))
		return

	var production_cost: int = accepted_total * maxi(production_cost_per_unit, 0)
	if production_cost > 0:
		if not world.economy.pay_production_cost(account, production_cost):
			close_due_to_finance(world, "unpaid production costs")
			return
		record_production_expense(production_cost)

	if accepted_clothes > 0:
		_add_product_to_inventory("clothes", accepted_clothes)
	if accepted_entertainment > 0:
		_add_product_to_inventory("entertainment", accepted_entertainment)
	output_clothes_today = accepted_clothes
	output_entertainment_today = accepted_entertainment

	_export_factory_inventory_to_market(world, _get_delivery_reserved_commodities(world))

func begin_new_day() -> void:
	super.begin_new_day()
	output_clothes_today = 0
	output_entertainment_today = 0
	shipped_goods_today = 0
	delivered_goods_today = 0
	market_exported_goods_today = 0

func has_delivery_in_progress() -> bool:
	return _delivery_worker != null and is_instance_valid(_delivery_worker)

func has_delivery_staff() -> bool:
	return not get_workers_by_titles(["Fahrer"]).is_empty()

func on_work_tick(world: World, citizen: Citizen, tick_minutes: int) -> void:
	if world == null or citizen == null:
		return
	if citizen.job == null or citizen.job.workplace != self:
		return
	_prune_invalid_delivery_worker()
	if not _is_delivery_worker(citizen):
		return
	_tick_delivery_activity(world, citizen, maxi(tick_minutes, 1))

func on_work_finished(world: World, citizen: Citizen) -> void:
	if citizen == null:
		return
	if citizen != _delivery_worker:
		return
	if citizen.has_method("stop_travel"):
		citizen.stop_travel()
	if citizen.has_method("clear_rest_pose"):
		citizen.clear_rest_pose(true)
	if _delivery_vehicle != null and is_instance_valid(_delivery_vehicle) and citizen.has_method("is_inside_vehicle") and citizen.is_inside_vehicle():
		_delivery_vehicle.unboard_driver(world, _delivery_vehicle.get_entry_point_global())
	_release_delivery_worker()

func get_storage_point_global() -> Vector3:
	var point := get_node_or_null("StoragePoint") as Node3D
	if point != null:
		return point.global_position
	return get_entrance_pos()

func _tick_delivery_activity(world: World, citizen: Citizen, tick_minutes: int) -> void:
	if not direct_shop_delivery_enabled:
		return
	if _delivery_worker != null and _delivery_worker != citizen:
		return
	if _delivery_worker == null and get_factory_inventory_amount("clothes") <= 0:
		return
	if _delivery_worker == null:
		var target := _select_delivery_target(world)
		if target.is_empty():
			return
		_assign_delivery_worker(world, citizen, target)
	_tick_delivery_worker(world, citizen, tick_minutes)

func _assign_delivery_worker(world: World, citizen: Citizen, target: Dictionary) -> void:
	_delivery_worker = citizen
	_delivery_target = target.get("building", null) as CommercialBuilding
	_delivery_target_item = str(target.get("item", "")).strip_edges()
	_delivery_source_commodity = str(target.get("commodity", "")).strip_edges()
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
			if not _ensure_delivery_vehicle(world):
				_release_delivery_worker()
				return
			var load_capacity := VehicleDepotAccessScript.get_delivery_vehicle_load_capacity(
				_delivery_vehicle,
				direct_delivery_batch_per_retailer
			)
			_delivery_quantity = _calculate_delivery_quantity(
				world,
				_delivery_target,
				_delivery_target_item,
				_delivery_source_commodity,
				load_capacity
			)
			if _delivery_quantity <= 0:
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
			if not _start_delivery_depot_exit(world, citizen):
				_release_delivery_worker()
				return
		DELIVERY_PHASE_EXITING_DEPOT:
			if _delivery_vehicle == null or not is_instance_valid(_delivery_vehicle):
				_release_delivery_worker()
				return
			if _delivery_vehicle.is_driving():
				return
			if not (citizen.has_method("is_inside_vehicle") and citizen.is_inside_vehicle()):
				_release_delivery_worker()
				return
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
			_complete_delivery(world, _delivery_target, _delivery_target_item, _delivery_source_commodity, _delivery_quantity)
			_delivery_quantity = 0
			if _delivery_vehicle == null or not is_instance_valid(_delivery_vehicle):
				_release_delivery_worker()
				return
			if not _start_delivery_return_to_depot(world, citizen):
				_release_delivery_worker()
				return
			_delivery_phase = DELIVERY_PHASE_DRIVING_RETURN
		DELIVERY_PHASE_DRIVING_RETURN:
			if _delivery_vehicle != null and is_instance_valid(_delivery_vehicle) and _delivery_vehicle.is_driving():
				return
			if citizen.has_method("is_inside_vehicle") and citizen.is_inside_vehicle():
				return
			if not _start_delivery_depot_parking():
				_release_delivery_worker()
				return
			_delivery_phase = DELIVERY_PHASE_PARKING_DEPOT
		DELIVERY_PHASE_PARKING_DEPOT:
			if _delivery_vehicle != null and is_instance_valid(_delivery_vehicle) and _delivery_vehicle.is_driving():
				return
			_finish_delivery_after_depot_parking(world, citizen)

func _start_delivery_depot_exit(world: World, citizen: Citizen) -> bool:
	if _delivery_vehicle == null or not is_instance_valid(_delivery_vehicle):
		return false
	if _delivery_target == null or not is_instance_valid(_delivery_target):
		return false
	if not _resolve_delivery_depot_positions(world):
		return false
	if not _delivery_vehicle.board_driver(citizen):
		return false
	var distance_to_access := VehicleDepotAccessScript.planar_distance(_delivery_vehicle.global_position, _delivery_depot_road_access_position)
	if distance_to_access <= _vehicle_arrival_radius():
		if not _delivery_vehicle.assign_delivery_driver(citizen, _delivery_target, world):
			return false
		_delivery_phase = DELIVERY_PHASE_DRIVING_TO_TARGET
		return true
	if distance_to_access > DELIVERY_DEPOT_MAX_LOCAL_MANEUVER_DISTANCE:
		push_warning("Factory: DeliveryVehicleDepot parking area is too far from road access.")
		return false
	if not _delivery_vehicle.start_drive_to_keep_driver(_delivery_depot_road_access_position, null):
		return false
	_delivery_phase = DELIVERY_PHASE_EXITING_DEPOT
	return true

func _start_delivery_return_to_depot(world: World, citizen: Citizen) -> bool:
	if _delivery_vehicle == null or not is_instance_valid(_delivery_vehicle):
		return false
	if not _resolve_delivery_depot_positions(world):
		return false
	return _delivery_vehicle.assign_delivery_driver_to_position(citizen, _delivery_depot_road_access_position, world, null)

func _start_delivery_depot_parking() -> bool:
	if _delivery_vehicle == null or not is_instance_valid(_delivery_vehicle):
		return false
	if not VehicleDepotAccessScript.is_finite_vector(_delivery_depot_parking_position):
		return false
	var distance_to_parking := VehicleDepotAccessScript.planar_distance(_delivery_vehicle.global_position, _delivery_depot_parking_position)
	if distance_to_parking <= _vehicle_arrival_radius():
		_place_delivery_vehicle_at(_delivery_depot_parking_position)
		return true
	if distance_to_parking > DELIVERY_DEPOT_MAX_LOCAL_MANEUVER_DISTANCE:
		push_warning("Factory: DeliveryVehicleDepot parking area is too far from return road access.")
		return false
	return _delivery_vehicle.start_drive_to(_delivery_depot_parking_position, null)

func _finish_delivery_after_depot_parking(world: World, citizen: Citizen) -> void:
	if _delivery_vehicle != null and is_instance_valid(_delivery_vehicle) \
			and VehicleDepotAccessScript.is_finite_vector(_delivery_depot_parking_position):
		if VehicleDepotAccessScript.planar_distance(_delivery_vehicle.global_position, _delivery_depot_parking_position) > _vehicle_arrival_radius():
			_place_delivery_vehicle_at(_delivery_depot_parking_position)
	if citizen.has_method("enter_building"):
		citizen.enter_building(self, world, true, true)
	_release_delivery_worker()

func _resolve_delivery_depot_positions(world: World) -> bool:
	var parking_position := VehicleDepotAccessScript.resolve_marker_parking_position(self, DELIVERY_DEPOT_MARKER_NAME)
	if not VehicleDepotAccessScript.is_finite_vector(parking_position):
		push_warning("Factory: Missing DeliveryVehicleDepot for delivery truck parking.")
		return false
	var road_access := parking_position
	if world != null and world.has_method("get_vehicle_road_access_point"):
		road_access = world.get_vehicle_road_access_point(parking_position)
	if not VehicleDepotAccessScript.is_finite_vector(road_access):
		push_warning("Factory: DeliveryVehicleDepot has no valid road access.")
		return false
	_delivery_depot_parking_position = parking_position
	_delivery_depot_road_access_position = road_access
	return true

func _place_delivery_vehicle_at(position: Vector3) -> void:
	if _delivery_vehicle == null or not is_instance_valid(_delivery_vehicle):
		return
	_delivery_vehicle.global_position = position
	if _delivery_vehicle.has_method("_snap_to_ground_now"):
		_delivery_vehicle.call("_snap_to_ground_now")

func _vehicle_arrival_radius() -> float:
	if _delivery_vehicle != null and is_instance_valid(_delivery_vehicle):
		var radius_value: Variant = _delivery_vehicle.get("waypoint_reach_distance")
		if radius_value is float or radius_value is int:
			return maxf(float(radius_value), 0.45)
	return 0.45

func _complete_delivery(
	world: World,
	target: CommercialBuilding,
	target_item: String,
	commodity: String,
	requested_qty: int
) -> int:
	if world == null or target == null or not is_instance_valid(target):
		return 0
	var qty := _calculate_delivery_quantity(world, target, target_item, commodity, requested_qty)
	if qty <= 0:
		return 0

	var unit_price := _get_direct_delivery_unit_price(world, commodity)
	var total_cost := qty * unit_price
	if not world.economy.transfer(target.account, account, total_cost):
		return 0
	var accepted := target.receive_direct_supply(target_item, qty, total_cost)
	if accepted <= 0:
		world.economy.transfer(account, target.account, total_cost)
		return 0
	if accepted < qty:
		var refund := (qty - accepted) * unit_price
		world.economy.transfer(account, target.account, refund)
		total_cost = accepted * unit_price

	_remove_product_from_inventory(commodity, accepted)
	shipped_goods_today += accepted
	delivered_goods_today += accepted
	record_income(total_cost)
	return accepted

func _select_delivery_target(world: World) -> Dictionary:
	var targets := _find_direct_delivery_targets(world)
	if targets.is_empty():
		return {}
	return targets[0]

func _find_direct_delivery_targets(world: World) -> Array[Dictionary]:
	var targets: Array[Dictionary] = []
	if world == null:
		return targets
	if get_factory_inventory_amount("clothes") <= 0:
		return targets
	for building in world.buildings:
		var target := building as CommercialBuilding
		if target == null or target == self or not is_instance_valid(target):
			continue
		if target.is_financially_closed():
			continue
		if not target.restock_enabled:
			continue
		for item in target.restock_targets.keys():
			var item_key := str(item).strip_edges()
			if item_key.is_empty():
				continue
			var commodity := str(target.source_commodities.get(item_key, item_key)).strip_edges()
			if commodity != "clothes":
				continue
			if _calculate_delivery_quantity(world, target, item_key, commodity) <= 0:
				continue
			if not _has_vehicle_route_to(world, target):
				continue
			targets.append({
				"building": target,
				"item": item_key,
				"commodity": commodity,
			})
	targets.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var target_a := a.get("building", null) as Building
		var target_b := b.get("building", null) as Building
		if target_a == null:
			return false
		if target_b == null:
			return true
		return global_position.distance_squared_to(target_a.global_position) < global_position.distance_squared_to(target_b.global_position)
	)
	return targets

func _calculate_delivery_quantity(
	world: World,
	target: CommercialBuilding,
	target_item: String,
	commodity: String,
	max_qty: int = -1
) -> int:
	if world == null or target == null or not is_instance_valid(target):
		return 0
	if target_item.strip_edges().is_empty() or commodity.strip_edges().is_empty():
		return 0
	var need := target.get_restock_need(target_item)
	if need <= 0:
		return 0
	var limit := direct_delivery_batch_per_retailer if max_qty < 0 else mini(max_qty, direct_delivery_batch_per_retailer)
	var unit_price := _get_direct_delivery_unit_price(world, commodity)
	var affordable_qty: int = target.account.balance / unit_price
	var available_stock := get_factory_inventory_amount(commodity)
	return maxi(mini(available_stock, mini(need, mini(limit, affordable_qty))), 0)

func _get_direct_delivery_unit_price(world: World, commodity: String) -> int:
	if world == null or world.economy == null:
		return 1
	var wholesale_price := world.economy.get_wholesale_unit_price(commodity)
	return maxi(int(round(float(wholesale_price) * direct_delivery_price_multiplier)), 1)

func _get_delivery_reserved_commodities(world: World) -> Dictionary:
	var reserved: Dictionary = {}
	if direct_shop_delivery_enabled and has_delivery_staff() and not _find_direct_delivery_targets(world).is_empty():
		reserved["clothes"] = true
	return reserved

func _ensure_delivery_vehicle(world: World) -> bool:
	if not _resolve_delivery_depot_positions(world):
		return false
	if _delivery_vehicle != null and is_instance_valid(_delivery_vehicle):
		return true
	var vehicle := VehicleDepotAccessScript.find_available_delivery_vehicle(self, world)
	if vehicle == null:
		push_warning("Factory: No free delivery vehicle available at depot.")
		return false
	_delivery_vehicle = vehicle
	_delivery_vehicle.add_to_group(VehicleDepotAccessScript.DELIVERY_VEHICLE_ASSIGNED_GROUP)
	if world != null and world.has_method("register_vehicle"):
		world.register_vehicle(_delivery_vehicle)
	return true

func _has_vehicle_route_to(world: World, target: Building) -> bool:
	if world == null or target == null:
		return false
	if not world.has_method("get_vehicle_road_path"):
		return false
	if not _resolve_delivery_depot_positions(world):
		return false
	var outbound_route: PackedVector3Array = world.get_vehicle_road_path(_delivery_depot_road_access_position, target.get_entrance_pos())
	if outbound_route.size() < 2:
		return false
	var return_route: PackedVector3Array = world.get_vehicle_road_path(target.get_entrance_pos(), _delivery_depot_road_access_position)
	return return_route.size() >= 2

func _export_factory_inventory_to_market(world: World, reserved_commodities: Dictionary) -> void:
	if world == null or not market_export_enabled:
		return
	var remaining_limit := market_export_limit_per_day
	var commodity_keys := inventory.keys()
	commodity_keys.sort()
	for key in commodity_keys:
		var commodity := str(key).strip_edges()
		if commodity.is_empty() or reserved_commodities.has(commodity):
			continue
		var available := get_factory_inventory_amount(commodity)
		if available <= 0:
			continue
		var offered := available
		if market_export_limit_per_day > 0:
			if remaining_limit <= 0:
				return
			offered = mini(offered, remaining_limit)
		var result: Dictionary = world.economy.sell_wholesale_to_market(account, commodity, offered)
		var accepted_qty := int(result.get("qty", 0))
		if accepted_qty <= 0:
			continue
		_remove_product_from_inventory(commodity, accepted_qty)
		shipped_goods_today += accepted_qty
		market_exported_goods_today += accepted_qty
		if market_export_limit_per_day > 0:
			remaining_limit -= accepted_qty
		var revenue := int(result.get("total_revenue", 0))
		if revenue > 0:
			record_income(revenue)

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

func _prune_invalid_delivery_worker() -> void:
	if _delivery_worker == null:
		return
	if not is_instance_valid(_delivery_worker):
		_release_delivery_worker()
		return
	if _delivery_worker.job == null or _delivery_worker.job.workplace != self:
		_release_delivery_worker()

func _release_delivery_worker() -> void:
	_delivery_worker = null
	_delivery_target = null
	_delivery_target_item = ""
	_delivery_source_commodity = ""
	_delivery_phase = DELIVERY_PHASE_NONE
	_delivery_quantity = 0
	_delivery_minutes_left = 0
	_delivery_depot_parking_position = Vector3.INF
	_delivery_depot_road_access_position = Vector3.INF

func _is_delivery_worker(citizen: Citizen) -> bool:
	if citizen == null or citizen.job == null:
		return false
	return citizen.job.title.strip_edges().to_lower() == "fahrer"

func _ensure_factory_inventory_registered() -> void:
	if not inventory.has("clothes"):
		inventory["clothes"] = initial_clothes_stock
	if not inventory.has("entertainment"):
		inventory["entertainment"] = initial_entertainment_stock
	_clamp_all_inventory_to_capacity()

func _resolve_commodity_key(commodity: String) -> String:
	var cleaned := commodity.strip_edges()
	if cleaned.is_empty():
		return "clothes"
	return cleaned

func _get_inventory_amount(commodity: String) -> int:
	var cleaned := commodity.strip_edges()
	if cleaned.is_empty():
		return 0
	return maxi(int(inventory.get(cleaned, 0)), 0)

func _set_inventory_amount_clamped(commodity: String, amount: int) -> void:
	var cleaned := _resolve_commodity_key(commodity)
	var current := _get_inventory_amount(cleaned)
	var other_products := _get_total_inventory_units_raw() - current
	var allowed := maxi(storage_capacity - other_products, 0)
	inventory[cleaned] = mini(maxi(amount, 0), allowed)

func _add_product_to_inventory(commodity: String, amount: int) -> int:
	if amount <= 0:
		return 0
	var accepted := mini(maxi(amount, 0), _get_available_storage())
	if accepted <= 0:
		return 0
	var cleaned := _resolve_commodity_key(commodity)
	inventory[cleaned] = _get_inventory_amount(cleaned) + accepted
	return accepted

func _remove_product_from_inventory(commodity: String, amount: int) -> int:
	if amount <= 0:
		return 0
	var cleaned := _resolve_commodity_key(commodity)
	var current := _get_inventory_amount(cleaned)
	var removed := mini(maxi(amount, 0), current)
	if removed <= 0:
		return 0
	inventory[cleaned] = current - removed
	return removed

func _get_available_storage() -> int:
	return maxi(storage_capacity - _get_total_inventory_units_raw(), 0)

func _get_total_inventory_units_raw() -> int:
	var total := 0
	for key in inventory.keys():
		total += _get_inventory_amount(str(key))
	return total

func _clamp_all_inventory_to_capacity() -> void:
	var remaining := maxi(storage_capacity, 0)
	var keys := inventory.keys()
	keys.sort()
	for key in keys:
		var commodity := str(key)
		var amount := mini(_get_inventory_amount(commodity), remaining)
		inventory[commodity] = amount
		remaining -= amount

func _get_extra_info(_world = null) -> Dictionary:
	var info := get_commercial_info()
	info["Output clothes"] = str(output_clothes_today)
	info["Output entertainment"] = str(output_entertainment_today)
	info["Factory inventory"] = _format_factory_inventory()
	info["Delivered goods today"] = str(delivered_goods_today)
	info["Market export today"] = str(market_exported_goods_today)
	info["Delivery staff"] = str(get_workers_by_titles(["Fahrer"]).size())
	if _delivery_target != null and is_instance_valid(_delivery_target):
		info["Delivery target"] = _delivery_target.get_display_name()
	return info

func _format_factory_inventory() -> String:
	var parts: PackedStringArray = []
	for key in inventory.keys():
		var commodity := str(key).strip_edges()
		if commodity.is_empty():
			continue
		parts.append("%s:%d" % [commodity, _get_inventory_amount(commodity)])
	if parts.is_empty():
		return "-"
	return ", ".join(parts)
