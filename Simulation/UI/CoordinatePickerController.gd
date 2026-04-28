extends RefCounted
class_name CoordinatePickerController

## Toggle-Modus-Tool für Koordinaten-Picking auf der Map.
##
## Ein Toggle-Button („Pick Coords") oben rechts im HUD aktiviert den Modus.
## Im aktiven Modus: Linksklick auf die Map → Camera-Ray + Ground-Snap →
## Floating Label3D am Treffer-Punkt + HUD-Status + Clipboard.
##
## Y wird IMMER auf den Boden gesnappt (Down-Ray ab Trefferpunkt + 4 m, 12 m
## nach unten). So liefern Klicks auf Wände/Mesh-Oberflächen am Hang die
## tatsächliche Standpunkt-Y, nicht die Mesh-Y.
##
## Komplett isoliert: hängt sich in den HUD-Canvas ein, fragt SceneRuntime nur
## über `handle_input` an. Headless-Builds bekommen keinen Picker.

const RAY_LENGTH: float = 1000.0
const GROUND_PROBE_UP: float = 4.0
const GROUND_PROBE_DOWN: float = 12.0
const PICK_COLLISION_MASK: int = 0xFFFFFFFF

var owner_node: Node = null
var world: World = null
var city_camera: Camera3D = null
var hud_canvas: CanvasLayer = null

var _is_active: bool = false
var _toggle_button: Button = null
var _result_label: Label = null
var _marker: Label3D = null


func setup(p_owner: Node, p_world: World, p_camera: Camera3D, p_canvas: CanvasLayer) -> void:
	owner_node = p_owner
	world = p_world
	city_camera = p_camera
	hud_canvas = p_canvas
	_build_panel()


func is_active() -> bool:
	return _is_active


## Returns true wenn Event konsumiert wurde — dann darf SceneRuntime es nicht
## weiterreichen an interaction_controller (sonst würde der Klick zusätzlich
## einen Citizen oder ein Building selektieren).
func handle_input(event: InputEvent) -> bool:
	if not _is_active:
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

	_toggle_button = Button.new()
	_toggle_button.text = "Pick Coords: OFF"
	_toggle_button.toggle_mode = true
	_toggle_button.focus_mode = Control.FOCUS_NONE
	_toggle_button.custom_minimum_size = Vector2(240, 32)
	_toggle_button.toggled.connect(_on_toggled)
	vbox.add_child(_toggle_button)

	_result_label = Label.new()
	_result_label.text = "Klick auf Map zum Picken"
	_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result_label.custom_minimum_size = Vector2(240, 56)
	_result_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(_result_label)


func _on_toggled(toggled_on: bool) -> void:
	_is_active = toggled_on
	if _toggle_button != null:
		_toggle_button.text = "Pick Coords: %s" % ("ON" if toggled_on else "OFF")
	if not _is_active:
		_hide_marker()
		if _result_label != null:
			_result_label.text = "Klick auf Map zum Picken"


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
