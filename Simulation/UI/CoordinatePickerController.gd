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

const SCAN_CELL_FILL: float = 0.85    # 0..1, Anteil der Cell-Größe den das Quad ausfüllt
const SCAN_CELL_Y_OFFSET: float = 0.04  # m, Quad sitzt knapp über der Geometrie

# Beim Scan-Klick wird der Citizen aus 3 m Höhe auf den Klickpunkt geworfen
# und fällt zu Boden. Erst nach Landung wird gescannt — so ist die Probe-
# Höhen-Basis identisch zur echten Citizen-Y wenn er da hingehen würde.
const SCAN_DROP_HEIGHT: float = 3.0
const SCAN_DROP_MAX_FRAMES: int = 90  # ~1.5 s Timeout

## Eigener Scan-Radius unabhängig vom Live-Citizen-Wert (`local_astar_radius`).
## Damit man ohne Inspector-Edit testen kann, wie eng/weit die Probe sein soll.
## Default 0.6 m — passt zum üblichen Pedzone-Korridor zwischen Park-Mauer
## und Straße. Erhöhe für Open-Air-Plätze, senke für sehr enge Gassen.
const SCAN_RADIUS_OVERRIDE: float = 0.6
const SCAN_CELL_SIZE_OVERRIDE: float = 0.10
## Wenn true: Sphere-Probe wird übersprungen — die User-„Top-Hit + Height"-
## Strategie übernimmt (siehe SCAN_MAX_STEP_HEIGHT). Default true: Down-Ray
## top-hit pro Cell, Y-Diff > Threshold = block. Pfosten, Hydranten, Wände
## werden über die Höhe erkannt; Sphere-Probe nicht nötig.
const SCAN_SKIP_PHYSICS: bool = true
## Höhen-basiertes Block-Kriterium (User-Idee): Cell.y vs. scan_origin.y.
## NAN = aus. Default 0.25 m = Treppenstufe / Park-Mauer-Schwelle.
## Wände, Klippen werden so erkannt ohne Sphere-Probe.
const SCAN_MAX_STEP_HEIGHT: float = 0.25
## Sphere-Probe-Radius nur für den Scan. Live-Config nutzt 0.16, was über
## 0.6 m hinaus in benachbarte Meshes greift. 0.08 ist näher an der echten
## Citizen-Capsule-Breite und macht Pedzonen sichtbar grün.
const SCAN_PROBE_RADIUS_OVERRIDE: float = 0.08
## Mindest-Wartezeit bevor `is_on_floor()` als valide gilt. Direkt nach
## einem Teleport ist der Cache von CharacterBody3D vom alten move_and_slide-
## Status, returnt also fälschlich `true` wenn der Citizen vor dem Teleport
## am Boden war.
const SCAN_DROP_MIN_FRAMES: int = 5
## Initiale Y-Velocity nach Teleport — zwingt das nächste `move_and_slide()`
## den Floor-Cache zu invalidieren. Sonst greift `_apply_idle_gravity` nie
## (denkt is_on_floor=true → keine Gravity).
const SCAN_DROP_KICKSTART_VELOCITY: float = -1.0

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
		# Scan is async (drop-and-land), kick it off but don't await here.
		_drop_and_scan(picked as Vector3, mouse_button.position)
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


## Sondiert den Boden direkt unter `point` und gibt die echte Boden-Y zurück.
##
## Walks ALLE Hits von oben nach unten durch (bis zu 8 Iterationen) und nimmt
## den **niedrigsten Y**. Das fixt den Bug, dass der erste Hit oft eine
## Park-Mauer-Top, ein EntranceTrigger oder ein anderer erhöhter Collider
## ist — dann würde der Citizen "auf der Mauer" landen statt am echten
## Boden. Falls gar kein Hit gefunden wird → Original-Y.
func _ground_snap(point: Vector3) -> Vector3:
	if owner_node == null or not owner_node.is_inside_tree():
		return point
	var space: PhysicsDirectSpaceState3D = owner_node.get_world_3d().direct_space_state
	if space == null:
		return point

	var from := point + Vector3.UP * GROUND_PROBE_UP
	var to := point + Vector3.DOWN * GROUND_PROBE_DOWN
	var exclude: Array[RID] = []
	var lowest_y: float = INF
	var lowest_pos: Vector3 = point

	for _attempt in range(8):
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.collision_mask = PICK_COLLISION_MASK
		query.collide_with_areas = false
		query.exclude = exclude
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			break
		var hit_pos: Vector3 = hit.get("position", point) as Vector3
		if hit_pos.y < lowest_y:
			lowest_y = hit_pos.y
			lowest_pos = hit_pos
		if not hit.has("rid"):
			break
		exclude.append(hit["rid"])

	if is_inf(lowest_y):
		return point
	return lowest_pos


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

## Async drop-and-scan with full diagnostics in the HUD so we can see
## exactly which step inflates the Y value when the visualization ends up
## in the air.
func _drop_and_scan(world_pos: Vector3, screen_pos: Vector2) -> void:
	var citizen := _find_citizen_for_scan()
	if citizen == null:
		_set_result("(kein Citizen-Node gefunden — Scan unmöglich)")
		return
	var local_grid = citizen._local_grid if "_local_grid" in citizen else null
	if local_grid == null or not local_grid.has_method("scan_at"):
		_set_result("(Citizen hat kein _local_grid mit scan_at)")
		return
	if owner_node == null or not owner_node.is_inside_tree():
		return

	# Stop any current travel so the drop position is not immediately overridden.
	if citizen.has_method("stop_travel"):
		citizen.stop_travel()

	var citizen_y_before: float = citizen.global_position.y if "global_position" in citizen else NAN
	var drop_pos := Vector3(world_pos.x, world_pos.y + SCAN_DROP_HEIGHT, world_pos.z)
	if "global_position" in citizen:
		citizen.global_position = drop_pos
	# Kickstart-velocity: forces the next move_and_slide to actually move (down)
	# which in turn invalidates the cached is_on_floor() value. Without this
	# the cache from the pre-teleport state stays true and the wait-loop
	# breaks immediately on frame 1.
	if "velocity" in citizen:
		citizen.velocity = Vector3(0.0, SCAN_DROP_KICKSTART_VELOCITY, 0.0)

	# Snapshot citizen capsule + collision configuration ONCE per click — so
	# the log shows whether global_position is the capsule center or bottom,
	# whether collision is enabled, and what gravity is applied.
	if "_logger" in citizen and citizen._logger != null:
		var col_layer: int = citizen.collision_layer if "collision_layer" in citizen else -1
		var col_mask: int = citizen.collision_mask if "collision_mask" in citizen else -1
		var grav: float = citizen._gravity if "_gravity" in citizen else NAN
		var capsule_radius: float = NAN
		var capsule_height: float = NAN
		var capsule_y_offset: float = NAN
		var collision_shape: Variant = citizen.get_node_or_null("CollisionShape3D")
		if collision_shape != null:
			capsule_y_offset = collision_shape.position.y
			var shape: Variant = collision_shape.shape
			if shape != null and shape is CapsuleShape3D:
				capsule_radius = (shape as CapsuleShape3D).radius
				capsule_height = (shape as CapsuleShape3D).height
		citizen._logger.info("DEBUG_SCAN", "DROP_INIT", {
			"click_world_pos": world_pos,
			"drop_from": drop_pos,
			"citizen_y_before": citizen_y_before,
			"collision_layer": col_layer,
			"collision_mask": col_mask,
			"gravity": grav,
			"capsule_radius": capsule_radius,
			"capsule_height": capsule_height,
			"capsule_y_offset_local": capsule_y_offset,
			"physics_process_enabled": citizen.is_processing_physics() if citizen.has_method("is_processing_physics") else true,
		})
	_set_result("Drop läuft … von Y=%.2f, warte auf Boden" % drop_pos.y)

	# Wait for landing. Skip is_on_floor() checks for the first MIN_FRAMES
	# frames because the cache from the pre-teleport state can lie. Log
	# every 10th frame so the citizen.log shows the fall trajectory.
	var tree := owner_node.get_tree()
	var landed := false
	var landing_frame := 0
	for i in range(SCAN_DROP_MAX_FRAMES):
		await tree.physics_frame
		landing_frame = i + 1
		if landing_frame >= SCAN_DROP_MIN_FRAMES \
				and citizen.has_method("is_on_floor") and citizen.is_on_floor():
			landed = true
			if "_logger" in citizen and citizen._logger != null:
				citizen._logger.info("DEBUG_SCAN", "DROP_LANDED", {
					"frame": landing_frame,
					"pos": citizen.global_position,
					"velocity": citizen.velocity if "velocity" in citizen else Vector3.ZERO,
				})
			break
		if (i % 10) == 0 and "_logger" in citizen and citizen._logger != null:
			citizen._logger.info("DEBUG_SCAN", "DROP_TICK", {
				"frame": landing_frame,
				"pos": citizen.global_position,
				"velocity_y": (citizen.velocity.y if "velocity" in citizen else 0.0),
				"on_floor": (citizen.has_method("is_on_floor") and citizen.is_on_floor()),
			})

	var citizen_y_after: float = citizen.global_position.y if "global_position" in citizen else NAN
	var landed_pos: Vector3 = citizen.global_position if "global_position" in citizen else world_pos
	var scan_origin: Vector3 = landed_pos if landed else world_pos
	var forward := _camera_forward_planar(screen_pos)
	var result: Dictionary = local_grid.scan_at(scan_origin, forward,
			SCAN_RADIUS_OVERRIDE, SCAN_CELL_SIZE_OVERRIDE, SCAN_SKIP_PHYSICS)
	_visualize_scan(result)
	_log_scan(citizen, scan_origin, forward, result)
	_log_per_cell_y_sample(citizen, result, scan_origin)

	# Sample the actual visualized cell-Y so we can SEE if the quads sit
	# above or at the scan origin.
	var avg_quad_y: float = NAN
	var min_quad_y: float = INF
	var max_quad_y: float = -INF
	var cells: Array = result.get("debug_cells", [])
	var n := 0
	var sum := 0.0
	for c in cells:
		var sp: Vector3 = c.get("surface_pos", c.get("world_pos", Vector3.ZERO)) as Vector3
		sum += sp.y
		min_quad_y = minf(min_quad_y, sp.y)
		max_quad_y = maxf(max_quad_y, sp.y)
		n += 1
	if n > 0:
		avg_quad_y = sum / float(n)

	var blocked := 0
	var by_reason: Dictionary = {}
	var by_surface: Dictionary = {}
	for c in cells:
		var s := str(c.get("surface", "?"))
		by_surface[s] = int(by_surface.get(s, 0)) + 1
		if not bool(c.get("blocked", false)):
			continue
		blocked += 1
		var r := str(c.get("blocked_reason", "?"))
		by_reason[r] = int(by_reason.get(r, 0)) + 1

	_set_result(("DROP+SCAN  landed=%s frames=%d\n" \
			+ "click_pick_Y=%.3f  drop_from_Y=%.3f\n" \
			+ "citizen_Y before=%.3f after=%.3f\n" \
			+ "scan_origin_Y=%.3f  quad_Y avg=%.3f min=%.3f max=%.3f\n" \
			+ "%d cells, %d blocked\n" \
			+ "blocked: %s\n" \
			+ "surfaces: %s") % [
		"YES" if landed else "NO",
		landing_frame,
		world_pos.y, drop_pos.y,
		citizen_y_before if not is_nan(citizen_y_before) else 0.0,
		citizen_y_after if not is_nan(citizen_y_after) else 0.0,
		scan_origin.y,
		avg_quad_y if not is_nan(avg_quad_y) else 0.0,
		min_quad_y if not is_inf(min_quad_y) else 0.0,
		max_quad_y if not is_inf(max_quad_y) else 0.0,
		cells.size(), blocked,
		_fmt_count_map(by_reason),
		_fmt_count_map(by_surface),
	])

	# Diagnostics into the citizen.log too.
	if "_logger" in citizen and citizen._logger != null \
			and citizen._logger.has_method("info"):
		citizen._logger.info("DEBUG_SCAN", "DROP", {
			"click_world_pos": world_pos,
			"drop_from": drop_pos,
			"landed": landed,
			"frames": landing_frame,
			"citizen_y_before": citizen_y_before,
			"citizen_y_after": citizen_y_after,
			"scan_origin": scan_origin,
			"avg_quad_y": avg_quad_y,
			"min_quad_y": min_quad_y,
			"max_quad_y": max_quad_y,
		})

	# Result text is produced inside `_drop_and_scan` (it has the diag fields).


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
	_scan_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _scan_material)

	var cells: Array = result.get("debug_cells", [])
	var step: float = float(result.get("step", 0.12))
	var half: float = step * 0.5 * SCAN_CELL_FILL
	# Render ALL quads at a uniform Y = scan_origin.y + small offset.
	# Using each cell's surface_pos.y would scatter the visualization
	# across 30-40 cm (down-ray hits walls at different heights), which
	# looks like the disc is glued onto the citizen body.
	var origin: Vector3 = result.get("origin", Vector3.ZERO) as Vector3
	var quad_y := origin.y + SCAN_CELL_Y_OFFSET
	for cell_data in cells:
		var blocked := bool(cell_data.get("blocked", false))
		var reason := str(cell_data.get("blocked_reason", ""))
		var surface := str(cell_data.get("surface", ""))
		var color := _cell_color(blocked, reason, surface)
		var cell_xz: Vector3 = cell_data.get("world_pos", Vector3.ZERO) as Vector3
		var center := Vector3(cell_xz.x, quad_y, cell_xz.z)
		_add_quad(center, half, color)

	_scan_mesh.surface_end()


## Adds a flat quad (XZ plane) centered at `center` with half-extent `half`.
## Two triangles, vertex-colored.
func _add_quad(center: Vector3, half: float, color: Color) -> void:
	var a := center + Vector3(-half, 0.0, -half)
	var b := center + Vector3( half, 0.0, -half)
	var c := center + Vector3( half, 0.0,  half)
	var d := center + Vector3(-half, 0.0,  half)
	# Two triangles: a-b-c, a-c-d (CW seen from above; cull is disabled).
	for v in [a, b, c, a, c, d]:
		_scan_mesh.surface_set_color(color)
		_scan_mesh.surface_add_vertex(v)


func _ensure_scan_visual() -> void:
	if _scan_material == null:
		_scan_material = StandardMaterial3D.new()
		_scan_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_scan_material.vertex_color_use_as_albedo = true
		# Disable depth test so quads stay visible through tiny ground geometry,
		# disable culling so the quad is visible from below as well.
		_scan_material.no_depth_test = true
		_scan_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_scan_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
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


## Strictly green/red color map. Goal: at a glance see where the citizen
## MAY walk (any green) vs. where it MAY NOT (any red). Sub-shades give a
## hint about the reason but never cross the green/red boundary.
##
## Alpha 0.65 so the underlying ground is still visible.
static func _cell_color(blocked: bool, reason: String, surface: String) -> Color:
	if not blocked:
		# All greens — walkable.
		if surface == "pedestrian":
			return Color(0.10, 0.95, 0.20, 0.65)  # bright green
		if surface == "crosswalk":
			return Color(0.15, 0.80, 0.20, 0.65)  # mid green
		if surface == "unknown":
			return Color(0.20, 0.60, 0.20, 0.55)  # darker green
		return Color(0.15, 0.75, 0.20, 0.65)      # green fallback
	# All reds — not walkable.
	if reason == "height":
		return Color(0.55, 0.05, 0.55, 0.70)      # purple = wall/cliff (height-detected)
	if reason == "height+other":
		return Color(0.40, 0.00, 0.40, 0.75)      # dark purple = height + other reasons
	if reason == "physics+road":
		return Color(0.70, 0.05, 0.05, 0.70)      # darkest red
	if reason == "road":
		return Color(1.00, 0.05, 0.05, 0.70)      # full red
	if reason == "road_buffer" or reason == "physics+road_buffer":
		return Color(0.95, 0.20, 0.10, 0.65)      # red, slight orange tint
	if reason == "physics":
		return Color(0.90, 0.25, 0.15, 0.65)      # red, more orange tint
	return Color(0.80, 0.10, 0.40, 0.65)          # magenta = unexpected (still red-side)


## Samples up to 6 cells from the result and logs their full Y-trace so we
## can see whether the visualization Y mismatch comes from `_world_from_offset`
## (sets cell.y = origin.y), from a missing surface-probe-hit (cell stays at
## origin.y because no down-ray found anything), or from somewhere else.
func _log_per_cell_y_sample(citizen: Node, result: Dictionary, scan_origin: Vector3) -> void:
	if not "_logger" in citizen or citizen._logger == null:
		return
	var logger = citizen._logger
	if not logger.has_method("info"):
		return
	var cells: Array = result.get("debug_cells", [])
	# Pick representative samples: the first cell, the middle, and the last.
	var sample_indices: Array[int] = []
	if cells.size() > 0: sample_indices.append(0)
	if cells.size() > 4: sample_indices.append(cells.size() / 4)
	if cells.size() > 8: sample_indices.append(cells.size() / 2)
	if cells.size() > 12: sample_indices.append(3 * cells.size() / 4)
	if cells.size() > 1: sample_indices.append(cells.size() - 1)
	for idx in sample_indices:
		var c: Dictionary = cells[idx]
		var sp: Vector3 = c.get("surface_pos", Vector3.ZERO) as Vector3
		var pp: Vector3 = c.get("physics_pos", Vector3.ZERO) as Vector3
		var wp: Vector3 = c.get("world_pos", Vector3.ZERO) as Vector3
		logger.info("DEBUG_SCAN", "CELL_Y_TRACE", {
			"idx": idx,
			"world_pos_y": wp.y,
			"surface_pos_y": sp.y,
			"physics_pos_y": pp.y,
			"scan_origin_y": scan_origin.y,
			"surface": str(c.get("surface", "?")),
			"blocked": bool(c.get("blocked", false)),
			"reason": str(c.get("blocked_reason", "")),
			"surface_eq_origin": is_equal_approx(sp.y, scan_origin.y),
		})


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
