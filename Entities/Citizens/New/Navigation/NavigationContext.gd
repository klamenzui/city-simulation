class_name NavigationContext
extends RefCounted

## Shared dependency bundle passed to every navigation module.
##
## Lives for the lifetime of the Controller.  Holds a weak-ish reference to
## the owner CharacterBody3D (via `owner_body`) for physics queries that need
## `get_rid`, `collision_mask`, `global_position`, `get_world_3d`.
##
## Also caches the `world_node` lookup — traversing the scene tree to find
## the node that implements `get_pedestrian_path` is expensive and was called
## ~800×/replan in the original monolith.

var owner_body: CharacterBody3D = null
var config: CitizenConfig = null
var logger: CitizenLogger = null

## Cached scene-tree lookup; refreshed lazily when invalidated.
var _cached_world_node: Node = null


func _init(
		p_owner: CharacterBody3D,
		p_config: CitizenConfig,
		p_logger: CitizenLogger) -> void:
	owner_body = p_owner
	config = p_config
	logger = p_logger


func is_ready_for_physics() -> bool:
	return owner_body != null \
			and owner_body.is_inside_tree() \
			and owner_body.get_world_3d() != null


func get_space_state() -> PhysicsDirectSpaceState3D:
	if not is_ready_for_physics():
		return null
	return owner_body.get_world_3d().direct_space_state


func get_owner_rid() -> RID:
	if owner_body == null:
		return RID()
	return owner_body.get_rid()


func get_owner_position() -> Vector3:
	if owner_body == null:
		return Vector3.ZERO
	return owner_body.global_position


func get_owner_collision_mask() -> int:
	if owner_body == null:
		return 0
	return owner_body.collision_mask


## Walks up the tree (then scans group "world") for a node exposing
## `get_pedestrian_path`.  Cached because every local-grid rebuild queried
## this per surface-cell.
func get_world_node() -> Node:
	if is_instance_valid(_cached_world_node):
		return _cached_world_node

	if owner_body == null or not owner_body.is_inside_tree():
		return null

	var current: Node = owner_body
	while current != null:
		if current.has_method("get_pedestrian_path"):
			_cached_world_node = current
			return current
		current = current.get_parent()

	for w in owner_body.get_tree().get_nodes_in_group("world"):
		if w != null and w.has_method("get_pedestrian_path"):
			_cached_world_node = w
			return w

	return null


## Returns the active navigation map RID, or RID() if unavailable.
func get_navigation_map() -> RID:
	if not is_ready_for_physics():
		return RID()
	var world_3d := owner_body.get_world_3d()
	if world_3d.has_method("get_navigation_map"):
		return world_3d.get_navigation_map()
	return world_3d.navigation_map
