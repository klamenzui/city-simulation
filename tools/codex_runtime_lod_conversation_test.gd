extends SceneTree

const CitizenScript = preload("res://Entities/Citizens/Citizen.gd")
const ResidentialBuildingScript = preload("res://Entities/Buildings/ResidentialBuilding.gd")
const RestaurantScript = preload("res://Entities/Buildings/Restaurant.gd")
const WorldScript = preload("res://Simulation/World.gd")
const ActionScript = preload("res://Actions/Action.gd")
const CitizenSimulationLodControllerScript = preload("res://Simulation/Citizens/CitizenSimulationLodController.gd")
const CitizenConversationManagerScript = preload("res://Simulation/Conversation/CitizenConversationManager.gd")
const LocalDialogueRuntimeServiceScript = preload("res://Simulation/AI/LocalDialogueRuntimeService.gd")
const SimulationInteractionControllerScript = preload("res://Simulation/UI/SimulationInteractionController.gd")

class MockSelectionStateController:
	extends RefCounted

	var selected_citizen: Citizen = null
	var controlled_citizen: Citizen = null
	var player_avatar: Citizen = null
	var player_control_active: bool = false
	var player_control_input_locked: bool = false
	var selected_building: Building = null

	func get_selected_citizen() -> Citizen:
		return selected_citizen if selected_citizen != null and is_instance_valid(selected_citizen) else null

	func get_selected_building() -> Building:
		return selected_building if selected_building != null and is_instance_valid(selected_building) else null

	func get_controlled_citizen() -> Citizen:
		return controlled_citizen if controlled_citizen != null and is_instance_valid(controlled_citizen) else null

	func get_player_avatar() -> Citizen:
		return player_avatar if player_avatar != null and is_instance_valid(player_avatar) else null

	func is_player_control_active() -> bool:
		var avatar := get_player_avatar()
		return player_control_active and avatar != null

	func set_player_control_input_locked(locked: bool) -> void:
		player_control_input_locked = locked
		var avatar := get_player_avatar()
		if avatar != null and avatar.has_method("set_manual_control_input_locked"):
			avatar.set_manual_control_input_locked(locked)

	func is_player_control_input_locked() -> bool:
		return player_control_input_locked

	func is_citizen_click_move_active() -> bool:
		return false

	func handle_citizen_clicked(citizen: Citizen) -> void:
		selected_citizen = citizen
		selected_building = null

	func refresh_debug_panel_mode_controls() -> void:
		pass

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
		"coarse_scheduler_only_ticks_due_slots",
		"conversation_manager_clears_stale_player_interest",
		"conversation_manager_respects_materialize_hysteresis",
		"conversation_start_rules_block_low_social_smalltalk",
		"conversation_start_rules_allow_scheduled_meeting_pair",
		"lod_controller_keeps_dialog_participants_active",
		"lod_controller_applies_runtime_profile_knobs",
		"lod_controller_uses_route_and_hotspot_relevance",
		"world_district_index_supports_lod_same_district_relevance",
		"materialized_conversation_gets_template_lines_from_dialogue_runtime",
		"player_dialog_session_gets_template_reply",
		"player_dialog_ui_state_switches_to_active_session",
		"dialog_interact_starts_nearest_player_dialog_and_faces_citizen",
		"player_dialog_queue_full_uses_template_reply",
		"player_dialog_prioritizes_over_warmup_queue",
		"player_dialog_locks_player_input",
		"player_dialog_pauses_citizen_action_while_active",
		"player_dialog_farewell_auto_closes",
		"player_dialog_template_farewell_reply_is_brief",
		"player_dialog_payload_includes_grounded_world_facts",
		"player_dialog_request_uses_json_profile_options",
		"dialogue_runtime_prefers_local_profile_models",
		"player_dialog_memory_summary_compacts_transcript",
		"player_dialog_json_parser_avoids_verbatim_repeat",
		"bark_mode_uses_topic_fallback_lines",
		"player_dialog_respects_interactive_budget",
		"dialogue_runtime_ui_state_prefers_setup_when_model_missing",
		"multilayer_residential_corner_rejects_blocked_slide_cache",
		"street_furniture_uses_soft_obstacle_layer",
	]:
		var error := _run_test(test_name)
		if error != "":
			failed.append("%s: %s" % [test_name, error])

	if is_instance_valid(_harness_root):
		_harness_root.free()

	if failed.is_empty():
		print("RUNTIME_TEST OK checks=%d" % _checks_run)
		quit(0)
		return

	for failure in failed:
		push_error(failure)
	print("RUNTIME_TEST FAIL count=%d" % failed.size())
	quit(1)

func _run_test(test_name: String) -> String:
	_current_error = ""
	_reset_harness_root()
	match test_name:
		"coarse_scheduler_only_ticks_due_slots":
			return _test_coarse_scheduler_only_ticks_due_slots()
		"conversation_manager_clears_stale_player_interest":
			return _test_conversation_manager_clears_stale_player_interest()
		"conversation_manager_respects_materialize_hysteresis":
			return _test_conversation_manager_respects_materialize_hysteresis()
		"conversation_start_rules_block_low_social_smalltalk":
			return _test_conversation_start_rules_block_low_social_smalltalk()
		"conversation_start_rules_allow_scheduled_meeting_pair":
			return _test_conversation_start_rules_allow_scheduled_meeting_pair()
		"lod_controller_keeps_dialog_participants_active":
			return _test_lod_controller_keeps_dialog_participants_active()
		"lod_controller_applies_runtime_profile_knobs":
			return _test_lod_controller_applies_runtime_profile_knobs()
		"lod_controller_uses_route_and_hotspot_relevance":
			return _test_lod_controller_uses_route_and_hotspot_relevance()
		"world_district_index_supports_lod_same_district_relevance":
			return _test_world_district_index_supports_lod_same_district_relevance()
		"materialized_conversation_gets_template_lines_from_dialogue_runtime":
			return _test_materialized_conversation_gets_template_lines_from_dialogue_runtime()
		"player_dialog_session_gets_template_reply":
			return _test_player_dialog_session_gets_template_reply()
		"player_dialog_ui_state_switches_to_active_session":
			return _test_player_dialog_ui_state_switches_to_active_session()
		"dialog_interact_starts_nearest_player_dialog_and_faces_citizen":
			return _test_dialog_interact_starts_nearest_player_dialog_and_faces_citizen()
		"player_dialog_queue_full_uses_template_reply":
			return _test_player_dialog_queue_full_uses_template_reply()
		"player_dialog_prioritizes_over_warmup_queue":
			return _test_player_dialog_prioritizes_over_warmup_queue()
		"player_dialog_locks_player_input":
			return _test_player_dialog_locks_player_input()
		"player_dialog_pauses_citizen_action_while_active":
			return _test_player_dialog_pauses_citizen_action_while_active()
		"player_dialog_farewell_auto_closes":
			return _test_player_dialog_farewell_auto_closes()
		"player_dialog_template_farewell_reply_is_brief":
			return _test_player_dialog_template_farewell_reply_is_brief()
		"player_dialog_payload_includes_grounded_world_facts":
			return _test_player_dialog_payload_includes_grounded_world_facts()
		"player_dialog_request_uses_json_profile_options":
			return _test_player_dialog_request_uses_json_profile_options()
		"dialogue_runtime_prefers_local_profile_models":
			return _test_dialogue_runtime_prefers_local_profile_models()
		"player_dialog_memory_summary_compacts_transcript":
			return _test_player_dialog_memory_summary_compacts_transcript()
		"player_dialog_json_parser_avoids_verbatim_repeat":
			return _test_player_dialog_json_parser_avoids_verbatim_repeat()
		"bark_mode_uses_topic_fallback_lines":
			return _test_bark_mode_uses_topic_fallback_lines()
		"player_dialog_respects_interactive_budget":
			return _test_player_dialog_respects_interactive_budget()
		"dialogue_runtime_ui_state_prefers_setup_when_model_missing":
			return _test_dialogue_runtime_ui_state_prefers_setup_when_model_missing()
		"multilayer_residential_corner_rejects_blocked_slide_cache":
			return _test_multilayer_residential_corner_rejects_blocked_slide_cache()
		"street_furniture_uses_soft_obstacle_layer":
			return _test_street_furniture_uses_soft_obstacle_layer()
		_:
			return "unknown test"

func _test_coarse_scheduler_only_ticks_due_slots() -> String:
	var world := _new_world()
	var citizen := _new_citizen("Coarse Citizen")
	world.register_citizen(citizen)
	citizen.current_action = ActionScript.new(999)
	citizen.set_simulation_lod_state("coarse", false, false, 5)
	citizen._simulation_lod_tick_phase_seed = 0
	world.notify_citizen_lod_changed(citizen)

	_expect_eq(world.get_citizen_simulation_minutes_until_due(citizen), 4, "coarse citizen should report the next scheduled tick in 4 minutes")

	for _i in range(4):
		world._on_tick()
	_expect_eq(citizen.current_action.elapsed_minutes, 0, "coarse scheduler should not tick the citizen before its scheduled slot")

	world._on_tick()
	_expect_eq(citizen.current_action.elapsed_minutes, 1, "coarse scheduler should tick the citizen on its scheduled slot")

	for _i in range(5):
		world._on_tick()
	_expect_eq(citizen.current_action.elapsed_minutes, 2, "coarse scheduler should continue ticking only on later scheduled slots")

	_free_world(world)
	return _current_error

func _test_conversation_manager_clears_stale_player_interest() -> String:
	var world := _new_world()
	var camera := _new_camera(Vector3(0.0, 10.0, 16.0), Vector3.ZERO)
	var selection := MockSelectionStateController.new()
	var citizen_a := _new_citizen("Selected A", Vector3(0.0, 0.0, 0.0))
	var citizen_b := _new_citizen("Selected B", Vector3(2.0, 0.0, 0.0))
	world.register_citizen(citizen_a)
	world.register_citizen(citizen_b)

	var manager = CitizenConversationManagerScript.new()
	manager.setup(world, camera, selection)

	selection.selected_citizen = citizen_a
	manager.update(1.0)
	_expect(citizen_a.has_active_lod_commitment(world, ["player_interest"]), "selected citizen should receive a player_interest commitment")
	_expect(not citizen_b.has_active_lod_commitment(world, ["player_interest"]), "non-selected citizen should not receive the selection commitment")

	selection.selected_citizen = citizen_b
	manager.update(1.0)
	_expect(not citizen_a.has_active_lod_commitment(world, ["player_interest"]), "previously selected citizen should lose stale player_interest")
	_expect(citizen_b.has_active_lod_commitment(world, ["player_interest"]), "newly selected citizen should receive player_interest")

	_free_world(world)
	return _current_error

func _test_conversation_manager_respects_materialize_hysteresis() -> String:
	var world := _new_world()
	var camera := _new_camera(Vector3(0.0, 10.0, 14.0), Vector3.ZERO)
	var selection := MockSelectionStateController.new()
	var player_avatar := _new_citizen("Player Proxy", Vector3(0.0, 0.0, 0.0))
	var citizen_a := _new_citizen("Talker A", Vector3(7.5, 0.0, 0.0))
	var citizen_b := _new_citizen("Talker B", Vector3(7.5, 0.0, 1.0))
	world.register_citizen(citizen_a)
	world.register_citizen(citizen_b)
	selection.player_avatar = player_avatar
	selection.player_control_active = true

	var manager = CitizenConversationManagerScript.new()
	manager.setup(world, camera, selection)

	manager.update(1.0)
	var conversation := _get_single_conversation(manager.get_active_conversations())
	_expect_eq(str(conversation.get("mode", "")), "materialized", "conversation should materialize when the player is very near")

	player_avatar.global_position = Vector3(-2.0, 0.0, 0.0)
	manager.update(1.0)
	conversation = _get_single_conversation(manager.get_active_conversations())
	_expect_eq(str(conversation.get("mode", "")), "materialized", "conversation should stay materialized until the materialize exit threshold is crossed")

	player_avatar.global_position = Vector3(-5.0, 0.0, 0.0)
	manager.update(1.0)
	conversation = _get_single_conversation(manager.get_active_conversations())
	_expect_eq(str(conversation.get("mode", "")), "bark", "conversation should downgrade to bark after leaving the materialize hysteresis window")

	_free_world(world)
	return _current_error

func _test_conversation_start_rules_block_low_social_smalltalk() -> String:
	var world := _new_world()
	var camera := _new_camera(Vector3(0.0, 10.0, 16.0), Vector3.ZERO)
	var selection := MockSelectionStateController.new()
	var citizen_a := _new_citizen("Quiet A", Vector3(0.0, 0.0, 0.0))
	var citizen_b := _new_citizen("Quiet B", Vector3(2.0, 0.0, 0.0))
	world.register_citizen(citizen_a)
	world.register_citizen(citizen_b)

	citizen_a.needs.fun = 92.0
	citizen_b.needs.fun = 95.0
	citizen_a.needs.hunger = 5.0
	citizen_b.needs.hunger = 5.0
	citizen_a.needs.energy = 95.0
	citizen_b.needs.energy = 95.0

	var manager = CitizenConversationManagerScript.new()
	manager.setup(world, camera, selection)
	manager.update(1.0)

	_expect_eq(manager.get_active_conversations().size(), 0, "smalltalk should not start when both citizens have low social need")

	_free_world(world)
	return _current_error

func _test_conversation_start_rules_allow_scheduled_meeting_pair() -> String:
	var world := _new_world()
	var camera := _new_camera(Vector3(0.0, 10.0, 16.0), Vector3.ZERO)
	var selection := MockSelectionStateController.new()
	var citizen_a := _new_citizen("Meeting A", Vector3(0.0, 0.0, 0.0))
	var citizen_b := _new_citizen("Meeting B", Vector3(2.0, 0.0, 0.0))
	world.register_citizen(citizen_a)
	world.register_citizen(citizen_b)

	citizen_a.needs.fun = 95.0
	citizen_b.needs.fun = 96.0
	citizen_a.needs.hunger = 92.0
	citizen_b.needs.energy = 8.0

	var future := _future_time(world, 45)
	citizen_a.upsert_lod_commitment("meeting", int(future.get("day", 1)), int(future.get("minute", 0)), 1.0, {
		"meeting_key": "after_work_food",
		"topic": "food"
	})
	citizen_b.upsert_lod_commitment("meeting", int(future.get("day", 1)), int(future.get("minute", 0)), 1.0, {
		"meeting_key": "after_work_food",
		"topic": "food"
	})

	var manager = CitizenConversationManagerScript.new()
	manager.setup(world, camera, selection)
	manager.update(1.0)

	var conversation := _get_single_conversation(manager.get_active_conversations())
	_expect_eq(str(conversation.get("start_mode", "")), "committed_meeting", "scheduled meetings should use the committed meeting start mode")
	_expect_eq(str(conversation.get("topic", "")), "food", "scheduled meetings should preserve their configured topic")

	_free_world(world)
	return _current_error

func _test_lod_controller_keeps_dialog_participants_active() -> String:
	var world := _new_world()
	var camera := _new_camera(Vector3(0.0, 12.0, 18.0), Vector3.ZERO)
	var selection := MockSelectionStateController.new()
	var citizen_a := _new_citizen("Meeting A", Vector3(200.0, 0.0, 0.0))
	var citizen_b := _new_citizen("Meeting B", Vector3(202.0, 0.0, 0.0))
	var citizen_c := _new_citizen("Remote C", Vector3(320.0, 0.0, 0.0))
	var citizen_c_home := _new_residential("Remote C Home", Vector3(320.0, 0.0, 0.0))
	world.register_citizen(citizen_a)
	world.register_citizen(citizen_b)
	world.register_citizen(citizen_c)
	world.register_building(citizen_c_home)
	citizen_c.home = citizen_c_home
	citizen_c.current_location = citizen_c_home
	citizen_c._home_rotation_candidate_day = world.world_day() - 1

	var future := _future_time(world, 30)
	citizen_a.upsert_lod_commitment("meeting", int(future.get("day", 1)), int(future.get("minute", 0)), 1.0)
	citizen_b.upsert_lod_commitment("meeting", int(future.get("day", 1)), int(future.get("minute", 0)), 1.0)

	var lod_controller = CitizenSimulationLodControllerScript.new()
	lod_controller.setup(world, camera, selection)
	lod_controller.update(1.0)

	_expect_eq(citizen_a.get_simulation_lod_tier(), "active", "meeting participant A should stay active even when far away")
	_expect_eq(citizen_b.get_simulation_lod_tier(), "active", "meeting participant B should stay active even when far away")
	_expect_eq(citizen_c.get_simulation_lod_tier(), "coarse", "irrelevant far citizen should drop to coarse")

	_free_world(world)
	return _current_error

func _test_lod_controller_applies_runtime_profile_knobs() -> String:
	var world := _new_world()
	var camera := _new_camera(Vector3(0.0, 12.0, 18.0), Vector3.ZERO)
	var selection := MockSelectionStateController.new()
	var focus_citizen := _new_citizen("Focus Citizen", Vector3(0.0, 0.0, 0.0))
	var active_citizen := _new_citizen("Active Citizen", Vector3(180.0, 0.0, 0.0))
	var partner_citizen := _new_citizen("Partner Citizen", Vector3(182.0, 0.0, 0.0))
	world.register_citizen(focus_citizen)
	world.register_citizen(active_citizen)
	world.register_citizen(partner_citizen)
	selection.selected_citizen = focus_citizen

	var future := _future_time(world, 30)
	active_citizen.upsert_lod_commitment("meeting", int(future.get("day", 1)), int(future.get("minute", 0)), 1.0)
	partner_citizen.upsert_lod_commitment("meeting", int(future.get("day", 1)), int(future.get("minute", 0)), 1.0)

	var lod_controller = CitizenSimulationLodControllerScript.new()
	lod_controller.setup(world, camera, selection)
	lod_controller.update(1.0)

	_expect_eq(focus_citizen.get_simulation_lod_tier(), "focus", "selected citizen should stay in focus tier")
	_expect(not focus_citizen._is_eligible_for_cheap_lod(), "focus tier should force full navigation instead of cheap path follow")

	_expect_eq(active_citizen.get_simulation_lod_tier(), "active", "meeting citizen should use active tier")
	_expect_eq(active_citizen.local_navigation_raycast_checks_enabled, false, "active tier should disable local raycast avoidance")
	_expect_eq(snappedf(active_citizen.repath_interval_sec, 0.1), 1.5, "active tier should apply the configured path refresh interval")
	_expect_eq(active_citizen.get_simulation_lod_decision_cooldown_range_minutes(world), Vector2i(7, 9), "active tier should apply the configured decision cadence")
	_expect(active_citizen._is_eligible_for_cheap_lod(), "active tier should use cheap path follow")

	_free_world(world)
	return _current_error

func _test_lod_controller_uses_route_and_hotspot_relevance() -> String:
	var world := _new_world()
	var camera := _new_camera(Vector3(0.0, 10.0, -10.0), Vector3(0.0, 0.0, 10.0))
	var selection := MockSelectionStateController.new()
	var route_owner := _new_citizen("Route Owner", Vector3.ZERO)
	var route_citizen := _new_citizen("Route Citizen", Vector3(10.0, 0.0, 0.0))
	var route_baseline := _new_citizen("Route Baseline", Vector3(0.0, 0.0, 10.0))
	var hotspot_citizen := _new_citizen("Hotspot Citizen", Vector3(0.0, 0.0, 6.0))
	var hotspot_baseline := _new_citizen("Hotspot Baseline", Vector3(6.0, 0.0, 0.0))
	world.register_citizen(route_owner)
	world.register_citizen(route_citizen)
	world.register_citizen(route_baseline)
	world.register_citizen(hotspot_citizen)
	world.register_citizen(hotspot_baseline)
	selection.selected_citizen = route_owner

	route_owner._is_travelling = true
	route_owner._travel_route = PackedVector3Array([
		Vector3.ZERO,
		Vector3(10.0, 0.0, 0.0),
		Vector3(20.0, 0.0, 0.0)
	])
	route_owner._debug_last_travel_route = route_owner._travel_route
	route_owner._travel_route_index = 1
	route_owner._travel_target = Vector3(10.0, 0.0, 0.0)

	var lod_controller = CitizenSimulationLodControllerScript.new()
	lod_controller.setup(world, camera, selection)
	var route_context := lod_controller._build_relevance_context(route_owner.global_position, null, null, route_owner, false)

	_expect(lod_controller._is_near_predicted_route(route_citizen, route_context), "route citizen should be recognized as near the selected route")
	_expect(not lod_controller._is_near_predicted_route(route_baseline, route_context), "baseline citizen should stay outside the selected route influence")

	var route_score := float(lod_controller._score_citizen(route_citizen, route_context, route_owner, null))
	var route_baseline_score := float(lod_controller._score_citizen(route_baseline, route_context, route_owner, null))
	_expect(route_score > route_baseline_score, "route relevance should increase the score of citizens near the predicted route")

	route_owner._is_travelling = false
	var hotspot_context := lod_controller._build_relevance_context(route_owner.global_position, null, null, route_owner, false)
	_expect(lod_controller._is_near_camera_hotspot(hotspot_citizen.global_position, hotspot_context), "hotspot citizen should be recognized near the camera hotspot")
	_expect(not lod_controller._is_near_camera_hotspot(hotspot_baseline.global_position, hotspot_context), "baseline citizen should stay outside the camera hotspot")

	var hotspot_score := float(lod_controller._score_citizen(hotspot_citizen, hotspot_context, route_owner, null))
	var hotspot_baseline_score := float(lod_controller._score_citizen(hotspot_baseline, hotspot_context, route_owner, null))
	_expect(hotspot_score > hotspot_baseline_score, "camera hotspot relevance should increase the score near the current camera focus")

	_free_world(world)
	return _current_error

func _test_world_district_index_supports_lod_same_district_relevance() -> String:
	var world := _new_world()
	var camera := _new_camera(Vector3(0.0, 10.0, -10.0), Vector3(0.0, 0.0, -20.0))
	var selection := MockSelectionStateController.new()
	var anchor_citizen := _new_citizen("Anchor Citizen", Vector3(7.0, 0.0, 0.0))
	var same_district_citizen := _new_citizen("Same District", Vector3(3.0, 0.0, 0.0))
	var other_district_citizen := _new_citizen("Other District", Vector3(11.0, 0.0, 0.0))
	world.register_citizen(anchor_citizen)
	world.register_citizen(same_district_citizen)
	world.register_citizen(other_district_citizen)
	selection.selected_citizen = anchor_citizen

	var anchor_district := world.get_district_id_for_position(anchor_citizen.global_position)
	var same_district := world.get_district_id_for_position(same_district_citizen.global_position)
	var other_district := world.get_district_id_for_position(other_district_citizen.global_position)
	_expect_eq(anchor_district, same_district, "nearby citizen should stay in the same district cell as the anchor")
	_expect(anchor_district != other_district, "citizen across the district border should resolve to a different district")

	var lod_controller = CitizenSimulationLodControllerScript.new()
	lod_controller.setup(world, camera, selection)
	var relevance_context := lod_controller._build_relevance_context(anchor_citizen.global_position, null, null, anchor_citizen, false)

	_expect(lod_controller._is_in_anchor_district(same_district_citizen.global_position, relevance_context), "same-district citizen should be recognized by the LOD context")
	_expect(not lod_controller._is_in_anchor_district(other_district_citizen.global_position, relevance_context), "cross-border citizen should not count as same-district")

	var same_score := float(lod_controller._score_citizen(same_district_citizen, relevance_context, anchor_citizen, null))
	var other_score := float(lod_controller._score_citizen(other_district_citizen, relevance_context, anchor_citizen, null))
	_expect(same_score > other_score, "same-district relevance should increase the LOD score when distance is otherwise equal")

	_free_world(world)
	return _current_error

func _test_materialized_conversation_gets_template_lines_from_dialogue_runtime() -> String:
	var world := _new_world()
	var camera := _new_camera(Vector3(0.0, 10.0, 14.0), Vector3.ZERO)
	var selection := MockSelectionStateController.new()
	var player_avatar := _new_citizen("Player Proxy", Vector3(0.0, 0.0, 0.0))
	var citizen_a := _new_citizen("Template A", Vector3(7.0, 0.0, 0.0))
	var citizen_b := _new_citizen("Template B", Vector3(7.0, 0.0, 1.1))
	world.register_citizen(citizen_a)
	world.register_citizen(citizen_b)
	selection.player_avatar = player_avatar
	selection.player_control_active = true

	var dialogue_runtime = LocalDialogueRuntimeServiceScript.new()
	_harness_root.add_child(dialogue_runtime)
	dialogue_runtime.setup({
		"runtime": {
			"force_template_mode": true
		},
		"startup": {
			"auto_start_on_game_boot": false,
			"disabled_in_headless": false
		}
	}, false)

	var manager = CitizenConversationManagerScript.new()
	manager.setup(world, camera, selection)
	manager.bind_dialogue_runtime(dialogue_runtime)
	manager.update(1.0)

	var conversation := _get_single_conversation(manager.get_active_conversations())
	var lines: Array = conversation.get("generated_lines", [])
	_expect_eq(str(conversation.get("dialogue_source", "")), "template", "materialized conversation should use template dialogue when runtime is in template mode")
	_expect(lines.size() >= 2, "materialized conversation should expose at least two generated lines")
	_expect(str(lines[0]).contains("Template A") or str(lines[0]).contains("Template B"), "template dialogue should reference participant names")

	_free_world(world)
	return _current_error

func _test_player_dialog_session_gets_template_reply() -> String:
	var world := _new_world()
	var camera := _new_camera(Vector3(0.0, 10.0, 14.0), Vector3.ZERO)
	var selection := MockSelectionStateController.new()
	var player_avatar := _new_citizen("Player", Vector3(0.0, 0.0, 0.0))
	var citizen := _new_citizen("Kevin", Vector3(1.5, 0.0, 0.0))
	world.register_citizen(player_avatar)
	world.register_citizen(citizen)
	selection.player_avatar = player_avatar
	selection.player_control_active = true
	selection.controlled_citizen = player_avatar
	selection.selected_citizen = citizen

	var dialogue_runtime = LocalDialogueRuntimeServiceScript.new()
	_harness_root.add_child(dialogue_runtime)
	dialogue_runtime.setup({
		"runtime": {
			"force_template_mode": true
		},
		"startup": {
			"auto_start_on_game_boot": false,
			"disabled_in_headless": false
		}
	}, false)

	var manager = CitizenConversationManagerScript.new()
	manager.setup(world, camera, selection)
	manager.bind_dialogue_runtime(dialogue_runtime)
	manager.update(1.0)

	var availability := manager.get_player_dialog_availability(citizen)
	_expect(bool(availability.get("available", false)), "player dialog should be available when the player avatar is nearby")

	var started_session := manager.begin_player_dialog(citizen)
	_expect(bool(started_session.get("active", false)), "begin_player_dialog should activate the session")

	var updated_session := manager.submit_player_dialog_message(citizen, "Wie geht's?")
	var messages: Array = updated_session.get("messages", [])
	_expect_eq(messages.size(), 2, "template player dialogue should append a citizen reply immediately")
	if messages.size() >= 2:
		var citizen_line := messages[1] as Dictionary
		_expect_eq(str(citizen_line.get("speaker", "")), "Kevin", "player dialogue reply should use the citizen name as speaker")
		_expect(not str(citizen_line.get("text", "")).begins_with("Kevin says:"), "template reply should not duplicate the speaker label in the message text")
		_expect(not str(citizen_line.get("text", "")).strip_edges().is_empty(), "template reply text should not be empty")

	_free_world(world)
	return _current_error

func _test_player_dialog_ui_state_switches_to_active_session() -> String:
	var world := _new_world()
	var camera := _new_camera(Vector3(0.0, 10.0, 14.0), Vector3.ZERO)
	var selection := MockSelectionStateController.new()
	var player_avatar := _new_citizen("Player", Vector3(0.0, 0.0, 0.0))
	var citizen := _new_citizen("Kevin", Vector3(1.5, 0.0, 0.0))
	world.register_citizen(player_avatar)
	world.register_citizen(citizen)
	selection.player_avatar = player_avatar
	selection.player_control_active = true
	selection.controlled_citizen = player_avatar
	selection.selected_citizen = citizen

	var manager = CitizenConversationManagerScript.new()
	manager.setup(world, camera, selection)
	manager.update(1.0)

	var idle_ui := manager.get_player_dialog_ui_state(citizen)
	_expect(bool(idle_ui.get("visible", false)), "selected citizen should expose the dialog controls in the UI")
	_expect(bool(idle_ui.get("button_enabled", false)), "dialog button should be enabled when player mode is active and the citizen is nearby")
	_expect_eq(str(idle_ui.get("button_text", "")), "Start Dialog", "inactive UI should offer to start the dialog")
	_expect_eq(str(idle_ui.get("status_text", "")), "Ready to talk", "inactive UI should describe ready dialog state")

	var started_session := manager.begin_player_dialog(citizen)
	_expect(bool(started_session.get("active", false)), "begin_player_dialog should activate the session for the UI")

	var active_ui := manager.get_player_dialog_ui_state(citizen)
	_expect_eq(str(active_ui.get("button_text", "")), "End Dialog", "active dialog UI should offer ending the session")
	_expect(bool(active_ui.get("log_visible", false)), "active dialog UI should show the chat log")
	_expect(bool(active_ui.get("input_visible", false)), "active dialog UI should show the message input")
	_expect(bool(active_ui.get("input_enabled", false)), "active dialog UI should keep input enabled without pending reply")

	_free_world(world)
	return _current_error

func _test_dialog_interact_starts_nearest_player_dialog_and_faces_citizen() -> String:
	var world := _new_world()
	var camera := _new_camera(Vector3(0.0, 10.0, 14.0), Vector3.ZERO)
	var selection := MockSelectionStateController.new()
	var player_avatar := _new_citizen("Player", Vector3.ZERO)
	var far_selected := _new_citizen("Far Selected", Vector3(8.0, 0.0, 0.0))
	var nearby_citizen := _new_citizen("Nearby Citizen", Vector3(1.5, 0.0, 0.5))
	world.register_citizen(player_avatar)
	world.register_citizen(far_selected)
	world.register_citizen(nearby_citizen)
	selection.player_avatar = player_avatar
	selection.controlled_citizen = player_avatar
	selection.player_control_active = true
	selection.selected_citizen = far_selected
	player_avatar.set_manual_control_enabled(true, world)

	var manager = CitizenConversationManagerScript.new()
	manager.setup(world, camera, selection)

	var interaction_controller = SimulationInteractionControllerScript.new()
	interaction_controller.setup(_harness_root, world)
	interaction_controller.bind_selection_state(selection, null)
	interaction_controller.bind_conversation_manager(manager)

	var interact_event := InputEventAction.new()
	interact_event.action = "dialog_interact"
	interact_event.pressed = true

	var handled := interaction_controller.handle_input(interact_event)
	_expect(handled, "dialog interact action should be consumed when a nearby citizen can talk")
	_expect_eq(selection.get_selected_citizen(), nearby_citizen, "dialog interact should retarget selection to the nearest talkable citizen")

	var session := manager.get_player_dialog_session(nearby_citizen)
	_expect(bool(session.get("active", false)), "dialog interact should start a player dialog for the nearest citizen")

	var facing_dir := (player_avatar.global_position - nearby_citizen.global_position)
	facing_dir.y = 0.0
	var expected_yaw := atan2(-facing_dir.normalized().x, -facing_dir.normalized().z)
	_expect(abs(wrapf(nearby_citizen.rotation.y - expected_yaw, -PI, PI)) < 0.01, "nearby citizen should face the player when the dialog starts")

	if interaction_controller.debug_panel != null and is_instance_valid(interaction_controller.debug_panel):
		interaction_controller.debug_panel.queue_free()
	interaction_controller.debug_panel = null
	_free_world(world)
	return _current_error

func _test_player_dialog_queue_full_uses_template_reply() -> String:
	var runtime_service = LocalDialogueRuntimeServiceScript.new()
	_harness_root.add_child(runtime_service)
	runtime_service.setup({
		"runtime": {
			"force_template_mode": false,
			"max_queue_size": 2
		},
		"startup": {
			"auto_start_on_game_boot": false,
			"disabled_in_headless": false
		},
		"fallback": {
			"on_queue_full": "use_template"
		}
	}, false)
	runtime_service._status = "ready"
	runtime_service._models_by_profile["player_npc"] = "qwen2.5:3b"
	runtime_service._job_queue = [
		{"kind": "npc_npc", "key": "conv_a"},
		{"kind": "npc_npc", "key": "conv_b"}
	]

	var reply := runtime_service.request_player_reply("player_test_turn_1", {
		"name": "Kevin",
		"mood": "calm",
		"current_goal": "walking home",
		"last_turns": [
			{
				"speaker": "Player",
				"text": "Where are you going?"
			}
		]
	})
	_expect_eq(str(reply.get("state", "")), "ready", "queue-full player dialogue should fall back immediately instead of hanging pending")
	_expect_eq(str(reply.get("source", "")), "template", "queue-full player dialogue should use template fallback")
	_expect(not str(reply.get("text", "")).begins_with("Kevin says:"), "template fallback should not hardcode the speaker prefix into the reply text")
	_expect(not str(reply.get("text", "")).strip_edges().is_empty(), "template fallback should still return a usable reply")

	runtime_service.queue_free()
	return _current_error

func _test_player_dialog_prioritizes_over_warmup_queue() -> String:
	var runtime_service = LocalDialogueRuntimeServiceScript.new()
	_harness_root.add_child(runtime_service)
	runtime_service.setup({
		"runtime": {
			"force_template_mode": false,
			"max_queue_size": 2
		},
		"startup": {
			"auto_start_on_game_boot": false,
			"disabled_in_headless": false
		},
		"fallback": {
			"on_queue_full": "use_template"
		}
	}, false)
	runtime_service._status = "warming"
	runtime_service._job_in_flight = true
	runtime_service._models_by_profile["player_npc"] = "qwen2.5:3b"
	runtime_service._job_queue = [
		{"kind": "warmup", "key": "warmup_a", "model": "qwen2.5:3b"},
		{"kind": "warmup", "key": "warmup_b", "model": "llama3.2:3b"}
	]

	var reply := runtime_service.request_player_reply("player_test_turn_priority", {
		"name": "Kevin",
		"mood": "calm",
		"current_goal": "walking home",
		"last_turns": [
			{
				"speaker": "Player",
				"text": "Hallo"
			}
		]
	})
	_expect_eq(str(reply.get("state", "")), "pending", "player dialogue should stay queued for the model when only warmup jobs block the queue")
	_expect_eq(str(reply.get("source", "")), "ollama", "player dialogue should reserve a real model slot instead of falling back immediately when warmups can be dropped")
	_expect_eq(runtime_service._job_queue.size(), 2, "player dialogue should replace one queued warmup while respecting max_queue_size")
	var has_player_job := false
	for job_variant in runtime_service._job_queue:
		if job_variant is not Dictionary:
			continue
		var job := job_variant as Dictionary
		if str(job.get("kind", "")) == "player_npc":
			has_player_job = true
			break
	_expect(has_player_job, "player dialogue should be inserted into the queue after dropping a warmup job")

	runtime_service.queue_free()
	return _current_error

func _test_player_dialog_locks_player_input() -> String:
	var world := _new_world()
	var camera := _new_camera(Vector3(0.0, 10.0, 14.0), Vector3.ZERO)
	var selection := MockSelectionStateController.new()
	var player_avatar := _new_citizen("Player", Vector3(0.0, 0.0, 0.0))
	var citizen := _new_citizen("Kevin", Vector3(1.5, 0.0, 0.0))
	world.register_citizen(player_avatar)
	world.register_citizen(citizen)
	selection.player_avatar = player_avatar
	selection.controlled_citizen = player_avatar
	selection.player_control_active = true
	player_avatar.set_manual_control_enabled(true, world)

	var manager = CitizenConversationManagerScript.new()
	manager.setup(world, camera, selection)
	var started_session := manager.begin_player_dialog(citizen)
	_expect(bool(started_session.get("active", false)), "interactive dialogue should start for input lock test")
	_expect(selection.is_player_control_input_locked(), "selection state should lock player input while a dialog is active")
	_expect(player_avatar.is_manual_control_input_locked(), "player avatar manual input should be locked during dialog")

	manager.close_player_dialog(citizen, "test_closed")
	_expect(not selection.is_player_control_input_locked(), "selection state should release player input after dialog closes")
	_expect(not player_avatar.is_manual_control_input_locked(), "player avatar manual input should unlock after dialog closes")

	_free_world(world)
	return _current_error

func _test_player_dialog_pauses_citizen_action_while_active() -> String:
	var world := _new_world()
	var camera := _new_camera(Vector3(0.0, 10.0, 14.0), Vector3.ZERO)
	var selection := MockSelectionStateController.new()
	var player_avatar := _new_citizen("Player", Vector3(0.0, 0.0, 0.0))
	var citizen := _new_citizen("Kevin", Vector3(1.5, 0.0, 0.0))
	world.register_citizen(player_avatar)
	world.register_citizen(citizen)
	selection.player_avatar = player_avatar
	selection.controlled_citizen = player_avatar
	selection.player_control_active = true
	selection.selected_citizen = citizen

	citizen.current_action = ActionScript.new(999)

	var manager = CitizenConversationManagerScript.new()
	manager.setup(world, camera, selection)
	manager.begin_player_dialog(citizen)
	manager.update(1.0)
	_expect(citizen.is_active_player_dialog_session(), "citizen should enter the active player dialog runtime state")

	citizen._agent.sim_tick(citizen, world)
	_expect_eq(citizen.current_action.elapsed_minutes, 0, "active player dialog should pause autonomous action ticking for the NPC")

	manager.close_player_dialog(citizen, "test_closed")
	manager.update(0.1)
	citizen._agent.sim_tick(citizen, world)
	_expect_eq(citizen.current_action.elapsed_minutes, 1, "NPC action ticking should resume once the dialog closes")

	_free_world(world)
	return _current_error

func _test_player_dialog_farewell_auto_closes() -> String:
	var world := _new_world()
	var camera := _new_camera(Vector3(0.0, 10.0, 14.0), Vector3.ZERO)
	var selection := MockSelectionStateController.new()
	var player_avatar := _new_citizen("Player", Vector3(0.0, 0.0, 0.0))
	var citizen := _new_citizen("Kevin", Vector3(1.5, 0.0, 0.0))
	world.register_citizen(player_avatar)
	world.register_citizen(citizen)
	selection.player_avatar = player_avatar
	selection.controlled_citizen = player_avatar
	selection.player_control_active = true
	selection.selected_citizen = citizen

	var manager = CitizenConversationManagerScript.new()
	manager.setup(world, camera, selection)
	manager.begin_player_dialog(citizen)
	manager.submit_player_dialog_message(citizen, "bye")

	var session := manager.get_player_dialog_session(citizen)
	_expect(bool(session.get("active", false)), "farewell dialog should remain active briefly after the NPC reply")
	_expect(float(session.get("auto_close_due_at_sec", -1.0)) > 0.0, "farewell dialog should schedule an automatic close after the reply")

	manager.update(1.0)
	session = manager.get_player_dialog_session(citizen)
	_expect(bool(session.get("active", false)), "farewell dialog should still be active before the close timeout")

	manager.update(1.1)
	session = manager.get_player_dialog_session(citizen)
	_expect(session.is_empty(), "farewell dialog should auto-close after the configured timeout")

	_free_world(world)
	return _current_error

func _test_player_dialog_template_farewell_reply_is_brief() -> String:
	var runtime_service = LocalDialogueRuntimeServiceScript.new()
	_harness_root.add_child(runtime_service)
	runtime_service.setup({
		"runtime": {
			"force_template_mode": true
		},
		"startup": {
			"auto_start_on_game_boot": false,
			"disabled_in_headless": false
		}
	}, false)

	var reply := runtime_service.request_player_reply("player_test_farewell", {
		"name": "Kevin",
		"mood": "exhausted",
		"current_goal": "GoTo -> Residential 03 (Multilayer)",
		"recent_summary": "Player: hi | Kevin: hello",
		"last_turns": [
			{
				"speaker": "Player",
				"text": "bye"
			}
		]
	})
	_expect_eq(str(reply.get("source", "")), "template", "forced template mode should return a template farewell reply")
	var reply_text := str(reply.get("text", ""))
	_expect(reply_text == "Bis spaeter." or reply_text == "See you around.", "farewell template reply should stay short and natural")
	_expect(not reply_text.contains("Player:"), "farewell template reply should not echo summarized chat history")

	runtime_service.queue_free()
	return _current_error

func _test_player_dialog_payload_includes_grounded_world_facts() -> String:
	var world := _new_world()
	var camera := _new_camera(Vector3(0.0, 10.0, 14.0), Vector3.ZERO)
	var selection := MockSelectionStateController.new()
	var citizen := _new_citizen("Hannah", Vector3(0.0, 0.0, 0.0))
	var home := _new_residential("Residential Alpha", Vector3(1.0, 0.0, 1.0))
	var restaurant := _new_restaurant("Cafe Nord", Vector3(2.5, 0.0, 0.0))
	world.register_citizen(citizen)
	world.register_building(home)
	world.register_building(restaurant)
	citizen.home = home
	citizen.favorite_restaurant = restaurant
	citizen.current_location = home

	var manager = CitizenConversationManagerScript.new()
	manager.setup(world, camera, selection)
	var payload := manager._build_player_dialogue_payload(citizen, {
		"messages": [
			{
				"speaker": "Player",
				"text": "wo essen?"
			}
		],
		"recent_summary": ""
	})

	_expect(str(payload.get("district", "")) != "", "player dialog payload should include the citizen district for grounding")
	_expect_eq(str(payload.get("reply_language", "")), "german", "payload should infer German replies from German player input")
	_expect_eq(str(payload.get("location", "")), "zu Hause", "player dialog payload should humanize the current home location")
	var known_places: Variant = payload.get("known_places", [])
	var nearby_places: Variant = payload.get("nearby_places", [])
	_expect(known_places is Array and (known_places as Array).size() >= 2, "payload should include grounded known places")
	_expect(nearby_places is Array and (nearby_places as Array).size() >= 2, "payload should include grounded nearby places")
	if known_places is Array:
		var known_names: Array[String] = []
		for entry in known_places as Array:
			if entry is Dictionary:
				known_names.append(str((entry as Dictionary).get("name", "")))
		_expect(known_names.has("mein Zuhause"), "known places should use a humanized home label")
		_expect(not known_names.has("Residential Alpha"), "known places should not expose the raw technical home building name")
		_expect(known_names.has("Cafe Nord"), "known places should still keep friendly custom place names")

	_free_world(world)
	return _current_error

func _test_player_dialog_request_uses_json_profile_options() -> String:
	var runtime_service := LocalDialogueRuntimeServiceScript.new()
	_harness_root.add_child(runtime_service)
	runtime_service.setup({
		"startup": {
			"auto_start_on_game_boot": false,
			"disabled_in_headless": false
		}
	}, false)

	var request := runtime_service._build_generate_request_parts("player_npc", "qwen2.5:3b", {
		"name": "Kevin",
		"reply_language": "german",
		"last_turns": [
			{
				"speaker": "Player",
				"text": "Wie geht's?"
			}
		]
	})
	var parsed: Variant = JSON.parse_string(str(request.get("body_json", "")))
	_expect(parsed is Dictionary, "player dialog request body should be valid JSON")
	if parsed is Dictionary:
		var body := parsed as Dictionary
		_expect_eq(str(body.get("format", "")), "", "player dialog request should use plain text output for lower latency")
		var options: Variant = body.get("options", {})
		_expect(options is Dictionary, "player dialog request should include generation options")
		if options is Dictionary:
			var typed_options := options as Dictionary
			_expect_eq(int(typed_options.get("top_k", 0)), 24, "player dialog request should use the lower-latency top_k")
			_expect_eq(int(typed_options.get("num_ctx", 0)), 1024, "player dialog request should use the reduced context window")
			_expect_eq(int(typed_options.get("num_predict", 0)), 40, "player dialog request should use the reduced output length")
			_expect(abs(float(typed_options.get("temperature", 0.0)) - 0.25) < 0.001, "player dialog request should use the more stable lower temperature")

	runtime_service.queue_free()
	return _current_error

func _test_dialogue_runtime_prefers_local_profile_models() -> String:
	var runtime_service := LocalDialogueRuntimeServiceScript.new()
	_harness_root.add_child(runtime_service)
	runtime_service.setup({
		"startup": {
			"auto_start_on_game_boot": false,
			"disabled_in_headless": false
		}
	}, false)

	runtime_service._available_models = {
		"npc-player:latest": true,
		"npc-overheard:latest": true,
		"qwen2.5:3b": true
	}
	runtime_service._prepare_profile_models()

	_expect_eq(str(runtime_service._models_by_profile.get("player_npc", "")), "npc-player:latest", "runtime should prefer the local player dialog profile model when available")
	_expect_eq(str(runtime_service._models_by_profile.get("npc_npc", "")), "npc-overheard:latest", "runtime should prefer the local overheard dialog profile model when available")

	runtime_service.queue_free()
	return _current_error

func _test_player_dialog_memory_summary_compacts_transcript() -> String:
	var world := _new_world()
	var camera := _new_camera(Vector3(0.0, 10.0, 14.0), Vector3.ZERO)
	var selection := MockSelectionStateController.new()
	var citizen := _new_citizen("Hannah", Vector3.ZERO)
	world.register_citizen(citizen)

	var manager = CitizenConversationManagerScript.new()
	manager.setup(world, camera, selection)
	var session := manager._ensure_player_dialog_session(citizen)
	session["messages"] = [
		{"speaker": "Player", "text": "Hallo"},
		{"speaker": "Hannah", "text": "Hallo."},
		{"speaker": "Player", "text": "Das hast du schon gesagt."},
		{"speaker": "Hannah", "text": "Stimmt."},
		{"speaker": "Player", "text": "Wohin gehst du?"},
		{"speaker": "Hannah", "text": "Nach Hause."},
		{"speaker": "Player", "text": "Und wo genau?"},
		{"speaker": "Hannah", "text": "Zum Wohnhaus."},
		{"speaker": "Player", "text": "Okay"}
	]

	manager._compress_player_dialog_session_memory(session)

	var recent_summary := str(session.get("recent_summary", ""))
	_expect(not recent_summary.is_empty(), "compressed session memory should produce a summary")
	_expect(not recent_summary.contains("Player:"), "compressed session memory should not keep raw speaker transcript prefixes")
	_expect(not recent_summary.contains("Das hast du schon gesagt."), "compressed session memory should not store raw repeated player text")
	_expect(recent_summary.contains("player said the citizen was repeating"), "compressed session memory should keep the repetition signal")

	_free_world(world)
	return _current_error

func _test_player_dialog_json_parser_avoids_verbatim_repeat() -> String:
	var runtime_service := LocalDialogueRuntimeServiceScript.new()
	_harness_root.add_child(runtime_service)
	runtime_service.setup({
		"startup": {
			"auto_start_on_game_boot": false,
			"disabled_in_headless": false
		}
	}, false)

	var reply := runtime_service._normalize_player_reply_result("{\"reply\":\"Ich bin muede.\",\"mood\":\"tired\",\"intent\":\"answer_player\"}", {
		"mood": "exhausted",
		"current_goal": "going home",
		"location": "street",
		"reply_language": "german",
		"last_npc_reply": "Ich bin muede.",
		"last_turns": [
			{
				"speaker": "Player",
				"text": "Wie geht's?"
			}
		]
	})
	_expect(str(reply.get("text", "")) != "Ich bin muede.", "player dialog parser should avoid reusing the exact last NPC reply")
	_expect(not str(reply.get("text", "")).strip_edges().is_empty(), "player dialog parser should still produce a usable reply after de-duplication")

	runtime_service.queue_free()
	return _current_error

func _test_bark_mode_uses_topic_fallback_lines() -> String:
	var world := _new_world()
	var camera := _new_camera(Vector3(0.0, 10.0, 20.0), Vector3.ZERO)
	var selection := MockSelectionStateController.new()
	var player_avatar := _new_citizen("Player Proxy", Vector3(0.0, 0.0, 0.0))
	var citizen_a := _new_citizen("Worker A", Vector3(14.0, 0.0, 0.0))
	var citizen_b := _new_citizen("Worker B", Vector3(14.0, 0.0, 1.0))
	world.register_citizen(citizen_a)
	world.register_citizen(citizen_b)
	selection.player_avatar = player_avatar
	selection.player_control_active = true

	var manager = CitizenConversationManagerScript.new()
	manager.setup(world, camera, selection)
	var conversation_id := "conv_%d_%d" % [citizen_a.get_instance_id(), citizen_b.get_instance_id()]
	manager._active_conversations[conversation_id] = {
		"id": conversation_id,
		"participant_ids": [citizen_a.get_instance_id(), citizen_b.get_instance_id()],
		"mode": "bark",
		"topic": "work",
		"started_at_sec": 0.0,
		"last_mode_change_sec": 0.0
	}

	manager.update(1.0)
	var conversation := _get_single_conversation(manager.get_active_conversations())
	_expect_eq(str(conversation.get("mode", "")), "bark", "conversation should stay in bark mode at bark distance")
	_expect_eq(str(conversation.get("dialogue_source", "")), "bark", "bark mode should mark bark as dialogue source")
	var lines: Array = conversation.get("generated_lines", [])
	_expect(lines.size() >= 2, "bark mode should expose fallback bark lines")
	if lines.size() >= 1:
		_expect(str(lines[0]).contains("Long shift today.") or str(lines[0]).contains("I should head back soon."), "bark lines should come from the configured work fallback set")

	_free_world(world)
	return _current_error

func _test_player_dialog_respects_interactive_budget() -> String:
	var world := _new_world()
	var camera := _new_camera(Vector3(0.0, 10.0, 14.0), Vector3.ZERO)
	var selection := MockSelectionStateController.new()
	var player_avatar := _new_citizen("Player", Vector3(0.0, 0.0, 0.0))
	var citizen_a := _new_citizen("Kevin", Vector3(1.5, 0.0, 0.0))
	var citizen_b := _new_citizen("Mira", Vector3(1.5, 0.0, 1.5))
	world.register_citizen(player_avatar)
	world.register_citizen(citizen_a)
	world.register_citizen(citizen_b)
	selection.player_avatar = player_avatar
	selection.player_control_active = true
	selection.controlled_citizen = player_avatar

	var manager = CitizenConversationManagerScript.new()
	manager.setup(world, camera, selection)

	selection.selected_citizen = citizen_a
	manager.update(1.0)
	var first_session := manager.begin_player_dialog(citizen_a)
	_expect(bool(first_session.get("active", false)), "first interactive dialogue should start")

	selection.selected_citizen = citizen_b
	var second_session := manager.begin_player_dialog(citizen_b)
	_expect_eq(str(second_session.get("error", "")), "interactive_budget_reached", "second dialogue should be blocked by the interactive budget")

	_free_world(world)
	return _current_error

func _test_dialogue_runtime_ui_state_prefers_setup_when_model_missing() -> String:
	var runtime_service := LocalDialogueRuntimeServiceScript.new()
	_harness_root.add_child(runtime_service)
	runtime_service.setup({
		"runtime": {
			"force_template_mode": false
		},
		"startup": {
			"auto_start_on_game_boot": false,
			"disabled_in_headless": false
		},
		"packaging": {
			"ai_root_dir": "{PROJECT_DIR}\\AI_RuntimeTest",
			"llama_dir": "{AI_ROOT_DIR}\\llama",
			"models_dir": "{AI_ROOT_DIR}\\models",
			"runtime_dir": "{AI_ROOT_DIR}\\runtime"
		}
	}, false)
	runtime_service._status = "template_only"
	runtime_service._status_detail = "preferred_model_missing"
	runtime_service._available_models.clear()
	runtime_service._models_by_profile.clear()

	var ui_state := runtime_service.get_ui_runtime_state()
	_expect_eq(str(ui_state.get("action", "")), "setup", "missing preferred models should surface the setup action in the UI")
	_expect_eq(str(ui_state.get("button_text", "")), "Download AI", "UI should recommend downloading the model when preferred models are missing")
	_expect(str(ui_state.get("recommended_model", "")) != "", "UI should expose a recommended model for setup")

	runtime_service.queue_free()
	return _current_error

func _test_multilayer_residential_corner_rejects_blocked_slide_cache() -> String:
	var residential_scene: PackedScene = load("res://Scenes/CityBuildings/multilayer/multilayer_004_d588520f.tscn")
	_expect(residential_scene != null, "multilayer residential scene should load for hard-corner movement regression coverage")
	if residential_scene == null:
		return _current_error

	var residential_root := residential_scene.instantiate() as Node3D
	_harness_root.add_child(residential_root)
	residential_root.global_position = Vector3(14.0, 0.0, -2.0)
	residential_root.propagate_call("force_update_transform")

	var citizen := _new_citizen("Corner Probe", Vector3(15.08, 0.06, -1.08))
	citizen._is_travelling = true
	citizen._travel_target = Vector3(17.0, 0.06, -2.0)
	citizen._travel_route = PackedVector3Array([
		citizen.global_position,
		citizen._travel_target,
	])
	citizen._travel_route_index = 1

	var probe_positions: Array[Vector3] = []
	for x_step in range(7):
		for z_step in range(8):
			probe_positions.append(Vector3(
				14.58 + float(x_step) * 0.08,
				0.06,
				-1.58 + float(z_step) * 0.08
			))

	var blocked_slide := Vector3.ZERO
	var escape_slide := Vector3.ZERO
	var selected_probe := Vector3.ZERO
	var best_blocked_score := -INF
	var best_open_score := INF
	for probe_position in probe_positions:
		citizen.global_position = probe_position
		citizen.force_update_transform()
		var preferred_escape := citizen._travel_target - citizen.global_position
		preferred_escape.y = 0.0
		if preferred_escape.length_squared() <= 0.0001:
			continue

		var candidate_blocked := Vector3.ZERO
		var candidate_open := Vector3.ZERO
		var candidate_blocked_score := -INF
		var candidate_open_score := INF
		for step in range(24):
			var angle := (TAU / 24.0) * float(step)
			var candidate := Vector3(cos(angle), 0.0, sin(angle))
			var score: float = citizen._agent.obstacle_avoidance.score_move_direction(citizen, candidate, false)
			if citizen._is_slide_escape_direction_viable(candidate):
				if score < candidate_open_score:
					candidate_open_score = score
					candidate_open = candidate
			elif score >= 1000.0:
				var alignment_bonus: float = candidate.dot((residential_root.global_position - citizen.global_position).normalized()) * 0.1
				var weighted_score: float = score + alignment_bonus
				if weighted_score > candidate_blocked_score:
					candidate_blocked_score = weighted_score
					candidate_blocked = candidate

		if candidate_blocked != Vector3.ZERO and candidate_open != Vector3.ZERO:
			selected_probe = probe_position
			blocked_slide = candidate_blocked
			escape_slide = candidate_open
			best_blocked_score = citizen._agent.obstacle_avoidance.score_move_direction(citizen, blocked_slide, false)
			best_open_score = candidate_open_score
			break

	_expect(selected_probe != Vector3.ZERO, "residential corner search should find a probe position with both a hard-blocked slide direction and an open sidewalk escape")
	if selected_probe == Vector3.ZERO:
		return _current_error

	citizen.global_position = selected_probe
	citizen.force_update_transform()
	_expect(blocked_slide != Vector3.ZERO, "residential corner should expose at least one hard-blocked slide direction into the building edge")
	_expect(escape_slide != Vector3.ZERO, "residential corner should keep at least one clear escape direction viable along the open sidewalk edge")

	var blocked_score: float = citizen._agent.obstacle_avoidance.score_move_direction(citizen, blocked_slide, false)
	var escape_score: float = citizen._agent.obstacle_avoidance.score_move_direction(citizen, escape_slide, false)
	_expect(blocked_score >= 1000.0, "blocked residential-corner direction should be treated as a hard blocker by obstacle scoring")
	_expect(escape_score < blocked_score, "open residential-corner escape direction should score better than the blocked cached slide")
	_expect(absf(blocked_score - best_blocked_score) <= 0.001, "blocked residential-corner score should stay stable after reapplying the selected probe")
	_expect(absf(escape_score - best_open_score) <= 0.001, "open residential-corner score should stay stable after reapplying the selected probe")

	citizen._stuck_slide_hold_dir = blocked_slide
	citizen._stuck_slide_hold_left = 0.2
	var reused_slide := citizen._get_stuck_slide_direction(escape_slide)
	_expect(reused_slide != blocked_slide, "citizen should not reuse a cached blocked slide direction at the residential multilayer corner")
	_expect(citizen._stuck_slide_hold_dir == Vector3.ZERO, "citizen should clear the cached blocked slide direction after invalidating it")

	return _current_error

func _test_street_furniture_uses_soft_obstacle_layer() -> String:
	var traffic_scene: PackedScene = load("res://ImportedCitySource/scenes/trafficlight_c_active.tscn")
	var street_scene: PackedScene = load("res://ImportedCitySource/scenes/streetlight_active.tscn")
	_expect(traffic_scene != null, "trafficlight active scene should load for movement regression coverage")
	_expect(street_scene != null, "streetlight active scene should load for movement regression coverage")

	if traffic_scene != null:
		var traffic_root := traffic_scene.instantiate() as Node3D
		_harness_root.add_child(traffic_root)
		_expect(traffic_root.is_in_group("pedestrian_soft_obstacle"), "trafficlights should be tagged as pedestrian soft obstacles")
		_expect(traffic_root.is_in_group("traffic_lights"), "trafficlights should be discoverable for crosswalk signal awareness")
		var traffic_body := traffic_root.find_child("StaticBody3D", true, false) as StaticBody3D
		_expect(traffic_body != null, "trafficlight scene should expose a StaticBody3D collider")
		if traffic_body != null:
			_expect_eq(traffic_body.collision_layer, 16, "trafficlight collider should live on the soft obstacle layer")
		_expect(traffic_root.has_method("is_pedestrian_crossing_allowed"), "trafficlight scene should expose pedestrian crossing signal state")
		_expect(traffic_root.has_method("get_current_light_name"), "trafficlight scene should expose a readable signal name")
		if traffic_root.has_method("is_pedestrian_crossing_allowed"):
			traffic_root.set("light_color", 2)
			_expect(not bool(traffic_root.call("is_pedestrian_crossing_allowed")), "red trafficlights should block pedestrian crossing")
			_expect_eq(str(traffic_root.call("get_current_light_name")), "red", "red signal should report its readable name")
			traffic_root.set("light_color", 0)
			_expect(bool(traffic_root.call("is_pedestrian_crossing_allowed")), "green trafficlights should allow pedestrian crossing")
			_expect_eq(str(traffic_root.call("get_current_light_name")), "green", "green signal should report its readable name")

	if street_scene != null:
		var street_root := street_scene.instantiate() as Node3D
		_harness_root.add_child(street_root)
		_expect(street_root.is_in_group("pedestrian_soft_obstacle"), "streetlights should be tagged as pedestrian soft obstacles")
		var street_body := street_root.find_child("StaticBody3D", true, false) as StaticBody3D
		_expect(street_body != null, "streetlight scene should expose a StaticBody3D collider")
		if street_body != null:
			_expect_eq(street_body.collision_layer, 16, "streetlight collider should live on the soft obstacle layer")

	return _current_error

func _new_world() -> World:
	var world: World = WorldScript.new()
	_harness_root.add_child(world)
	world.time.minutes_total = 10 * 60
	if world._timer != null:
		world._timer.stop()
	return world

func _new_camera(position: Vector3, look_target: Vector3) -> Camera3D:
	var camera := Camera3D.new()
	camera.name = "TestCamera"
	_harness_root.add_child(camera)
	camera.global_position = position
	camera.look_at(look_target, Vector3.UP)
	return camera

func _new_residential(building_name: String, spawn_position: Vector3 = Vector3.ZERO) -> ResidentialBuilding:
	var building: ResidentialBuilding = ResidentialBuildingScript.new()
	building.name = building_name
	building.building_name = building_name
	building.capacity = 4
	var entrance := Node3D.new()
	entrance.name = "Entrance"
	entrance.position = Vector3(0.0, 0.0, 1.1)
	building.add_child(entrance)
	_harness_root.add_child(building)
	building.global_position = spawn_position
	return building

func _new_restaurant(building_name: String, spawn_position: Vector3 = Vector3.ZERO) -> Restaurant:
	var building: Restaurant = RestaurantScript.new()
	building.name = building_name
	building.building_name = building_name
	var entrance := Node3D.new()
	entrance.name = "Entrance"
	entrance.position = Vector3(0.0, 0.0, 1.1)
	building.add_child(entrance)
	_harness_root.add_child(building)
	building.global_position = spawn_position
	return building

func _new_citizen(citizen_name: String, spawn_position: Vector3 = Vector3.ZERO) -> Citizen:
	var citizen: Citizen = CitizenScript.new()
	citizen.name = citizen_name
	citizen.citizen_name = citizen_name
	_harness_root.add_child(citizen)
	citizen.global_position = spawn_position
	return citizen

func _future_time(world: World, offset_minutes: int) -> Dictionary:
	var current_day := world.world_day()
	var current_total := world.time.get_hour() * 60 + world.time.get_minute() + maxi(offset_minutes, 0)
	var extra_days: int = current_total / (24 * 60)
	var minute_of_day := current_total % (24 * 60)
	return {
		"day": current_day + extra_days,
		"minute": minute_of_day
	}

func _get_single_conversation(conversations: Dictionary) -> Dictionary:
	if conversations.size() != 1:
		_expect(false, "expected exactly one active conversation, got %d" % conversations.size())
		return {}
	var values := conversations.values()
	if values.is_empty() or values[0] is not Dictionary:
		_expect(false, "expected a dictionary conversation payload")
		return {}
	return values[0] as Dictionary

func _free_world(world: World) -> void:
	if world == null:
		return
	if world._timer != null:
		world._timer.stop()
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
