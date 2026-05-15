extends RefCounted
class_name SimulationHudController

const UiThemeScript = preload("res://Simulation/UI/UiTheme.gd")

var owner_node: Node = null
var world: World = null
var canvas: CanvasLayer = null
var building_overview_button: Button = null
var citizen_overview_button: Button = null
var economy_overview_button: Button = null

var _theme: Theme = null
var _pause_button: Button = null
var _player_control_button: Button = null
var _ai_runtime_button: Button = null
var _speed_buttons: Dictionary = {}  # float speed → Button
var _speed_label: Label = null
var _date_label: Label = null
var _clock_label: Label = null
var _citizen_stats_label: Label = null
var _control_mode_panel: PanelContainer = null
var _control_mode_label: Label = null
var _ai_runtime_label: Label = null
var _ai_runtime_service = null

func setup(
	owner_ref: Node,
	world_ref: World,
	pause_pressed: Callable,
	speed_pressed: Callable,
	building_overview_pressed: Callable,
	citizen_overview_pressed: Callable,
	economy_overview_pressed: Callable,
	player_control_pressed: Callable,
	ai_runtime_pressed: Callable
) -> void:
	owner_node = owner_ref
	world = world_ref
	_build_hud(pause_pressed, speed_pressed, building_overview_pressed, citizen_overview_pressed,
			economy_overview_pressed, player_control_pressed, ai_runtime_pressed)
	_bind_world_signals()
	_refresh_time_hud()
	_refresh_pause_button()
	_refresh_speed_label()
	refresh_control_mode(null)
	set_player_control_visible(false)
	refresh_player_control_button(false)
	refresh_ai_runtime_state({})

func get_canvas() -> CanvasLayer:
	return canvas

func get_building_overview_button() -> Button:
	return building_overview_button

func get_citizen_overview_button() -> Button:
	return citizen_overview_button

func get_economy_overview_button() -> Button:
	return economy_overview_button

func refresh_control_mode(controlled_citizen: Citizen, mode_prefix: String = "CONTROL MODE", mode_hint: String = "") -> void:
	if _control_mode_panel == null or _control_mode_label == null:
		return
	if controlled_citizen == null or not is_instance_valid(controlled_citizen):
		_control_mode_panel.visible = false
		return
	_control_mode_panel.visible = true
	var control_hint := mode_hint if not mode_hint.is_empty() else "WASD Move | Space Jump | Esc Exit"
	_control_mode_label.text = "%s: %s | %s" % [mode_prefix, controlled_citizen.citizen_name, control_hint]

func set_player_control_visible(is_visible: bool) -> void:
	if _player_control_button == null:
		return
	_player_control_button.visible = is_visible

func refresh_player_control_button(is_active: bool) -> void:
	if _player_control_button == null:
		return
	_player_control_button.text = "Exit Player" if is_active else "Control Player"
	UiThemeScript.apply_accent_state(_player_control_button, is_active)

func bind_dialogue_runtime_service(dialogue_runtime_service_ref) -> void:
	_ai_runtime_service = dialogue_runtime_service_ref
	if _ai_runtime_service == null:
		refresh_ai_runtime_state({})
		return
	if _ai_runtime_service.has_signal("status_changed"):
		var status_cb := Callable(self, "_on_ai_runtime_status_changed")
		if not _ai_runtime_service.status_changed.is_connected(status_cb):
			_ai_runtime_service.status_changed.connect(status_cb)
	if _ai_runtime_service.has_method("get_ui_runtime_state"):
		refresh_ai_runtime_state(_ai_runtime_service.get_ui_runtime_state())

func refresh_ai_runtime_state(ui_state: Dictionary) -> void:
	if _ai_runtime_label == null or _ai_runtime_button == null:
		return
	var summary_text := "AI: Offline"
	var button_visible := false
	var button_enabled := false
	var button_text := "Setup AI"
	if not ui_state.is_empty():
		summary_text = str(ui_state.get("summary_text", summary_text))
		button_visible = bool(ui_state.get("button_visible", false))
		button_enabled = bool(ui_state.get("button_enabled", false))
		button_text = str(ui_state.get("button_text", button_text))
	_ai_runtime_label.text = summary_text
	_ai_runtime_button.visible = button_visible
	_ai_runtime_button.disabled = not button_enabled
	_ai_runtime_button.text = button_text

func _build_hud(
	pause_pressed: Callable,
	speed_pressed: Callable,
	building_overview_pressed: Callable,
	citizen_overview_pressed: Callable,
	economy_overview_pressed: Callable,
	player_control_pressed: Callable,
	ai_runtime_pressed: Callable
) -> void:
	if owner_node == null:
		return

	canvas = CanvasLayer.new()
	owner_node.add_child(canvas)

	# CanvasLayer is not a Control, so it cannot hold a Theme — children
	# attached to it don't automatically inherit theming. Cache one Theme
	# instance per session and assign it to each top-level Control we build
	# directly under the canvas. Nested Control children then inherit normally.
	_theme = UiThemeScript.get_or_build()

	_build_top_time_panel()
	_build_bottom_action_bar(pause_pressed, speed_pressed, building_overview_pressed,
			citizen_overview_pressed, economy_overview_pressed,
			player_control_pressed, ai_runtime_pressed)
	_build_control_mode_banner()


func _build_top_time_panel() -> void:
	# Symmetric with the bottom action bar: top-left, 12 px margin.
	var time_panel := PanelContainer.new()
	time_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	time_panel.position = Vector2(12, 12)
	time_panel.theme = _theme
	canvas.add_child(time_panel)

	var time_box := HBoxContainer.new()
	time_box.add_theme_constant_override("separation", UiThemeScript.SEPARATION_LOOSE)
	time_panel.add_child(time_box)

	_date_label = Label.new()
	_date_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_date_label.add_theme_color_override("font_color", UiThemeScript.TEXT_SECONDARY)
	_date_label.add_theme_font_size_override("font_size", UiThemeScript.FONT_SIZE_BODY)
	_date_label.custom_minimum_size = Vector2(120, 36)
	time_box.add_child(_date_label)

	time_box.add_child(_make_v_divider())

	_clock_label = Label.new()
	_clock_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_clock_label.add_theme_font_size_override("font_size", UiThemeScript.FONT_SIZE_HEADING)
	_clock_label.add_theme_color_override("font_color", UiThemeScript.ACCENT)
	_clock_label.custom_minimum_size = Vector2(78, 36)
	time_box.add_child(_clock_label)

	time_box.add_child(_make_v_divider())

	_citizen_stats_label = Label.new()
	_citizen_stats_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_citizen_stats_label.add_theme_color_override("font_color", UiThemeScript.TEXT_SECONDARY)
	_citizen_stats_label.add_theme_font_size_override("font_size", UiThemeScript.FONT_SIZE_BODY)
	_citizen_stats_label.custom_minimum_size = Vector2(620, 36)
	time_box.add_child(_citizen_stats_label)


func _build_bottom_action_bar(
	pause_pressed: Callable,
	speed_pressed: Callable,
	building_overview_pressed: Callable,
	citizen_overview_pressed: Callable,
	economy_overview_pressed: Callable,
	player_control_pressed: Callable,
	ai_runtime_pressed: Callable
) -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.position = Vector2(12, -72)
	panel.theme = _theme
	canvas.add_child(panel)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", UiThemeScript.SEPARATION_NORMAL)
	panel.add_child(hbox)

	# Pause: prominent toggle on the left.
	_pause_button = Button.new()
	_pause_button.text = "Pause"
	_pause_button.custom_minimum_size = Vector2(96, 36)
	_pause_button.focus_mode = Control.FOCUS_NONE
	if pause_pressed.is_valid():
		_pause_button.pressed.connect(pause_pressed)
	hbox.add_child(_pause_button)

	hbox.add_child(_make_v_divider())

	# Speed buttons grouped as one cluster — active multiplier gets accent.
	for speed in [1, 2, 3, 4]:
		var btn := Button.new()
		btn.text = "%dx" % speed
		btn.custom_minimum_size = Vector2(44, 36)
		btn.focus_mode = Control.FOCUS_NONE
		if speed_pressed.is_valid():
			btn.pressed.connect(speed_pressed.bind(float(speed)))
		hbox.add_child(btn)
		_speed_buttons[float(speed)] = btn

	hbox.add_child(_make_v_divider())

	building_overview_button = Button.new()
	building_overview_button.text = "Buildings"
	building_overview_button.custom_minimum_size = Vector2(96, 36)
	building_overview_button.focus_mode = Control.FOCUS_NONE
	if building_overview_pressed.is_valid():
		building_overview_button.pressed.connect(building_overview_pressed)
	hbox.add_child(building_overview_button)

	citizen_overview_button = Button.new()
	citizen_overview_button.text = "Citizens"
	citizen_overview_button.custom_minimum_size = Vector2(96, 36)
	citizen_overview_button.focus_mode = Control.FOCUS_NONE
	if citizen_overview_pressed.is_valid():
		citizen_overview_button.pressed.connect(citizen_overview_pressed)
	hbox.add_child(citizen_overview_button)

	economy_overview_button = Button.new()
	economy_overview_button.text = "Economy"
	economy_overview_button.custom_minimum_size = Vector2(96, 36)
	economy_overview_button.focus_mode = Control.FOCUS_NONE
	if economy_overview_pressed.is_valid():
		economy_overview_button.pressed.connect(economy_overview_pressed)
	hbox.add_child(economy_overview_button)

	_player_control_button = Button.new()
	_player_control_button.text = "Control Player"
	_player_control_button.custom_minimum_size = Vector2(120, 36)
	_player_control_button.focus_mode = Control.FOCUS_NONE
	_player_control_button.visible = false
	if player_control_pressed.is_valid():
		_player_control_button.pressed.connect(player_control_pressed)
	hbox.add_child(_player_control_button)

	_ai_runtime_button = Button.new()
	_ai_runtime_button.text = "Setup AI"
	_ai_runtime_button.custom_minimum_size = Vector2(104, 36)
	_ai_runtime_button.focus_mode = Control.FOCUS_NONE
	_ai_runtime_button.visible = false
	if ai_runtime_pressed.is_valid():
		_ai_runtime_button.pressed.connect(ai_runtime_pressed)
	hbox.add_child(_ai_runtime_button)

	hbox.add_child(_make_v_divider())

	var hint := Label.new()
	hint.text = "Click citizen / building for info"
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", UiThemeScript.TEXT_MUTED)
	hint.add_theme_font_size_override("font_size", UiThemeScript.FONT_SIZE_SMALL)
	hint.custom_minimum_size = Vector2(0, 36)
	hbox.add_child(hint)

	_ai_runtime_label = Label.new()
	_ai_runtime_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ai_runtime_label.add_theme_color_override("font_color", UiThemeScript.TEXT_SECONDARY)
	_ai_runtime_label.add_theme_font_size_override("font_size", UiThemeScript.FONT_SIZE_SMALL)
	_ai_runtime_label.custom_minimum_size = Vector2(220, 36)
	hbox.add_child(_ai_runtime_label)

	# Compact current-speed indicator at the far right.
	_speed_label = Label.new()
	_speed_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_speed_label.add_theme_color_override("font_color", UiThemeScript.ACCENT)
	_speed_label.add_theme_font_size_override("font_size", UiThemeScript.FONT_SIZE_LABEL)
	_speed_label.custom_minimum_size = Vector2(50, 36)
	hbox.add_child(_speed_label)


func _build_control_mode_banner() -> void:
	_control_mode_panel = PanelContainer.new()
	_control_mode_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_control_mode_panel.position = Vector2(12, 12)
	_control_mode_panel.visible = false
	_control_mode_panel.theme = _theme
	# Accent-tinted banner — clearly different from a passive info panel.
	var banner_box := StyleBoxFlat.new()
	banner_box.bg_color = UiThemeScript.BG_900
	banner_box.border_color = UiThemeScript.ACCENT
	banner_box.border_width_left = 4
	banner_box.border_width_top = UiThemeScript.BORDER_WIDTH
	banner_box.border_width_right = UiThemeScript.BORDER_WIDTH
	banner_box.border_width_bottom = UiThemeScript.BORDER_WIDTH
	banner_box.corner_radius_top_left = UiThemeScript.RADIUS_PANEL
	banner_box.corner_radius_top_right = UiThemeScript.RADIUS_PANEL
	banner_box.corner_radius_bottom_left = UiThemeScript.RADIUS_PANEL
	banner_box.corner_radius_bottom_right = UiThemeScript.RADIUS_PANEL
	banner_box.content_margin_left = 16
	banner_box.content_margin_right = UiThemeScript.PADDING_PANEL_H
	banner_box.content_margin_top = UiThemeScript.PADDING_PANEL_V
	banner_box.content_margin_bottom = UiThemeScript.PADDING_PANEL_V
	_control_mode_panel.add_theme_stylebox_override("panel", banner_box)
	canvas.add_child(_control_mode_panel)

	_control_mode_label = Label.new()
	_control_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_control_mode_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_control_mode_label.add_theme_font_size_override("font_size", UiThemeScript.FONT_SIZE_LABEL)
	_control_mode_label.custom_minimum_size = Vector2(520, 32)
	_control_mode_panel.add_child(_control_mode_label)


## 1-px vertical divider with margins — used to group the action bar.
func _make_v_divider() -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(1, 26)
	spacer.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var divider_panel := PanelContainer.new()
	divider_panel.custom_minimum_size = Vector2(1, 26)
	divider_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiThemeScript.BORDER
	divider_panel.add_theme_stylebox_override("panel", sb)
	return divider_panel

func _on_ai_runtime_status_changed(_status: String, _detail: String) -> void:
	if _ai_runtime_service != null and _ai_runtime_service.has_method("get_ui_runtime_state"):
		refresh_ai_runtime_state(_ai_runtime_service.get_ui_runtime_state())

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
	# Paused = accent-on, so the player always sees the current state.
	UiThemeScript.apply_accent_state(_pause_button, world.is_paused)

func _refresh_speed_label() -> void:
	if _speed_label == null or world == null:
		return
	_speed_label.text = "%.0fx" % world.speed_multiplier
	# Highlight the speed button matching the current multiplier.
	var current_speed := world.speed_multiplier
	for speed_key in _speed_buttons.keys():
		var btn: Button = _speed_buttons[speed_key]
		if btn == null:
			continue
		var is_active := is_equal_approx(float(speed_key), current_speed)
		UiThemeScript.apply_accent_state(btn, is_active)

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
