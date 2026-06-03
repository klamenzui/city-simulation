extends Control
class_name TeacherLessonMinigame

const UiThemeScript = preload("res://Simulation/UI/UiTheme.gd")

signal score_changed(score: int)
signal combo_changed(combo: int)
signal mistake_made(reason: String)
signal question_answered(question_id: String, correct: bool)
signal session_finished(result: Dictionary)

const TARGET_FORMULA := "formula"
const TARGET_EVENT := "event"
const TARGET_TOOL := "tool"

const DEFAULT_SESSION_DURATION_SEC := 75.0
const BASE_QUESTION_WINDOW_SEC := 5.4
const MIN_QUESTION_WINDOW_SEC := 2.2
const TARGET_BUTTON_MIN_SIZE := Vector2(210.0, 92.0)
const QUALITY_BONUS_THRESHOLD := 0.65

const TARGET_DEFINITIONS := [
	{
		"id": TARGET_FORMULA,
		"key": "1",
		"label": "Formel",
		"hint": "Mathe",
		"color": Color8(102, 187, 106, 255),
	},
	{
		"id": TARGET_EVENT,
		"key": "2",
		"label": "Ereignis",
		"hint": "Geschichte",
		"color": Color8(255, 202, 40, 255),
	},
	{
		"id": TARGET_TOOL,
		"key": "3",
		"label": "Werkzeug",
		"hint": "Technik",
		"color": Color8(79, 195, 247, 255),
	},
]

const QUESTION_DEFINITIONS := [
	{
		"id": "area_rectangle",
		"student": "Lina",
		"subject": "Mathe",
		"prompt": "Wie berechnet man die Flaeche eines Rechtecks?",
		"answer": "A = Laenge x Breite",
		"target": TARGET_FORMULA,
		"min_skill": 0,
		"weight": 8,
		"points": 12,
	},
	{
		"id": "percentage",
		"student": "Mika",
		"subject": "Mathe",
		"prompt": "Wie schreibt man einen einfachen Prozentanteil?",
		"answer": "Teil / Ganzes x 100",
		"target": TARGET_FORMULA,
		"min_skill": 0,
		"weight": 7,
		"points": 12,
	},
	{
		"id": "wall_fall",
		"student": "Noah",
		"subject": "Geschichte",
		"prompt": "Was passt zu Berlin im Jahr 1989?",
		"answer": "Mauerfall",
		"target": TARGET_EVENT,
		"min_skill": 0,
		"weight": 8,
		"points": 12,
	},
	{
		"id": "moon_landing",
		"student": "Emma",
		"subject": "Geschichte",
		"prompt": "Was geschah 1969 mit Apollo 11?",
		"answer": "Mondlandung",
		"target": TARGET_EVENT,
		"min_skill": 0,
		"weight": 6,
		"points": 13,
	},
	{
		"id": "screwdriver",
		"student": "Ben",
		"subject": "Technik",
		"prompt": "Womit zieht man eine Schraube fest?",
		"answer": "Schraubendreher",
		"target": TARGET_TOOL,
		"min_skill": 0,
		"weight": 8,
		"points": 12,
	},
	{
		"id": "multimeter",
		"student": "Sara",
		"subject": "Technik",
		"prompt": "Womit misst man Spannung oder Widerstand?",
		"answer": "Multimeter",
		"target": TARGET_TOOL,
		"min_skill": 0,
		"weight": 6,
		"points": 13,
	},
	{
		"id": "pythagoras",
		"student": "Jonas",
		"subject": "Mathe",
		"prompt": "Welche Regel hilft beim rechtwinkligen Dreieck?",
		"answer": "a^2 + b^2 = c^2",
		"target": TARGET_FORMULA,
		"min_skill": 1,
		"weight": 5,
		"points": 15,
	},
	{
		"id": "printing_press",
		"student": "Lea",
		"subject": "Geschichte",
		"prompt": "Was verbreitete Buecher in Europa viel schneller?",
		"answer": "Buchdruck",
		"target": TARGET_EVENT,
		"min_skill": 1,
		"weight": 5,
		"points": 15,
	},
	{
		"id": "debugger",
		"student": "Nora",
		"subject": "Technik",
		"prompt": "Womit findet man Schritt fuer Schritt einen Codefehler?",
		"answer": "Debugger",
		"target": TARGET_TOOL,
		"min_skill": 1,
		"weight": 5,
		"points": 15,
	},
	{
		"id": "circle_area",
		"student": "Paul",
		"subject": "Mathe",
		"prompt": "Welche Antwort passt zur Kreisflaeche?",
		"answer": "A = pi x r^2",
		"target": TARGET_FORMULA,
		"min_skill": 2,
		"weight": 4,
		"points": 18,
	},
	{
		"id": "french_revolution",
		"student": "Marie",
		"subject": "Geschichte",
		"prompt": "Was verbindet man mit Frankreich 1789?",
		"answer": "Franzoesische Revolution",
		"target": TARGET_EVENT,
		"min_skill": 2,
		"weight": 4,
		"points": 18,
	},
	{
		"id": "version_control",
		"student": "Alex",
		"subject": "Technik",
		"prompt": "Womit verwaltet ein Team Code-Aenderungen?",
		"answer": "Versionskontrolle",
		"target": TARGET_TOOL,
		"min_skill": 2,
		"weight": 4,
		"points": 18,
	},
]

@export var auto_start: bool = true
@export var session_duration_sec: float = DEFAULT_SESSION_DURATION_SEC
@export var player_skill_level: int = 0
@export var rng_seed: int = 0

var workplace_label: String = "Universitaet"
var workplace_type: String = "University"
var running: bool = false
var elapsed_sec: float = 0.0
var score: int = 0
var combo: int = 0
var best_combo: int = 0
var mistakes: int = 0
var correct_answers: int = 0
var missed_questions: int = 0

var _rng := RandomNumberGenerator.new()
var _current_question: Dictionary = {}
var _question_timer_sec: float = 0.0
var _last_question_id: String = ""
var _target_buttons: Dictionary = {}

var _score_label: Label = null
var _combo_label: Label = null
var _timer_label: Label = null
var _quality_label: Label = null
var _hint_label: Label = null
var _student_label: Label = null
var _prompt_label: Label = null
var _answer_label: Label = null
var _question_bar: ProgressBar = null


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
	_question_timer_sec -= delta
	if _question_timer_sec <= 0.0:
		_miss_current_question()
		_advance_question()
	_update_status_labels()
	_update_question_bar()


func _unhandled_input(event: InputEvent) -> void:
	if not running:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				_answer_current_to(TARGET_FORMULA)
				get_viewport().set_input_as_handled()
			KEY_2:
				_answer_current_to(TARGET_EVENT)
				get_viewport().set_input_as_handled()
			KEY_3:
				_answer_current_to(TARGET_TOOL)
				get_viewport().set_input_as_handled()


func configure_for_workplace(workplace, skill_level: int = 0) -> bool:
	player_skill_level = maxi(skill_level, 0)
	if workplace == null:
		_apply_workplace_labels("University", "Universitaet")
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
	return normalized == "university" or normalized == "universitaet"


func start_session() -> void:
	running = true
	elapsed_sec = 0.0
	score = 0
	combo = 0
	best_combo = 0
	mistakes = 0
	correct_answers = 0
	missed_questions = 0
	_current_question.clear()
	_question_timer_sec = 0.0
	_set_hint("Studentenfrage lesen, Antwort einordnen: 1 Formel, 2 Ereignis, 3 Werkzeug.")
	score_changed.emit(score)
	combo_changed.emit(combo)
	_advance_question()
	_update_status_labels()


func finish_session() -> void:
	if not running:
		return
	running = false
	_current_question.clear()
	_update_question_ui()
	_update_status_labels()
	_set_hint("Unterricht beendet.")
	session_finished.emit(get_result())


func get_result() -> Dictionary:
	var quality := get_teaching_quality()
	return {
		"score": score,
		"combo": combo,
		"best_combo": best_combo,
		"mistakes": mistakes,
		"correct_answers": correct_answers,
		"missed_questions": missed_questions,
		"elapsed_sec": elapsed_sec,
		"workplace_type": workplace_type,
		"workplace_label": workplace_label,
		"teaching_quality": quality,
		"education_progress_bonus": get_education_progress_bonus(),
		"city_effect_sessions": get_city_effect_sessions(),
	}


func get_teaching_quality() -> float:
	var answered_total := correct_answers + mistakes
	if answered_total <= 0:
		return 0.0
	var accuracy := float(correct_answers) / float(answered_total)
	var volume := clampf(float(correct_answers) / 12.0, 0.0, 1.0)
	var combo_factor := clampf(float(best_combo) / 8.0, 0.0, 1.0)
	return clampf(accuracy * 0.55 + volume * 0.30 + combo_factor * 0.15, 0.0, 1.0)


func get_education_progress_bonus() -> int:
	return 1 if get_teaching_quality() >= QUALITY_BONUS_THRESHOLD else 0


func get_city_effect_sessions() -> int:
	if get_education_progress_bonus() <= 0:
		return 0
	return 2 + int(round(get_teaching_quality() * 3.0))


func get_target_for_question(question_id: String) -> String:
	var definition := _get_question_definition(question_id)
	return str(definition.get("target", "")) if not definition.is_empty() else ""


func get_question_ids_for_skill(skill_level: int = -1) -> PackedStringArray:
	var resolved_skill := player_skill_level if skill_level < 0 else maxi(skill_level, 0)
	var ids := PackedStringArray()
	for definition in QUESTION_DEFINITIONS:
		if int(definition.get("min_skill", 0)) <= resolved_skill:
			ids.append(str(definition.get("id", "")))
	return ids


func debug_answer_question(question_id: String, target_id: String) -> Dictionary:
	var definition := _get_question_definition(question_id)
	if definition.is_empty():
		return {"correct": false, "reason": "unknown_question", "score": score}
	var correct := str(definition.get("target", "")) == target_id
	if correct:
		_score_correct_answer(definition)
	else:
		_register_mistake("wrong_target")
	question_answered.emit(question_id, correct)
	return {
		"correct": correct,
		"target": str(definition.get("target", "")),
		"score": score,
		"combo": combo,
		"teaching_quality": get_teaching_quality(),
		"education_progress_bonus": get_education_progress_bonus(),
	}


func debug_get_current_question_window() -> float:
	return _current_question_window()


func debug_set_elapsed(seconds: float) -> void:
	elapsed_sec = clampf(seconds, 0.0, session_duration_sec)
	_update_status_labels()


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color8(13, 18, 25, 255)
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
	title.text = "Teacher: Unterricht halten"
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

	var question_panel := PanelContainer.new()
	question_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	question_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	question_panel.custom_minimum_size = Vector2(0, 250)
	question_panel.add_theme_stylebox_override("panel", _make_panel_box(Color8(20, 26, 36, 255), UiThemeScript.BORDER_STRONG))
	root.add_child(question_panel)

	var question_box := VBoxContainer.new()
	question_box.add_theme_constant_override("separation", UiThemeScript.SEPARATION_NORMAL)
	question_panel.add_child(question_box)

	_student_label = Label.new()
	_student_label.add_theme_font_size_override("font_size", 16)
	_student_label.add_theme_color_override("font_color", UiThemeScript.ACCENT)
	question_box.add_child(_student_label)

	_prompt_label = Label.new()
	_prompt_label.add_theme_font_size_override("font_size", 21)
	_prompt_label.add_theme_color_override("font_color", UiThemeScript.TEXT_PRIMARY)
	_prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	question_box.add_child(_prompt_label)

	_answer_label = Label.new()
	_answer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_answer_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_answer_label.custom_minimum_size = Vector2(0, 82)
	_answer_label.add_theme_font_size_override("font_size", 24)
	_answer_label.add_theme_color_override("font_color", UiThemeScript.TEXT_ON_ACCENT)
	_answer_label.add_theme_stylebox_override("normal", _make_panel_box(Color8(231, 235, 242, 255), UiThemeScript.ACCENT))
	question_box.add_child(_answer_label)

	_question_bar = ProgressBar.new()
	_question_bar.custom_minimum_size = Vector2(0, 18)
	_question_bar.show_percentage = false
	question_box.add_child(_question_bar)

	var target_row := HBoxContainer.new()
	target_row.add_theme_constant_override("separation", UiThemeScript.SEPARATION_NORMAL)
	target_row.custom_minimum_size = Vector2(0, 110)
	root.add_child(target_row)

	for definition in TARGET_DEFINITIONS:
		var target_button := _make_target_button(definition)
		target_row.add_child(target_button)
		_target_buttons[str(definition.get("id", ""))] = target_button

	_update_question_ui()


func _make_status_label() -> Label:
	var label := Label.new()
	label.custom_minimum_size = Vector2(118, 44)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", UiThemeScript.TEXT_PRIMARY)
	UiThemeScript.apply_pill_label(label, UiThemeScript.TEXT_PRIMARY, Color8(35, 41, 56, 255))
	return label


func _make_target_button(definition: Dictionary) -> Button:
	var target_id := str(definition.get("id", ""))
	var button := Button.new()
	button.custom_minimum_size = TARGET_BUTTON_MIN_SIZE
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


func _on_target_pressed(target_id: String) -> void:
	_answer_current_to(target_id)


func _answer_current_to(target_id: String) -> void:
	if _current_question.is_empty():
		_set_hint("Es ist gerade keine Frage aktiv.")
		return
	var question_id := str(_current_question.get("id", ""))
	var correct_target := str(_current_question.get("target", ""))
	if target_id == correct_target:
		_score_correct_answer(_current_question)
		_set_hint("Richtig: %s ist %s." % [str(_current_question.get("answer", "")), _target_label(target_id)])
		question_answered.emit(question_id, true)
	else:
		_register_mistake("wrong_target")
		_set_hint("Falsch: %s gehoert zu %s." % [str(_current_question.get("answer", "")), _target_label(correct_target)])
		question_answered.emit(question_id, false)
	_advance_question()
	_update_status_labels()


func _score_correct_answer(definition: Dictionary) -> void:
	correct_answers += 1
	combo += 1
	best_combo = maxi(best_combo, combo)
	var time_bonus := int(ceil(clampf(_question_timer_sec, 0.0, BASE_QUESTION_WINDOW_SEC) * 0.8))
	var combo_bonus := mini(maxi(combo - 1, 0), 10)
	score += int(definition.get("points", 12)) + combo_bonus + time_bonus
	score_changed.emit(score)
	combo_changed.emit(combo)


func _register_mistake(reason: String) -> void:
	mistakes += 1
	combo = 0
	score = maxi(score - 4, 0)
	score_changed.emit(score)
	combo_changed.emit(combo)
	mistake_made.emit(reason)


func _miss_current_question() -> void:
	if _current_question.is_empty():
		return
	missed_questions += 1
	_register_mistake("missed_question")
	_set_hint("Verpasst: %s." % str(_current_question.get("answer", "Antwort")))
	question_answered.emit(str(_current_question.get("id", "")), false)


func _advance_question() -> void:
	if not running:
		return
	var definition := _pick_question_definition()
	if definition.is_empty():
		_current_question.clear()
		_update_question_ui()
		return
	_current_question = definition.duplicate(true)
	_last_question_id = str(_current_question.get("id", ""))
	_question_timer_sec = _current_question_window()
	_update_question_ui()
	_update_question_bar()


func _pick_question_definition() -> Dictionary:
	var candidates: Array[Dictionary] = []
	var total_weight := 0
	for definition in QUESTION_DEFINITIONS:
		if int(definition.get("min_skill", 0)) > player_skill_level:
			continue
		if QUESTION_DEFINITIONS.size() > 1 and str(definition.get("id", "")) == _last_question_id:
			continue
		var weight := maxi(int(definition.get("weight", 1)), 1)
		candidates.append(definition)
		total_weight += weight
	if candidates.is_empty():
		for definition in QUESTION_DEFINITIONS:
			if int(definition.get("min_skill", 0)) <= player_skill_level:
				candidates.append(definition)
				total_weight += maxi(int(definition.get("weight", 1)), 1)
	if candidates.is_empty():
		return {}
	var roll := _rng.randi_range(1, total_weight)
	var cursor := 0
	for definition in candidates:
		cursor += maxi(int(definition.get("weight", 1)), 1)
		if roll <= cursor:
			return definition
	return candidates.back()


func _get_question_definition(question_id: String) -> Dictionary:
	for definition in QUESTION_DEFINITIONS:
		if str(definition.get("id", "")) == question_id:
			return definition
	return {}


func _current_question_window() -> float:
	var progress := _session_progress()
	var skill_pressure := minf(float(player_skill_level) * 0.16, 0.48)
	return maxf(lerpf(BASE_QUESTION_WINDOW_SEC, MIN_QUESTION_WINDOW_SEC, progress) - skill_pressure, MIN_QUESTION_WINDOW_SEC)


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
	_quality_label.text = "Qualitaet\n%d%%" % int(round(get_teaching_quality() * 100.0))


func _update_question_ui() -> void:
	if _student_label == null:
		return
	if _current_question.is_empty():
		_student_label.text = "Kein aktiver Student"
		_prompt_label.text = ""
		_answer_label.text = ""
		return
	_student_label.text = "%s fragt in %s" % [
		str(_current_question.get("student", "Student")),
		str(_current_question.get("subject", "Unterricht")),
	]
	_prompt_label.text = str(_current_question.get("prompt", ""))
	_answer_label.text = str(_current_question.get("answer", ""))


func _update_question_bar() -> void:
	if _question_bar == null:
		return
	var window := _current_question_window()
	_question_bar.max_value = maxf(window, 0.1)
	_question_bar.value = clampf(_question_timer_sec, 0.0, window)


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
		return "University"
	if workplace.has_method("get_building_type_name"):
		return str(workplace.call("get_building_type_name"))
	if workplace is University:
		return "University"
	return str(workplace.get_class())


func _apply_workplace_labels(type_name: String, label: String) -> void:
	workplace_type = type_name
	workplace_label = label
	if _hint_label != null:
		_set_hint("%s: Unterricht halten." % workplace_label)


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
