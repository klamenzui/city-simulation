extends RefCounted
class_name CityDistrictIndex

const CONFIG_PATH := "res://config/city_districts.json"

var world: World = null

var _config: Dictionary = {}
var _origin: Vector3 = Vector3.ZERO
var _building_district_by_id: Dictionary = {}
var _building_ids_by_district: Dictionary = {}

func setup(world_ref: World) -> void:
	world = world_ref
	_config = _load_config()
	_recompute_origin()
	rebuild_building_index()

func rebuild_building_index() -> void:
	_building_district_by_id.clear()
	_building_ids_by_district.clear()
	if world == null:
		return
	for building in world.buildings:
		register_building(building)

func register_building(building: Building) -> void:
	if building == null:
		return
	var building_id := building.get_instance_id()
	var district_id := get_district_id_for_position(building.global_position)
	_building_district_by_id[building_id] = district_id
	var district_entries: Array = _building_ids_by_district.get(district_id, [])
	if not district_entries.has(building_id):
		district_entries.append(building_id)
	_building_ids_by_district[district_id] = district_entries

func unregister_building(building: Building) -> void:
	if building == null:
		return
	var building_id := building.get_instance_id()
	var district_id := str(_building_district_by_id.get(building_id, ""))
	_building_district_by_id.erase(building_id)
	if district_id.is_empty():
		return
	var district_entries: Array = _building_ids_by_district.get(district_id, [])
	district_entries.erase(building_id)
	if district_entries.is_empty():
		_building_ids_by_district.erase(district_id)
	else:
		_building_ids_by_district[district_id] = district_entries

func get_district_id_for_position(world_pos: Vector3) -> String:
	var coords := get_district_coords_for_position(world_pos)
	return _district_id_from_coords(coords)

func get_district_coords_for_position(world_pos: Vector3) -> Vector2i:
	var cell_size := _get_cell_size()
	return Vector2i(
		int(floor((world_pos.x - _origin.x) / cell_size)),
		int(floor((world_pos.z - _origin.z) / cell_size))
	)

func get_district_center(district_id: String) -> Vector3:
	var coords := _district_coords_from_id(district_id)
	var cell_size := _get_cell_size()
	return Vector3(
		_origin.x + (float(coords.x) + 0.5) * cell_size,
		world.get_ground_fallback_y() if world != null else 0.0,
		_origin.z + (float(coords.y) + 0.5) * cell_size
	)

func get_neighbor_district_ids_for_position(world_pos: Vector3) -> Array[String]:
	var district_ids: Array[String] = []
	var coords := get_district_coords_for_position(world_pos)
	var radius := _get_neighbor_radius()
	for offset_x in range(-radius, radius + 1):
		for offset_y in range(-radius, radius + 1):
			district_ids.append(_district_id_from_coords(coords + Vector2i(offset_x, offset_y)))
	return district_ids

func are_positions_in_same_or_neighbor_district(pos_a: Vector3, pos_b: Vector3) -> bool:
	var coords_a := get_district_coords_for_position(pos_a)
	var coords_b := get_district_coords_for_position(pos_b)
	var radius := _get_neighbor_radius()
	return abs(coords_a.x - coords_b.x) <= radius and abs(coords_a.y - coords_b.y) <= radius

func get_building_district_id(building: Building) -> String:
	if building == null:
		return ""
	var building_id := building.get_instance_id()
	if _building_district_by_id.has(building_id):
		return str(_building_district_by_id[building_id])
	return get_district_id_for_position(building.global_position)

func get_buildings_in_district(district_id: String) -> Array[Building]:
	var buildings_in_district: Array[Building] = []
	var building_ids: Variant = _building_ids_by_district.get(district_id, [])
	if building_ids is not Array:
		return buildings_in_district
	for raw_id in building_ids as Array:
		var building := instance_from_id(int(raw_id)) as Building
		if building == null or not is_instance_valid(building):
			continue
		buildings_in_district.append(building)
	return buildings_in_district

func get_citizens_in_district(district_id: String) -> Array[Citizen]:
	var citizens_in_district: Array[Citizen] = []
	if world == null:
		return citizens_in_district
	for citizen in world.citizens:
		if citizen == null:
			continue
		if get_district_id_for_position(citizen.global_position) == district_id:
			citizens_in_district.append(citizen)
	return citizens_in_district

func _recompute_origin() -> void:
	if world == null:
		_origin = Vector3.ZERO
		return
	var bounds := world.get_world_bounds()
	_origin = bounds.position
	_origin.y = 0.0

func _district_id_from_coords(coords: Vector2i) -> String:
	return "%s_%d_%d" % [_get_label_prefix(), coords.x, coords.y]

func _district_coords_from_id(district_id: String) -> Vector2i:
	var prefix := "%s_" % _get_label_prefix()
	if not district_id.begins_with(prefix):
		return Vector2i.ZERO
	var raw_suffix := district_id.trim_prefix(prefix)
	var parts := raw_suffix.split("_")
	if parts.size() < 2:
		return Vector2i.ZERO
	return Vector2i(int(parts[0]), int(parts[1]))

func _get_cell_size() -> float:
	return maxf(float(_get_value("grid.cell_size_m", 24.0)), 1.0)

func _get_neighbor_radius() -> int:
	return maxi(int(_get_value("grid.neighbor_radius_cells", 1)), 0)

func _get_label_prefix() -> String:
	return str(_get_value("grid.label_prefix", "D"))

func _load_config() -> Dictionary:
	var defaults := {
		"grid": {
			"cell_size_m": 24.0,
			"neighbor_radius_cells": 1,
			"label_prefix": "D"
		}
	}
	if not FileAccess.file_exists(CONFIG_PATH):
		return defaults
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		return defaults
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		_deep_merge(defaults, parsed as Dictionary)
	return defaults

func _deep_merge(base: Dictionary, override: Dictionary) -> void:
	for key in override.keys():
		var override_value: Variant = override[key]
		if base.has(key) and base[key] is Dictionary and override_value is Dictionary:
			_deep_merge(base[key], override_value)
		else:
			base[key] = override_value

func _get_value(path: String, default_value = null):
	var current: Variant = _config
	for part in path.split("."):
		if part.is_empty():
			continue
		if current is Dictionary and current.has(part):
			current = current[part]
			continue
		return default_value
	return current
