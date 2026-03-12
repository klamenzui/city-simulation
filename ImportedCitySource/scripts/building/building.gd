extends ModelLoader
enum BuildingType {COMMERCIAL, RESIDENTIAL, MIX}

var max_floors: int = 4
var floors: Array = []
var modules_by_type: Dictionary = {}
var building_type: BuildingType = BuildingType.RESIDENTIAL
var part: BuildingPart = BuildingPart.new()
var is_complete: bool = false
var _dimension: Vector3 = Vector3.ZERO
var _position: Vector3 = Vector3.ZERO
var foundation_path = "res://ImportedCitySource/assets/city/base.gltf"
@export var main_group:= "building"
func _init() -> void:
	models_folder = "res://ImportedCitySource/assets/buildings_parts/"
	files_filter = ['building', 'roof']
	script_path = "res://ImportedCitySource/scripts/building_part.gd"
	add_to_group(main_group)
	
# Builds a building of the specified type
func build(_building_type: BuildingType = BuildingType.MIX) -> void:
	building_type = _building_type
	
	if building_type == BuildingType.MIX:
		_build_mixed_building()
		return
		
	_build_modular_building()

# Builds a pre-designed mixed building
func _build_mixed_building() -> void:
	models_folder = "res://ImportedCitySource/assets/buildings/"
	var letters: Array = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L"]
	var letter = letters[randi() % letters.size()]
	var file_name: String = "building_"
	if letter in ["I", "J", "K", "L"]: # add base
		add_child(load_module(foundation_path))
	add_child(load_module(file_name + letter))

# Builds a modular building from individual parts
func _build_modular_building() -> void:
	add_child(load_module(foundation_path))
	
	if building_type == BuildingType.COMMERCIAL:
		max_floors = 3
		
	var floors_count: int = randi() % max_floors + 1
	
	# Initialize modules_by_type with empty arrays for each BlockType
	for t in BuildingPart.BlockType.values():
		var type_name: String = part.get_block_type_name(t)
		modules_by_type[type_name] = []
		
	load_modules_from_folder()
	
	for i in floors_count + 1:
		var module: BuildingPart = find_module(i, floors_count)
		if module:
			floors.append(module)
			module.visible = true
			add_child(module)
			module.transform.origin = Vector3(
				snappedf(_position.x, 0.001),
				snappedf(_dimension.y, 0.001),
				snappedf(_position.z, 0.001)
			)
			_dimension.y += snappedf(module.height, 0.001)
			_dimension.x = module.width
			_dimension.z = module.length
	
	is_complete = floors.size() == floors_count + 1

# Finds an appropriate module for the given floor
func find_module(floor_num: int, max_floor: int) -> BuildingPart:
	var block_type: int = BuildingPart.BlockType.GROUND_FLOOR
	var prev_module: BuildingPart = null
	
	if floor_num == max_floor:
		block_type = BuildingPart.BlockType.ROOF
	elif floor_num > 0:
		block_type = BuildingPart.BlockType.MIDDLE
	
	if floor_num > 0 and floors.size() > floor_num - 1:
		prev_module = floors[floor_num - 1]
	
	var type_name: String = part.get_block_type_name(block_type)
	var retries: int = 4
	
	while retries >= 0:
		var module: BuildingPart = get_random_module(type_name, prev_module)
		if module and module.can_connect(prev_module, "bottom"):
			var m: BuildingPart = module.duplicate()
			if m:
				m.init()
				return m
		retries -= 1
	
	push_warning("No suitable module found for floor %d of type %s" % [floor_num, type_name])
	return null

# Gets a random module of the specified type compatible with the previous module
func get_random_module(block_type: String, prev_module: BuildingPart) -> BuildingPart:
	var modules_list: Array = modules_by_type.get(block_type, [])
	if modules_list.is_empty():
		push_warning("No modules found for type: %s" % block_type)
		return null
		
	var filtered: Array = []
	if prev_module:
		for mname in modules_list:
			if modules[mname].form_type == prev_module.form_type:
				filtered.append(mname)
	else:
		filtered = modules_list
	
	if filtered.is_empty():
		return null
		
	var i: int = randi() % filtered.size()
	return modules[filtered[i]]

# Loads a module and categorizes it by type
func load_module(module_name: String) -> Node3D:
	# Skip incompatible modules based on building type
	if module_name.begins_with("roof"):
		if "awning" in module_name and building_type != BuildingType.COMMERCIAL:
			return null
		elif building_type == BuildingType.COMMERCIAL and not "awning" in module_name:
			return null
		 
	var module: Node3D = super.load_module(module_name)
	if not module:
		return null
		
	# Add the module to its type category
	var part_module: BuildingPart = module as BuildingPart
	if part_module:
		var type_name: String = part.get_block_type_name(part_module.block_type)
		if not modules_by_type.has(type_name):
			modules_by_type[type_name] = []
		modules_by_type[type_name].append(module_name)
		
	return module
