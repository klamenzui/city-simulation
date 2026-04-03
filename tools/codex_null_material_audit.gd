extends SceneTree

func _init() -> void:
	var main_scene := load("res://Main.tscn")
	if main_scene == null:
		push_error("Failed to load Main.tscn")
		quit(1)
		return

	var main: Node = main_scene.instantiate()
	root.add_child(main)

	await process_frame
	await process_frame
	await process_frame

	var findings := _collect_null_material_surfaces(main)
	print("NULL_MATERIAL_SURFACES total=", findings.size())
	for finding in findings:
		print(
			"NULL_MATERIAL path=",
			str(finding.get("path", "")),
			" surface=",
			int(finding.get("surface", -1)),
			" mesh=",
			str(finding.get("mesh", "")),
			" override=",
			str(finding.get("override", false)),
			" base=",
			str(finding.get("base", false))
		)

	var invalid_materials := _collect_invalid_material_rids(main)
	print("INVALID_MATERIAL_RIDS total=", invalid_materials.size())
	for finding in invalid_materials:
		print(
			"INVALID_MATERIAL path=",
			str(finding.get("path", "")),
			" surface=",
			int(finding.get("surface", -1)),
			" slot=",
			str(finding.get("slot", "")),
			" class=",
			str(finding.get("class", "")),
			" name=",
			str(finding.get("name", ""))
		)

	var geometry_summary := _collect_geometry_summary(main)
	print("GEOMETRY_SUMMARY total=", geometry_summary.size())
	for finding in geometry_summary:
		print(
			"GEOMETRY path=",
			str(finding.get("path", "")),
			" class=",
			str(finding.get("class", "")),
			" detail=",
			str(finding.get("detail", ""))
		)

	var instance_shader_findings := _collect_instance_shader_nodes(main)
	print("INSTANCE_SHADER_NODES total=", instance_shader_findings.size())
	for finding in instance_shader_findings:
		print(
			"INSTANCE_SHADER path=",
			str(finding.get("path", "")),
			" props=",
			str(finding.get("props", []))
		)

	main.queue_free()
	await process_frame
	quit()

func _collect_null_material_surfaces(root_node: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	_collect_null_material_surfaces_recursive(root_node, out)
	return out

func _collect_null_material_surfaces_recursive(node: Node, out: Array[Dictionary]) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			for surface_idx in range(mesh_instance.mesh.get_surface_count()):
				var override_material := mesh_instance.get_surface_override_material(surface_idx)
				var base_material := mesh_instance.mesh.surface_get_material(surface_idx)
				if override_material == null and base_material == null:
					out.append({
						"path": str(mesh_instance.get_path()),
						"surface": surface_idx,
						"mesh": mesh_instance.mesh.resource_name,
						"override": override_material != null,
						"base": base_material != null,
					})
	for child in node.get_children():
		_collect_null_material_surfaces_recursive(child, out)

func _collect_geometry_summary(root_node: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	_collect_geometry_summary_recursive(root_node, out)
	return out

func _collect_geometry_summary_recursive(node: Node, out: Array[Dictionary]) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var surface_count := mesh_instance.mesh.get_surface_count() if mesh_instance.mesh != null else 0
		if surface_count >= 2:
			out.append({
				"path": str(mesh_instance.get_path()),
				"class": mesh_instance.get_class(),
				"detail": "surfaces=%d visible=%s" % [surface_count, str(mesh_instance.visible)],
			})
	elif node is MultiMeshInstance3D:
		var multimesh_instance := node as MultiMeshInstance3D
		var mesh_surface_count := 0
		var instance_count := 0
		if multimesh_instance.multimesh != null:
			instance_count = multimesh_instance.multimesh.instance_count
			if multimesh_instance.multimesh.mesh != null:
				mesh_surface_count = multimesh_instance.multimesh.mesh.get_surface_count()
		out.append({
			"path": str(multimesh_instance.get_path()),
			"class": multimesh_instance.get_class(),
			"detail": "mesh_surfaces=%d instances=%d visible=%s" % [
				mesh_surface_count,
				instance_count,
				str(multimesh_instance.visible),
			],
		})
	for child in node.get_children():
		_collect_geometry_summary_recursive(child, out)

func _collect_instance_shader_nodes(root_node: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	_collect_instance_shader_nodes_recursive(root_node, out)
	return out

func _collect_instance_shader_nodes_recursive(node: Node, out: Array[Dictionary]) -> void:
	if node is GeometryInstance3D:
		var props: Array[String] = []
		for property_info in node.get_property_list():
			var property_name := str(property_info.get("name", ""))
			if not property_name.begins_with("instance_shader_parameters/"):
				continue
			props.append(property_name)
		if not props.is_empty():
			out.append({
				"path": str(node.get_path()),
				"props": props,
			})
	for child in node.get_children():
		_collect_instance_shader_nodes_recursive(child, out)

func _collect_invalid_material_rids(root_node: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	_collect_invalid_material_rids_recursive(root_node, out)
	return out

func _collect_invalid_material_rids_recursive(node: Node, out: Array[Dictionary]) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			if mesh_instance.material_override != null and not mesh_instance.material_override.get_rid().is_valid():
				out.append({
					"path": str(mesh_instance.get_path()),
					"surface": -1,
					"slot": "material_override",
					"class": mesh_instance.material_override.get_class(),
					"name": mesh_instance.material_override.resource_name,
				})
			for surface_idx in range(mesh_instance.mesh.get_surface_count()):
				var override_material := mesh_instance.get_surface_override_material(surface_idx)
				if override_material != null and not override_material.get_rid().is_valid():
					out.append({
						"path": str(mesh_instance.get_path()),
						"surface": surface_idx,
						"slot": "surface_override",
						"class": override_material.get_class(),
						"name": override_material.resource_name,
					})
				var base_material := mesh_instance.mesh.surface_get_material(surface_idx)
				if base_material != null and not base_material.get_rid().is_valid():
					out.append({
						"path": str(mesh_instance.get_path()),
						"surface": surface_idx,
						"slot": "surface_base",
						"class": base_material.get_class(),
						"name": base_material.resource_name,
					})
	for child in node.get_children():
		_collect_invalid_material_rids_recursive(child, out)
