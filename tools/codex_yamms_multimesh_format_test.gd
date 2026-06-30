extends SceneTree

class MockPlacementMode:
	extends PlacementMode

	func generate() -> void:
		multimesh_item.instance_count = amount
		for index in range(amount):
			multimesh_item.set_instance_transform(index, Transform3D(Basis(), Vector3(index, 0.0, 0.0)))


func _init() -> void:
	print("=== YAMMS MultiMesh format test ===")
	var item := MultiScatterItem.new()
	root.add_child(item)
	var multi_mesh := MultiMesh.new()
	multi_mesh.transform_format = MultiMesh.TRANSFORM_2D
	multi_mesh.instance_count = 3
	multi_mesh.visible_instance_count = 3
	item.multimesh = multi_mesh

	item._prepare_multimesh()

	if item.multimesh == null:
		printerr("FAIL: MultiScatterItem should keep or create a MultiMesh.")
		quit(1)
		return
	if item.multimesh.instance_count != 0:
		printerr("FAIL: MultiMesh instance_count should be reset before generation.")
		quit(1)
		return
	if item.multimesh.transform_format != MultiMesh.TRANSFORM_3D:
		printerr("FAIL: MultiMesh transform_format should be TRANSFORM_3D.")
		quit(1)
		return

	item.amount = 3
	item.percentage = 100.0
	item.random = RandomNumberGenerator.new()
	item.curve = Curve3D.new()
	var placement := MockPlacementMode.new()
	item.add_child(placement)
	item.generate(Vector3.ZERO, null)

	if item.multimesh.instance_count != 3:
		printerr("FAIL: MultiMesh generation should create 3 instances.")
		quit(1)
		return
	if item.multimesh.visible_instance_count != 3:
		printerr("FAIL: MultiMesh generation should restore visible_instance_count to generated instances.")
		quit(1)
		return

	print("YAMMS_MULTIMESH_FORMAT OK")
	item.queue_free()
	await process_frame
	quit(0)
