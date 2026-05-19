extends SceneTree

const BuildingScript = preload("res://Entities/Buildings/Building.gd")
const ParkScript = preload("res://Entities/Buildings/Park.gd")
const RestaurantScript = preload("res://Entities/Buildings/Restaurant.gd")
const ResidentialBuildingScript = preload("res://Entities/Buildings/ResidentialBuilding.gd")
const UniversityScript = preload("res://Entities/Buildings/University.gd")
const CitizenScript = preload("res://Entities/Citizens/New/Citizen.gd")
const WorldScript = preload("res://Simulation/World.gd")
const CitizenFactoryScript = preload("res://Simulation/Factories/CitizenFactory.gd")
const ActionScript = preload("res://Actions/Action.gd")
const StudyAtUniversityActionScript = preload("res://Actions/StudyAtUniversityAction.gd")
const GoToBuildingActionScript = preload("res://Actions/GoToBuildingAction.gd")
const GoToBenchActionScript = preload("res://Actions/GoToBenchAction.gd")
const RelaxAtParkActionScript = preload("res://Actions/RelaxAtParkAction.gd")
const RelaxAtBenchActionScript = preload("res://Actions/RelaxAtBenchAction.gd")
const SimulationInteractionControllerScript = preload("res://Simulation/UI/SimulationInteractionController.gd")

class MockSelectionStateController:
	extends RefCounted

	var player_avatar: Citizen = null
	var controlled_citizen: Citizen = null
	var camera_player_target: Citizen = null
	var player_control_active: bool = false

	func get_player_avatar() -> Citizen:
		return player_avatar if player_avatar != null and is_instance_valid(player_avatar) else null

	func get_controlled_citizen() -> Citizen:
		return controlled_citizen if controlled_citizen != null and is_instance_valid(controlled_citizen) else null

	func get_camera_player_target() -> Citizen:
		return camera_player_target if camera_player_target != null and is_instance_valid(camera_player_target) else null

	func is_player_control_active() -> bool:
		return player_control_active

var _checks_run: int = 0
var _current_error: String = ""
var _harness_root: Node3D

func _initialize() -> void:
	_harness_root = Node3D.new()
	get_root().add_child(_harness_root)
	call_deferred("_run_all_tests")

func _run_all_tests() -> void:
	var failed: Array[String] = []
	for test_name in [
		"building_entry_updates_visitors",
		"player_enter_takes_capacity_slot",
		"offline_keyboard_player_building_input_uses_camera_target",
		"keyboard_player_needs_tick_without_goap",
		"university_requires_worker_for_study",
		"university_accepts_education_service_staff",
		"university_unstaffed_label_is_teaching_specific",
		"park_entry_keeps_citizen_visible",
		"park_reserved_bench_sets_visit_point",
		"park_arrival_keeps_bench_reserved_without_auto_rest",
		"go_to_park_finish_chains_relax_for_visitors",
		"go_to_park_social_visit_suppresses_auto_rest",
		"go_to_park_finish_uses_015_entrance_tolerance",
		"go_to_bench_arrival_keeps_reservation_without_auto_rest",
		"relax_park_uses_bench_bonus",
		"relax_park_finish_releases_bench_after_location_change",
		"relax_park_without_bench_stays_fun_only",
		"agent_clears_stale_outdoor_rest_pose",
		"agent_finishes_relax_park_without_stale_rest_trace",
		"manual_control_releases_city_bench_reservation",
		"world_city_bench_excludes_park_benches",
		"world_city_bench_cache_refreshes_on_scene_change",
		"world_auto_registers_runtime_park_queries",
		"world_unregisters_removed_park_from_queries",
		"world_registers_scene_park_cluster_once",
		"citizen_factory_spawns_at_home_entrance",
		"job_offer_prefers_training_and_reserves_slot",
		"study_finish_hires_reserved_trainee",
		"citizen_death_cleanup_unregisters_and_queues_refill",
		"population_refill_spawns_after_delay",
		"citizen_crowd_push_separates_close_neighbors",
		"citizen_auto_resolves_world_for_queries",
		"hungry_citizen_uses_nearest_food_target",
		"action_default_needs_modifier_is_isolated",
		"relax_bench_uses_energy_bonus",
		"worker_count_lifecycle",
	]:
		var error := _run_test(test_name)
		if error != "":
			failed.append("%s: %s" % [test_name, error])

	if is_instance_valid(_harness_root):
		_harness_root.free()

	if failed.is_empty():
		print("OCCUPANCY_TEST OK checks=%d" % _checks_run)
		quit(0)
		return

	for failure in failed:
		push_error(failure)
	print("OCCUPANCY_TEST FAIL count=%d" % failed.size())
	quit(1)

func _run_test(test_name: String) -> String:
	_current_error = ""
	_reset_harness_root()
	match test_name:
		"building_entry_updates_visitors":
			return _test_building_entry_updates_visitors()
		"player_enter_takes_capacity_slot":
			return _test_player_enter_takes_capacity_slot()
		"offline_keyboard_player_building_input_uses_camera_target":
			return _test_offline_keyboard_player_building_input_uses_camera_target()
		"keyboard_player_needs_tick_without_goap":
			return _test_keyboard_player_needs_tick_without_goap()
		"university_requires_worker_for_study":
			return _test_university_requires_worker_for_study()
		"university_accepts_education_service_staff":
			return _test_university_accepts_education_service_staff()
		"university_unstaffed_label_is_teaching_specific":
			return _test_university_unstaffed_label_is_teaching_specific()
		"park_entry_keeps_citizen_visible":
			return _test_park_entry_keeps_citizen_visible()
		"park_reserved_bench_sets_visit_point":
			return _test_park_reserved_bench_sets_visit_point()
		"park_arrival_keeps_bench_reserved_without_auto_rest":
			return _test_park_arrival_keeps_bench_reserved_without_auto_rest()
		"go_to_park_finish_chains_relax_for_visitors":
			return _test_go_to_park_finish_chains_relax_for_visitors()
		"go_to_park_social_visit_suppresses_auto_rest":
			return _test_go_to_park_social_visit_suppresses_auto_rest()
		"go_to_park_finish_uses_015_entrance_tolerance":
			return _test_go_to_park_finish_uses_015_entrance_tolerance()
		"go_to_bench_arrival_keeps_reservation_without_auto_rest":
			return _test_go_to_bench_arrival_keeps_reservation_without_auto_rest()
		"relax_park_uses_bench_bonus":
			return _test_relax_park_uses_bench_bonus()
		"relax_park_finish_releases_bench_after_location_change":
			return _test_relax_park_finish_releases_bench_after_location_change()
		"relax_park_without_bench_stays_fun_only":
			return _test_relax_park_without_bench_stays_fun_only()
		"agent_clears_stale_outdoor_rest_pose":
			return _test_agent_clears_stale_outdoor_rest_pose()
		"agent_finishes_relax_park_without_stale_rest_trace":
			return _test_agent_finishes_relax_park_without_stale_rest_trace()
		"manual_control_releases_city_bench_reservation":
			return _test_manual_control_releases_city_bench_reservation()
		"world_city_bench_excludes_park_benches":
			return _test_world_city_bench_excludes_park_benches()
		"world_city_bench_cache_refreshes_on_scene_change":
			return _test_world_city_bench_cache_refreshes_on_scene_change()
		"world_auto_registers_runtime_park_queries":
			return _test_world_auto_registers_runtime_park_queries()
		"world_unregisters_removed_park_from_queries":
			return _test_world_unregisters_removed_park_from_queries()
		"world_registers_scene_park_cluster_once":
			return _test_world_registers_scene_park_cluster_once()
		"citizen_factory_spawns_at_home_entrance":
			return _test_citizen_factory_spawns_at_home_entrance()
		"job_offer_prefers_training_and_reserves_slot":
			return _test_job_offer_prefers_training_and_reserves_slot()
		"study_finish_hires_reserved_trainee":
			return _test_study_finish_hires_reserved_trainee()
		"citizen_death_cleanup_unregisters_and_queues_refill":
			return _test_citizen_death_cleanup_unregisters_and_queues_refill()
		"population_refill_spawns_after_delay":
			return _test_population_refill_spawns_after_delay()
		"citizen_crowd_push_separates_close_neighbors":
			return _test_citizen_crowd_push_separates_close_neighbors()
		"citizen_auto_resolves_world_for_queries":
			return _test_citizen_auto_resolves_world_for_queries()
		"hungry_citizen_uses_nearest_food_target":
			return _test_hungry_citizen_uses_nearest_food_target()
		"action_default_needs_modifier_is_isolated":
			return _test_action_default_needs_modifier_is_isolated()
		"relax_bench_uses_energy_bonus":
			return _test_relax_bench_uses_energy_bonus()
		"worker_count_lifecycle":
			return _test_worker_count_lifecycle()
		_:
			return "unknown test"

func _test_building_entry_updates_visitors() -> String:
	var university: University = _new_university("Entry Uni")
	var citizen: Citizen = _new_citizen("Visitor One")

	_expect_eq(university.visitors.size(), 0, "university should start with no visitors")
	citizen.enter_building(university, null, false)
	_expect(citizen.current_location == university, "citizen current_location should point to entered building")
	_expect_eq(university.visitors.size(), 1, "building entry should register a visitor immediately")
	_expect(university.visitors.has(citizen), "entered citizen should be listed as visitor")
	var info := university.get_info(null)
	_expect_eq(info.get("Visitors", ""), "1 / %d" % max(university.capacity, 0), "building info should reflect live visitor count")

	citizen.exit_current_building(null)
	_expect_eq(university.visitors.size(), 0, "leaving the building should remove the visitor")
	return _current_error

func _test_university_requires_worker_for_study() -> String:
	var university: University = _new_university("Study Uni")
	var citizen: Citizen = _new_citizen("Student One")
	var teacher: Citizen = _new_citizen("Teacher One")
	var world: World = _new_world()
	var wallet_before: int = citizen.wallet.balance
	teacher.job = Job.new()
	teacher.job.title = "Teacher"
	teacher.job.workplace = university

	_expect(not university.is_open(world.time.get_hour()), "university should be unavailable without at least one worker")
	_expect(not university.can_study(citizen), "student should not be able to study when no worker is present")

	citizen.enter_building(university, null, false)
	_expect_eq(university.visitors.size(), 1, "entering the university should count as one visitor before study starts")

	var action: StudyAtUniversityAction = StudyAtUniversityActionScript.new(university, 90)
	action.start(world, citizen)
	_expect(action.finished, "study action should stop immediately when the university has no worker")
	_expect_eq(university.account.balance, 0, "university should not receive income while it has no worker")
	_expect_eq(citizen.education_level, 0, "study should not progress while university is unstaffed")

	_expect(university.try_hire(teacher), "university should accept its first worker")
	_expect(university.is_open(world.time.get_hour()), "university should open once at least one worker is hired")
	_expect(university.can_study(citizen), "student should be allowed to study once the university is staffed")

	action = StudyAtUniversityActionScript.new(university, 90)
	action.start(world, citizen)
	_expect_eq(university.visitors.size(), 1, "study start should not double-count an already entered visitor")
	_expect_eq(citizen.education_level, 1, "study start should grant education progress")
	_expect_eq(university.account.balance, 0, "university should not charge tuition in the public funding model")
	_expect_eq(citizen.wallet.balance, wallet_before, "public university study should not change the student wallet")

	action.finish(world, citizen)
	_expect_eq(university.visitors.size(), 0, "study finish should clear the university visitor again")

	_free_world(world)
	return _current_error

func _test_university_accepts_education_service_staff() -> String:
	var university: University = _new_university("Service Uni")
	var lecturer: Citizen = _new_citizen("Lecturer One")
	lecturer.job = Job.new()
	lecturer.job.title = " visiting lecturer "
	lecturer.job.workplace = university
	lecturer.job.workplace_service_type = "education"

	_expect(university.try_hire(lecturer), "university should hire an education-service worker")
	_expect(university.has_teaching_staff(), "education-service staff should satisfy teaching requirement")
	_expect_eq(university.get_teaching_staff().size(), 1, "teaching staff count should include the education-service worker")
	_expect_eq(university.get_open_status_label(10), "OPEN", "university should open with education-service teaching staff")
	return _current_error

func _test_worker_count_lifecycle() -> String:
	var building: Building = _new_building("Workshop", 2)
	var worker_a: Citizen = _new_citizen("Worker A")
	var worker_b: Citizen = _new_citizen("Worker B")

	_expect(building.try_hire(worker_a), "first worker should be hired")
	_expect(building.try_hire(worker_a), "rehiring same worker should stay idempotent")
	_expect_eq(building.workers.size(), 1, "same worker should not be counted twice")
	_expect(building.try_hire(worker_b), "second worker should be hired while capacity remains")
	_expect_eq(building.workers.size(), 2, "worker array should reflect filled slots")
	building.fire(worker_a)
	_expect_eq(building.workers.size(), 1, "fire should reduce worker count")
	var info := building.get_info(null)
	_expect_eq(info.get("Workers", ""), "1 / 2", "building info should reflect live worker count")
	return _current_error

func _test_university_unstaffed_label_is_teaching_specific() -> String:
	var university: University = _new_university("Teaching Uni")
	var janitor: Citizen = _new_citizen("Janitor Worker")
	janitor.job = Job.new()
	janitor.job.title = "Janitor"
	janitor.job.workplace = university

	_expect(university.try_hire(janitor), "university should be able to hire non-teaching staff")
	_expect_eq(university.workers.size(), 1, "worker count should include non-teaching staff")
	_expect_eq(university.get_open_status_label(10), "UNSTAFFED", "university should remain unstaffed for teaching without teachers")
	_expect_eq(university.get_open_status_display_label(10), "Geschlossen: keine Lehrkraft", "status label should explain the missing teaching role")
	return _current_error

func _test_park_entry_keeps_citizen_visible() -> String:
	var park: Park = _new_park("Central Park")
	var citizen: Citizen = _new_citizen("Park Visitor")

	citizen.enter_building(park, null, false)
	_expect(citizen.current_location == park, "citizen current_location should point to the park")
	_expect(not citizen.is_inside_building(), "park should not mark the citizen as hidden indoors")
	_expect(citizen.visible, "citizen should stay visible inside the park")
	_expect_eq(park.visitors.size(), 1, "park should register one visitor")

	citizen.leave_current_location(null, false)
	_expect(citizen.current_location == null, "leaving the park should clear current location")
	_expect_eq(park.visitors.size(), 0, "park visitor should be removed after leaving")
	return _current_error

func _test_park_reserved_bench_sets_visit_point() -> String:
	var park: Park = _new_park("Bench Park")
	var citizen: Citizen = _new_citizen("Bench Walker")
	var bench := _add_bench(park, "Bench_A", Vector3(2.5, 0.0, -0.5), 0.9)

	var reservation := park.reserve_bench_for(citizen, citizen.global_position)
	var nav_points := citizen.get_navigation_points_for_building(park, null)

	_expect(not reservation.is_empty(), "park should reserve a bench for the citizen")
	_expect(nav_points.has("visit"), "park navigation should expose a visit target")
	_expect_eq(nav_points.get("visit"), bench.global_position, "reserved bench position should become the visit target")
	_expect(is_equal_approx(float(nav_points.get("bench_yaw", 0.0)), bench.global_rotation.y), "bench yaw should be forwarded for the rest pose")
	return _current_error

func _test_park_arrival_keeps_bench_reserved_without_auto_rest() -> String:
	var world: World = _new_world()
	var park: Park = _new_park("Arrival Park")
	var visitor: Citizen = _new_citizen("Park Visitor")
	var worker: Citizen = _new_citizen("Park Worker")
	var bench := _add_bench(park, "Bench_A", Vector3(1.8, 0.0, 0.4), 0.7)

	visitor.set_world_ref(world)
	var visitor_reservation := park.reserve_bench_for(visitor, visitor.global_position)
	visitor.current_action = GoToBuildingActionScript.new(park, 10)
	visitor.enter_building(park, world, false)
	_expect(not visitor.has_active_rest_pose(), "park arrival should wait for RelaxPark before locking a visitor into the bench rest pose")
	_expect_eq(visitor_reservation.get("node"), bench, "park should reserve the expected bench for the visitor")
	_expect_eq(park.get_reserved_bench_for(visitor).get("node"), bench, "park arrival should keep the reserved bench locked until RelaxPark starts")

	worker.job = Job.new()
	worker.job.workplace = park
	worker.set_world_ref(world)
	worker.current_action = GoToBuildingActionScript.new(park, 10)
	worker.enter_building(park, world, false)
	_expect(not worker.has_active_rest_pose(), "park workers should not auto-occupy visitor benches on arrival")
	_expect(park.get_reserved_bench_for(worker).is_empty(), "park workers should not keep a visitor bench reservation on arrival")

	_free_world(world)
	return _current_error

func _test_go_to_park_finish_chains_relax_for_visitors() -> String:
	var world: World = _new_world()
	var park: Park = _new_park("Chain Park")
	var visitor: Citizen = _new_citizen("Chain Visitor")
	var worker: Citizen = _new_citizen("Chain Worker")
	_add_bench(park, "Bench_A", Vector3(1.5, 0.0, 0.5), 0.4)

	visitor.set_world_ref(world)
	var visitor_action: GoToBuildingAction = GoToBuildingActionScript.new(park, 10)
	visitor.current_action = visitor_action
	visitor_action._arrival_target = visitor.get_navigation_points_for_building(park, world).get("access", park.global_position)
	visitor.set_position_grounded(visitor_action._arrival_target)
	visitor._travel_target = visitor_action._arrival_target
	visitor.stop_travel()
	visitor_action.finish(world, visitor)
	_expect(visitor.current_action is RelaxAtParkAction, "park arrival should immediately chain into RelaxPark for normal visitors")

	worker.job = Job.new()
	worker.job.workplace = park
	worker.set_world_ref(world)
	var worker_action: GoToBuildingAction = GoToBuildingActionScript.new(park, 10)
	worker.current_action = worker_action
	worker_action._arrival_target = worker.get_navigation_points_for_building(park, world).get("access", park.global_position)
	worker.set_position_grounded(worker_action._arrival_target)
	worker._travel_target = worker_action._arrival_target
	worker.stop_travel()
	worker_action.finish(world, worker)
	_expect(not (worker.current_action is RelaxAtParkAction), "park workers should enter the park without auto-starting RelaxPark")

	_free_world(world)
	return _current_error

func _test_go_to_park_social_visit_suppresses_auto_rest() -> String:
	var world: World = _new_world()
	var park: Park = _new_park("Social Park")
	var visitor: Citizen = _new_citizen("Social Visitor")
	_add_bench(park, "Bench_A", Vector3(1.5, 0.0, 0.5), 0.4)

	visitor.set_world_ref(world)
	var social_trip: GoToBuildingAction = GoToBuildingActionScript.new(park, 10, false)
	visitor.current_action = social_trip
	social_trip._arrival_target = visitor.get_navigation_points_for_building(park, world).get("access", park.global_position)
	visitor.set_position_grounded(social_trip._arrival_target)
	visitor._travel_target = social_trip._arrival_target
	visitor.stop_travel()

	social_trip.finish(world, visitor)

	_expect(visitor.current_location == park, "social park trip should still enter the park")
	_expect(not (visitor.current_action is RelaxAtParkAction), "social park trip must not auto-chain into RelaxPark")
	_expect(not visitor.has_active_rest_pose(), "social park trip should not lock a bench rest pose")
	_expect_eq(visitor.decision_cooldown_left, 0, "social park trip should allow immediate Socialize replanning")

	_free_world(world)
	return _current_error

func _test_go_to_park_finish_uses_015_entrance_tolerance() -> String:
	var world: World = _new_world()
	var park: Park = _new_park("Tolerance Park")
	var within: Citizen = _new_citizen("Tolerance Within")
	var outside: Citizen = _new_citizen("Tolerance Outside")
	_add_bench(park, "Bench_A", Vector3(1.5, 0.0, 0.5), 0.4)

	within.set_world_ref(world)
	var within_action: GoToBuildingAction = GoToBuildingActionScript.new(park, 10)
	within.current_action = within_action
	within_action._arrival_target = within.get_navigation_points_for_building(park, world).get("access", park.global_position)
	within.set_position_grounded(within_action._arrival_target + Vector3(0.14, 0.0, 0.0))
	within._travel_target = within_action._arrival_target
	within.stop_travel()
	within_action.finish(world, within)
	_expect(within.current_action is RelaxAtParkAction, "park arrival should accept up to 0.15m entrance deviation")

	outside.set_world_ref(world)
	var outside_action: GoToBuildingAction = GoToBuildingActionScript.new(park, 10)
	outside.current_action = outside_action
	outside_action._arrival_target = outside.get_navigation_points_for_building(park, world).get("access", park.global_position)
	outside.set_position_grounded(outside_action._arrival_target + Vector3(0.16, 0.0, 0.0))
	outside._travel_target = outside_action._arrival_target
	outside.stop_travel()
	outside_action.finish(world, outside)
	_expect(not (outside.current_action is RelaxAtParkAction), "park arrival should not accept more than 0.15m entrance deviation")
	_expect(outside.current_location == null, "park arrival outside the 0.15m tolerance should not enter the park yet")

	_free_world(world)
	return _current_error

func _test_go_to_bench_arrival_keeps_reservation_without_auto_rest() -> String:
	var world: World = _new_world()
	var building: Building = _new_building("Bench House")
	var citizen: Citizen = _new_citizen("Bench Walker")
	var bench := _add_bench(building, "Bench", Vector3(1.4, 0.0, -0.3), 1.05)
	world.register_building(building)
	world.register_citizen(citizen)

	var reservation := world.get_reserved_city_bench_for(citizen)
	if reservation.is_empty():
		reservation = world.reserve_city_bench_for(citizen, citizen.global_position)
	_expect(not reservation.is_empty(), "go-to-bench should reserve a city bench before travel starts")
	_expect_eq(reservation.get("node"), bench, "go-to-bench should reserve the expected city bench")
	var action = GoToBenchActionScript.new()
	citizen.global_position = reservation.get("position", citizen.global_position)
	citizen._is_travelling = false
	citizen._travel_target = reservation.get("position", citizen.global_position)
	citizen.decision_cooldown_left = citizen.decision_cooldown_range_max

	action.finish(world, citizen)
	_expect(not citizen.has_active_rest_pose(), "arriving at a city bench should wait for RelaxBench before activating the rest pose")
	_expect_eq(world.get_reserved_city_bench_for(citizen).get("node"), bench, "city bench arrival should keep the reservation for the follow-up relax action")
	_expect_eq(citizen.decision_cooldown_left, 0, "city bench arrival should allow immediate follow-up planning")

	_free_world(world)
	return _current_error

func _test_relax_park_uses_bench_bonus() -> String:
	var world: World = _new_world()
	var park: Park = _new_park("Rest Park")
	var citizen: Citizen = _new_citizen("Park Sitter")
	var bench := _add_bench(park, "Bench_Main", Vector3(1.2, 0.0, 0.8), 1.1)
	citizen.set_world_ref(world)
	citizen.enter_building(park, world, false)
	var nav_points := citizen.get_navigation_points_for_building(park, world)
	citizen.set_position_grounded(nav_points.get("access", park.global_position))
	park.reserve_bench_for(citizen, citizen.global_position)

	var action: RelaxAtParkAction = RelaxAtParkActionScript.new()
	action.start(world, citizen)

	_expect(action.is_using_bench(), "relaxing in a park with a reserved bench should use the bench flow")
	_expect(citizen.is_travelling(), "park relax should first walk from the entrance to the reserved bench")
	_expect(not citizen.has_active_rest_pose(), "bench relax should wait with the rest pose until the citizen reaches the bench")

	citizen.set_position_grounded(bench.global_position)
	citizen.stop_travel()
	action.tick(world, citizen, world.minutes_per_tick)
	var modifier := action.get_needs_modifier(world, citizen)

	_expect(citizen.has_active_rest_pose(), "bench relax should activate a rest pose after arriving at the reserved bench")
	_expect_planar_vec3_near(citizen.global_position, bench.global_position, 0.001, "citizen should rest at the reserved bench marker")
	_expect(float(modifier.get("energy_add", 0.0)) > 0.08, "bench relax should produce a net positive energy gain")
	_expect(float(modifier.get("fun_add", 0.0)) > 0.22, "bench relax should provide a small extra fun bonus")

	action.finish(world, citizen)
	_expect(not citizen.has_active_rest_pose(), "bench relax finish should clear the rest pose again")
	_expect(park.get_reserved_bench_for(citizen).is_empty(), "bench relax finish should release the reserved bench")
	_expect_eq(citizen.decision_cooldown_left, 0, "bench relax finish should allow immediate replanning")

	_free_world(world)
	return _current_error

func _test_relax_park_finish_releases_bench_after_location_change() -> String:
	var world: World = _new_world()
	var park: Park = _new_park("Moved Park")
	var citizen: Citizen = _new_citizen("Moved Visitor")
	_add_bench(park, "Bench_Main", Vector3(1.2, 0.0, 0.8), 1.1)
	citizen.set_world_ref(world)
	citizen.enter_building(park, world, false)
	var nav_points := citizen.get_navigation_points_for_building(park, world)
	citizen.set_position_grounded(nav_points.get("access", park.global_position))
	park.reserve_bench_for(citizen, citizen.global_position)

	var action: RelaxAtParkAction = RelaxAtParkActionScript.new()
	action.start(world, citizen)
	citizen.current_location = null

	action.finish(world, citizen)
	_expect(park.get_reserved_bench_for(citizen).is_empty(), "park bench reservation should still be released even if the citizen location changed before finish")

	_free_world(world)
	return _current_error

func _test_relax_park_without_bench_stays_fun_only() -> String:
	var world: World = _new_world()
	var park: Park = _new_park("Open Park")
	var citizen: Citizen = _new_citizen("Standing Visitor")
	citizen.set_world_ref(world)
	citizen.enter_building(park, world, false)
	var nav_points := citizen.get_navigation_points_for_building(park, world)
	citizen.set_position_grounded(nav_points.get("access", park.global_position))

	var action: RelaxAtParkAction = RelaxAtParkActionScript.new()
	action.start(world, citizen)
	var modifier := action.get_needs_modifier(world, citizen)

	_expect(not action.is_using_bench(), "park relax without benches should stay in non-bench mode")
	_expect(not citizen.has_active_rest_pose(), "without a bench the citizen should not be locked into a rest pose")
	_expect(is_equal_approx(float(modifier.get("energy_add", -1.0)), 0.0), "park relax without a bench should not add energy")
	_expect(float(modifier.get("fun_add", 0.0)) > 0.0, "park relax without a bench should still add fun")

	action.finish(world, citizen)
	_free_world(world)
	return _current_error

func _test_agent_clears_stale_outdoor_rest_pose() -> String:
	var world: World = _new_world()
	var park: Park = _new_park("Cleanup Park")
	var citizen: Citizen = _new_citizen("Cleanup Visitor")
	var bench := _add_bench(park, "Bench", Vector3(0.8, 0.0, 0.6), 0.5)
	citizen.set_world_ref(world)
	park.on_citizen_entered(citizen)
	citizen.current_location = park
	park.reserve_bench_for(citizen, citizen.global_position)
	citizen.set_rest_pose(bench.global_position, bench.global_rotation.y)
	citizen.current_action = null
	citizen.decision_cooldown_left = citizen.decision_cooldown_range_max

	citizen._agent.sim_tick(citizen, world)

	_expect(not citizen.has_active_rest_pose(), "agent should clear stale outdoor rest poses that are no longer owned by a relax action")
	_expect(park.get_reserved_bench_for(citizen).is_empty(), "clearing a stale outdoor rest pose should also release the reserved park bench")

	_free_world(world)
	return _current_error

func _test_agent_finishes_relax_park_without_stale_rest_trace() -> String:
	var world: World = _new_world()
	var park: Park = _new_park("Finish Park")
	var citizen: Citizen = _new_citizen("Trace Visitor")
	_add_bench(park, "Bench", Vector3(0.8, 0.0, 0.6), 0.5)
	citizen.set_world_ref(world)
	citizen.enter_building(park, world, false)
	var nav_points := citizen.get_navigation_points_for_building(park, world)
	citizen.set_position_grounded(nav_points.get("access", park.global_position))

	var action: RelaxAtParkAction = RelaxAtParkActionScript.new()
	citizen.current_action = action
	action.start(world, citizen)
	action.finished = true

	citizen._agent.sim_tick(citizen, world)

	_expect(citizen.current_action == null, "finished relax action should be cleared from the citizen")
	_expect(not citizen.has_active_rest_pose(), "finishing relax park through the agent should clear the active rest pose immediately")
	_expect(not citizen._trace_last_decision_reason.begins_with("rest_pose"), "finishing relax park should not leave a stale rest_pose trace reason behind")
	_expect(park.get_reserved_bench_for(citizen).is_empty(), "finishing relax park through the agent should release the reserved park bench immediately")

	_free_world(world)
	return _current_error

func _test_manual_control_releases_city_bench_reservation() -> String:
	var world: World = _new_world()
	var building: Building = _new_building("Bench House")
	var citizen: Citizen = _new_citizen("Manual Bench User")
	var bench := _add_bench(building, "Bench", Vector3(1.4, 0.0, -0.3), 1.05)
	world.register_building(building)
	world.register_citizen(citizen)
	var reservation := world.reserve_city_bench_for(citizen, citizen.global_position)
	citizen.set_rest_pose(bench.global_position, bench.global_rotation.y)

	citizen.set_manual_control_enabled(true, world)

	_expect(not reservation.is_empty(), "manual control test should start with a city bench reservation")
	_expect(not citizen.has_active_rest_pose(), "switching to manual control should clear the bench rest pose")
	_expect(world.get_reserved_city_bench_for(citizen).is_empty(), "switching to manual control should also release the reserved city bench")

	_free_world(world)
	return _current_error

func _test_world_city_bench_excludes_park_benches() -> String:
	var world: World = _new_world()
	var building: Building = _new_building("Bench House")
	var park: Park = _new_park("Garden Park")
	var citizen: Citizen = _new_citizen("Bench Finder")
	var city_bench := _add_bench(building, "Bench", Vector3(2.0, 0.0, 0.6), 0.4)
	_add_bench(park, "Bench", Vector3(0.4, 0.0, 0.2), 0.2)
	world.register_building(building)
	world.register_building(park)
	world.register_citizen(citizen)

	var reservation := world.reserve_city_bench_for(citizen, citizen.global_position)

	_expect(not reservation.is_empty(), "world should find a free city bench")
	_expect_eq(reservation.get("node"), city_bench, "city bench search should ignore park benches")

	world.release_city_bench_for(citizen)
	_free_world(world)
	return _current_error

func _test_world_city_bench_cache_refreshes_on_scene_change() -> String:
	var world: World = _new_world()
	var building: Building = _new_building("Bench Cache House")
	var citizen: Citizen = _new_citizen("Bench Cache Finder")
	world.register_building(building)
	world.register_citizen(citizen)

	_expect(not world.has_available_city_bench_for(citizen, citizen.global_position), "without markers the city bench cache should start empty")

	var bench := _add_bench(building, "Bench_Late", Vector3(1.8, 0.0, 0.2), 0.35)
	var reservation := world.reserve_city_bench_for(citizen, citizen.global_position)
	_expect(not reservation.is_empty(), "adding a bench after the initial lookup should invalidate the cache")
	_expect_eq(reservation.get("node"), bench, "cache rebuild should discover the newly added city bench")

	world.release_city_bench_for(citizen)
	bench.free()
	_expect(not world.has_available_city_bench_for(citizen, citizen.global_position), "removing the bench should invalidate the cache again")

	_free_world(world)
	return _current_error

func _test_world_auto_registers_runtime_park_queries() -> String:
	var world: World = _new_world()
	var park: Park = _new_park("Auto Park")

	_expect_eq(world.find_nearest_park(Vector3.ZERO), park, "runtime-added parks should auto-register for nearest park queries")
	_expect_eq(world.find_nearest_building_with_service(Vector3.ZERO, "fun", false, null), park, "runtime-added parks should also populate the generic service registry")

	_free_world(world)
	return _current_error

func _test_world_unregisters_removed_park_from_queries() -> String:
	var world: World = _new_world()
	var park: Park = _new_park("Removed Park")

	_expect_eq(world.find_nearest_park(Vector3.ZERO), park, "precondition failed: park should be queryable before removal")
	park.free()
	_expect(world.find_nearest_park(Vector3.ZERO) == null, "removed parks should be pruned from nearest park queries")
	_expect(world.find_nearest_building_with_service(Vector3.ZERO, "fun", false, null) == null, "removed parks should also leave the generic service registry")

	_free_world(world)
	return _current_error

func _test_world_registers_scene_park_cluster_once() -> String:
	var world: World = _new_world()
	var cluster := Node3D.new()
	cluster.name = "Park"
	_harness_root.add_child(cluster)

	var park_a: Park = ParkScript.new()
	park_a.name = "ParkTileA"
	park_a.building_name = "Park 01 (Park)"
	var entrance_a := Node3D.new()
	entrance_a.name = "Entrance"
	entrance_a.position = Vector3(0.0, 0.0, 1.0)
	park_a.add_child(entrance_a)
	cluster.add_child(park_a)
	var park_b: Park = ParkScript.new()
	park_b.name = "ParkTileB"
	park_b.building_name = "Park 02 (Park)"
	park_b.position = Vector3(2.0, 0.0, 0.0)
	var entrance_b := Node3D.new()
	entrance_b.name = "Entrance"
	entrance_b.position = Vector3(0.0, 0.0, 1.0)
	park_b.add_child(entrance_b)
	cluster.add_child(park_b)

	world.register_building(park_a)
	world.register_building(park_b)

	_expect_eq(world.buildings.size(), 1, "scene park tiles under the Park node should register as one building")
	_expect_eq(world.find_nearest_park(Vector3.ZERO), park_a, "first park tile should act as the scene-cluster representative")
	_expect_eq(world.get_canonical_building(park_b), park_a, "park tile aliases should resolve to the representative")
	_expect_eq(park_a.get_display_name(), "Park", "park cluster should use the parent node name in building lists")

	_free_world(world)
	return _current_error

func _test_citizen_factory_spawns_at_home_entrance() -> String:
	var world: World = _new_world()
	var home: ResidentialBuilding = _new_residential("Starter Home", Vector3(0.0, 0.0, 1.4), 6)
	world.register_building(home)

	var spawned: Array[Citizen] = CitizenFactoryScript.spawn_citizens(_harness_root, world, 4)
	_expect_eq(spawned.size(), 4, "factory should spawn the requested citizens")
	_expect_eq(home.tenants.size(), 4, "spawned citizens should occupy home slots immediately")

	for index in spawned.size():
		var citizen := spawned[index]
		_expect_eq(citizen.home, home, "spawned citizen should keep the assigned residential home")
		_expect_eq(citizen.current_location, home, "spawned citizen should start logically at home")
		_expect(citizen.is_inside_building(), "initial spawn should start inside the home until the first exit")
		_expect(not citizen.visible, "initial home residents should be hidden while they are inside")
		_expect(citizen.global_position.distance_to(home.get_entrance_pos()) < 1.2, "citizen should spawn near the home entrance")
		if index == 0:
			var center_spawn: Vector3 = home.get_navigation_points(world, 0.0).get("spawn", home.get_entrance_pos())
			_expect(citizen.global_position.distance_to(center_spawn) < 0.15, "first same-home spawn should stay centered at the exit")

	_free_world(world)
	return _current_error

func _test_job_offer_prefers_training_and_reserves_slot() -> String:
	var world: World = _new_world()
	var factory: Building = _new_building("Training Factory", 1)
	factory.building_type = BuildingScript.BuildingType.FACTORY
	world.register_building(factory)

	var trainee: Citizen = _new_citizen("Trainee Applicant")
	trainee.education_level = 0
	world.register_citizen(trainee)

	var offer := world.find_best_job_offer_for_citizen(trainee.global_position, trainee, true)
	_expect(not offer.is_empty(), "job offer should be available for an uneducated trainee")
	_expect_eq(offer.get("building", null), factory, "job offer should target the factory")
	_expect(int(offer.get("education_gap", 0)) > 0, "job offer should be allowed to require education")

	var job := CitizenFactoryScript.build_job_from_offer(offer)
	_expect(job != null, "training offer should build a concrete job resource")
	if job != null:
		trainee.job = job
		world.register_job(job)

	var second: Citizen = _new_citizen("Second Applicant")
	var second_offer := world.find_best_job_offer_for_citizen(second.global_position, second, true)
	_expect(second_offer.is_empty(), "reserved trainee job should consume the only factory slot")

	_free_world(world)
	return _current_error

func _test_study_finish_hires_reserved_trainee() -> String:
	var world: World = _new_world()
	var university: University = _new_university("Hiring Uni")
	var factory: Building = _new_building("Hiring Factory", 1)
	factory.building_type = BuildingScript.BuildingType.FACTORY
	university.job_capacity = 2
	world.register_building(university)
	world.register_building(factory)

	var teacher: Citizen = _new_citizen("Teacher Worker")
	teacher.job = Job.new()
	teacher.job.title = "Teacher"
	teacher.job.workplace = university
	teacher.job.workplace_service_type = "education"
	_expect(university.try_hire(teacher), "university should hire teaching staff before study")

	var trainee: Citizen = _new_citizen("Engineer Trainee")
	trainee.education_level = 0
	trainee.job = Job.new()
	trainee.job.title = "Engineer"
	trainee.job.workplace = factory
	trainee.job.preferred_workplace = factory
	trainee.job.required_education_level = 1
	trainee.job.allowed_building_types = [BuildingScript.BuildingType.FACTORY]
	world.register_citizen(trainee)
	world.register_job(trainee.job)

	var action: StudyAtUniversityAction = StudyAtUniversityActionScript.new(university, 1)
	action.start(world, trainee)
	action.tick(world, trainee, 1)
	action.finish(world, trainee)

	_expect_eq(trainee.education_level, 1, "study should satisfy the reserved job education requirement")
	_expect(factory.workers.has(trainee), "study finish should hire the qualified trainee into the reserved workplace")
	_expect(world.jobs.has(trainee.job), "reserved trainee job should remain registered after hiring")
	_expect_eq(university.visitors.size(), 0, "study finish should remove the trainee from university visitors")

	_free_world(world)
	return _current_error

func _test_citizen_death_cleanup_unregisters_and_queues_refill() -> String:
	var world: World = _new_world()
	var home: ResidentialBuilding = _new_residential("Death Home", Vector3(0.0, 0.0, 1.4), 2)
	var workplace: Building = _new_building("Death Workplace", 1)
	world.register_building(home)
	world.register_building(workplace)

	var spawned: Array[Citizen] = CitizenFactoryScript.spawn_citizens(_harness_root, world, 1)
	_expect_eq(spawned.size(), 1, "factory should create the death-test citizen")
	if spawned.is_empty():
		_free_world(world)
		return _current_error

	var citizen := spawned[0]
	var job := citizen.job if citizen.job != null else Job.new()
	job.title = "Worker"
	job.workplace = workplace
	citizen.job = job
	world.register_job(job)
	_expect(workplace.try_hire(citizen), "workplace should hire the test citizen")
	_expect(home.tenants.has(citizen), "death-test citizen should occupy a home before death")
	_expect(world.citizens.has(citizen), "death-test citizen should be registered before death")
	_expect(world.jobs.has(job), "death-test job should be registered before death")

	citizen.needs.health = 0.0
	citizen.die(world)

	_expect(citizen.is_dying(), "death cleanup should mark the citizen as dying")
	_expect(not world.citizens.has(citizen), "death cleanup should unregister the citizen immediately")
	_expect(not home.tenants.has(citizen), "death cleanup should release the residential tenant slot")
	_expect(not workplace.workers.has(citizen), "death cleanup should release the workplace worker slot")
	_expect(job.workplace == null, "death cleanup should detach the job from the workplace")
	_expect(not world.jobs.has(job), "death cleanup should unregister the citizen job from world/economy")
	_expect(world.get_population_refill_pending_count() > 0, "death cleanup should queue a delayed population refill")

	_free_world(world)
	return _current_error

func _test_population_refill_spawns_after_delay() -> String:
	var world: World = _new_world()
	world.minutes_per_tick = 60
	world.time.minutes_total = 0
	world.set_citizen_spawn_parent(_harness_root)
	var home: ResidentialBuilding = _new_residential("Refill Home", Vector3(0.0, 0.0, 1.4), 2)
	world.register_building(home)

	var spawned: Array[Citizen] = CitizenFactoryScript.spawn_citizens(_harness_root, world, 1)
	_expect_eq(spawned.size(), 1, "factory should create the refill-test citizen")
	if spawned.is_empty():
		_free_world(world)
		return _current_error

	var original := spawned[0]
	original.needs.health = 0.0
	original.die(world)
	_expect_eq(world.get_active_citizen_count(), 0, "dead citizen should not count as active population")
	_expect(world.get_population_refill_pending_count() > 0, "death should queue at least one refill request")

	var replacement: Citizen = null
	for _hour in range(181):
		world._on_tick()
		if world.get_active_citizen_count() <= 0:
			continue
		for candidate in world.citizens:
			if candidate != null and is_instance_valid(candidate) and candidate != original:
				replacement = candidate
				break
		if replacement != null:
			break

	_expect(replacement != null, "population refill should spawn a replacement after the configured delay window")
	if replacement != null:
		_expect(replacement.home == home, "refill citizen should prefer an available residential home")
		_expect(home.tenants.has(replacement), "refill citizen should occupy the residential tenant slot")
		_expect(replacement.current_location == home, "refill citizen should start logically at home")
		_expect(replacement.is_inside_building(), "refill citizen should start hidden inside the home")
		_expect(replacement.wallet.balance > 0, "refill citizen should receive the configured starting wallet")
		_expect(replacement.home_food_stock > 0, "refill citizen should receive configured home food stock")

	_free_world(world)
	return _current_error

func _test_citizen_crowd_push_separates_close_neighbors() -> String:
	var front: Citizen = _new_citizen("Front Citizen")
	var back: Citizen = _new_citizen("Back Citizen")
	front.add_to_group("citizens")
	back.add_to_group("citizens")
	front.global_position = Vector3(0.0, 0.0, 0.0)
	back.global_position = Vector3(0.0, 0.0, 0.0)
	front.velocity = Vector3.ZERO
	back.velocity = Vector3.ZERO

	front._apply_citizen_crowd_push()
	back._apply_citizen_crowd_push()

	_expect(front.velocity.length() > 0.01, "front citizen should be pushed out of exact overlap")
	_expect(back.velocity.length() > 0.01, "back citizen should also separate from exact overlap")
	_expect(front.velocity.dot(back.velocity) < -0.0001, "exact-overlap push should split the pair in opposite directions")
	return _current_error

func _test_citizen_auto_resolves_world_for_queries() -> String:
	var world: World = _new_world()
	var park: Park = _new_park("Query Park")
	var citizen: Citizen = _new_citizen("Query Citizen")

	var found_park: Building = citizen._find_nearest_park(Vector3.ZERO)

	_expect_eq(found_park, park, "citizen should still find the nearest park through the world service")
	_expect_eq(citizen._world_ref, world, "citizen query helpers should auto-resolve and retain the world reference")

	_free_world(world)
	return _current_error

func _test_hungry_citizen_uses_nearest_food_target() -> String:
	var world: World = _new_world()
	world.time.minutes_total = 12 * 60
	var near_restaurant: Restaurant = _new_restaurant("Near Restaurant", Vector3(2.0, 0.0, 0.0))
	var far_restaurant: Restaurant = _new_restaurant("Far Favorite Restaurant", Vector3(40.0, 0.0, 0.0))
	world.register_building(far_restaurant)
	world.register_building(near_restaurant)

	_expect_eq(
		world.find_nearest_restaurant_with_meal(Vector3.ZERO, true, null),
		near_restaurant,
		"world should expose the nearest stocked restaurant for urgent food queries"
	)

	var citizen: Citizen = _new_citizen("Hungry Citizen")
	world.register_citizen(citizen)
	citizen.set_world_ref(world)
	citizen.global_position = Vector3.ZERO
	citizen.force_update_transform()
	citizen.home = null
	citizen.home_food_stock = 0
	citizen.favorite_restaurant = far_restaurant
	citizen.favorite_supermarket = null
	citizen.wallet.balance = 200
	citizen.needs.energy = 90.0
	citizen.needs.fun = 70.0
	citizen.needs.health = 100.0
	citizen.hunger_threshold = 60.0

	citizen.needs.hunger = 72.0
	citizen.plan_next_action(world)
	var hunger_action := citizen.current_action as GoToBuildingAction
	_expect(hunger_action != null, "hungry citizen should choose a restaurant travel action")
	if hunger_action != null:
		_expect_eq(hunger_action.target, near_restaurant, "GOAP hunger target should prefer nearby stocked food over a far favorite")

	citizen.stop_travel()
	citizen.current_action = null
	citizen.current_location = null
	citizen.decision_cooldown_left = 0
	citizen.needs.hunger = 85.0
	citizen.plan_next_action(world)
	var survival_action := citizen.current_action as GoToBuildingAction
	_expect(survival_action != null, "critical hunger should choose a restaurant travel action")
	if survival_action != null:
		_expect_eq(survival_action.target, near_restaurant, "survival hunger target should prefer nearby stocked food over a far favorite")

	_free_world(world)
	return _current_error

func _test_action_default_needs_modifier_is_isolated() -> String:
	var action := ActionScript.new()
	var first_modifier := action.get_needs_modifier(null, null)
	first_modifier["energy_add"] = 123.0
	var second_modifier := action.get_needs_modifier(null, null)

	_expect(is_equal_approx(float(second_modifier.get("energy_add", -1.0)), 0.0), "default action needs modifiers should not leak mutations across calls")
	return _current_error

func _test_relax_bench_uses_energy_bonus() -> String:
	var world: World = _new_world()
	var building: Building = _new_building("Bench House")
	var citizen: Citizen = _new_citizen("Bench Sitter")
	var bench := _add_bench(building, "Bench", Vector3(1.4, 0.0, -0.3), 1.05)
	world.register_building(building)
	world.register_citizen(citizen)

	var reservation := world.reserve_city_bench_for(citizen, citizen.global_position)
	var action = RelaxAtBenchActionScript.new()
	action.start(world, citizen)
	var modifier: Dictionary = action.get_needs_modifier(world, citizen)

	_expect(not reservation.is_empty(), "world should reserve a city bench before bench relax starts")
	_expect(action.is_using_bench(world, citizen), "bench relax should keep the city bench reservation active")
	_expect(citizen.has_active_rest_pose(), "bench relax should activate a rest pose on the citizen")
	_expect_planar_vec3_near(citizen.global_position, bench.global_position, 0.001, "bench relax should snap the citizen onto the city bench marker")
	_expect(float(modifier.get("energy_add", 0.0)) > 0.08, "city bench relax should provide a net positive energy gain")

	action.finish(world, citizen)
	_expect(not citizen.has_active_rest_pose(), "bench relax finish should clear the rest pose")
	_expect(world.get_reserved_city_bench_for(citizen).is_empty(), "bench relax finish should release the city bench reservation")
	_expect_eq(citizen.decision_cooldown_left, 0, "bench relax finish should allow immediate replanning")

	_free_world(world)
	return _current_error

func _new_building(building_name: String, worker_capacity: int = 0) -> Building:
	var building: Building = BuildingScript.new()
	building.name = building_name
	building.building_name = building_name
	building.job_capacity = worker_capacity
	var entrance := Node3D.new()
	entrance.name = "Entrance"
	entrance.position = Vector3(0.0, 0.0, 1.1)
	building.add_child(entrance)
	_harness_root.add_child(building)
	return building

func _test_player_enter_takes_capacity_slot() -> String:
	var world: World = _new_world()

	# Residential -> tenant slot, capacity-gated, hidden, reversible.
	var home: ResidentialBuilding = _new_residential("PlayerHome", Vector3.ZERO, 1)
	home.capacity = 1  # override balance-applied default from _ready()
	var p1: Citizen = _new_citizen("Player One")
	_expect(p1.player_enter_building(home, world), "player should enter residential and take a tenant slot")
	_expect_eq(home.tenants.size(), 1, "residential tenants should increase by 1")
	_expect(home.tenants.has(p1), "player should be listed as tenant")
	_expect(p1.is_inside_building(), "player should be marked inside (hidden) after entering")

	var p2: Citizen = _new_citizen("Player Two")
	_expect(not p2.player_enter_building(home, world), "full residential must reject the player")
	_expect_eq(home.tenants.size(), 1, "rejected entry must not take a slot")
	_expect(not p2.is_inside_building(), "rejected player must not be inside")

	_expect(p1.player_exit_building(world), "player should exit residential")
	_expect_eq(home.tenants.size(), 0, "exit should free the tenant slot")
	_expect(not p1.is_inside_building(), "player should no longer be inside after exit")

	# Workplace -> worker slot, no double visitor count.
	var uni: University = _new_university("Player Work")
	uni.job_capacity = 2
	var p3: Citizen = _new_citizen("Player Three")
	_expect(p3.player_enter_building(uni, world), "player should enter workplace and take a worker slot")
	_expect_eq(uni.workers.size(), 1, "workplace workers should increase by 1")
	_expect_eq(uni.visitors.size(), 0, "player worker must not be double-counted as visitor")
	_expect(p3.is_inside_building(), "player should be inside the workplace")
	_expect(p3.player_exit_building(world), "player should exit workplace")
	_expect_eq(uni.workers.size(), 0, "exit should free the worker slot")

	_free_world(world)
	return _current_error

func _test_offline_keyboard_player_building_input_uses_camera_target() -> String:
	var world: World = _new_world()
	var home: ResidentialBuilding = _new_residential("OfflineInputHome", Vector3.ZERO, 1)
	world.register_building(home)

	var player: Citizen = _new_citizen("Offline Keyboard Player")
	player.keyboard_control_enabled = true
	player.set_world_ref(world)
	player.global_position = home.get_entrance_pos()

	var selection := MockSelectionStateController.new()
	selection.camera_player_target = player
	selection.player_control_active = false

	var interaction = SimulationInteractionControllerScript.new()
	interaction.world = world
	interaction.selection_state_controller = selection
	interaction._ensure_dialog_interact_input_action()
	interaction._ensure_player_building_input_actions()

	var enter_event := InputEventAction.new()
	enter_event.action = "player_enter_building"
	enter_event.pressed = true

	_expect(interaction.handle_input(enter_event), "R-enter should be handled for the offline keyboard camera target")
	_expect(player.is_inside_building(), "offline keyboard player should enter the nearest building")
	_expect(home.tenants.has(player), "offline keyboard player should take a residential capacity slot")

	var exit_event := InputEventAction.new()
	exit_event.action = "player_exit_building"
	exit_event.pressed = true

	_expect(interaction.handle_input(exit_event), "T-exit should be handled for the offline keyboard camera target")
	_expect(not player.is_inside_building(), "offline keyboard player should exit the building")
	_expect(not home.tenants.has(player), "offline keyboard player should free the residential slot on exit")

	_free_world(world)
	return _current_error

func _test_keyboard_player_needs_tick_without_goap() -> String:
	var world: World = _new_world()
	world.minutes_per_tick = 10
	var home: ResidentialBuilding = _new_residential("KeyboardNeedsHome", Vector3.ZERO, 1)
	world.register_building(home)

	var player: Citizen = _new_citizen("Keyboard Needs Player")
	world.register_citizen(player)
	player.set_world_ref(world)
	player.autonomous_simulation_enabled = false
	player.keyboard_control_enabled = true
	player.home = home
	player.current_location = home
	player.home_food_stock = 2
	player.needs.hunger = 85.0
	player.needs.energy = 100.0
	player.needs.fun = 70.0
	player.needs.social = 70.0
	player.needs.health = 100.0

	var hunger_before: float = player.needs.hunger
	var energy_before: float = player.needs.energy
	var social_before: float = player.needs.social
	var health_before: float = player.needs.health

	player._agent.sim_tick(player, world)

	_expect(player.needs.hunger > hunger_before, "keyboard player hunger should still tick while autonomous sim is disabled")
	_expect(player.needs.energy < energy_before, "keyboard player energy should still decay while autonomous sim is disabled")
	_expect(player.needs.social < social_before, "keyboard player social need should still decay while autonomous sim is disabled")
	_expect(player.needs.health < health_before, "keyboard player should still receive health penalties from unmet needs")
	_expect_eq(player.current_action, null, "keyboard player must not start GOAP actions after needs tick")
	_expect_eq(player.decision_cooldown_left, 0, "keyboard player must not roll planner cooldown after needs tick")

	var paused: Citizen = _new_citizen("Paused Non Keyboard")
	world.register_citizen(paused)
	paused.set_world_ref(world)
	paused.autonomous_simulation_enabled = false
	paused.keyboard_control_enabled = false
	paused.needs.hunger = 85.0
	var paused_hunger_before: float = paused.needs.hunger

	paused._agent.sim_tick(paused, world)
	_expect_eq(paused.needs.hunger, paused_hunger_before, "non-keyboard paused citizens should remain outside sim_tick")

	_free_world(world)
	return _current_error

func _new_residential(building_name: String, entrance_pos: Vector3, home_capacity: int = 10) -> ResidentialBuilding:
	var residential: ResidentialBuilding = ResidentialBuildingScript.new()
	residential.name = building_name
	residential.building_name = building_name
	residential.capacity = home_capacity
	var entrance := Node3D.new()
	entrance.name = "Entrance"
	entrance.position = entrance_pos
	residential.add_child(entrance)
	_harness_root.add_child(residential)
	return residential

func _new_university(building_name: String) -> University:
	var university: University = UniversityScript.new()
	university.name = building_name
	university.building_name = building_name
	var entrance := Node3D.new()
	entrance.name = "Entrance"
	entrance.position = Vector3(0.0, 0.0, 1.4)
	university.add_child(entrance)
	_harness_root.add_child(university)
	return university

func _new_restaurant(building_name: String, position: Vector3) -> Restaurant:
	var restaurant: Restaurant = RestaurantScript.new()
	restaurant.name = building_name
	restaurant.building_name = building_name
	restaurant.position = position
	var entrance := Node3D.new()
	entrance.name = "Entrance"
	restaurant.add_child(entrance)
	_harness_root.add_child(restaurant)
	return restaurant

func _new_park(building_name: String) -> Park:
	var cluster := Node3D.new()
	cluster.name = "%sCluster" % building_name
	_harness_root.add_child(cluster)
	var park: Park = ParkScript.new()
	park.name = building_name
	park.building_name = building_name
	var entrance_south := Node3D.new()
	entrance_south.name = "EntranceSouth"
	entrance_south.position = Vector3(0.0, 0.0, 1.4)
	park.add_child(entrance_south)
	var entrance_north := Node3D.new()
	entrance_north.name = "EntranceNorth"
	entrance_north.position = Vector3(0.0, 0.0, -1.4)
	park.add_child(entrance_north)
	cluster.add_child(park)
	return park

func _add_bench(parent: Node3D, bench_name: String, position: Vector3, yaw: float = 0.0) -> Node3D:
	var bench := Node3D.new()
	bench.name = bench_name
	bench.position = position
	bench.rotation.y = yaw
	parent.add_child(bench)
	return bench

func _new_citizen(citizen_name: String) -> Citizen:
	var citizen: Citizen = CitizenScript.new()
	citizen.name = citizen_name
	citizen.citizen_name = citizen_name
	citizen.jump_low_obstacles = false
	_harness_root.add_child(citizen)
	return citizen

func _new_world() -> World:
	var world: World = WorldScript.new()
	world.time.minutes_total = 10 * 60
	_harness_root.add_child(world)
	return world

func _free_world(world) -> void:
	if world == null:
		return
	if world.time != null:
		world.time.free()
		world.time = null
	if world.economy != null:
		world.economy.free()
		world.economy = null
	world.free()

func _reset_harness_root() -> void:
	if not is_instance_valid(_harness_root):
		return
	for child in _harness_root.get_children():
		child.free()

func _expect(condition: bool, message: String) -> void:
	_checks_run += 1
	if condition or _current_error != "":
		return
	_current_error = message

func _expect_eq(actual, expected, message: String) -> void:
	_checks_run += 1
	if actual == expected or _current_error != "":
		return
	_current_error = "%s | expected=%s actual=%s" % [message, str(expected), str(actual)]

func _expect_vec3_near(actual: Vector3, expected: Vector3, tolerance: float, message: String) -> void:
	_checks_run += 1
	if actual.distance_to(expected) <= tolerance or _current_error != "":
		return
	_current_error = "%s | expected=%s actual=%s tol=%.4f" % [message, str(expected), str(actual), tolerance]

func _expect_planar_vec3_near(actual: Vector3, expected: Vector3, tolerance: float, message: String) -> void:
	_checks_run += 1
	if _current_error != "":
		return
	var delta := actual - expected
	delta.y = 0.0
	if delta.length() <= tolerance:
		return
	_current_error = "%s | expected=%s actual=%s tol=%.4f" % [message, str(expected), str(actual), tolerance]
