extends RefCounted
class_name NavigationSetup

static func ensure_region(root: Node3D, world: World, region_name: String = "NavigationRegion3D") -> void:
	if root == null or world == null:
		return
	if has_dedicated_pedestrian_nav(root):
		return
	if root.get_node_or_null(region_name) != null:
		return

	var bounds := world.get_world_bounds()
	var center := bounds.position + bounds.size * 0.5
	var half_x: float = maxf(bounds.size.x * 0.5 - 1.0, 6.0)
	var half_z: float = maxf(bounds.size.z * 0.5 - 1.0, 6.0)
	var nav_y: float = world.get_ground_fallback_y() + 0.02

	var nav_mesh := NavigationMesh.new()
	nav_mesh.agent_height = 1.8
	nav_mesh.agent_radius = 0.35
	nav_mesh.cell_size = 0.25
	nav_mesh.cell_height = 0.25
	nav_mesh.vertices = PackedVector3Array([
		Vector3(center.x - half_x, nav_y, center.z - half_z),
		Vector3(center.x + half_x, nav_y, center.z - half_z),
		Vector3(center.x + half_x, nav_y, center.z + half_z),
		Vector3(center.x - half_x, nav_y, center.z + half_z)
	])
	nav_mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))

	var nav_region := NavigationRegion3D.new()
	nav_region.name = region_name
	nav_region.navigation_mesh = nav_mesh
	root.add_child(nav_region)

static func has_dedicated_pedestrian_nav(root: Node3D) -> bool:
	if root == null:
		return false
	return root.get_node_or_null("World/City/only_people_nav") != null \
		or root.get_node_or_null("ImportedCity/only_people_nav") != null
