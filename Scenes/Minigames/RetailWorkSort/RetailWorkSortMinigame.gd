extends Control
class_name RetailWorkSortMinigame

const UiThemeScript = preload("res://Simulation/UI/UiTheme.gd")

signal score_changed(score: int)
signal combo_changed(combo: int)
signal mistake_made(reason: String)
signal session_finished(result: Dictionary)

const TARGET_CASH_REGISTER := "cash_register"
const TARGET_RETURN_BIN := "return_bin"
const TARGET_HAZARD_SHELF := "hazard_shelf"
const TARGET_STORAGE := "storage"

const ITEM_SIZE := Vector2(132.0, 54.0)
const DEFAULT_SESSION_DURATION_SEC := 90.0
const BASE_CONVEYOR_SPEED := 135.0
const MAX_CONVEYOR_SPEED := 340.0
const BASE_SPAWN_INTERVAL_SEC := 1.45
const MIN_SPAWN_INTERVAL_SEC := 0.48
const MAX_ACTIVE_ITEMS := 9

const TARGET_DEFINITIONS := [
	{
		"id": TARGET_CASH_REGISTER,
		"key": "1",
		"label": "Kasse",
		"hint": "Lebensmittel",
		"color": Color8(102, 187, 106, 255),
	},
	{
		"id": TARGET_RETURN_BIN,
		"key": "2",
		"label": "Retour",
		"hint": "kaputt / abgelaufen",
		"color": Color8(239, 83, 80, 255),
	},
	{
		"id": TARGET_HAZARD_SHELF,
		"key": "3",
		"label": "Extra-Regal",
		"hint": "Reiniger / Gefahr",
		"color": Color8(255, 167, 38, 255),
	},
	{
		"id": TARGET_STORAGE,
		"key": "4",
		"label": "Lager",
		"hint": "falscher Artikel",
		"color": Color8(79, 195, 247, 255),
	},
]

const ITEM_DEFINITIONS := [
	{
		"id": "bread",
		"label": "Brot",
		"icon": "BROT",
		"target": TARGET_CASH_REGISTER,
		"min_skill": 0,
		"weight": 9,
		"points": 10,
		"color": Color8(211, 155, 76, 255),
	},
	{
		"id": "milk",
		"label": "Milch",
		"icon": "MILCH",
		"target": TARGET_CASH_REGISTER,
		"min_skill": 0,
		"weight": 8,
		"points": 10,
		"color": Color8(224, 236, 244, 255),
	},
	{
		"id": "meat",
		"label": "Fleisch",
		"icon": "FLEISCH",
		"target": TARGET_CASH_REGISTER,
		"min_skill": 0,
		"weight": 7,
		"points": 10,
		"color": Color8(197, 85, 95, 255),
	},
	{
		"id": "fruit",
		"label": "Obst",
		"icon": "OBST",
		"target": TARGET_CASH_REGISTER,
		"min_skill": 0,
		"weight": 8,
		"points": 10,
		"color": Color8(130, 200, 90, 255),
	},
	{
		"id": "cleaning_supply",
		"label": "Reiniger",
		"icon": "FLASCHE",
		"target": TARGET_HAZARD_SHELF,
		"min_skill": 0,
		"weight": 5,
		"points": 12,
		"color": Color8(106, 162, 225, 255),
	},
	{
		"id": "broken_goods",
		"label": "Kaputte Ware",
		"icon": "KAPUTT",
		"target": TARGET_RETURN_BIN,
		"min_skill": 0,
		"weight": 5,
		"points": 12,
		"color": Color8(152, 138, 127, 255),
	},
	{
		"id": "wrong_article",
		"label": "Falscher Artikel",
		"icon": "FALSCH",
		"target": TARGET_STORAGE,
		"min_skill": 0,
		"weight": 5,
		"points": 12,
		"color": Color8(165, 123, 204, 255),
	},
	{
		"id": "expired_food",
		"label": "Abgelaufen",
		"icon": "ALT",
		"target": TARGET_RETURN_BIN,
		"min_skill": 0,
		"weight": 4,
		"points": 14,
		"color": Color8(182, 130, 80, 255),
	},
	{
		"id": "milk_bottle_similar",
		"label": "Milchflasche",
		"icon": "FLASCHE",
		"target": TARGET_CASH_REGISTER,
		"min_skill": 2,
		"weight": 4,
		"points": 16,
		"color": Color8(225, 235, 245, 255),
	},
	{
		"id": "cleaner_bottle_similar",
		"label": "Reinigerflasche",
		"icon": "FLASCHE",
		"target": TARGET_HAZARD_SHELF,
		"min_skill": 2,
		"weight": 4,
		"points": 16,
		"color": Color8(98, 156, 220, 255),
	},
	{
		"id": "discount_food",
		"label": "Rabattartikel",
		"icon": "RABATT",
		"target": TARGET_CASH_REGISTER,
		"min_skill": 3,
		"weight": 3,
		"points": 18,
		"color": Color8(248, 205, 88, 255),
	},
]

@export var auto_start: bool = true
@export var session_duration_sec: float = DEFAULT_SESSION_DURATION_SEC
@export var player_skill_level: int = 0
@export var rng_seed: int = 0

var workplace_label: String = "Laden"
var workplace_type: String = "Shop"
var running: bool = false
var elapsed_sec: float = 0.0
var score: int = 0
var combo: int = 0
var mistakes: int = 0
var sorted_items: int = 0
var missed_items: int = 0

var _rng := RandomNumberGenerator.new()
var _spawn_timer_sec: float = 0.0
var _selected_item: Button = null
var _active_items: Array[Button] = []
var _drop_zone_buttons: Dictionary = {}

var _score_label: Label = null
var _combo_label: Label = null
var _timer_label: Label = null
var _speed_label: Label = null
var _hint_label: Label = null
var _lane_panel: PanelContainer = null
var _item_layer: Control = null


func _ready() -> void:
	theme = UiThemeScript.get_or_build()
	custom_minimum_size = Vector2(960, 540)
	if rng_seed == 0:
		_rng.randomize()
	else:
		_rng.seed = rng_seed
	_build_ui()
	if auto_start:
		start_session()


func _process(delta: float) -> void:
	if not running:
		return
	elapsed_sec += delta
	if elapsed_sec >= session_duration_sec:
		finish_session()
		return
	_spawn_timer_sec -= delta
	if _spawn_timer_sec <= 0.0:
		_try_spawn_item()
		_spawn_timer_sec = _current_spawn_interval()
	_move_active_items(delta)
	_update_status_labels()


func _unhandled_input(event: InputEvent) -> void:
	if not running:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				_sort_selected_to(TARGET_CASH_REGISTER)
				get_viewport().set_input_as_handled()
			KEY_2:
				_sort_selected_to(TARGET_RETURN_BIN)
				get_viewport().set_input_as_handled()
			KEY_3:
				_sort_selected_to(TARGET_HAZARD_SHELF)
				get_viewport().set_input_as_handled()
			KEY_4:
				_sort_selected_to(TARGET_STORAGE)
				get_viewport().set_input_as_handled()


func configure_for_workplace(workplace, skill_level: int = 0) -> bool:
	player_skill_level = maxi(skill_level, 0)
	if workplace == null:
		_apply_workplace_labels("Shop", "Laden")
		return true
	var type_name := _resolve_workplace_type_name(workplace)
	if not supports_workplace_type(type_name):
		return false
	var label := str(workplace.name)
	if workplace.has_method("get_display_name"):
		label = str(workplace.call("get_display_name"))
	_apply_workplace_labels(type_name, label)
	return true


func supports_workplace_type(type_name: String) -> bool:
	var normalized := type_name.strip_edges().to_lower()
	return normalized == "shop" or normalized == "supermarket"


func start_session() -> void:
	running = true
	elapsed_sec = 0.0
	score = 0
	combo = 0
	mistakes = 0
	sorted_items = 0
	missed_items = 0
	_spawn_timer_sec = 0.15
	_clear_items()
	_select_item(null)
	_update_status_labels()
	_set_hint("Ware anklicken, dann Ziel 1-4 oder Zielbutton waehlen.")
	score_changed.emit(score)
	combo_changed.emit(combo)


func finish_session() -> void:
	if not running:
		return
	running = false
	_select_item(null)
	_update_status_labels()
	_set_hint("Schicht-Minispiel beendet.")
	session_finished.emit(get_result())


func get_result() -> Dictionary:
	return {
		"score": score,
		"combo": combo,
		"mistakes": mistakes,
		"sorted_items": sorted_items,
		"missed_items": missed_items,
		"elapsed_sec": elapsed_sec,
		"workplace_type": workplace_type,
		"workplace_label": workplace_label,
	}


func get_target_for_item(item_id: String) -> String:
	var definition := _get_item_definition(item_id)
	return str(definition.get("target", "")) if not definition.is_empty() else ""


func get_item_ids_for_skill(skill_level: int = -1) -> PackedStringArray:
	var resolved_skill := player_skill_level if skill_level < 0 else maxi(skill_level, 0)
	var ids := PackedStringArray()
	for definition in ITEM_DEFINITIONS:
		if int(definition.get("min_skill", 0)) <= resolved_skill:
			ids.append(str(definition.get("id", "")))
	return ids


func debug_sort_item(item_id: String, target_id: String) -> Dictionary:
	var definition := _get_item_definition(item_id)
	if definition.is_empty():
		return {"correct": false, "reason": "unknown_item", "score": score}
	var correct := str(definition.get("target", "")) == target_id
	if correct:
		_score_correct_sort(definition)
	else:
		_register_mistake("wrong_target")
	return {"correct": correct, "target": str(definition.get("target", "")), "score": score, "combo": combo}


func debug_get_current_speed() -> float:
	return _current_conveyor_speed()


func debug_set_elapsed(seconds: float) -> void:
	elapsed_sec = clampf(seconds, 0.0, session_duration_sec)
	_update_status_labels()


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color8(11, 15, 22, 255)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_bottom", 18)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", UiThemeScript.SEPARATION_NORMAL)
	margin.add_child(root)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", UiThemeScript.SEPARATION_LOOSE)
	root.add_child(header)

	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_box)

	var title := Label.new()
	title.text = "Verkaeufer: Waren sortieren"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", UiThemeScript.TEXT_PRIMARY)
	title_box.add_child(title)

	_hint_label = Label.new()
	_hint_label.text = ""
	_hint_label.add_theme_color_override("font_color", UiThemeScript.TEXT_SECONDARY)
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_box.add_child(_hint_label)

	_score_label = _make_status_label()
	_combo_label = _make_status_label()
	_timer_label = _make_status_label()
	_speed_label = _make_status_label()
	header.add_child(_score_label)
	header.add_child(_combo_label)
	header.add_child(_timer_label)
	header.add_child(_speed_label)

	_lane_panel = PanelContainer.new()
	_lane_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lane_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_lane_panel.custom_minimum_size = Vector2(0, 260)
	_lane_panel.add_theme_stylebox_override("panel", _make_panel_box(Color8(18, 24, 34, 255), UiThemeScript.BORDER_STRONG))
	root.add_child(_lane_panel)

	_item_layer = Control.new()
	_item_layer.clip_contents = true
	_item_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_item_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lane_panel.add_child(_item_layer)

	var target_row := HBoxContainer.new()
	target_row.add_theme_constant_override("separation", UiThemeScript.SEPARATION_NORMAL)
	target_row.custom_minimum_size = Vector2(0, 110)
	root.add_child(target_row)

	for definition in TARGET_DEFINITIONS:
		var target_button := _make_target_button(definition)
		target_row.add_child(target_button)
		_drop_zone_buttons[str(definition.get("id", ""))] = target_button


func _make_status_label() -> Label:
	var label := Label.new()
	label.custom_minimum_size = Vector2(116, 44)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", UiThemeScript.TEXT_PRIMARY)
	UiThemeScript.apply_pill_label(label, UiThemeScript.TEXT_PRIMARY, Color8(35, 41, 56, 255))
	return label


func _make_target_button(definition: Dictionary) -> Button:
	var target_id := str(definition.get("id", ""))
	var button := Button.new()
	button.custom_minimum_size = Vector2(165, 92)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	button.text = "%s  [%s]\n%s" % [
		str(definition.get("label", "")),
		str(definition.get("key", "")),
		str(definition.get("hint", "")),
	]
	button.pressed.connect(_on_target_pressed.bind(target_id))
	var color: Color = definition.get("color", UiThemeScript.ACCENT)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", _make_button_box(color.darkened(0.68), color.darkened(0.1), false))
	button.add_theme_stylebox_override("hover", _make_button_box(color.darkened(0.55), color, true))
	button.add_theme_stylebox_override("pressed", _make_button_box(color.darkened(0.75), color.lightened(0.1), true))
	return button


func _try_spawn_item() -> void:
	if _item_layer == null or _item_layer.size.x <= ITEM_SIZE.x:
		return
	_compact_active_items()
	if _active_items.size() >= MAX_ACTIVE_ITEMS:
		return
	var definition := _pick_item_definition()
	if definition.is_empty():
		return
	var item := Button.new()
	item.custom_minimum_size = ITEM_SIZE
	item.size = ITEM_SIZE
	item.focus_mode = Control.FOCUS_NONE
	item.text = "%s\n%s" % [str(definition.get("icon", "")), str(definition.get("label", ""))]
	item.position = Vector2(-ITEM_SIZE.x, _pick_item_y())
	item.set_meta("sort_item", definition.duplicate(true))
	item.pressed.connect(_on_item_pressed.bind(item))
	_apply_item_style(item, definition, false)
	_item_layer.add_child(item)
	_active_items.append(item)


func _move_active_items(delta: float) -> void:
	var speed := _current_conveyor_speed()
	var lane_width := _item_layer.size.x if _item_layer != null else 0.0
	var missed: Array[Button] = []
	for item in _active_items:
		if item == null or not is_instance_valid(item):
			continue
		item.position.x += speed * delta
		if item.position.x > lane_width + ITEM_SIZE.x:
			missed.append(item)
	for item in missed:
		_miss_item(item)
	_compact_active_items()


func _on_item_pressed(item: Button) -> void:
	if item == null or not is_instance_valid(item):
		return
	_select_item(item)


func _on_target_pressed(target_id: String) -> void:
	_sort_selected_to(target_id)


func _sort_selected_to(target_id: String) -> void:
	if _selected_item == null or not is_instance_valid(_selected_item):
		_set_hint("Erst eine Ware auf der Laufbahn auswaehlen.")
		return
	var definition: Dictionary = _selected_item.get_meta("sort_item", {})
	var correct_target := str(definition.get("target", ""))
	if target_id == correct_target:
		_score_correct_sort(definition)
		_set_hint("Richtig: %s -> %s." % [str(definition.get("label", "")), _target_label(target_id)])
	else:
		_register_mistake("wrong_target")
		_set_hint("Falsch: %s gehoert zu %s." % [str(definition.get("label", "")), _target_label(correct_target)])
	_remove_item(_selected_item)
	_select_item(null)
	_update_status_labels()


func _score_correct_sort(definition: Dictionary) -> void:
	sorted_items += 1
	combo += 1
	var combo_bonus := mini(maxi(combo - 1, 0), 10)
	score += int(definition.get("points", 10)) + combo_bonus
	score_changed.emit(score)
	combo_changed.emit(combo)


func _register_mistake(reason: String) -> void:
	mistakes += 1
	combo = 0
	score = maxi(score - 5, 0)
	score_changed.emit(score)
	combo_changed.emit(combo)
	mistake_made.emit(reason)


func _miss_item(item: Button) -> void:
	if item == null or not is_instance_valid(item):
		return
	missed_items += 1
	_register_mistake("missed_item")
	var definition: Dictionary = item.get_meta("sort_item", {})
	_set_hint("Verpasst: %s." % str(definition.get("label", "Ware")))
	_remove_item(item)
	if _selected_item == item:
		_select_item(null)


func _select_item(item: Button) -> void:
	if _selected_item != null and is_instance_valid(_selected_item):
		var old_definition: Dictionary = _selected_item.get_meta("sort_item", {})
		_apply_item_style(_selected_item, old_definition, false)
	_selected_item = item
	if _selected_item != null and is_instance_valid(_selected_item):
		var definition: Dictionary = _selected_item.get_meta("sort_item", {})
		_apply_item_style(_selected_item, definition, true)
		_set_hint("%s gewaehlt. Ziel per 1-4 oder Button auswaehlen." % str(definition.get("label", "Ware")))


func _remove_item(item: Button) -> void:
	if item == null:
		return
	_active_items.erase(item)
	if item.get_parent() != null:
		item.queue_free()


func _clear_items() -> void:
	for item in _active_items:
		if item != null and is_instance_valid(item):
			item.queue_free()
	_active_items.clear()


func _compact_active_items() -> void:
	for i in range(_active_items.size() - 1, -1, -1):
		var item := _active_items[i]
		if item == null or not is_instance_valid(item):
			_active_items.remove_at(i)


func _apply_item_style(item: Button, definition: Dictionary, selected: bool) -> void:
	if item == null:
		return
	var color: Color = definition.get("color", UiThemeScript.ACCENT)
	item.add_theme_color_override("font_color", Color8(10, 14, 22, 255))
	item.add_theme_color_override("font_hover_color", Color8(10, 14, 22, 255))
	item.add_theme_color_override("font_pressed_color", Color8(10, 14, 22, 255))
	item.add_theme_stylebox_override("normal", _make_button_box(color, UiThemeScript.ACCENT if selected else color.darkened(0.2), selected))
	item.add_theme_stylebox_override("hover", _make_button_box(color.lightened(0.08), UiThemeScript.ACCENT, true))
	item.add_theme_stylebox_override("pressed", _make_button_box(color.darkened(0.08), UiThemeScript.ACCENT_DIM, true))


func _make_panel_box(bg: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.border_width_left = 1
	box.border_width_top = 1
	box.border_width_right = 1
	box.border_width_bottom = 1
	box.corner_radius_top_left = 8
	box.corner_radius_top_right = 8
	box.corner_radius_bottom_left = 8
	box.corner_radius_bottom_right = 8
	box.content_margin_left = 12
	box.content_margin_top = 12
	box.content_margin_right = 12
	box.content_margin_bottom = 12
	return box


func _make_button_box(bg: Color, border: Color, strong_border: bool) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	var border_width := 2 if strong_border else 1
	box.border_width_left = border_width
	box.border_width_top = border_width
	box.border_width_right = border_width
	box.border_width_bottom = border_width
	box.corner_radius_top_left = 6
	box.corner_radius_top_right = 6
	box.corner_radius_bottom_left = 6
	box.corner_radius_bottom_right = 6
	box.content_margin_left = 10
	box.content_margin_top = 6
	box.content_margin_right = 10
	box.content_margin_bottom = 6
	return box


func _pick_item_y() -> float:
	var lane_height := _item_layer.size.y if _item_layer != null else 260.0
	var min_y := 18.0
	var max_y := maxf(min_y, lane_height - ITEM_SIZE.y - 18.0)
	return _rng.randf_range(min_y, max_y)


func _pick_item_definition() -> Dictionary:
	var candidates: Array[Dictionary] = []
	var total_weight := 0
	for definition in ITEM_DEFINITIONS:
		if int(definition.get("min_skill", 0)) > player_skill_level:
			continue
		var weight := maxi(int(definition.get("weight", 1)), 1)
		candidates.append(definition)
		total_weight += weight
	if candidates.is_empty():
		return {}
	var roll := _rng.randi_range(1, total_weight)
	var cursor := 0
	for definition in candidates:
		cursor += maxi(int(definition.get("weight", 1)), 1)
		if roll <= cursor:
			return definition
	return candidates.back()


func _get_item_definition(item_id: String) -> Dictionary:
	for definition in ITEM_DEFINITIONS:
		if str(definition.get("id", "")) == item_id:
			return definition
	return {}


func _current_conveyor_speed() -> float:
	var progress := _session_progress()
	var skill_pressure := minf(float(player_skill_level) * 10.0, 45.0)
	return minf(BASE_CONVEYOR_SPEED + 165.0 * progress + skill_pressure, MAX_CONVEYOR_SPEED)


func _current_spawn_interval() -> float:
	var progress := _session_progress()
	var skill_pressure := minf(float(player_skill_level) * 0.06, 0.22)
	return maxf(lerpf(BASE_SPAWN_INTERVAL_SEC, MIN_SPAWN_INTERVAL_SEC, progress) - skill_pressure, MIN_SPAWN_INTERVAL_SEC)


func _session_progress() -> float:
	if session_duration_sec <= 0.0:
		return 1.0
	return clampf(elapsed_sec / session_duration_sec, 0.0, 1.0)


func _update_status_labels() -> void:
	if _score_label == null:
		return
	var remaining := maxi(int(ceil(session_duration_sec - elapsed_sec)), 0)
	_score_label.text = "Score\n%d" % score
	_combo_label.text = "Combo\nx%d" % combo
	_timer_label.text = "Zeit\n%02d:%02d" % [remaining / 60, remaining % 60]
	_speed_label.text = "Tempo\n%d%%" % int(round((_current_conveyor_speed() / BASE_CONVEYOR_SPEED) * 100.0))


func _set_hint(text: String) -> void:
	if _hint_label != null:
		_hint_label.text = text


func _target_label(target_id: String) -> String:
	for definition in TARGET_DEFINITIONS:
		if str(definition.get("id", "")) == target_id:
			return str(definition.get("label", target_id))
	return target_id


func _resolve_workplace_type_name(workplace) -> String:
	if workplace == null:
		return "Shop"
	if workplace.has_method("get_building_type_name"):
		return str(workplace.call("get_building_type_name"))
	if workplace is Supermarket:
		return "Supermarket"
	if workplace is Shop:
		return "Shop"
	return str(workplace.get_class())


func _apply_workplace_labels(type_name: String, label: String) -> void:
	workplace_type = type_name
	workplace_label = label
	if _hint_label != null:
		_set_hint("%s: Ware sortieren." % workplace_label)
