extends SceneTree

const FarmWorkSceneResource = preload("res://Scenes/WorkScenes/Farm/FarmWorkScene.tscn")
const CitizenScene = preload("res://Entities/Citizens/CitizenNew.tscn")
const SimulationInteractionControllerScript = preload("res://Simulation/UI/SimulationInteractionController.gd")

const ACTION_PLANT := "plant"
const ACTION_WATER := "water"
const ACTION_WEED := "weed"
const ACTION_HARVEST := "harvest"
const ACTION_DELIVER := "deliver"
const LIVE_TAKE_WHEAT_SEEDS := "take_wheat_seeds"
const LIVE_SOW_FIELD := "sow_field"
const LIVE_WATER_FIELD := "water_field"
const LIVE_HARVEST_FIELD := "harvest_field"
const LIVE_STORE_GRAIN_SILO := "store_grain_silo"
const LIVE_START_WINDMILL := "start_windmill"
const LIVE_COLLECT_FLOUR := "collect_flour"
const LIVE_STORE_FLOUR_BARN := "store_flour_barn"
const LIVE_LOAD_PICKUP := "load_pickup"


func _initialize() -> void:
	var failures: Array[String] = []
	var world := World.new()
	world.name = "FarmWorkSceneTestWorld"
	root.add_child(world)
	await process_frame

	var farm := Farm.new()
	farm.name = "FarmWorkSceneProbeFarm"
	farm.job_capacity = 6
	farm.storage_capacity = 140
	farm.account.balance = 1000
	root.add_child(farm)
	await process_frame
	farm.crop_state = Farm.CropState.READY
	farm.crop_growth_minutes = farm.get_crop_growth_total_minutes()
	farm.set_product_inventory_amount(farm.get_product_commodity(), 0)

	var player := CitizenScene.instantiate() as Citizen
	root.add_child(player)
	await process_frame
	var player_job := _make_farm_job(farm, "Gardener")
	player.job = player_job
	player.needs.hunger = 0.0
	player.needs.energy = 100.0
	player.needs.fun = 100.0
	player.needs.health = 100.0
	_expect(farm.try_hire(player), "player should be hired by farm", failures)
	_expect(farm.begin_player_work_session(player), "player farm work session should start", failures)
	_expect(farm.has_player_work_session_in_progress(), "farm should track active player work session", failures)

	var game := FarmWorkSceneResource.instantiate()
	game.set("auto_start", false)
	_expect(bool(game.call("configure_for_farm", farm, 1)), "FarmWorkScene should configure for Farm", failures)
	root.add_child(game)
	await process_frame
	game.call("start_session")
	_expect(game is Node3D, "FarmWorkScene should be a 3D scene root", failures)
	_expect(game.get_node_or_null("WindmillFarm3D/Player") != null, "FarmWorkScene should spawn a walkable player", failures)
	_expect(game.get_node_or_null("WindmillFarm3D") != null, "FarmWorkScene should build a 3D farm world", failures)
	_expect(game.get_node_or_null("WindmillFarm3D/ExistingFarm/Buildings/BigBarnModel") != null, "FarmWorkScene should reuse the existing big barn", failures)
	_expect(game.get_node_or_null("WindmillFarm3D/ExistingFarm/Buildings/SiloModel") != null, "FarmWorkScene should reuse the existing silo", failures)
	_expect(game.get_node_or_null("WindmillFarm3D/ExistingFarm/TowerWindmill") != null, "FarmWorkScene should reuse the existing tower windmill", failures)
	_expect(game.get_node_or_null("WindmillFarm3D/ExistingFarm/Fields/FieldWest/FarmlandModel") != null, "FarmWorkScene should reuse the existing west field", failures)
	_expect(game.get_node_or_null("WindmillFarm3D/ExistingFarm/Obstacles/GroundShape") != null, "FarmWorkScene should reuse the Windmill Farm ground collider", failures)
	_expect(game.get_node_or_null("WindmillFarm3D/GroundCollision") == null, "FarmWorkScene should not duplicate the Windmill Farm ground collider", failures)
	_expect(game.get_node_or_null("WindmillFarm3D/MainPath") == null, "FarmWorkScene should not generate a primitive replacement path", failures)
	_expect(game.get_node_or_null("WindmillFarm3D/FenceBack") == null, "FarmWorkScene should not generate replacement fences", failures)
	for interactable_id in ["field_wheat", "field_corn", "barn", "shed", "silo", "windmill", "machine_yard", "gate"]:
		_expect(game.call("_find_interactable", interactable_id) != null, "FarmWorkScene should bind existing interaction: %s" % interactable_id, failures)
	var barn_interactable = game.call("_find_interactable", "barn")
	game.call("_open_context_for", barn_interactable)
	var context_menu := game.get_node_or_null("FarmWorkHud/HudRoot/ContextMenu") as Control
	_expect(context_menu != null and context_menu.visible, "clicking an existing farm object should open its context UI", failures)
	_expect_eq(str(barn_interactable.display_name), "Farm inventory", "barn interaction should open the farm inventory", failures)
	var barn_context_lines := game.call("_get_context_lines", barn_interactable) as PackedStringArray
	_expect(barn_context_lines.has("Stored products"), "farm inventory should show stored products", failures)
	_expect(barn_context_lines.has("Seeds"), "farm inventory should show seed stock", failures)
	var initial_seed_inventory := game.call("debug_get_inventory_snapshot", "seeds") as Dictionary
	_expect(int(initial_seed_inventory.get("wheat_seed", 0)) > 0, "farm inventory should start with wheat seeds", failures)
	_expect(int(initial_seed_inventory.get("corn_seed", 0)) > 0, "farm inventory should start with corn seeds", failures)
	_expect(int(initial_seed_inventory.get("sunflower_seed", 0)) > 0, "farm inventory should start with sunflower seeds", failures)
	var seed_grid := context_menu.find_child("SeedsGrid", true, false) as GridContainer
	var product_grid := context_menu.find_child("StoredproductsGrid", true, false) as GridContainer
	_expect(seed_grid != null and seed_grid.get_child_count() == 3, "farm inventory should render three seed slots", failures)
	_expect(product_grid != null and product_grid.get_child_count() == 4, "farm inventory should render four product slots", failures)
	var wheat_seed_slot := context_menu.find_child("FarmInventorySlot_wheat_seed", true, false) as Button
	var flour_slot := context_menu.find_child("FarmInventorySlot_flour_sack", true, false) as Button
	_expect(wheat_seed_slot != null and not wheat_seed_slot.disabled, "stocked seed slot should be clickable", failures)
	_expect(flour_slot != null and flour_slot.disabled, "empty product slot should stay visible and disabled", failures)
	var wheat_seed_icon := wheat_seed_slot.find_child("Icon", true, false) as TextureRect if wheat_seed_slot != null else null
	var flour_icon := flour_slot.find_child("Icon", true, false) as TextureRect if flour_slot != null else null
	_expect(wheat_seed_icon != null and wheat_seed_icon.texture != null, "seed slot should render its farm icon", failures)
	_expect(flour_icon != null and flour_icon.texture != null, "empty flour slot should keep its farm icon visible", failures)
	var corn_seed_slot := context_menu.find_child("FarmInventorySlot_corn_seed", true, false) as Button
	var corn_grain_slot := context_menu.find_child("FarmInventorySlot_corn_grain", true, false) as Button
	var corn_seed_icon := corn_seed_slot.find_child("Icon", true, false) as TextureRect if corn_seed_slot != null else null
	var corn_grain_icon := corn_grain_slot.find_child("Icon", true, false) as TextureRect if corn_grain_slot != null else null
	_expect(
		corn_seed_icon != null and corn_grain_icon != null
			and corn_seed_icon.texture != corn_grain_icon.texture,
		"corn seed and harvested corn should use distinct icons",
		failures
	)
	if wheat_seed_slot != null:
		var wheat_before_click := int(initial_seed_inventory.get("wheat_seed", 0))
		wheat_seed_slot.pressed.emit()
		var wheat_after_click := int((game.call("debug_get_inventory_snapshot", "seeds") as Dictionary).get("wheat_seed", 0))
		_expect_eq(wheat_after_click, wheat_before_click - 4, "clicking a seed slot should withdraw one seed stack", failures)

	_expect_eq(game.call("get_recommended_action_for_plot", 1), ACTION_HARVEST, "plot 1 should start harvestable", failures)
	var harvest_one := game.call("debug_perform_action", 1, ACTION_HARVEST) as Dictionary
	_expect(bool(harvest_one.get("correct", false)), "ready plot should harvest", failures)
	var bad_harvest := game.call("debug_perform_action", 2, ACTION_HARVEST) as Dictionary
	_expect(not bool(bad_harvest.get("correct", true)), "dry plot should reject harvest", failures)
	_expect_eq(str(bad_harvest.get("required_action", "")), ACTION_WATER, "dry plot should require water", failures)
	_expect(bool((game.call("debug_perform_action", 2, ACTION_WATER) as Dictionary).get("correct", false)), "plot 2 should water", failures)
	_expect(bool((game.call("debug_perform_action", 2, ACTION_HARVEST) as Dictionary).get("correct", false)), "plot 2 should harvest after water", failures)
	_expect(bool((game.call("debug_perform_action", 0, ACTION_DELIVER) as Dictionary).get("correct", false)), "full basket should deliver", failures)
	_expect(bool((game.call("debug_perform_action", 3, ACTION_WEED) as Dictionary).get("correct", false)), "plot 3 should weed", failures)
	_expect(bool((game.call("debug_perform_action", 3, ACTION_HARVEST) as Dictionary).get("correct", false)), "plot 3 should harvest after weeding", failures)
	_expect(bool((game.call("debug_perform_action", 0, ACTION_DELIVER) as Dictionary).get("correct", false)), "second basket should deliver", failures)

	var result := game.call("get_result") as Dictionary
	_expect(int(result.get("harvested_amount", 0)) > 0, "work result should include harvested amount", failures)
	_expect(int(result.get("delivered_crates", 0)) >= 3, "work result should include delivered crates", failures)
	_expect(float(result.get("quality_score", 0.0)) > 0.45, "work result should include usable quality", failures)
	var applied: Dictionary = farm.apply_player_work_result(world, player, result)
	_expect(bool(applied.get("accepted", false)), "farm should accept player work result", failures)
	_expect(int(applied.get("harvested_amount", 0)) > 0, "applied result should harvest farm product", failures)
	_expect(farm.get_product_inventory_amount(farm.get_product_commodity()) > 0, "farm inventory should receive player harvest", failures)
	_expect(player.work_minutes_today > 0, "player work minutes should increase from FarmWorkScene result", failures)
	_expect(not farm.is_crop_ready(), "accepted harvest should reset farm crop growth", failures)
	_expect(not farm.has_player_work_session_in_progress(), "player session should be released after applying result", failures)

	farm.crop_state = Farm.CropState.GROWING
	farm.crop_growth_minutes = 0
	_expect(farm.begin_player_work_session(player), "maintenance session should start", failures)
	var maintenance := FarmWorkSceneResource.instantiate()
	maintenance.set("auto_start", false)
	_expect(bool(maintenance.call("configure_for_farm", farm, 0)), "maintenance scene should configure for growing crop", failures)
	root.add_child(maintenance)
	await process_frame
	maintenance.call("start_session")
	_expect_eq(maintenance.call("get_recommended_action_for_plot", 1), ACTION_PLANT, "empty maintenance plot should need planting", failures)
	_expect(bool((maintenance.call("debug_perform_action", 1, ACTION_PLANT) as Dictionary).get("correct", false)), "maintenance plot should plant", failures)
	_expect(bool((maintenance.call("debug_perform_action", 1, ACTION_WATER) as Dictionary).get("correct", false)), "maintenance plot should water", failures)
	var maintenance_result := maintenance.call("get_result") as Dictionary
	var growth_before := farm.crop_growth_minutes
	var maintenance_applied: Dictionary = farm.apply_player_work_result(world, player, maintenance_result)
	_expect(bool(maintenance_applied.get("accepted", false)), "maintenance result should apply", failures)
	_expect(farm.crop_growth_minutes > growth_before, "maintenance work should advance farm growth", failures)
	_expect(not farm.has_player_work_session_in_progress(), "maintenance session should release", failures)

	farm.crop_state = Farm.CropState.GROWING
	farm.crop_growth_minutes = 0
	farm.set_product_inventory_amount(farm.get_product_commodity(), 0)
	_expect(farm.begin_player_work_session(player), "live 3D session should start", failures)
	var live := FarmWorkSceneResource.instantiate()
	live.set("auto_start", false)
	_expect(bool(live.call("configure_for_farm", farm, 1)), "live 3D scene should configure for Farm", failures)
	root.add_child(live)
	await process_frame
	live.call("start_session")
	var wheat_seed_stock_before := int((live.call("debug_get_inventory_snapshot", "seeds") as Dictionary).get("wheat_seed", 0))
	_expect(bool((live.call("debug_perform_live_action", "shed", LIVE_TAKE_WHEAT_SEEDS) as Dictionary).get("correct", false)), "live flow should take wheat seeds", failures)
	var wheat_seed_stock_after := int((live.call("debug_get_inventory_snapshot", "seeds") as Dictionary).get("wheat_seed", 0))
	_expect_eq(wheat_seed_stock_after, wheat_seed_stock_before - 4, "taking seeds should reduce farm seed stock", failures)
	_expect_eq(int((live.call("debug_get_inventory_snapshot", "player") as Dictionary).get("wheat_seed", 0)), 4, "taken seeds should enter player inventory", failures)
	_expect(bool((live.call("debug_perform_live_action", "field_wheat", LIVE_SOW_FIELD) as Dictionary).get("correct", false)), "live flow should sow wheat", failures)
	_expect(bool((live.call("debug_perform_live_action", "field_wheat", LIVE_WATER_FIELD) as Dictionary).get("correct", false)), "live flow should water wheat", failures)
	live.call("debug_tick_live", 9.0)
	var wheat_field := live.call("debug_get_field_snapshot", "field_wheat") as Dictionary
	_expect_eq(str(wheat_field.get("state_label", "")), "mature", "live wheat should mature after test time", failures)
	_expect(bool((live.call("debug_perform_live_action", "field_wheat", LIVE_HARVEST_FIELD) as Dictionary).get("correct", false)), "live flow should harvest wheat", failures)
	_expect(bool((live.call("debug_perform_live_action", "silo", LIVE_STORE_GRAIN_SILO) as Dictionary).get("correct", false)), "live flow should store wheat in silo", failures)
	_expect(bool((live.call("debug_perform_live_action", "windmill", LIVE_START_WINDMILL) as Dictionary).get("correct", false)), "live flow should start windmill", failures)
	live.call("debug_tick_live", 9.0)
	_expect(bool((live.call("debug_perform_live_action", "windmill", LIVE_COLLECT_FLOUR) as Dictionary).get("correct", false)), "live flow should collect flour sacks", failures)
	_expect(bool((live.call("debug_perform_live_action", "barn", LIVE_STORE_FLOUR_BARN) as Dictionary).get("correct", false)), "live flow should store flour sacks", failures)
	_expect(bool((live.call("debug_perform_live_action", "machine_yard", LIVE_LOAD_PICKUP) as Dictionary).get("correct", false)), "live flow should load pickup", failures)
	var pickup_inventory := live.call("debug_get_inventory_snapshot", "pickup") as Dictionary
	_expect(int(pickup_inventory.get("flour_sack", 0)) > 0, "pickup should receive flour sacks", failures)
	var live_result := live.call("get_result") as Dictionary
	_expect(int(live_result.get("harvested_amount", 0)) > 0, "live result should include harvested wheat", failures)
	_expect(int(live_result.get("goods_delivered", 0)) > 0, "live result should include loaded flour sacks", failures)
	var live_applied: Dictionary = farm.apply_player_work_result(world, player, live_result)
	_expect(bool(live_applied.get("accepted", false)), "live 3D result should apply", failures)
	_expect(int(live_applied.get("harvested_amount", 0)) > 0, "live 3D result should store output on Farm", failures)
	_expect(not farm.has_player_work_session_in_progress(), "live 3D session should release", failures)

	var interaction = SimulationInteractionControllerScript.new()
	interaction.setup(root, world)
	_expect(bool(interaction.call("_try_start_farm_work_scene", player, farm)), "controller should start FarmWorkScene", failures)
	await process_frame
	var mounted_scene := interaction.get("_farm_work_scene") as Node
	var mounted_viewport := mounted_scene.get_viewport() if mounted_scene != null else null
	_expect(mounted_viewport is SubViewport, "controller should mount FarmWorkScene in an isolated SubViewport", failures)
	_expect(mounted_scene != null and mounted_scene.get_parent() == mounted_viewport, "FarmWorkScene should be a child of the work viewport", failures)
	if mounted_viewport is SubViewport:
		_expect((mounted_viewport as SubViewport).world_3d != root.get_world_3d(), "FarmWorkScene viewport should not share the city World3D", failures)
	var mounted_player := mounted_scene.get_node_or_null("WindmillFarm3D/Player") as CharacterBody3D if mounted_scene != null else null
	_expect(mounted_player != null, "mounted FarmWorkScene should create its player", failures)
	if mounted_player != null:
		for frame in range(30):
			await physics_frame
		_expect(mounted_player.global_position.y > -0.5, "FarmWorkScene player should remain above the farm ground", failures)
		_expect(mounted_player.is_on_floor(), "FarmWorkScene player should settle on the farm ground", failures)
	if mounted_scene != null and mounted_scene.has_method("finish_session"):
		mounted_scene.call("finish_session")
	await process_frame

	var owner := CitizenScene.instantiate() as Citizen
	root.add_child(owner)
	await process_frame
	owner.citizen_name = "Farm Owner"
	owner.needs.hunger = 0.0
	owner.needs.energy = 100.0
	owner.needs.health = 100.0
	farm.citizen_owner = owner
	farm.owner_display_name = owner.citizen_name
	farm.crop_state = Farm.CropState.READY
	farm.crop_growth_minutes = farm.get_crop_growth_total_minutes()
	_expect(owner.job == null, "owner work fixture should not have an employment contract", failures)
	_expect(farm.can_actor_perform_work(owner), "Farm owner should be allowed to work without a job", failures)
	_expect(farm.begin_player_work_session(owner), "Farm owner work session should start", failures)
	var owner_context := farm.get_player_work_context(world, owner)
	_expect_eq(str(owner_context.get("actor_role", "")), "owner", "Farm work context should expose owner role", failures)
	var restaurant := Restaurant.new()
	restaurant.name = "Demand Restaurant"
	root.add_child(restaurant)
	await process_frame
	world.register_building(restaurant)
	restaurant.inventory["meal"] = 0
	restaurant.account.balance = 1000
	var worker_demand := farm.get_delivery_demand_snapshot(world, player)
	var owner_demand := farm.get_delivery_demand_snapshot(world, owner)
	_expect(_demand_contains_target(worker_demand, restaurant.get_display_name()), "Farm worker should see Restaurant demand", failures)
	_expect(not _demand_has_finance(worker_demand), "Farm worker demand must hide revenue data", failures)
	_expect(_demand_has_finance(owner_demand), "Farm owner demand should include revenue data", failures)
	var worker_sections := farm.get_info_sections_for_viewer(world, player)
	var owner_sections := farm.get_info_sections_for_viewer(world, owner)
	_expect_eq(owner_sections.size(), worker_sections.size() + 1, "Farm owner details should add the finance section", failures)
	var owner_applied := farm.apply_player_work_result(world, owner, {
		"harvested_amount": 1,
		"quality_score": 0.9,
		"work_minutes": 30,
		"growth_minutes_added": 0,
		"delivered_crates": 0,
	})
	_expect(bool(owner_applied.get("accepted", false)), "Farm should accept owner self-work result", failures)
	_expect_eq(owner.work_minutes_today, 0, "Owner self-work must not create wage minutes", failures)
	_expect(farm.owner_work_minutes_today >= 30, "Farm should track unpaid owner work minutes", failures)

	game.queue_free()
	maintenance.queue_free()
	live.queue_free()
	restaurant.queue_free()
	owner.queue_free()
	player.queue_free()
	farm.queue_free()
	world.queue_free()

	if failures.is_empty():
		print("FARM_WORK_SCENE_TEST OK")
		quit(0)
		return
	print("FARM_WORK_SCENE_TEST FAILED:")
	for failure in failures:
		print("  - %s" % failure)
	quit(1)


func _make_farm_job(farm: Farm, title: String) -> Job:
	var job := Job.new()
	job.title = title
	job.workplace = farm
	job.preferred_workplace = farm
	job.wage_per_hour = 12
	job.start_hour = 6
	job.shift_hours = 8
	return job


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)


func _expect_eq(actual, expected, message: String, failures: Array[String]) -> void:
	if actual != expected:
		failures.append("%s (expected %s, got %s)" % [message, str(expected), str(actual)])


func _demand_contains_target(entries: Array, target_name: String) -> bool:
	for entry_var in entries:
		var entry := entry_var as Dictionary
		if str(entry.get("target_name", "")) == target_name:
			return true
	return false


func _demand_has_finance(entries: Array) -> bool:
	for entry_var in entries:
		var entry := entry_var as Dictionary
		if entry.has("expected_revenue") or entry.has("unit_price"):
			return true
	return false
