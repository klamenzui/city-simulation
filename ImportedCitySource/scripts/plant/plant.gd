extends ModelLoader
class_name Plant

enum PlantType {TREE, BUSH, FLOWER, WEED}

var modules_by_type: Dictionary = {}
var plant_type: PlantType = PlantType.TREE
# var _dimension: Vector3 = Vector3.ZERO
# var _position: Vector3 = Vector3.ZERO
@export var main_group:= "plant"
func _init() -> void:
	models_folder = "res://ImportedCitySource/assets/plants/"
	add_to_group(main_group)

# Returns the string name of a plant type enum value
func get_type_name(type: PlantType) -> String:
	return PlantType.keys()[type]

# Creates a plant of the specified type
func plant(_plant_type: PlantType = PlantType.TREE) -> void:
	plant_type = _plant_type
	load_modules_from_folder()
	
	var module = find_module()
	if module:
		add_child(module)
	else:
		push_warning("Could not find a suitable module for plant type: %s" % get_type_name(plant_type))

# Finds an appropriate module for the plant type
func find_module() -> Node3D:
	var type_name: String = get_type_name(plant_type)
	return get_random_module(type_name)

# Gets a random module of the specified type
func get_random_module(type_name: String) -> Node3D:
	var modules_list: Array = modules_by_type.get(type_name, [])
	if modules_list.is_empty():
		push_warning("No modules found for type: %s" % type_name)
		return null
		
	var i: int = randi() % modules_list.size()
	return modules[modules_list[i]]

# Gets the plant type based on the file name
func get_type_by_file_name(file_name: String) -> String:
	for k in PlantType.keys():
		var key_lower: String = k.to_lower()
		if file_name.to_lower().begins_with(key_lower):
			return k
	return ""

# Loads a module and categorizes it by type
func load_module(module_name: String) -> Node3D:
	var type_name: String = get_type_by_file_name(module_name)
	if not type_name:
		return null
		
	var module: Node3D = super.load_module(module_name)
	if not module:
		return null
		
	if not modules_by_type.has(type_name):
		modules_by_type[type_name] = []
		
	modules_by_type[type_name].append(module_name)
	return module
