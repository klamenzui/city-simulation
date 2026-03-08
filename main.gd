extends Node3D

@onready var world: World = $World

var _pause_btn: Button
var _speed_label: Label
var _debug_panel: DebugPanel
var _selected_citizen: Citizen = null

# ── Konfiguration ──────────────────────────────────────────────────────────────
const CITIZEN_COUNT := 6

const FIRST_NAMES := [
	"Alex", "Maria", "Jonas", "Sophie", "Luca", "Emma", "Finn", "Mia",
	"Noah", "Lea", "Ben", "Hannah", "Leon", "Anna", "Felix", "Laura",
	"Paul", "Clara", "Max", "Lisa", "Tom", "Julia", "Jan", "Sara",
	"Erik", "Nora", "David", "Lena", "Simon", "Eva"
]

const LAST_NAMES := [
	"Müller", "Schmidt", "Weber", "Fischer", "Meyer", "Wagner", "Becker",
	"Schulz", "Hoffmann", "Koch", "Richter", "Klein", "Wolf", "Schröder",
	"Neumann", "Schwarz", "Zimmermann", "Braun", "Krüger", "Hartmann"
]

# ── Godot Lifecycle ────────────────────────────────────────────────────────────
func _ready() -> void:
	# Physik-Picking aktivieren (nötig für Area3D-Klicks im 3D-Viewport)
	get_viewport().physics_object_picking = true
	for node in get_tree().get_nodes_in_group("buildings"):
		if node is Building:
			world.register_building(node)
			if "work" in node.get_groups() and node.job_capacity == 0:
				node.job_capacity = 1
			if node is ResidentialBuilding:
				# BUG FIX: Rent 50§/day was too high relative to wages (citizens earn ~40-60§/day
				# working only 2-3h). Combined with 2-3 meals × 15§ = 30-45§/day, citizens went
				# broke within 3 days. Reduced to 15§/day for a realistic balance.
				node.rent_per_day = 15
				world.time.rent_due.connect(node.charge_rent.bind(world))

	_build_debug_panel()
	_spawn_citizens()
	_build_hud()

# ── Debug-Panel (wird nur bei selektiertem Citizen angezeigt) ──────────────────
func _build_debug_panel() -> void:
	_debug_panel = preload("res://Scenes/DebugPanel.tscn").instantiate()
	add_child(_debug_panel)
	_debug_panel.visible = false

# ── Citizen-Spawner ────────────────────────────────────────────────────────────
func _spawn_citizens() -> void:
	var names_pool := FIRST_NAMES.duplicate()
	names_pool.shuffle()
	var last_pool := LAST_NAMES.duplicate()
	last_pool.shuffle()

	var citizen_scene: PackedScene = preload("res://Entities/Citizens/Citizen.tscn")

	for i in CITIZEN_COUNT:
		var c: Citizen = citizen_scene.instantiate()

		# Zufälliger Name
		var fname: String = names_pool[i % names_pool.size()]
		var lname: String = last_pool[i % last_pool.size()]
		c.citizen_name = "%s %s" % [fname, lname]

		# Zufälliger Job
		var j := Job.new()
		j.title      = _random_job_title()
		j.wage_per_hour = randi_range(10, 22)
		j.start_hour    = randi_range(7, 9)
		j.shift_hours   = 8
		c.job = j

		add_child(c)
		world.register_citizen(c)

		# Klick-Signal verbinden (Citizen.gd emittiert es via Area3D)
		c.clicked.connect(_on_citizen_clicked.bind(c))

func _random_job_title() -> String:
	var titles := ["Bäcker", "Lehrer", "Ingenieur", "Kellner", "Programmierer",
				   "Fahrer", "Mechaniker", "Arzt", "Verkäufer", "Designer"]
	return titles[randi() % titles.size()]

# ── Selektion ──────────────────────────────────────────────────────────────────
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

# ── HUD ───────────────────────────────────────────────────────────────────────
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

	# ── Pause button ──────────────────────────────────
	_pause_btn = Button.new()
	_pause_btn.text = "⏸ Pause"
	_pause_btn.custom_minimum_size = Vector2(100, 36)
	_pause_btn.pressed.connect(_on_pause_pressed)
	hbox.add_child(_pause_btn)

	# ── Speed buttons ─────────────────────────────────
	for speed in [0.1, 0.5, 1, 2]:
		var btn := Button.new()
		btn.text = "%.1fx" % speed
		btn.custom_minimum_size = Vector2(48, 36)
		btn.pressed.connect(_on_speed_pressed.bind(float(speed)))
		hbox.add_child(btn)

	# ── Hint label ────────────────────────────────────
	var hint := Label.new()
	hint.text = "  Klick auf Citizen → Debug"
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.custom_minimum_size = Vector2(0, 36)
	hbox.add_child(hint)

	# ── Current speed label ───────────────────────────
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

	# Klick ins Leere → deselektieren
	if event is InputEventMouseButton \
		and event.button_index == MOUSE_BUTTON_LEFT \
		and event.pressed:
		# Kleiner Frame-Delay: Area3D input_event wird ZUERST gefeuert,
		# danach kommt _input. Wenn kein Citizen verarbeitet hat,
		# deselektieren wir. Flag wird in Citizen.gd gesetzt.
		call_deferred("_check_deselect_this_frame")

var _citizen_clicked_this_frame := false

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
	_pause_btn.text = "▶ Resume" if paused else "⏸ Pause"

func _on_world_speed_changed(multiplier: float) -> void:
	_speed_label.text = "%dx" % int(multiplier)
