@tool
extends MeshInstance3D
class_name LowPolyWaterPlane

@export_category("Universal Water Plane")
@export var plane_size: Vector2 = Vector2(200.0, 200.0):
	set(value):
		plane_size = Vector2(maxf(value.x, 0.1), maxf(value.y, 0.1))
		_rebuild_if_ready()
@export_range(1, 256, 1) var subdivisions_x: int = 64:
	set(value):
		subdivisions_x = maxi(value, 1)
		_rebuild_if_ready()
@export_range(1, 256, 1) var subdivisions_z: int = 64:
	set(value):
		subdivisions_z = maxi(value, 1)
		_rebuild_if_ready()
@export var water_y: float = 0.0:
	set(value):
		water_y = value
		_update_height()
@export var water_material: Material:
	set(value):
		water_material = value
		_apply_material()

@export_category("Automatic Shore Mask")
@export var auto_generate_shore_mask: bool = true
@export var shore_source_root_path: NodePath
@export_range(64, 2048, 1) var shore_mask_resolution: int = 2048
@export var shore_scan_below_water: float = 0.35
@export var shore_scan_above_water: float = 260.0
@export var shore_required_above_water: float = 0.35
@export var shore_gradient_pixels: float = 60.0
@export var foam_band_pixels: float = 0.8
@export var shore_vertex_radius_pixels: int = 2
@export var include_name_keywords: PackedStringArray = PackedStringArray(["Beach", "Rock"])
@export var exclude_name_keywords: PackedStringArray = PackedStringArray(["PalmTree", "Grass", "Flowers", "Fence", "Rope", "Torch", "Bones", "Skull", "Ship", "Boat", "Barrel", "Table", "Chair"])

var _runtime_material: ShaderMaterial
var _last_viewport_size: Vector2i = Vector2i.ZERO
var _shore_mask_texture: ImageTexture

func _ready() -> void:
	_rebuild_mesh()
	_update_height()
	_apply_material()
	set_process(true)
	_update_shader_water_bounds()
	_update_shader_viewport_size(true)
	if auto_generate_shore_mask and not Engine.is_editor_hint():
		call_deferred("generate_and_apply_shore_mask")

func _process(_delta: float) -> void:
	_update_shader_viewport_size(false)
	_update_shader_water_bounds()

func rebuild() -> void:
	_rebuild_mesh()
	_update_height()
	_apply_material()
	_update_shader_water_bounds()
	_update_shader_viewport_size(true)

func generate_and_apply_shore_mask() -> void:
	if _runtime_material == null or not is_inside_tree():
		return

	var root := get_node_or_null(shore_source_root_path)
	if root == null:
		return

	var size: int = maxi(shore_mask_resolution, 64)
	var total: int = size * size
	var land := PackedByteArray()
	land.resize(total)

	var marked: int = _mark_land_from_node(root, land, size)
	if marked <= 0:
		return

	var dist: PackedInt32Array = _distance_field_from_land(land, size)
	var shore_values := PackedFloat32Array()
	shore_values.resize(total)
	var foam_values := PackedFloat32Array()
	foam_values.resize(total)

	var foam_center: float = maxf(foam_band_pixels * 0.01, 0.01)
	var foam_half_width: float = maxf(foam_band_pixels * 0.01, 0.01)
	var foam_start: float = maxf(foam_center - foam_half_width, 0.01)
	var foam_end: float = foam_center + foam_half_width

	for i in range(total):
		if land[i] > 0:
			shore_values[i] = 0.0
			foam_values[i] = 0.0
		else:
			var d: float = float(dist[i]) / 10.0
			var shore: float = clampf(1.0 - smoothstep(0.0, maxf(shore_gradient_pixels, 0.001), d), 0.0, 1.0)
			var foam_edge: float = smoothstep(foam_start, foam_center, d) * (1.0 - smoothstep(foam_center, foam_end, d))
			shore_values[i] = shore
			foam_values[i] = clampf(foam_edge, 0.0, 1.0)

	shore_values = _blur_float_field(shore_values, size, 2)
	foam_values = _blur_float_field(foam_values, size, 0)

	var img: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in range(size):
		for x in range(size):
			var idx: int = y * size + x
			if land[idx] > 0:
				img.set_pixel(x, y, Color(0.0, 0.0, 1.0, 1.0))
			else:
				img.set_pixel(x, y, Color(shore_values[idx], foam_values[idx], 0.0, 1.0))

	_shore_mask_texture = ImageTexture.create_from_image(img)
	_runtime_material.set_shader_parameter("shore_mask", _shore_mask_texture)
	_update_shader_water_bounds()

func _blur_float_field(values: PackedFloat32Array, size: int, radius: int) -> PackedFloat32Array:
	if radius <= 0:
		return values

	var temp := PackedFloat32Array()
	temp.resize(values.size())
	var out := PackedFloat32Array()
	out.resize(values.size())

	for y in range(size):
		for x in range(size):
			var sum: float = 0.0
			var count: int = 0
			for ox in range(-radius, radius + 1):
				var nx: int = clampi(x + ox, 0, size - 1)
				sum += values[y * size + nx]
				count += 1
			temp[y * size + x] = sum / float(maxi(count, 1))

	for y in range(size):
		for x in range(size):
			var sum: float = 0.0
			var count: int = 0
			for oy in range(-radius, radius + 1):
				var ny: int = clampi(y + oy, 0, size - 1)
				sum += temp[ny * size + x]
				count += 1
			out[y * size + x] = sum / float(maxi(count, 1))

	return out

func _rebuild_if_ready() -> void:
	if is_inside_tree():
		_rebuild_mesh()
		_apply_material()
		_update_shader_water_bounds()
		_update_shader_viewport_size(true)

func _rebuild_mesh() -> void:
	var plane := PlaneMesh.new()
	plane.size = plane_size
	plane.subdivide_width = subdivisions_x
	plane.subdivide_depth = subdivisions_z
	mesh = plane

func _update_height() -> void:
	position.y = water_y

func _apply_material() -> void:
	if water_material == null:
		_runtime_material = null
		material_override = null
		return

	if water_material is ShaderMaterial:
		_runtime_material = water_material.duplicate() as ShaderMaterial
		material_override = _runtime_material
	else:
		_runtime_material = null
		material_override = water_material
	_update_shader_water_bounds()

func _update_shader_viewport_size(force: bool) -> void:
	if _runtime_material == null or not is_inside_tree():
		return

	var viewport := get_viewport()
	if viewport == null:
		return

	var size := viewport.get_visible_rect().size
	var viewport_size := Vector2i(maxi(int(size.x), 1), maxi(int(size.y), 1))
	if not force and viewport_size == _last_viewport_size:
		return

	_last_viewport_size = viewport_size

func _update_shader_water_bounds() -> void:
	if _runtime_material == null or not is_inside_tree():
		return
	_runtime_material.set_shader_parameter("water_center_xz", Vector2(global_position.x, global_position.z))
	_runtime_material.set_shader_parameter("water_size_xz", plane_size)

func _mark_land_from_node(node: Node, land: PackedByteArray, size: int) -> int:
	var marked := 0
	if node is MeshInstance3D:
		marked += _mark_mesh_instance(node as MeshInstance3D, land, size)
	for child in node.get_children():
		marked += _mark_land_from_node(child, land, size)
	return marked

func _mark_mesh_instance(mi: MeshInstance3D, land: PackedByteArray, size: int) -> int:
	if mi.mesh == null:
		return 0
	if not _name_matches_include(mi):
		return 0
	if _name_matches_exclude(mi):
		return 0
	if not _aabb_intersects_water_band(mi):
		return 0

	var marked := 0
	for surface_idx in range(mi.mesh.get_surface_count()):
		var arrays := mi.mesh.surface_get_arrays(surface_idx)
		if arrays.size() <= Mesh.ARRAY_VERTEX:
			continue
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if vertices.is_empty():
			continue
		var indices: PackedInt32Array
		if arrays.size() > Mesh.ARRAY_INDEX and arrays[Mesh.ARRAY_INDEX] != null:
			indices = arrays[Mesh.ARRAY_INDEX]
		if indices.size() >= 3:
			var i := 0
			while i + 2 < indices.size():
				marked += _mark_triangle(mi, vertices[indices[i]], vertices[indices[i + 1]], vertices[indices[i + 2]], land, size)
				i += 3
		else:
			var i := 0
			while i + 2 < vertices.size():
				marked += _mark_triangle(mi, vertices[i], vertices[i + 1], vertices[i + 2], land, size)
				i += 3
	return marked

func _mark_triangle(mi: MeshInstance3D, a: Vector3, b: Vector3, c: Vector3, land: PackedByteArray, size: int) -> int:
	var water_h := global_position.y
	var pa := mi.global_transform * a
	var pb := mi.global_transform * b
	var pc := mi.global_transform * c
	var min_y := minf(pa.y, minf(pb.y, pc.y))
	var max_y := maxf(pa.y, maxf(pb.y, pc.y))
	if max_y < water_h + shore_required_above_water:
		return 0
	if min_y > water_h + shore_scan_above_water:
		return 0
	if max_y < water_h - shore_scan_below_water:
		return 0

	var av := _world_to_mask_pixel(pa, size)
	var bv := _world_to_mask_pixel(pb, size)
	var cv := _world_to_mask_pixel(pc, size)
	return _rasterize_triangle(av, bv, cv, land, size)

func _world_to_mask_pixel(p: Vector3, size: int) -> Vector2:
	var u := (p.x - global_position.x) / maxf(plane_size.x, 0.001) + 0.5
	var v := (p.z - global_position.z) / maxf(plane_size.y, 0.001) + 0.5
	return Vector2(clampf(u, 0.0, 0.9999) * float(size - 1), clampf(v, 0.0, 0.9999) * float(size - 1))

func _rasterize_triangle(a: Vector2, b: Vector2, c: Vector2, land: PackedByteArray, size: int) -> int:
	var min_x := clampi(floori(minf(a.x, minf(b.x, c.x))) - shore_vertex_radius_pixels, 0, size - 1)
	var max_x := clampi(ceili(maxf(a.x, maxf(b.x, c.x))) + shore_vertex_radius_pixels, 0, size - 1)
	var min_y := clampi(floori(minf(a.y, minf(b.y, c.y))) - shore_vertex_radius_pixels, 0, size - 1)
	var max_y := clampi(ceili(maxf(a.y, maxf(b.y, c.y))) + shore_vertex_radius_pixels, 0, size - 1)
	var area := _edge(a, b, c)
	var marked := 0

	if absf(area) < 0.001:
		return _mark_disk(a, land, size, shore_vertex_radius_pixels) + _mark_disk(b, land, size, shore_vertex_radius_pixels) + _mark_disk(c, land, size, shore_vertex_radius_pixels)

	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var p := Vector2(float(x) + 0.5, float(y) + 0.5)
			var w0 := _edge(b, c, p)
			var w1 := _edge(c, a, p)
			var w2 := _edge(a, b, p)
			if (w0 >= 0.0 and w1 >= 0.0 and w2 >= 0.0) or (w0 <= 0.0 and w1 <= 0.0 and w2 <= 0.0):
				var idx := y * size + x
				if land[idx] == 0:
					land[idx] = 1
					marked += 1
	return marked

func _edge(a: Vector2, b: Vector2, c: Vector2) -> float:
	return (c.x - a.x) * (b.y - a.y) - (c.y - a.y) * (b.x - a.x)

func _mark_disk(p: Vector2, land: PackedByteArray, size: int, radius: int) -> int:
	var cx := clampi(roundi(p.x), 0, size - 1)
	var cy := clampi(roundi(p.y), 0, size - 1)
	var marked := 0
	for y in range(maxi(0, cy - radius), mini(size - 1, cy + radius) + 1):
		for x in range(maxi(0, cx - radius), mini(size - 1, cx + radius) + 1):
			var idx := y * size + x
			if land[idx] == 0:
				land[idx] = 1
				marked += 1
	return marked

func _distance_field_from_land(land: PackedByteArray, size: int) -> PackedInt32Array:
	var total := size * size
	var inf := 1000000000
	var dist := PackedInt32Array()
	dist.resize(total)
	for i in range(total):
		dist[i] = 0 if land[i] > 0 else inf

	for y in range(size):
		for x in range(size):
			var idx := y * size + x
			var best := dist[idx]
			if x > 0:
				best = mini(best, dist[idx - 1] + 10)
			if y > 0:
				best = mini(best, dist[idx - size] + 10)
			if x > 0 and y > 0:
				best = mini(best, dist[idx - size - 1] + 14)
			if x < size - 1 and y > 0:
				best = mini(best, dist[idx - size + 1] + 14)
			dist[idx] = best

	for y in range(size - 1, -1, -1):
		for x in range(size - 1, -1, -1):
			var idx := y * size + x
			var best := dist[idx]
			if x < size - 1:
				best = mini(best, dist[idx + 1] + 10)
			if y < size - 1:
				best = mini(best, dist[idx + size] + 10)
			if x < size - 1 and y < size - 1:
				best = mini(best, dist[idx + size + 1] + 14)
			if x > 0 and y < size - 1:
				best = mini(best, dist[idx + size - 1] + 14)
			dist[idx] = best
	return dist

func _aabb_intersects_water_band(mi: MeshInstance3D) -> bool:
	var aabb := mi.mesh.get_aabb()
	var water_h := global_position.y
	var min_y := INF
	var max_y := -INF
	for x in [aabb.position.x, aabb.position.x + aabb.size.x]:
		for y in [aabb.position.y, aabb.position.y + aabb.size.y]:
			for z in [aabb.position.z, aabb.position.z + aabb.size.z]:
				var p := mi.global_transform * Vector3(x, y, z)
				min_y = minf(min_y, p.y)
				max_y = maxf(max_y, p.y)
	return max_y >= water_h + shore_required_above_water and min_y <= water_h + shore_scan_above_water

func _name_matches_include(mi: MeshInstance3D) -> bool:
	if include_name_keywords.is_empty():
		return true
	var text := String(mi.name).to_lower()
	var parent := mi.get_parent()
	if parent != null:
		text += " " + String(parent.name).to_lower()
	for keyword in include_name_keywords:
		if text.find(String(keyword).to_lower()) >= 0:
			return true
	return false

func _name_matches_exclude(mi: MeshInstance3D) -> bool:
	var text := String(mi.name).to_lower()
	var parent := mi.get_parent()
	if parent != null:
		text += " " + String(parent.name).to_lower()
	for keyword in exclude_name_keywords:
		if text.find(String(keyword).to_lower()) >= 0:
			return true
	return false
