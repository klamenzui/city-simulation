extends SceneTree

const FarmWorkSceneResource = preload("res://Scenes/WorkScenes/Farm/FarmWorkScene.tscn")
const WindmillFarmScene = preload("res://Scenes/Farm_Windmill.tscn")
const CitizenScene = preload("res://Entities/Citizens/CitizenNew.tscn")
const LocaleServiceScript = preload("res://Simulation/Localization/LocaleService.gd")

const ROLE_WORKER := "worker"
const ROLE_OWNER := "owner"
const DEFAULT_CAPTURE_DIR := "res://.ai/screenshots/farm_windmill_player_probe"

const LIVE_TAKE_WHEAT_SEEDS := "take_wheat_seeds"
const LIVE_SOW_FIELD := "sow_field"
const LIVE_WATER_FIELD := "water_field"
const LIVE_HARVEST_FIELD := "harvest_field"
const LIVE_STORE_GRAIN_SILO := "store_grain_silo"
const LIVE_START_WINDMILL := "start_windmill"
const LIVE_COLLECT_FLOUR := "collect_flour"
const LIVE_STORE_FLOUR_BARN := "store_flour_barn"
const LIVE_LOAD_PICKUP := "load_pickup"

var _errors: Array[String] = []
var _captures: Array[String] = []
var _capture_dir: String = DEFAULT_CAPTURE_DIR
var _role_filter: String = "both"
var _manual_mode: bool = false
var _manual_fixture: Dictionary = {}
var _original_language: String = ""


func _initialize() -> void:
	_parse_args()
	_original_language = LocaleServiceScript.get_language()
	LocaleServiceScript.set_language("de")
	if not _capture_dir.is_empty() and DisplayServer.get_name() != "headless":
		DisplayServer.window_set_size(Vector2i(1440, 900))

	if _manual_mode:
		await _start_manual_session()
		return

	var roles := _selected_roles()
	for role in roles:
		await _run_role_probe(role)
	_finish()


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--manual":
			_manual_mode = true
		elif arg == "--no-capture":
			_capture_dir = ""
		elif arg.begins_with("--capture-dir="):
			_capture_dir = arg.substr("--capture-dir=".length()).strip_edges()
		elif arg.begins_with("--role="):
			_role_filter = arg.substr("--role=".length()).strip_edges().to_lower()


func _selected_roles() -> Array[String]:
	if _role_filter == ROLE_WORKER:
		return [ROLE_WORKER]
	if _role_filter == ROLE_OWNER:
		return [ROLE_OWNER]
	return [ROLE_WORKER, ROLE_OWNER]


func _start_manual_session() -> void:
	var role := _role_filter if _role_filter in [ROLE_WORKER, ROLE_OWNER] else ROLE_WORKER
	var fixture := await _create_role_fixture(role)
	if fixture.is_empty():
		_finish()
		return
	var scene := await _mount_work_scene(fixture, role)
	if scene == null:
		await _free_fixture(fixture)
		_finish()
		return
	_manual_fixture = fixture
	fixture["scene"] = scene
	scene.connect("session_finished", Callable(self, "_on_manual_session_finished").bind(fixture, role))
	print("FARM_WINDMILL_PLAYER_PROBE MANUAL role=%s" % role)
	print("Use WASD/arrow keys to move, F or left click near farm objects to interact, Q/E to rotate camera, ESC to finish.")


func _on_manual_session_finished(result: Dictionary, fixture: Dictionary, role: String) -> void:
	var world := fixture.get("world", null) as World
	var farm := fixture.get("farm", null) as Farm
	var actor := fixture.get("actor", null) as Citizen
	var applied := farm.apply_player_work_result(world, actor, result) if farm != null else {"accepted": false, "reason": "missing_farm"}
	print("FARM_WINDMILL_PLAYER_PROBE MANUAL_RESULT role=%s result=%s applied=%s" % [
		role,
		str(result),
		str(applied),
	])
	if not _original_language.is_empty():
		LocaleServiceScript.set_language(_original_language)
	quit(0 if bool(applied.get("accepted", false)) else 1)


func _run_role_probe(role: String) -> void:
	var fixture := await _create_role_fixture(role)
	if fixture.is_empty():
		return

	var world := fixture.get("world", null) as World
	var farm := fixture.get("farm", null) as Farm
	var actor := fixture.get("actor", null) as Citizen
	_validate_role_contract(world, farm, actor, role)
	_expect(farm != null and farm.begin_player_work_session(actor), "%s should be allowed to begin Windmill Farm work." % role)

	var scene := await _mount_work_scene(fixture, role)
	if scene == null:
		await _free_fixture(fixture)
		return
	fixture["scene"] = scene

	_focus_interactable(scene, "shed")
	await _capture("%s_start.png" % role)
	await _run_windmill_action_flow(scene, role)
	_focus_interactable(scene, "windmill")
	await _capture("%s_windmill_complete.png" % role)

	var result := scene.call("get_result") as Dictionary
	_validate_work_result(result, role)
	_apply_and_validate_result(fixture, result, role)
	if scene.has_method("finish_session"):
		scene.call("finish_session")
	await _free_fixture(fixture)


func _create_role_fixture(role: String) -> Dictionary:
	var world := World.new()
	world.name = "FarmWindmillProbeWorld_%s" % role
	root.add_child(world)
	await process_frame

	var farm := WindmillFarmScene.instantiate() as Farm
	if farm == null:
		_fail("Could not instantiate Scenes/Farm_Windmill.tscn as Farm.")
		world.queue_free()
		return {}
	farm.name = "ProbeWindmillFarm_%s" % role
	farm.visible = false
	root.add_child(farm)
	await process_frame
	world.register_building(farm)
	_prepare_windmill_farm(farm)

	var market := Supermarket.new()
	market.name = "ProbeSupermarket_%s" % role
	market.building_name = "Probe Supermarket %s" % role.capitalize()
	market.position = farm.position + Vector3(24.0, 0.0, 0.0)
	root.add_child(market)
	await process_frame
	world.register_building(market)
	_prepare_target_market(market, farm)

	var actor := CitizenScene.instantiate() as Citizen
	if actor == null:
		_fail("Could not instantiate CitizenNew.tscn for %s probe." % role)
		market.queue_free()
		farm.queue_free()
		world.queue_free()
		return {}
	root.add_child(actor)
	await process_frame
	_prepare_actor(actor, farm, role)
	_assign_role(world, farm, actor, role)

	return {
		"world": world,
		"farm": farm,
		"market": market,
		"actor": actor,
		"stock_before": farm.get_product_inventory_amount(farm.get_product_commodity()),
	}


func _prepare_windmill_farm(farm: Farm) -> void:
	farm.job_capacity = maxi(farm.job_capacity, 6)
	farm.storage_capacity = maxi(farm.storage_capacity, 160)
	farm.account.balance = maxi(farm.account.balance, 5000)
	if farm.is_financially_closed():
		farm.reopen_after_funding()
	farm.crop_state = Farm.CropState.GROWING
	farm.crop_growth_minutes = 0
	farm.owner_work_minutes_today = 0
	farm.market_export_enabled = false
	farm.direct_supermarket_delivery_enabled = true
	farm.set_product_inventory_amount(farm.get_product_commodity(), 24)


func _prepare_target_market(market: Supermarket, farm: Farm) -> void:
	var item_id := farm.get_supermarket_delivery_item()
	var commodity := farm.get_product_commodity()
	if not market.inventory.has(item_id):
		market.define_stock_item(item_id, 0, 7, 36, 18, commodity)
	market.restock_enabled = true
	market.inventory[item_id] = 0
	market.restock_targets[item_id] = maxi(int(market.restock_targets.get(item_id, 36)), 36)
	market.source_commodities[item_id] = commodity
	market.account.balance = maxi(market.account.balance, 5000)


func _prepare_actor(actor: Citizen, farm: Farm, role: String) -> void:
	actor.citizen_name = "Probe %s" % role.capitalize()
	actor.global_position = farm.get_entrance_pos()
	actor.wallet.balance = 1000
	if actor.needs != null:
		actor.needs.hunger = 0.0
		actor.needs.energy = 100.0
		actor.needs.health = 100.0
		actor.needs.fun = 100.0
	actor.work_minutes_today = 0


func _assign_role(world: World, farm: Farm, actor: Citizen, role: String) -> void:
	if role == ROLE_OWNER:
		actor.job = null
		farm.citizen_owner = actor
		farm.owner_display_name = actor.citizen_name
		_expect(farm.can_actor_perform_work(actor), "Owner should work at Windmill Farm without employment.")
		return

	var job := _make_farm_job(farm, "Gardener")
	actor.job = job
	world.register_job(job)
	_expect(farm.try_hire(actor), "Worker should be hired by Windmill Farm.")
	_expect(farm.is_worker(actor), "Worker role should register as Farm worker.")


func _make_farm_job(farm: Farm, title: String) -> Job:
	var job := Job.new()
	job.title = title
	job.workplace = farm
	job.preferred_workplace = farm
	job.wage_per_hour = 12
	job.start_hour = 6
	job.shift_hours = 8
	job.allowed_building_types = [farm.building_type]
	return job


func _mount_work_scene(fixture: Dictionary, role: String) -> Node:
	var world := fixture.get("world", null) as World
	var farm := fixture.get("farm", null) as Farm
	var actor := fixture.get("actor", null) as Citizen
	var scene := FarmWorkSceneResource.instantiate()
	if scene == null:
		_fail("Could not instantiate FarmWorkScene for %s." % role)
		return null
	scene.set("auto_start", false)
	var skill_level := 3 if role == ROLE_OWNER else 1
	_expect(
		bool(scene.call("configure_for_farm", farm, skill_level, world, actor)),
		"FarmWorkScene should configure for %s Windmill Farm context." % role
	)
	root.add_child(scene)
	await process_frame
	scene.call("start_session")
	for _i in range(30):
		await physics_frame
	_validate_visual_contract(scene, role)
	return scene


func _validate_role_contract(world: World, farm: Farm, actor: Citizen, role: String) -> void:
	if world == null or farm == null or actor == null:
		_fail("Missing role fixture for %s." % role)
		return
	var context := farm.get_player_work_context(world, actor)
	_expect(str(context.get("actor_role", "")) == role, "%s context should expose actor_role=%s." % [role, role])
	var demand_entries: Array = context.get("demand_entries", [])
	_expect(not demand_entries.is_empty(), "%s should see compatible Windmill Farm demand." % role)
	if role == ROLE_OWNER:
		_expect(_demand_has_finance(demand_entries), "Owner demand should expose revenue fields.")
	else:
		_expect(not _demand_has_finance(demand_entries), "Worker demand must hide revenue fields.")


func _validate_visual_contract(scene: Node, role: String) -> void:
	_expect(scene.get_node_or_null("WindmillFarm3D") != null, "%s scene should build the WindmillFarm3D root." % role)
	_expect(scene.get_node_or_null("WindmillFarm3D/ExistingFarm/TowerWindmill") != null, "%s scene should render the TowerWindmill." % role)
	_expect(scene.get_node_or_null("WindmillFarm3D/ExistingFarm/Buildings/BigBarnModel") != null, "%s scene should render the big barn." % role)
	_expect(scene.get_node_or_null("WindmillFarm3D/ExistingFarm/Buildings/SiloModel") != null, "%s scene should render the silo." % role)
	_expect(scene.get_node_or_null("WindmillFarm3D/ExistingFarm/Fields/FieldWest2/FarmlandModel") != null, "%s scene should render the wheat field." % role)
	_expect(scene.get_node_or_null("WindmillFarm3D/ExistingFarm/Obstacles/GroundShape") != null, "%s scene should reuse the Windmill Farm ground collider." % role)
	var player := scene.get_node_or_null("WindmillFarm3D/Player") as CharacterBody3D
	_expect(player != null, "%s scene should spawn a playable worker body." % role)
	if player != null:
		_expect(player.global_position.y > -0.5, "%s player should not fall through the Windmill Farm floor." % role)
		_expect(player.is_on_floor(), "%s player should settle on the farm floor." % role)
	var camera := scene.get_node_or_null("WindmillFarm3D/CameraPivot/FarmCamera") as Camera3D
	_expect(camera != null and camera.current, "%s scene should own the active FarmCamera." % role)
	for interactable_id in ["field_wheat", "barn", "shed", "silo", "windmill", "machine_yard", "gate"]:
		_expect(scene.call("_find_interactable", interactable_id) != null, "%s scene should bind interactable %s." % [role, interactable_id])
	_validate_windmill_context(scene, role)


func _validate_windmill_context(scene: Node, role: String) -> void:
	var windmill = scene.call("_find_interactable", "windmill")
	if windmill == null:
		return
	var lines := scene.call("_get_context_lines", windmill) as PackedStringArray
	_expect(_packed_lines_contain(lines, "Benötigt:"), "%s windmill context should show required grain." % role)
	_expect(_packed_lines_contain(lines, "Output:"), "%s windmill context should show production output." % role)
	var actions := scene.call("_get_context_actions", windmill) as Array
	_expect(_actions_contain(actions, LIVE_START_WINDMILL), "%s windmill context should offer production start." % role)
	_expect(_actions_contain(actions, LIVE_COLLECT_FLOUR), "%s windmill context should offer flour collection." % role)


func _run_windmill_action_flow(scene: Node, role: String) -> void:
	_expect_action(scene, "shed", LIVE_TAKE_WHEAT_SEEDS, role)
	_expect_action(scene, "field_wheat", LIVE_SOW_FIELD, role)
	_expect(_is_node_visible(scene, "WindmillFarm3D/ExistingFarm/Fields/FieldWest2/CropWheatInstancesEast/WheatItem"), "%s wheat crop should be visible after sowing." % role)
	_expect_action(scene, "field_wheat", LIVE_WATER_FIELD, role)
	scene.call("debug_tick_live", 9.0)
	var wheat_field := scene.call("debug_get_field_snapshot", "field_wheat") as Dictionary
	_expect(str(wheat_field.get("state_label", "")) == "mature", "%s wheat field should mature during probe time." % role)
	_expect_action(scene, "field_wheat", LIVE_HARVEST_FIELD, role)
	_expect(not _is_node_visible(scene, "WindmillFarm3D/ExistingFarm/Fields/FieldWest2/CropWheatInstancesEast/WheatItem"), "%s wheat crop should be hidden after harvest." % role)
	_expect_action(scene, "silo", LIVE_STORE_GRAIN_SILO, role)
	var silo_inventory := scene.call("debug_get_inventory_snapshot", "silo") as Dictionary
	_expect(int(silo_inventory.get("wheat_grain", 0)) >= 10, "%s silo should contain enough wheat for the windmill." % role)
	_expect_action(scene, "windmill", LIVE_START_WINDMILL, role)
	scene.call("debug_tick_live", 9.0)
	var result_mid := scene.call("get_result") as Dictionary
	var production := result_mid.get("production", {}) as Dictionary
	_expect(int(production.get("produced_sacks_pending", 0)) > 0, "%s windmill should produce pending flour sacks." % role)
	_expect_action(scene, "windmill", LIVE_COLLECT_FLOUR, role)
	_expect_action(scene, "barn", LIVE_STORE_FLOUR_BARN, role)
	_expect_action(scene, "machine_yard", LIVE_LOAD_PICKUP, role)
	var pickup_inventory := scene.call("debug_get_inventory_snapshot", "pickup") as Dictionary
	_expect(int(pickup_inventory.get("flour_sack", 0)) > 0, "%s pickup should be loaded with flour sacks." % role)


func _expect_action(scene: Node, interactable_id: String, action_id: String, role: String) -> void:
	var result := scene.call("debug_perform_live_action", interactable_id, action_id) as Dictionary
	_expect(
		bool(result.get("correct", false)),
		"%s action %s on %s should pass, reason=%s." % [
			role,
			action_id,
			interactable_id,
			str(result.get("reason", "")),
		]
	)


func _validate_work_result(result: Dictionary, role: String) -> void:
	_expect(int(result.get("harvested_amount", 0)) > 0, "%s result should include harvested wheat." % role)
	_expect(int(result.get("goods_produced", 0)) > 0, "%s result should include windmill flour production." % role)
	_expect(int(result.get("goods_delivered", 0)) > 0, "%s result should include loaded pickup goods." % role)
	_expect(float(result.get("quality_score", 0.0)) >= 0.62, "%s result should be good enough to apply." % role)
	_expect(int(result.get("work_minutes", 0)) > 0, "%s result should include work minutes." % role)


func _apply_and_validate_result(fixture: Dictionary, result: Dictionary, role: String) -> void:
	var world := fixture.get("world", null) as World
	var farm := fixture.get("farm", null) as Farm
	var actor := fixture.get("actor", null) as Citizen
	if world == null or farm == null or actor == null:
		_fail("Cannot apply %s result because the fixture is incomplete." % role)
		return
	var stock_before := int(fixture.get("stock_before", 0))
	var paid_minutes_before := actor.work_minutes_today
	var owner_minutes_before := farm.owner_work_minutes_today
	var applied := farm.apply_player_work_result(world, actor, result)
	_expect(bool(applied.get("accepted", false)), "%s result should be accepted by authoritative Farm.gd." % role)
	_expect(farm.get_product_inventory_amount(farm.get_product_commodity()) > stock_before, "%s work should add product stock to Windmill Farm." % role)
	_expect(not farm.has_player_work_session_in_progress(), "%s work session should be released after applying the result." % role)
	if role == ROLE_OWNER:
		_expect(actor.work_minutes_today == paid_minutes_before, "Owner work must not create paid wage minutes.")
		_expect(farm.owner_work_minutes_today > owner_minutes_before, "Owner work should record unpaid owner minutes.")
	else:
		_expect(actor.work_minutes_today > paid_minutes_before, "Worker work should record paid work minutes.")


func _focus_interactable(scene: Node, interactable_id: String) -> void:
	var interactable = scene.call("_find_interactable", interactable_id)
	var player := scene.get_node_or_null("WindmillFarm3D/Player") as CharacterBody3D
	if interactable == null or player == null:
		return
	player.global_position = interactable.global_position + Vector3(0.0, 0.4, 1.4)
	player.velocity = Vector3.ZERO
	scene.call("_update_nearest_interactable")
	scene.call("_open_context_for", interactable)
	scene.call("_update_all_ui")


func _capture(file_name: String) -> void:
	if _capture_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	for _i in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null:
		_fail("Could not read viewport image for %s." % file_name)
		return
	_expect(_image_has_visible_content(image), "Screenshot %s should contain non-blank rendered content." % file_name)
	var absolute_dir := ProjectSettings.globalize_path(_capture_dir)
	DirAccess.make_dir_recursive_absolute(absolute_dir)
	var path := _capture_dir.path_join(file_name)
	var err := image.save_png(path)
	_expect(err == OK, "Could not save screenshot %s." % path)
	if err == OK:
		var absolute_path := ProjectSettings.globalize_path(path)
		_captures.append(absolute_path)
		print("FARM_WINDMILL_PLAYER_SCREENSHOT ", absolute_path)


func _image_has_visible_content(image: Image) -> bool:
	var width := image.get_width()
	var height := image.get_height()
	if width <= 0 or height <= 0:
		return false
	var min_luma := INF
	var max_luma := -INF
	var opaque_samples := 0
	var step_x := maxi(int(width / 32), 1)
	var step_y := maxi(int(height / 24), 1)
	for y in range(0, height, step_y):
		for x in range(0, width, step_x):
			var color := image.get_pixel(x, y)
			if color.a <= 0.01:
				continue
			opaque_samples += 1
			var luma := color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
			min_luma = minf(min_luma, luma)
			max_luma = maxf(max_luma, luma)
	return opaque_samples > 16 and max_luma - min_luma > 0.03


func _free_fixture(fixture: Dictionary) -> void:
	for key in ["scene", "actor", "market", "farm", "world"]:
		var node := fixture.get(key, null) as Node
		if node != null and is_instance_valid(node):
			node.queue_free()
	await process_frame


func _demand_has_finance(entries: Array) -> bool:
	for entry_var in entries:
		var entry := entry_var as Dictionary
		if entry.has("expected_revenue") or entry.has("unit_price"):
			return true
	return false


func _packed_lines_contain(lines: PackedStringArray, needle: String) -> bool:
	for line in lines:
		if line.contains(needle):
			return true
	return false


func _actions_contain(actions: Array, action_id: String) -> bool:
	for action_var in actions:
		var action := action_var as Dictionary
		if str(action.get("id", "")) == action_id:
			return true
	return false


func _is_node_visible(scene: Node, node_path: String) -> bool:
	var node := scene.get_node_or_null(NodePath(node_path)) as Node3D
	return node != null and node.is_visible_in_tree()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	_errors.append(message)


func _finish() -> void:
	if not _original_language.is_empty():
		LocaleServiceScript.set_language(_original_language)
	if _errors.is_empty():
		print("FARM_WINDMILL_PLAYER_PROBE OK roles=%s captures=%d" % [
			",".join(_selected_roles()),
			_captures.size(),
		])
		quit(0)
		return
	print("FARM_WINDMILL_PLAYER_PROBE FAILED:")
	for error in _errors:
		print("  - %s" % error)
	quit(1)
