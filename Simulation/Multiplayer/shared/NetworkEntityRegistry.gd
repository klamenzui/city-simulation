extends RefCounted
class_name NetworkEntityRegistry

const META_ENTITY_ID := "_network_entity_id"
const BUILDING_PREFIX := "building:"
const CITIZEN_PREFIX := "citizen:"

var _next_citizen_id: int = 1

func ensure_world_entities(world: World, root: Node) -> void:
	ensure_building_ids(world, root)
	ensure_citizen_ids(world)

func ensure_building_ids(world: World, root: Node) -> void:
	if world == null or root == null:
		return
	var entries: Array = []
	for building in world.buildings:
		if building == null or not is_instance_valid(building):
			continue
		entries.append({
			"building": building,
			"path": _node_path(root, building),
		})
	entries.sort_custom(func(a, b): return str(a.get("path", "")) < str(b.get("path", "")))
	for entry in entries:
		var building := entry["building"] as Building
		var path := str(entry.get("path", ""))
		if building == null or path.is_empty():
			continue
		if get_entity_id(building).is_empty():
			set_entity_id(building, BUILDING_PREFIX + path)

func ensure_citizen_ids(world: World) -> void:
	if world == null:
		return
	for citizen in world.citizens:
		if citizen == null or not is_instance_valid(citizen):
			continue
		if not get_entity_id(citizen).is_empty():
			continue
		set_entity_id(citizen, CITIZEN_PREFIX + ("%04d" % _next_citizen_id))
		_next_citizen_id += 1

static func get_entity_id(node: Node) -> String:
	if node == null or not node.has_meta(META_ENTITY_ID):
		return ""
	return str(node.get_meta(META_ENTITY_ID))

static func set_entity_id(node: Node, entity_id: String) -> void:
	if node == null or entity_id.strip_edges().is_empty():
		return
	node.set_meta(META_ENTITY_ID, entity_id.strip_edges())

static func _node_path(root: Node, node: Node) -> String:
	if root == null or node == null:
		return ""
	if root == node:
		return "."
	if not root.is_ancestor_of(node):
		return str(node.get_path())
	return str(root.get_path_to(node))
