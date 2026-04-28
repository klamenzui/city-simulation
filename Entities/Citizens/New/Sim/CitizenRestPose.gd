class_name CitizenRestPose
extends RefCounted

## First Sim-layer component, extracted from old `Citizen.gd` (lines ~1276–1311).
##
## Encapsulates the bench/park rest-pose state — when a citizen sits on a bench
## or rests in a park spot, the rest pose freezes its position + yaw and the
## movement layer is told to stop driving. Pure data + a few small operations.
##
## Owner is `Node3D` (typically the CitizenController CharacterBody3D, but the
## component does not depend on movement specifics — only `global_position`
## and `rotation.y`).
##
## Future extension: snap-to-ground on `clear()` was previously inlined in
## `Citizen.set_position_grounded`. Once a Movement-API helper is exposed on
## CitizenController, plug it in here.

var owner_node: Node3D = null

var _active: bool = false
var _position: Vector3 = Vector3.ZERO
var _yaw: float = 0.0


func _init(p_owner: Node3D) -> void:
	owner_node = p_owner


## True iff the citizen has a rest pose set (sitting, standing in a park spot).
func is_active() -> bool:
	return _active


func get_position() -> Vector3:
	return _position


func get_yaw() -> float:
	return _yaw


## Sets a new rest pose. Caller is responsible for stopping movement
## (`stop_travel`) — this component only stores the pose.
func set_pose(target_pos: Vector3, yaw: float = 0.0) -> void:
	_active = true
	_position = target_pos
	_yaw = yaw


## Clears the rest pose. `snap_to_ground` is reserved for the future
## ground-probe call; today it is a no-op.
func clear(_snap_to_ground: bool = false) -> void:
	_active = false


## Applies the stored pose to the owner_node's transform. Idempotent —
## callers may invoke each frame while the pose is active.
func apply() -> void:
	if not _active or owner_node == null:
		return
	owner_node.global_position = _position
	var rot := owner_node.rotation
	rot.y = _yaw
	owner_node.rotation = rot
