extends RefCounted
class_name SimulationHudController

## Persistent in-game chrome: a full-width top resource bar and a left
## vertical icon-navigation sidebar (city-builder style). Replaces the old
## bottom action bar. Public API is unchanged — SceneRuntimeController and
## SelectionStateController still drive it through the same methods.

const UiThemeScript = preload("res://Simulation/UI/UiTheme.gd")
const NetworkRoleScript = preload("res://Simulation/Multiplayer/shared/NetworkRole.gd")

const _SPEED_STEPS: Array[float] = [1.0, 2.0, 3.0, 4.0]
const _HUD_STATUS_REFRESH_INTERVAL_SEC := 0.12

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
var _speed_button: Button = null
var _date_label: Label = null
var _clock_label: Label = null
var _treasury_label: Label = null
var _population_label: Label = null
var _housing_jobs_label: Label = null
var _satisfaction_label: Label = null
var _network_status_label: Label = null
var _network_interaction_label: Label = null
var _control_mode_panel: PanelContainer = null
var _control_mode_label: Label = null
var _ai_runtime_label: Label = null
var _ai_runtime_service = null
var multiplayer_session = null
var _hud_status_refresh_left: float = 0.0

# Balance at the start of the current in-game day — drives the "today" delta.
var _treasury_day_start: int = 0

func setup(
	owner_ref: Node,
	world_ref: World,
	pause_pressed: Callable,
	speed_pressed: Callable,
	building_overview_pressed: Callable,
	citizen_overview_pressed: Callable,
	economy_overview_pressed: Callable,
	player_control_pressed: Callable,
	ai_runtime_pressed: Callable,
	multiplayer_session_ref = null
) -> void:
	owner_node = owner_ref
	world = world_ref
	multiplayer_session = multiplayer_session_ref
	if world != null and world.city_account != null:
		_treasury_day_start = world.city_account.balance
	_build_hud(pause_pressed, speed_pressed, building_overview_pressed, citizen_overview_pressed,
			economy_overview_pressed, player_control_pressed, ai_runtime_pressed)
	_bind_world_signals()
	_bind_multiplayer_session()
	_refresh_time_hud()
	_refresh_stats()
	_refresh_pause_button()
	_refresh_speed_label()
	_refresh_network_status()
	_refresh_network_interaction_status()
	_refresh_authority_controls()
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

func update(delta: float) -> void:
	_hud_status_refresh_left -= delta
	if _hud_status_refresh_left > 0.0:
		return
	_hud_status_refresh_left = _HUD_STATUS_REFRESH_INTERVAL_SEC
	_refresh_network_status()
	_refresh_network_interaction_status()

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
	_player_control_button.visible = is_visible and not _is_network_client()

func refresh_player_control_button(is_active: bool) -> void:
	if _player_control_button == null:
		return
	if _is_network_client():
		_player_control_button.disabled = true
		_player_control_button.tooltip_text = "Clients steuern Citizens erst in Phase 2."
		return
	_player_control_button.disabled = false
	_player_control_button.tooltip_text = ""
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

func bind_multiplayer_session(multiplayer_session_ref) -> void:
	multiplayer_session = multiplayer_session_ref
	_bind_multiplayer_session()
	_refresh_network_status()
	_refresh_network_interaction_status()
	_refresh_authority_controls()

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

	# CanvasLayer is not a Control, so it cannot hold a Theme — every top-level
	# Control we attach to it must set `.theme` explicitly. Children inherit.
	_theme = UiThemeScript.get_or_build()

	_build_top_bar(pause_pressed, speed_pressed)
	_build_bottom_action_bar(building_overview_pressed, citizen_overview_pressed,
			economy_overview_pressed, player_control_pressed, ai_runtime_pressed)
	_build_control_mode_banner()


func _build_top_bar(pause_pressed: Callable, speed_pressed: Callable) -> void:
	var bar := PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = 0
	bar.offset_top = 0
	bar.offset_right = 0
	bar.offset_bottom = UiThemeScript.TOPBAR_HEIGHT
	bar.theme = _theme
	# Square top edge — reads as an anchored bar, not a floating panel.
	var bar_box := UiThemeScript._make_panel_box(0, UiThemeScript.BG_900, UiThemeScript.BORDER)
	bar_box.corner_radius_top_left = 0
	bar_box.corner_radius_top_right = 0
	bar_box.content_margin_left = UiThemeScript.PADDING_PANEL_H
	bar_box.content_margin_right = UiThemeScript.PADDING_PANEL_H
	bar_box.content_margin_top = 6
	bar_box.content_margin_bottom = 6
	bar.add_theme_stylebox_override("panel", bar_box)
	canvas.add_child(bar)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", UiThemeScript.SEPARATION_NORMAL)
	bar.add_child(hbox)

	# Left: pause toggle.
	_pause_button = Button.new()
	_pause_button.text = "Pause"
	_pause_button.custom_minimum_size = Vector2(84, 40)
	_pause_button.focus_mode = Control.FOCUS_NONE
	if pause_pressed.is_valid():
		_pause_button.pressed.connect(pause_pressed)
	hbox.add_child(_pause_button)

	hbox.add_child(_make_v_divider())

	# Time cluster: date + clock chips, then one cycling speed button.
	_date_label = _make_stat_chip(hbox, "DATUM", UiThemeScript.TEXT_PRIMARY, 112)
	_clock_label = _make_stat_chip(hbox, "ZEIT", UiThemeScript.ACCENT, 62)

	_speed_button = Button.new()
	_speed_button.text = "Tempo x1"
	_speed_button.tooltip_text = "Simulationstempo umschalten (1x -> 4x)"
	_speed_button.custom_minimum_size = Vector2(90, 40)
	_speed_button.focus_mode = Control.FOCUS_NONE
	if speed_pressed.is_valid():
		_speed_button.pressed.connect(_on_speed_cycle_pressed.bind(speed_pressed))
	hbox.add_child(_speed_button)

	_network_status_label = _make_stat_chip(hbox, "NETZ", UiThemeScript.TEXT_SECONDARY, 120)
	_network_interaction_label = _make_stat_chip(hbox, "AKTION", UiThemeScript.TEXT_SECONDARY, 116)

	hbox.add_child(_make_v_divider())

	# City stat chips.
	_treasury_label = _make_stat_chip(hbox, "STADTKASSE", UiThemeScript.TEXT_PRIMARY, 178)
	_population_label = _make_stat_chip(hbox, "EINWOHNER", UiThemeScript.TEXT_PRIMARY, 122)
	_housing_jobs_label = _make_stat_chip(hbox, "WOHNEN / JOBS", UiThemeScript.TEXT_PRIMARY, 112)
	_satisfaction_label = _make_stat_chip(hbox, "ZUFRIEDENHEIT", UiThemeScript.SUCCESS, 76)

	# Spacer so the AI status sits flush right.
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	_ai_runtime_label = Label.new()
	_ai_runtime_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ai_runtime_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ai_runtime_label.add_theme_color_override("font_color", UiThemeScript.TEXT_SECONDARY)
	_ai_runtime_label.add_theme_font_size_override("font_size", UiThemeScript.FONT_SIZE_SMALL)
	_ai_runtime_label.custom_minimum_size = Vector2(150, 40)
	hbox.add_child(_ai_runtime_label)


func _build_bottom_action_bar(
	building_overview_pressed: Callable,
	citizen_overview_pressed: Callable,
	economy_overview_pressed: Callable,
	player_control_pressed: Callable,
	ai_runtime_pressed: Callable
) -> void:
	# Bottom-left bar. The left details panel reserves ~72 px here
	# (DebugPanel offset_bottom = -84), so it never overlaps this bar.
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.position = Vector2(12, -72)
	panel.theme = _theme
	canvas.add_child(panel)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", UiThemeScript.SEPARATION_NORMAL)
	panel.add_child(hbox)

	building_overview_button = _make_bar_button(hbox, "Gebaeude", 110, building_overview_pressed)
	citizen_overview_button = _make_bar_button(hbox, "Buerger", 110, citizen_overview_pressed)
	economy_overview_button = _make_bar_button(hbox, "Finanzen", 110, economy_overview_pressed)

	hbox.add_child(_make_v_divider())

	_player_control_button = _make_bar_button(hbox, "Control Player", 130, player_control_pressed)
	_player_control_button.visible = false

	_ai_runtime_button = _make_bar_button(hbox, "Setup AI", 110, ai_runtime_pressed)
	_ai_runtime_button.visible = false

	hbox.add_child(_make_v_divider())

	var hint := Label.new()
	hint.text = "Klick auf Buerger / Gebaeude fuer Infos"
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", UiThemeScript.TEXT_MUTED)
	hint.add_theme_font_size_override("font_size", UiThemeScript.FONT_SIZE_SMALL)
	hint.custom_minimum_size = Vector2(0, 36)
	hbox.add_child(hint)


func _build_control_mode_banner() -> void:
	_control_mode_panel = PanelContainer.new()
	_control_mode_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	# Below the top bar, right of the left details panel (~392 px wide).
	_control_mode_panel.position = Vector2(404, UiThemeScript.TOPBAR_HEIGHT + 12)
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


## Caption-over-value chip for the top bar. Returns the value Label so the
## refresh code can update it; the caption is static.
func _make_stat_chip(parent: Node, caption: String, value_color: Color, min_width: int) -> Label:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.custom_minimum_size = Vector2(min_width, 44)
	parent.add_child(box)

	var caption_label := Label.new()
	caption_label.text = caption
	caption_label.add_theme_color_override("font_color", UiThemeScript.TEXT_MUTED)
	caption_label.add_theme_font_size_override("font_size", UiThemeScript.FONT_SIZE_SMALL)
	box.add_child(caption_label)

	var value_label := Label.new()
	value_label.text = "-"
	value_label.add_theme_color_override("font_color", value_color)
	value_label.add_theme_font_size_override("font_size", UiThemeScript.FONT_SIZE_HEADING)
	box.add_child(value_label)
	return value_label


func _make_bar_button(parent: Node, text: String, min_width: int, on_pressed: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(min_width, 36)
	btn.focus_mode = Control.FOCUS_NONE
	if on_pressed.is_valid():
		btn.pressed.connect(on_pressed)
	parent.add_child(btn)
	return btn


## 1-px vertical divider with margins — groups the bar clusters.
func _make_v_divider() -> Control:
	var divider_panel := PanelContainer.new()
	divider_panel.custom_minimum_size = Vector2(1, 26)
	divider_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiThemeScript.BORDER
	divider_panel.add_theme_stylebox_override("panel", sb)
	return divider_panel


func _on_speed_cycle_pressed(speed_pressed: Callable) -> void:
	if not speed_pressed.is_valid():
		return
	var current := world.speed_multiplier if world != null else 1.0
	var next_speed := _SPEED_STEPS[0]
	for step in _SPEED_STEPS:
		if step > current + 0.01:
			next_speed = step
			break
	speed_pressed.call(next_speed)


func _on_ai_runtime_status_changed(_status: String, _detail: String) -> void:
	if _ai_runtime_service != null and _ai_runtime_service.has_method("get_ui_runtime_state"):
		refresh_ai_runtime_state(_ai_runtime_service.get_ui_runtime_state())

func _on_multiplayer_status_changed(_status: String, _detail: String) -> void:
	_refresh_network_status()
	_refresh_network_interaction_status()
	_refresh_authority_controls()

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
		var day_cb := Callable(self, "_on_day_changed")
		if not world.time.day_changed.is_connected(day_cb):
			world.time.day_changed.connect(day_cb)

func _bind_multiplayer_session() -> void:
	if multiplayer_session == null or not multiplayer_session.has_signal("status_changed"):
		return
	var status_cb := Callable(self, "_on_multiplayer_status_changed")
	if not multiplayer_session.status_changed.is_connected(status_cb):
		multiplayer_session.status_changed.connect(status_cb)

func _on_world_paused(_paused: bool) -> void:
	_refresh_pause_button()

func _on_world_speed_changed(_multiplier: float) -> void:
	_refresh_speed_label()

func _on_time_advanced(_day: int, _hour: int, _minute: int) -> void:
	_refresh_time_hud()
	_refresh_stats()

func _on_day_changed(_day: int) -> void:
	# Snapshot the day's opening balance so the treasury delta is "since
	# midnight". Runs before World processes the day's economy.
	if world != null and world.city_account != null:
		_treasury_day_start = world.city_account.balance
	_refresh_stats()

func _refresh_pause_button() -> void:
	if _pause_button == null or world == null:
		return
	_pause_button.text = "Resume" if world.is_paused else "Pause"
	# Paused = accent-on, so the player always sees the current state.
	UiThemeScript.apply_accent_state(_pause_button, world.is_paused)
	_refresh_authority_controls()

func _refresh_speed_label() -> void:
	if _speed_button == null or world == null:
		return
	_speed_button.text = "Tempo x%d" % int(round(world.speed_multiplier))
	# Accent-on whenever the sim runs faster than real time.
	UiThemeScript.apply_accent_state(_speed_button, world.speed_multiplier > 1.01)
	_refresh_authority_controls()

func _refresh_authority_controls() -> void:
	var client := _is_network_client()
	if _pause_button != null:
		_pause_button.disabled = client
		_pause_button.tooltip_text = "Clients folgen Pause/Zeit des Hosts." if client else ""
	if _speed_button != null:
		_speed_button.disabled = client
		_speed_button.tooltip_text = "Clients folgen dem Simulationstempo des Hosts." if client else "Simulationstempo umschalten (1x -> 4x)"
	if _player_control_button != null and client:
		_player_control_button.disabled = true
		_player_control_button.visible = false

func _refresh_network_status() -> void:
	if _network_status_label == null:
		return
	var text := "Offline"
	var color := UiThemeScript.TEXT_MUTED
	var tooltip := ""
	if multiplayer_session != null and multiplayer_session.has_method("get_status"):
		var status: Dictionary = multiplayer_session.get_status()
		var role := str(status.get("role", NetworkRoleScript.OFFLINE))
		var session_status := str(status.get("status", "offline"))
		tooltip = str(status.get("detail", ""))
		match role:
			NetworkRoleScript.HOST:
				text = "Host:%d" % int(status.get("port", 0))
				color = UiThemeScript.SUCCESS
			NetworkRoleScript.CLIENT:
				if session_status == "connected":
					text = "Client OK"
					color = UiThemeScript.SUCCESS
				elif session_status == "connection_failed" or session_status == "server_disconnected" or session_status == "join_error":
					text = "Client Fehler"
					color = UiThemeScript.DANGER
				else:
					text = "Client ..."
					color = UiThemeScript.WARNING
			_:
				text = "Offline"
				color = UiThemeScript.TEXT_MUTED
	_network_status_label.text = text
	_network_status_label.tooltip_text = tooltip
	_network_status_label.add_theme_color_override("font_color", color)

func _refresh_network_interaction_status() -> void:
	if _network_interaction_label == null:
		return
	var status := _current_interaction_status_from_session()
	if status.is_empty():
		_network_interaction_label.text = "-"
		_network_interaction_label.tooltip_text = ""
		_network_interaction_label.add_theme_color_override("font_color", UiThemeScript.TEXT_MUTED)
		return
	_network_interaction_label.text = _interaction_status_text(status)
	_network_interaction_label.tooltip_text = _interaction_status_tooltip(status)
	_network_interaction_label.add_theme_color_override("font_color", _interaction_status_color(status))

func _current_interaction_status_from_session() -> Dictionary:
	if multiplayer_session == null or not multiplayer_session.has_method("get_status"):
		return {}
	var session_status: Dictionary = multiplayer_session.get_status()
	var role := str(session_status.get("role", NetworkRoleScript.OFFLINE))
	if role == NetworkRoleScript.CLIENT:
		var client_debug := _dictionary_from_variant(session_status.get("client_debug", {}))
		return _dictionary_from_variant(client_debug.get("interaction_status", {}))
	if role == NetworkRoleScript.HOST:
		var host_debug := _dictionary_from_variant(session_status.get("host_debug", {}))
		var statuses := _dictionary_from_variant(host_debug.get("interaction_status_by_peer", {}))
		var local_status := _dictionary_from_variant(statuses.get("1", {}))
		if not local_status.is_empty():
			return local_status
		var active_effects := _dictionary_from_variant(host_debug.get("active_interaction_effect_by_peer", {}))
		var effect_status := _dictionary_from_variant(active_effects.get("1", {}))
		if not effect_status.is_empty():
			effect_status["state"] = "effect"
			return effect_status
		var active_interactions := _dictionary_from_variant(host_debug.get("active_interaction_by_peer", {}))
		var active_status := _dictionary_from_variant(active_interactions.get("1", {}))
		if not active_status.is_empty():
			active_status["state"] = "travelling"
			return active_status
	return {}

func _dictionary_from_variant(value: Variant) -> Dictionary:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}

func _interaction_status_text(status: Dictionary) -> String:
	match str(status.get("state", "")):
		"requested":
			return "Anfrage"
		"travelling":
			return "Unterwegs"
		"arrived":
			return "Am Ziel"
		"effect", "entered_building", "citizen_interaction":
			return "Aktiv"
		"rejected", "travel_failed":
			return "Abgelehnt"
		"cancelled":
			return "Abbruch"
		"ready":
			return "Bereit"
	return "-"

func _interaction_status_color(status: Dictionary) -> Color:
	match str(status.get("state", "")):
		"requested", "travelling":
			return UiThemeScript.WARNING
		"arrived", "effect", "entered_building", "citizen_interaction":
			return UiThemeScript.SUCCESS
		"rejected", "travel_failed", "cancelled":
			return UiThemeScript.DANGER
		"ready":
			return UiThemeScript.TEXT_SECONDARY
	return UiThemeScript.TEXT_MUTED

func _interaction_status_tooltip(status: Dictionary) -> String:
	var parts: Array[String] = []
	var target_label := _compact_target_label(status)
	if not target_label.is_empty():
		parts.append(target_label)
	var detail := str(status.get("detail", "")).strip_edges()
	if detail.is_empty():
		detail = str(status.get("reason", "")).strip_edges()
	if not detail.is_empty():
		parts.append(detail)
	return " | ".join(parts)

func _compact_target_label(status: Dictionary) -> String:
	var target_name := str(status.get("target_name", "")).strip_edges()
	var target_type := str(status.get("target_type", "")).strip_edges()
	if target_name.is_empty():
		return target_type.capitalize() if not target_type.is_empty() else ""
	if target_type.is_empty():
		return target_name
	return "%s: %s" % [target_type.capitalize(), target_name]

func _is_network_client() -> bool:
	return multiplayer_session != null \
		and multiplayer_session.has_method("is_client") \
		and multiplayer_session.is_client()

func _refresh_time_hud() -> void:
	if _date_label == null or _clock_label == null or world == null or world.time == null:
		return
	var weekend_tag := "  WE" if world.time.is_weekend() else ""
	_date_label.text = "%s . Tag %d%s" % [
		world.time.get_weekday_name_short_de(),
		world.time.day,
		weekend_tag
	]
	_clock_label.text = world.time.get_time_string()

func _refresh_stats() -> void:
	if world == null:
		return
	_refresh_treasury_label()
	if _population_label != null:
		_population_label.text = "%d  .  %d ohne Job" % [
			_count_registered_citizens(),
			_count_unemployed_citizens()
		]
	if _housing_jobs_label != null:
		_housing_jobs_label.text = "%d/%d  .  %d/%d" % [
			_count_used_housing_slots(),
			_count_total_housing_slots(),
			_count_filled_job_slots(),
			_count_total_job_slots()
		]
	if _satisfaction_label != null:
		var satisfaction := _compute_satisfaction_percent()
		_satisfaction_label.text = "%d%%" % satisfaction
		var sat_color := UiThemeScript.SUCCESS
		if satisfaction < 45:
			sat_color = UiThemeScript.DANGER
		elif satisfaction < 70:
			sat_color = UiThemeScript.WARNING
		_satisfaction_label.add_theme_color_override("font_color", sat_color)

func _refresh_treasury_label() -> void:
	if _treasury_label == null or world == null or world.city_account == null:
		return
	var balance := world.city_account.balance
	var delta := balance - _treasury_day_start
	var delta_text := "+%s" % _format_int_grouped(delta) if delta >= 0 else _format_int_grouped(delta)
	_treasury_label.text = "%s EUR  (%s heute)" % [_format_int_grouped(balance), delta_text]
	var color := UiThemeScript.TEXT_PRIMARY
	if balance < 0:
		color = UiThemeScript.DANGER
	elif delta > 0:
		color = UiThemeScript.SUCCESS
	elif delta < 0:
		color = UiThemeScript.WARNING
	_treasury_label.add_theme_color_override("font_color", color)

## Groups an integer with '.' thousands separators (German style).
func _format_int_grouped(value: int) -> String:
	var negative := value < 0
	var digits := str(absi(value))
	var grouped := ""
	var count := 0
	for i in range(digits.length() - 1, -1, -1):
		grouped = digits[i] + grouped
		count += 1
		if count % 3 == 0 and i > 0:
			grouped = "." + grouped
	return ("-" + grouped) if negative else grouped

## Average citizen well-being as a 0-100 percentage. Hunger is inverted
## (high hunger = bad); health/energy/fun count directly.
func _compute_satisfaction_percent() -> int:
	if world == null:
		return 0
	var total := 0.0
	var counted := 0
	for citizen in world.citizens:
		if citizen == null or not is_instance_valid(citizen) or citizen.needs == null:
			continue
		var n := citizen.needs
		var score := (
			clampf(n.health, 0.0, 100.0)
			+ clampf(n.energy, 0.0, 100.0)
			+ clampf(n.fun, 0.0, 100.0)
			+ (100.0 - clampf(n.hunger, 0.0, 100.0))
		) / 4.0
		total += score
		counted += 1
	if counted == 0:
		return 0
	return int(round(total / counted))

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
