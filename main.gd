extends Node3D

@onready var world: World = $World

const CITIZEN_COUNT := 10
const SELECTED_CITIZEN_TRACE_INTERVAL_SEC := 1.0
const ALL_CITIZEN_TRACE_INTERVAL_SEC := 0.5
const ENABLE_ALL_CITIZEN_TRACE := true
const ENABLE_MAP_SNAPSHOT_LOG := true
const RoadBuilderScript = preload("res://Simulation/Bootstrap/RoadBuilder.gd")
const ImportedCitySetupScript = preload("res://Simulation/Bootstrap/ImportedCitySetup.gd")
const RestaurantScene = preload("res://Scenes/Restaurant.tscn")
const SupermarketScene = preload("res://Scenes/Supermarket.tscn")
const ShopScene = preload("res://Scenes/Shop.tscn")
const CinemaScene = preload("res://Scenes/Cinema.tscn")
const UniversityScene = preload("res://Scenes/University.tscn")
const CityHallScene = preload("res://Scenes/CityHall.tscn")
const FarmScene = preload("res://Scenes/Farm.tscn")
const FactoryScene = preload("res://Scenes/Factory.tscn")
const SimLogger = preload("res://Simulation/Logging/SimLogger.gd")

var _pause_btn: Button
var _speed_label: Label
var _date_label: Label
var _clock_label: Label
var _citizen_stats_label: Label
var _debug_panel: DebugPanel
var _selected_citizen: Citizen = null
var _selected_building: Building = null
var _entity_clicked_this_frame: bool = false
var _building_panel_refresh_left: float = 0.0
var _selected_citizen_trace_left: float = 0.0
var _all_citizen_trace_left: float = 0.0
var _citizen_path_debug: MeshInstance3D = null
var _citizen_path_debug_mesh: ImmediateMesh = null
var _citizen_path_line_material: StandardMaterial3D = null
var _citizen_path_active_material: StandardMaterial3D = null
var _citizen_path_start_material: StandardMaterial3D = null
var _citizen_path_waypoint_material: StandardMaterial3D = null
var _citizen_path_end_material: StandardMaterial3D = null
var _citizen_path_failed_material: StandardMaterial3D = null

func _ready() -> void:
	SimLogger.start_new_session(false)
	get_viewport().physics_object_picking = true

	_setup_world_systems()
	_setup_citizen_path_debug()
	_build_debug_panel()
	_bind_building_clicks()
	_spawn_citizens()
	call_deferred("_log_initial_debug_snapshot")
	_build_hud()

func _process(delta: float) -> void:
	_update_selected_citizen_path_debug()
	_update_selected_citizen_trace(delta)
	_update_all_citizen_trace(delta)

	if _selected_building != null and _debug_panel != null and _debug_panel.visible:
		_building_panel_refresh_left -= delta
		if _building_panel_refresh_left <= 0.0:
			_building_panel_refresh_left = 0.25
			_selected_building.refresh_info_panel(world)

func _setup_world_systems() -> void:
	var has_scene_city: bool = get_node_or_null("World/City") != null
	var imported_city: Node3D = null
	if not has_scene_city:
		imported_city = ImportedCitySetupScript.ensure_city_visual(self)

	_spawn_missing_core_buildings()
	NavigationSetup.ensure_region(self, world)
	WorldSetup.configure_scene_buildings(get_tree(), world)
	if not has_scene_city and imported_city == null:
		RoadBuilderScript.build_simple_roads(self, world)

	world.rebuild_road_graph(self)
	world.rebuild_pedestrian_graph(self)

func _spawn_missing_core_buildings() -> void:
	if not _has_building_type("restaurant"):
		_spawn_if_missing("Restaurant", RestaurantScene, Vector3(11.0, 0.0, -7.0))
	if not _has_building_type("supermarket"):
		_spawn_if_missing("Supermarket", SupermarketScene, Vector3(15.0, 0.0, 9.0))
	if not _has_building_type("shop"):
		_spawn_if_missing("Shop", ShopScene, Vector3(19.0, 0.0, -4.0))
	if not _has_building_type("cinema"):
		_spawn_if_missing("Cinema", CinemaScene, Vector3(-18.0, 0.0, -9.0))
	if not _has_building_type("university"):
		_spawn_if_missing("University", UniversityScene, Vector3(-14.0, 0.0, 10.0))
	if not _has_building_type("city_hall"):
		_spawn_if_missing("CityHall", CityHallScene, Vector3(1.0, 0.0, 15.0))
	if not _has_building_type("farm"):
		_spawn_if_missing("Farm", FarmScene, Vector3(-24.0, 0.0, 14.0))
	if not _has_building_type("factory"):
		_spawn_if_missing("Factory", FactoryScene, Vector3(24.0, 0.0, 14.0))

func _has_building_type(type_id: String) -> bool:
	for node in get_tree().get_nodes_in_group("buildings"):
		if node is not Building:
			continue
		match type_id:
			"restaurant":
				if node is Restaurant:
					return true
			"supermarket":
				if node is Supermarket:
					return true
			"shop":
				if node is Shop and node is not Supermarket:
					return true
			"cinema":
				if node is Cinema:
					return true
			"university":
				if node is University:
					return true
			"city_hall":
				if node is CityHall:
					return true
			"farm":
				if node is Farm:
					return true
			"factory":
				if node is Factory:
					return true
			_:
				pass
	return false

func _spawn_if_missing(node_name: String, scene: PackedScene, pos: Vector3) -> void:
	if get_node_or_null(node_name) != null:
		return
	var instance := scene.instantiate() as Node3D
	if instance == null:
		return
	instance.name = node_name
	instance.position = pos
	add_child(instance)

func _build_debug_panel() -> void:
	_debug_panel = preload("res://Scenes/DebugPanel.tscn").instantiate()
	add_child(_debug_panel)
	_debug_panel.visible = false

func _setup_citizen_path_debug() -> void:
	_citizen_path_debug = MeshInstance3D.new()
	_citizen_path_debug.name = "SelectedCitizenPathDebug"
	_citizen_path_debug.top_level = true
	_citizen_path_debug.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_citizen_path_debug.visible = false

	_citizen_path_debug_mesh = ImmediateMesh.new()
	_citizen_path_debug.mesh = _citizen_path_debug_mesh

	_citizen_path_line_material = _create_path_debug_material(Color(0.10, 0.95, 0.35, 1.0))
	_citizen_path_active_material = _create_path_debug_material(Color(0.10, 0.85, 1.0, 1.0))
	_citizen_path_start_material = _create_path_debug_material(Color(0.20, 1.0, 0.20, 1.0))
	_citizen_path_waypoint_material = _create_path_debug_material(Color(1.0, 0.82, 0.18, 1.0))
	_citizen_path_end_material = _create_path_debug_material(Color(1.0, 0.22, 0.22, 1.0))
	_citizen_path_failed_material = _create_path_debug_material(Color(1.0, 0.35, 0.10, 1.0))

	add_child(_citizen_path_debug)

func _create_path_debug_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.no_depth_test = true
	return material

func _bind_building_clicks() -> void:
	for building in world.buildings:
		if building == null:
			continue
		if not building.clicked.is_connected(_on_building_clicked):
			building.clicked.connect(_on_building_clicked)

func _spawn_citizens() -> void:
	var spawned := CitizenFactory.spawn_citizens(self, world, CITIZEN_COUNT)
	for citizen in spawned:
		var cb := _on_citizen_clicked.bind(citizen)
		if not citizen.clicked.is_connected(cb):
			citizen.clicked.connect(cb)

func _log_initial_debug_snapshot() -> void:
	if ENABLE_MAP_SNAPSHOT_LOG:
		_log_map_snapshot()
	if ENABLE_ALL_CITIZEN_TRACE:
		_all_citizen_trace_left = 0.0
		_log_all_citizen_traces("spawn")

func _on_citizen_clicked(c: Citizen) -> void:
	_entity_clicked_this_frame = true

	if _selected_citizen == c:
		_deselect()
		return

	if _selected_building != null:
		_selected_building.select(null, world)
		_selected_building = null

	if _selected_citizen != null:
		_log_selected_citizen_trace("switch")
		_selected_citizen.select(null)
		_selected_citizen_trace_left = 0.0
		_clear_selected_citizen_path_debug()

	_selected_citizen = c
	c.select(_debug_panel)
	_debug_panel.visible = true
	_selected_citizen_trace_left = 0.0
	_log_selected_citizen_trace("selected")
	_update_selected_citizen_path_debug()

func _on_building_clicked(b: Building) -> void:
	_entity_clicked_this_frame = true

	if _selected_building == b:
		_deselect()
		return

	if _selected_citizen != null:
		_log_selected_citizen_trace("deselected")
		_selected_citizen.select(null)
		_selected_citizen = null
		_selected_citizen_trace_left = 0.0
		_clear_selected_citizen_path_debug()

	if _selected_building != null:
		_selected_building.select(null, world)

	_selected_building = b
	b.select(_debug_panel, world)
	_debug_panel.visible = true
	_building_panel_refresh_left = 0.0

func _deselect() -> void:
	if _selected_citizen != null:
		_log_selected_citizen_trace("deselected")
		_selected_citizen.select(null)
		_selected_citizen = null
		_selected_citizen_trace_left = 0.0
	if _selected_building != null:
		_selected_building.select(null, world)
		_selected_building = null
	_clear_selected_citizen_path_debug()
	if _debug_panel != null:
		_debug_panel.visible = false

func _update_selected_citizen_trace(delta: float) -> void:
	if _selected_citizen == null or not is_instance_valid(_selected_citizen):
		_selected_citizen_trace_left = 0.0
		return

	_selected_citizen_trace_left -= delta
	if _selected_citizen_trace_left > 0.0:
		return

	_selected_citizen_trace_left = SELECTED_CITIZEN_TRACE_INTERVAL_SEC
	_log_selected_citizen_trace("tick")

func _log_selected_citizen_trace(event_name: String) -> void:
	if _selected_citizen == null or not is_instance_valid(_selected_citizen):
		return

	var time_label := "day=? time=?"
	if world != null and world.time != null:
		time_label = "day=%d time=%s" % [world.time.day, world.time.get_time_string()]

	SimLogger.log("[CitizenTrace %s] %s | %s" % [
		event_name,
		time_label,
		_selected_citizen.get_trace_debug_summary()
	])

func _update_all_citizen_trace(delta: float) -> void:
	if not ENABLE_ALL_CITIZEN_TRACE:
		return
	_all_citizen_trace_left -= delta
	if _all_citizen_trace_left > 0.0:
		return

	_all_citizen_trace_left = ALL_CITIZEN_TRACE_INTERVAL_SEC
	_log_all_citizen_traces("tick")

func _log_all_citizen_traces(event_name: String) -> void:
	var time_label := "day=? time=?"
	if world != null and world.time != null:
		time_label = "day=%d time=%s" % [world.time.day, world.time.get_time_string()]

	for citizen in world.citizens:
		if citizen == null or not is_instance_valid(citizen):
			continue
		SimLogger.log("[CitizenTraceAll %s] %s | %s" % [
			event_name,
			time_label,
			citizen.get_trace_debug_summary()
		])

func _log_map_snapshot() -> void:
	var road_nodes := _collect_debug_roads()
	var crosswalk_nodes := _collect_debug_crosswalks()
	var light_nodes := _collect_debug_lights(self)

	SimLogger.log("[MapDump summary] buildings=%d citizens=%d roads=%d crosswalks=%d lights=%d" % [
		world.buildings.size(),
		world.citizens.size(),
		road_nodes.size(),
		crosswalk_nodes.size(),
		light_nodes.size()
	])

	for building in world.buildings:
		if building == null:
			continue
		SimLogger.log("[MapDump building] name=%s pos=%s %s" % [
			building.get_display_name(),
			_fmt_vec3(building.global_position),
			building.get_navigation_debug_summary(world) if building.has_method("get_navigation_debug_summary") else ""
		])

	for citizen in world.citizens:
		if citizen == null:
			continue
		SimLogger.log("[MapDump citizen] name=%s pos=%s home=%s location=%s inside=%s action=%s" % [
			citizen.citizen_name,
			_fmt_vec3(citizen.global_position),
			citizen.home.get_display_name() if citizen.home != null else "-",
			citizen.current_location.get_display_name() if citizen.current_location != null else "-",
			citizen._inside_building.get_display_name() if citizen._inside_building != null else "-",
			citizen.current_action.label if citizen.current_action != null else "idle"
		])

	for road in road_nodes:
		SimLogger.log("[MapDump road] path=%s pos=%s" % [road.get_path(), _fmt_vec3(road.global_position)])

	for crosswalk in crosswalk_nodes:
		SimLogger.log("[MapDump crosswalk] path=%s pos=%s" % [crosswalk.get_path(), _fmt_vec3(crosswalk.global_position)])

	for light in light_nodes:
		SimLogger.log("[MapDump light] type=%s path=%s pos=%s" % [
			light.get_class(),
			light.get_path(),
			_fmt_vec3(light.global_position)
		])

func _collect_debug_roads() -> Array[Node3D]:
	var out: Array[Node3D] = []
	_append_transport_segments_for_log(get_node_or_null("World/City/only_transport"), out)
	_append_transport_segments_for_log(get_node_or_null("ImportedCity/only_transport"), out)
	var generated := get_node_or_null("RoadNetwork")
	if generated != null:
		for child in generated.get_children():
			if child is Node3D:
				out.append(child as Node3D)
	return out

func _append_transport_segments_for_log(root: Node, out: Array[Node3D]) -> void:
	if root == null:
		return
	for category in root.get_children():
		if category is not Node3D:
			continue
		for segment in (category as Node3D).get_children():
			if segment is Node3D:
				out.append(segment as Node3D)

func _collect_debug_crosswalks() -> Array[Node3D]:
	var out: Array[Node3D] = []
	_append_node3d_children_for_log(get_node_or_null("World/City/only_people_nav/only_people/Road_straight_crossing"), out)
	_append_node3d_children_for_log(get_node_or_null("ImportedCity/only_people_nav/only_people/Road_straight_crossing"), out)
	return out

func _append_node3d_children_for_log(root: Node, out: Array[Node3D]) -> void:
	if root == null:
		return
	for child in root.get_children():
		if child is Node3D:
			out.append(child as Node3D)

func _collect_debug_lights(root: Node) -> Array[Light3D]:
	var out: Array[Light3D] = []
	_collect_debug_lights_recursive(root, out)
	return out

func _collect_debug_lights_recursive(node: Node, out: Array[Light3D]) -> void:
	if node is Light3D:
		out.append(node as Light3D)
	for child in node.get_children():
		if child is Node:
			_collect_debug_lights_recursive(child as Node, out)

func _fmt_vec3(value: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [value.x, value.y, value.z]

func _update_selected_citizen_path_debug() -> void:
	if _citizen_path_debug == null or _citizen_path_debug_mesh == null:
		return

	if _selected_citizen == null or not is_instance_valid(_selected_citizen):
		_clear_selected_citizen_path_debug()
		return

	if not _selected_citizen.has_debug_travel_route():
		_clear_selected_citizen_path_debug()
		return

	var route := _selected_citizen.get_debug_travel_route_points()
	if route.size() < 2:
		_clear_selected_citizen_path_debug()
		return

	var is_active_route := _selected_citizen.is_debug_travelling()
	var route_failed := _selected_citizen.did_debug_last_travel_fail()
	var current_target := _selected_citizen.get_debug_travel_current_target()
	var current_target_idx := _selected_citizen.get_debug_travel_route_index()
	var route_material := _citizen_path_failed_material if route_failed else _citizen_path_line_material

	_citizen_path_debug.visible = true
	_citizen_path_debug.global_transform = Transform3D.IDENTITY
	_citizen_path_debug_mesh.clear_surfaces()

	var path_offset := Vector3.UP * 0.18
	_citizen_path_debug_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, route_material)
	for point in route:
		_citizen_path_debug_mesh.surface_add_vertex((point as Vector3) + path_offset)
	_citizen_path_debug_mesh.surface_end()

	if is_active_route and current_target != Vector3.ZERO:
		_citizen_path_debug_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _citizen_path_active_material)
		_citizen_path_debug_mesh.surface_add_vertex(_selected_citizen.global_position + path_offset)
		_citizen_path_debug_mesh.surface_add_vertex(current_target + path_offset)
		_add_path_debug_marker(current_target + path_offset, 0.18, 0.42)
		_citizen_path_debug_mesh.surface_end()

	_citizen_path_debug_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _citizen_path_start_material)
	_add_path_debug_marker(route[0] + path_offset, 0.18, 0.42)
	_citizen_path_debug_mesh.surface_end()

	if route.size() > 2:
		_citizen_path_debug_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _citizen_path_waypoint_material)
		for i in range(1, route.size() - 1):
			var point: Vector3 = route[i]
			if current_target_idx == i and current_target.distance_to(point) < 0.05:
				continue
			_add_path_debug_marker(point + path_offset, 0.12, 0.28)
		_citizen_path_debug_mesh.surface_end()

	_citizen_path_debug_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _citizen_path_end_material)
	_add_path_debug_marker(route[route.size() - 1] + path_offset, 0.20, 0.48)
	_citizen_path_debug_mesh.surface_end()

func _add_path_debug_marker(center: Vector3, radius: float, height: float) -> void:
	_citizen_path_debug_mesh.surface_add_vertex(center)
	_citizen_path_debug_mesh.surface_add_vertex(center + Vector3.UP * height)
	_citizen_path_debug_mesh.surface_add_vertex(center + Vector3(-radius, 0.0, 0.0))
	_citizen_path_debug_mesh.surface_add_vertex(center + Vector3(radius, 0.0, 0.0))
	_citizen_path_debug_mesh.surface_add_vertex(center + Vector3(0.0, 0.0, -radius))
	_citizen_path_debug_mesh.surface_add_vertex(center + Vector3(0.0, 0.0, radius))
	_citizen_path_debug_mesh.surface_add_vertex(center + Vector3(-radius * 0.75, 0.0, -radius * 0.75))
	_citizen_path_debug_mesh.surface_add_vertex(center + Vector3(radius * 0.75, 0.0, radius * 0.75))
	_citizen_path_debug_mesh.surface_add_vertex(center + Vector3(-radius * 0.75, 0.0, radius * 0.75))
	_citizen_path_debug_mesh.surface_add_vertex(center + Vector3(radius * 0.75, 0.0, -radius * 0.75))

func _clear_selected_citizen_path_debug() -> void:
	if _citizen_path_debug_mesh != null:
		_citizen_path_debug_mesh.clear_surfaces()
	if _citizen_path_debug != null:
		_citizen_path_debug.visible = false

func _build_hud() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	var top_margin := MarginContainer.new()
	top_margin.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_margin.offset_top = 10
	top_margin.offset_bottom = 54
	canvas.add_child(top_margin)

	var top_center := CenterContainer.new()
	top_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	top_margin.add_child(top_center)

	var time_panel := PanelContainer.new()
	top_center.add_child(time_panel)

	var time_box := HBoxContainer.new()
	time_box.add_theme_constant_override("separation", 12)
	time_panel.add_child(time_box)

	_date_label = Label.new()
	_date_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_date_label.custom_minimum_size = Vector2(104, 34)
	time_box.add_child(_date_label)

	var separator := Label.new()
	separator.text = "|"
	separator.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	time_box.add_child(separator)

	_clock_label = Label.new()
	_clock_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_clock_label.add_theme_font_size_override("font_size", 18)
	_clock_label.custom_minimum_size = Vector2(66, 34)
	time_box.add_child(_clock_label)

	var separator2 := Label.new()
	separator2.text = "|"
	separator2.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	time_box.add_child(separator2)

	_citizen_stats_label = Label.new()
	_citizen_stats_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_citizen_stats_label.custom_minimum_size = Vector2(620, 34)
	time_box.add_child(_citizen_stats_label)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.position = Vector2(10, -60)
	canvas.add_child(panel)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	panel.add_child(hbox)

	_pause_btn = Button.new()
	_pause_btn.text = "Pause"
	_pause_btn.custom_minimum_size = Vector2(100, 36)
	_pause_btn.pressed.connect(_on_pause_pressed)
	hbox.add_child(_pause_btn)

	for speed in [0.1, 0.5, 1.0, 2.0]:
		var btn := Button.new()
		btn.text = "%.1fx" % speed
		btn.custom_minimum_size = Vector2(48, 36)
		btn.pressed.connect(_on_speed_pressed.bind(float(speed)))
		hbox.add_child(btn)

	var hint := Label.new()
	hint.text = "Click citizen/building -> Info"
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.custom_minimum_size = Vector2(0, 36)
	hbox.add_child(hint)

	_speed_label = Label.new()
	_speed_label.text = "1.0x"
	_speed_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_speed_label.custom_minimum_size = Vector2(42, 36)
	hbox.add_child(_speed_label)

	world.paused_changed.connect(_on_world_paused)
	world.speed_changed.connect(_on_world_speed_changed)
	world.time.time_advanced.connect(_on_time_advanced)
	_refresh_time_hud()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		_on_pause_pressed()

	if event is InputEventMouseButton \
		and event.button_index == MOUSE_BUTTON_LEFT \
		and event.pressed:
		call_deferred("_check_deselect_this_frame")

func _check_deselect_this_frame() -> void:
	if not _entity_clicked_this_frame:
		_deselect()
	_entity_clicked_this_frame = false

func _on_pause_pressed() -> void:
	world.toggle_pause()

func _on_speed_pressed(multiplier: float) -> void:
	world.set_speed(multiplier)
	if world.is_paused:
		world.toggle_pause()

func _on_world_paused(paused: bool) -> void:
	_pause_btn.text = "Resume" if paused else "Pause"

func _on_world_speed_changed(multiplier: float) -> void:
	_speed_label.text = "%.1fx" % multiplier

func _on_time_advanced(_day: int, _hour: int, _minute: int) -> void:
	_refresh_time_hud()

func _refresh_time_hud() -> void:
	if _date_label == null or _clock_label == null or _citizen_stats_label == null or world == null or world.time == null:
		return
	_date_label.text = world.time.get_ui_date_string()
	_clock_label.text = world.time.get_time_string()
	_citizen_stats_label.text = "Citizens: %d | Unbeschaeftigt: %d | Wohnplaetze: %d/%d | Arbeitsplaetze: %d/%d" % [
		_count_registered_citizens(),
		_count_unemployed_citizens(),
		_count_used_housing_slots(),
		_count_total_housing_slots(),
		_count_filled_job_slots(),
		_count_total_job_slots()
	]

func _count_registered_citizens() -> int:
	if world == null:
		return 0
	var total := 0
	for citizen in world.citizens:
		if citizen != null:
			total += 1
	return total

func _count_unemployed_citizens() -> int:
	if world == null:
		return 0
	var unemployed := 0
	for citizen in world.citizens:
		if citizen == null:
			continue
		if citizen.job == null or citizen.job.workplace == null:
			unemployed += 1
	return unemployed

func _count_total_housing_slots() -> int:
	if world == null:
		return 0
	var total := 0
	for building in world.buildings:
		if building is ResidentialBuilding:
			total += maxi((building as ResidentialBuilding).capacity, 0)
	return total

func _count_used_housing_slots() -> int:
	if world == null:
		return 0
	var used := 0
	for building in world.buildings:
		if building is ResidentialBuilding:
			used += (building as ResidentialBuilding).tenants.size()
	return used

func _count_total_job_slots() -> int:
	if world == null:
		return 0
	var total := 0
	for building in world.buildings:
		if building == null:
			continue
		total += maxi(building.job_capacity, 0)
	return total

func _count_filled_job_slots() -> int:
	if world == null:
		return 0
	var filled := 0
	for building in world.buildings:
		if building == null:
			continue
		filled += building.workers.size()
	return filled
