@tool
extends Node3D
class_name WaterBuoyancy

## Realistic-ish buoyancy for objects on the LowPolyWaterPlane. Samples the wave
## height at the object's bow / stern / port / starboard and derives its height,
## pitch and roll from those probes - so it rises over crests, pitches nose-up into
## a swell and rolls with side waves. Also leaves a fading, tapering foam wake when
## it moves fast. Inspired by the buoyancy in the GodotOceanWaves projects, done
## kinematically (no rigidbody) so it composes with a simple keyboard driver.

@export var water_path: NodePath
## Node to float. Leave empty to float this node's parent.
@export var target_path: NodePath
@export var height_offset: float = 0.0
## Where the waterline sits as a fraction of the model's height (0 = only the very
## bottom tip touches / floats high, 0.5 = half submerged). Auto-lifted from AABB.
@export_range(0.0, 0.9, 0.01) var draft_fraction: float = 0.0
## How fast the height tracks the wave. High so the boat stays ON the surface even
## while moving across waves (low values make it lag under water when driving).
@export var height_smoothing: float = 20.0
## How fast the pitch/roll settle (gentler than the height).
@export var tilt_smoothing: float = 8.0
@export var align_to_waves: bool = true
@export_range(0.0, 45.0, 1.0) var max_tilt_deg: float = 7.0
## How far the bow/stern/port/starboard probes sit from centre, as a fraction of the
## object's own size (1 = its edges). Lower = gentler rocking / less bow-dive.
@export var probe_scale: float = 0.4

@export_category("Wake Foam")
@export var wake_enabled: bool = true
## Auto-size the wake to the object's width (beam). If off, uses wake_radius.
@export var wake_auto_width: bool = true
@export var wake_width_scale: float = 0.25
@export var wake_margin: float = 0.2
## Hard cap so a big model (sail/oars) can't make a huge wake.
@export var wake_radius_max: float = 2.2
@export var wake_radius: float = 3.5
## Planar speed (units/sec) where the wake starts / reaches full strength.
@export var wake_speed_threshold: float = 1.5
@export var wake_speed_full: float = 8.0
## Trail: how long each foam blob lingers (s), min spacing, max blobs kept.
@export var wake_lifetime: float = 2.2
@export var wake_spacing: float = 1.4
@export_range(1, 12, 1) var wake_trail_max: int = 10

## Direct water reference (used by auto-attach); falls back to water_path.
var water_node: Node = null

var _water: Node = null
var _target: Node3D = null
var _last_pos: Vector3 = Vector3.ZERO
var _wake: Array = [] # each element: Vector4(world_x, world_z, birth_strength, life 0..1)
var _wake_base_radius: float = 3.5
var _half_len: float = 2.0 # half the object's length (local Z)
var _half_wid: float = 1.0 # half the object's width (local X)
var _auto_lift: float = 0.0 # raises the origin so the model floats (from its AABB bottom)

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_water = water_node if water_node != null else get_node_or_null(water_path)
	if target_path.is_empty():
		_target = get_parent() as Node3D
	else:
		_target = get_node_or_null(target_path) as Node3D
	if _target != null:
		_last_pos = _target.global_position
		_measure_object()

func _measure_object() -> void:
	var to_local := _target.global_transform.affine_inverse()
	var merged := AABB()
	var has := false
	for node in _collect_visuals(_target):
		var la: AABB = (to_local * node.global_transform) * node.get_aabb()
		if not has:
			merged = la
			has = true
		else:
			merged = merged.merge(la)
	if not has:
		_wake_base_radius = wake_radius
		return
	_half_len = maxf(merged.size.z * 0.5 * probe_scale, 0.4)
	_half_wid = maxf(merged.size.x * 0.5 * probe_scale, 0.3)
	# Put the waterline at draft_fraction up the model, so it floats there.
	_auto_lift = -(merged.position.y + merged.size.y * draft_fraction)
	if wake_auto_width:
		var beam: float = minf(merged.size.x, merged.size.z)
		_wake_base_radius = clampf(beam * 0.5 * wake_width_scale + wake_margin, 0.25, wake_radius_max)
	else:
		_wake_base_radius = wake_radius

func _collect_visuals(node: Node) -> Array:
	var out: Array = []
	if node is VisualInstance3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_collect_visuals(c))
	return out

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _water == null or _target == null or not _water.has_method("get_height"):
		return

	# Horizontal heading axes (ignore current pitch/roll so probes don't feed back).
	var basis := _target.global_transform.basis.orthonormalized()
	var fwd_flat := Vector3(-basis.z.x, 0.0, -basis.z.z)
	if fwd_flat.length() < 0.001:
		fwd_flat = Vector3(0.0, 0.0, -1.0)
	fwd_flat = fwd_flat.normalized()
	var right_flat := fwd_flat.cross(Vector3.UP).normalized()

	# Sample the wave at the four hull probes.
	var c := _target.global_position
	var hb: float = float(_water.get_height(c + fwd_flat * _half_len))   # bow
	var hs: float = float(_water.get_height(c - fwd_flat * _half_len))   # stern
	var hp: float = float(_water.get_height(c - right_flat * _half_wid)) # port
	var ht: float = float(_water.get_height(c + right_flat * _half_wid)) # starboard
	# Height rides the CENTRE of the surface so a wave crest never rolls over the
	# boat (the 4 probes above are used only for pitch/roll below).
	var hc: float = float(_water.get_height(c))
	var cy: float = hc + height_offset + _auto_lift

	var th := 1.0 - exp(-height_smoothing * delta)
	var pos := c
	pos.y = lerpf(pos.y, cy, th)
	_target.global_position = pos

	_update_wake(pos, delta)

	if align_to_waves:
		# Robust tilt: heading (yaw) kept, plus CLAMPED pitch (bow vs stern) and roll
		# (port vs starboard). Building from clamped Euler angles means the boat can
		# never capsize, unlike a looking_at basis.
		var max_rad := deg_to_rad(max_tilt_deg)
		var yaw := atan2(-fwd_flat.x, -fwd_flat.z)
		var pitch := clampf(atan2(hb - hs, 2.0 * _half_len), -max_rad, max_rad)
		var roll := clampf(atan2(hp - ht, 2.0 * _half_wid), -max_rad, max_rad)
		var target_basis := Basis.from_euler(Vector3(pitch, yaw, roll))
		var tt := 1.0 - exp(-tilt_smoothing * delta)
		_target.global_transform.basis = basis.slerp(target_basis, tt).orthonormalized()

	_last_pos = pos

func _update_wake(pos: Vector3, delta: float) -> void:
	if not wake_enabled or not _water.has_method("report_disturbance"):
		return

	var planar := Vector2(pos.x - _last_pos.x, pos.z - _last_pos.z).length() / maxf(delta, 0.0001)
	var strength := clampf((planar - wake_speed_threshold) / maxf(wake_speed_full - wake_speed_threshold, 0.001), 0.0, 1.0)

	if strength > 0.02:
		var need_point := _wake.is_empty()
		if not need_point:
			var last: Vector4 = _wake[_wake.size() - 1]
			need_point = Vector2(pos.x, pos.z).distance_to(Vector2(last.x, last.y)) >= wake_spacing
		if need_point:
			_wake.append(Vector4(pos.x, pos.z, strength, 1.0))
			while _wake.size() > wake_trail_max:
				_wake.remove_at(0)

	var life_step := delta / maxf(wake_lifetime, 0.05)
	var i := _wake.size() - 1
	while i >= 0:
		var p: Vector4 = _wake[i]
		p.w -= life_step
		if p.w <= 0.0:
			_wake.remove_at(i)
		else:
			_wake[i] = p
			var s := p.z * smoothstep(0.0, 0.35, p.w)
			# Widest at the boat (life ~1), tapering to a narrow tail behind (life ~0).
			var r := _wake_base_radius * (0.2 + 0.8 * p.w)
			_water.report_disturbance(Vector3(p.x, 0.0, p.y), r, s)
		i -= 1
