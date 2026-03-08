extends Node3D

@onready var world: World = $World

const CITIZEN_COUNT := 6

var _pause_btn: Button
var _speed_label: Label
var _debug_panel: DebugPanel
var _selected_citizen: Citizen = null
var _citizen_clicked_this_frame: bool = false

func _ready() -> void:
	get_viewport().physics_object_picking = true

	NavigationSetup.ensure_region(self, world)
	WorldSetup.configure_scene_buildings(get_tree(), world)

	_build_debug_panel()
	_spawn_citizens()
	_build_hud()

func _build_debug_panel() -> void:
	_debug_panel = preload("res://Scenes/DebugPanel.tscn").instantiate()
	add_child(_debug_panel)
	_debug_panel.visible = false

func _spawn_citizens() -> void:
	var spawned := CitizenFactory.spawn_citizens(self, world, CITIZEN_COUNT)
	for citizen in spawned:
		citizen.clicked.connect(_on_citizen_clicked.bind(citizen))
		citizen.clicked.connect(_on_citizen_clicked_frame_flag.bind(citizen))

func _on_citizen_clicked(c: Citizen) -> void:
	if _selected_citizen == c:
		_deselect()
		return

	if _selected_citizen != null:
		_selected_citizen.select(null)

	_selected_citizen = c
	c.select(_debug_panel)
	_debug_panel.visible = true

func _deselect() -> void:
	if _selected_citizen != null:
		_selected_citizen.select(null)
		_selected_citizen = null
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
	hint.text = "Click citizen -> Debug"
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.custom_minimum_size = Vector2(0, 36)
	hbox.add_child(hint)

	_speed_label = Label.new()
	_speed_label.text = "1x"
	_speed_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_speed_label.custom_minimum_size = Vector2(36, 36)
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
	if not _citizen_clicked_this_frame:
		_deselect()
	_citizen_clicked_this_frame = false

func _on_citizen_clicked_frame_flag(_c: Citizen) -> void:
	_citizen_clicked_this_frame = true

func _on_pause_pressed() -> void:
	world.toggle_pause()

func _on_speed_pressed(multiplier: float) -> void:
	world.set_speed(multiplier)
	if world.is_paused:
		world.toggle_pause()

func _on_world_paused(paused: bool) -> void:
	_pause_btn.text = "Resume" if paused else "Pause"

func _on_world_speed_changed(multiplier: float) -> void:
	_speed_label.text = "%dx" % int(multiplier)