extends SceneTree

const MainScene := preload("res://Main.tscn")

const SETTLE_PROCESS_FRAMES := 24
const SETTLE_PHYSICS_FRAMES := 4

var _errors: Array[String] = []


func _initialize() -> void:
	var main := MainScene.instantiate()
	if main == null:
		_errors.append("Could not instantiate Main.tscn.")
		_finish()
		return
	root.add_child(main)

	for _i in range(SETTLE_PROCESS_FRAMES):
		await process_frame
	for _i in range(SETTLE_PHYSICS_FRAMES):
		await physics_frame

	var world := main.get_node_or_null("World") as World
	if world == null:
		_errors.append("Main.tscn should expose $World.")
		_finish(main)
		return

	var pair := _find_first_day_delivery_pair(world)
	if pair.is_empty():
		_errors.append("Start world should contain one staffed, stocked Farm with a road route to a Supermarket that needs restock. %s" % _build_debug_summary(world))
		_finish(main)
		return

	var farm := pair.get("farm", null) as Farm
	var market := pair.get("market", null) as Supermarket
	print("FIRST_DAY_DELIVERY_SEED_TEST OK farm=%s stock=%d market=%s need=%d" % [
		farm.get_display_name(),
		farm.get_product_inventory_amount(farm.get_product_commodity()),
		market.get_display_name(),
		market.get_restock_need(farm.get_supermarket_delivery_item()),
	])
	_finish(main)


func _find_first_day_delivery_pair(world: World) -> Dictionary:
	if world == null:
		return {}
	for building in world.buildings:
		var farm := building as Farm
		if farm == null or not is_instance_valid(farm):
			continue
		if not farm.direct_supermarket_delivery_enabled:
			continue
		if not farm.has_delivery_staff():
			continue
		var product_key := farm.get_product_commodity()
		var farm_stock := farm.get_product_inventory_amount(product_key)
		if farm_stock <= 0:
			continue
		var delivery_item := farm.get_supermarket_delivery_item()
		for building2 in world.buildings:
			var market := building2 as Supermarket
			if market == null or not is_instance_valid(market):
				continue
			if market.is_financially_closed() or not market.restock_enabled:
				continue
			var restock_need := market.get_restock_need(delivery_item)
			if restock_need <= 0:
				continue
			var route := world.get_vehicle_road_path(farm.get_storage_point_global(), market.get_entrance_pos())
			if route.size() <= 2:
				continue
			var delivery_quantity := mini(farm_stock, mini(restock_need, farm.direct_delivery_batch_per_supermarket))
			if delivery_quantity <= 0:
				continue
			return {
				"farm": farm,
				"market": market,
				"quantity": delivery_quantity,
			}
	return {}


func _build_debug_summary(world: World) -> String:
	if world == null:
		return "world=null"
	var farms := 0
	var stocked_farms := 0
	var driver_farms := 0
	var supermarkets_with_need := 0
	var routed_pairs := 0
	for building in world.buildings:
		var farm := building as Farm
		if farm == null or not is_instance_valid(farm):
			continue
		farms += 1
		if farm.get_product_inventory_amount(farm.get_product_commodity()) > 0:
			stocked_farms += 1
		if farm.has_delivery_staff():
			driver_farms += 1
		var delivery_item := farm.get_supermarket_delivery_item()
		for building2 in world.buildings:
			var market := building2 as Supermarket
			if market == null or not is_instance_valid(market):
				continue
			if market.get_restock_need(delivery_item) > 0:
				supermarkets_with_need += 1
				var route := world.get_vehicle_road_path(farm.get_storage_point_global(), market.get_entrance_pos())
				if route.size() > 2:
					routed_pairs += 1
	return "farms=%d stocked=%d with_driver=%d supermarkets_with_need=%d routed_pairs=%d" % [
		farms,
		stocked_farms,
		driver_farms,
		supermarkets_with_need,
		routed_pairs,
	]


func _finish(main: Node = null) -> void:
	if main != null:
		main.queue_free()
	if not _errors.is_empty():
		for error in _errors:
			push_error(error)
		quit(FAILED)
		return
	quit(OK)
