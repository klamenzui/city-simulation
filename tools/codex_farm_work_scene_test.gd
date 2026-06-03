extends SceneTree

const FarmWorkSceneResource = preload("res://Scenes/WorkScenes/Farm/FarmWorkScene.tscn")
const CitizenScene = preload("res://Entities/Citizens/CitizenNew.tscn")

const ACTION_PLANT := "plant"
const ACTION_WATER := "water"
const ACTION_WEED := "weed"
const ACTION_HARVEST := "harvest"
const ACTION_DELIVER := "deliver"


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

	game.queue_free()
	maintenance.queue_free()
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
