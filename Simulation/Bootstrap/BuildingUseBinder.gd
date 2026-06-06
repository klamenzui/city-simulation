extends RefCounted
class_name BuildingUseBinder

const ResidentialBuildingScript = preload("res://Entities/Buildings/ResidentialBuilding.gd")
const ShopScript = preload("res://Entities/Buildings/Shop.gd")
const CafeScript = preload("res://Entities/Buildings/Cafe.gd")
const RestaurantScript = preload("res://Entities/Buildings/Restaurant.gd")
const BankScript = preload("res://Entities/Buildings/Bank.gd")

const META_USES := "building_uses"
const META_USE := "building_use"
const META_BOUND := "_building_uses_bound"
const META_GENERATED := "generated_from_building_uses"
const META_SOURCE_INSTANCE_ID := "building_use_source_instance_id"
const DEFAULT_ENTRANCE_NAME := "Entrance"
const GROUP_USE_PREFIX := "building_use_"

const USE_RESIDENTIAL := "residential"
const USE_SHOP := "shop"
const USE_CAFE := "cafe"
const USE_RESTAURANT := "restaurant"
const USE_BANK := "bank"

const USE_ORDER := [
	USE_RESIDENTIAL,
	USE_SHOP,
	USE_CAFE,
	USE_RESTAURANT,
	USE_BANK,
]

static func bind_tree(root: Node) -> Array[Building]:
	var created: Array[Building] = []
	if root == null:
		return created

	var candidates: Array[Node] = []
	_collect_tagged_nodes(root, candidates)
	for candidate in candidates:
		created.append_array(bind_node(candidate))
	return created

static func bind_node(source: Node) -> Array[Building]:
	var created: Array[Building] = []
	if source == null:
		return created
	if bool(source.get_meta(META_BOUND, false)):
		return created

	var uses := get_declared_uses(source)
	if uses.is_empty():
		return created
	if source is Building:
		return _bind_existing_building(source as Building, uses)

	source.set_meta(META_BOUND, true)
	if uses.size() > 1:
		source.add_to_group("mixed_use")

	var source_3d := source as Node3D
	var entrance := _resolve_entrance(source)
	var residential: ResidentialBuilding = null

	if uses.has(USE_RESIDENTIAL):
		residential = _new_residential_unit(source, source_3d, entrance)
		if uses.size() > 1:
			residential.add_to_group("mixed_use")
		source.add_child(residential)
		created.append(residential)

	var business_parent: Node = residential if residential != null else source
	for use in uses:
		if use == USE_RESIDENTIAL:
			continue
		var business := _new_business_unit(use, source, source_3d, entrance)
		if business == null:
			continue
		business_parent.add_child(business)
		created.append(business)

	return created

static func get_declared_uses(source: Node) -> Array[String]:
	var raw: Array[String] = []
	if source.has_meta(META_USES):
		raw.append_array(_parse_uses(source.get_meta(META_USES)))
	elif source.has_meta(META_USE):
		raw.append_array(_parse_uses(source.get_meta(META_USE)))

	for group_name_var in source.get_groups():
		var group_name := str(group_name_var)
		var normalized := _normalize_group_use(group_name)
		if not normalized.is_empty():
			raw.append(normalized)

	var by_key := {}
	for use in raw:
		var normalized_use := _normalize_use(use)
		if _is_supported_use(normalized_use):
			by_key[normalized_use] = true

	var ordered: Array[String] = []
	for use_ordered in USE_ORDER:
		if by_key.has(use_ordered):
			ordered.append(use_ordered)
	return ordered

static func _collect_tagged_nodes(node: Node, out: Array[Node]) -> void:
	if node == null:
		return
	var uses := get_declared_uses(node)
	if not bool(node.get_meta(META_BOUND, false)) and not _get_actionable_uses(node, uses).is_empty():
		out.append(node)
		if node is Building:
			return
	if node is Building:
		return
	for child in node.get_children():
		_collect_tagged_nodes(child, out)

static func _parse_uses(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for entry in value as Array:
			result.append(str(entry))
		return result
	var text := str(value)
	for part in text.split(",", false):
		result.append(part)
	return result

static func _normalize_group_use(group_name: String) -> String:
	var stripped := group_name.strip_edges()
	if stripped.is_empty():
		return ""
	if stripped == stripped.to_upper():
		return _normalize_use(stripped)
	var lower := stripped.to_lower()
	if lower.begins_with("building_use_"):
		return _normalize_use(lower.substr("building_use_".length()))
	if lower.begins_with("use_"):
		return _normalize_use(lower.substr("use_".length()))
	if lower.begins_with("building_use:"):
		return _normalize_use(lower.substr("building_use:".length()))
	return ""

static func _normalize_use(use: String) -> String:
	var normalized := use.strip_edges().to_lower()
	normalized = normalized.replace("-", "_")
	normalized = normalized.replace(" ", "_")
	match normalized:
		"res", "house", "housing", "wohnung", "wohnungen", "wohnhaus":
			return USE_RESIDENTIAL
		"store", "laden":
			return USE_SHOP
		"café":
			return USE_CAFE
		"restourant":
			return USE_RESTAURANT
		"finanzbank", "finance_bank", "kreditbank":
			return USE_BANK
		_:
			return normalized

static func _is_supported_use(use: String) -> bool:
	return use == USE_RESIDENTIAL \
		or use == USE_SHOP \
		or use == USE_CAFE \
		or use == USE_RESTAURANT \
		or use == USE_BANK

static func _resolve_entrance(source: Node) -> Node3D:
	if source == null:
		return null
	var entrance_path := DEFAULT_ENTRANCE_NAME
	if source.has_meta("entrance"):
		entrance_path = str(source.get_meta("entrance"))
	elif source.has_meta("building_entrance"):
		entrance_path = str(source.get_meta("building_entrance"))
	var entrance := source.get_node_or_null(entrance_path) as Node3D
	if entrance != null:
		return entrance
	return source.get_node_or_null(DEFAULT_ENTRANCE_NAME) as Node3D

static func _new_residential_unit(source: Node, source_3d: Node3D, entrance: Node3D) -> ResidentialBuilding:
	var unit := ResidentialBuildingScript.new() as ResidentialBuilding
	_configure_unit(unit, USE_RESIDENTIAL, source, source_3d, entrance)
	return unit

static func _new_business_unit(use: String, source: Node, source_3d: Node3D, entrance: Node3D) -> Building:
	var unit: Building = null
	match use:
		USE_SHOP:
			unit = ShopScript.new() as Shop
		USE_CAFE:
			unit = CafeScript.new() as Cafe
		USE_RESTAURANT:
			unit = RestaurantScript.new() as Restaurant
		USE_BANK:
			unit = BankScript.new() as Bank
		_:
			return null
	_configure_unit(unit, use, source, source_3d, entrance)
	unit.add_to_group("ground_floor_business")
	return unit

static func _bind_existing_building(source: Building, uses: Array[String]) -> Array[Building]:
	var created: Array[Building] = []
	if source == null or bool(source.get_meta(META_GENERATED, false)):
		return created

	var actionable_uses := _get_actionable_uses(source, uses)
	if actionable_uses.is_empty():
		return created

	source.set_meta(META_BOUND, true)
	source.add_to_group("mixed_use")
	source.set_meta(META_SOURCE_INSTANCE_ID, source.get_instance_id())

	var source_3d := source as Node3D
	var entrance := source.entrance if source.entrance != null else _resolve_entrance(source)
	if source.entrance == null:
		source.entrance = entrance

	for use in actionable_uses:
		if _has_existing_business_unit(source, use):
			continue
		var business := _new_business_unit(use, source, source_3d, entrance)
		if business == null:
			continue
		source.add_child(business)
		created.append(business)
	return created

static func _get_actionable_uses(source: Node, uses: Array[String]) -> Array[String]:
	var actionable: Array[String] = []
	if source == null or uses.is_empty():
		return actionable
	if source is Building:
		if source is ResidentialBuilding:
			for use in uses:
				if use != USE_RESIDENTIAL and _is_supported_use(use):
					actionable.append(use)
		return actionable
	return uses

static func _has_existing_business_unit(source: Building, use: String) -> bool:
	if source == null:
		return false
	var businesses: Array[Building] = []
	_collect_existing_business_units(source, businesses)
	for business in businesses:
		if _building_matches_use(business, use):
			return true
	return false

static func _collect_existing_business_units(node: Node, out: Array[Building]) -> void:
	for child in node.get_children():
		if child is Building:
			var building := child as Building
			if building is Shop or building is Cafe or building is Restaurant or building is Bank:
				out.append(building)
			continue
		_collect_existing_business_units(child, out)

static func _building_matches_use(building: Building, use: String) -> bool:
	if building == null:
		return false
	match use:
		USE_SHOP:
			return building is Shop and building is not Supermarket
		USE_CAFE:
			return building is Cafe
		USE_RESTAURANT:
			return building is Restaurant
		USE_BANK:
			return building is Bank
		_:
			return false

static func _configure_unit(unit: Building, use: String, source: Node, source_3d: Node3D, entrance: Node3D) -> void:
	unit.name = _unit_node_name(use)
	unit.building_name = _unit_display_name(use, source)
	unit.entrance = entrance
	unit.add_to_group("buildings")
	unit.add_to_group("%s%s" % [GROUP_USE_PREFIX, use])
	unit.set_meta(META_GENERATED, true)
	unit.set_meta(META_SOURCE_INSTANCE_ID, source.get_instance_id())
	if source.has_meta("building_archetype"):
		unit.set_meta("building_archetype", source.get_meta("building_archetype"))
	_apply_common_overrides(unit, use, source)
	_add_generated_click_area(unit, source_3d, entrance)

static func _apply_common_overrides(unit: Building, use: String, source: Node) -> void:
	var capacity_key := "%s_capacity" % use
	var job_capacity_key := "%s_job_capacity" % use
	var open_hour_key := "%s_open_hour" % use
	var close_hour_key := "%s_close_hour" % use
	if source.has_meta(capacity_key):
		unit.capacity = int(source.get_meta(capacity_key))
	elif source.has_meta("capacity"):
		unit.capacity = int(source.get_meta("capacity"))
	if source.has_meta(job_capacity_key):
		unit.job_capacity = int(source.get_meta(job_capacity_key))
	if source.has_meta(open_hour_key):
		unit.open_hour = int(source.get_meta(open_hour_key))
	if source.has_meta(close_hour_key):
		unit.close_hour = int(source.get_meta(close_hour_key))

static func _add_generated_click_area(unit: Building, source_3d: Node3D, entrance: Node3D) -> void:
	var area := Area3D.new()
	area.name = "GeneratedClickArea"
	area.collision_layer = 8
	area.collision_mask = 0
	var shape_node := CollisionShape3D.new()
	shape_node.name = "CollisionShape3D"
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.9, 1.8, 0.7)
	shape_node.shape = shape
	var local_pos := Vector3(0.0, 0.9, 0.0)
	if source_3d != null and entrance != null:
		if source_3d.is_inside_tree() and entrance.is_inside_tree():
			local_pos = source_3d.to_local(entrance.global_position)
		else:
			local_pos = entrance.position
		local_pos.y += 0.9
	shape_node.position = local_pos
	area.add_child(shape_node)
	unit.add_child(area)

static func _unit_node_name(use: String) -> String:
	match use:
		USE_RESIDENTIAL:
			return "ResidentialUnit"
		USE_SHOP:
			return "ShopUnit"
		USE_CAFE:
			return "CafeUnit"
		USE_RESTAURANT:
			return "RestaurantUnit"
		USE_BANK:
			return "BankUnit"
		_:
			return "%sUnit" % use.capitalize()

static func _unit_display_name(use: String, source: Node) -> String:
	var base_name := source.name
	if source.has_meta("building_name"):
		base_name = str(source.get_meta("building_name")).strip_edges()
	if base_name.is_empty():
		base_name = source.name
	match use:
		USE_RESIDENTIAL:
			return "%s Apartments" % base_name
		USE_SHOP:
			return "%s Shop" % base_name
		USE_CAFE:
			return "%s Cafe" % base_name
		USE_RESTAURANT:
			return "%s Restaurant" % base_name
		USE_BANK:
			if base_name.to_lower().contains("bank"):
				return base_name
			return "%s Bank" % base_name
		_:
			return base_name
