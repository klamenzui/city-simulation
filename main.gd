extends Node3D

@onready var world: World = $World

const CITIZEN_COUNT := 6
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

var _pause_btn: Button
var _speed_label: Label
var _debug_panel: DebugPanel
var _selected_citizen: Citizen = null
var _selected_building: Building = null
var _entity_clicked_this_frame: bool = false
var _building_panel_refresh_left: float = 0.0

func _ready() -> void:
	get_viewport().physics_object_picking = true

	_setup_world_systems()
	_build_debug_panel()
	_bind_building_clicks()
	_spawn_citizens()
	_build_hud()

func _process(delta: float) -> void:
	if _selected_building == null or _debug_panel == null or not _debug_panel.visible:
		return
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

func _on_citizen_clicked(c: Citizen) -> void:
	_entity_clicked_this_frame = true

	if _selected_citizen == c:
		_deselect()
		return

	if _selected_building != null:
		_selected_building.select(null, world)
		_selected_building = null

	if _selected_citizen != null:
		_selected_citizen.select(null)

	_selected_citizen = c
	c.select(_debug_panel)
	_debug_panel.visible = true

func _on_building_clicked(b: Building) -> void:
	_entity_clicked_this_frame = true

	if _selected_building == b:
		_deselect()
		return

	if _selected_citizen != null:
		_selected_citizen.select(null)
		_selected_citizen = null

	if _selected_building != null:
		_selected_building.select(null, world)

	_selected_building = b
	b.select(_debug_panel, world)
	_debug_panel.visible = true
	_building_panel_refresh_left = 0.0

func _deselect() -> void:
	if _selected_citizen != null:
		_selected_citizen.select(null)
		_selected_citizen = null
	if _selected_building != null:
		_selected_building.select(null, world)
		_selected_building = null
	if _debug_panel != null:
		_debug_panel.visible = false

func _build_hud() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

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
