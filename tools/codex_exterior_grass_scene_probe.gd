extends SceneTree

const MAIN_SCENE_PATH := "res://Main.tscn"
const SCATTER_ROOT_PATH := NodePath("World/MeadowPlantsScatter")
const GRASS_ITEM_PATH := NodePath("World/MeadowPlantsScatter/GrassItem")
const GRASS_SCENE_PATH := "res://Scenes/Environment/Grass/grass.glb"
const GRASS_MATERIAL_PATH := "res://Scenes/Plants/Biomes/Stylized3DGrass.tres"
const GRASS_SHADER_PATH := "res://Scenes/Plants/Biomes/GrassShader.tres"

var _grass_instance_budget: int = 0


func _initialize() -> void:
	var errors: Array[String] = []
	await _check_main_scene_contract(errors)
	_check_grass_assets(errors)

	if not errors.is_empty():
		for error in errors:
			push_error(error)
		quit(FAILED)
		return

	print("Scatter grass probe passed: budget=%d." % _grass_instance_budget)
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

	if main.get_node_or_null(NodePath("World/ExteriorGrass")) != null:
		errors.append("Main scene should use scatter grass, not legacy World/ExteriorGrass.")

	var scatter := main.get_node_or_null(SCATTER_ROOT_PATH)
	if scatter == null:
		errors.append("Main scene is missing %s." % str(SCATTER_ROOT_PATH))
		main.free()
		return
	if _count_nodes_of_type(scatter, StaticBody3D) > 0:
		errors.append("Scatter grass must stay visual-only and contain no StaticBody3D.")
	if _count_nodes_of_type(scatter, CollisionShape3D) > 0:
		errors.append("Scatter grass must not add CollisionShape3D nodes.")
	if scatter.is_in_group("buildings") or scatter.is_in_group("walkable_surface"):
		errors.append("Scatter grass must not register as a building or walkable surface.")

	var grass_item := main.get_node_or_null(GRASS_ITEM_PATH) as MultiMeshInstance3D
	if grass_item == null:
		errors.append("Main scene is missing %s." % str(GRASS_ITEM_PATH))
		main.free()
		return
	if grass_item.multimesh == null or grass_item.multimesh.mesh == null:
		errors.append("GrassItem should contain a MultiMesh with a mesh.")
	else:
		_grass_instance_budget = grass_item.multimesh.instance_count
	if grass_item.material_override == null or grass_item.material_override.resource_path != GRASS_MATERIAL_PATH:
		errors.append("GrassItem should use %s as material_override." % GRASS_MATERIAL_PATH)

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
