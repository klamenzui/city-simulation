extends Model
class_name BuildingPart

enum FormType {BLOCK, CORNER, EDGES}
enum BlockType {GROUND_FLOOR, MIDDLE, ROOF}

@export var form_type: FormType = FormType.BLOCK
@export var block_type: BlockType = BlockType.MIDDLE
@export var has_window: bool = false
@export var has_door: bool = false
@export var min_floor: int = 0  # Minimum floor placement
@export var max_floor: int = 3  # Maximum floor placement
var config_data: Dictionary = {}  # Configuration data

func get_form_type_name(type: FormType) -> String:
	return FormType.keys()[type]
	
func get_block_type_name(type: BlockType) -> String:
	return BlockType.keys()[type]

# Initialize the building part with correct type properties
func init() -> BuildingPart:
	mesh_instance = find_mesh(self)
	if mesh_instance:
		load_dimensions_from_model(mesh_instance)
	else:
		push_warning("Mesh not found in building part, dimensions can't be set automatically")
	
	# Determine block type from name
	_set_block_type_from_name()
	
	# Determine form type from name
	_set_form_type_from_name()
	
	# Configure block properties based on type
	_configure_block_properties()
	
	return self

# Set the block type based on the node name
func _set_block_type_from_name() -> void:
	var type_indicators := {
		"steps": BlockType.GROUND_FLOOR,
		"door": BlockType.GROUND_FLOOR,
		"roof": BlockType.ROOF
	}
	
	for key in type_indicators:
		if key in self.name:
			self.block_type = type_indicators[key]
			break

# Set the form type based on the node name
func _set_form_type_from_name() -> void:
	if "corner" in self.name:
		self.form_type = FormType.CORNER
	# Uncomment if needed:
	# elif "edges" in self.name:
	#	self.form_type = FormType.EDGES

# Configure the block properties based on its type
func _configure_block_properties() -> void:
	# Window detection
	if "window" in self.name:
		self.has_window = true
		self.front["connectable"] = false
	
	# Ground floor specific configuration
	if self.block_type == BlockType.GROUND_FLOOR:
		self.has_door = true
		self.bottom["connectable"] = false
		self.front["connectable"] = false
		self.max_floor = 0
	
	# Middle floor specific configuration
	if self.block_type == BlockType.MIDDLE:
		self.min_floor = 1
		if not self.has_window:  # Don't use blocks without windows
			self.bottom["connectable"] = false
	
	# Roof specific configuration
	if self.block_type == BlockType.ROOF:
		self.top["connectable"] = false
		self.min_floor = 1

#func _ready() -> void:
	#load_config("res://ImportedCitySource/config.json")
	#apply_config_to_side_features()
	#add_to_group(main_group)

# Ensures material is properly set up
func ensure_material() -> void:
	if mesh_instance and mesh_instance.get_surface_override_material(0) == null:
		var shader_material = ShaderMaterial.new()
		shader_material.shader = preload("res://ImportedCitySource/materials/tint_shader.gdshader")
		mesh_instance.set_surface_override_material(0, shader_material)

# Sets color for preview
func set_preview_color(color: Color) -> void:
	if not mesh_instance:
		return
		
	var material = mesh_instance.get_surface_override_material(0)
	if material:
		material.set_shader_parameter("tint_color", color)

# Saves configuration to JSON
func save_to_json(file_path: String) -> void:
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file:
		var json = JSON.stringify(config_data, "\t")
		file.store_string(json)
		file.close()
	else:
		push_error("Error saving file: %s" % file_path)

# Loads configuration from JSON
#func load_config(file_path: String) -> void:
#	if not FileAccess.file_exists(file_path):
#		push_warning("Configuration file not found: %s" % file_path)
#		return
#		
#	var file = FileAccess.open(file_path, FileAccess.READ)
#	if file:
#		var json = JSON.new()
#		var result = json.parse(file.get_as_text())
#		if result == OK:
#			config_data = json.get_data()
#		else:
#			push_error("Error parsing configuration file: %s" % json.get_error_message())
#		file.close()

# Applies configuration to side features
#func apply_config_to_side_features() -> void:
#	if config_data.has(name):
#		var module_config = config_data[name]
#		for side in sides:
#			if module_config.has(side):
#				self[side] = module_config[side]

# Checks if a connection is possible on a specified side
func can_connect(other: BuildingPart = null, side: String = "") -> bool:
	# Allow ground connection only for ground floor
	if not other:
		return self.min_floor == 0
		
	# Validate parameters
	if side == "":
		push_warning("Side is not defined for connection check")
		return false
		
	# Check form type compatibility
	if form_type != other.form_type:
		return false
		
	# Get the actual side considering rotation
	var actual_side := get_rotated_side(side)
	
	# Check if side exists and is connectable
	if not self.get(actual_side):
		return false
		
	var side_data = self[actual_side]
	if not side_data["connectable"]:
		return false
		
	# Check if the other module is allowed to connect
	var allowed_modules = side_data["connectable_modules"]
	var other_module_name := other.name
	
	if "all" in allowed_modules:
		return true
		
	return other_module_name in allowed_modules
