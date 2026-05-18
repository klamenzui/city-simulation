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
	var lod_probe := _run_lod_visibility_probe(main, world, 140)
	print("lod_probe visible=%d focus=%d active=%d coarse=%d budget=%d controlled_visible=%s" % [
		int(lod_probe.get("visible", 0)),
		int(lod_probe.get("focus", 0)),
		int(lod_probe.get("active", 0)),
		int(lod_probe.get("coarse", 0)),
		int(lod_probe.get("budget", 0)),
		str(lod_probe.get("controlled_visible", false)),
	])
	if int(lod_probe.get("visible", 0)) > int(lod_probe.get("budget", 0)):
		printerr("FAIL: visible citizens exceed configured LOD budget")
		quit(1)
		return
	if not bool(lod_probe.get("controlled_visible", false)):
		printerr("FAIL: offline third-person controlled citizen should stay visible")
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


func _run_lod_visibility_probe(main: Node, world: World, tick_count: int) -> Dictionary:
	var runtime = main.get("_runtime_controller") if main != null else null
	for _i in range(tick_count):
		world.call("_on_tick")
		if runtime != null and runtime.has_method("update"):
			runtime.update(0.5)
	var counts := {
		"visible": 0,
		"focus": 0,
		"active": 0,
		"coarse": 0,
		"budget": _read_lod_visible_budget(),
		"controlled_visible": false,
	}
	var controlled: Citizen = null
	if main != null:
		controlled = main.get_node_or_null("ControlledCitizen") as Citizen
	for citizen in world.citizens:
		if citizen == null:
			continue
		if citizen.visible:
			counts["visible"] = int(counts["visible"]) + 1
		match citizen.get_simulation_lod_tier() if citizen.has_method("get_simulation_lod_tier") else "focus":
			"focus":
				counts["focus"] = int(counts["focus"]) + 1
			"active":
				counts["active"] = int(counts["active"]) + 1
			"coarse":
				counts["coarse"] = int(counts["coarse"]) + 1
	if controlled != null:
		counts["controlled_visible"] = controlled.visible
	return counts


func _read_lod_visible_budget() -> int:
	var fallback := 15
	var path := "res://config/citizen_simulation_lod.json"
	if not FileAccess.file_exists(path):
		return fallback
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return fallback
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary:
		return fallback
	var budgets: Variant = (parsed as Dictionary).get("budgets", {})
	if budgets is not Dictionary:
		return fallback
	var focus_budget := maxi(int((budgets as Dictionary).get("focus_citizens", fallback)), 0)
	var active_budget := maxi(int((budgets as Dictionary).get("active_citizens", 0)), 0)
	return focus_budget + active_budget
