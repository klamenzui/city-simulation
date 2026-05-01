extends RefCounted
class_name CoordinatePickerController

## Two debug toggles in the top-right of the HUD:
##
##   1. **Pick Coords** — Linksklick → Camera-Ray + Ground-Snap → Floating
##      Label3D + HUD-Anzeige + Clipboard.  Y wird auf Boden gesnappt.
##
##   2. **Scan Grid** — Linksklick → führt einen `LocalGridPlanner.scan_at()`
##      an der Klick-Position aus (mit Camera-Forward als Richtung) und
##      visualisiert jede Cell als 3D-Cross (rot=blocked, grün=free, etc.).
##      Reasons werden NICHT als Welt-Labels gerendert (verdecken sich
##      gegenseitig) — stattdessen als aggregierte Counts im HUD-Panel und
##      per-Cell ins citizen.log.
##
## Sucht den `$Citizen`-Node (CitizenFacade/Controller) zur Laufzeit für den
## Scan — die Komponenten `_local_grid` und `_perception` werden geliehen.

const RAY_LENGTH: float = 1000.0
const GROUND_PROBE_UP: float = 4.0
const GROUND_PROBE_DOWN: float = 12.0
const PICK_COLLISION_MASK: int = 0xFFFFFFFF

const SCAN_CROSS_SIZE: float = 0.05   # m

var owner_node: Node = null
var world: World = null
var city_camera: Camera3D = null
var hud_canvas: CanvasLayer = null

# Pick-mode state
var _pick_active: bool = false
var _pick_button: Button = null
var _result_label: Label = null
var _marker: Label3D = null

# Scan-mode state
var _scan_active: bool = false
var _scan_button: Button = null
var _scan_visual: MeshInstance3D = null
var _scan_mesh: ImmediateMesh = null
var _scan_material: StandardMaterial3D = null


func setup(p_owner: Node, p_world: World, p_camera: Camera3D, p_canvas: CanvasLayer) -> void:
	owner_node = p_owner
	world = p_world
	city_camera = p_camera
	hud_canvas = p_canvas
	_build_panel()


func is_active() -> bool:
	return _pick_active or _scan_active


## Returns true wenn Event konsumiert wurde — dann darf SceneRuntime es nicht
## weiterreichen an interaction_controller (sonst würde der Klick zusätzlich
## einen Citizen oder ein Building selektieren).
func handle_input(event: InputEvent) -> bool:
	if not is_active():
		return false
	if not (event is InputEventMouseButton):
		return false
	var mouse_button := event as InputEventMouseButton
	if mouse_button.button_index != MOUSE_BUTTON_LEFT or not mouse_button.pressed:
		return false
	var picked: Variant = _pick_coordinate(mouse_button.position)
	if picked == null:
		_set_result("(kein Treffer)")
		return true
	if _scan_active:
		_run_scan(picked as Vector3, mouse_button.position)
	else:
		_show_pick(picked as Vector3)
	return true


func _build_panel() -> void:
	if hud_canvas == null:
		return
	var panel := PanelContainer.new()
	panel.name = "CoordinatePickerPanel"
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -260
	panel.offset_top = 10
	panel.offset_right = -10
	panel.offset_bottom = 110
	hud_canvas.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	_pick_button = Button.new()
	_pick_button.text = "Pick Coords: OFF"
	_pick_button.toggle_mode = true
	_pick_button.focus_mode = Control.FOCUS_NONE
	_pick_button.custom_minimum_size = Vector2(240, 32)
	_pick_button.toggled.connect(_on_pick_toggled)
	vbox.add_child(_pick_button)

	_scan_button = Button.new()
	_scan_button.text = "Scan Grid: OFF"
	_scan_button.toggle_mode = true
	_scan_button.focus_mode = Control.FOCUS_NONE
	_scan_button.custom_minimum_size = Vector2(240, 32)
	_scan_button.toggled.connect(_on_scan_toggled)
	vbox.add_child(_scan_button)

	_result_label = Label.new()
	_result_label.text = "Modus aktivieren, dann auf Map klicken"
	_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result_label.custom_minimum_size = Vector2(260, 100)
	_result_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(_result_label)


func _on_pick_toggled(toggled_on: bool) -> void:
	_pick_active = toggled_on
	if _pick_button != null:
		_pick_button.text = "Pick Coords: %s" % ("ON" if toggled_on else "OFF")
	# Mutually exclusive with scan-mode.
	if toggled_on and _scan_active:
		_scan_active = false
		if _scan_button != null:
			_scan_button.set_pressed_no_signal(false)
			_scan_button.text = "Scan Grid: OFF"
	if not _pick_active:
		_hide_marker()
	if _result_label != null and not is_active():
		_result_label.text = "Modus aktivieren, dann auf Map klicken"


func _on_scan_toggled(toggled_on: bool) -> void:
	_scan_active = toggled_on
	if _scan_button != null:
		_scan_button.text = "Scan Grid: %s" % ("ON" if toggled_on else "OFF")
	if toggled_on and _pick_active:
		_pick_active = false
		if _pick_button != null:
			_pick_button.set_pressed_no_signal(false)
			_pick_button.text = "Pick Coords: OFF"
	if not _scan_active:
		_clear_scan_visuals()
	if _result_label != null and not is_active():
		_result_label.text = "Modus aktivieren, dann auf Map klicken"


func _pick_coordinate(screen_pos: Vector2) -> Variant:
	if city_camera == null or owner_node == null or not owner_node.is_inside_tree():
		return null
	var space: PhysicsDirectSpaceState3D = owner_node.get_world_3d().direct_space_state
	if space == null:
		return null
	var from := city_camera.project_ray_origin(screen_pos)
	var to := from + city_camera.project_ray_normal(screen_pos) * RAY_LENGTH
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = PICK_COLLISION_MASK
	query.collide_with_areas = false
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return null
	var hit_pos: Vector3 = hit.get("position", Vector3.ZERO) as Vector3
	return _ground_snap(hit_pos)


## Sondiert den Boden direkt unter `point` und gibt die Boden-Y zurück.
## Falls kein Boden gefunden wird (Citizen schwebt im Nirgendwo), Original-Y.
func _ground_snap(point: Vector3) -> Vector3:
	if owner_node == null or not owner_node.is_inside_tree():
		return point
	var space: PhysicsDirectSpaceState3D = owner_node.get_world_3d().direct_space_state
	if space == null:
		return point
	var from := point + Vector3.UP * GROUND_PROBE_UP
	var to := point + Vector3.DOWN * GROUND_PROBE_DOWN
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = PICK_COLLISION_MASK
	query.collide_with_areas = false
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return point
	return hit.get("position", point) as Vector3


func _show_pick(pos: Vector3) -> void:
	var clipboard_text := "Vector3(%.2f, %.2f, %.2f)" % [pos.x, pos.y, pos.z]
	var label_text := "x=%.2f  y=%.2f  z=%.2f\n%s" % [
		pos.x, pos.y, pos.z, "(in Clipboard kopiert)"
	]
	_set_result(label_text)
	DisplayServer.clipboard_set(clipboard_text)
	_show_marker(pos)


func _show_marker(pos: Vector3) -> void:
	_ensure_marker()
	_marker.global_position = pos + Vector3.UP * 0.4
	_marker.text = "(%.2f, %.2f, %.2f)" % [pos.x, pos.y, pos.z]
	_marker.visible = true


func _ensure_marker() -> void:
	if _marker != null:
		return
	if owner_node == null:
		return
	_marker = Label3D.new()
	_marker.name = "CoordinatePickerMarker"
	_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_marker.no_depth_test = true
	_marker.font_size = 28
	_marker.modulate = Color(1.0, 0.85, 0.1, 1.0)
	_marker.outline_modulate = Color.BLACK
	_marker.outline_size = 4
	_marker.pixel_size = 0.005
	owner_node.add_child(_marker)


func _hide_marker() -> void:
	if _marker != null:
		_marker.visible = false


func _set_result(text: String) -> void:
	if _result_label != null:
		_result_label.text = text


# ============================================================================
# Scan-Grid mode
# ============================================================================

func _run_scan(world_pos: Vector3, screen_pos: Vector2) -> void:
	# Find the live Citizen-node (Facade or Controller) — borrows its
	# _local_grid and _perception.
	var citizen := _find_citizen_for_scan()
	if citizen == null:
		_set_result("(kein Citizen-Node gefunden — Scan unmöglich)")
		return
	var local_grid = citizen._local_grid if "_local_grid" in citizen else null
	if local_grid == null or not local_grid.has_method("scan_at"):
		_set_result("(Citizen hat kein _local_grid mit scan_at)")
		return

	# Forward direction = camera ray projected onto XZ.
	var forward := _camera_forward_planar(screen_pos)
	var result: Dictionary = local_grid.scan_at(world_pos, forward)
	_visualize_scan(result)
	_log_scan(citizen, world_pos, forward, result)

	var cells: Array = result.get("debug_cells", [])
	var by_reason: Dictionary = {}
	var by_surface: Dictionary = {}
	var blocked := 0
	for c in cells:
		var s := str(c.get("surface", "?"))
		by_surface[s] = int(by_surface.get(s, 0)) + 1
		if not bool(c.get("blocked", false)):
			continue
		blocked += 1
		var r := str(c.get("blocked_reason", "?"))
		by_reason[r] = int(by_reason.get(r, 0)) + 1
	_set_result("Scan @ (%.2f, %.2f, %.2f)  fwd=(%.2f,_,%.2f)\n%d cells, %d blocked\nblocked: %s\nsurfaces: %s" % [
		world_pos.x, world_pos.y, world_pos.z,
		forward.x, forward.z,
		cells.size(), blocked,
		_fmt_count_map(by_reason),
		_fmt_count_map(by_surface),
	])


static func _fmt_count_map(m: Dictionary) -> String:
	if m.is_empty():
		return "-"
	var keys: Array = m.keys()
	keys.sort()
	var parts: Array[String] = []
	for k in keys:
		parts.append("%s=%d" % [str(k), int(m[k])])
	return ", ".join(parts)


func _camera_forward_planar(screen_pos: Vector2) -> Vector3:
	if city_camera == null:
		return Vector3.FORWARD
	var dir := city_camera.project_ray_normal(screen_pos)
	dir.y = 0.0
	if dir.length_squared() <= 0.0001:
		# Fall back to camera-basis -Z.
		dir = -city_camera.global_transform.basis.z
		dir.y = 0.0
		if dir.length_squared() <= 0.0001:
			return Vector3.FORWARD
	return dir.normalized()


func _find_citizen_for_scan() -> Node:
	if owner_node == null:
		return null
	# Try the canonical $Citizen child first.
	var direct := owner_node.get_node_or_null("Citizen")
	if direct != null:
		return direct
	# Fallback: scan citizens group.
	if not owner_node.is_inside_tree():
		return null
	for n in owner_node.get_tree().get_nodes_in_group("citizens"):
		if n != null and "_local_grid" in n:
			return n
	return null


func _visualize_scan(result: Dictionary) -> void:
	_clear_scan_visuals()
	_ensure_scan_visual()
	_scan_mesh.clear_surfaces()
	_scan_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _scan_material)

	var cells: Array = result.get("debug_cells", [])
	for cell_data in cells:
		var blocked := bool(cell_data.get("blocked", false))
		var reason := str(cell_data.get("blocked_reason", ""))
		var surface := str(cell_data.get("surface", ""))
		var color := _cell_color(blocked, reason, surface)
		var center: Vector3 = cell_data.get("surface_pos", cell_data.get("world_pos", Vector3.ZERO)) as Vector3
		_add_cross(center + Vector3.UP * 0.02, SCAN_CROSS_SIZE, color)

	_scan_mesh.surface_end()


func _ensure_scan_visual() -> void:
	if _scan_material == null:
		_scan_material = StandardMaterial3D.new()
		_scan_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_scan_material.vertex_color_use_as_albedo = true
		_scan_material.no_depth_test = true
	if _scan_mesh == null:
		_scan_mesh = ImmediateMesh.new()
	if _scan_visual == null:
		_scan_visual = MeshInstance3D.new()
		_scan_visual.name = "CoordPickerScanVisual"
		_scan_visual.top_level = true
		_scan_visual.mesh = _scan_mesh
		owner_node.add_child(_scan_visual)
		_scan_visual.global_transform = Transform3D.IDENTITY


func _clear_scan_visuals() -> void:
	if _scan_mesh != null:
		_scan_mesh.clear_surfaces()


func _add_cross(center: Vector3, size: float, color: Color) -> void:
	var directions: Array[Vector3] = [Vector3.RIGHT, Vector3.UP, Vector3.FORWARD]
	for d in directions:
		_scan_mesh.surface_set_color(color)
		_scan_mesh.surface_add_vertex(center - d * size)
		_scan_mesh.surface_set_color(color)
		_scan_mesh.surface_add_vertex(center + d * size)


## Same color logic as NavigationDebugDraw — mirrored here so the picker
## doesn't depend on a citizen-instance.
static func _cell_color(blocked: bool, reason: String, surface: String) -> Color:
	if not blocked:
		if surface == "pedestrian":
			return Color(0.0, 0.8, 0.2)         # bright green
		if surface == "crosswalk":
			return Color(0.9, 0.9, 0.05)        # yellow
		if surface == "unknown":
			return Color(0.5, 0.5, 0.5)         # grey
		return Color(0.1, 0.6, 0.2)             # green fallback
	if reason == "road":
		return Color(1.0, 0.0, 0.0)             # bright red
	if reason == "road_buffer":
		return Color(1.0, 0.4, 0.1)             # orange-red
	if reason == "physics":
		return Color(1.0, 0.55, 0.0)            # orange
	if reason == "physics+road":
		return Color(0.85, 0.0, 0.0)            # dark red
	if reason == "physics+road_buffer":
		return Color(0.85, 0.3, 0.0)            # dark orange
	return Color(0.7, 0.15, 0.7)                # purple = unexpected


func _log_scan(citizen: Node, origin: Vector3, forward: Vector3, result: Dictionary) -> void:
	if not "_logger" in citizen:
		return
	var logger = citizen._logger
	if logger == null or not logger.has_method("info"):
		return
	var cells: Array = result.get("debug_cells", [])
	var blocked_total := 0
	var by_reason: Dictionary = {}
	for c in cells:
		if not bool(c.get("blocked", false)):
			continue
		blocked_total += 1
		var r := str(c.get("blocked_reason", ""))
		by_reason[r] = int(by_reason.get(r, 0)) + 1
	logger.info("DEBUG_SCAN", "GRID", {
		"origin": origin,
		"forward": forward,
		"cells": cells.size(),
		"blocked": blocked_total,
		"reasons": str(by_reason),
		"radius_world": float(result.get("radius_world", 0.0)),
		"step": float(result.get("step", 0.0)),
	})
	# Per-cell DEBUG entries (verbose) so individual cells can be looked up.
	for c in cells:
		if not bool(c.get("blocked", false)):
			continue
		logger.debug("DEBUG_SCAN", "CELL", {
			"pos": c.get("world_pos", Vector3.ZERO),
			"surface": str(c.get("surface", "")),
			"reason": str(c.get("blocked_reason", "")),
			"collider": str(c.get("collider", "")),
		})
