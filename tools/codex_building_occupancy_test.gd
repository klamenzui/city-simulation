extends SceneTree

const BuildingScript = preload("res://Entities/Buildings/Building.gd")
const ParkScript = preload("res://Entities/Buildings/Park.gd")
const CinemaScript = preload("res://Entities/Buildings/Cinema.gd")
const RestaurantScript = preload("res://Entities/Buildings/Restaurant.gd")
const ResidentialBuildingScript = preload("res://Entities/Buildings/ResidentialBuilding.gd")
const ShopScript = preload("res://Entities/Buildings/Shop.gd")
const SupermarketScript = preload("res://Entities/Buildings/Supermarket.gd")
const UniversityScript = preload("res://Entities/Buildings/University.gd")
const CitizenScript = preload("res://Entities/Citizens/New/Citizen.gd")
const WorldScript = preload("res://Simulation/World.gd")
const CitizenFactoryScript = preload("res://Simulation/Factories/CitizenFactory.gd")
const ActionScript = preload("res://Actions/Action.gd")
const WorkActionScript = preload("res://Actions/WorkAction.gd")
const StudyAtUniversityActionScript = preload("res://Actions/StudyAtUniversityAction.gd")
const RelaxAtHomeActionScript = preload("res://Actions/RelaxAtHomeAction.gd")
const GoToBuildingActionScript = preload("res://Actions/GoToBuildingAction.gd")
const GoToBenchActionScript = preload("res://Actions/GoToBenchAction.gd")
const RelaxAtParkActionScript = preload("res://Actions/RelaxAtParkAction.gd")
const RelaxAtBenchActionScript = preload("res://Actions/RelaxAtBenchAction.gd")
const SocializeActionScript = preload("res://Actions/SocializeAction.gd")
const WatchCinemaActionScript = preload("res://Actions/WatchCinemaAction.gd")
const SimulationInteractionControllerScript = preload("res://Simulation/UI/SimulationInteractionController.gd")
const ToastControllerScript = preload("res://Simulation/UI/ToastController.gd")
const MultiplayerHostAuthorityScript = preload("res://Simulation/Multiplayer/server/MultiplayerHostAuthority.gd")
const NetworkEntityRegistryScript = preload("res://Simulation/Multiplayer/shared/NetworkEntityRegistry.gd")
const WorldSnapshotSerializerScript = preload("res://Simulation/Multiplayer/shared/WorldSnapshotSerializer.gd")

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

class MockMultiplayerSession:
	extends RefCounted

	var client_mode: bool = true
	var host_mode: bool = false
	var requested_player_actions: Array[String] = []
	var requested_entity_targets: Array[Node] = []

	func is_client() -> bool:
		return client_mode

	func is_host() -> bool:
		return host_mode

	func request_player_action(action_id: String) -> bool:
		requested_player_actions.append(action_id)
		return true

	func request_entity_interaction(target: Node) -> bool:
		requested_entity_targets.append(target)
		return target != null

class MockToastController:
	extends RefCounted

	var messages: Array[String] = []
	var kinds: Array[String] = []

	func show_toast(message: String, kind: String = "info", _duration_sec: float = 0.0) -> void:
		messages.append(message)
		kinds.append(kind)

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
		"pause_uses_explicit_action_not_ui_accept",
		"offline_keyboard_player_building_input_uses_camera_target",
		"keyboard_player_needs_tick_without_goap",
		"toast_controller_lifecycle",
		"player_action_buttons_and_manual_actions",
		"player_home_move_quit_and_info",
		"multiplayer_controller_routes_player_actions_as_commands",
		"multiplayer_host_authority_applies_player_actions",
		"network_snapshot_rebuilds_player_work_and_home_ui",
		"player_work_education_gate",
		"player_university_unlocks_job",
		"player_work_payday_uses_worked_minutes",
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
		"citizen_factory_display_names_stay_unique",
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
		"pause_uses_explicit_action_not_ui_accept":
			return _test_pause_uses_explicit_action_not_ui_accept()
		"offline_keyboard_player_building_input_uses_camera_target":
			return _test_offline_keyboard_player_building_input_uses_camera_target()
		"keyboard_player_needs_tick_without_goap":
			return _test_keyboard_player_needs_tick_without_goap()
		"toast_controller_lifecycle":
			return _test_toast_controller_lifecycle()
		"player_action_buttons_and_manual_actions":
			return _test_player_action_buttons_and_manual_actions()
		"player_home_move_quit_and_info":
			return _test_player_home_move_quit_and_info()
		"multiplayer_controller_routes_player_actions_as_commands":
			return _test_multiplayer_controller_routes_player_actions_as_commands()
		"multiplayer_host_authority_applies_player_actions":
			return _test_multiplayer_host_authority_applies_player_actions()
		"network_snapshot_rebuilds_player_work_and_home_ui":
			return _test_network_snapshot_rebuilds_player_work_and_home_ui()
		"player_work_education_gate":
			return _test_player_work_education_gate()
		"player_university_unlocks_job":
			return _test_player_university_unlocks_job()
		"player_work_payday_uses_worked_minutes":
			return _test_player_work_payday_uses_worked_minutes()
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
		"citizen_factory_display_names_stay_unique":
			return _test_citizen_factory_display_names_stay_unique()
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

func _test_citizen_factory_display_names_stay_unique() -> String:
	var names := {}
	for serial in range(1, 121):
		var display_name := str(CitizenFactoryScript._build_citizen_display_name(serial))
		_expect(not names.has(display_name), "citizen display name should not repeat before exhausting the full name pool: %s" % display_name)
		names[display_name] = true
	_expect_eq(names.size(), 120, "first 120 citizen display names should be unique")
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

	# Residential entry is only inspection. Renting is explicit and persists.
	var home: ResidentialBuilding = _new_residential("PlayerHome", Vector3.ZERO, 1)
	home.capacity = 1  # override balance-applied default from _ready()
	var p1: Citizen = _new_citizen("Player One")
	p1.set_world_ref(world)
	_expect(p1.player_enter_building(home, world), "player should enter residential to inspect it")
	_expect_eq(home.tenants.size(), 0, "residential inspection must not take a tenant slot")
	_expect(p1.home == null, "residential inspection must not assign a home")
	_expect(p1.is_inside_building(), "player should be marked inside (hidden) after entering")
	var rent_state := p1.get_player_action_ui_state(world)
	_expect(_player_ui_button_enabled(rent_state, "rent_home"), "residential UI should expose an enabled rent button")
	_expect_eq(_player_ui_button_text(rent_state, "rent_home"), "Mieten", "first residential action should be Mieten")
	_expect(p1.player_rent_home(world), "rent button should assign the player home")
	_expect_eq(home.tenants.size(), 1, "renting should take the tenant slot")
	_expect(home.tenants.has(p1), "player should be listed as tenant after renting")
	_expect_eq(p1.home, home, "rented residential should persist as the player's home")

	var p2: Citizen = _new_citizen("Player Two")
	p2.set_world_ref(world)
	_expect(p2.player_enter_building(home, world), "full residential can still be inspected")
	_expect(not p2.player_rent_home(world), "full residential must reject rental")
	_expect_eq(home.tenants.size(), 1, "rejected rental must not take a slot")
	_expect(p2.home == null, "rejected rental must not assign a home")

	_expect(p1.player_exit_building(world), "player should exit residential")
	_expect_eq(home.tenants.size(), 1, "leaving home should keep the player's home slot")
	_expect_eq(p1.home, home, "residential entry should persist as the player's home")
	_expect(not p1.is_inside_building(), "player should no longer be inside after exit")

	# Workplace entry is a plain visit: NO job and NO worker slot. Employment
	# is opt-in via player_apply_for_work() ("Bewerben") only.
	var uni: University = _new_university("Player Work")
	uni.job_capacity = 2
	var p3: Citizen = _new_citizen("Player Three")
	_expect(p3.player_enter_building(uni, world), "player should enter the workplace as a visitor")
	_expect_eq(uni.workers.size(), 0, "entering a workplace must not auto-hire the player")
	_expect(uni.visitors.has(p3), "workplace entry should occupy a visitor slot")
	_expect(p3.job == null, "entering a workplace must not assign any job")
	_expect(p3.is_inside_building(), "player should be inside the workplace")
	_expect(p3.player_exit_building(world), "player should exit workplace")
	_expect_eq(uni.workers.size(), 0, "exit should not leave a worker slot taken")
	_expect_eq(uni.visitors.size(), 0, "exit should free the visitor slot")

	_free_world(world)
	return _current_error

func _test_pause_uses_explicit_action_not_ui_accept() -> String:
	var world: World = _new_world()
	var interaction = SimulationInteractionControllerScript.new()
	interaction.world = world
	interaction.selection_state_controller = MockSelectionStateController.new()
	interaction._ensure_pause_input_action()
	interaction._ensure_dialog_interact_input_action()

	var accept_event := InputEventAction.new()
	accept_event.action = "ui_accept"
	accept_event.pressed = true
	_expect(not interaction.handle_input(accept_event), "ui_accept should not toggle simulation pause")
	_expect(not world.is_paused, "ui_accept should leave the world unpaused")

	var pause_event := InputEventAction.new()
	pause_event.action = "simulation_pause"
	pause_event.pressed = true
	_expect(interaction.handle_input(pause_event), "simulation_pause should be handled")
	_expect(world.is_paused, "simulation_pause should toggle world pause")

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
	_expect(not home.tenants.has(player), "offline keyboard entry should inspect before renting")
	_expect(player.player_rent_home(world), "offline keyboard player should rent after entering residential")
	_expect(home.tenants.has(player), "offline keyboard player should take a residential slot after renting")

	var exit_event := InputEventAction.new()
	exit_event.action = "player_exit_building"
	exit_event.pressed = true

	_expect(interaction.handle_input(exit_event), "T-exit should be handled for the offline keyboard camera target")
	_expect(not player.is_inside_building(), "offline keyboard player should exit the building")
	_expect(home.tenants.has(player), "offline keyboard player should keep their home slot on exit")

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

func _test_toast_controller_lifecycle() -> String:
	var canvas := CanvasLayer.new()
	_harness_root.add_child(canvas)
	var toasts = ToastControllerScript.new()
	toasts.setup(canvas)
	toasts.show_toast("Testmeldung", "success", 0.2)
	_expect_eq(toasts.get_active_toast_count(), 1, "toast should be tracked after creation")
	var messages := toasts.get_active_toast_messages()
	_expect(messages.has("Testmeldung"), "toast should keep its visible message for tests and diagnostics")
	toasts.update(0.3)
	_expect_eq(toasts.get_active_toast_count(), 0, "toast should expire after its duration")
	return _current_error

func _test_player_action_buttons_and_manual_actions() -> String:
	var world: World = _new_world()
	world.minutes_per_tick = 10
	var home: ResidentialBuilding = _new_residential("PlayerActionHome", Vector3.ZERO, 1)
	var workplace: Building = _new_building("PlayerActionShop", 1)
	workplace.building_type = BuildingScript.BuildingType.SHOP
	world.register_building(home)
	world.register_building(workplace)

	var player: Citizen = _new_citizen("Player Action")
	world.register_citizen(player)
	player.set_world_ref(world)
	player.autonomous_simulation_enabled = false
	player.keyboard_control_enabled = true
	player.home_food_stock = 2
	player.needs.hunger = 85.0
	player.needs.energy = 100.0
	player.needs.fun = 70.0
	player.needs.health = 100.0

	_expect(player.player_enter_building(home, world), "player should move into a free home")
	var rent_home_state := player.get_player_action_ui_state(world)
	_expect(_player_ui_button_enabled(rent_home_state, "rent_home"), "residential UI should expose an enabled rent button")
	_expect(player.player_rent_home(world), "rent button action should set the player's home")
	var selection := MockSelectionStateController.new()
	selection.camera_player_target = player
	var interaction = SimulationInteractionControllerScript.new()
	interaction.world = world
	interaction.selection_state_controller = selection
	interaction._refresh_player_home_marker()
	var home_marker := home.get_node_or_null("PlayerHomeMarker") as Label3D
	_expect(home_marker != null and home_marker.text.find("ZUHAUSE") != -1,
			"rented player home should get a visible home marker")
	var home_state := player.get_player_action_ui_state(world)
	_expect_eq(_player_ui_button_text(home_state, "quit_home"), "Wohnung kuendigen", "home UI should expose explicit lease cancellation")
	_expect(_player_ui_button_enabled(home_state, "eat"), "home UI should expose an enabled eat button")
	_expect(_player_ui_button_enabled(home_state, "sleep"), "home UI should expose an enabled sleep button")
	_expect(_player_ui_button_enabled(home_state, "relax"), "home UI should expose an enabled relax button")
	player.needs.hunger = 20.0
	player.needs.energy = 90.0
	player.needs.fun = 0.0
	var home_fun_before := player.needs.fun
	_expect(player.player_relax(world), "home relax action should start for the player")
	_expect(player.current_action is RelaxAtHomeActionScript, "home relax should use RelaxAtHomeAction")
	player._agent.sim_tick(player, world)
	_expect(player.needs.fun > home_fun_before, "home relax should improve player fun")
	player.cancel_player_action(world)

	player.needs.hunger = 85.0
	var hunger_before := player.needs.hunger
	_expect(player.player_eat(world), "eat button action should start eating at home")
	_expect_eq(player.home_food_stock, 1, "eat action should consume one home food stock immediately")
	player._agent.sim_tick(player, world)
	_expect(player.needs.hunger < hunger_before, "explicit player eat action should tick for keyboard player")
	_expect(player.player_exit_building(world), "player should leave home after eating")
	_expect(home.tenants.has(player), "leaving home should not cancel the home lease")

	player.needs.hunger = 20.0
	player.needs.energy = 100.0
	player.needs.fun = 80.0
	_expect(player.player_enter_building(workplace, world), "player should enter the workplace as a visitor")
	_expect(not workplace.workers.has(player), "entering a workplace must not auto-hire the player")
	_expect(player.job == null, "entering a workplace must not assign any job")
	var work_state := player.get_player_action_ui_state(world)
	_expect(_player_ui_button_enabled(work_state, "apply_work"), "workplace UI should expose an enabled apply button")
	_expect_eq(_player_ui_button_text(work_state, "apply_work"), "Bewerben", "first workplace action should be Bewerben")
	_expect(not _player_ui_button_present(work_state, "work"), "work must not appear before the player is accepted")
	_expect(not _player_ui_button_present(work_state, "quit_job"), "quit must not appear before the player is employed")
	_expect(player.player_apply_for_work(world), "apply button action should accept and hire the player")
	_expect(workplace.workers.has(player), "accepted application should take the worker slot")
	_expect(player.job != null and player.job.workplace == workplace, "accepted application should assign the workplace job")
	var accepted_state := player.get_player_action_ui_state(world)
	_expect(_player_ui_button_enabled(accepted_state, "work"), "accepted workplace UI should expose an enabled work button")
	_expect_eq(_player_ui_button_text(accepted_state, "work"), "Arbeiten", "accepted workplace action should be Arbeiten")
	_expect(not _player_ui_button_present(accepted_state, "apply_work"), "apply must disappear after acceptance")
	_expect(_player_ui_button_enabled(accepted_state, "quit_job"), "quit should appear once the player is employed")
	var worked_before := player.work_minutes_today
	_expect(player.player_work(world), "work button action should start the accepted job")
	player._agent.sim_tick(player, world)
	_expect(player.work_minutes_today > worked_before, "explicit player work action should tick for keyboard player")
	_expect(player.player_exit_building(world), "leaving workplace should exit without quitting")
	_expect(player.job != null and player.job.workplace == workplace, "leaving workplace should keep the accepted job")
	_expect(workplace.workers.has(player), "leaving workplace should keep the worker slot")
	_expect(player.player_enter_building(workplace, world), "player should re-enter accepted workplace")
	var reentered_state := player.get_player_action_ui_state(world)
	_expect(_player_ui_button_enabled(reentered_state, "work"), "accepted job should still show Arbeit after re-entering")
	_expect(not _player_ui_button_present(reentered_state, "apply_work"), "accepted job should not require re-application")
	_expect(player.player_quit_job(world, true), "quit button action should leave and remove the job")
	_expect(player.job == null, "quit should clear the player's job")
	_expect(not workplace.workers.has(player), "quit should free the worker slot")
	_expect(not player.is_inside_building(), "quit from UI should exit the workplace")

	var shop: Shop = _new_shop("Player Inventory Shop", Vector3(6.0, 0.0, 0.0))
	var market: Supermarket = _new_supermarket("Player Inventory Market", Vector3(8.0, 0.0, 0.0))
	world.register_building(shop)
	world.register_building(market)
	world.time.minutes_total = 10 * 60
	player.wallet.balance = 120
	player.needs.fun = 30.0

	_expect(player.player_enter_building(shop, world), "player should enter a shop as a visitor")
	var shop_action_state := player.get_player_action_ui_state(world)
	_expect(_player_ui_button_enabled(shop_action_state, "inventory"), "player UI should expose the inventory button")
	_expect(_player_ui_button_enabled(shop_action_state, "shop"), "shop UI should expose the shopping window button")
	var shop_inventory_state := player.get_player_inventory_ui_state(world, "shop")
	_expect(_player_ui_button_enabled(shop_inventory_state, "buy_shop_item"), "shop inventory should expose clothing purchase")
	var clothing_price := shop.get_item_price_quote(1.0)
	var shop_stock_before := shop.get_stock("clothing")
	var shop_balance_before := shop.account.balance
	var wallet_before_shop := player.wallet.balance
	var fun_before_shop := player.needs.fun
	_expect(player.player_buy_shop_item(world), "player should buy clothing directly from the shop")
	_expect_eq(player.clothing_items, 1, "clothing purchase should add to player inventory")
	_expect_eq(player.wallet.balance, wallet_before_shop - clothing_price, "clothing purchase should charge the player")
	_expect_eq(shop.account.balance, shop_balance_before + clothing_price, "shop should receive clothing revenue")
	_expect_eq(shop.get_stock("clothing"), shop_stock_before - 1, "shop clothing stock should decrease")
	_expect(player.needs.fun > fun_before_shop, "clothing purchase should improve fun")
	_expect(player.player_exit_building(world), "player should leave the shop before entering the market")

	_expect(player.player_enter_building(market, world), "player should enter a supermarket as a visitor")
	var grocery_inventory_state := player.get_player_inventory_ui_state(world, "shop")
	_expect(_player_ui_button_enabled(grocery_inventory_state, "buy_groceries"), "supermarket inventory should expose grocery purchase")
	var grocery_price := market.get_grocery_price(world)
	var grocery_stock_before := market.get_stock("grocery_bundle")
	var wallet_before_grocery := player.wallet.balance
	var food_before := player.home_food_stock
	_expect(player.player_buy_groceries(world), "player should buy groceries from the supermarket")
	_expect_eq(player.home_food_stock, food_before + market.groceries_per_purchase, "grocery purchase should add home food stock")
	_expect_eq(player.wallet.balance, wallet_before_grocery - grocery_price, "grocery purchase should charge the player")
	_expect_eq(market.get_stock("grocery_bundle"), grocery_stock_before - 1, "supermarket grocery stock should decrease")
	_expect(player.player_exit_building(world), "player should leave the market before park actions")

	var park: Park = _new_park("Player Social Park")
	world.register_building(park)
	player.needs.hunger = 20.0
	player.needs.energy = 90.0
	player.needs.health = 100.0
	player.needs.social = 0.0
	player.needs.fun = 0.0
	_expect(player.player_enter_building(park, world), "player should enter park for social and fun actions")
	var park_action_state := player.get_player_action_ui_state(world)
	_expect(_player_ui_button_enabled(park_action_state, "socialize"), "park UI should expose socialize")
	_expect(_player_ui_button_enabled(park_action_state, "relax"), "park UI should expose relax")
	var social_before := player.needs.social
	_expect(player.player_socialize(world), "park socialize action should start for the player")
	_expect(player.current_action is SocializeActionScript, "socialize should use SocializeAction")
	player._agent.sim_tick(player, world)
	_expect(player.needs.social > social_before, "socialize should improve player social")
	player.cancel_player_action(world)
	_expect(player.player_enter_building(park, world), "player should re-enter park after cancelling socialize")
	var park_fun_before := player.needs.fun
	_expect(player.player_relax(world), "park relax action should start for the player")
	_expect(player.current_action is RelaxAtParkActionScript, "park relax should use RelaxAtParkAction")
	player._agent.sim_tick(player, world)
	_expect(player.needs.fun > park_fun_before, "park relax should improve player fun")
	player.cancel_player_action(world)
	_expect(not player.is_inside_building(), "cancelled park relax should leave the park")

	var cinema: Cinema = _new_cinema("Player Cinema", Vector3(10.0, 0.0, 0.0))
	world.register_building(cinema)
	world.time.minutes_total = 13 * 60
	player.wallet.balance = 100
	player.needs.fun = 0.0
	_expect(player.player_enter_building(cinema, world), "player should enter cinema as visitor")
	var cinema_action_state := player.get_player_action_ui_state(world)
	_expect(_player_ui_button_enabled(cinema_action_state, "watch_cinema"), "cinema UI should expose watch action")
	var cinema_fun_before := player.needs.fun
	_expect(player.player_watch_cinema(world), "watch cinema action should start for the player")
	_expect(player.current_action is WatchCinemaActionScript, "cinema action should use WatchCinemaAction")
	player._agent.sim_tick(player, world)
	_expect(player.needs.fun > cinema_fun_before, "watching cinema should improve player fun")

	_free_world(world)
	return _current_error

func _test_player_home_move_quit_and_info() -> String:
	var world: World = _new_world()
	var first_home: ResidentialBuilding = _new_residential("First Player Home", Vector3.ZERO, 1)
	var second_home: ResidentialBuilding = _new_residential("Second Player Home", Vector3(4.0, 0.0, 0.0), 1)
	world.register_building(first_home)
	world.register_building(second_home)

	var player: Citizen = _new_citizen("Player Tenant")
	world.register_citizen(player)
	player.set_world_ref(world)

	_expect(player.player_enter_building(first_home, world), "player should inspect first home")
	_expect(player.player_rent_home(world), "player should rent first home")
	_expect_eq(_info_row_value(player.get_info_sections(world), "Wohnung"), "First Player Home",
			"player info should show rented home")
	_expect(player.player_exit_building(world), "player should leave first home without ending lease")

	_expect(player.player_enter_building(second_home, world), "player should inspect second home")
	var move_state := player.get_player_action_ui_state(world)
	_expect_eq(_player_ui_button_text(move_state, "rent_home"), "Umziehen",
			"second residential should offer moving instead of first rental")
	_expect(player.player_rent_home(world), "player should move to second home")
	_expect_eq(player.home, second_home, "move should replace the player home")
	_expect(not first_home.tenants.has(player), "move should release the old tenant slot")
	_expect(second_home.tenants.has(player), "move should take the new tenant slot")
	_expect_eq(_info_row_value(player.get_info_sections(world), "Wohnung"), "Second Player Home",
			"player info should show moved home")

	_expect(player.player_quit_home(world, true), "player should be able to cancel the home lease")
	_expect(player.home == null, "home cancellation should clear player home")
	_expect(not second_home.tenants.has(player), "home cancellation should release tenant slot")
	_expect_eq(_info_row_value(player.get_info_sections(world), "Wohnung"), "keine",
			"player info should show no home after cancellation")

	_free_world(world)
	return _current_error

func _test_multiplayer_controller_routes_player_actions_as_commands() -> String:
	var world: World = _new_world()
	var home: ResidentialBuilding = _new_residential("NetworkCommandHome", Vector3.ZERO, 1)
	world.register_building(home)

	var player: Citizen = _new_citizen("Network Command Player")
	world.register_citizen(player)
	player.set_world_ref(world)

	var selection := MockSelectionStateController.new()
	selection.camera_player_target = player
	selection.player_control_active = true
	var session := MockMultiplayerSession.new()
	var interaction = SimulationInteractionControllerScript.new()
	interaction.world = world
	interaction.selection_state_controller = selection
	interaction.multiplayer_session = session
	var toasts := MockToastController.new()
	interaction.bind_toast_controller(toasts)

	interaction.handle_debug_panel_player_action_pressed("rent_home")
	_expect_eq(session.requested_player_actions.size(), 1,
			"network player action should be routed as a command")
	_expect_eq(toasts.messages.size(), 1,
			"network player action should show a request toast")
	var first_action := session.requested_player_actions[0] if session.requested_player_actions.size() > 0 else ""
	_expect_eq(first_action, "rent_home",
			"network player action command should keep the action id")
	_expect(player.home == null, "network controller must not mutate the client replica directly")

	_expect(interaction._try_player_enter_building(), "network R-enter should be handled as a command")
	_expect_eq(session.requested_entity_targets.size(), 1,
			"network R-enter should request one entity interaction")
	_expect_eq(toasts.messages.size(), 2,
			"network R-enter should show a request toast")
	var first_target := session.requested_entity_targets[0] if session.requested_entity_targets.size() > 0 else null
	_expect_eq(first_target, home,
			"network R-enter should target the nearest building")
	_expect(not player.is_inside_building(), "network R-enter must not locally enter the building")

	_expect(interaction._try_player_exit_building(), "network T-exit should be handled as a command")
	_expect_eq(toasts.messages.size(), 3,
			"network T-exit should show a request toast")
	var exit_action := session.requested_player_actions[1] if session.requested_player_actions.size() > 1 else ""
	_expect_eq(exit_action, "exit_building",
			"network T-exit should request an authoritative exit action")

	_free_world(world)
	return _current_error

func _test_multiplayer_host_authority_applies_player_actions() -> String:
	var world: World = _new_world()
	world.minutes_per_tick = 10
	var home: ResidentialBuilding = _new_residential("HostActionHome", Vector3.ZERO, 1)
	var workplace: Building = _new_building("HostActionShop", 1)
	workplace.building_type = BuildingScript.BuildingType.SHOP
	world.register_building(home)
	world.register_building(workplace)

	var player: Citizen = _new_citizen("Host Action Player")
	world.register_citizen(player)
	player.set_world_ref(world)
	player.autonomous_simulation_enabled = true
	player.needs.hunger = 20.0
	player.needs.energy = 100.0
	player.needs.fun = 80.0
	player.needs.health = 100.0

	var authority = MultiplayerHostAuthorityScript.new()
	authority.setup(_harness_root, world, null)
	authority._assign_player_citizen(1)

	_expect(player.player_enter_building(home, world), "host command player should inspect home first")
	authority.handle_local_command({"type": "player_action", "action_id": "rent_home"})
	_expect_eq(player.home, home, "host player_action rent_home should assign home")
	_expect(home.tenants.has(player), "host player_action rent_home should take tenant slot")

	_expect(player.player_exit_building(world), "host command player should leave home before work")
	_expect(player.player_enter_building(workplace, world), "host command player should enter workplace")
	authority.handle_local_command({"type": "player_action", "action_id": "apply_work"})
	_expect(player.job != null and player.job.workplace == workplace,
			"host player_action apply_work should assign the workplace job")
	_expect(workplace.workers.has(player), "host player_action apply_work should take worker slot")
	authority.handle_local_command({"type": "player_action", "action_id": "work"})
	_expect(player.current_action is WorkActionScript,
			"host player_action work should start the explicit work action")

	authority.handle_local_command({"type": "player_action", "action_id": "stop"})
	_expect(player.current_action == null, "host player_action stop should cancel the explicit work action")
	_expect(player.player_exit_building(world), "host command player should leave workplace before shopping")
	var shop: Shop = _new_shop("HostActionInventoryShop", Vector3(4.0, 0.0, 0.0))
	world.register_building(shop)
	world.time.minutes_total = 10 * 60
	player.wallet.balance = 100
	_expect(player.player_enter_building(shop, world), "host command player should enter shop before buying")
	authority.handle_local_command({"type": "player_action", "action_id": "buy_shop_item"})
	_expect_eq(player.clothing_items, 1, "host player_action buy_shop_item should add clothing inventory")

	var status: Dictionary = authority.get_debug_status()
	_expect(int(status.get("accepted_player_action_command_count", 0)) >= 3,
			"host debug should count accepted player action commands")

	_free_world(world)
	return _current_error

func _test_network_snapshot_rebuilds_player_work_and_home_ui() -> String:
	var world: World = _new_world()
	world.minutes_per_tick = 10
	var home: ResidentialBuilding = _new_residential("SnapshotHome", Vector3.ZERO, 1)
	var workplace: Building = _new_building("SnapshotShop", 1)
	workplace.building_type = BuildingScript.BuildingType.SHOP
	world.register_building(home)
	world.register_building(workplace)

	var player: Citizen = _new_citizen("Snapshot Player")
	world.register_citizen(player)
	player.set_world_ref(world)
	player.home_food_stock = 3
	player.needs.hunger = 20.0
	player.needs.energy = 100.0
	player.needs.fun = 80.0
	player.needs.health = 100.0

	_expect(player.player_enter_building(home, world), "snapshot player should inspect home")
	_expect(player.player_rent_home(world), "snapshot player should rent home")
	_expect(player.player_exit_building(world), "snapshot player should leave home")
	_expect(player.player_enter_building(workplace, world), "snapshot player should enter workplace")
	_expect(player.player_apply_for_work(world), "snapshot player should be accepted for work")
	_expect(player.player_work(world), "snapshot player should start work")
	player.work_minutes_today = 45
	player.clothing_items = 2

	var registry = NetworkEntityRegistryScript.new()
	var snapshot := WorldSnapshotSerializerScript.build_snapshot(world, _harness_root, 1, registry)
	var player_id := NetworkEntityRegistryScript.get_entity_id(player)
	var player_entry := _snapshot_entry_by_id(snapshot.get("citizens", []), player_id)
	var building_lookup := WorldSnapshotSerializerScript.build_building_lookup(
			_harness_root,
			snapshot.get("buildings", []) as Array)

	var replica: Citizen = _new_citizen("Snapshot Replica")
	replica.apply_network_snapshot(player_entry, building_lookup)
	var ui_state := replica.get_player_action_ui_state(world)
	_expect_eq(replica.home, home, "replica snapshot should restore player home")
	_expect(replica.job != null and replica.job.workplace == workplace,
			"replica snapshot should restore accepted job")
	_expect_eq(replica.work_minutes_today, 45,
			"replica snapshot should restore worked minutes")
	_expect_eq(replica.clothing_items, 2,
			"replica snapshot should restore player clothing inventory")
	_expect(_player_ui_button_present(ui_state, "work"),
			"replica UI should show Arbeiten after accepted job snapshot")
	_expect(not _player_ui_button_present(ui_state, "apply_work"),
			"replica UI must not show Bewerben after accepted job snapshot")
	_expect(_player_ui_button_enabled(ui_state, "stop"),
			"replica UI should expose stop while work action is active")
	_expect_eq(_info_row_value(replica.get_info_sections(world), "Wohnung"), "SnapshotHome",
			"replica info should show the snapshot home")

	_free_world(world)
	return _current_error

func _test_player_work_education_gate() -> String:
	var world: World = _new_world()
	world.minutes_per_tick = 10
	var uni: University = _new_university("EduGateUni")
	uni.job_capacity = 1
	world.register_building(uni)

	var player: Citizen = _new_citizen("Edu Gate Player")
	world.register_citizen(player)
	player.set_world_ref(world)
	player.autonomous_simulation_enabled = false
	player.keyboard_control_enabled = true

	var required: int = uni.get_required_education_level()
	_expect(player.player_enter_building(uni, world), "player should enter the workplace as a visitor")
	_expect(player.job == null, "entering a workplace must not assign a job")

	if required > 0:
		player.education_level = required - 1
		_expect(not player.player_apply_for_work(world), "under-qualified player must be rejected by application")
		_expect(not uni.workers.has(player), "rejected player must not take a worker slot")
		_expect(player.job == null, "rejected player must not keep a job")
		var rejected_state := player.get_player_action_ui_state(world)
		_expect(str(rejected_state.get("status_text", "")).find("Abgelehnt") != -1,
				"rejection must be shown in the player-action status text")

	player.education_level = required
	_expect(player.player_apply_for_work(world), "qualified application should hire the player")
	_expect(uni.workers.has(player), "qualified application should take the worker slot")
	_expect(player.job != null and player.job.workplace == uni, "qualified application should assign the job")
	_expect(player.player_work(world), "accepted player_work should start work")

	_free_world(world)
	return _current_error

func _test_player_university_unlocks_job() -> String:
	var world: World = _new_world()
	world.minutes_per_tick = 90
	var university: University = _new_university("Player Training Uni")
	var factory: Building = _new_building("Player Training Factory", 1)
	factory.building_type = BuildingScript.BuildingType.FACTORY
	university.job_capacity = 2
	world.register_building(university)
	world.register_building(factory)

	var teacher: Citizen = _new_citizen("Player Training Teacher")
	teacher.job = Job.new()
	teacher.job.title = "Teacher"
	teacher.job.workplace = university
	teacher.job.workplace_service_type = "education"
	_expect(university.try_hire(teacher), "university should have teaching staff for player study")

	var player: Citizen = _new_citizen("Player Trainee")
	world.register_citizen(player)
	player.set_world_ref(world)
	player.autonomous_simulation_enabled = false
	player.keyboard_control_enabled = true
	player.education_level = 0
	player.needs.hunger = 20.0
	player.needs.energy = 100.0
	player.needs.fun = 80.0

	# Enter the factory: visitor only, no job. Technician needs education 1.
	_expect(player.player_enter_building(factory, world), "player should enter the factory as a visitor")
	_expect(player.job == null, "entering the factory must not assign a job")
	_expect(not factory.workers.has(player), "entering must not hire the player")
	_expect_eq(factory.get_default_job_title(), "Technician", "factory job should be the technician role")
	_expect_eq(factory.get_required_education_level(), 1, "technician role should require university education")
	var factory_state := player.get_player_action_ui_state(world)
	_expect(_player_ui_button_enabled(factory_state, "apply_work"), "apply button should stay clickable; the gate is in application")
	_expect(not _player_ui_button_present(factory_state, "work"), "work button should wait until the player is accepted")
	_expect(_player_ui_button_enabled(factory_state, "training"), "factory UI should offer a training exit while under-qualified")

	# Applying while under-qualified is rejected and no job is kept.
	_expect(not player.player_apply_for_work(world), "under-qualified application must be rejected")
	_expect(not factory.workers.has(player), "rejected player must not be hired")
	_expect(player.job == null, "rejected player must not keep a job")
	_expect(player.player_leave_for_training(world), "training button should leave the factory")

	# Study at the university until the requirement is met.
	_expect(player.player_enter_building(university, world), "player should enter the university to study")
	var uni_state := player.get_player_action_ui_state(world)
	_expect(_player_ui_button_enabled(uni_state, "study"), "university UI should expose a study button")
	_expect(player.player_study(world), "study button action should start studying")
	player._agent.sim_tick(player, world)
	_expect(player.education_level >= 1, "study should raise education to the job requirement")
	_expect(player.player_exit_building(world), "player should leave the university after studying")

	# Back at the factory, now qualified -> application accepts, then work starts.
	_expect(player.player_enter_building(factory, world), "player should re-enter the factory")
	_expect(player.player_apply_for_work(world), "qualified application should hire the player")
	_expect(factory.workers.has(player), "qualified application should take the factory worker slot")
	_expect(player.job != null and player.job.workplace == factory, "application should assign the factory job")
	var accepted_factory_state := player.get_player_action_ui_state(world)
	_expect(_player_ui_button_enabled(accepted_factory_state, "work"), "work should appear once the player is accepted")
	_expect(player.player_work(world), "accepted player_work should start the factory job")

	_free_world(world)
	return _current_error

func _test_player_work_payday_uses_worked_minutes() -> String:
	var world: World = _new_world()
	world.minutes_per_tick = 30
	var workplace: Building = _new_building("Payday Shop", 1)
	workplace.building_type = BuildingScript.BuildingType.SHOP
	workplace.account.balance = 1000
	world.register_building(workplace)

	var player: Citizen = _new_citizen("Payday Player")
	world.register_citizen(player)
	player.set_world_ref(world)
	player.autonomous_simulation_enabled = false
	player.keyboard_control_enabled = true
	player.wallet.balance = 100
	player.needs.hunger = 20.0
	player.needs.energy = 100.0
	player.needs.fun = 80.0
	player.needs.health = 100.0

	_expect(player.player_enter_building(workplace, world), "player should enter the workplace")
	_expect(player.player_apply_for_work(world), "player should be accepted before working")
	_expect(player.player_work(world), "accepted player should start work")
	player._agent.sim_tick(player, world)
	player._agent.sim_tick(player, world)
	_expect_eq(player.work_minutes_today, 60, "two 30-minute work ticks should record one hour")

	var wallet_before := player.wallet.balance
	var workplace_before := workplace.account.balance
	var expected_wage := player.job.wage_per_hour
	world._on_payday()
	_expect_eq(player.wallet.balance, wallet_before + expected_wage,
			"payday should pay exactly the wage for worked minutes")
	_expect_eq(workplace.account.balance, workplace_before - expected_wage,
			"workplace should pay only the earned wage")

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

func _new_shop(building_name: String, position: Vector3 = Vector3.ZERO) -> Shop:
	var shop: Shop = ShopScript.new()
	shop.name = building_name
	shop.building_name = building_name
	shop.position = position
	var entrance := Node3D.new()
	entrance.name = "Entrance"
	entrance.position = Vector3(0.0, 0.0, 1.1)
	shop.add_child(entrance)
	_harness_root.add_child(shop)
	shop.job_capacity = 0
	if shop.get_stock("clothing") <= 0:
		shop.define_stock_item("clothing", 8, shop.item_price, 12, 4, "clothes")
	return shop

func _new_cinema(building_name: String, position: Vector3 = Vector3.ZERO) -> Cinema:
	var cinema: Cinema = CinemaScript.new()
	cinema.name = building_name
	cinema.building_name = building_name
	cinema.position = position
	var entrance := Node3D.new()
	entrance.name = "Entrance"
	entrance.position = Vector3(0.0, 0.0, 1.1)
	cinema.add_child(entrance)
	_harness_root.add_child(cinema)
	cinema.job_capacity = 0
	return cinema

func _new_supermarket(building_name: String, position: Vector3 = Vector3.ZERO) -> Supermarket:
	var market: Supermarket = SupermarketScript.new()
	market.name = building_name
	market.building_name = building_name
	market.position = position
	var entrance := Node3D.new()
	entrance.name = "Entrance"
	entrance.position = Vector3(0.0, 0.0, 1.1)
	market.add_child(entrance)
	_harness_root.add_child(market)
	market.job_capacity = 0
	if market.get_stock("clothing") <= 0:
		market.define_stock_item("clothing", 8, market.clothing_price, 12, 4, "clothes")
	if market.get_stock("grocery_bundle") <= 0:
		market.define_stock_item("grocery_bundle", 8, market.grocery_price, 12, 4, "food")
	return market

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

func _player_ui_button_enabled(ui_state: Dictionary, action_id: String) -> bool:
	var buttons: Array = ui_state.get("buttons", [])
	for spec_var in buttons:
		if spec_var is not Dictionary:
			continue
		var spec := spec_var as Dictionary
		if str(spec.get("id", "")) == action_id:
			return bool(spec.get("enabled", false))
	# Inventory state uses a categories[].items[] layout where the button id
	# lives in each item's "action_id" field; consult it as a secondary source.
	for cat_var in ui_state.get("categories", []):
		if cat_var is not Dictionary:
			continue
		for item_var in (cat_var as Dictionary).get("items", []):
			if item_var is not Dictionary:
				continue
			var item := item_var as Dictionary
			if str(item.get("action_id", "")) == action_id:
				return bool(item.get("enabled", false))
	return false

func _player_ui_button_present(ui_state: Dictionary, action_id: String) -> bool:
	var buttons: Array = ui_state.get("buttons", [])
	for spec_var in buttons:
		if spec_var is not Dictionary:
			continue
		if str((spec_var as Dictionary).get("id", "")) == action_id:
			return true
	for cat_var in ui_state.get("categories", []):
		if cat_var is not Dictionary:
			continue
		for item_var in (cat_var as Dictionary).get("items", []):
			if item_var is Dictionary and str((item_var as Dictionary).get("action_id", "")) == action_id:
				return true
	return false

func _player_ui_button_text(ui_state: Dictionary, action_id: String) -> String:
	var buttons: Array = ui_state.get("buttons", [])
	for spec_var in buttons:
		if spec_var is not Dictionary:
			continue
		var spec := spec_var as Dictionary
		if str(spec.get("id", "")) == action_id:
			return str(spec.get("text", ""))
	return ""

func _info_row_value(sections: Array, label: String) -> String:
	for section_var in sections:
		if section_var is not Dictionary:
			continue
		var rows: Array = (section_var as Dictionary).get("rows", [])
		for row_var in rows:
			if row_var is not Dictionary:
				continue
			var row := row_var as Dictionary
			if str(row.get("label", "")) == label:
				return str(row.get("value", ""))
	return ""

func _snapshot_entry_by_id(entries: Variant, entity_id: String) -> Dictionary:
	if entries is not Array:
		return {}
	for entry_var in entries as Array:
		if entry_var is not Dictionary:
			continue
		var entry := entry_var as Dictionary
		if str(entry.get("id", "")) == entity_id:
			return entry
	return {}

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
