extends SceneTree

# Headless smoke test for the save / load roundtrip. Loads Main.tscn, lets the
# bootstrap settle for a handful of frames, saves to slot 1, mutates a citizen,
# applies the payload back, and confirms the mutated state was restored.
#
# Run via: run_tests.ps1 -Only @("save_roundtrip")  (or directly from a shell).

const SaveGameServiceScript = preload("res://Simulation/Persistence/SaveGameService.gd")
const NetworkEntityRegistryScript = preload("res://Simulation/Multiplayer/shared/NetworkEntityRegistry.gd")

const SETTLE_FRAMES := 6

var _failed := false

func _initialize() -> void:
	_run()

func _run() -> void:
	var scene_resource: PackedScene = load("res://Main.tscn")
	if scene_resource == null:
		_fail("Main.tscn could not be loaded.")
		_finish()
		return
	var root := scene_resource.instantiate()
	get_root().add_child(root)

	for _i in range(SETTLE_FRAMES):
		await process_frame

	var world: World = root.get_node_or_null("World") as World
	if world == null:
		_fail("World node missing on Main.tscn root.")
		_finish()
		return

	var player := root.get_node_or_null("ControlledCitizen") as Node3D
	if player == null:
		_fail("ControlledCitizen missing on Main.tscn root.")
		_finish()
		return
	if not (player is Citizen):
		_fail("ControlledCitizen is not a Citizen.")
		_finish()
		return

	var citizen := player as Citizen
	var expected_home := _ensure_test_home(world, citizen)
	if expected_home == null:
		_fail("No residential building available for save/load relationship test.")
		_finish()
		return
	var expected_workplace := _find_test_workplace(world)
	if expected_workplace == null:
		_fail("No workplace with a free job slot available for save/load relationship test.")
		_finish()
		return
	var expected_job := _install_test_job(world, citizen, expected_workplace)
	if expected_job == null:
		_fail("Could not install deterministic test job.")
		_finish()
		return
	citizen.work_minutes_today = 90
	citizen.job_tenure_days = 8
	citizen.job_absence_days = 2
	citizen.experience_wage_bonus = 0.075
	citizen.personal_speed_multiplier = 0.93
	expected_workplace.profit_average = 325.0
	expected_workplace._profit_average_seeded = true
	var owner_citizen := _find_non_player_citizen(world, citizen)
	if owner_citizen == null:
		_fail("No non-player citizen available for ownership restore test.")
		_finish()
		return
	var owned_building := _find_ownable_building(world)
	if owned_building == null:
		_fail("No ownable building available for ownership restore test.")
		_finish()
		return
	owned_building.citizen_owner = owner_citizen
	owned_building.owner_display_name = owner_citizen.citizen_name
	if owned_building is CommercialBuilding:
		var commercial := owned_building as CommercialBuilding
		commercial.inventory["save_roundtrip_item"] = 3
		commercial.base_prices["save_roundtrip_item"] = 17

	var save_err := SaveGameServiceScript.save_to_slot(1, world, root, player)
	if save_err != OK:
		_fail("save_to_slot returned %d" % save_err)
		_finish()
		return

	var payload := SaveGameServiceScript.read_payload(1)
	if payload.is_empty():
		_fail("read_payload returned empty dictionary after save.")
		_finish()
		return
	var saved_citizen_count := int(payload.get("citizen_count", world.citizens.size()))
	var owner_entity_id := NetworkEntityRegistryScript.get_entity_id(owner_citizen)
	var owner_name := owner_citizen.citizen_name
	if owner_entity_id.is_empty():
		_fail("test owner did not receive a network entity id.")
		_finish()
		return

	var original_hunger: float = citizen.needs.hunger if citizen.needs != null else 0.0
	var original_balance: int = citizen.wallet.balance if citizen.wallet != null else 0
	if citizen.needs != null:
		citizen.needs.hunger = clampf(original_hunger - 25.0, 0.0, 100.0)
	if citizen.wallet != null:
		citizen.wallet.balance = original_balance + 5000
	expected_home.remove_tenant(citizen)
	var old_job := citizen.job
	expected_workplace.fire(citizen)
	if old_job != null:
		world.unregister_job(old_job)
	citizen.home = null
	citizen.job = null
	citizen.current_location = null
	citizen.work_minutes_today = 0
	citizen.job_tenure_days = 0
	citizen.job_absence_days = 0
	citizen.experience_wage_bonus = 0.0
	citizen.personal_speed_multiplier = 1.2
	expected_workplace.profit_average = -999.0
	expected_workplace._profit_average_seeded = false
	owned_building.citizen_owner = null
	owned_building.owner_display_name = ""
	if owned_building is CommercialBuilding:
		var commercial := owned_building as CommercialBuilding
		commercial.inventory["save_roundtrip_item"] = 99
		commercial.inventory["stale_after_save"] = 12
		commercial.base_prices["save_roundtrip_item"] = 99
		commercial.base_prices["stale_after_save"] = 44
	if not _remove_citizen_for_restore_test(world, owner_citizen):
		_fail("Could not remove the owner citizen for ownership restore test.")
		_finish()
		return

	var apply_err := SaveGameServiceScript.apply_payload(payload, world, root, player)
	if apply_err != OK:
		_fail("apply_payload returned %d" % apply_err)
		_finish()
		return

	if citizen.needs != null and not is_equal_approx(citizen.needs.hunger, original_hunger):
		_fail("hunger not restored: expected %.2f got %.2f" % [original_hunger, citizen.needs.hunger])
	if citizen.wallet != null and citizen.wallet.balance != original_balance:
		_fail("wallet not restored: expected %d got %d" % [original_balance, citizen.wallet.balance])
	if world.citizens.size() != saved_citizen_count:
		_fail("citizen count not restored: expected %d got %d" % [saved_citizen_count, world.citizens.size()])
	if citizen.home != expected_home or not expected_home.tenants.has(citizen):
		_fail("home/tenant relationship not restored.")
	if citizen.job == null:
		_fail("job not restored.")
	elif citizen.job.workplace != expected_workplace:
		_fail("job workplace not restored.")
	elif not world.jobs.has(citizen.job):
		_fail("restored job not registered in World.")
	elif not expected_workplace.workers.has(citizen):
		_fail("worker relationship not restored.")
	elif citizen.job.title != expected_job.title:
		_fail("job title not restored: expected %s got %s" % [expected_job.title, citizen.job.title])
	if citizen.work_minutes_today != 90:
		_fail("work minutes not restored: expected 90 got %d" % citizen.work_minutes_today)
	if citizen.job_tenure_days != 8:
		_fail("job tenure not restored: expected 8 got %d" % citizen.job_tenure_days)
	if citizen.job_absence_days != 2:
		_fail("job absence days not restored: expected 2 got %d" % citizen.job_absence_days)
	if not is_equal_approx(citizen.experience_wage_bonus, 0.075):
		_fail("experience bonus not restored: expected 0.075 got %.4f" % citizen.experience_wage_bonus)
	if not is_equal_approx(citizen.personal_speed_multiplier, 0.93):
		_fail("personal speed multiplier not restored: expected 0.93 got %.4f" % citizen.personal_speed_multiplier)
	if not is_equal_approx(expected_workplace.profit_average, 325.0):
		_fail("building profit average not restored: expected 325 got %.2f" % expected_workplace.profit_average)
	if not expected_workplace._profit_average_seeded:
		_fail("building profit average seeded flag not restored.")
	var restored_owner := owned_building.get_owner_citizen()
	if restored_owner == null:
		_fail("building citizen owner not restored.")
	elif NetworkEntityRegistryScript.get_entity_id(restored_owner) != owner_entity_id:
		_fail("building owner restored to wrong citizen: expected %s got %s" % [
			owner_entity_id,
			NetworkEntityRegistryScript.get_entity_id(restored_owner)
		])
	elif owned_building.owner_display_name != owner_name:
		_fail("building owner display name not restored: expected %s got %s" % [
			owner_name,
			owned_building.owner_display_name
		])
	if owned_building is CommercialBuilding:
		var restored_commercial := owned_building as CommercialBuilding
		if int(restored_commercial.inventory.get("save_roundtrip_item", 0)) != 3:
			_fail("commercial inventory not restored from snapshot.")
		elif restored_commercial.inventory.has("stale_after_save"):
			_fail("commercial inventory kept stale keys after snapshot apply.")
		elif int(restored_commercial.base_prices.get("save_roundtrip_item", 0)) != 17:
			_fail("commercial base price not restored from snapshot.")
		elif restored_commercial.base_prices.has("stale_after_save"):
			_fail("commercial base prices kept stale keys after snapshot apply.")

	# clean up the slot we just wrote so the test does not leave artefacts.
	var path := SaveGameServiceScript.slot_path(1)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

	_finish()

func _fail(msg: String) -> void:
	push_error("save_roundtrip FAIL: %s" % msg)
	print("save_roundtrip FAIL: %s" % msg)
	_failed = true

func _ensure_test_home(world: World, citizen: Citizen) -> ResidentialBuilding:
	if citizen.home != null:
		if not citizen.home.tenants.has(citizen):
			citizen.home.add_tenant(citizen)
		return citizen.home
	for building in world.buildings:
		if building is ResidentialBuilding:
			var residential := building as ResidentialBuilding
			if residential.tenants.has(citizen) or residential.has_free_slot():
				if residential.add_tenant(citizen):
					citizen.home = residential
					return residential
	return null

func _find_test_workplace(world: World) -> Building:
	for building in world.buildings:
		if building == null or not is_instance_valid(building):
			continue
		if int(building.job_capacity) <= 0:
			continue
		if building.has_free_job_slots():
			return building
	return null

func _install_test_job(world: World, citizen: Citizen, workplace: Building) -> Job:
	if world == null or citizen == null or workplace == null:
		return null
	if citizen.job != null:
		var old_job := citizen.job
		if old_job.workplace != null:
			old_job.workplace.fire(citizen)
		world.unregister_job(old_job)
	var job := Job.new()
	job.title = "Savegame Tester"
	job.wage_per_hour = 17
	job.shift_hours = 8
	job.required_education_level = 0
	job.workplace = workplace
	job.preferred_workplace = workplace
	job.workplace_service_type = workplace.get_service_type()
	job.allowed_building_types = [int(workplace.building_type)]
	citizen.job = job
	world.register_job(job)
	if not workplace.try_hire(citizen):
		world.unregister_job(job)
		citizen.job = null
		return null
	return job

func _find_non_player_citizen(world: World, player: Citizen) -> Citizen:
	for candidate in world.citizens:
		if candidate == null or candidate == player or not is_instance_valid(candidate):
			continue
		return candidate
	return null

func _find_ownable_building(world: World) -> Building:
	for building in world.buildings:
		if building == null or not is_instance_valid(building):
			continue
		if building.is_citizen_ownable():
			return building
	return null

func _remove_citizen_for_restore_test(world: World, citizen: Citizen) -> bool:
	if citizen == null or world == null or not world.citizens.has(citizen):
		return false
	world.unregister_citizen(citizen)
	citizen.queue_free()
	return true

func _finish() -> void:
	if _failed:
		print("save_roundtrip: FAILED")
		quit(1)
	else:
		print("save_roundtrip: OK")
		quit(0)
