extends Node3D
class_name ModelLoader

# Module storage and configuration
var modules := {}
var files_filter := []
var models_folder := ""
var script_path := ""

# Load all modules from the specified folder
func load_modules_from_folder() -> void:
	modules.clear()
	
	var dir := DirAccess.open(models_folder)
	if !dir:
		push_error("Folder not found: " + models_folder)
		return
		
	dir.list_dir_begin()
	var file_name := dir.get_next()
	
	while file_name != "":
		# Apply filters if specified
		var is_module = true
		if files_filter:
			is_module = false
			for filter in files_filter:
				if file_name.begins_with(filter):
					is_module = true
					break
					
		# Load valid model files
		if !dir.current_is_dir() and file_name.get_extension().to_lower() in ["glb", "gltf"] and is_module:
			load_module(file_name)
			
		file_name = dir.get_next()
		
	dir.list_dir_end()

# Load a single module
func load_module(module_name: String) -> Node3D:
	# Handle absolute paths
	var module_path = models_folder
	# + ".gltf" or ".glb"
	if module_name.begins_with("res://ImportedCitySource/"):
		module_path = ""
	module_path += module_name
	if not FileAccess.file_exists(module_path):
		var exts = [".gltf", ".glb"]
		var valid_ext = false
		for ext in exts:
			if module_path.ends_with(ext):
				valid_ext = true
				break
		if not valid_ext:
			for ext in exts:
				if FileAccess.file_exists(module_path + ext):
					module_path += ext
					valid_ext = true
					break
		if not valid_ext:
			push_error('Module could not be loaded by path: ' + module_path)
			return null
	
	# Load the scene
	var loaded_scene = load(module_path)
	if not loaded_scene:
		push_error('Module could not be loaded: ' + module_path)
		return null
	
	# Instantiate the scene
	var module = loaded_scene.instantiate()
	if not module:
		push_error('Module could not be instantiated: ' + module_path)
		return null
	
	# Apply script if specified
	if script_path:
		var script := load(script_path)
		if not script:
			push_error('Script could not be loaded: ' + script_path)
			return null
		
		# Assign script to module
		module.set_script(script)
		
		# Initialize module
		module.init()
	modules[module_name] = module
	return module
	
