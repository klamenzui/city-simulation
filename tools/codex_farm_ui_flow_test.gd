extends SceneTree

const MainScene := preload("res://Main.tscn")
const VehicleDepotAccessScript := preload("res://Simulation/Transport/VehicleDepotAccess.gd")
const SimulationInteractionControllerScript := preload("res://Simulation/UI/SimulationInteractionController.gd")

const ACTION_HARVEST := "harvest"
const ACTION_DELIVER := "deliver"
const ACTION_PLANT := "plant"
const ACTION_WATER := "water"
const SETTLE_FRAMES := 12

var _errors: Array[String] = []
var _capture_dir: String = ""

class TestSelectionState:
	extends RefCounted

	var player: Citizen = null
	var selected_citizen: Citizen = null
	var selected_building: Building = null
	var camera_locked: bool = false
	var player_input_locked: bool = false

	func _init(player_ref: Citizen) -> void:
		player = player_ref

	func get_player_avatar() -> Citizen:
		return null

	func get_controlled_citizen() -> Citizen:
		return player

	func get_camera_player_target() -> Citizen:
		return player

	func get_selected_citizen() -> Citizen:
		return selected_citizen

	func get_selected_building() -> Building:
		return selected_building

	func handle_citizen_clicked(citizen: Citizen) -> void:
		selected_citizen = citizen
		selected_building = null

	func handle_building_clicked(building: Building) -> void:
		selected_building = building
		selected_citizen = null

	func deselect() -> void:
		selected_citizen = null
		selected_building = null

	func is_player_control_active() -> bool:
		return false

	func is_camera_input_locked() -> bool:
		return camera_locked

	func set_camera_input_locked(locked: bool) -> void:
		camera_locked = locked

	func is_player_control_input_locked() -> bool:
		return player_input_locked

	func set_player_control_input_locked(locked: bool) -> void:
		player_input_locked = locked


func _initialize() -> void:
	_capture_dir = _get_capture_dir()
	if not _capture_dir.is_empty():
		DisplayServer.window_set_size(Vector2i(1440, 900))

	var main := MainScene.instantiate()
	if main == null:
		_fail("Could not instantiate Main.tscn.")
		_finish()
		return
	root.add_child(main)
	for _i in range(SETTLE_FRAMES):
		await process_frame
	for _i in range(4):
		await physics_frame

	if main.get("_runtime_controller") == null and main.has_method("_on_main_menu_singleplayer"):
		main.call("_on_main_menu_singleplayer")
		for _i in range(SETTLE_FRAMES):
			await process_frame
		for _i in range(4):
			await physics_frame

	var world := main.get_node_or_null("World") as World
	var player := main.get_node_or_null("ControlledCitizen") as Citizen
	var runtime = main.get("_runtime_controller")
	var interaction = runtime.get("interaction_controller") if runtime != null else null
	if interaction == null:
		interaction = SimulationInteractionControllerScript.new()
		interaction.setup(main, world)
	var selection = TestSelectionState.new(player)
	interaction.bind_selection_state(selection, null)
	if world == null:
		_fail("Main runtime should expose World.")
	if player == null:
		_fail("Main runtime should expose ControlledCitizen.")
	if interaction == null:
		_fail("Main runtime should expose SimulationInteractionController.")
	if not _errors.is_empty():
		_finish(main)
		return

	world.is_paused = true
	world.time.minutes_total = 10 * 60
	var pair := _select_farm_target_pair(world)
	var farm := pair.get("farm", null) as Farm
	var target := pair.get("target", null) as Supermarket
	if farm == null or target == null:
		_fail("Main should contain a Farm/Supermarket pair with complete delivery routes.")
		_finish(main)
		return

	_prepare_player(world, player)
	_prepare_demand_fixture(world, farm, target)
	await _run_worker_flow(world, player, farm, target, interaction, selection)
	await _reset_after_delivery(world, player, farm)
	await _run_owner_flow(world, player, farm, target, interaction, selection)

	_finish(main)


func _run_worker_flow(
	world: World,
	player: Citizen,
	farm: Farm,
	target: Supermarket,
	interaction,
	selection
) -> void:
	farm.citizen_owner = null
	farm.owner_display_name = ""
	farm.crop_state = Farm.CropState.READY
	farm.crop_growth_minutes = farm.get_crop_growth_total_minutes()
	var initial_stock := farm.get_product_inventory_amount()
	_enter_and_show_farm(world, player, farm, interaction, selection)
	await process_frame

	var before_apply := player.get_player_action_ui_state(world)
	_expect(_button_present(before_apply, "apply_work"), "Worker flow should initially show Bewerben.")
	_expect(not _button_present(before_apply, "work"), "Worker flow must not show Arbeiten before application.")
	_expect(_press_action(interaction, "apply_work"), "Bewerben UI button should exist and be pressable.")
	await process_frame
	await process_frame
	_expect(player.job != null and player.job.workplace == farm, "Bewerben should assign the Farm job.")
	_expect(farm.is_worker(player), "Bewerben should register the player as Farm worker.")

	var after_apply := player.get_player_action_ui_state(world)
	_expect(_button_present(after_apply, "work"), "Accepted Farm worker should see Arbeiten.")
	_expect(_button_present(after_apply, "farm_demand"), "Accepted Farm worker should see Nachfrage.")
	_expect(_press_action(interaction, "work"), "Arbeiten UI button should start the Farm WorkScene.")
	await process_frame
	await process_frame
	var work_scene := interaction.get("_farm_work_scene") as Node
	_expect(work_scene != null, "Arbeiten should mount FarmWorkScene.")
	if work_scene != null:
		await _capture("worker_work.png")
		work_scene.call("debug_perform_action", 1, ACTION_HARVEST)
		work_scene.call("debug_perform_action", 0, ACTION_DELIVER)
		work_scene.call("finish_session")
		await process_frame
		await process_frame
	_expect(farm.get_product_inventory_amount() > initial_stock, "Worker Farm shift should add harvested stock.")
	_expect(player.work_minutes_today > 0, "Worker Farm shift should record paid work minutes.")

	_show_player_context(player, farm, interaction, selection)
	await process_frame
	_expect(_press_action(interaction, "farm_demand"), "Nachfrage UI button should open the demand window.")
	await process_frame
	await process_frame
	var demand_window = interaction.get("farm_demand_window")
	_expect(demand_window != null and demand_window.visible, "Worker Nachfrage should open FarmDemandWindow.")
	if demand_window != null:
		var text := _visible_text(demand_window)
		_expect(text.contains(target.get_display_name()), "Worker Nachfrage should show the target business.")
		_expect(text.contains("Selbst liefern"), "Worker Nachfrage should offer self-delivery.")
		_expect(not text.contains("Umsatz"), "Worker Nachfrage must hide revenue.")
	await _capture("worker_demand.png")

	var target_stock_before := target.get_stock(farm.get_supermarket_delivery_item())
	_expect(_press_text_button(demand_window, "Selbst liefern"), "Worker should start delivery from the demand UI.")
	await process_frame
	await process_frame
	_expect(farm.has_manual_delivery_for(player), "Worker self-delivery should create a Farm delivery session.")
	var vehicle := player.current_vehicle as VehicleAgent
	_expect(vehicle != null, "Worker self-delivery should board a real depot vehicle.")
	if vehicle == null:
		return
	vehicle.global_position = target.get_entrance_pos()
	vehicle.linear_velocity = Vector3.ZERO
	interaction.call("_refresh_player_action_ui")
	await process_frame
	_expect(_action_enabled(player.get_player_action_ui_state(world), "complete_farm_delivery"), "Unload should enable at the target.")
	_expect(_press_action(interaction, "complete_farm_delivery"), "Worker should unload through the UI action.")
	await process_frame
	_expect(target.get_stock(farm.get_supermarket_delivery_item()) > target_stock_before, "Worker delivery should increase target stock.")
	_expect(not farm.has_manual_delivery_for(player), "Worker delivery session should close after unloading.")


func _run_owner_flow(
	world: World,
	player: Citizen,
	farm: Farm,
	target: Supermarket,
	interaction,
	selection
) -> void:
	farm.citizen_owner = player
	farm.owner_display_name = player.citizen_name
	farm.owner_work_minutes_today = 0
	farm.crop_state = Farm.CropState.GROWING
	farm.crop_growth_minutes = 0
	target.inventory[farm.get_supermarket_delivery_item()] = 0
	farm.set_product_inventory_amount(farm.get_product_commodity(), maxi(farm.get_product_inventory_amount(), 30))
	_enter_and_show_farm(world, player, farm, interaction, selection)
	await process_frame

	var owner_state := player.get_player_action_ui_state(world)
	_expect(not _button_present(owner_state, "apply_work"), "Farm owner must not see Bewerben for own Farm.")
	_expect(_button_present(owner_state, "work"), "Farm owner should see Arbeiten without a job.")
	_expect(_button_present(owner_state, "farm_demand"), "Farm owner should see Nachfrage.")
	_expect(_button_present(owner_state, "building_inventory"), "Farm owner should see internal Farm inventory.")
	var paid_minutes_before := player.work_minutes_today
	_expect(_press_action(interaction, "work"), "Owner Arbeiten button should start FarmWorkScene.")
	await process_frame
	await process_frame
	var work_scene := interaction.get("_farm_work_scene") as Node
	_expect(work_scene != null, "Owner Arbeiten should mount FarmWorkScene without employment.")
	if work_scene != null:
		await _capture("owner_work.png")
		work_scene.call("debug_perform_action", 1, ACTION_PLANT)
		work_scene.call("debug_perform_action", 1, ACTION_WATER)
		work_scene.call("finish_session")
		await process_frame
		await process_frame
	_expect(farm.owner_work_minutes_today > 0, "Owner Farm shift should record unpaid owner minutes.")
	_expect(player.work_minutes_today == paid_minutes_before, "Owner Farm shift must not create paid wage minutes.")

	_show_player_context(player, farm, interaction, selection)
	await process_frame
	_expect(_press_action(interaction, "farm_demand"), "Owner Nachfrage button should open demand UI.")
	await process_frame
	await process_frame
	var demand_window = interaction.get("farm_demand_window")
	_expect(demand_window != null and demand_window.visible, "Owner Nachfrage should open FarmDemandWindow.")
	if demand_window != null:
		var text := _visible_text(demand_window)
		_expect(text.contains(target.get_display_name()), "Owner Nachfrage should show the target business.")
		_expect(text.contains("Umsatz"), "Owner Nachfrage should show expected revenue.")
	await _capture("owner_demand.png")

	var income_before := farm.income_today
	_expect(_press_text_button(demand_window, "Selbst liefern"), "Owner should start self-delivery from demand UI.")
	await process_frame
	await process_frame
	_expect(farm.has_manual_delivery_for(player), "Owner self-delivery should create a Farm delivery session.")
	var vehicle := player.current_vehicle as VehicleAgent
	_expect(vehicle != null, "Owner self-delivery should board a real depot vehicle.")
	if vehicle == null:
		return
	vehicle.global_position = target.get_entrance_pos()
	vehicle.linear_velocity = Vector3.ZERO
	interaction.call("_refresh_player_action_ui")
	await process_frame
	_expect(_press_action(interaction, "complete_farm_delivery"), "Owner should unload through the UI action.")
	await process_frame
	_expect(farm.income_today > income_before, "Owner self-delivery should add Farm revenue.")
	_expect(player.work_minutes_today == paid_minutes_before, "Owner self-delivery must not create wage minutes.")


func _prepare_player(world: World, player: Citizen) -> void:
	if player.current_action != null:
		player.cancel_player_action(world)
	if player.is_inside_vehicle():
		var vehicle := player.current_vehicle as VehicleAgent
		if vehicle != null:
			vehicle.unboard_driver(world, vehicle.get_entry_point_global())
	if player.is_inside_building():
		player.player_exit_building(world)
	if player.job != null and player.job.workplace != null:
		player.job.workplace.fire(player)
	player.job = null
	player.work_minutes_today = 0
	player.wallet.balance = 1000
	player.needs.hunger = 0.0
	player.needs.energy = 100.0
	player.needs.health = 100.0
	player.needs.fun = 100.0


func _prepare_demand_fixture(world: World, farm: Farm, target: Supermarket) -> void:
	var product_key := farm.get_product_commodity()
	for building in world.buildings:
		var business := building as CommercialBuilding
		if business == null or business == farm:
			continue
		for item_var in business.source_commodities.keys():
			if str(business.source_commodities.get(item_var, "")) == product_key:
				business.restock_enabled = business == target
				break
	farm.job_capacity = maxi(farm.job_capacity, farm.workers.size() + 2)
	farm.account.balance = maxi(farm.account.balance, 3000)
	farm.market_export_enabled = false
	farm.direct_supermarket_delivery_enabled = true
	farm.set_product_inventory_amount(product_key, 40)
	target.account.balance = maxi(target.account.balance, 3000)
	target.restock_enabled = true
	target.inventory[farm.get_supermarket_delivery_item()] = 0


func _enter_and_show_farm(world: World, player: Citizen, farm: Farm, interaction, selection) -> void:
	if player.is_inside_vehicle():
		var vehicle := player.current_vehicle as VehicleAgent
		if vehicle != null:
			vehicle.unboard_driver(world, vehicle.get_entry_point_global())
	if player.is_inside_building():
		player.player_exit_building(world)
	player.global_position = farm.get_entrance_pos()
	_expect(player.player_enter_building(farm, world), "Player should enter the Farm.")
	_show_player_context(player, farm, interaction, selection)


func _show_player_context(player: Citizen, farm: Farm, interaction, selection) -> void:
	if selection != null:
		selection.handle_citizen_clicked(player)
	interaction.call("_show_player_building_context", player, farm)
	interaction.call("_refresh_player_action_ui")


func _reset_after_delivery(world: World, player: Citizen, farm: Farm) -> void:
	if player.is_inside_vehicle():
		var vehicle := player.current_vehicle as VehicleAgent
		if vehicle != null:
			vehicle.unboard_driver(world, vehicle.get_entry_point_global())
			var depot_position := VehicleDepotAccessScript.resolve_marker_parking_position(farm, "DeliveryVehicleDepot")
			if VehicleDepotAccessScript.is_finite_vector(depot_position):
				vehicle.global_position = depot_position
				vehicle.linear_velocity = Vector3.ZERO
	if player.is_inside_building():
		player.player_exit_building(world)
	if farm.is_worker(player):
		farm.fire(player)
	player.job = null
	await process_frame


func _select_farm_target_pair(world: World) -> Dictionary:
	var depot_position := VehicleDepotAccessScript.resolve_marker_parking_position(world, "DeliveryVehicleDepot")
	if not VehicleDepotAccessScript.is_finite_vector(depot_position):
		return {}
	var depot_access := world.get_vehicle_road_access_point(depot_position)
	for building in world.buildings:
		var farm := building as Farm
		if farm == null:
			continue
		var loading_position := VehicleDepotAccessScript.resolve_marker_parking_position(farm, "DeliveryLoadingDepot")
		if not VehicleDepotAccessScript.is_finite_vector(loading_position):
			continue
		var loading_access := world.get_vehicle_road_access_point(loading_position)
		if world.get_vehicle_road_path(depot_access, loading_access).size() < 2:
			continue
		for candidate in world.buildings:
			var target := candidate as Supermarket
			if target == null:
				continue
			if target.get_restock_need(farm.get_supermarket_delivery_item()) <= 0:
				continue
			var outbound := world.get_vehicle_road_path(loading_access, target.get_entrance_pos())
			var returning := world.get_vehicle_road_path(target.get_entrance_pos(), depot_access)
			if outbound.size() >= 2 and returning.size() >= 2:
				return {"farm": farm, "target": target}
	return {}


func _press_action(interaction, action_id: String) -> bool:
	if interaction == null:
		return false
	interaction.call("_refresh_player_action_ui")
	var panel := interaction.get_debug_panel() as DebugPanel
	if panel == null:
		return false
	for node in _all_nodes(panel):
		var button := node as Button
		if button != null and str(button.get_meta("action_id", "")) == action_id:
			if button.disabled:
				return false
			button.pressed.emit()
			return true
	return false


func _press_text_button(scope: Node, text: String) -> bool:
	if scope == null:
		return false
	for node in _all_nodes(scope):
		var button := node as Button
		if button != null and button.visible and button.text == text and not button.disabled:
			button.pressed.emit()
			return true
	return false


func _button_present(state: Dictionary, action_id: String) -> bool:
	for spec_var in state.get("buttons", []):
		var spec := spec_var as Dictionary
		if str(spec.get("id", "")) == action_id:
			return true
	return false


func _action_enabled(state: Dictionary, action_id: String) -> bool:
	for spec_var in state.get("buttons", []):
		var spec := spec_var as Dictionary
		if str(spec.get("id", "")) == action_id:
			return bool(spec.get("enabled", false))
	return false


func _visible_text(scope: Node) -> String:
	var parts := PackedStringArray()
	if scope == null:
		return ""
	for node in _all_nodes(scope):
		var control := node as Control
		if control == null or not control.is_visible_in_tree():
			continue
		if control is Label:
			parts.append((control as Label).text)
		elif control is Button:
			parts.append((control as Button).text)
		elif control is RichTextLabel:
			parts.append((control as RichTextLabel).get_parsed_text())
	return "\n".join(parts)


func _capture(file_name: String) -> void:
	if _capture_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	for _i in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var absolute_dir := ProjectSettings.globalize_path(_capture_dir)
	DirAccess.make_dir_recursive_absolute(absolute_dir)
	var path := _capture_dir.path_join(file_name)
	var err := image.save_png(path)
	_expect(err == OK, "Could not save screenshot %s." % path)
	if err == OK:
		print("FARM_UI_SCREENSHOT ", ProjectSettings.globalize_path(path))


func _get_capture_dir() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			return arg.substr("--capture-dir=".length()).strip_edges()
	return ""


func _all_nodes(scope: Node) -> Array[Node]:
	var nodes: Array[Node] = [scope]
	for child in scope.get_children():
		nodes.append_array(_all_nodes(child))
	return nodes


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	_errors.append(message)


func _finish(main: Node = null) -> void:
	if main != null and is_instance_valid(main):
		main.queue_free()
	if _errors.is_empty():
		print("FARM_UI_FLOW_TEST OK")
		quit(0)
		return
	print("FARM_UI_FLOW_TEST FAILED:")
	for error in _errors:
		print("  - %s" % error)
	quit(1)
