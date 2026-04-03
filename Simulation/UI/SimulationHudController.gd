extends RefCounted
class_name SimulationHudController

var owner_node: Node = null
var world: World = null
var canvas: CanvasLayer = null
var building_overview_button: Button = null

var _pause_button: Button = null
var _speed_label: Label = null
var _date_label: Label = null
var _clock_label: Label = null
var _citizen_stats_label: Label = null
var _control_mode_panel: PanelContainer = null
var _control_mode_label: Label = null

func setup(
	owner_ref: Node,
	world_ref: World,
	pause_pressed: Callable,
	speed_pressed: Callable,
	building_overview_pressed: Callable
) -> void:
	owner_node = owner_ref
	world = world_ref
	_build_hud(pause_pressed, speed_pressed, building_overview_pressed)
	_bind_world_signals()
	_refresh_time_hud()
	_refresh_pause_button()
	_refresh_speed_label()
	refresh_control_mode(null)

func get_canvas() -> CanvasLayer:
	return canvas

func get_building_overview_button() -> Button:
	return building_overview_button

func refresh_control_mode(controlled_citizen: Citizen) -> void:
	if _control_mode_panel == null or _control_mode_label == null:
		return
	if controlled_citizen == null or not is_instance_valid(controlled_citizen):
		_control_mode_panel.visible = false
		return
	_control_mode_panel.visible = true
	_control_mode_label.text = "CONTROL MODE: %s | WASD Move | Space Jump | Esc Exit" % controlled_citizen.citizen_name

func _build_hud(
	pause_pressed: Callable,
	speed_pressed: Callable,
	building_overview_pressed: Callable
) -> void:
	if owner_node == null:
		return

	canvas = CanvasLayer.new()
	owner_node.add_child(canvas)

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

	_pause_button = Button.new()
	_pause_button.text = "Pause"
	_pause_button.custom_minimum_size = Vector2(100, 36)
	if pause_pressed.is_valid():
		_pause_button.pressed.connect(pause_pressed)
	hbox.add_child(_pause_button)

	for speed in [1, 2, 3, 4]:
		var btn := Button.new()
		btn.text = "%.1fx" % speed
		btn.custom_minimum_size = Vector2(48, 36)
		if speed_pressed.is_valid():
			btn.pressed.connect(speed_pressed.bind(float(speed)))
		hbox.add_child(btn)

	building_overview_button = Button.new()
	building_overview_button.text = "Buildings"
	building_overview_button.custom_minimum_size = Vector2(92, 36)
	if building_overview_pressed.is_valid():
		building_overview_button.pressed.connect(building_overview_pressed)
	hbox.add_child(building_overview_button)

	var hint := Label.new()
	hint.text = "Click citizen/building -> Info"
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.custom_minimum_size = Vector2(0, 36)
	hbox.add_child(hint)

	_speed_label = Label.new()
	_speed_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_speed_label.custom_minimum_size = Vector2(42, 36)
	hbox.add_child(_speed_label)

	_control_mode_panel = PanelContainer.new()
	_control_mode_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_control_mode_panel.position = Vector2(10, 10)
	_control_mode_panel.visible = false
	canvas.add_child(_control_mode_panel)

	_control_mode_label = Label.new()
	_control_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_control_mode_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_control_mode_label.custom_minimum_size = Vector2(520, 32)
	_control_mode_panel.add_child(_control_mode_label)

func _bind_world_signals() -> void:
	if world == null:
		return

	var paused_cb := Callable(self, "_on_world_paused")
	if not world.paused_changed.is_connected(paused_cb):
		world.paused_changed.connect(paused_cb)

	var speed_cb := Callable(self, "_on_world_speed_changed")
	if not world.speed_changed.is_connected(speed_cb):
		world.speed_changed.connect(speed_cb)

	if world.time != null:
		var time_cb := Callable(self, "_on_time_advanced")
		if not world.time.time_advanced.is_connected(time_cb):
			world.time.time_advanced.connect(time_cb)

func _on_world_paused(_paused: bool) -> void:
	_refresh_pause_button()

func _on_world_speed_changed(_multiplier: float) -> void:
	_refresh_speed_label()

func _on_time_advanced(_day: int, _hour: int, _minute: int) -> void:
	_refresh_time_hud()

func _refresh_pause_button() -> void:
	if _pause_button == null or world == null:
		return
	_pause_button.text = "Resume" if world.is_paused else "Pause"

func _refresh_speed_label() -> void:
	if _speed_label == null or world == null:
		return
	_speed_label.text = "%.1fx" % world.speed_multiplier

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
