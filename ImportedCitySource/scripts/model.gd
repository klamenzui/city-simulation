extends Node3D
class_name Model

# Side connection properties
@export var front: Dictionary = {"connectable_modules": ["all"], "connectable": true, "type": "none"}
@export var back: Dictionary = {"connectable_modules": ["all"], "connectable": true, "type": "none"}
@export var left: Dictionary = {"connectable_modules": ["all"], "connectable": true, "type": "none"}
@export var right: Dictionary = {"connectable_modules": ["all"], "connectable": true, "type": "none"}
@export var top: Dictionary = {"connectable_modules": ["all"], "connectable": true, "type": "none"}
@export var bottom: Dictionary = {"connectable_modules": ["all"], "connectable": true, "type": "none"}

# Mesh and dimensions
@export var mesh_instance: MeshInstance3D
@export var width: float = 1.0
@export var height: float = 1.0
@export var length: float = 1.0

# Rotation state in 90-degree increments (0 = 0°, 1 = 90°, 2 = 180°, 3 = 270°)
var rotation_state: int = 0
var sides: Array = ["front", "back", "left", "right", "top", "bottom"]

# Returns the actual side name considering rotation
func get_rotated_side(side: String) -> String:
	var horizontal_sides: Array = ["front", "right", "back", "left"]
	var index: int = horizontal_sides.find(side)
	
	if index == -1:
		return side  # Return unchanged for top/bottom
	
	return horizontal_sides[int(round(index + rotation_state / 90)) % 4]

# Returns the opposite side
func get_opposite_side(side: String) -> String:
	match side:
		"front": return "back"
		"back": return "front"
		"left": return "right"
		"right": return "left"
		"top": return "bottom"
		"bottom": return "top"
	return side  # Default return if invalid side

# Recursively finds the first mesh instance in the node tree
func find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
		
	for child in node.get_children():
		var mesh := find_mesh(child)
		if mesh:
			return mesh
			
	return null

# Loads dimensions from a mesh instance's bounding box
func load_dimensions_from_model(mesh_inst: MeshInstance3D) -> void:
	if not mesh_inst:
		push_warning("Cannot load dimensions: no mesh instance provided")
		return
		
	if not mesh_inst.get_aabb():
		push_warning("Cannot load dimensions: mesh has no bounding box")
		return
		
	var aabb := mesh_inst.get_aabb()
	self.width = snappedf(aabb.size.x, 0.001)
	self.height = snappedf(aabb.size.y, 0.001)
	self.length = snappedf(aabb.size.z, 0.001)
