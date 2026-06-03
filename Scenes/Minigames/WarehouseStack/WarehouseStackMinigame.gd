extends Control
class_name WarehouseStackMinigame

const UiThemeScript = preload("res://Simulation/UI/UiTheme.gd")

signal score_changed(score: int)
signal combo_changed(combo: int)
signal mistake_made(reason: String)
signal package_placed(package_id: String, cells: Array[Vector2i])
signal session_finished(result: Dictionary)

const GRID_COLUMNS := 8
const GRID_ROWS := 6
const COLD_ZONE_MIN_X := 6
const DEFAULT_SESSION_DURATION_SEC := 120.0
const MAX_ROTATIONS := 4
const HEAVY_WEIGHT_RANK := 3
const QUALITY_BONUS_THRESHOLD := 0.72

const PACKAGE_DEFINITIONS := [
	{
		"id": "long_crate",
		"label": "Lange Kiste",
		"icon": "LANG",
		"cells": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)],
		"weight_rank": 2,
		"min_skill": 0,
		"weight": 8,
		"points": 22,
		"color": Color8(205, 143, 82, 255),
	},
	{
		"id": "small_box",
		"label": "Kleine Box",
		"icon": "BOX",
		"cells": [Vector2i(0, 0)],
		"weight_rank": 1,
		"min_skill": 0,
		"weight": 9,
		"points": 10,
		"color": Color8(125, 184, 129, 255),
	},
	{
		"id": "l_package",
		"label": "L-Form Paket",
		"icon": "L",
		"cells": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)],
		"weight_rank": 2,
		"min_skill": 0,
		"weight": 7,
		"points": 24,
		"color": Color8(159, 127, 205, 255),
	},
	{
		"id": "fragile_goods",
		"label": "Zerbrechliche Ware",
		"icon": "GLAS",
		"cells": [Vector2i(0, 0), Vector2i(1, 0)],
		"weight_rank": 1,
		"fragile": true,
		"min_skill": 0,
		"weight": 6,
		"points": 24,
		"color": Color8(235, 211, 125, 255),
	},
	{
		"id": "cold_goods",
		"label": "Kuehlware",
		"icon": "KALT",
		"cells": [Vector2i(0, 0), Vector2i(0, 1)],
		"weight_rank": 2,
		"requires_cold": true,
		"min_skill": 0,
		"weight": 6,
		"points": 26,
		"color": Color8(88, 176, 226, 255),
	},
	{
		"id": "heavy_crate",
		"label": "Schwere Kiste",
		"icon": "SCHWER",
		"cells": [Vector2i(0, 0)],
		"weight_rank": 3,
		"min_skill": 1,
		"weight": 5,
		"points": 18,
		"color": Color8(126, 136, 150, 255),
	},
	{
		"id": "wide_pallet",
		"label": "Breite Palette",
		"icon": "PALETTE",
		"cells": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)],
		"weight_rank": 3,
		"min_skill": 2,
		"weight": 4,
		"points": 34,
		"color": Color8(168, 116, 85, 255),
	},
	{
		"id": "frozen_pallet",
		"label": "Tiefkuehlpalette",
		"icon": "FROST",
		"cells": [Vector2i(0, 0), Vector2i(1, 0)],
		"weight_rank": 3,
		"requires_cold": true,
		"min_skill": 2,
		"weight": 4,
		"points": 36,
		"color": Color8(82, 157, 222, 255),
	},
]

@export var auto_start: bool = true
@export var session_duration_sec: float = DEFAULT_SESSION_DURATION_SEC
@export var player_skill_level: int = 0
@export var rng_seed: int = 0

var workplace_label: String = "Fabrik"
var workplace_type: String = "Factory"
var running: bool = false
var elapsed_sec: float = 0.0
var score: int = 0
var combo: int = 0
var best_combo: int = 0
var mistakes: int = 0
var placed_packages: int = 0
var rejected_packages: int = 0
var used_cells: int = 0

var _rng := RandomNumberGenerator.new()
var _grid: Dictionary = {}
var _current_package: Dictionary = {}
var _rotation: int = 0
var _last_package_id: String = ""
var _cell_buttons: Dictionary = {}

var _score_label: Label = null
var _combo_label: Label = null
var _timer_label: Label = null
var _density_label: Label = null
var _hint_label: Label = null
var _package_label: Label = null
var _preview_label: Label = null
var _grid_container: GridContainer = null
var _rotate_button: Button = null
var _skip_button: Button = null


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
	_update_status_labels()


func _unhandled_input(event: InputEvent) -> void:
	if not running:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_R:
				rotate_current_package()
				get_viewport().set_input_as_handled()
			KEY_SPACE:
				skip_current_package()
				get_viewport().set_input_as_handled()


func configure_for_workplace(workplace, skill_level: int = 0) -> bool:
	player_skill_level = maxi(skill_level, 0)
	if workplace == null:
		_apply_workplace_labels("Factory", "Fabrik")
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
	return normalized == "factory" or normalized == "warehouse"


func start_session() -> void:
	running = true
	elapsed_sec = 0.0
	score = 0
	combo = 0
	best_combo = 0
	mistakes = 0
	placed_packages = 0
	rejected_packages = 0
	used_cells = 0
	_rotation = 0
	_grid.clear()
	_current_package.clear()
	_last_package_id = ""
	_pick_next_package()
	_set_hint("Paket platzieren. R rotiert, Leertaste verwirft.")
	score_changed.emit(score)
	combo_changed.emit(combo)
	_refresh_grid_ui()
	_update_package_ui()
	_update_status_labels()


func finish_session() -> void:
	if not running:
		return
	running = false
	_update_status_labels()
	_set_hint("Warehouse Stack beendet.")
	session_finished.emit(get_result())


func get_result() -> Dictionary:
	var quality := get_packing_quality()
	return {
		"score": score,
		"combo": combo,
		"best_combo": best_combo,
		"mistakes": mistakes,
		"placed_packages": placed_packages,
		"rejected_packages": rejected_packages,
		"used_cells": used_cells,
		"storage_efficiency": get_storage_efficiency(),
		"packing_quality": quality,
		"work_bonus_multiplier": get_work_bonus_multiplier(),
		"production_output_multiplier": get_production_output_multiplier(),
		"elapsed_sec": elapsed_sec,
		"workplace_type": workplace_type,
		"workplace_label": workplace_label,
	}


func get_storage_efficiency() -> float:
	return clampf(float(used_cells) / float(GRID_COLUMNS * GRID_ROWS), 0.0, 1.0)


func get_packing_quality() -> float:
	var attempts := placed_packages + rejected_packages
	if attempts <= 0:
		return 0.0
	var accuracy := float(placed_packages) / float(attempts)
	var density := get_storage_efficiency()
	var combo_factor := clampf(float(best_combo) / 8.0, 0.0, 1.0)
	return clampf(density * 0.55 + accuracy * 0.30 + combo_factor * 0.15, 0.0, 1.0)


func get_work_bonus_multiplier() -> float:
	var quality := get_packing_quality()
	if placed_packages <= 0 or quality < QUALITY_BONUS_THRESHOLD * 0.45:
		return 0.0
	return snappedf(1.0 + quality * 0.30 + get_storage_efficiency() * 0.20, 0.01)


func get_production_output_multiplier() -> float:
	if get_packing_quality() < QUALITY_BONUS_THRESHOLD:
		return 1.0
	return snappedf(1.0 + get_packing_quality() * 0.18, 0.01)


func get_package_ids_for_skill(skill_level: int = -1) -> PackedStringArray:
	var resolved_skill := player_skill_level if skill_level < 0 else maxi(skill_level, 0)
	var ids := PackedStringArray()
	for definition in PACKAGE_DEFINITIONS:
		if int(definition.get("min_skill", 0)) <= resolved_skill:
			ids.append(str(definition.get("id", "")))
	return ids


func get_package_cells(package_id: String, rotation: int = 0) -> Array[Vector2i]:
	var definition := _get_package_definition(package_id)
	if definition.is_empty():
		return []
	return _rotated_cells(definition, rotation)


func package_requires_cold(package_id: String) -> bool:
	var definition := _get_package_definition(package_id)
	return bool(definition.get("requires_cold", false)) if not definition.is_empty() else false


func is_cold_cell(cell: Vector2i) -> bool:
	return cell.x >= COLD_ZONE_MIN_X and cell.x < GRID_COLUMNS and cell.y >= 0 and cell.y < GRID_ROWS


func can_place_package(package_id: String, origin: Vector2i, rotation: int = 0) -> bool:
	var definition := _get_package_definition(package_id)
	if definition.is_empty():
		return false
	return bool(_validate_placement(definition, origin, rotation).get("ok", false))


func debug_place_package(package_id: String, origin: Vector2i, rotation: int = 0) -> Dictionary:
	var definition := _get_package_definition(package_id)
	if definition.is_empty():
		return {"placed": false, "reason": "unknown_package", "score": score}
	return _try_place_definition(definition, origin, rotation)


func debug_get_grid_snapshot() -> Dictionary:
	return _grid.duplicate(true)


func debug_set_elapsed(seconds: float) -> void:
	elapsed_sec = clampf(seconds, 0.0, session_duration_sec)
	_update_status_labels()


func rotate_current_package() -> void:
	if _current_package.is_empty():
		return
	_rotation = (_rotation + 1) % MAX_ROTATIONS
	_update_package_ui()


func skip_current_package() -> void:
	if not running or _current_package.is_empty():
		return
	rejected_packages += 1
	combo = 0
	score = maxi(score - 3, 0)
	score_changed.emit(score)
	combo_changed.emit(combo)
	mistake_made.emit("package_skipped")
	_pick_next_package()
	_set_hint("Paket verworfen.")
	_update_package_ui()
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
	title.text = "Warehouse Stack"
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
	_density_label = _make_status_label()
	header.add_child(_score_label)
	header.add_child(_combo_label)
	header.add_child(_timer_label)
	header.add_child(_density_label)

	var body := HBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", UiThemeScript.SEPARATION_NORMAL)
	root.add_child(body)

	var grid_panel := PanelContainer.new()
	grid_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid_panel.add_theme_stylebox_override("panel", _make_panel_box(Color8(18, 24, 34, 255), UiThemeScript.BORDER_STRONG))
	body.add_child(grid_panel)

	_grid_container = GridContainer.new()
	_grid_container.columns = GRID_COLUMNS
	_grid_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_grid_container.add_theme_constant_override("h_separation", 4)
	_grid_container.add_theme_constant_override("v_separation", 4)
	grid_panel.add_child(_grid_container)
	_build_grid_buttons()

	var side_panel := PanelContainer.new()
	side_panel.custom_minimum_size = Vector2(260, 0)
	side_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side_panel.add_theme_stylebox_override("panel", _make_panel_box(Color8(20, 26, 36, 255), UiThemeScript.BORDER_STRONG))
	body.add_child(side_panel)

	var side_box := VBoxContainer.new()
	side_box.add_theme_constant_override("separation", UiThemeScript.SEPARATION_NORMAL)
	side_panel.add_child(side_box)

	_package_label = Label.new()
	_package_label.add_theme_font_size_override("font_size", 18)
	_package_label.add_theme_color_override("font_color", UiThemeScript.TEXT_PRIMARY)
	_package_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side_box.add_child(_package_label)

	_preview_label = Label.new()
	_preview_label.custom_minimum_size = Vector2(0, 150)
	_preview_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preview_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_preview_label.add_theme_font_size_override("font_size", 21)
	_preview_label.add_theme_color_override("font_color", UiThemeScript.TEXT_ON_ACCENT)
	_preview_label.add_theme_stylebox_override("normal", _make_panel_box(Color8(229, 234, 241, 255), UiThemeScript.ACCENT))
	side_box.add_child(_preview_label)

	_rotate_button = Button.new()
	_rotate_button.text = "Rotieren"
	_rotate_button.focus_mode = Control.FOCUS_NONE
	_rotate_button.pressed.connect(rotate_current_package)
	side_box.add_child(_rotate_button)

	_skip_button = Button.new()
	_skip_button.text = "Verwerfen"
	_skip_button.focus_mode = Control.FOCUS_NONE
	_skip_button.pressed.connect(skip_current_package)
	side_box.add_child(_skip_button)


func _build_grid_buttons() -> void:
	if _grid_container == null:
		return
	_cell_buttons.clear()
	for y in range(GRID_ROWS - 1, -1, -1):
		for x in range(GRID_COLUMNS):
			var cell := Vector2i(x, y)
			var button := Button.new()
			button.custom_minimum_size = Vector2(64, 64)
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.size_flags_vertical = Control.SIZE_EXPAND_FILL
			button.focus_mode = Control.FOCUS_NONE
			button.pressed.connect(_on_cell_pressed.bind(cell))
			_grid_container.add_child(button)
			_cell_buttons[_cell_key(cell)] = button


func _make_status_label() -> Label:
	var label := Label.new()
	label.custom_minimum_size = Vector2(118, 44)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", UiThemeScript.TEXT_PRIMARY)
	UiThemeScript.apply_pill_label(label, UiThemeScript.TEXT_PRIMARY, Color8(35, 41, 56, 255))
	return label


func _on_cell_pressed(cell: Vector2i) -> void:
	if not running or _current_package.is_empty():
		return
	var result := _try_place_definition(_current_package, cell, _rotation)
	if bool(result.get("placed", false)):
		_pick_next_package()
	_update_package_ui()
	_update_status_labels()


func _try_place_definition(definition: Dictionary, origin: Vector2i, rotation: int = 0) -> Dictionary:
	var validation := _validate_placement(definition, origin, rotation)
	if not bool(validation.get("ok", false)):
		_register_mistake(str(validation.get("reason", "invalid_placement")))
		_set_hint(_format_failure_hint(definition, str(validation.get("reason", "invalid_placement"))))
		_update_status_labels()
		return {
			"placed": false,
			"reason": str(validation.get("reason", "invalid_placement")),
			"score": score,
			"combo": combo,
		}

	var cells: Array[Vector2i] = validation.get("cells", [])
	var package_id := str(definition.get("id", ""))
	var color: Color = definition.get("color", UiThemeScript.ACCENT)
	for cell in cells:
		_grid[_cell_key(cell)] = {
			"package_id": package_id,
			"label": str(definition.get("label", "")),
			"icon": str(definition.get("icon", "")),
			"weight_rank": int(definition.get("weight_rank", 1)),
			"fragile": bool(definition.get("fragile", false)),
			"requires_cold": bool(definition.get("requires_cold", false)),
			"color": color,
		}

	placed_packages += 1
	used_cells += cells.size()
	combo += 1
	best_combo = maxi(best_combo, combo)
	var combo_bonus := mini(maxi(combo - 1, 0), 10)
	score += int(definition.get("points", 10)) + cells.size() * 5 + combo_bonus + _placement_bonus(definition, cells)
	score_changed.emit(score)
	combo_changed.emit(combo)
	package_placed.emit(package_id, cells)
	_last_package_id = package_id
	_set_hint("%s platziert." % str(definition.get("label", "Paket")))
	_refresh_grid_ui()
	return {
		"placed": true,
		"reason": "ok",
		"cells": cells,
		"score": score,
		"combo": combo,
		"storage_efficiency": get_storage_efficiency(),
		"packing_quality": get_packing_quality(),
	}


func _validate_placement(definition: Dictionary, origin: Vector2i, rotation: int = 0) -> Dictionary:
	var cells := _world_cells(definition, origin, rotation)
	if cells.is_empty():
		return {"ok": false, "reason": "empty_shape"}

	for cell in cells:
		if cell.x < 0 or cell.x >= GRID_COLUMNS or cell.y < 0 or cell.y >= GRID_ROWS:
			return {"ok": false, "reason": "out_of_bounds", "cells": cells}
		if _grid.has(_cell_key(cell)):
			return {"ok": false, "reason": "occupied", "cells": cells}
		if bool(definition.get("requires_cold", false)) and not is_cold_cell(cell):
			return {"ok": false, "reason": "cold_zone_required", "cells": cells}

	if _would_put_heavy_over_fragile(definition, cells):
		return {"ok": false, "reason": "fragile_under_heavy", "cells": cells}
	if _would_put_fragile_under_heavy(definition, cells):
		return {"ok": false, "reason": "fragile_under_heavy", "cells": cells}

	var support_result := _validate_support(definition, cells)
	if not bool(support_result.get("ok", false)):
		return {"ok": false, "reason": str(support_result.get("reason", "unsupported")), "cells": cells}

	return {"ok": true, "reason": "ok", "cells": cells}


func _validate_support(definition: Dictionary, cells: Array[Vector2i]) -> Dictionary:
	var shape_lookup := {}
	for cell in cells:
		shape_lookup[_cell_key(cell)] = true

	var package_weight := int(definition.get("weight_rank", 1))
	for cell in cells:
		var below := Vector2i(cell.x, cell.y - 1)
		if shape_lookup.has(_cell_key(below)):
			continue
		if cell.y == 0:
			continue
		var support_data: Dictionary = _grid.get(_cell_key(below), {})
		if support_data.is_empty():
			return {"ok": false, "reason": "unsupported"}
		var support_weight := int(support_data.get("weight_rank", 1))
		if support_weight < package_weight:
			return {"ok": false, "reason": "heavy_on_light"}
	return {"ok": true, "reason": "ok"}


func _would_put_heavy_over_fragile(definition: Dictionary, cells: Array[Vector2i]) -> bool:
	if int(definition.get("weight_rank", 1)) < HEAVY_WEIGHT_RANK:
		return false
	for cell in cells:
		for y in range(cell.y - 1, -1, -1):
			var data: Dictionary = _grid.get(_cell_key(Vector2i(cell.x, y)), {})
			if bool(data.get("fragile", false)):
				return true
	return false


func _would_put_fragile_under_heavy(definition: Dictionary, cells: Array[Vector2i]) -> bool:
	if not bool(definition.get("fragile", false)):
		return false
	for cell in cells:
		for y in range(cell.y + 1, GRID_ROWS):
			var data: Dictionary = _grid.get(_cell_key(Vector2i(cell.x, y)), {})
			if int(data.get("weight_rank", 1)) >= HEAVY_WEIGHT_RANK:
				return true
	return false


func _placement_bonus(definition: Dictionary, cells: Array[Vector2i]) -> int:
	var bonus := 0
	var is_heavy := int(definition.get("weight_rank", 1)) >= HEAVY_WEIGHT_RANK
	if is_heavy:
		var lowest_y := GRID_ROWS
		for cell in cells:
			lowest_y = mini(lowest_y, cell.y)
		if lowest_y <= 1:
			bonus += 8
	if bool(definition.get("requires_cold", false)):
		bonus += 10
	if bool(definition.get("fragile", false)):
		bonus += 6
	return bonus


func _register_mistake(reason: String) -> void:
	mistakes += 1
	rejected_packages += 1
	combo = 0
	score = maxi(score - 6, 0)
	score_changed.emit(score)
	combo_changed.emit(combo)
	mistake_made.emit(reason)


func _pick_next_package() -> void:
	var candidates: Array[Dictionary] = []
	var total_weight := 0
	for definition in PACKAGE_DEFINITIONS:
		if int(definition.get("min_skill", 0)) > player_skill_level:
			continue
		var package_id := str(definition.get("id", ""))
		var weight := maxi(int(definition.get("weight", 1)), 1)
		if PACKAGE_DEFINITIONS.size() > 1 and package_id == _last_package_id:
			weight = maxi(int(weight / 2), 1)
		candidates.append(definition)
		total_weight += weight
	if candidates.is_empty():
		_current_package.clear()
		return
	var roll := _rng.randi_range(1, total_weight)
	var cursor := 0
	for definition in candidates:
		var package_id := str(definition.get("id", ""))
		var weight := maxi(int(definition.get("weight", 1)), 1)
		if PACKAGE_DEFINITIONS.size() > 1 and package_id == _last_package_id:
			weight = maxi(int(weight / 2), 1)
		cursor += weight
		if roll <= cursor:
			_current_package = definition.duplicate(true)
			_rotation = 0
			return
	_current_package = candidates.back().duplicate(true)
	_rotation = 0


func _get_package_definition(package_id: String) -> Dictionary:
	for definition in PACKAGE_DEFINITIONS:
		if str(definition.get("id", "")) == package_id:
			return definition
	return {}


func _world_cells(definition: Dictionary, origin: Vector2i, rotation: int = 0) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell in _rotated_cells(definition, rotation):
		result.append(origin + cell)
	return result


func _rotated_cells(definition: Dictionary, rotation: int = 0) -> Array[Vector2i]:
	var raw_cells: Array = definition.get("cells", [])
	var cells: Array[Vector2i] = []
	for raw_cell in raw_cells:
		if raw_cell is Vector2i:
			cells.append(raw_cell)
	var steps := posmod(rotation, MAX_ROTATIONS)
	for _i in range(steps):
		cells = _rotate_cells_clockwise(cells)
	return _normalize_cells(cells)


func _rotate_cells_clockwise(cells: Array[Vector2i]) -> Array[Vector2i]:
	var rotated: Array[Vector2i] = []
	for cell in cells:
		rotated.append(Vector2i(cell.y, -cell.x))
	return rotated


func _normalize_cells(cells: Array[Vector2i]) -> Array[Vector2i]:
	if cells.is_empty():
		return []
	var min_x := cells[0].x
	var min_y := cells[0].y
	for cell in cells:
		min_x = mini(min_x, cell.x)
		min_y = mini(min_y, cell.y)
	var normalized: Array[Vector2i] = []
	for cell in cells:
		normalized.append(Vector2i(cell.x - min_x, cell.y - min_y))
	normalized.sort_custom(_sort_cells)
	return normalized


func _sort_cells(a: Vector2i, b: Vector2i) -> bool:
	if a.y == b.y:
		return a.x < b.x
	return a.y < b.y


func _refresh_grid_ui() -> void:
	for y in range(GRID_ROWS):
		for x in range(GRID_COLUMNS):
			var cell := Vector2i(x, y)
			var button := _cell_buttons.get(_cell_key(cell), null) as Button
			if button == null:
				continue
			var data: Dictionary = _grid.get(_cell_key(cell), {})
			if data.is_empty():
				button.text = "KUEHL" if is_cold_cell(cell) else ""
				button.add_theme_color_override("font_color", UiThemeScript.TEXT_MUTED)
				var empty_bg := Color8(24, 36, 48, 255) if is_cold_cell(cell) else Color8(29, 34, 45, 255)
				var empty_border := Color8(77, 151, 190, 255) if is_cold_cell(cell) else UiThemeScript.BORDER
				button.add_theme_stylebox_override("normal", _make_button_box(empty_bg, empty_border, false))
				button.add_theme_stylebox_override("hover", _make_button_box(empty_bg.lightened(0.08), UiThemeScript.ACCENT, true))
				button.add_theme_stylebox_override("pressed", _make_button_box(empty_bg.darkened(0.08), UiThemeScript.ACCENT_DIM, true))
			else:
				var color: Color = data.get("color", UiThemeScript.ACCENT)
				button.text = str(data.get("icon", "BOX"))
				button.add_theme_color_override("font_color", Color8(10, 14, 22, 255))
				button.add_theme_color_override("font_hover_color", Color8(10, 14, 22, 255))
				button.add_theme_color_override("font_pressed_color", Color8(10, 14, 22, 255))
				button.add_theme_stylebox_override("normal", _make_button_box(color, color.darkened(0.22), false))
				button.add_theme_stylebox_override("hover", _make_button_box(color.lightened(0.06), UiThemeScript.ACCENT, true))
				button.add_theme_stylebox_override("pressed", _make_button_box(color.darkened(0.08), UiThemeScript.ACCENT_DIM, true))


func _update_package_ui() -> void:
	if _package_label == null:
		return
	if _current_package.is_empty():
		_package_label.text = "Kein Paket"
		_preview_label.text = ""
		return
	var flags := PackedStringArray()
	var weight_rank := int(_current_package.get("weight_rank", 1))
	if weight_rank >= HEAVY_WEIGHT_RANK:
		flags.append("schwer")
	elif weight_rank == 2:
		flags.append("mittel")
	else:
		flags.append("leicht")
	if bool(_current_package.get("fragile", false)):
		flags.append("zerbrechlich")
	if bool(_current_package.get("requires_cold", false)):
		flags.append("kuehl")
	_package_label.text = "%s\n%s" % [
		str(_current_package.get("label", "Paket")),
		" / ".join(flags),
	]
	_preview_label.text = _format_shape_preview(_rotated_cells(_current_package, _rotation))


func _format_shape_preview(cells: Array[Vector2i]) -> String:
	if cells.is_empty():
		return ""
	var width := 0
	var height := 0
	var lookup := {}
	for cell in cells:
		width = maxi(width, cell.x + 1)
		height = maxi(height, cell.y + 1)
		lookup[_cell_key(cell)] = true
	var lines := PackedStringArray()
	for y in range(height - 1, -1, -1):
		var parts := PackedStringArray()
		for x in range(width):
			parts.append("XX" if lookup.has(_cell_key(Vector2i(x, y))) else "..")
		lines.append(" ".join(parts))
	return "\n".join(lines)


func _update_status_labels() -> void:
	if _score_label == null:
		return
	var remaining := maxi(int(ceil(session_duration_sec - elapsed_sec)), 0)
	_score_label.text = "Score\n%d" % score
	_combo_label.text = "Combo\nx%d" % combo
	_timer_label.text = "Zeit\n%02d:%02d" % [remaining / 60, remaining % 60]
	_density_label.text = "Dichte\n%d%%" % int(round(get_storage_efficiency() * 100.0))


func _set_hint(text: String) -> void:
	if _hint_label != null:
		_hint_label.text = text


func _format_failure_hint(definition: Dictionary, reason: String) -> String:
	var label := str(definition.get("label", "Paket"))
	match reason:
		"out_of_bounds":
			return "%s passt dort nicht ins Feld." % label
		"occupied":
			return "%s ueberlappt bereits gelagerte Ware." % label
		"unsupported":
			return "%s braucht unten Halt." % label
		"heavy_on_light":
			return "%s ist zu schwer fuer die Ware darunter." % label
		"fragile_under_heavy":
			return "Zerbrechliche Ware darf nicht unter schweren Kisten liegen."
		"cold_zone_required":
			return "%s gehoert in den Kuehlbereich." % label
		_:
			return "%s kann dort nicht platziert werden." % label


func _resolve_workplace_type_name(workplace) -> String:
	if workplace == null:
		return "Factory"
	if workplace.has_method("get_building_type_name"):
		return str(workplace.call("get_building_type_name"))
	if workplace is Factory:
		return "Factory"
	return str(workplace.get_class())


func _apply_workplace_labels(type_name: String, label: String) -> void:
	workplace_type = type_name
	workplace_label = label
	if _hint_label != null:
		_set_hint("%s: Lager packen." % workplace_label)


func _normalize_workplace_type(type_name: String) -> String:
	var normalized := type_name.strip_edges().to_lower()
	match normalized:
		"factory", "fabrik":
			return "factory"
		"warehouse", "lager", "storage", "logistics", "logistik":
			return "warehouse"
		_:
			return normalized


func _cell_key(cell: Vector2i) -> String:
	return "%d:%d" % [cell.x, cell.y]


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
	box.content_margin_left = 8
	box.content_margin_top = 5
	box.content_margin_right = 8
	box.content_margin_bottom = 5
	return box
