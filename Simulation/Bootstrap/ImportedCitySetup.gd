extends RefCounted
class_name ImportedCitySetup

const IMPORTED_CITY_SCENE_PATH := "res://ImportedCitySource/city_edited.tscn"
const IMPORTED_CITY_NODE_NAME := "ImportedCity"

static func ensure_city_visual(root: Node3D) -> Node3D:
	if root == null:
		return null

	var existing := root.get_node_or_null(IMPORTED_CITY_NODE_NAME) as Node3D
	if existing != null:
		return existing

	var city_scene: PackedScene = load(IMPORTED_CITY_SCENE_PATH)
	if city_scene == null:
		push_warning("ImportedCitySetup: Could not load %s" % IMPORTED_CITY_SCENE_PATH)
		return null

	var city := city_scene.instantiate() as Node3D
	if city == null:
		push_warning("ImportedCitySetup: Scene did not instantiate as Node3D")
		return null

	city.name = IMPORTED_CITY_NODE_NAME
	_cleanup_non_visual_nodes(city)
	root.add_child(city)
	city.position = Vector3.ZERO
	city.rotation = Vector3.ZERO
	city.scale = Vector3.ONE

	# Keep imported content as static decoration.
	city.process_mode = Node.PROCESS_MODE_DISABLED
	return city

static func _cleanup_non_visual_nodes(city: Node3D) -> void:
	if city == null:
		return

	for node_name in ["only_people_nav", "PathPointsLeft", "PathPointsRight"]:
		var node := city.get_node_or_null(node_name)
		if node != null:
			node.free()
