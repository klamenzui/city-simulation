extends Control
class_name CookingIngredientCatchMinigame

const UiThemeScript = preload("res://Simulation/UI/UiTheme.gd")

signal score_changed(score: int)
signal combo_changed(combo: int)
signal quality_changed(quality: float)
signal mistake_made(reason: String)
signal recipe_completed(recipe_id: String, quality: float)
signal session_finished(result: Dictionary)

const DEFAULT_SESSION_DURATION_SEC := 82.0
const BASE_FALL_SPEED := 150.0
const MAX_FALL_SPEED := 360.0
const BASE_SPAWN_INTERVAL_SEC := 1.05
const MIN_SPAWN_INTERVAL_SEC := 0.38
const MAX_ACTIVE_ITEMS := 12
const FALLING_ITEM_SIZE := Vector2(128.0, 54.0)
const CATCHER_SIZE := Vector2(156.0, 34.0)
const CATCHER_SPEED := 560.0
const WRONG_CATCH_QUALITY_PENALTY := 10.0
const HARMFUL_CATCH_QUALITY_PENALTY := 16.0
const WRONG_CATCH_TIME_PENALTY_SEC := 3.0
const MAX_MISTAKES := 3
const QUALITY_BONUS_THRESHOLD := 70.0

const RECIPE_DEFINITIONS := [
	{
		"id": "sandwich",
		"label": "Sandwich",
		"workplace_types": ["restaurant", "cafe", "bakery"],
		"min_skill": 0,
		"weight": 9,
		"ingredients": {"bread": 1, "cheese": 1, "lettuce": 1, "tomato": 1},
	},
	{
		"id": "soup",
		"label": "Suppe",
		"workplace_types": ["restaurant"],
		"min_skill": 0,
		"weight": 8,
		"ingredients": {"potato": 1, "carrot": 1, "water": 1},
	},
	{
		"id": "salad",
		"label": "Salat",
		"workplace_types": ["restaurant", "cafe"],
		"min_skill": 0,
		"weight": 8,
		"ingredients": {"lettuce": 1, "tomato": 1, "carrot": 1},
	},
	{
		"id": "burger",
		"label": "Burger",
		"workplace_types": ["restaurant"],
		"min_skill": 0,
		"weight": 7,
		"ingredients": {"bread": 1, "meat": 1, "cheese": 1, "lettuce": 1},
	},
	{
		"id": "cake",
		"label": "Kuchen",
		"workplace_types": ["cafe", "bakery"],
		"min_skill": 0,
		"weight": 8,
		"ingredients": {"flour": 1, "egg": 1, "milk": 1, "sugar": 1},
	},
	{
		"id": "pancakes",
		"label": "Pancakes",
		"workplace_types": ["cafe", "bakery"],
		"min_skill": 1,
		"weight": 6,
		"ingredients": {"flour": 1, "egg": 1, "milk": 1, "sugar": 1, "butter": 1},
	},
	{
		"id": "hearty_soup",
		"label": "Gemuese-Suppe",
		"workplace_types": ["restaurant"],
		"min_skill": 1,
		"weight": 5,
		"ingredients": {"carrot": 2, "potato": 2, "onion": 1, "water": 1},
	},
	{
		"id": "pizza",
		"label": "Pizza",
		"workplace_types": ["restaurant"],
		"min_skill": 1,
		"weight": 6,
		"ingredients": {"dough": 1, "tomato": 1, "cheese": 1, "mushroom": 1, "salami": 1},
	},
	{
		"id": "pasta",
		"label": "Pasta",
		"workplace_types": ["restaurant"],
		"min_skill": 2,
		"weight": 5,
		"ingredients": {"noodles": 1, "tomato": 1, "cheese": 1, "basil": 1},
	},
	{
		"id": "coffee_cake",
		"label": "Kaffee mit Kuchen",
		"workplace_types": ["cafe"],
		"min_skill": 2,
		"weight": 5,
		"ingredients": {"coffee": 1, "milk": 1, "sugar": 1, "cake_piece": 1},
	},
]

const PRODUCT_DEFINITIONS := [
	{"id": "bread", "label": "Brot", "icon": "BROT", "category": "base", "min_skill": 0, "weight": 8, "points": 10, "color": Color8(210, 157, 77, 255)},
	{"id": "cheese", "label": "Kaese", "icon": "KAESE", "category": "dairy", "min_skill": 0, "weight": 8, "points": 10, "color": Color8(248, 218, 92, 255)},
	{"id": "lettuce", "label": "Salat", "icon": "SALAT", "category": "vegetable", "min_skill": 0, "weight": 8, "points": 10, "color": Color8(105, 190, 91, 255)},
	{"id": "tomato", "label": "Tomate", "icon": "TOMATE", "category": "vegetable", "min_skill": 0, "weight": 8, "points": 10, "color": Color8(230, 78, 72, 255)},
	{"id": "potato", "label": "Kartoffel", "icon": "KART.", "category": "vegetable", "min_skill": 0, "weight": 7, "points": 10, "color": Color8(191, 154, 91, 255)},
	{"id": "carrot", "label": "Karotte", "icon": "KAROT.", "category": "vegetable", "min_skill": 0, "weight": 7, "points": 10, "color": Color8(242, 136, 54, 255)},
	{"id": "meat", "label": "Fleisch", "icon": "FLEISCH", "category": "meat", "min_skill": 0, "weight": 6, "points": 12, "color": Color8(190, 83, 92, 255)},
	{"id": "flour", "label": "Mehl", "icon": "MEHL", "category": "base", "min_skill": 0, "weight": 7, "points": 10, "color": Color8(232, 224, 202, 255)},
	{"id": "egg", "label": "Ei", "icon": "EI", "category": "protein", "min_skill": 0, "weight": 6, "points": 10, "color": Color8(246, 237, 196, 255)},
	{"id": "milk", "label": "Milch", "icon": "MILCH", "category": "dairy", "min_skill": 0, "weight": 7, "points": 10, "color": Color8(224, 237, 245, 255)},
	{"id": "water", "label": "Wasser", "icon": "WASSER", "category": "drink", "min_skill": 0, "weight": 6, "points": 10, "color": Color8(100, 180, 235, 255)},
	{"id": "sugar", "label": "Zucker", "icon": "ZUCKER", "category": "sweet", "min_skill": 0, "weight": 6, "points": 10, "color": Color8(241, 242, 244, 255)},
	{"id": "butter", "label": "Butter", "icon": "BUTTER", "category": "dairy", "min_skill": 1, "weight": 5, "points": 12, "color": Color8(248, 224, 118, 255)},
	{"id": "onion", "label": "Zwiebel", "icon": "ZWIEB.", "category": "vegetable", "min_skill": 1, "weight": 5, "points": 12, "color": Color8(214, 180, 225, 255)},
	{"id": "dough", "label": "Teig", "icon": "TEIG", "category": "base", "min_skill": 1, "weight": 5, "points": 12, "color": Color8(218, 184, 126, 255)},
	{"id": "mushroom", "label": "Pilz", "icon": "PILZ", "category": "vegetable", "min_skill": 1, "weight": 5, "points": 12, "color": Color8(169, 139, 118, 255)},
	{"id": "salami", "label": "Salami", "icon": "SALAMI", "category": "meat", "min_skill": 1, "weight": 4, "points": 13, "color": Color8(178, 69, 75, 255)},
	{"id": "noodles", "label": "Nudeln", "icon": "NUDELN", "category": "base", "min_skill": 2, "weight": 4, "points": 14, "color": Color8(232, 204, 120, 255)},
	{"id": "basil", "label": "Basilikum", "icon": "BASIL", "category": "spice", "min_skill": 2, "weight": 3, "points": 15, "color": Color8(62, 168, 92, 255)},
	{"id": "coffee", "label": "Kaffee", "icon": "KAFFEE", "category": "drink", "min_skill": 2, "weight": 4, "points": 14, "color": Color8(129, 86, 58, 255)},
	{"id": "cake_piece", "label": "Kuchenstueck", "icon": "KUCHEN", "category": "sweet", "min_skill": 2, "weight": 3, "points": 16, "color": Color8(210, 142, 164, 255)},
	{"id": "trash", "label": "Muell", "icon": "MUELL", "category": "bad", "min_skill": 0, "weight": 4, "points": 0, "harmful": true, "color": Color8(112, 118, 126, 255)},
	{"id": "tool", "label": "Werkzeug", "icon": "TOOL", "category": "wrong", "min_skill": 0, "weight": 3, "points": 0, "color": Color8(142, 152, 166, 255)},
	{"id": "cleaner", "label": "Putzmittel", "icon": "PUTZ", "category": "bad", "min_skill": 1, "weight": 3, "points": 0, "harmful": true, "color": Color8(86, 151, 207, 255)},
	{"id": "spoiled_meat", "label": "Verdorben", "icon": "ALT", "category": "bad", "min_skill": 2, "weight": 3, "points": 0, "harmful": true, "color": Color8(112, 91, 84, 255)},
]

@export var auto_start: bool = true
@export var session_duration_sec: float = DEFAULT_SESSION_DURATION_SEC
@export var player_skill_level: int = 0
@export var rng_seed: int = 0
@export var preferred_recipe_id: String = ""

var workplace_label: String = "Restaurant"
var workplace_type: String = "Restaurant"
var running: bool = false
var elapsed_sec: float = 0.0
var score: int = 0
var combo: int = 0
var best_combo: int = 0
var mistakes: int = 0
var correct_catches: int = 0
var wrong_catches: int = 0
var missed_required_items: int = 0
var completed_recipes: int = 0
var dish_quality: float = 100.0
var current_recipe: Dictionary = {}
var remaining_ingredients: Dictionary = {}

var _rng := RandomNumberGenerator.new()
var _spawn_timer_sec: float = 0.0
var _catcher_x: float = 0.0
var _catcher_layout_initialized: bool = false
var _active_items: Array[Control] = []
var _last_spawned_product_id: String = ""

var _score_label: Label = null
var _combo_label: Label = null
var _timer_label: Label = null
var _quality_label: Label = null
var _hint_label: Label = null
var _recipe_label: Label = null
var _progress_label: Label = null
var _playfield_panel: PanelContainer = null
var _item_layer: Control = null
var _catcher: PanelContainer = null
var _catcher_label: Label = null


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
	_update_catcher(delta)
	_spawn_timer_sec -= delta
	if _spawn_timer_sec <= 0.0:
		_try_spawn_product()
		_spawn_timer_sec = _current_spawn_interval()
	_move_active_items(delta)
	_update_status_labels()


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
	return normalized == "restaurant" or normalized == "cafe" or normalized == "bakery"


func start_session(recipe_id: String = "") -> void:
	running = true
	elapsed_sec = 0.0
	score = 0
	combo = 0
	best_combo = 0
	mistakes = 0
	correct_catches = 0
	wrong_catches = 0
	missed_required_items = 0
	completed_recipes = 0
	dish_quality = 100.0
	_spawn_timer_sec = 0.2
	_catcher_layout_initialized = false
	_clear_items()
	_pick_or_set_recipe(recipe_id)
	_center_catcher()
	call_deferred("_center_catcher")
	_set_hint("Fange nur die Zutaten im Rezept. Pfeiltasten oder A/D bewegen den Korb.")
	score_changed.emit(score)
	combo_changed.emit(combo)
	quality_changed.emit(dish_quality)
	_update_recipe_ui()
	_update_status_labels()


func finish_session() -> void:
	if not running:
		return
	running = false
	_clear_items()
	_update_status_labels()
	_set_hint("Koch-Minigame beendet.")
	session_finished.emit(get_result())


func get_result() -> Dictionary:
	var success := completed_recipes > 0 and mistakes < MAX_MISTAKES and dish_quality > 0.0
	return {
		"score": score,
		"combo": combo,
		"best_combo": best_combo,
		"mistakes": mistakes,
		"correct_catches": correct_catches,
		"wrong_catches": wrong_catches,
		"missed_required_items": missed_required_items,
		"completed_recipes": completed_recipes,
		"elapsed_sec": elapsed_sec,
		"workplace_type": workplace_type,
		"workplace_label": workplace_label,
		"recipe_id": str(current_recipe.get("id", "")),
		"recipe_label": str(current_recipe.get("label", "")),
		"dish_quality": dish_quality,
		"success": success,
		"work_bonus_multiplier": get_work_bonus_multiplier(),
		"customer_satisfaction_delta": get_customer_satisfaction_delta(),
	}


func get_work_bonus_multiplier() -> float:
	if completed_recipes <= 0 or mistakes >= MAX_MISTAKES or dish_quality <= 0.0:
		return 0.0
	var combo_factor := clampf(float(best_combo) / 10.0, 0.0, 1.0)
	var quality_factor := clampf(dish_quality / 100.0, 0.0, 1.0)
	return snappedf(1.0 + quality_factor * 0.35 + combo_factor * 0.15, 0.01)


func get_customer_satisfaction_delta() -> int:
	if completed_recipes <= 0:
		return -1
	if dish_quality >= 90.0 and mistakes == 0:
		return 3
	if dish_quality >= QUALITY_BONUS_THRESHOLD:
		return 2
	if dish_quality >= 45.0:
		return 1
	return -1


func get_recipe_ids_for_workplace(type_name: String = "", skill_level: int = -1) -> PackedStringArray:
	var normalized_type := _normalize_workplace_type(workplace_type if type_name.is_empty() else type_name)
	var resolved_skill := player_skill_level if skill_level < 0 else maxi(skill_level, 0)
	var ids := PackedStringArray()
	for definition in RECIPE_DEFINITIONS:
		if int(definition.get("min_skill", 0)) > resolved_skill:
			continue
		var workplace_types: Array = definition.get("workplace_types", [])
		if workplace_types.has(normalized_type):
			ids.append(str(definition.get("id", "")))
	return ids


func get_recipe_requirement(recipe_id: String) -> Dictionary:
	var definition := _get_recipe_definition(recipe_id)
	if definition.is_empty():
		return {}
	return _copy_ingredient_counts(definition.get("ingredients", {}))


func get_product_ids_for_skill(skill_level: int = -1) -> PackedStringArray:
	var resolved_skill := player_skill_level if skill_level < 0 else maxi(skill_level, 0)
	var ids := PackedStringArray()
	for definition in PRODUCT_DEFINITIONS:
		if int(definition.get("min_skill", 0)) <= resolved_skill:
			ids.append(str(definition.get("id", "")))
	return ids


func get_recipe_label(recipe_id: String) -> String:
	var definition := _get_recipe_definition(recipe_id)
	return str(definition.get("label", "")) if not definition.is_empty() else ""


func is_product_required(product_id: String) -> bool:
	return int(remaining_ingredients.get(product_id, 0)) > 0


func debug_catch_product(product_id: String) -> Dictionary:
	var definition := _get_product_definition(product_id)
	if definition.is_empty():
		return {"correct": false, "reason": "unknown_product", "score": score}
	var correct := _handle_product_caught(definition)
	return {
		"correct": correct,
		"score": score,
		"combo": combo,
		"quality": dish_quality,
		"remaining": remaining_ingredients.duplicate(true),
		"completed_recipes": completed_recipes,
		"mistakes": mistakes,
	}


func debug_miss_product(product_id: String) -> Dictionary:
	var definition := _get_product_definition(product_id)
	if definition.is_empty():
		return {"missed": false, "reason": "unknown_product"}
	_handle_product_missed(definition)
	return {
		"missed": true,
		"missed_required_items": missed_required_items,
		"mistakes": mistakes,
		"quality": dish_quality,
	}


func debug_get_current_fall_speed() -> float:
	return _current_fall_speed()


func debug_get_current_spawn_interval() -> float:
	return _current_spawn_interval()


func debug_set_elapsed(seconds: float) -> void:
	elapsed_sec = clampf(seconds, 0.0, session_duration_sec)
	_update_status_labels()


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color8(12, 16, 22, 255)
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
	title.text = "Kitchen Rush: Ingredient Catch"
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

	var recipe_panel := PanelContainer.new()
	recipe_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	recipe_panel.add_theme_stylebox_override("panel", _make_panel_box(Color8(20, 26, 36, 255), UiThemeScript.BORDER_STRONG))
	root.add_child(recipe_panel)

	var recipe_box := VBoxContainer.new()
	recipe_box.add_theme_constant_override("separation", 4)
	recipe_panel.add_child(recipe_box)

	_recipe_label = Label.new()
	_recipe_label.add_theme_font_size_override("font_size", 19)
	_recipe_label.add_theme_color_override("font_color", UiThemeScript.TEXT_PRIMARY)
	_recipe_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	recipe_box.add_child(_recipe_label)

	_progress_label = Label.new()
	_progress_label.add_theme_color_override("font_color", UiThemeScript.TEXT_SECONDARY)
	_progress_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	recipe_box.add_child(_progress_label)

	_playfield_panel = PanelContainer.new()
	_playfield_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_playfield_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_playfield_panel.custom_minimum_size = Vector2(0, 320)
	_playfield_panel.add_theme_stylebox_override("panel", _make_panel_box(Color8(17, 22, 31, 255), UiThemeScript.BORDER_STRONG))
	root.add_child(_playfield_panel)

	_item_layer = Control.new()
	_item_layer.clip_contents = true
	_item_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_item_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_playfield_panel.add_child(_item_layer)

	_catcher = PanelContainer.new()
	_catcher.custom_minimum_size = CATCHER_SIZE
	_catcher.size = CATCHER_SIZE
	_catcher.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_catcher.add_theme_stylebox_override("panel", _make_panel_box(Color8(235, 238, 243, 255), UiThemeScript.ACCENT))
	_item_layer.add_child(_catcher)

	_catcher_label = Label.new()
	_catcher_label.text = "KORB"
	_catcher_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_catcher_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_catcher_label.add_theme_color_override("font_color", Color8(12, 16, 22, 255))
	_catcher.add_child(_catcher_label)


func _make_status_label() -> Label:
	var label := Label.new()
	label.custom_minimum_size = Vector2(118, 44)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", UiThemeScript.TEXT_PRIMARY)
	UiThemeScript.apply_pill_label(label, UiThemeScript.TEXT_PRIMARY, Color8(35, 41, 56, 255))
	return label


func _try_spawn_product() -> void:
	if _item_layer == null or _item_layer.size.x <= FALLING_ITEM_SIZE.x:
		return
	_compact_active_items()
	if _active_items.size() >= MAX_ACTIVE_ITEMS:
		return
	var definition := _pick_product_definition()
	if definition.is_empty():
		return
	var item := Button.new()
	item.custom_minimum_size = FALLING_ITEM_SIZE
	item.size = FALLING_ITEM_SIZE
	item.focus_mode = Control.FOCUS_NONE
	item.text = "%s\n%s" % [str(definition.get("icon", "")), str(definition.get("label", ""))]
	item.position = Vector2(_pick_item_x(), -FALLING_ITEM_SIZE.y)
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item.set_meta("cooking_product", definition.duplicate(true))
	_apply_product_style(item, definition)
	_item_layer.add_child(item)
	_active_items.append(item)
	_last_spawned_product_id = str(definition.get("id", ""))


func _move_active_items(delta: float) -> void:
	if _item_layer == null:
		return
	var speed := _current_fall_speed()
	var lane_height := _item_layer.size.y
	var catcher_rect := Rect2(_catcher.position, _catcher.size) if _catcher != null else Rect2()
	var caught: Array[Control] = []
	var missed: Array[Control] = []
	for item in _active_items:
		if item == null or not is_instance_valid(item):
			continue
		item.position.y += speed * delta
		var item_rect := Rect2(item.position, item.size)
		if item_rect.intersects(catcher_rect):
			caught.append(item)
		elif item.position.y > lane_height + FALLING_ITEM_SIZE.y:
			missed.append(item)
	for item in caught:
		if not running:
			break
		_catch_item(item)
	for item in missed:
		if not running:
			break
		_miss_item(item)
	_compact_active_items()


func _update_catcher(delta: float) -> void:
	if _catcher == null or _item_layer == null:
		return
	if not _catcher_layout_initialized and _item_layer.size.x > CATCHER_SIZE.x:
		_center_catcher()
	var direction := 0.0
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		direction -= 1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		direction += 1.0
	var max_x := maxf(_item_layer.size.x - CATCHER_SIZE.x, 0.0)
	_catcher_x = clampf(_catcher_x + direction * CATCHER_SPEED * delta, 0.0, max_x)
	_catcher.position = Vector2(_catcher_x, maxf(_item_layer.size.y - CATCHER_SIZE.y - 18.0, 0.0))


func _center_catcher() -> void:
	if _item_layer == null or _catcher == null:
		return
	if _item_layer.size.x <= CATCHER_SIZE.x:
		return
	_catcher_x = maxf((_item_layer.size.x - CATCHER_SIZE.x) * 0.5, 0.0)
	_catcher.position = Vector2(_catcher_x, maxf(_item_layer.size.y - CATCHER_SIZE.y - 18.0, 0.0))
	_catcher_layout_initialized = true


func _catch_item(item: Control) -> void:
	if item == null or not is_instance_valid(item):
		return
	var definition: Dictionary = item.get_meta("cooking_product", {})
	_handle_product_caught(definition)
	_remove_item(item)
	_update_recipe_ui()
	_update_status_labels()


func _miss_item(item: Control) -> void:
	if item == null or not is_instance_valid(item):
		return
	var definition: Dictionary = item.get_meta("cooking_product", {})
	_handle_product_missed(definition)
	_remove_item(item)
	_update_recipe_ui()
	_update_status_labels()


func _handle_product_caught(definition: Dictionary) -> bool:
	if definition.is_empty():
		return false
	var product_id := str(definition.get("id", ""))
	if is_product_required(product_id):
		_score_correct_catch(definition)
		remaining_ingredients[product_id] = maxi(int(remaining_ingredients.get(product_id, 0)) - 1, 0)
		_set_hint("Richtig: %s." % str(definition.get("label", "Zutat")))
		if _is_recipe_complete():
			_complete_recipe()
		return true
	_register_wrong_catch(definition)
	return false


func _handle_product_missed(definition: Dictionary) -> void:
	if definition.is_empty():
		return
	var product_id := str(definition.get("id", ""))
	if is_product_required(product_id):
		missed_required_items += 1
		_set_hint("Verpasst: %s. Kein Fehler, aber die Zeit laeuft." % str(definition.get("label", "Zutat")))


func _score_correct_catch(definition: Dictionary) -> void:
	correct_catches += 1
	combo += 1
	best_combo = maxi(best_combo, combo)
	var combo_bonus := mini(maxi(combo - 1, 0), 10)
	var quality_bonus := 4 if combo >= 10 else 2 if combo >= 5 else 1 if combo >= 3 else 0
	score += int(definition.get("points", 10)) + combo_bonus + quality_bonus
	dish_quality = clampf(dish_quality + float(quality_bonus) * 0.6, 0.0, 100.0)
	score_changed.emit(score)
	combo_changed.emit(combo)
	quality_changed.emit(dish_quality)


func _register_wrong_catch(definition: Dictionary) -> void:
	wrong_catches += 1
	mistakes += 1
	combo = 0
	var harmful := bool(definition.get("harmful", false))
	var penalty := HARMFUL_CATCH_QUALITY_PENALTY if harmful else WRONG_CATCH_QUALITY_PENALTY
	dish_quality = clampf(dish_quality - penalty, 0.0, 100.0)
	score = maxi(score - (12 if harmful else 8), 0)
	elapsed_sec = minf(elapsed_sec + WRONG_CATCH_TIME_PENALTY_SEC, session_duration_sec)
	var label := str(definition.get("label", "Produkt"))
	_set_hint("%s verunreinigt das Gericht." % label if harmful else "%s gehoert nicht ins Rezept." % label)
	score_changed.emit(score)
	combo_changed.emit(combo)
	quality_changed.emit(dish_quality)
	mistake_made.emit("harmful_product" if harmful else "wrong_product")
	if mistakes >= MAX_MISTAKES or dish_quality <= 0.0:
		_fail_recipe()


func _complete_recipe() -> void:
	completed_recipes += 1
	var remaining_time_bonus := int(ceil(maxf(session_duration_sec - elapsed_sec, 0.0) * 0.25))
	var quality_bonus := int(round(dish_quality * 0.5))
	score += 40 + remaining_time_bonus + quality_bonus
	_set_hint("%s fertig." % str(current_recipe.get("label", "Gericht")))
	recipe_completed.emit(str(current_recipe.get("id", "")), dish_quality)
	finish_session()


func _fail_recipe() -> void:
	_set_hint("Gericht misslungen: zu viele falsche Produkte.")
	finish_session()


func _pick_or_set_recipe(recipe_id: String) -> void:
	var requested := recipe_id.strip_edges()
	if requested.is_empty():
		requested = preferred_recipe_id.strip_edges()
	var definition := _get_recipe_definition(requested) if not requested.is_empty() else {}
	if definition.is_empty() or not _recipe_matches_current_workplace(definition):
		definition = _pick_recipe_definition()
	if definition.is_empty():
		definition = RECIPE_DEFINITIONS.front()
	current_recipe = definition.duplicate(true)
	remaining_ingredients = _copy_ingredient_counts(current_recipe.get("ingredients", {}))


func _pick_recipe_definition() -> Dictionary:
	var normalized_type := _normalize_workplace_type(workplace_type)
	var candidates: Array[Dictionary] = []
	var total_weight := 0
	for definition in RECIPE_DEFINITIONS:
		if int(definition.get("min_skill", 0)) > player_skill_level:
			continue
		var workplace_types: Array = definition.get("workplace_types", [])
		if not workplace_types.has(normalized_type):
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


func _pick_product_definition() -> Dictionary:
	var candidates: Array[Dictionary] = []
	var total_weight := 0
	for definition in PRODUCT_DEFINITIONS:
		if int(definition.get("min_skill", 0)) > player_skill_level:
			continue
		var product_id := str(definition.get("id", ""))
		var weight := maxi(int(definition.get("weight", 1)), 1)
		if is_product_required(product_id):
			weight += 18
		elif _recipe_contains_product(product_id):
			weight = maxi(weight - 3, 1)
		else:
			weight = max(1, int(round(float(weight) * _wrong_product_pressure())))
		if PRODUCT_DEFINITIONS.size() > 1 and product_id == _last_spawned_product_id:
			weight = maxi(int(weight / 2), 1)
		candidates.append(definition)
		total_weight += weight
	if candidates.is_empty():
		return {}
	var roll := _rng.randi_range(1, total_weight)
	var cursor := 0
	for definition in candidates:
		var product_id := str(definition.get("id", ""))
		var weight := maxi(int(definition.get("weight", 1)), 1)
		if is_product_required(product_id):
			weight += 18
		elif _recipe_contains_product(product_id):
			weight = maxi(weight - 3, 1)
		else:
			weight = max(1, int(round(float(weight) * _wrong_product_pressure())))
		if PRODUCT_DEFINITIONS.size() > 1 and product_id == _last_spawned_product_id:
			weight = maxi(int(weight / 2), 1)
		cursor += weight
		if roll <= cursor:
			return definition
	return candidates.back()


func _wrong_product_pressure() -> float:
	return clampf(0.35 + _session_progress() * 0.55 + float(player_skill_level) * 0.12, 0.25, 1.15)


func _recipe_matches_current_workplace(definition: Dictionary) -> bool:
	if int(definition.get("min_skill", 0)) > player_skill_level:
		return false
	var workplace_types: Array = definition.get("workplace_types", [])
	return workplace_types.has(_normalize_workplace_type(workplace_type))


func _get_recipe_definition(recipe_id: String) -> Dictionary:
	for definition in RECIPE_DEFINITIONS:
		if str(definition.get("id", "")) == recipe_id:
			return definition
	return {}


func _get_product_definition(product_id: String) -> Dictionary:
	for definition in PRODUCT_DEFINITIONS:
		if str(definition.get("id", "")) == product_id:
			return definition
	return {}


func _copy_ingredient_counts(raw_counts: Variant) -> Dictionary:
	var result := {}
	if raw_counts is not Dictionary:
		return result
	var counts := raw_counts as Dictionary
	for key in counts.keys():
		result[str(key)] = maxi(int(counts.get(key, 0)), 0)
	return result


func _recipe_contains_product(product_id: String) -> bool:
	var ingredients: Dictionary = current_recipe.get("ingredients", {})
	return ingredients.has(product_id)


func _is_recipe_complete() -> bool:
	for product_id in remaining_ingredients.keys():
		if int(remaining_ingredients.get(product_id, 0)) > 0:
			return false
	return true


func _pick_item_x() -> float:
	var lane_width := _item_layer.size.x if _item_layer != null else 640.0
	var min_x := 12.0
	var max_x := maxf(min_x, lane_width - FALLING_ITEM_SIZE.x - 12.0)
	return _rng.randf_range(min_x, max_x)


func _current_fall_speed() -> float:
	var progress := _session_progress()
	var skill_pressure := minf(float(player_skill_level) * 14.0, 56.0)
	return minf(BASE_FALL_SPEED + 175.0 * progress + skill_pressure, MAX_FALL_SPEED)


func _current_spawn_interval() -> float:
	var progress := _session_progress()
	var skill_pressure := minf(float(player_skill_level) * 0.05, 0.2)
	return maxf(lerpf(BASE_SPAWN_INTERVAL_SEC, MIN_SPAWN_INTERVAL_SEC, progress) - skill_pressure, MIN_SPAWN_INTERVAL_SEC)


func _session_progress() -> float:
	if session_duration_sec <= 0.0:
		return 1.0
	return clampf(elapsed_sec / session_duration_sec, 0.0, 1.0)


func _apply_product_style(item: Button, definition: Dictionary) -> void:
	if item == null:
		return
	var color: Color = definition.get("color", UiThemeScript.ACCENT)
	item.add_theme_color_override("font_color", Color8(10, 14, 22, 255))
	item.add_theme_color_override("font_hover_color", Color8(10, 14, 22, 255))
	item.add_theme_color_override("font_pressed_color", Color8(10, 14, 22, 255))
	item.add_theme_stylebox_override("normal", _make_button_box(color, color.darkened(0.22)))
	item.add_theme_stylebox_override("hover", _make_button_box(color.lightened(0.06), UiThemeScript.ACCENT))
	item.add_theme_stylebox_override("pressed", _make_button_box(color.darkened(0.08), UiThemeScript.ACCENT_DIM))


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
	box.content_margin_top = 8
	box.content_margin_right = 12
	box.content_margin_bottom = 8
	return box


func _make_button_box(bg: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.border_width_left = 1
	box.border_width_top = 1
	box.border_width_right = 1
	box.border_width_bottom = 1
	box.corner_radius_top_left = 6
	box.corner_radius_top_right = 6
	box.corner_radius_bottom_left = 6
	box.corner_radius_bottom_right = 6
	box.content_margin_left = 8
	box.content_margin_top = 5
	box.content_margin_right = 8
	box.content_margin_bottom = 5
	return box


func _remove_item(item: Control) -> void:
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


func _update_status_labels() -> void:
	if _score_label == null:
		return
	var remaining := maxi(int(ceil(session_duration_sec - elapsed_sec)), 0)
	_score_label.text = "Score\n%d" % score
	_combo_label.text = "Combo\nx%d" % combo
	_timer_label.text = "Zeit\n%02d:%02d" % [remaining / 60, remaining % 60]
	_quality_label.text = "Qualitaet\n%d%%" % int(round(dish_quality))


func _update_recipe_ui() -> void:
	if _recipe_label == null:
		return
	var recipe_name := str(current_recipe.get("label", "Rezept"))
	_recipe_label.text = "%s: %s" % [workplace_label, recipe_name]
	_progress_label.text = _format_recipe_progress()


func _format_recipe_progress() -> String:
	if current_recipe.is_empty():
		return ""
	var ingredients: Dictionary = current_recipe.get("ingredients", {})
	var parts := PackedStringArray()
	for product_id in ingredients.keys():
		var total := int(ingredients.get(product_id, 0))
		var remaining := int(remaining_ingredients.get(product_id, 0))
		var collected := maxi(total - remaining, 0)
		parts.append("%s %d/%d" % [_product_label(str(product_id)), collected, total])
	return " + ".join(parts)


func _product_label(product_id: String) -> String:
	var definition := _get_product_definition(product_id)
	return str(definition.get("label", product_id)) if not definition.is_empty() else product_id


func _set_hint(text: String) -> void:
	if _hint_label != null:
		_hint_label.text = text


func _resolve_workplace_type_name(workplace) -> String:
	if workplace == null:
		return "Restaurant"
	if workplace.has_method("get_building_type_name"):
		return str(workplace.call("get_building_type_name"))
	if workplace is Restaurant:
		return "Restaurant"
	if workplace is Cafe:
		return "Cafe"
	return str(workplace.get_class())


func _apply_workplace_labels(type_name: String, label: String) -> void:
	workplace_type = type_name
	workplace_label = label
	if _hint_label != null:
		_set_hint("%s: Zutaten fangen." % workplace_label)


func _normalize_workplace_type(type_name: String) -> String:
	var normalized := type_name.strip_edges().to_lower()
	match normalized:
		"cafe":
			return "cafe"
		"restaurant":
			return "restaurant"
		"bakery", "baeckerei":
			return "bakery"
		_:
			return normalized
