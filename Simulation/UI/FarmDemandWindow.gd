extends CanvasLayer
class_name FarmDemandWindow

const UiThemeScript = preload("res://Simulation/UI/UiTheme.gd")

signal delivery_requested(request_id: String)
signal closed
signal ui_interacted

var _farm: Farm = null
var _actor: Citizen = null
var _world: World = null
var _panel: PanelContainer = null
var _rows: VBoxContainer = null
var _title: Label = null
var _summary: Label = null
var _refresh_left: float = 0.0


func _ready() -> void:
	layer = 70
	_build_ui()
	hide_window()


func show_for(farm: Farm, actor: Citizen, world: World) -> void:
	_farm = farm
	_actor = actor
	_world = world
	visible = true
	_refresh_left = 0.0
	_refresh()


func hide_window() -> void:
	visible = false
	_farm = null
	_actor = null
	_world = null


func is_open_for(farm: Farm, actor: Citizen) -> bool:
	return visible and _farm == farm and _actor == actor


func _process(delta: float) -> void:
	if not visible:
		return
	if _farm == null or not is_instance_valid(_farm) \
			or _actor == null or not is_instance_valid(_actor):
		hide_window()
		return
	if _actor._get_player_current_building() != _farm:
		hide_window()
		return
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = 0.5
		_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.0, 0.0, 0.0, 0.42)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.gui_input.connect(_on_ui_input)
	add_child(backdrop)

	_panel = PanelContainer.new()
	_panel.anchor_left = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -500.0
	_panel.offset_top = -205.0
	_panel.offset_right = 500.0
	_panel.offset_bottom = 205.0
	_panel.theme = UiThemeScript.get_or_build()
	_panel.gui_input.connect(_on_ui_input)
	add_child(_panel)

	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(960.0, 360.0)
	root.add_theme_constant_override("separation", UiThemeScript.SEPARATION_NORMAL)
	_panel.add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)
	_title = Label.new()
	_title.text = "Farmnachfrage"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.add_theme_font_size_override("font_size", 20)
	header.add_child(_title)
	var close_button := Button.new()
	close_button.text = "Schließen"
	close_button.pressed.connect(_close)
	header.add_child(close_button)

	_summary = Label.new()
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.add_theme_color_override("font_color", UiThemeScript.TEXT_SECONDARY)
	root.add_child(_summary)

	var columns := Label.new()
	columns.text = "Geschäft / Ware        Bestand        Bedarf        Lieferbar        Entfernung        Status"
	columns.add_theme_color_override("font_color", UiThemeScript.TEXT_MUTED)
	root.add_child(columns)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", UiThemeScript.SEPARATION_DENSE)
	scroll.add_child(_rows)


func _refresh() -> void:
	if _rows == null or _farm == null or _world == null:
		return
	_clear_rows()
	var demand := _farm.get_delivery_demand_snapshot(_world, _actor)
	var role_label := "Besitzer" if _farm.is_owned_by(_actor) else "Arbeiter"
	_title.text = "%s – Nachfrage" % _farm.get_display_name()
	_summary.text = "%s | Farmbestand: %d | Offene Bestellungen: %d" % [
		role_label,
		_farm.get_product_inventory_amount(),
		demand.size(),
	]
	if demand.is_empty():
		var empty := Label.new()
		empty.text = "Keine offene kompatible Nachfrage."
		empty.add_theme_color_override("font_color", UiThemeScript.TEXT_MUTED)
		_rows.add_child(empty)
		return
	for entry_var in demand:
		_add_demand_row(entry_var as Dictionary)


func _add_demand_row(entry: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(920.0, 44.0)
	row.add_theme_constant_override("separation", UiThemeScript.SEPARATION_DENSE)
	_rows.add_child(row)

	var name_label := _make_cell("%s\n%s" % [
		str(entry.get("target_name", "Geschäft")),
		str(entry.get("target_item_label", "Ware")),
	], 190.0)
	row.add_child(name_label)
	row.add_child(_make_cell("%d / %d" % [
		int(entry.get("stock", 0)),
		int(entry.get("restock_target", 0)),
	], 90.0))
	row.add_child(_make_cell("%d" % int(entry.get("need", 0)), 70.0))
	row.add_child(_make_cell("%d" % int(entry.get("deliverable", 0)), 80.0))
	row.add_child(_make_cell("%.0f m" % float(entry.get("distance_m", 0.0)), 85.0))
	var status_text := _urgency_display_label(str(entry.get("urgency", "normal")))
	if not bool(entry.get("route_available", false)):
		status_text = "keine Route"
	row.add_child(_make_cell(status_text, 75.0))

	var button := Button.new()
	button.text = "Selbst liefern"
	button.disabled = int(entry.get("deliverable", 0)) <= 0
	button.tooltip_text = "Kein lieferbarer Bestand oder Kunde kann nicht zahlen." if button.disabled else ""
	button.pressed.connect(_request_delivery.bind(str(entry.get("request_id", ""))))
	row.add_child(button)

	if _farm.is_owned_by(_actor):
		var finance := Label.new()
		finance.text = "Umsatz %d EUR" % int(entry.get("expected_revenue", 0))
		finance.add_theme_color_override("font_color", UiThemeScript.TEXT_SECONDARY)
		finance.custom_minimum_size = Vector2(105.0, 0.0)
		row.add_child(finance)


func _make_cell(text: String, width: float) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(width, 0.0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _urgency_display_label(urgency_key: String) -> String:
	match urgency_key:
		"critical":
			return "kritisch"
		"high":
			return "hoch"
		_:
			return "normal"


func _request_delivery(request_id: String) -> void:
	if request_id.is_empty():
		return
	ui_interacted.emit()
	delivery_requested.emit(request_id)


func _close() -> void:
	ui_interacted.emit()
	hide_window()
	closed.emit()


func _clear_rows() -> void:
	for child in _rows.get_children():
		child.queue_free()


func _on_ui_input(_event: InputEvent) -> void:
	ui_interacted.emit()
