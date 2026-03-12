extends Model
class_name RoadPart

# Road types
enum FormType {STRAIGHT, CORNER, TSPLIT, JUNCTION}

# Configuration
@export var form_type: FormType = FormType.STRAIGHT
@export var file_name := ""
var models_folder = "res://ImportedCitySource/assets/roads/"
var model: Node3D = null
var crossing = null
var pos := Vector2.ZERO
var world: Node3D = null
var direction = ""
@export var main_group:= "road"
# Connection data
var connections = {
	"front": null,
	"right": null,
	"back": null,
	"left": null
}

# Initialize with world and position
func _init(_world: Node3D, _pos: Vector2) -> void:
	world = _world
	pos = _pos

# Get form type name
func get_form_type_name(type: FormType) -> String:
	return FormType.keys()[type]

# Check if road has a connection in the specified direction
func has_connection(side: String) -> bool:
	return connections[side] != null

# Add decorations to the road (traffic lights, street lamps, etc.)
func decorate() -> void:
	# Only decorate straight roads
	if self.form_type != FormType.STRAIGHT:
		return
	
	# Decoration parameters
	var module_name = "streetlight.gltf"
	var _rotation = PI/2
	var move_offset = Vector2(0, -1)
	
	# Special handling for intersections with traffic lights
	if crossing:
		module_name = "trafficlight_C.gltf"
		move_offset = Vector2.ZERO
		
		# Configuration for traffic lights at different crossing positions
		var crossing_configs = {
			"front":  {"_rotation": deg_to_rad(-360), "offset": Vector2(1, -0.3)},
			"back":   {"_rotation": deg_to_rad(180),  "offset": Vector2(-1, 0.3)},
			"left":   {"_rotation": deg_to_rad(-90),  "offset": Vector2(0.3, 1)},
			"right":  {"_rotation": deg_to_rad(90),   "offset": Vector2(-0.3, -1)}
		}
		
		if crossing in crossing_configs:
			var config = crossing_configs[crossing]
			_rotation = config._rotation
			move_offset = config.offset
	else:
		# Street lamp positioning for regular roads
		if has_connection("front"):
			_rotation = deg_to_rad(180)
			move_offset.x = -1
	
	# Calculate decoration position
	var _pos = Vector2(pos.x + move_offset.x, pos.y + move_offset.y)
	
	# Load and place decoration
	_place_decoration(module_name, _pos, _rotation)

# Place a decoration at the specified position
func _place_decoration(module_name: String, _pos: Vector2, _rotation: float) -> void:
	# Load decoration model
	var decoration = load_module(module_name)
	if not decoration:
		push_warning("Could not load decoration: " + module_name)
		return
	
	# Set rotation and position
	decoration.rotation.y = _rotation
	decoration.transform.origin = Vector3(_pos.x, 0, _pos.y)
	
	# Group management for cleanup
	var _main_group = "deco"
	var group = _main_group + ":" + str(pos.x) + ",0," + str(pos.y)
	
	# Clean up existing decorations
	clear_position(_main_group)
	
	# Add new decoration
	decoration.add_to_group(_main_group)
	decoration.add_to_group(group)
	world.add_child(decoration)

# Clear nodes at a position with specified prefix
func clear_position(prefix: String) -> void:
	var group = prefix + ":" + str(pos.x) + ",0," + str(pos.y)
	for existing_node in world.get_children():
		if existing_node.is_in_group(group):
			world.remove_child(existing_node)
			existing_node.queue_free()

# Get next connected positions
func next_connections(other: RoadPart) -> Array:
	var positions = []
	var _direction = determine_connection_direction(other)
	for c in connections:
		if c != _direction and connections[c] != null:
			positions.append(connections[c])
	return positions

# Connect this road to another
func connect_road(other: RoadPart) -> void:
	# Determine relative position
	var _direction = determine_connection_direction(other)
	if _direction == "":
		return
		
	direction = _direction
	
	# Update connections
	connections[direction] = other.pos
	var opposite = get_opposite_direction(direction)
	other.connections[opposite] = pos
	
	# Update models
	update_model()
	other.update_model()

# Determine the connection direction to another road
func determine_connection_direction(other: RoadPart) -> String:
	# Calculate relative position
	var diff = other.pos - pos
	
	# Normalize to cardinal directions
	if abs(diff.x) > abs(diff.y):
		return "right" if diff.x > 0 else "left"
	else:
		return "front" if diff.y > 0 else "back"

# Get opposite direction (static method)
static func get_opposite_direction(_direction: String) -> String:
	match _direction:
		"front": return "back"
		"back": return "front"
		"left": return "right"
		"right": return "left"
		_: return ""

# Update road model based on connections
func update_model() -> void:
	var connection_count = count_connections()
	var model_name = ""
	var ext = ".gltf"
	self.form_type = FormType.STRAIGHT
	
	# Choose model based on connection count and pattern
	match connection_count:
		0, 1:
			model_name = "road_straight" + ext
		2:
			if are_opposite_connections():
				if crossing:
					model_name = "road_straight_crossing" + ext
				else:
					model_name = "road_straight" + ext
			else:
				self.form_type = FormType.CORNER
				model_name = "road_corner_curved" + ext
		3:
			self.form_type = FormType.TSPLIT
			model_name = "road_tsplit" + ext
		4:
			self.form_type = FormType.JUNCTION
			model_name = "road_junction" + ext
	
	# Load and place model
	if model_name != "":
		file_name = model_name
		load_and_rotate_model(model_name)

# Count active connections
func count_connections() -> int:
	var count = 0
	for connected in connections.values():
		if connected != null:
			count += 1
	return count

# Check if connections are on opposite sides
func are_opposite_connections() -> bool:
	return (has_connection("front") and has_connection("back")) or \
		(has_connection("left") and has_connection("right"))

# Load and rotate the road model
func load_and_rotate_model(model_name: String) -> void:
	var new_model = load_module(model_name)
	if new_model:
		# Set rotation based on connections
		var _rotation = calculate_rotation()
		new_model.rotation.y = _rotation
		model = new_model
		
		# Position and group management
		var group = main_group + ":" + str(pos.x) + ",0," + str(pos.y)
		model.transform.origin = Vector3(pos.x, 0, pos.y)
		
		# Clean up existing road
		clear_position(main_group)
		
		# Add new road
		model.add_to_group(main_group)
		model.add_to_group(group)
		world.add_child(model)

# Calculate rotation based on connections
func calculate_rotation() -> float:
	match count_connections():
		1:
			# Single connection - rotate toward the connected side
			for _direction in connections:
				if has_connection(_direction):
					return get_rotation_for_direction(_direction)
		2:
			if are_opposite_connections():
				# Straight road
				if has_connection("front") and has_connection("back"):
					return 0.0
				else:  # left and right
					return PI/2
			else:
				# Corner - find the two connected sides
				var connected_dirs = []
				for _direction in connections:
					if has_connection(_direction):
						connected_dirs.append(_direction)
				return get_rotation_for_corner(connected_dirs[0], connected_dirs[1])
		3:
			# T-junction - find the unconnected side
			for _direction in connections:
				if not has_connection(_direction):
					return get_rotation_for_tsplit(_direction) + deg_to_rad(-90)
	return 0.0

# Get rotation for a direction (static method)
static func get_rotation_for_direction(_direction: String) -> float:
	match _direction:
		"front": return 0.0
		"right": return PI/2
		"back": return PI
		"left": return -PI/2
	return 0.0

# Get rotation for a corner connection
func get_rotation_for_corner(dir1: String, dir2: String) -> float:
	# Lookup table for corner rotations
	var corner_rotations = {
		"front_right": 0.0,
		"right_front": 0.0,
		"right_back": PI/2,
		"back_right": PI/2,
		"back_left": PI,
		"left_back": PI,
		"left_front": -PI/2,
		"front_left": -PI/2
	}
	
	var key = dir1 + "_" + dir2
	if corner_rotations.has(key):
		return corner_rotations[key]
	return 0.0

# Get rotation for a T-split
func get_rotation_for_tsplit(blocked_direction: String) -> float:
	match blocked_direction:
		"front": return PI
		"right": return -PI/2
		"back": return 0.0
		"left": return PI/2
	return 0.0

# Get the road model
func get_model() -> Node3D:
	return model if model else null

# Load a model module
func load_module(module_name: String) -> Node3D:
	var module_path = models_folder + module_name
	var loaded_scene = load(module_path)
	if not loaded_scene:
		push_error('Module could not be loaded: ' + module_path)
		return null

	var module = loaded_scene.instantiate()
	if not module:
		push_error('Module could not be instantiated: ' + module_path)
		return null
	return module
