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
@export var include_name_keywords: PackedStringArray = PackedStringArray(["Beach", "Rock", "Cliff", "Stone", "Sand", "Island", "Ground", "Pier", "Dock", "Bridge", "Boat", "Ship", "Buoy", "Post", "Wood"])
@export var exclude_name_keywords: PackedStringArray = PackedStringArray(["PalmTree", "Grass", "Flowers", "Fence", "Rope", "Torch", "Bones", "Skull", "Tree", "Plant", "Bush", "Table", "Chair"])

@export_category("Contact Foam Categories")
## Object name -> foam category. Encoded into the shore-mask alpha so the shader
## can vary foam density / texture / behavior per contact type. Priority on
## overlap: prop > structure > rock > sand > default.
@export var sand_name_keywords: PackedStringArray = PackedStringArray(["Beach", "Sand", "Ground", "Island"])
@export var rock_name_keywords: PackedStringArray = PackedStringArray(["Rock", "Cliff", "Stone"])
@export var structure_name_keywords: PackedStringArray = PackedStringArray(["Pier", "Dock", "Bridge", "Wood", "Plank", "Post"])
@export var prop_name_keywords: PackedStringArray = PackedStringArray(["Boat", "Ship", "Buoy", "Barrel", "Crate"])
## How far (mask pixels) a land pixel's category bleeds into adjacent water so the
## contact-foam band picks up the right behavior.
@export_range(1, 32, 1) var category_spread_pixels: int = 6

const CAT_SAND := 1.0
const CAT_ROCK := 0.7
const CAT_STRUCTURE := 0.45
const CAT_PROP := 0.2
const CAT_DEFAULT := 0.6

var _runtime_material: ShaderMaterial
var _last_viewport_size: Vector2i = Vector2i.ZERO
var _shore_mask_texture: ImageTexture

const MAX_DISTURBANCES := 12
var _disturbances: Array[Vector4] = []

# Separate shoreline-foam overlay (so the foam can sit on the beach and move with
# the tide, independent of the static water plane).
const SHORELINE_FOAM_MATERIAL := preload("res://Scenes/LowPolyWater/WaterPack/Materials/ShorelineFoam.tres")
var _foam_overlay: MeshInstance3D = null
var _foam_material: ShaderMaterial = null

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
	_push_disturbances()

func rebuild() -> void:
	_rebuild_mesh()
	_update_height()
	_apply_material()
	_update_shader_water_bounds()
	_update_shader_viewport_size(true)

# --- Buoyancy API -----------------------------------------------------------
# Sample the wave surface height at a world position. Mirrors the two Gerstner
# waves in the shader (ignores the small noise ripple and shore damping) so
# floating objects bob roughly in sync with what is rendered.
func get_height(world_pos: Vector3) -> float:
	var t: float = float(Time.get_ticks_msec()) / 1000.0
	var xz := Vector2(world_pos.x, world_pos.z)
	var d1 := _wp_dir("primary_wave_direction", Vector2(0.84, 0.31))
	var d2 := _wp_dir("secondary_wave_direction", Vector2(-0.38, 0.93))
	var k1 := _wp_f("primary_wave_scale", 0.08)
	var k2 := _wp_f("secondary_wave_scale", 0.12)
	var a1 := _wp_f("primary_wave_height", 1.4)
	var a2 := _wp_f("secondary_wave_height", 0.8)
	var sp1 := _wp_f("primary_wave_speed", 0.6)
	var sp2 := _wp_f("secondary_wave_speed", 0.85)
	var gy: float = sin(xz.dot(d1) * k1 + t * sp1) * a1 + sin(xz.dot(d2) * k2 + t * sp2) * a2
	return global_position.y + gy

# Approximate surface normal from finite differences of get_height.
func get_normal(world_pos: Vector3, eps: float = 1.5) -> Vector3:
	var hl := get_height(world_pos - Vector3(eps, 0.0, 0.0))
	var hr := get_height(world_pos + Vector3(eps, 0.0, 0.0))
	var hb := get_height(world_pos - Vector3(0.0, 0.0, eps))
	var hf := get_height(world_pos + Vector3(0.0, 0.0, eps))
	return Vector3(hl - hr, 2.0 * eps, hb - hf).normalized()

func _wp_f(param_name: String, fallback: float) -> float:
	if _runtime_material == null:
		return fallback
	var v = _runtime_material.get_shader_parameter(param_name)
	return float(v) if v != null else fallback

func _wp_dir(param_name: String, fallback: Vector2) -> Vector2:
	var d := fallback
	if _runtime_material != null:
		var v = _runtime_material.get_shader_parameter(param_name)
		if v != null:
			d = v
	var l := d.length()
	return d / l if l > 0.0001 else fallback

# --- Dynamic wake foam --------------------------------------------------------
# A moving floating object reports itself each frame; the shader draws extra foam
# around it. Static objects still get the depth intersection-foam rim for free,
# so they do not need to report. xz = world position, radius/strength in shader.
func report_disturbance(world_pos: Vector3, radius: float, strength: float) -> void:
	if _disturbances.size() >= MAX_DISTURBANCES:
		return
	_disturbances.append(Vector4(world_pos.x, world_pos.z, maxf(radius, 0.1), clampf(strength, 0.0, 1.0)))

func _push_disturbances() -> void:
	if _runtime_material == null:
		return
	var n: int = mini(_disturbances.size(), MAX_DISTURBANCES)
	_runtime_material.set_shader_parameter("disturbance_count", n)
	if n > 0:
		var arr: Array[Vector4] = _disturbances.duplicate()
		while arr.size() < MAX_DISTURBANCES:
			arr.append(Vector4.ZERO)
		_runtime_material.set_shader_parameter("disturbances", arr)
	_disturbances.clear()

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
	var category := PackedFloat32Array()
	category.resize(total)

	var marked: int = _mark_land_from_node(root, land, category, size)
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

	# Bleed each land pixel's foam category into nearby water so the contact-foam
	# band knows what it is touching (sand / rock / structure / prop).
	var spread: int = maxi(category_spread_pixels, 1)
	var land_floats := PackedFloat32Array()
	land_floats.resize(total)
	for i in range(total):
		land_floats[i] = 1.0 if land[i] > 0 else 0.0
	var blurred_land := _blur_float_field(land_floats, size, spread)
	var blurred_cat := _blur_float_field(category, size, spread)
	var contact_cat := PackedFloat32Array()
	contact_cat.resize(total)
	for i in range(total):
		var occ: float = blurred_land[i]
		if occ > 0.0001:
			contact_cat[i] = clampf(blurred_cat[i] / occ, 0.0, 1.0)
		else:
			contact_cat[i] = CAT_DEFAULT

	var img: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in range(size):
		for x in range(size):
			var idx: int = y * size + x
			if land[idx] > 0:
				img.set_pixel(x, y, Color(0.0, 0.0, 1.0, clampf(category[idx], 0.0, 1.0)))
			else:
				img.set_pixel(x, y, Color(shore_values[idx], foam_values[idx], 0.0, contact_cat[idx]))

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
	_runtime_material.set_shader_parameter("water_base_y", global_position.y)
	if _foam_material != null:
		_foam_material.set_shader_parameter("water_base_y", global_position.y)

func _setup_foam_overlay() -> void:
	if _foam_overlay != null:
		return
	_foam_overlay = MeshInstance3D.new()
	_foam_overlay.name = "ShorelineFoam"
	var pm := PlaneMesh.new()
	pm.size = plane_size
	pm.subdivide_width = 1
	pm.subdivide_depth = 1
	_foam_overlay.mesh = pm
	if SHORELINE_FOAM_MATERIAL is ShaderMaterial:
		_foam_material = (SHORELINE_FOAM_MATERIAL as ShaderMaterial).duplicate() as ShaderMaterial
		_foam_overlay.material_override = _foam_material
	# Big margin + no shadows: it is a flat screen-covering overlay, not real geo.
	_foam_overlay.extra_cull_margin = 8192.0
	_foam_overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_foam_overlay)
	if _foam_material != null:
		_foam_material.set_shader_parameter("water_base_y", global_position.y)

func _mark_land_from_node(node: Node, land: PackedByteArray, category: PackedFloat32Array, size: int) -> int:
	var marked := 0
	if node is MeshInstance3D:
		marked += _mark_mesh_instance(node as MeshInstance3D, land, category, size)
	for child in node.get_children():
		marked += _mark_land_from_node(child, land, category, size)
	return marked

func _mark_mesh_instance(mi: MeshInstance3D, land: PackedByteArray, category: PackedFloat32Array, size: int) -> int:
	if mi.mesh == null:
		return 0
	if not _name_matches_include(mi):
		return 0
	if _name_matches_exclude(mi):
		return 0
	if not _aabb_intersects_water_band(mi):
		return 0

	var cat: float = _object_category(mi)
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
				marked += _mark_triangle(mi, vertices[indices[i]], vertices[indices[i + 1]], vertices[indices[i + 2]], land, category, cat, size)
				i += 3
		else:
			var i := 0
			while i + 2 < vertices.size():
				marked += _mark_triangle(mi, vertices[i], vertices[i + 1], vertices[i + 2], land, category, cat, size)
				i += 3
	return marked

func _mark_triangle(mi: MeshInstance3D, a: Vector3, b: Vector3, c: Vector3, land: PackedByteArray, category: PackedFloat32Array, cat: float, size: int) -> int:
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
	return _rasterize_triangle(av, bv, cv, land, category, cat, size)

func _world_to_mask_pixel(p: Vector3, size: int) -> Vector2:
	var u := (p.x - global_position.x) / maxf(plane_size.x, 0.001) + 0.5
	var v := (p.z - global_position.z) / maxf(plane_size.y, 0.001) + 0.5
	return Vector2(clampf(u, 0.0, 0.9999) * float(size - 1), clampf(v, 0.0, 0.9999) * float(size - 1))

func _rasterize_triangle(a: Vector2, b: Vector2, c: Vector2, land: PackedByteArray, category: PackedFloat32Array, cat: float, size: int) -> int:
	var min_x := clampi(floori(minf(a.x, minf(b.x, c.x))) - shore_vertex_radius_pixels, 0, size - 1)
	var max_x := clampi(ceili(maxf(a.x, maxf(b.x, c.x))) + shore_vertex_radius_pixels, 0, size - 1)
	var min_y := clampi(floori(minf(a.y, minf(b.y, c.y))) - shore_vertex_radius_pixels, 0, size - 1)
	var max_y := clampi(ceili(maxf(a.y, maxf(b.y, c.y))) + shore_vertex_radius_pixels, 0, size - 1)
	var area := _edge(a, b, c)
	var marked := 0

	if absf(area) < 0.001:
		return _mark_disk(a, land, category, cat, size, shore_vertex_radius_pixels) + _mark_disk(b, land, category, cat, size, shore_vertex_radius_pixels) + _mark_disk(c, land, category, cat, size, shore_vertex_radius_pixels)

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
				category[idx] = maxf(category[idx], cat)
	return marked

func _edge(a: Vector2, b: Vector2, c: Vector2) -> float:
	return (c.x - a.x) * (b.y - a.y) - (c.y - a.y) * (b.x - a.x)

func _mark_disk(p: Vector2, land: PackedByteArray, category: PackedFloat32Array, cat: float, size: int, radius: int) -> int:
	var cx := clampi(roundi(p.x), 0, size - 1)
	var cy := clampi(roundi(p.y), 0, size - 1)
	var marked := 0
	for y in range(maxi(0, cy - radius), mini(size - 1, cy + radius) + 1):
		for x in range(maxi(0, cx - radius), mini(size - 1, cx + radius) + 1):
			var idx := y * size + x
			if land[idx] == 0:
				land[idx] = 1
				marked += 1
			category[idx] = maxf(category[idx], cat)
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

# Classify a contact object into a foam category. Priority on overlap:
# prop > structure > rock > sand > default (a wooden boat is a prop, not a structure).
func _object_category(mi: MeshInstance3D) -> float:
	var text := String(mi.name).to_lower()
	var parent := mi.get_parent()
	if parent != null:
		text += " " + String(parent.name).to_lower()
	for keyword in prop_name_keywords:
		if text.find(String(keyword).to_lower()) >= 0:
			return CAT_PROP
	for keyword in structure_name_keywords:
		if text.find(String(keyword).to_lower()) >= 0:
			return CAT_STRUCTURE
	for keyword in rock_name_keywords:
		if text.find(String(keyword).to_lower()) >= 0:
			return CAT_ROCK
	for keyword in sand_name_keywords:
		if text.find(String(keyword).to_lower()) >= 0:
			return CAT_SAND
	return CAT_DEFAULT
