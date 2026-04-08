extends SceneTree

const CitizenScript = preload("res://Entities/Citizens/Citizen.gd")
const ResidentialBuildingScript = preload("res://Entities/Buildings/ResidentialBuilding.gd")
const RestaurantScript = preload("res://Entities/Buildings/Restaurant.gd")
const WorldScript = preload("res://Simulation/World.gd")
const ActionScript = preload("res://Actions/Action.gd")
const CitizenSimulationLodControllerScript = preload("res://Simulation/Citizens/CitizenSimulationLodController.gd")
const CitizenConversationManagerScript = preload("res://Simulation/Conversation/CitizenConversationManager.gd")
const LocalDialogueRuntimeServiceScript = preload("res://Simulation/AI/LocalDialogueRuntimeService.gd")

class MockSelectionStateController:
	extends RefCounted

	var selected_citizen: Citizen = null
	var controlled_citizen: Citizen = null
	var player_avatar: Citizen = null
	var player_control_active: bool = false
	var player_control_input_locked: bool = false

	func get_selected_citizen() -> Citizen:
		return selected_citizen if selected_citizen != null and is_instance_valid(selected_citizen) else null

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
		"player_dialog_queue_full_uses_template_reply",
		"player_dialog_prioritizes_over_warmup_queue",
		"player_dialog_locks_player_input",
		"player_dialog_pauses_citizen_action_while_active",
		"player_dialog_farewell_auto_closes",
		"player_dialog_template_farewell_reply_is_brief",
		"player_dialog_payload_includes_grounded_world_facts",
		"bark_mode_uses_topic_fallback_lines",
		"player_dialog_respects_interactive_budget",
		"dialogue_runtime_ui_state_prefers_setup_when_model_missing",
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
		"bark_mode_uses_topic_fallback_lines":
			return _test_bark_mode_uses_topic_fallback_lines()
		"player_dialog_respects_interactive_budget":
			return _test_player_dialog_respects_interactive_budget()
		"dialogue_runtime_ui_state_prefers_setup_when_model_missing":
			return _test_dialogue_runtime_ui_state_prefers_setup_when_model_missing()
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
	var known_places: Variant = payload.get("known_places", [])
	var nearby_places: Variant = payload.get("nearby_places", [])
	_expect(known_places is Array and (known_places as Array).size() >= 2, "payload should include grounded known places")
	_expect(nearby_places is Array and (nearby_places as Array).size() >= 2, "payload should include grounded nearby places")

	_free_world(world)
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
