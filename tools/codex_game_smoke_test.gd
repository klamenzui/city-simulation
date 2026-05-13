extends SceneTree

const SETTLE_FRAMES := 30
const POST_DAY_FRAMES := 30

func _init() -> void:
	print("=== Game smoke test ===")
	var main_scene := load("res://Main.tscn")
	if main_scene == null:
		printerr("FAIL: cannot load Main.tscn")
		quit(1)
		return

	var main: Node = main_scene.instantiate()
	root.add_child(main)

	for _i in range(SETTLE_FRAMES):
		await process_frame
	await physics_frame

	var world := main.get_node_or_null("World") as World
	if world == null:
		printerr("FAIL: World node not found")
		quit(1)
		return

	if world.citizens.is_empty():
		printerr("FAIL: no citizens registered after scene setup")
		quit(1)
		return
	if world.buildings.is_empty():
		printerr("FAIL: no buildings registered after scene setup")
		quit(1)
		return
	var park_count := _count_registered_parks(world)
	if park_count != 1:
		printerr("FAIL: expected one registered park cluster, got %d" % park_count)
		quit(1)
		return

	_ensure_rent_has_a_tenant(world)
	var tenant_count := _count_residential_tenants(world)
	print("scene citizens=%d buildings=%d parks=%d residential_tenants=%d" % [
		world.citizens.size(),
		world.buildings.size(),
		park_count,
		tenant_count
	])
	if tenant_count <= 0:
		printerr("FAIL: no residential tenants available for rent smoke")
		quit(1)
		return

	var residential_balance_before := _sum_residential_account_balance(world)
	var day_before := world.time.day
	world.time.advance(24 * 60)
	for _i in range(POST_DAY_FRAMES):
		await process_frame
	await physics_frame
	var residential_balance_after := _sum_residential_account_balance(world)

	if world.time.day <= day_before:
		printerr("FAIL: day did not advance")
		quit(1)
		return
	if residential_balance_after <= residential_balance_before:
		printerr("FAIL: residential rent did not increase landlord balances")
		quit(1)
		return

	print("advanced day %d -> %d time=%s" % [
		day_before,
		world.time.day,
		world.time.get_time_string()
	])
	print("residential_balance=%d -> %d" % [
		residential_balance_before,
		residential_balance_after
	])
	print("GAME_SMOKE OK")
	main.queue_free()
	await process_frame
	quit(0)


func _ensure_rent_has_a_tenant(world: World) -> void:
	if _count_residential_tenants(world) > 0:
		return
	var citizen := world.citizens[0] as Citizen if not world.citizens.is_empty() else null
	if citizen == null:
		return
	for building in world.buildings:
		if building is ResidentialBuilding:
			var residential := building as ResidentialBuilding
			if residential.add_tenant(citizen):
				citizen.home = residential
				return


func _count_residential_tenants(world: World) -> int:
	var total := 0
	for building in world.buildings:
		if building is ResidentialBuilding:
			total += (building as ResidentialBuilding).tenants.size()
	return total


func _count_registered_parks(world: World) -> int:
	var total := 0
	for building in world.buildings:
		if building is Park or building.is_in_group("parks"):
			total += 1
	return total


func _sum_residential_account_balance(world: World) -> int:
	var total := 0
	for building in world.buildings:
		if building is ResidentialBuilding:
			total += (building as ResidentialBuilding).account.balance
	return total
