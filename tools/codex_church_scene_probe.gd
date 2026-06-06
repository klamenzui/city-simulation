extends SceneTree

const CHURCH_SCENE_PATH := "res://Scenes/CityBuildings/landmarks/church.tscn"
const MAIN_SCENE_PATH := "res://Main.tscn"
const MAIN_CHURCH_PATH := "World/City/only_people_nav/only_people/Services/Church"


func _initialize() -> void:
	var errors: Array[String] = []
	var scene := load(CHURCH_SCENE_PATH) as PackedScene
	if scene == null:
		errors.append("Could not load %s." % CHURCH_SCENE_PATH)
	else:
		var church := scene.instantiate()
		if church is not Church:
			errors.append("%s root should instantiate as Church." % CHURCH_SCENE_PATH)
		else:
			root.add_child(church)
			await process_frame
			_check_church_contract(church as Church, errors)
			church.free()

	_check_main_scene_contains_church(errors)

	if not errors.is_empty():
		for error in errors:
			push_error(error)
		quit(FAILED)
		return

	print("Church scene probe passed.")
	quit(OK)


func _check_church_contract(church: Church, errors: Array[String]) -> void:
	if church.name != "Church":
		errors.append("Church scene root should be named Church.")
	if not church.is_in_group("buildings"):
		errors.append("Church must register in the buildings group.")
	if not church.is_in_group("building_use_church"):
		errors.append("Church must use the standard building_use_church group.")
	if church.building_type != Building.BuildingType.CHURCH:
		errors.append("Church building_type should be CHURCH.")
	if church.get_building_type_name() != "Church":
		errors.append("Church building type name should be Church.")
	if church.get_service_type() != "community":
		errors.append("Church service type should be community.")
	if church.capacity <= 0:
		errors.append("Church should have positive visitor capacity.")
	if church.job_capacity != 0:
		errors.append("Church should not create jobs until gameplay for it exists.")

	var entrance := church.get_node_or_null(NodePath("Entrance")) as Marker3D
	if entrance == null:
		errors.append("Church is missing Entrance Marker3D.")
	elif church.entrance != entrance:
		errors.append("Church exported entrance should reference Entrance.")

	if church.get_node_or_null(NodePath("Church")) is not MeshInstance3D:
		errors.append("Church scene should keep the imported Church mesh.")
	if _count_nodes_of_type(church, StaticBody3D) <= 0:
		errors.append("Church scene should include collision bodies.")
	if _count_nodes_of_type(church, CollisionShape3D) <= 0:
		errors.append("Church scene should include collision shapes.")
	if church.get_node_or_null(NodePath("EntranceTrigger")) == null:
		errors.append("Church should create an EntranceTrigger from Building._ready().")
	if _count_nodes_of_type(church, Camera3D) > 0:
		errors.append("Church must not contain a Camera3D; city cameras own rendering.")


func _check_main_scene_contains_church(errors: Array[String]) -> void:
	var file := FileAccess.open(MAIN_SCENE_PATH, FileAccess.READ)
	if file == null:
		errors.append("Could not read %s." % MAIN_SCENE_PATH)
		return
	var text := file.get_as_text()
	if not text.contains('path="res://Scenes/CityBuildings/landmarks/church.tscn"'):
		errors.append("Main scene should reference %s." % CHURCH_SCENE_PATH)
	if not text.contains('[node name="Church" parent="%s"' % MAIN_CHURCH_PATH.get_base_dir()):
		errors.append("Main scene should instance Church at %s." % MAIN_CHURCH_PATH)


func _count_nodes_of_type(node: Node, type_ref: Variant) -> int:
	var count := 0
	if is_instance_of(node, type_ref):
		count += 1
	for child in node.get_children():
		count += _count_nodes_of_type(child, type_ref)
	return count
