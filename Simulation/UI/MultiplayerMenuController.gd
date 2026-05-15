extends RefCounted
class_name MultiplayerMenuController

## Pre-game multiplayer modal.
##
## Shown once at startup for interactive launches that did not pass an explicit
## --mp-host / --mp-client flag. The role (host / client / offline) must be
## decided here before the runtime spawns citizens, so this controller drives
## MultiplayerSession directly and only signals the owner to start the runtime
## once a session mode is active. Headless / CLI launches never build this.

const UiThemeScript = preload("res://Simulation/UI/UiTheme.gd")
const LaunchOptionsScript = preload("res://Simulation/Multiplayer/shared/MultiplayerLaunchOptions.gd")

var owner_node: Node = null
var session: MultiplayerSession = null

var _on_started: Callable = Callable()
var _theme: Theme = null
var _canvas: CanvasLayer = null
var _host_port_edit: LineEdit = null
var _host_max_edit: LineEdit = null
var _join_address_edit: LineEdit = null
var _join_port_edit: LineEdit = null
var _status_label: Label = null
var _buttons: Array[Button] = []
var _started: bool = false

func setup(owner_ref: Node, session_ref: MultiplayerSession, on_started: Callable) -> void:
	owner_node = owner_ref
	session = session_ref
	_on_started = on_started
	_build_menu()
	if session != null and session.has_signal("status_changed"):
		var status_cb := Callable(self, "_on_session_status_changed")
		if not session.status_changed.is_connected(status_cb):
			session.status_changed.connect(status_cb)

func close() -> void:
	if session != null and session.has_signal("status_changed"):
		var status_cb := Callable(self, "_on_session_status_changed")
		if session.status_changed.is_connected(status_cb):
			session.status_changed.disconnect(status_cb)
	if _canvas != null and is_instance_valid(_canvas):
		_canvas.queue_free()
	_canvas = null

func _build_menu() -> void:
	if owner_node == null:
		return

	_canvas = CanvasLayer.new()
	_canvas.layer = 128
	owner_node.add_child(_canvas)

	# CanvasLayer is not a Control and cannot hold a Theme; top-level Controls
	# under it must set .theme explicitly. Nested children inherit normally.
	_theme = UiThemeScript.get_or_build()

	# Dimmed backdrop: the 3D city stays visible behind it. STOP filter so the
	# scene below never receives clicks while the modal is up.
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.theme = _theme
	_canvas.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 0)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", UiThemeScript.SEPARATION_NORMAL)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Multiplayer"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", UiThemeScript.FONT_SIZE_HEADING)
	title.add_theme_color_override("font_color", UiThemeScript.ACCENT)
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Modus wählen — Host besitzt Welt, Zeit, Wirtschaft und Citizens."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_color_override("font_color", UiThemeScript.TEXT_MUTED)
	subtitle.add_theme_font_size_override("font_size", UiThemeScript.FONT_SIZE_SMALL)
	vbox.add_child(subtitle)

	vbox.add_child(_make_separator())

	# --- Singleplayer / offline ------------------------------------------
	var single_btn := Button.new()
	single_btn.text = "Singleplayer (Offline)"
	single_btn.custom_minimum_size = Vector2(0, 38)
	single_btn.pressed.connect(Callable(self, "_on_singleplayer_pressed"))
	vbox.add_child(single_btn)
	_buttons.append(single_btn)

	vbox.add_child(_make_separator())

	# --- Host ------------------------------------------------------------
	vbox.add_child(_make_section_label("Hosten"))
	var host_row := HBoxContainer.new()
	host_row.add_theme_constant_override("separation", UiThemeScript.SEPARATION_DENSE)
	vbox.add_child(host_row)
	host_row.add_child(_make_field_label("Port"))
	_host_port_edit = _make_line_edit(str(LaunchOptionsScript.DEFAULT_PORT), 90)
	host_row.add_child(_host_port_edit)
	host_row.add_child(_make_field_label("Max. Spieler"))
	_host_max_edit = _make_line_edit(str(LaunchOptionsScript.DEFAULT_MAX_CLIENTS), 60)
	host_row.add_child(_host_max_edit)

	var host_btn := Button.new()
	host_btn.text = "Spiel hosten"
	host_btn.custom_minimum_size = Vector2(0, 38)
	host_btn.pressed.connect(Callable(self, "_on_host_pressed"))
	vbox.add_child(host_btn)
	_buttons.append(host_btn)
	UiThemeScript.apply_accent_state(host_btn, true)

	vbox.add_child(_make_separator())

	# --- Join ------------------------------------------------------------
	vbox.add_child(_make_section_label("Beitreten"))
	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", UiThemeScript.SEPARATION_DENSE)
	vbox.add_child(join_row)
	join_row.add_child(_make_field_label("Adresse"))
	_join_address_edit = _make_line_edit(LaunchOptionsScript.DEFAULT_ADDRESS, 150)
	join_row.add_child(_join_address_edit)
	join_row.add_child(_make_field_label("Port"))
	_join_port_edit = _make_line_edit(str(LaunchOptionsScript.DEFAULT_PORT), 90)
	join_row.add_child(_join_port_edit)

	var join_btn := Button.new()
	join_btn.text = "Spiel beitreten"
	join_btn.custom_minimum_size = Vector2(0, 38)
	join_btn.pressed.connect(Callable(self, "_on_join_pressed"))
	vbox.add_child(join_btn)
	_buttons.append(join_btn)
	UiThemeScript.apply_accent_state(join_btn, true)

	vbox.add_child(_make_separator())

	_status_label = Label.new()
	_status_label.text = "Bereit."
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_color_override("font_color", UiThemeScript.TEXT_SECONDARY)
	_status_label.add_theme_font_size_override("font_size", UiThemeScript.FONT_SIZE_SMALL)
	_status_label.custom_minimum_size = Vector2(0, 32)
	vbox.add_child(_status_label)

func _on_singleplayer_pressed() -> void:
	if _started or session == null:
		return
	session.start_offline()
	_finish()

func _on_host_pressed() -> void:
	if _started or session == null:
		return
	var host_port := _parse_port(_host_port_edit.text if _host_port_edit != null else "")
	var host_max := _parse_max_clients(_host_max_edit.text if _host_max_edit != null else "")
	_set_status("Starte Host auf Port %d …" % host_port)
	var err: int = session.host_game(host_port, host_max)
	if err != OK:
		_set_status(_status_detail("Host fehlgeschlagen."))
		return
	_finish()

func _on_join_pressed() -> void:
	if _started or session == null:
		return
	var join_address := _parse_address(_join_address_edit.text if _join_address_edit != null else "")
	var join_port := _parse_port(_join_port_edit.text if _join_port_edit != null else "")
	_set_status("Verbinde zu %s:%d …" % [join_address, join_port])
	var err: int = session.join_game(join_address, join_port)
	if err != OK:
		_set_status(_status_detail("Verbindung fehlgeschlagen."))
		return
	_finish()

func _finish() -> void:
	if _started:
		return
	_started = true
	for button in _buttons:
		if button != null:
			button.disabled = true
	if _on_started.is_valid():
		_on_started.call()

func _on_session_status_changed(_status: String, detail: String) -> void:
	if detail.is_empty():
		return
	_set_status(detail)

func _status_detail(fallback: String) -> String:
	if session != null:
		var status: Dictionary = session.get_status()
		var detail := str(status.get("detail", ""))
		if not detail.is_empty():
			return detail
	return fallback

func _set_status(text: String) -> void:
	if _status_label != null:
		_status_label.text = text

# --- Input parsing — mirrors MultiplayerLaunchOptions clamping. -----------
func _parse_port(raw: String) -> int:
	var trimmed := raw.strip_edges()
	if not trimmed.is_valid_int():
		return LaunchOptionsScript.DEFAULT_PORT
	return clampi(int(trimmed), 1024, 65535)

func _parse_max_clients(raw: String) -> int:
	var trimmed := raw.strip_edges()
	if not trimmed.is_valid_int():
		return LaunchOptionsScript.DEFAULT_MAX_CLIENTS
	return clampi(int(trimmed), 1, 32)

func _parse_address(raw: String) -> String:
	var trimmed := raw.strip_edges()
	if trimmed.is_empty():
		return LaunchOptionsScript.DEFAULT_ADDRESS
	return trimmed

# --- Small builders ------------------------------------------------------
func _make_line_edit(default_text: String, min_width: int) -> LineEdit:
	var edit := LineEdit.new()
	edit.text = default_text
	edit.custom_minimum_size = Vector2(min_width, 32)
	return edit

func _make_field_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", UiThemeScript.TEXT_SECONDARY)
	label.add_theme_font_size_override("font_size", UiThemeScript.FONT_SIZE_BODY)
	return label

func _make_section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", UiThemeScript.TEXT_PRIMARY)
	label.add_theme_font_size_override("font_size", UiThemeScript.FONT_SIZE_LABEL)
	return label

func _make_separator() -> HSeparator:
	return HSeparator.new()
