extends Control
class_name FarmWorkScene

const UiThemeScript = preload("res://Simulation/UI/UiTheme.gd")

signal session_finished(result: Dictionary)
signal score_changed(score: int)
signal mistake_made(reason: String)

const ACTION_PLANT := "plant"
const ACTION_WATER := "water"
const ACTION_WEED := "weed"
const ACTION_HARVEST := "harvest"
const ACTION_DELIVER := "deliver"

const PLOT_COUNT := 4
const DEFAULT_SESSION_DURATION_SEC := 96.0
const DEFAULT_WORK_MINUTES := 75
const BASKET_CAPACITY_CRATES := 2
const FALLBACK_UNITS_PER_CRATE := 8
const GROWTH_MINUTES_PER_MAINTENANCE_TASK := 90
const QUALITY_BONUS_THRESHOLD := 0.62

const ACTION_DEFINITIONS := [
	{
		"id": ACTION_PLANT,
		"key": "Q",
		"label": "Pflanzen",
		"hint": "leere Parzelle",
		"color": Color8(102, 187, 106, 255),
	},
	{
		"id": ACTION_WATER,
		"key": "W",
		"label": "Giessen",
		"hint": "trockene Pflanze",
		"color": Color8(79, 195, 247, 255),
	},
	{
		"id": ACTION_WEED,
		"key": "E",
		"label": "Unkraut",
		"hint": "entfernen",
		"color": Color8(255, 202, 40, 255),
	},
	{
		"id": ACTION_HARVEST,
		"key": "R",
		"label": "Ernten",
		"hint": "saubere reife Parzelle",
		"color": Color8(255, 167, 38, 255),
	},
	{
		"id": ACTION_DELIVER,
		"key": "T",
		"label": "Liefern",
		"hint": "Korb zur Kiste",
		"color": Color8(171, 126, 235, 255),
	},
]

@export var auto_start: bool = true
@export var session_duration_sec: float = DEFAULT_SESSION_DURATION_SEC
@export var player_skill_level: int = 0

var farm_label: String = "Farm"
var product_commodity: String = "food"
var product_display_name: String = "food"
var crop_ready: bool = false
var available_storage: int = 0
var suggested_harvest_units: int = 0
var running: bool = false
var elapsed_sec: float = 0.0
var score: int = 0
var mistakes: int = 0
var completed_tasks: int = 0
var delivered_crates: int = 0
var harvested_amount: int = 0
var quality_score: float = 1.0
var work_minutes: int = DEFAULT_WORK_MINUTES

var _plots: Array[Dictionary] = []
var _selected_plot_index: int = 0
var _basket_crates: int = 0
var _basket_units: int = 0
var _units_per_crate: int = FALLBACK_UNITS_PER_CRATE
var _maintenance_tasks_done: int = 0

var _score_label: Label = null
var _timer_label: Label = null
var _quality_label: Label = null
var _basket_label: Label = null
var _hint_label: Label = null
var _plot_buttons: Array[Button] = []
var _action_buttons: Dictionary = {}
var _plot_meshes: Array[MeshInstance3D] = []
var _plot_materials: Array[StandardMaterial3D] = []
var _preview_viewport: SubViewport = null


func _ready() -> void:
	theme = UiThemeScript.get_or_build()
	process_mode = Node.PROCESS_MODE_ALWAYS
	custom_minimum_size = Vector2(1024, 640)
	_build_ui()
	_build_farm_preview()
	_reset_session_state()
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
	_update_status_labels()


func _unhandled_input(event: InputEvent) -> void:
	if not running:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				select_plot(1)
				get_viewport().set_input_as_handled()
			KEY_2:
				select_plot(2)
				get_viewport().set_input_as_handled()
			KEY_3:
				select_plot(3)
				get_viewport().set_input_as_handled()
			KEY_4:
				select_plot(4)
				get_viewport().set_input_as_handled()
			KEY_Q:
				_perform_selected_action(ACTION_PLANT)
				get_viewport().set_input_as_handled()
			KEY_W:
				_perform_selected_action(ACTION_WATER)
				get_viewport().set_input_as_handled()
			KEY_E:
				_perform_selected_action(ACTION_WEED)
				get_viewport().set_input_as_handled()
			KEY_R:
				_perform_selected_action(ACTION_HARVEST)
				get_viewport().set_input_as_handled()
			KEY_T:
				_perform_selected_action(ACTION_DELIVER)
				get_viewport().set_input_as_handled()
			KEY_ESCAPE:
				finish_session()
				get_viewport().set_input_as_handled()


func configure_for_farm(farm, skill_level: int = 0) -> bool:
	player_skill_level = maxi(skill_level, 0)
	if farm == null:
		_apply_context({
			"farm_label": "Farm",
			"product_commodity": "food",
			"product_display_name": "food",
			"crop_ready": true,
			"available_storage": 48,
			"suggested_harvest_units": 32,
		})
		return true
	if farm is not Farm:
		return false
	if farm.has_method("get_player_work_context"):
		_apply_context(farm.call("get_player_work_context"))
	else:
		_apply_context({
			"farm_label": farm.get_display_name() if farm.has_method("get_display_name") else str(farm.name),
			"product_commodity": "food",
			"product_display_name": "food",
			"crop_ready": false,
			"available_storage": 0,
			"suggested_harvest_units": 0,
		})
	return true


func start_session() -> void:
	_reset_session_state()
	running = true
	_set_hint("%s: Parzellen pflegen, reife Ernte in den Korb legen und zur Kiste bringen." % farm_label)
	_update_all_ui()


func finish_session() -> void:
	if not running:
		return
	running = false
	_update_all_ui()
	session_finished.emit(get_result())


func get_result() -> Dictionary:
	return {
		"job_type": "farm",
		"farm_label": farm_label,
		"product_commodity": product_commodity,
		"product_display_name": product_display_name,
		"score": score,
		"mistakes": mistakes,
		"completed_tasks": completed_tasks,
		"delivered_crates": delivered_crates,
		"harvested_amount": harvested_amount,
		"quality_score": get_quality_score(),
		"work_minutes": _calculate_work_minutes(),
		"time_used_sec": elapsed_sec,
		"growth_minutes_added": get_growth_minutes_added(),
		"success": get_quality_score() >= QUALITY_BONUS_THRESHOLD,
		"customer_satisfaction": get_quality_score() * 100.0,
		"earned_money": 0,
		"reputation_gain": get_reputation_gain(),
	}


func get_quality_score() -> float:
	var task_factor := clampf(float(completed_tasks) / 10.0, 0.0, 1.0)
	var harvest_factor := 0.0
	if suggested_harvest_units > 0:
		harvest_factor = clampf(float(harvested_amount) / float(suggested_harvest_units), 0.0, 1.0)
	elif not crop_ready:
		harvest_factor = task_factor
	var mistake_penalty := clampf(float(mistakes) * 0.08, 0.0, 0.45)
	return clampf(task_factor * 0.45 + harvest_factor * 0.45 + quality_score * 0.10 - mistake_penalty, 0.0, 1.0)


func get_growth_minutes_added() -> int:
	if crop_ready:
		return 0
	return _maintenance_tasks_done * GROWTH_MINUTES_PER_MAINTENANCE_TASK


func get_reputation_gain() -> int:
	var quality := get_quality_score()
	if quality >= 0.88 and mistakes == 0:
		return 3
	if quality >= QUALITY_BONUS_THRESHOLD:
		return 2
	if quality >= 0.42:
		return 1
	return 0


func get_action_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for definition in ACTION_DEFINITIONS:
		ids.append(str(definition.get("id", "")))
	return ids


func get_plot_snapshot(plot_number: int) -> Dictionary:
	_ensure_plots()
	var index := plot_number - 1
	if index < 0 or index >= _plots.size():
		return {}
	var plot := _plots[index].duplicate(true)
	plot["plot_number"] = plot_number
	plot["label"] = "Feld %d" % plot_number
	plot["required_action"] = get_recommended_action_for_plot(plot_number)
	plot["state_label"] = _plot_state_label(plot)
	return plot


func get_recommended_action_for_plot(plot_number: int) -> String:
	_ensure_plots()
	var index := plot_number - 1
	if index < 0 or index >= _plots.size():
		return ""
	return _recommended_action_for_plot(_plots[index])


func select_plot(plot_number: int) -> bool:
	var index := plot_number - 1
	if index < 0 or index >= PLOT_COUNT:
		return false
	_selected_plot_index = index
	_update_all_ui()
	return true


func debug_perform_action(plot_number: int, action_id: String) -> Dictionary:
	if action_id == ACTION_DELIVER:
		return _perform_delivery_action()
	return _perform_plot_action(plot_number - 1, action_id)


func debug_force_elapsed(seconds: float) -> void:
	elapsed_sec = clampf(seconds, 0.0, session_duration_sec)
	_update_status_labels()


func _apply_context(context: Dictionary) -> void:
	farm_label = str(context.get("farm_label", farm_label)).strip_edges()
	if farm_label.is_empty():
		farm_label = "Farm"
	product_commodity = str(context.get("product_commodity", product_commodity)).strip_edges()
	if product_commodity.is_empty():
		product_commodity = "food"
	product_display_name = str(context.get("product_display_name", product_display_name)).strip_edges()
	if product_display_name.is_empty():
		product_display_name = product_commodity
	crop_ready = bool(context.get("crop_ready", crop_ready))
	available_storage = maxi(int(context.get("available_storage", available_storage)), 0)
	suggested_harvest_units = maxi(int(context.get("suggested_harvest_units", suggested_harvest_units)), 0)
	work_minutes = maxi(int(context.get("work_minutes", work_minutes)), 15)
	_units_per_crate = _calculate_units_per_crate()
	if is_inside_tree():
		_reset_plots()
		_update_all_ui()


func _reset_session_state() -> void:
	running = false
	elapsed_sec = 0.0
	score = 0
	mistakes = 0
	completed_tasks = 0
	delivered_crates = 0
	harvested_amount = 0
	quality_score = 1.0
	_basket_crates = 0
	_basket_units = 0
	_maintenance_tasks_done = 0
	_units_per_crate = _calculate_units_per_crate()
	_reset_plots()


func _reset_plots() -> void:
	_plots.clear()
	if crop_ready and available_storage > 0:
		_plots.append(_make_plot(true, true, 0, true))
		_plots.append(_make_plot(true, false, 0, true))
		_plots.append(_make_plot(true, true, 1, true))
		_plots.append(_make_plot(true, true, 0, true))
	else:
		_plots.append(_make_plot(false, false, 0, false))
		_plots.append(_make_plot(true, false, 0, false))
		_plots.append(_make_plot(true, true, 1, false))
		_plots.append(_make_plot(true, true, 0, false))
	_selected_plot_index = 0


func _make_plot(planted: bool, watered: bool, weeds: int, ready: bool) -> Dictionary:
	return {
		"planted": planted,
		"watered": watered,
		"weeds": maxi(weeds, 0),
		"ready": ready,
		"harvested": false,
	}


func _ensure_plots() -> void:
	if _plots.size() != PLOT_COUNT:
		_reset_plots()


func _calculate_units_per_crate() -> int:
	if suggested_harvest_units <= 0:
		return FALLBACK_UNITS_PER_CRATE
	return maxi(int(ceil(float(suggested_harvest_units) / 3.0)), 1)


func _calculate_work_minutes() -> int:
	var progress := clampf(elapsed_sec / maxf(session_duration_sec, 1.0), 0.25, 1.0)
	return maxi(int(round(float(work_minutes) * progress)), 15)


func _perform_selected_action(action_id: String) -> void:
	var result: Dictionary
	if action_id == ACTION_DELIVER:
		result = _perform_delivery_action()
	else:
		result = _perform_plot_action(_selected_plot_index, action_id)
	if bool(result.get("correct", false)):
		_select_next_relevant_plot()
	_update_all_ui()


func _perform_plot_action(plot_index: int, action_id: String) -> Dictionary:
	_ensure_plots()
	if plot_index < 0 or plot_index >= _plots.size():
		return _wrong_action("invalid_plot", -1, action_id, "")
	var plot := _plots[plot_index]
	var required_action := _recommended_action_for_plot(plot)
	if action_id != required_action:
		return _wrong_action("wrong_action", plot_index, action_id, required_action)

	match action_id:
		ACTION_PLANT:
			plot["planted"] = true
			plot["watered"] = false
			plot["weeds"] = 0
			plot["ready"] = false
			_score_correct(plot_index, "Saat gesetzt", 10)
			_maintenance_tasks_done += 1
		ACTION_WATER:
			plot["watered"] = true
			_score_correct(plot_index, "Pflanze gegossen", 9)
			_maintenance_tasks_done += 1
		ACTION_WEED:
			plot["weeds"] = maxi(int(plot.get("weeds", 0)) - 1, 0)
			_score_correct(plot_index, "Unkraut entfernt", 11)
			_maintenance_tasks_done += 1
		ACTION_HARVEST:
			if _basket_crates >= BASKET_CAPACITY_CRATES:
				return _wrong_action("basket_full", plot_index, action_id, ACTION_DELIVER)
			plot["harvested"] = true
			_basket_crates += 1
			_basket_units += _units_per_crate
			_score_correct(plot_index, "%s geerntet" % product_display_name, 16)
		_:
			return _wrong_action("unsupported_action", plot_index, action_id, required_action)

	_plots[plot_index] = plot
	return {
		"correct": true,
		"reason": "ok",
		"plot_number": plot_index + 1,
		"action": action_id,
		"score": score,
		"basket_crates": _basket_crates,
	}


func _perform_delivery_action() -> Dictionary:
	if _basket_crates <= 0:
		return _wrong_action("empty_basket", _selected_plot_index, ACTION_DELIVER, "")
	_deliver_basket()
	_set_hint("Kiste geliefert: %d %s im Lagerbereich." % [harvested_amount, product_display_name])
	return {
		"correct": true,
		"reason": "delivered",
		"action": ACTION_DELIVER,
		"score": score,
		"delivered_crates": delivered_crates,
		"harvested_amount": harvested_amount,
	}


func _deliver_basket() -> void:
	delivered_crates += _basket_crates
	harvested_amount += _basket_units
	score += 12 * _basket_crates
	completed_tasks += 1
	_basket_crates = 0
	_basket_units = 0
	score_changed.emit(score)


func _score_correct(plot_index: int, message: String, points: int) -> void:
	completed_tasks += 1
	score += points + mini(player_skill_level, 5)
	quality_score = clampf(quality_score + 0.015, 0.0, 1.0)
	_set_hint("Feld %d: %s." % [plot_index + 1, message])
	score_changed.emit(score)


func _wrong_action(reason: String, plot_index: int, action_id: String, required_action: String) -> Dictionary:
	mistakes += 1
	score = maxi(score - 8, 0)
	quality_score = clampf(quality_score - 0.10, 0.0, 1.0)
	var target := "Feld %d" % (plot_index + 1) if plot_index >= 0 else "Farm"
	var needed := _action_label(required_action)
	if needed.is_empty():
		_set_hint("%s: Aktion %s passt gerade nicht." % [target, _action_label(action_id)])
	else:
		_set_hint("%s: gebraucht wird %s." % [target, needed])
	mistake_made.emit(reason)
	return {
		"correct": false,
		"reason": reason,
		"plot_number": plot_index + 1,
		"action": action_id,
		"required_action": required_action,
		"score": score,
		"mistakes": mistakes,
	}


func _recommended_action_for_plot(plot: Dictionary) -> String:
	if bool(plot.get("harvested", false)):
		return ""
	if not bool(plot.get("planted", false)):
		return ACTION_PLANT
	if not bool(plot.get("watered", false)):
		return ACTION_WATER
	if int(plot.get("weeds", 0)) > 0:
		return ACTION_WEED
	if bool(plot.get("ready", false)):
		return ACTION_HARVEST
	return ""


func _select_next_relevant_plot() -> void:
	_ensure_plots()
	for offset in range(PLOT_COUNT):
		var index := (_selected_plot_index + offset) % PLOT_COUNT
		if not _recommended_action_for_plot(_plots[index]).is_empty():
			_selected_plot_index = index
			return


func _plot_state_label(plot: Dictionary) -> String:
	if bool(plot.get("harvested", false)):
		return "abgeerntet"
	if not bool(plot.get("planted", false)):
		return "leer"
	if not bool(plot.get("watered", false)):
		return "trocken"
	if int(plot.get("weeds", 0)) > 0:
		return "Unkraut"
	if bool(plot.get("ready", false)):
		return "reif"
	return "gepflegt"


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color8(9, 12, 16, 245)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
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
	title.text = "Farm-Schicht"
	title.add_theme_font_size_override("font_size", 23)
	title.add_theme_color_override("font_color", UiThemeScript.TEXT_PRIMARY)
	title_box.add_child(title)

	_hint_label = Label.new()
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.add_theme_color_override("font_color", UiThemeScript.TEXT_SECONDARY)
	title_box.add_child(_hint_label)

	_score_label = _make_status_label()
	_timer_label = _make_status_label()
	_quality_label = _make_status_label()
	_basket_label = _make_status_label()
	header.add_child(_score_label)
	header.add_child(_timer_label)
	header.add_child(_quality_label)
	header.add_child(_basket_label)

	var finish_button := Button.new()
	finish_button.custom_minimum_size = Vector2(128, 48)
	finish_button.text = "Schicht abgeben"
	finish_button.focus_mode = Control.FOCUS_NONE
	finish_button.pressed.connect(finish_session)
	header.add_child(finish_button)

	var content := HBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", UiThemeScript.SEPARATION_NORMAL)
	root.add_child(content)

	var viewport_panel := PanelContainer.new()
	viewport_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	viewport_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	viewport_panel.custom_minimum_size = Vector2(620, 0)
	content.add_child(viewport_panel)

	var viewport_container := SubViewportContainer.new()
	viewport_container.stretch = true
	viewport_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	viewport_container.name = "FarmPreview"
	viewport_panel.add_child(viewport_container)

	var viewport := SubViewport.new()
	viewport.name = "Viewport"
	viewport.size = Vector2i(720, 480)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport_container.add_child(viewport)
	_preview_viewport = viewport

	var side_panel := PanelContainer.new()
	side_panel.custom_minimum_size = Vector2(340, 0)
	side_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(side_panel)

	var side_box := VBoxContainer.new()
	side_box.add_theme_constant_override("separation", UiThemeScript.SEPARATION_NORMAL)
	side_panel.add_child(side_box)

	var plot_title := Label.new()
	plot_title.text = "Felder"
	plot_title.add_theme_font_size_override("font_size", 17)
	side_box.add_child(plot_title)

	var plot_grid := GridContainer.new()
	plot_grid.columns = 2
	plot_grid.add_theme_constant_override("h_separation", UiThemeScript.SEPARATION_DENSE)
	plot_grid.add_theme_constant_override("v_separation", UiThemeScript.SEPARATION_DENSE)
	side_box.add_child(plot_grid)

	for plot_index in range(PLOT_COUNT):
		var button := Button.new()
		button.custom_minimum_size = Vector2(150, 86)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(select_plot.bind(plot_index + 1))
		_plot_buttons.append(button)
		plot_grid.add_child(button)

	var action_title := Label.new()
	action_title.text = "Werkzeuge"
	action_title.add_theme_font_size_override("font_size", 17)
	side_box.add_child(action_title)

	for definition in ACTION_DEFINITIONS:
		var action_id := str(definition.get("id", ""))
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 52)
		button.focus_mode = Control.FOCUS_NONE
		button.text = "%s [%s]\n%s" % [
			str(definition.get("label", "")),
			str(definition.get("key", "")),
			str(definition.get("hint", "")),
		]
		button.pressed.connect(_perform_selected_action.bind(action_id))
		_action_buttons[action_id] = button
		side_box.add_child(button)


func _build_farm_preview() -> void:
	if _preview_viewport == null:
		return
	var scene := Node3D.new()
	scene.name = "FarmPreviewScene"
	_preview_viewport.add_child(scene)

	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color8(76, 105, 92, 255)
	environment.environment = env
	scene.add_child(environment)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48.0, 35.0, 0.0)
	light.light_energy = 1.15
	scene.add_child(light)

	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 7.2, 7.6)
	camera.rotation_degrees = Vector3(-47.0, 0.0, 0.0)
	camera.current = true
	scene.add_child(camera)

	var ground := MeshInstance3D.new()
	var ground_mesh := BoxMesh.new()
	ground_mesh.size = Vector3(9.0, 0.12, 7.0)
	ground.mesh = ground_mesh
	ground.position = Vector3(0.0, -0.08, 0.0)
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color8(76, 125, 79, 255)
	ground.material_override = ground_mat
	scene.add_child(ground)

	for index in range(PLOT_COUNT):
		var plot := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(2.6, 0.18, 2.0)
		plot.mesh = mesh
		plot.position = Vector3(-1.6 + float(index % 2) * 3.2, 0.05, -1.25 + float(int(index / 2)) * 2.5)
		var mat := StandardMaterial3D.new()
		plot.material_override = mat
		_plot_meshes.append(plot)
		_plot_materials.append(mat)
		scene.add_child(plot)

	var crate := MeshInstance3D.new()
	var crate_mesh := BoxMesh.new()
	crate_mesh.size = Vector3(1.2, 0.8, 1.2)
	crate.mesh = crate_mesh
	crate.position = Vector3(3.6, 0.35, 2.65)
	var crate_mat := StandardMaterial3D.new()
	crate_mat.albedo_color = Color8(150, 92, 46, 255)
	crate.material_override = crate_mat
	scene.add_child(crate)


func _make_status_label() -> Label:
	var label := Label.new()
	label.custom_minimum_size = Vector2(116, 46)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiThemeScript.apply_pill_label(label, UiThemeScript.TEXT_PRIMARY, Color8(35, 41, 56, 255))
	return label


func _update_all_ui() -> void:
	_update_status_labels()
	_update_plot_buttons()
	_update_action_buttons()
	_update_plot_preview()


func _update_status_labels() -> void:
	if _score_label != null:
		_score_label.text = "Score\n%d" % score
	if _timer_label != null:
		var remaining := maxf(session_duration_sec - elapsed_sec, 0.0)
		_timer_label.text = "Zeit\n%02ds" % int(ceil(remaining))
	if _quality_label != null:
		_quality_label.text = "Qualitaet\n%d%%" % int(round(get_quality_score() * 100.0))
	if _basket_label != null:
		_basket_label.text = "Korb\n%d/%d" % [_basket_crates, BASKET_CAPACITY_CRATES]


func _update_plot_buttons() -> void:
	_ensure_plots()
	for index in range(_plot_buttons.size()):
		var button := _plot_buttons[index]
		if button == null:
			continue
		var plot := _plots[index]
		var required_action := _recommended_action_for_plot(plot)
		button.text = "Feld %d\n%s\n%s" % [
			index + 1,
			_plot_state_label(plot),
			_action_label(required_action) if not required_action.is_empty() else "-",
		]
		var color := _plot_color(plot)
		var selected := index == _selected_plot_index
		button.add_theme_stylebox_override("normal", _make_button_box(color.darkened(0.58), color, selected))
		button.add_theme_stylebox_override("hover", _make_button_box(color.darkened(0.46), color, true))
		button.add_theme_stylebox_override("pressed", _make_button_box(color.darkened(0.68), color.lightened(0.1), true))


func _update_action_buttons() -> void:
	var selected_action := ""
	if _selected_plot_index >= 0 and _selected_plot_index < _plots.size():
		selected_action = _recommended_action_for_plot(_plots[_selected_plot_index])
	if _basket_crates > 0:
		selected_action = ACTION_DELIVER if selected_action.is_empty() else selected_action
	for action_id in _action_buttons.keys():
		var button: Button = _action_buttons[action_id]
		var definition := _get_action_definition(str(action_id))
		var color: Color = definition.get("color", UiThemeScript.ACCENT)
		var highlighted := str(action_id) == selected_action
		button.add_theme_stylebox_override("normal", _make_button_box(color.darkened(0.58 if highlighted else 0.70), color, highlighted))
		button.add_theme_stylebox_override("hover", _make_button_box(color.darkened(0.48), color, true))
		button.add_theme_stylebox_override("pressed", _make_button_box(color.darkened(0.62), color.lightened(0.1), true))


func _update_plot_preview() -> void:
	_ensure_plots()
	for index in range(mini(_plot_materials.size(), _plots.size())):
		var mat := _plot_materials[index]
		if mat == null:
			continue
		mat.albedo_color = _plot_color(_plots[index])
		var mesh := _plot_meshes[index]
		if mesh != null:
			mesh.scale.y = 0.45 if bool(_plots[index].get("harvested", false)) else 1.0


func _plot_color(plot: Dictionary) -> Color:
	if bool(plot.get("harvested", false)):
		return Color8(96, 73, 55, 255)
	if not bool(plot.get("planted", false)):
		return Color8(96, 65, 43, 255)
	if not bool(plot.get("watered", false)):
		return Color8(142, 94, 50, 255)
	if int(plot.get("weeds", 0)) > 0:
		return Color8(128, 150, 48, 255)
	if bool(plot.get("ready", false)):
		return Color8(215, 139, 48, 255)
	return Color8(74, 145, 74, 255)


func _get_action_definition(action_id: String) -> Dictionary:
	for definition in ACTION_DEFINITIONS:
		if str(definition.get("id", "")) == action_id:
			return definition
	return {}


func _action_label(action_id: String) -> String:
	if action_id.is_empty():
		return ""
	var definition := _get_action_definition(action_id)
	if definition.is_empty():
		return action_id
	return str(definition.get("label", action_id))


func _set_hint(text: String) -> void:
	if _hint_label != null:
		_hint_label.text = text


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
	box.content_margin_top = 7
	box.content_margin_bottom = 7
	return box
