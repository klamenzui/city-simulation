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
## Attaches its visuals as children of the owner body.  All meshes are
## ImmediateMesh so frame-to-frame rebuilding is cheap.

var _ctx: NavigationContext

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
	_avoid_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _avoid_material)

	var base := _ctx.get_owner_position() + Vector3.UP * 0.35
	_add_line(base, base + desired_direction * 1.1, Color(0.824, 0.122, 0.953, 1.0))
	_add_line(base + Vector3.UP * 0.05, base + final_direction * 1.1 + Vector3.UP * 0.05,
			Color(1.0, 0.85, 0.1, 1.0))
	_draw_grid(local_path, local_goal, has_goal, grid_cells, grid_physics_hits)

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


func _draw_grid(local_path: PackedVector3Array, local_goal: Vector3,
		has_goal: bool, grid_cells: Array, grid_physics_hits: Array) -> void:
	var cfg := _ctx.config
	var effective_step := maxf(cfg.local_astar_cell_size, 0.08) \
			/ float(maxi(cfg.local_astar_grid_subdivisions, 1))
	var cell_mark_size := maxf(effective_step * 0.18, 0.012)
	var ref_y := _ctx.get_owner_position().y

	if cfg.debug_draw_surface_cells:
		for cell_data in grid_cells:
			var surface_pos: Vector3 = cell_data.get("surface_pos", Vector3.ZERO) as Vector3
			var blocked := bool(cell_data.get("blocked", false))
			var reason := str(cell_data.get("blocked_reason", ""))
			var surface := str(cell_data.get("surface", ""))
			var color := _cell_color(blocked, reason, surface)
			var mark_pos := surface_pos + Vector3.UP * 0.02
			_add_cross(mark_pos, cell_mark_size, color)
			if cfg.debug_draw_cell_heights and absf(surface_pos.y - ref_y) > 0.01:
				var floor_pos := Vector3(surface_pos.x, ref_y + 0.07, surface_pos.z)
				var stem_color := Color(color.r, color.g, color.b, 0.35)
				_add_line(mark_pos, floor_pos, stem_color)

	if cfg.debug_draw_physics_hits:
		for hit_data in grid_physics_hits:
			var hit_pos: Vector3 = hit_data.get("pos", Vector3.ZERO) as Vector3
			var near_road := bool(hit_data.get("near_road", false))
			var color := Color(0.851, 0.0, 0.0, 1.0) if near_road else Color(1.0, 0.306, 0.0, 1.0)
			_add_cross(hit_pos + Vector3.UP * 0.12, cell_mark_size * 1.5, color)

	if not local_path.is_empty():
		var previous := _ctx.get_owner_position() + Vector3.UP * 0.18
		for point in local_path:
			var next := point + Vector3.UP * 0.18
			_add_line(previous, next, Color(0.1, 0.45, 1.0, 1.0))
			previous = next

	if has_goal:
		_add_cross(local_goal + Vector3.UP * 0.22, 0.12, Color.WHITE)


## Colour scheme:
##   pedestrian (navigable)  → teal / green shades
##   road                    → red shades
##   physics (wall/object)   → orange shades
##   free / crosswalk        → green / yellow
static func _cell_color(blocked: bool, reason: String, surface: String) -> Color:
	if not blocked:
		if surface == SurfaceClassifier.KIND_PEDESTRIAN:
			return Color(0.0, 0.454, 0.0, 1.0)   # teal — pedestrian zone
		if surface == SurfaceClassifier.KIND_CROSSWALK:
			return Color(0.0, 0.902, 0.051, 1.0) # yellow — crosswalk
		if surface == SurfaceClassifier.KIND_UNKNOWN:
			return Color(0.085, 0.085, 0.085, 1.0) # grey — not classified
		return Color(0.10, 0.72, 0.22)           # green — free fallback
	if reason == "road":
		return Color(1.00, 0.00, 0.00)           # bright red — road
	if reason == "road_buffer":
		return Color(1.00, 0.38, 0.10)           # orange-red — road safety ring
	if reason == "physics":
		return Color(1.00, 0.55, 0.00)           # orange — wall/hydrant/citizen
	if reason == "physics+road":
		return Color(0.85, 0.00, 0.00)           # dark red
	if reason == "physics+road_buffer":
		return Color(0.85, 0.30, 0.00)           # dark orange — object near road
	return Color(0.70, 0.15, 0.70)               # purple — unexpected state


func _add_line(from: Vector3, to: Vector3, color: Color) -> void:
	_avoid_mesh.surface_set_color(color)
	_avoid_mesh.surface_add_vertex(_ctx.owner_body.to_local(from))
	_avoid_mesh.surface_set_color(color)
	_avoid_mesh.surface_add_vertex(_ctx.owner_body.to_local(to))


func _add_cross(center: Vector3, size: float, color: Color) -> void:
	_add_line(center - Vector3.RIGHT * size, center + Vector3.RIGHT * size, color)
	_add_line(center - Vector3.FORWARD * size, center + Vector3.FORWARD * size, color)
	_add_line(center - Vector3.UP * size, center + Vector3.UP * size, color)


# ---------------------------------------------------------- Global path ribbon

func update_global_path(global_path: PackedVector3Array, path_index: int) -> void:
	if not _ctx.config.show_global_path or global_path.size() < 2:
		clear_global_path()
		return

	_ensure_global_path_visual()
	_path_mesh.clear_surfaces()
	_path_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _path_material)
	var draw_from := maxi(path_index, 0)
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
