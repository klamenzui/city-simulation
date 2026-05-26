extends SceneTree

const MAIN_SCENE_PATH := "res://Main.tscn"
const GRASS_SCRIPT_PATH := "res://Scenes/Environment/ExteriorGrassDecorator.gd"
const GRASS_SCENE_PATH := "res://Scenes/Environment/Grass/grass.glb"
const GRASS_MATERIAL_PATH := "res://Scenes/Environment/Grass/Stylized3DGrass.tres"
const GRASS_SHADER_PATH := "res://Scenes/Environment/Grass/GrassShader.tres"

var _runtime_instance_count: int = 0


func _initialize() -> void:
	var errors: Array[String] = []
	await _check_main_scene_contract(errors)
	_check_grass_assets(errors)

	if not errors.is_empty():
		for error in errors:
			push_error(error)
		quit(FAILED)
		return

	print("Exterior grass probe passed: instances=%d." % _runtime_instance_count)
	quit(OK)


func _check_main_scene_contract(errors: Array[String]) -> void:
	var main_scene := load(MAIN_SCENE_PATH) as PackedScene
	if main_scene == null:
		errors.append("Could not load %s." % MAIN_SCENE_PATH)
		return

	var main := main_scene.instantiate()
	root.add_child(main)
	for _i in range(3):
		await physics_frame

	var grass := main.get_node_or_null(NodePath("World/ExteriorGrass"))
	if grass == null:
		errors.append("Main scene is missing World/ExteriorGrass.")
		main.free()
		return

	if grass.get_script() == null or grass.get_script().resource_path != GRASS_SCRIPT_PATH:
		errors.append("World/ExteriorGrass must use %s." % GRASS_SCRIPT_PATH)
	if grass is ExteriorGrassDecorator:
		_runtime_instance_count = grass.get_generated_instance_count()
		if _runtime_instance_count <= 0:
			errors.append("Exterior grass should generate visible MultiMesh instances at runtime.")
	var grass_multimesh := grass.get_node_or_null(NodePath("GrassMultiMesh")) as MultiMeshInstance3D
	if grass_multimesh == null:
		errors.append("Exterior grass should create a GrassMultiMesh child at runtime.")
	elif grass_multimesh.multimesh == null or grass_multimesh.multimesh.instance_count <= 0:
		errors.append("GrassMultiMesh should contain a populated MultiMesh.")
	if _count_nodes_of_type(grass, StaticBody3D) > 0:
		errors.append("Exterior grass must stay visual-only and contain no StaticBody3D.")
	if _count_nodes_of_type(grass, CollisionShape3D) > 0:
		errors.append("Exterior grass must not add CollisionShape3D nodes.")
	if grass.is_in_group("buildings") or grass.is_in_group("walkable_surface"):
		errors.append("Exterior grass must not register as a building or walkable surface.")

	main.free()
	await process_frame


func _check_grass_assets(errors: Array[String]) -> void:
	var material := load(GRASS_MATERIAL_PATH) as ShaderMaterial
	if material == null:
		errors.append("Could not load grass material %s." % GRASS_MATERIAL_PATH)
	var shader := load(GRASS_SHADER_PATH) as Shader
	if shader == null:
		errors.append("Could not load grass shader %s." % GRASS_SHADER_PATH)

	var grass_scene := load(GRASS_SCENE_PATH) as PackedScene
	if grass_scene == null:
		errors.append("Could not load grass mesh scene %s." % GRASS_SCENE_PATH)
		return

	var scene_root := grass_scene.instantiate()
	if _find_first_mesh(scene_root) == null:
		errors.append("Grass mesh scene does not contain a MeshInstance3D with a Mesh.")
	scene_root.free()


func _find_first_mesh(node: Node) -> Mesh:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			return mesh_instance.mesh
	for child in node.get_children():
		var mesh := _find_first_mesh(child)
		if mesh != null:
			return mesh
	return null


func _count_nodes_of_type(node: Node, type_ref: Variant) -> int:
	var count := 0
	if is_instance_of(node, type_ref):
		count += 1
	for child in node.get_children():
		count += _count_nodes_of_type(child, type_ref)
	return count
