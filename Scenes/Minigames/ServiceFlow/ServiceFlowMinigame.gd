extends Control
class_name ServiceFlowMinigame

const UiThemeScript = preload("res://Simulation/UI/UiTheme.gd")

signal score_changed(score: int)
signal combo_changed(combo: int)
signal satisfaction_changed(customer_satisfaction: float)
signal mistake_made(reason: String)
signal task_resolved(table_number: int, action_id: String, correct: bool)
signal session_finished(result: Dictionary)

const ACTION_TAKE_ORDER := "take_order"
const ACTION_DELIVER_FOOD := "deliver_food"
const ACTION_REFILL_DRINK := "refill_drink"
const ACTION_COLLECT_PAYMENT := "collect_payment"
const ACTION_CLEAN_TABLE := "clean_table"

const STATE_EMPTY := "empty"
const STATE_NEW_ARRIVAL := "new_arrival"
const STATE_WAITING_FOOD := "waiting_food"
const STATE_LOW_DRINK := "low_drink"
const STATE_WANTS_PAY := "wants_pay"
const STATE_DIRTY := "dirty"
const STATE_WRONG_FOOD := "wrong_food"

const TABLE_COUNT := 4
const DEFAULT_SESSION_DURATION_SEC := 82.0
const BASE_EVENT_INTERVAL_SEC := 8.0
const MIN_EVENT_INTERVAL_SEC := 2.6
const WRONG_ACTION_WAIT_PENALTY_SEC := 5.0
const MAX_PRIORITY_FOR_UI := 110.0
const QUALITY_BONUS_THRESHOLD := 0.62

const ACTION_DEFINITIONS := [
	{
		"id": ACTION_TAKE_ORDER,
		"key": "Q",
		"label": "Bestellung",
		"hint": "aufnehmen",
		"color": Color8(102, 187, 106, 255),
	},
	{
		"id": ACTION_DELIVER_FOOD,
		"key": "W",
		"label": "Essen",
		"hint": "bringen",
		"color": Color8(255, 202, 40, 255),
	},
	{
		"id": ACTION_REFILL_DRINK,
		"key": "E",
		"label": "Getraenk",
		"hint": "nachfuellen",
		"color": Color8(79, 195, 247, 255),
	},
	{
		"id": ACTION_COLLECT_PAYMENT,
		"key": "R",
		"label": "Kasse",
		"hint": "kassieren",
		"color": Color8(171, 126, 235, 255),
	},
	{
		"id": ACTION_CLEAN_TABLE,
		"key": "T",
		"label": "Tisch",
		"hint": "reinigen",
		"color": Color8(255, 167, 38, 255),
	},
]

const TASK_DEFINITIONS := [
	{
		"state": STATE_NEW_ARRIVAL,
		"label": "Neu angekommen",
		"required_action": ACTION_TAKE_ORDER,
		"base_priority": 26.0,
		"patience_sec": 44.0,
		"points": 12,
		"color": Color8(102, 187, 106, 255),
	},
	{
		"state": STATE_WAITING_FOOD,
		"label": "Wartet aufs Essen",
		"required_action": ACTION_DELIVER_FOOD,
		"base_priority": 30.0,
		"patience_sec": 52.0,
		"points": 13,
		"color": Color8(255, 202, 40, 255),
	},
	{
		"state": STATE_LOW_DRINK,
		"label": "Getraenk leer",
		"required_action": ACTION_REFILL_DRINK,
		"base_priority": 23.0,
		"patience_sec": 46.0,
		"points": 11,
		"color": Color8(79, 195, 247, 255),
	},
	{
		"state": STATE_WANTS_PAY,
		"label": "Will zahlen",
		"required_action": ACTION_COLLECT_PAYMENT,
		"base_priority": 37.0,
		"patience_sec": 38.0,
		"points": 14,
		"color": Color8(171, 126, 235, 255),
	},
	{
		"state": STATE_DIRTY,
		"label": "Muss gereinigt werden",
		"required_action": ACTION_CLEAN_TABLE,
		"base_priority": 18.0,
		"patience_sec": 58.0,
		"points": 10,
		"color": Color8(255, 167, 38, 255),
	},
	{
		"state": STATE_WRONG_FOOD,
		"label": "Falsches Essen",
		"required_action": ACTION_DELIVER_FOOD,
		"base_priority": 46.0,
		"patience_sec": 36.0,
		"points": 17,
		"color": Color8(239, 83, 80, 255),
	},
]

const INITIAL_TABLES := [
	{"state": STATE_WAITING_FOOD, "wait_sec": 38.0},
	{"state": STATE_WANTS_PAY, "wait_sec": 13.0},
	{"state": STATE_WRONG_FOOD, "wait_sec": 8.0},
	{"state": STATE_NEW_ARRIVAL, "wait_sec": 0.0},
]

@export var auto_start: bool = true
@export var session_duration_sec: float = DEFAULT_SESSION_DURATION_SEC
@export var player_skill_level: int = 0
@export var rng_seed: int = 0

var workplace_label: String = "Restaurant"
var workplace_type: String = "Restaurant"
var running: bool = false
var elapsed_sec: float = 0.0
var score: int = 0
var combo: int = 0
var best_combo: int = 0
var mistakes: int = 0
var completed_tasks: int = 0
var failed_tables: int = 0
var customer_satisfaction: float = 100.0

var _rng := RandomNumberGenerator.new()
var _tables: Array[Dictionary] = []
var _selected_table_index: int = 0
var _event_timer_sec: float = 0.0

var _score_label: Label = null
var _combo_label: Label = null
var _timer_label: Label = null
var _quality_label: Label = null
var _hint_label: Label = null
var _queue_label: Label = null
var _selected_label: Label = null
var _table_buttons: Array[Button] = []
var _action_buttons: Dictionary = {}


func _ready() -> void:
	theme = UiThemeScript.get_or_build()
	custom_minimum_size = Vector2(960, 540)
	if rng_seed == 0:
		_rng.randomize()
	else:
		_rng.seed = rng_seed
	_build_ui()
	_reset_tables()
	if auto_start:
		start_session()
	else:
		_update_all_ui()


func _process(delta: float) -> void:
	if not running:
		return
	elapsed_sec += delta
	if elapsed_sec >= session_duration_sec:
		finish_session()
		return
	_tick_tables(delta)
	_event_timer_sec -= delta
	if _event_timer_sec <= 0.0:
		_seed_new_arrival_if_possible()
		_event_timer_sec = _current_event_interval()
	_update_all_ui()


func _unhandled_input(event: InputEvent) -> void:
	if not running:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				select_table(1)
				get_viewport().set_input_as_handled()
			KEY_2:
				select_table(2)
				get_viewport().set_input_as_handled()
			KEY_3:
				select_table(3)
				get_viewport().set_input_as_handled()
			KEY_4:
				select_table(4)
				get_viewport().set_input_as_handled()
			KEY_Q:
				_perform_selected_action(ACTION_TAKE_ORDER)
				get_viewport().set_input_as_handled()
			KEY_W:
				_perform_selected_action(ACTION_DELIVER_FOOD)
				get_viewport().set_input_as_handled()
			KEY_E:
				_perform_selected_action(ACTION_REFILL_DRINK)
				get_viewport().set_input_as_handled()
			KEY_R:
				_perform_selected_action(ACTION_COLLECT_PAYMENT)
				get_viewport().set_input_as_handled()
			KEY_T:
				_perform_selected_action(ACTION_CLEAN_TABLE)
				get_viewport().set_input_as_handled()


func configure_for_workplace(workplace, skill_level: int = 0) -> bool:
	player_skill_level = maxi(skill_level, 0)
	if workplace == null:
		_apply_workplace_labels("Restaurant", "Restaurant")
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
	var normalized := _normalize_workplace_type(type_name)
	return normalized == "restaurant" \
		or normalized == "cafe" \
		or normalized == "bakery" \
		or normalized == "baeckerei" \
		or normalized == "baecker" \
		or normalized == "backer"


func start_session() -> void:
	running = true
	elapsed_sec = 0.0
	score = 0
	combo = 0
	best_combo = 0
	mistakes = 0
	completed_tasks = 0
	failed_tables = 0
	customer_satisfaction = 100.0
	_event_timer_sec = _current_event_interval()
	_reset_tables()
	_selected_table_index = maxi(get_highest_priority_table_number() - 1, 0)
	_set_hint("%s: hoechste Prioritaet erkennen und passende Aktion ausfuehren." % workplace_label)
	_update_all_ui()


func finish_session() -> void:
	if not running:
		return
	running = false
	_update_all_ui()
	session_finished.emit(get_result())


func get_result() -> Dictionary:
	var quality := get_service_quality()
	return {
		"score": score,
		"combo": combo,
		"best_combo": best_combo,
		"mistakes": mistakes,
		"completed_tasks": completed_tasks,
		"failed_tables": failed_tables,
		"customer_satisfaction": customer_satisfaction,
		"service_quality": quality,
		"work_bonus_multiplier": get_work_bonus_multiplier(),
		"customer_satisfaction_delta": get_customer_satisfaction_delta(),
		"success": quality >= QUALITY_BONUS_THRESHOLD,
		"workplace_type": workplace_type,
		"workplace_label": workplace_label,
	}


func get_service_quality() -> float:
	var resolved_total := completed_tasks + failed_tables + mistakes
	if resolved_total <= 0:
		return 0.0
	var completion_factor := float(completed_tasks) / float(resolved_total)
	var satisfaction_factor := clampf(customer_satisfaction / 100.0, 0.0, 1.0)
	var combo_factor := clampf(float(best_combo) / 10.0, 0.0, 1.0)
	var mistake_penalty := clampf(float(mistakes) * 0.035, 0.0, 0.28)
	return clampf(
		completion_factor * 0.48 + satisfaction_factor * 0.42 + combo_factor * 0.10 - mistake_penalty,
		0.0,
		1.0
	)


func get_work_bonus_multiplier() -> float:
	var quality := get_service_quality()
	if quality < 0.38:
		return 0.0
	return snappedf(0.65 + quality * 0.75, 0.01)


func get_customer_satisfaction_delta() -> int:
	var quality := get_service_quality()
	if quality >= 0.88 and mistakes == 0:
		return 3
	if quality >= QUALITY_BONUS_THRESHOLD:
		return 2
	if quality >= 0.44:
		return 1
	return -2


func get_action_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for definition in ACTION_DEFINITIONS:
		ids.append(str(definition.get("id", "")))
	return ids


func get_required_action_for_state(state_id: String) -> String:
	var definition := _get_task_definition(state_id)
	return str(definition.get("required_action", "")) if not definition.is_empty() else ""


func get_required_action_for_table(table_number: int) -> String:
	var snapshot := get_table_snapshot(table_number)
	return str(snapshot.get("required_action", ""))


func get_table_state(table_number: int) -> String:
	var snapshot := get_table_snapshot(table_number)
	return str(snapshot.get("state", ""))


func get_table_snapshot(table_number: int) -> Dictionary:
	_ensure_tables()
	var index := table_number - 1
	if index < 0 or index >= _tables.size():
		return {}
	var table := _tables[index].duplicate(true)
	var state_id := str(table.get("state", STATE_EMPTY))
	var definition := _get_task_definition(state_id)
	table["table_number"] = table_number
	table["state_label"] = _task_label(state_id)
	table["required_action"] = str(definition.get("required_action", ""))
	table["priority"] = _calculate_table_priority(table)
	table["patience_sec"] = _effective_patience_for_state(state_id)
	return table


func get_priority_for_table(table_number: int) -> float:
	return float(get_table_snapshot(table_number).get("priority", 0.0))


func get_highest_priority_table_number() -> int:
	_ensure_tables()
	var best_number := 0
	var best_priority := -1.0
	for index in range(_tables.size()):
		var priority := _calculate_table_priority(_tables[index])
		if priority > best_priority:
			best_priority = priority
			best_number = index + 1
	return best_number


func select_table(table_number: int) -> bool:
	var index := table_number - 1
	if index < 0 or index >= TABLE_COUNT:
		return false
	_selected_table_index = index
	_update_all_ui()
	return true


func debug_perform_action(table_number: int, action_id: String) -> Dictionary:
	return _perform_table_action(table_number - 1, action_id)


func debug_set_elapsed(seconds: float) -> void:
	elapsed_sec = clampf(seconds, 0.0, session_duration_sec)
	_update_all_ui()


func debug_get_current_event_interval() -> float:
	return _current_event_interval()


func debug_get_current_patience_multiplier() -> float:
	return _current_patience_multiplier()


func debug_force_table_state(table_number: int, state_id: String, wait_sec: float = 0.0) -> bool:
	_ensure_tables()
	var index := table_number - 1
	if index < 0 or index >= _tables.size():
		return false
	var table := _make_table(index, state_id, wait_sec)
	_tables[index] = table
	_update_all_ui()
	return true


func debug_advance_time(seconds: float) -> void:
	_tick_tables(maxf(seconds, 0.0))
	_update_all_ui()


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color8(13, 17, 23, 255)
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
	title.text = "Kellner: Service Flow"
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
	_quality_label = _make_status_label()
	header.add_child(_score_label)
	header.add_child(_combo_label)
	header.add_child(_timer_label)
	header.add_child(_quality_label)

	var content := HBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", UiThemeScript.SEPARATION_NORMAL)
	root.add_child(content)

	var table_panel := PanelContainer.new()
	table_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	table_panel.custom_minimum_size = Vector2(560, 0)
	table_panel.add_theme_stylebox_override("panel", _make_panel_box(Color8(20, 26, 36, 255), UiThemeScript.BORDER_STRONG))
	content.add_child(table_panel)

	var table_box := VBoxContainer.new()
	table_box.add_theme_constant_override("separation", UiThemeScript.SEPARATION_NORMAL)
	table_panel.add_child(table_box)

	var table_title := Label.new()
	table_title.text = "Tische"
	table_title.add_theme_font_size_override("font_size", 17)
	table_title.add_theme_color_override("font_color", UiThemeScript.TEXT_PRIMARY)
	table_box.add_child(table_title)

	var table_grid := GridContainer.new()
	table_grid.columns = 2
	table_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	table_grid.add_theme_constant_override("h_separation", UiThemeScript.SEPARATION_NORMAL)
	table_grid.add_theme_constant_override("v_separation", UiThemeScript.SEPARATION_NORMAL)
	table_box.add_child(table_grid)

	for table_index in range(TABLE_COUNT):
		var table_button := _make_table_button(table_index)
		_table_buttons.append(table_button)
		table_grid.add_child(table_button)

	var side_panel := PanelContainer.new()
	side_panel.custom_minimum_size = Vector2(320, 0)
	side_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side_panel.add_theme_stylebox_override("panel", _make_panel_box(Color8(18, 23, 32, 255), UiThemeScript.BORDER_STRONG))
	content.add_child(side_panel)

	var side_box := VBoxContainer.new()
	side_box.add_theme_constant_override("separation", UiThemeScript.SEPARATION_NORMAL)
	side_panel.add_child(side_box)

	_selected_label = Label.new()
	_selected_label.add_theme_font_size_override("font_size", 17)
	_selected_label.add_theme_color_override("font_color", UiThemeScript.ACCENT)
	_selected_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side_box.add_child(_selected_label)

	_queue_label = Label.new()
	_queue_label.custom_minimum_size = Vector2(0, 128)
	_queue_label.add_theme_color_override("font_color", UiThemeScript.TEXT_SECONDARY)
	_queue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side_box.add_child(_queue_label)

	var action_grid := GridContainer.new()
	action_grid.columns = 1
	action_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_grid.add_theme_constant_override("v_separation", UiThemeScript.SEPARATION_DENSE)
	side_box.add_child(action_grid)

	for definition in ACTION_DEFINITIONS:
		var action_button := _make_action_button(definition)
		action_grid.add_child(action_button)
		_action_buttons[str(definition.get("id", ""))] = action_button


func _make_status_label() -> Label:
	var label := Label.new()
	label.custom_minimum_size = Vector2(118, 44)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", UiThemeScript.TEXT_PRIMARY)
	UiThemeScript.apply_pill_label(label, UiThemeScript.TEXT_PRIMARY, Color8(35, 41, 56, 255))
	return label


func _make_table_button(table_index: int) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(250, 170)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.size_flags_vertical = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(select_table.bind(table_index + 1))
	return button


func _make_action_button(definition: Dictionary) -> Button:
	var action_id := str(definition.get("id", ""))
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 58)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	button.text = "%s  [%s]\n%s" % [
		str(definition.get("label", "")),
		str(definition.get("key", "")),
		str(definition.get("hint", "")),
	]
	button.pressed.connect(_perform_selected_action.bind(action_id))
	var color: Color = definition.get("color", UiThemeScript.ACCENT)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", _make_button_box(color.darkened(0.70), color.darkened(0.1), false))
	button.add_theme_stylebox_override("hover", _make_button_box(color.darkened(0.56), color, true))
	button.add_theme_stylebox_override("pressed", _make_button_box(color.darkened(0.76), color.lightened(0.1), true))
	return button


func _perform_selected_action(action_id: String) -> void:
	var result := _perform_table_action(_selected_table_index, action_id)
	if bool(result.get("correct", false)):
		_selected_table_index = maxi(get_highest_priority_table_number() - 1, 0)
	_update_all_ui()


func _perform_table_action(table_index: int, action_id: String) -> Dictionary:
	_ensure_tables()
	if table_index < 0 or table_index >= _tables.size():
		return {"correct": false, "reason": "invalid_table", "score": score}
	var table := _tables[table_index]
	var state_id := str(table.get("state", STATE_EMPTY))
	var definition := _get_task_definition(state_id)
	if definition.is_empty():
		_set_hint("Tisch %d hat gerade keine Aufgabe." % (table_index + 1))
		return {
			"correct": false,
			"reason": "no_task",
			"table_number": table_index + 1,
			"score": score,
			"combo": combo,
		}
	var required_action := str(definition.get("required_action", ""))
	if action_id == required_action:
		_score_correct_service(table_index, definition)
		_advance_table_state(table_index, state_id)
		task_resolved.emit(table_index + 1, action_id, true)
		var result := get_table_snapshot(table_index + 1)
		result["correct"] = true
		result["score"] = score
		result["combo"] = combo
		return result
	_register_mistake("wrong_action")
	table["wait_sec"] = float(table.get("wait_sec", 0.0)) + WRONG_ACTION_WAIT_PENALTY_SEC
	_tables[table_index] = table
	_set_hint(
		"Falsch an Tisch %d: gebraucht wird %s." % [
			table_index + 1,
			_action_label(required_action),
		]
	)
	task_resolved.emit(table_index + 1, action_id, false)
	return {
		"correct": false,
		"reason": "wrong_action",
		"table_number": table_index + 1,
		"state": state_id,
		"required_action": required_action,
		"score": score,
		"combo": combo,
		"customer_satisfaction": customer_satisfaction,
	}


func _score_correct_service(table_index: int, definition: Dictionary) -> void:
	var table := _tables[table_index]
	var priority := _calculate_table_priority(table)
	var wait_sec := float(table.get("wait_sec", 0.0))
	var patience_sec := _effective_patience_for_state(str(table.get("state", STATE_EMPTY)))
	completed_tasks += 1
	combo += 1
	best_combo = maxi(best_combo, combo)
	var combo_bonus := mini(maxi(combo - 1, 0) * 2, 14)
	var priority_bonus := int(round(clampf(priority, 0.0, MAX_PRIORITY_FOR_UI) * 0.32))
	score += int(definition.get("points", 10)) + priority_bonus + combo_bonus
	var wait_ratio := wait_sec / maxf(patience_sec, 1.0)
	var satisfaction_gain := 3.0 if wait_ratio <= 0.5 else 1.0
	customer_satisfaction = clampf(customer_satisfaction + satisfaction_gain, 0.0, 100.0)
	score_changed.emit(score)
	combo_changed.emit(combo)
	satisfaction_changed.emit(customer_satisfaction)
	_set_hint(
		"Tisch %d erledigt: %s." % [
			table_index + 1,
			_action_label(str(definition.get("required_action", ""))),
		]
	)


func _register_mistake(reason: String) -> void:
	mistakes += 1
	combo = 0
	score = maxi(score - 7, 0)
	customer_satisfaction = clampf(customer_satisfaction - 6.0, 0.0, 100.0)
	score_changed.emit(score)
	combo_changed.emit(combo)
	satisfaction_changed.emit(customer_satisfaction)
	mistake_made.emit(reason)


func _tick_tables(delta: float) -> void:
	for index in range(_tables.size()):
		var table := _tables[index]
		var state_id := str(table.get("state", STATE_EMPTY))
		if state_id == STATE_EMPTY:
			continue
		table["wait_sec"] = float(table.get("wait_sec", 0.0)) + delta
		_tables[index] = table
		if float(table.get("wait_sec", 0.0)) > _effective_patience_for_state(state_id):
			_fail_table(index)


func _fail_table(table_index: int) -> void:
	var table := _tables[table_index]
	var old_state := str(table.get("state", STATE_EMPTY))
	if old_state == STATE_EMPTY:
		return
	failed_tables += 1
	mistakes += 1
	combo = 0
	score = maxi(score - 12, 0)
	customer_satisfaction = clampf(customer_satisfaction - 15.0, 0.0, 100.0)
	var next_state := STATE_EMPTY if old_state == STATE_DIRTY else STATE_DIRTY
	_tables[table_index] = _make_table(table_index, next_state, 0.0)
	_set_hint("Tisch %d verloren: Wartezeit war zu lang." % (table_index + 1))
	score_changed.emit(score)
	combo_changed.emit(combo)
	satisfaction_changed.emit(customer_satisfaction)
	mistake_made.emit("table_timeout")


func _advance_table_state(table_index: int, previous_state: String) -> void:
	var next_state := _next_state_after_service(previous_state)
	_tables[table_index] = _make_table(table_index, next_state, 0.0)


func _next_state_after_service(previous_state: String) -> String:
	match previous_state:
		STATE_NEW_ARRIVAL:
			return STATE_WAITING_FOOD
		STATE_WAITING_FOOD:
			return STATE_LOW_DRINK
		STATE_WRONG_FOOD:
			return STATE_LOW_DRINK
		STATE_LOW_DRINK:
			return STATE_WANTS_PAY
		STATE_WANTS_PAY:
			return STATE_DIRTY
		STATE_DIRTY:
			return STATE_EMPTY
	return STATE_EMPTY


func _seed_new_arrival_if_possible() -> void:
	var empty_indices: Array[int] = []
	for index in range(_tables.size()):
		if str(_tables[index].get("state", STATE_EMPTY)) == STATE_EMPTY:
			empty_indices.append(index)
	if empty_indices.is_empty():
		return
	var chosen_index := empty_indices[_rng.randi_range(0, empty_indices.size() - 1)]
	_tables[chosen_index] = _make_table(chosen_index, STATE_NEW_ARRIVAL, 0.0)
	if chosen_index == _selected_table_index:
		_set_hint("Tisch %d ist neu angekommen." % (chosen_index + 1))


func _reset_tables() -> void:
	_tables.clear()
	for index in range(TABLE_COUNT):
		var seed: Dictionary = INITIAL_TABLES[index]
		_tables.append(_make_table(index, str(seed.get("state", STATE_EMPTY)), float(seed.get("wait_sec", 0.0))))


func _ensure_tables() -> void:
	if _tables.size() != TABLE_COUNT:
		_reset_tables()


func _make_table(index: int, state_id: String, wait_sec: float) -> Dictionary:
	return {
		"id": "table_%d" % (index + 1),
		"label": "Tisch %d" % (index + 1),
		"state": state_id,
		"wait_sec": maxf(wait_sec, 0.0),
	}


func _calculate_table_priority(table: Dictionary) -> float:
	var state_id := str(table.get("state", STATE_EMPTY))
	var definition := _get_task_definition(state_id)
	if definition.is_empty():
		return 0.0
	var wait_sec := float(table.get("wait_sec", 0.0))
	var patience_sec := _effective_patience_for_state(state_id)
	var pressure := clampf(wait_sec / maxf(patience_sec, 1.0), 0.0, 1.65)
	var priority := float(definition.get("base_priority", 0.0)) + pressure * 48.0
	if state_id == STATE_WRONG_FOOD:
		priority += 5.0
	return priority


func _effective_patience_for_state(state_id: String) -> float:
	var definition := _get_task_definition(state_id)
	if definition.is_empty():
		return 9999.0
	return maxf(float(definition.get("patience_sec", 40.0)) * _current_patience_multiplier(), 12.0)


func _current_event_interval() -> float:
	var progress := _session_progress()
	var skill_pressure := minf(float(player_skill_level) * 0.12, 0.42)
	var interval := lerpf(BASE_EVENT_INTERVAL_SEC, MIN_EVENT_INTERVAL_SEC, clampf(progress + skill_pressure, 0.0, 1.0))
	return maxf(interval, MIN_EVENT_INTERVAL_SEC)


func _current_patience_multiplier() -> float:
	var progress := _session_progress()
	var skill_pressure := minf(float(player_skill_level) * 0.04, 0.18)
	return clampf(1.0 - progress * 0.24 - skill_pressure, 0.58, 1.0)


func _session_progress() -> float:
	if session_duration_sec <= 0.0:
		return 1.0
	return clampf(elapsed_sec / session_duration_sec, 0.0, 1.0)


func _update_all_ui() -> void:
	_update_status_labels()
	_update_table_cards()
	_update_side_panel()
	_update_action_buttons()


func _update_status_labels() -> void:
	if _score_label != null:
		_score_label.text = "Score\n%d" % score
	if _combo_label != null:
		_combo_label.text = "Combo\n%d" % combo
	if _timer_label != null:
		var remaining := maxf(session_duration_sec - elapsed_sec, 0.0)
		_timer_label.text = "Zeit\n%02ds" % int(ceil(remaining))
	if _quality_label != null:
		_quality_label.text = "Zufrieden\n%d%%" % int(round(customer_satisfaction))


func _update_table_cards() -> void:
	_ensure_tables()
	for index in range(_table_buttons.size()):
		var button := _table_buttons[index]
		if button == null:
			continue
		var table := _tables[index]
		var state_id := str(table.get("state", STATE_EMPTY))
		var priority := _calculate_table_priority(table)
		var wait_sec := float(table.get("wait_sec", 0.0))
		var required_action := get_required_action_for_state(state_id)
		if state_id == STATE_EMPTY:
			button.text = "Tisch %d\nfrei\n-\nPrioritaet 0" % (index + 1)
		else:
			button.text = "Tisch %d\n%s\n%s\n%ds  P%d" % [
				index + 1,
				_task_label(state_id),
				_action_label(required_action),
				int(round(wait_sec)),
				int(round(priority)),
			]
		_apply_table_button_style(button, state_id, priority, index == _selected_table_index)


func _update_side_panel() -> void:
	var selected_number := _selected_table_index + 1
	var selected_snapshot := get_table_snapshot(selected_number)
	if _selected_label != null:
		if selected_snapshot.is_empty() or str(selected_snapshot.get("state", STATE_EMPTY)) == STATE_EMPTY:
			_selected_label.text = "Tisch %d ausgewaehlt\nkeine Aufgabe" % selected_number
		else:
			_selected_label.text = "Tisch %d ausgewaehlt\n%s -> %s" % [
				selected_number,
				str(selected_snapshot.get("state_label", "")),
				_action_label(str(selected_snapshot.get("required_action", ""))),
			]
	if _queue_label != null:
		var lines := PackedStringArray()
		lines.append("Prioritaetsliste")
		var indices := _get_priority_indices()
		for rank in range(mini(indices.size(), TABLE_COUNT)):
			var index := indices[rank]
			var snapshot := get_table_snapshot(index + 1)
			if float(snapshot.get("priority", 0.0)) <= 0.0:
				continue
			lines.append(
				"%d. Tisch %d  P%d  %s" % [
					rank + 1,
					index + 1,
					int(round(float(snapshot.get("priority", 0.0)))),
					str(snapshot.get("state_label", "")),
				]
			)
		_queue_label.text = "\n".join(lines)


func _update_action_buttons() -> void:
	var required_action := get_required_action_for_table(_selected_table_index + 1)
	for action_id in _action_buttons.keys():
		var button: Button = _action_buttons[action_id]
		var definition := _get_action_definition(str(action_id))
		var color: Color = definition.get("color", UiThemeScript.ACCENT)
		var highlighted := str(action_id) == required_action and not required_action.is_empty()
		button.add_theme_stylebox_override(
			"normal",
			_make_button_box(color.darkened(0.58 if highlighted else 0.70), color, highlighted)
		)


func _get_priority_indices() -> Array[int]:
	var indices: Array[int] = []
	for index in range(_tables.size()):
		indices.append(index)
	indices.sort_custom(func(a: int, b: int) -> bool:
		return _calculate_table_priority(_tables[a]) > _calculate_table_priority(_tables[b])
	)
	return indices


func _apply_table_button_style(button: Button, state_id: String, priority: float, selected: bool) -> void:
	var color := UiThemeScript.BORDER_STRONG
	var definition := _get_task_definition(state_id)
	if not definition.is_empty():
		color = definition.get("color", UiThemeScript.ACCENT)
	var bg := color.darkened(0.70)
	if priority >= 76.0:
		bg = UiThemeScript.DANGER.darkened(0.62)
	elif priority >= 54.0:
		bg = color.darkened(0.58)
	if selected:
		bg = color.darkened(0.46)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", _make_button_box(bg, color, selected))
	button.add_theme_stylebox_override("hover", _make_button_box(color.darkened(0.48), color, true))
	button.add_theme_stylebox_override("pressed", _make_button_box(color.darkened(0.62), color.lightened(0.1), true))


func _get_task_definition(state_id: String) -> Dictionary:
	for definition in TASK_DEFINITIONS:
		if str(definition.get("state", "")) == state_id:
			return definition
	return {}


func _get_action_definition(action_id: String) -> Dictionary:
	for definition in ACTION_DEFINITIONS:
		if str(definition.get("id", "")) == action_id:
			return definition
	return {}


func _task_label(state_id: String) -> String:
	if state_id == STATE_EMPTY:
		return "Frei"
	var definition := _get_task_definition(state_id)
	return str(definition.get("label", state_id)) if not definition.is_empty() else state_id


func _action_label(action_id: String) -> String:
	var definition := _get_action_definition(action_id)
	if definition.is_empty():
		return action_id
	return "%s %s" % [str(definition.get("label", "")), str(definition.get("hint", ""))]


func _set_hint(text: String) -> void:
	if _hint_label != null:
		_hint_label.text = text


func _resolve_workplace_type_name(workplace) -> String:
	if workplace == null:
		return "Restaurant"
	if workplace.has_method("get_building_type_name"):
		return str(workplace.call("get_building_type_name"))
	var script: Script = workplace.get_script()
	if script != null and script.has_method("get_global_name"):
		var global_name := str(script.get_global_name())
		if not global_name.is_empty():
			return global_name
	return str(workplace.get_class())


func _apply_workplace_labels(type_name: String, label: String) -> void:
	workplace_type = type_name
	workplace_label = label
	if _hint_label != null:
		_set_hint("%s: Service Flow." % workplace_label)


func _normalize_workplace_type(type_name: String) -> String:
	var normalized := type_name.strip_edges().to_lower()
	if normalized == "cafe":
		return "cafe"
	if normalized == "coffee_shop":
		return "cafe"
	return normalized


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
	box.content_margin_left = 16
	box.content_margin_right = 16
	box.content_margin_top = 14
	box.content_margin_bottom = 14
	return box


func _make_button_box(bg: Color, border: Color, strong_border: bool) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	var width := 2 if strong_border else 1
	box.border_width_left = width
	box.border_width_top = width
	box.border_width_right = width
	box.border_width_bottom = width
	box.corner_radius_top_left = 6
	box.corner_radius_top_right = 6
	box.corner_radius_bottom_left = 6
	box.corner_radius_bottom_right = 6
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	return box
