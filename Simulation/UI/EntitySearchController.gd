extends RefCounted
class_name EntitySearchController

var world: World = null
var city_camera: CityBuilderCamera = null
var search_input: LineEdit = null
var search_results_list: ItemList = null
var search_result_limit: int = 12

var _search_results: Array[Dictionary] = []
var _select_citizen: Callable = Callable()
var _select_building: Callable = Callable()
var _mark_ui_interacted: Callable = Callable()

func setup(
	world_ref: World,
	camera_ref: CityBuilderCamera,
	input_ref: LineEdit,
	results_ref: ItemList,
	select_citizen: Callable,
	select_building: Callable,
	mark_ui_interacted: Callable,
	result_limit: int = 12
) -> void:
	world = world_ref
	city_camera = camera_ref
	search_input = input_ref
	search_results_list = results_ref
	search_result_limit = maxi(result_limit, 1)
	_select_citizen = select_citizen
	_select_building = select_building
	_mark_ui_interacted = mark_ui_interacted

	if search_input != null:
		if not search_input.text_changed.is_connected(_on_search_text_changed):
			search_input.text_changed.connect(_on_search_text_changed)
		if not search_input.text_submitted.is_connected(_on_search_text_submitted):
			search_input.text_submitted.connect(_on_search_text_submitted)
		if not search_input.gui_input.is_connected(_on_search_ui_input):
			search_input.gui_input.connect(_on_search_ui_input)

	if search_results_list != null:
		if not search_results_list.item_selected.is_connected(_on_search_result_selected):
			search_results_list.item_selected.connect(_on_search_result_selected)
		if not search_results_list.item_activated.is_connected(_on_search_result_activated):
			search_results_list.item_activated.connect(_on_search_result_activated)
		if not search_results_list.gui_input.is_connected(_on_search_ui_input):
			search_results_list.gui_input.connect(_on_search_ui_input)

func _on_search_text_changed(new_text: String) -> void:
	_refresh_search_results(new_text)

func _on_search_text_submitted(submitted_text: String) -> void:
	_refresh_search_results(submitted_text)
	if _search_results.is_empty():
		return
	_apply_search_result(0)

func _on_search_result_selected(index: int) -> void:
	_apply_search_result(index)

func _on_search_result_activated(index: int) -> void:
	_apply_search_result(index)

func _on_search_ui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_mark_interacted()

func _refresh_search_results(raw_query: String) -> void:
	_search_results.clear()
	if search_results_list == null:
		return

	search_results_list.clear()
	var query := raw_query.strip_edges().to_lower()
	if query.is_empty():
		search_results_list.visible = false
		return

	for entry in _collect_search_matches(query):
		_search_results.append(entry)
		search_results_list.add_item(str(entry.get("label", "")))

	search_results_list.visible = not _search_results.is_empty()

func _collect_search_matches(query: String) -> Array[Dictionary]:
	var matches: Array[Dictionary] = []
	if world == null:
		return matches

	for citizen in world.citizens:
		if citizen == null or not is_instance_valid(citizen):
			continue
		var citizen_name := citizen.citizen_name.strip_edges()
		var location_name := citizen.current_location.get_display_name() if citizen.current_location != null else "travelling"
		var searchable := ("%s %s citizen person" % [citizen_name, location_name]).to_lower()
		var score := _compute_search_score(query, citizen_name.to_lower(), searchable)
		if score < 0:
			continue
		matches.append({
			"score": score,
			"sort_name": citizen_name.to_lower(),
			"name": citizen_name,
			"label": "Citizen | %s | %s" % [citizen_name, location_name],
			"entity": citizen,
		})

	for building in world.buildings:
		if building == null or not is_instance_valid(building):
			continue
		var building_name := building.get_display_name().strip_edges()
		var searchable := ("%s %s building house" % [building_name, building.get_service_type()]).to_lower()
		var score := _compute_search_score(query, building_name.to_lower(), searchable)
		if score < 0:
			continue
		matches.append({
			"score": score,
			"sort_name": building_name.to_lower(),
			"name": building_name,
			"label": "Building | %s | %s" % [building_name, building.get_service_type()],
			"entity": building,
		})

	matches.sort_custom(_sort_search_matches)
	if matches.size() > search_result_limit:
		matches.resize(search_result_limit)
	return matches

func _compute_search_score(query: String, primary_name: String, searchable: String) -> int:
	if primary_name == query:
		return 0
	if primary_name.begins_with(query):
		return 1
	if searchable.contains(" " + query):
		return 2
	if searchable.contains(query):
		return 3
	return -1

func _sort_search_matches(a: Dictionary, b: Dictionary) -> bool:
	var score_a := int(a.get("score", 99))
	var score_b := int(b.get("score", 99))
	if score_a != score_b:
		return score_a < score_b
	return str(a.get("sort_name", "")) < str(b.get("sort_name", ""))

func _apply_search_result(index: int) -> void:
	if index < 0 or index >= _search_results.size():
		return

	_mark_interacted()
	var entry := _search_results[index]
	var entity = entry.get("entity", null)

	if entity is Citizen:
		if _select_citizen.is_valid():
			_select_citizen.call(entity as Citizen)
	elif entity is Building:
		if _select_building.is_valid():
			_select_building.call(entity as Building)
	else:
		return

	if search_input != null:
		search_input.text = str(entry.get("name", search_input.text))
	if search_results_list != null:
		search_results_list.visible = false

	_focus_camera_on_search_entity(entity)

func _focus_camera_on_search_entity(entity) -> void:
	if city_camera == null:
		return

	var focus_pos := Vector3.ZERO
	if entity is Citizen:
		var citizen := entity as Citizen
		if citizen.is_inside_building() and citizen.current_location != null:
			focus_pos = citizen.current_location.global_position
		else:
			focus_pos = citizen.global_position
	elif entity is Building:
		focus_pos = (entity as Building).global_position
	else:
		return

	city_camera.focus_on_world_position(focus_pos)

func _mark_interacted() -> void:
	if _mark_ui_interacted.is_valid():
		_mark_ui_interacted.call()
