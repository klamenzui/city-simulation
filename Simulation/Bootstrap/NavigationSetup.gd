extends RefCounted
class_name NavigationSetup

static func ensure_region(root: Node3D, world: World, region_name: String = "NavigationRegion3D") -> void:
	if root == null or world == null:
		return
	if root.get_node_or_null(region_name) != null:
		return

	var scale_abs := Vector3(absf(world.scale.x), absf(world.scale.y), absf(world.scale.z))
	var world_size := world.size * scale_abs
	var half_x: float = maxf(world_size.x * 0.5 - 1.0, 6.0)
	var half_z: float = maxf(world_size.z * 0.5 - 1.0, 6.0)
	var nav_y: float = world.global_position.y + world_size.y * 0.5 + 0.02

	var nav_mesh := NavigationMesh.new()
	nav_mesh.agent_height = 1.8
	nav_mesh.agent_radius = 0.35
	nav_mesh.cell_size = 0.25
	nav_mesh.cell_height = 0.25
	nav_mesh.vertices = PackedVector3Array([
		Vector3(-half_x, nav_y, -half_z),
		Vector3(half_x, nav_y, -half_z),
		Vector3(half_x, nav_y, half_z),
		Vector3(-half_x, nav_y, half_z)
	])
	nav_mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))

	var nav_region := NavigationRegion3D.new()
	nav_region.name = region_name
	nav_region.navigation_mesh = nav_mesh
	root.add_child(nav_region)