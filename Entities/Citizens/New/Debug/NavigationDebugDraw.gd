class_name NavigationDebugDraw
extends RefCounted

## Debug visualisation for the 4-layer nav pipeline.
##
## Draws:
##   - Global path ribbon (world-space, `top_level` MeshInstance)
##   - Avoidance direction arrows (desired vs steered)
##   - Local A* grid cells with colour-coded blocked reason
##   - Local A* physics-hit markers
##   - Status label (path progress, avoidance/local/jump status)
##
## Attaches its visuals as children of the owner body. All meshes are
## ImmediateMesh so frame-to-frame rebuilding is cheap.

var _ctx: NavigationContext
const _SCAN_CELL_FILL: float = 0.85
const _SCAN_CELL_Y_OFFSET: float = 0.04

# Avoidance visual (local space)
var _avoid_mesh: ImmediateMesh = ImmediateMesh.new()
var _avoid_visual: MeshInstance3D = null
var _avoid_material: StandardMaterial3D = null
var _avoid_label: Label3D = null

# Global path visual (world space, top_level)
var _path_mesh: ImmediateMesh = ImmediateMesh.new()
var _path_visual: MeshInstance3D = null
var _path_material: StandardMaterial3D = null


func _init(context: NavigationContext) -> void:
	_ctx = context


# ---------------------------------------------------------- Avoidance visual

func update_avoidance(desired_direction: Vector3, final_direction: Vector3,
		local_path: PackedVector3Array,
		local_goal: Vector3, has_goal: bool,
		grid_cells: Array, grid_physics_hits: Array,
		labels: Dictionary) -> void:
	if not _ctx.config.debug_draw_avoidance:
		clear_avoidance()
		return

	_ensure_avoidance_visual()
	_avoid_visual.visible = true
	_avoid_label.visible = true
	_avoid_mesh.clear_surfaces()

	if _ctx.config.debug_draw_surface_cells and not grid_cells.is_empty():
		_avoid_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _avoid_material)
		_draw_grid_quads(grid_cells)
		_avoid_mesh.surface_end()

	_avoid_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _avoid_material)

	var base := _ctx.get_owner_position() + Vector3.UP * 0.35
	_add_line(base, base + desired_direction * 1.1, Color(0.824, 0.122, 0.953, 1.0))
	_add_line(base + Vector3.UP * 0.05, base + final_direction * 1.1 + Vector3.UP * 0.05,
			Color(1.0, 0.85, 0.1, 1.0))
	_draw_scan_radius()
	_draw_grid_lines(local_path, local_goal, has_goal, grid_cells, grid_physics_hits)

	_avoid_mesh.surface_end()
	_update_label(labels)


func clear_avoidance() -> void:
	if _avoid_mesh != null:
		_avoid_mesh.clear_surfaces()
	if _avoid_visual != null:
		_avoid_visual.visible = false
	if _avoid_label != null:
		_avoid_label.visible = false


func _ensure_avoidance_visual() -> void:
	if _avoid_material == null:
		_avoid_material = StandardMaterial3D.new()
		_avoid_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_avoid_material.vertex_color_use_as_albedo = true
		_avoid_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_avoid_material.no_depth_test = true
		_avoid_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	if _avoid_visual == null:
		_avoid_visual = MeshInstance3D.new()
		_avoid_visual.name = "AvoidanceDebugVisual"
		_avoid_visual.mesh = _avoid_mesh
		_ctx.owner_body.add_child(_avoid_visual)

	if _avoid_label == null:
		_avoid_label = Label3D.new()
		_avoid_label.name = "AvoidanceDebugLabel"
		_avoid_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_avoid_label.font_size = 16
		_avoid_label.pixel_size = 0.01
		_ctx.owner_body.add_child(_avoid_label)


func _update_label(labels: Dictionary) -> void:
	_avoid_label.position = Vector3.UP * 1.4
	_avoid_label.text = "path: %s\navoid: %s\nlocal: %s\njump: %s" % [
		str(labels.get("path", "-")),
		str(labels.get("avoidance", "-")),
		str(labels.get("local", "-")),
		str(labels.get("jump", "-")),
	]


func _draw_grid_quads(grid_cells: Array) -> void:
	var cfg := _ctx.config
	var effective_step := maxf(cfg.local_astar_cell_size, 0.08) \
			/ float(maxi(cfg.local_astar_grid_subdivisions, 1))
	var cell_half := effective_step * 0.5 * _SCAN_CELL_FILL
	var ref_y := _ctx.get_owner_position().y
	var quad_y := ref_y + _SCAN_CELL_Y_OFFSET

	for cell_data in grid_cells:
		var world_pos: Vector3 = cell_data.get("world_pos", Vector3.ZERO) as Vector3
		var blocked := bool(cell_data.get("blocked", false))
		var reason := str(cell_data.get("blocked_reason", ""))
		var surface := str(cell_data.get("surface", ""))
		var color := _cell_color(blocked, reason, surface)
		var mark_pos := Vector3(world_pos.x, quad_y, world_pos.z)
		_add_quad(mark_pos, cell_half, color)


func _draw_grid_lines(local_path: PackedVector3Array, local_goal: Vector3,
		has_goal: bool, grid_cells: Array, grid_physics_hits: Array) -> void:
	var cfg := _ctx.config
	var effective_step := maxf(cfg.local_astar_cell_size, 0.08) \
			/ float(maxi(cfg.local_astar_grid_subdivisions, 1))
	var cell_mark_size := maxf(effective_step * 0.18, 0.012)
	var ref_y := _ctx.get_owner_position().y
	var quad_y := ref_y + _SCAN_CELL_Y_OFFSET

	if cfg.debug_draw_surface_cells and cfg.debug_draw_cell_heights:
		for cell_data in grid_cells:
			var world_pos: Vector3 = cell_data.get("world_pos", Vector3.ZERO) as Vector3
			var surface_pos: Vector3 = cell_data.get("surface_pos", Vector3.ZERO) as Vector3
			if absf(surface_pos.y - ref_y) <= 0.01:
				continue
			var blocked := bool(cell_data.get("blocked", false))
			var reason := str(cell_data.get("blocked_reason", ""))
			var surface := str(cell_data.get("surface", ""))
			var color := _cell_color(blocked, reason, surface)
			var mark_pos := Vector3(world_pos.x, quad_y, world_pos.z)
			var floor_pos := Vector3(surface_pos.x, surface_pos.y + 0.02, surface_pos.z)
			var stem_color := Color(color.r, color.g, color.b, 0.35)
			_add_line(mark_pos, floor_pos, stem_color)

	if cfg.debug_draw_physics_hits:
		for hit_data in grid_physics_hits:
			var hit_pos: Vector3 = hit_data.get("pos", Vector3.ZERO) as Vector3
			var near_road := bool(hit_data.get("near_road", false))
			var reason := str(hit_data.get("reason", ""))
			var color := _hit_color(reason, near_road)
			_add_cross(hit_pos + Vector3.UP * 0.12, cell_mark_size * 1.5, color)

	if not local_path.is_empty():
		var previous := _ctx.get_owner_position() + Vector3.UP * 0.18
		for point in local_path:
			var next := point + Vector3.UP * 0.18
			_add_line(previous, next, Color(0.1, 0.45, 1.0, 1.0))
			previous = next

	if has_goal:
		_add_cross(local_goal + Vector3.UP * 0.22, 0.12, Color.WHITE)


func _draw_scan_radius() -> void:
	var radius := maxf(_ctx.config.local_astar_radius, 0.05)
	var center := _ctx.get_owner_position() + Vector3.UP * _SCAN_CELL_Y_OFFSET
	var segments := 64
	var previous := center + Vector3(radius, 0.0, 0.0)
	var color := Color(0.35, 0.85, 1.0, 0.95)
	for i in range(1, segments + 1):
		var angle := TAU * float(i) / float(segments)
		var next := center + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		_add_line(previous, next, color)
		previous = next


## Shared palette with the Coordinate Picker scan:
##   walkable             -> green family
##   road / road buffer   -> red family
##   physics blockers     -> orange-red family
##   height / wall buffer -> purple family
static func _cell_color(blocked: bool, reason: String, surface: String) -> Color:
	if not blocked:
		if surface == SurfaceClassifier.KIND_PEDESTRIAN:
			return Color(0.10, 0.95, 0.20, 0.65)
		if surface == SurfaceClassifier.KIND_CROSSWALK:
			return Color(0.15, 0.80, 0.20, 0.65)
		if surface == SurfaceClassifier.KIND_UNKNOWN:
			return Color(0.20, 0.60, 0.20, 0.55)
		return Color(0.15, 0.75, 0.20, 0.65)
	if reason == "height":
		return Color(0.55, 0.05, 0.55, 0.70)
	if reason == "height+other":
		return Color(0.40, 0.00, 0.40, 0.72)
	if reason == "wall_buffer":
		return Color(0.75, 0.20, 0.55, 0.70)
	if reason == "physics+road":
		return Color(0.70, 0.05, 0.05, 0.70)
	if reason == "road":
		return Color(1.00, 0.05, 0.05, 0.70)
	if reason == "road_buffer" or reason == "physics+road_buffer":
		return Color(0.95, 0.20, 0.10, 0.70)
	if reason == "physics":
		return Color(0.90, 0.25, 0.15, 0.70)
	return Color(0.80, 0.10, 0.40, 0.70)


static func _hit_color(reason: String, near_road: bool) -> Color:
	if reason == "height":
		return Color(0.65, 0.15, 0.80, 1.0)
	if reason == "height+other":
		return Color(0.50, 0.05, 0.60, 1.0)
	if reason == "physics+road":
		return Color(0.75, 0.05, 0.05, 1.0)
	if near_road or reason == "road_buffer" or reason == "physics+road_buffer":
		return Color(0.95, 0.20, 0.10, 1.0)
	return Color(1.0, 0.35, 0.0, 1.0)


func _add_line(from: Vector3, to: Vector3, color: Color) -> void:
	_avoid_mesh.surface_set_color(color)
	_avoid_mesh.surface_add_vertex(_ctx.owner_body.to_local(from))
	_avoid_mesh.surface_set_color(color)
	_avoid_mesh.surface_add_vertex(_ctx.owner_body.to_local(to))


func _add_cross(center: Vector3, size: float, color: Color) -> void:
	_add_line(center - Vector3.RIGHT * size, center + Vector3.RIGHT * size, color)
	_add_line(center - Vector3.FORWARD * size, center + Vector3.FORWARD * size, color)
	_add_line(center - Vector3.UP * size, center + Vector3.UP * size, color)


func _add_quad(center: Vector3, half: float, color: Color) -> void:
	var a := center + Vector3(-half, 0.0, -half)
	var b := center + Vector3(half, 0.0, -half)
	var c := center + Vector3(half, 0.0, half)
	var d := center + Vector3(-half, 0.0, half)
	for v in [a, b, c, a, c, d]:
		_avoid_mesh.surface_set_color(color)
		_avoid_mesh.surface_add_vertex(_ctx.owner_body.to_local(v))


# ---------------------------------------------------------- Global path ribbon

func update_global_path(global_path: PackedVector3Array, path_index: int) -> void:
	if not _ctx.config.show_global_path or global_path.size() < 2:
		clear_global_path()
		return

	_ensure_global_path_visual()
	_path_mesh.clear_surfaces()
	# Skip if there are no remaining segments to draw - Godot raises
	# "No vertices were added" if surface_end() is called on an empty surface.
	var draw_from := maxi(path_index, 0)
	if draw_from >= global_path.size() - 1:
		return
	# Pre-count drawable segments so we never open a surface we cannot fill.
	var drawable_segments := 0
	for idx in range(draw_from, global_path.size() - 1):
		var seg := global_path[idx + 1] - global_path[idx]
		seg.y = 0.0
		if seg.length_squared() > 0.0001:
			drawable_segments += 1
	if drawable_segments == 0:
		return
	_path_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _path_material)
	for idx in range(draw_from, global_path.size() - 1):
		_add_path_segment(global_path[idx], global_path[idx + 1])
	_path_mesh.surface_end()


func clear_global_path() -> void:
	if _path_mesh != null:
		_path_mesh.clear_surfaces()


func _ensure_global_path_visual() -> void:
	if _path_material == null:
		_path_material = StandardMaterial3D.new()
		_path_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_path_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_path_material.albedo_color = _ctx.config.global_path_line_color

	if _path_visual == null:
		_path_visual = MeshInstance3D.new()
		_path_visual.name = "GlobalPathVisual"
		_path_visual.top_level = true
		_path_visual.mesh = _path_mesh
		_ctx.owner_body.add_child(_path_visual)
	_path_visual.global_transform = Transform3D.IDENTITY


func _add_path_segment(from: Vector3, to: Vector3) -> void:
	var y_off := _ctx.config.global_path_line_y_offset
	var start := from + Vector3.UP * y_off
	var end := to + Vector3.UP * y_off
	var segment := end - start
	segment.y = 0.0
	if segment.length_squared() <= 0.0001:
		return
	var half_width := maxf(_ctx.config.global_path_line_width * 0.5, 0.005)
	var side := segment.normalized().cross(Vector3.UP).normalized() * half_width
	var a := start - side
	var b := start + side
	var c := end + side
	var d := end - side
	_path_mesh.surface_add_vertex(a)
	_path_mesh.surface_add_vertex(b)
	_path_mesh.surface_add_vertex(c)
	_path_mesh.surface_add_vertex(a)
	_path_mesh.surface_add_vertex(c)
	_path_mesh.surface_add_vertex(d)
