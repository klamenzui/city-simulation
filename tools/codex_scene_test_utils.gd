extends RefCounted
class_name CodexSceneTestUtils

const WORLD_PATHS: Array[NodePath] = [
	NodePath("World"),
	NodePath("RootNode/Islands/MainIsland"),
	NodePath("RootNode/Islands/World"),
]

static func find_world(root: Node) -> World:
	if root == null:
		return null
	for path in WORLD_PATHS:
		var world := root.get_node_or_null(path) as World
		if world != null:
			return world
	var tree := root.get_tree()
	if tree != null:
		for node in tree.get_nodes_in_group("world"):
			if node is World and _is_same_tree_branch(root, node):
				return node as World
	return _find_world_recursive(root)

static func _find_world_recursive(node: Node) -> World:
	if node is World:
		return node as World
	for child in node.get_children():
		var world := _find_world_recursive(child)
		if world != null:
			return world
	return null

static func _is_same_tree_branch(root: Node, node: Node) -> bool:
	var current := node
	while current != null:
		if current == root:
			return true
		current = current.get_parent()
	return false
