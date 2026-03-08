extends Node3D
class_name Citizen

# Emittiert wenn der Spieler auf diesen Citizen klickt
signal clicked

@export var citizen_name: String = "Alex"
@export var home_path: NodePath
@export var restaurant_path: NodePath
@export var park_path: NodePath
@export var job: Job
@export var debug_panel: DebugPanel

var home: ResidentialBuilding
var favorite_restaurant: Restaurant
var favorite_park: Building

var needs := Needs.new()
var wallet := Account.new()

var current_location: Building = null
var current_action: Action = null

var _world_ref: World = null

# --- Variation / Personality ---
@export var schedule_offset_min: int = -25
@export var schedule_offset_max: int = 25
var schedule_offset: int = 0

@export var decision_cooldown_range_min: int = 5
@export var decision_cooldown_range_max: int = 20
var decision_cooldown_left: int = 0

@export var hunger_threshold_base: float = 60.0
@export var hunger_threshold_jitter: float = 12.0
var hunger_threshold: float = 60.0

@export var low_energy_threshold_base: float = 35.0
@export var low_energy_threshold_jitter: float = 10.0
var low_energy_threshold: float = 35.0

@export var work_motivation_base: float = 1.0
@export var work_motivation_jitter: float = 0.4
var work_motivation: float = 1.0

@export var park_interest_base: float = 0.35
@export var park_interest_jitter: float = 0.20
var park_interest: float = 0.35

@export var fun_target_base: float = 65.0
@export var fun_target_jitter: float = 15.0
var fun_target: float = 65.0

# --- Work tracking ---
var work_minutes_today: int = 0
var _work_day_key: int = -1

# --- Selection highlight ---
var _mesh_instance: MeshInstance3D = null
var _original_material: Material = null
var _highlight_material: StandardMaterial3D = null

func _ready() -> void:
	wallet.owner_name = citizen_name
	wallet.balance = 200

	schedule_offset = randi_range(schedule_offset_min, schedule_offset_max)
	hunger_threshold = hunger_threshold_base + randf_range(-hunger_threshold_jitter, hunger_threshold_jitter)
	low_energy_threshold = low_energy_threshold_base + randf_range(-low_energy_threshold_jitter, low_energy_threshold_jitter)
	work_motivation = work_motivation_base + randf_range(-work_motivation_jitter, work_motivation_jitter)
	park_interest = clamp(park_interest_base + randf_range(-park_interest_jitter, park_interest_jitter), 0.0, 0.9)

	decision_cooldown_left = randi_range(0, 10)

	_setup_clickable()
	_setup_highlight()
	call_deferred("_auto_resolve_refs")


# ── Klick-Erkennung via Area3D ─────────────────────────────────────────────────
func _setup_clickable() -> void:
	var area := Area3D.new()
	area.name = "ClickArea"
	area.input_ray_pickable = true

	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.45
	shape.height = 2.1
	col.shape = shape
	col.position = Vector3(0, 1.05, 0)  # Mitte der Kapsel-Figur
	area.add_child(col)
	add_child(area)

	area.input_event.connect(_on_area_input_event)


func _on_area_input_event(_camera: Camera3D, event: InputEvent,
		_position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if event is InputEventMouseButton \
		and event.button_index == MOUSE_BUTTON_LEFT \
		and event.pressed:
		clicked.emit()
		get_viewport().set_input_as_handled()


# ── Highlight (Auswahl-Farbe) ──────────────────────────────────────────────────
func _setup_highlight() -> void:
	_mesh_instance = get_node_or_null("MeshInstance3D") as MeshInstance3D
	if _mesh_instance == null:
		return
	_original_material = _mesh_instance.get_surface_override_material(0)

	_highlight_material = StandardMaterial3D.new()
	_highlight_material.albedo_color = Color(1.0, 0.85, 0.1)  # Gelb
	_highlight_material.emission_enabled = true
	_highlight_material.emission = Color(0.6, 0.4, 0.0)


# Wird von main.gd via debug_panel-Setter ausgelöst; oder direkt aufgerufen.
func set_selected(selected: bool) -> void:
	if _mesh_instance == null:
		return
	if selected:
		_mesh_instance.set_surface_override_material(0, _highlight_material)
	else:
		_mesh_instance.set_surface_override_material(0, _original_material)


# ── Selektion: von main.gd aufgerufen ─────────────────────────────────────────
# BUG FIX: _set() wird in GDScript NICHT für @export var aufgerufen — die
# Variable ist schon definiert, daher greift der _set-Fallback nie.
# Lösung: main.gd ruft select(panel) direkt auf statt debug_panel zuzuweisen.
func select(panel) -> void:
	debug_panel = panel
	set_selected(panel != null)


# ── Referenzen auto-auflösen ───────────────────────────────────────────────────
func _auto_resolve_refs() -> void:
	if home_path != NodePath():
		home = get_node_or_null(home_path) as ResidentialBuilding
	if restaurant_path != NodePath():
		favorite_restaurant = get_node_or_null(restaurant_path) as Restaurant
	if park_path != NodePath():
		favorite_park = get_node_or_null(park_path) as Building

	if home == null:
		home = _find_first_residential_building()
		if home:
			print("[Citizen %s] Auto-found home: %s" % [citizen_name, home.name])

	if home != null:
		var added := home.add_tenant(self)
		if added:
			print("[Citizen %s] Registered as tenant at: %s" % [citizen_name, home.name])
		else:
			print("[Citizen %s] WARNING: Home %s is full, could not register as tenant!" % [citizen_name, home.name])

	if favorite_restaurant == null:
		favorite_restaurant = _find_nearest_restaurant(home.get_entrance_pos() if home else global_position)
		if favorite_restaurant:
			print("[Citizen %s] Auto-found restaurant: %s" % [citizen_name, favorite_restaurant.name])

	if favorite_park == null:
		favorite_park = _find_nearest_park(home.get_entrance_pos() if home else global_position)
		if favorite_park:
			print("[Citizen %s] Auto-found park: %s" % [citizen_name, favorite_park.name])

	_try_find_job_once()

	if home:
		current_location = home
		global_position = home.get_entrance_pos()


func _try_find_job_once() -> void:
	if job == null:
		return
	if job.workplace != null:
		return

	var root := get_tree().current_scene
	var from_pos := home.get_entrance_pos() if home else global_position
	job.resolve_nearest(root, from_pos)

	if job.workplace:
		var hired := job.try_get_employed(self)
		if hired:
			print("[Citizen %s] Employed at: %s" % [citizen_name, job.workplace.name])
		else:
			job.workplace = null
			print("[Citizen %s] Workplace full, will retry later." % citizen_name)


func _connect_time_signals(world: World) -> void:
	if world == null or world.time == null:
		return
	if not world.time.hour_changed.is_connected(_on_hour_changed):
		world.time.hour_changed.connect(_on_hour_changed)


func _on_hour_changed(new_hour: int) -> void:
	if new_hour < 6 or new_hour > 20:
		return
	_try_find_job_once()

func _update_debug(world: World, h_delta: float) -> void:
	if not debug_panel:
		return

	if abs(h_delta) >= 0.5:
		var reason := ""
		if needs.hunger >= 80.0:   reason += " [starving]"
		if needs.energy <= 10.0:   reason += " [exhausted]"
		if needs.fun <= 0.0:       reason += " [depressed]"
		if h_delta > 0:            reason = " [recovering]"
		print("[%s] ❤ Health %s%.1f → %.1f%s" % [
			citizen_name,
			"+" if h_delta > 0 else "",
			h_delta, needs.health, reason
		])

	debug_panel.update_debug({
		"Time"     : "%s (%s)" % [world.time.get_time_string(), world.time.get_weekday_name()],
		"Weekend"  : str(world.time.is_weekend()),
		"Citizen"  : citizen_name,
		"Location" : current_location.name if current_location else "travelling...",
		"Action"   : current_action.label if current_action else "idle",
		"──────────": "",
		"Hunger"   : "%.1f / 100  (eat@50)" % needs.hunger,
		"Energy"   : "%.1f / 100  (sleep@80)" % needs.energy,
		"Fun"      : "%.1f / 100  (relax@30)" % needs.fun,
		"Health"   : "%.1f / 100" % needs.health,
		"──────────2": "",
		"Money"    : "%d §" % wallet.balance,
		"Workplace": job.workplace.name if (job and job.workplace) else "unemployed",
		"WorkToday": "%d / %d min" % [
			work_minutes_today,
			int(job.shift_hours * 60) if job else 0
		],
		"Motivation": "%.2f" % work_motivation,
		"ParkInterest": "%.2f" % park_interest,
	})

func _update_work_day(world: World) -> void:
	var today: int = world.time.day
	if _work_day_key != today:
		_work_day_key = today
		work_minutes_today = 0


func sim_tick(world: World) -> void:
	if _world_ref == null:
		_world_ref = world
		_connect_time_signals(world)

	var mod := current_action.get_needs_modifier(world, self) if current_action != null else Action.DEFAULT_NEEDS_MOD
	needs.advance(world.minutes_per_tick, mod.hunger_mul, mod.energy_mul, mod.fun_mul, mod.get("hunger_add", 0.0), mod.energy_add, mod.fun_add)

	_update_work_day(world)
	# BUG FIX: get_health_delta() must be called every tick to keep _last_health in sync.
	# Previously only called inside _update_debug (requires debug_panel) → showed large
	# jumps like "-8.5" when a citizen was first selected after many silent ticks.
	var h_delta := needs.get_health_delta()
	_update_debug(world, h_delta)

	if current_action != null:
		current_action.tick(world, self, world.minutes_per_tick)
		if current_action.is_done():
			current_action.finish(world, self)
			current_action = null
		return
	if decision_cooldown_left > 0:
		decision_cooldown_left -= world.minutes_per_tick
		if decision_cooldown_left > 0:
			return

	plan_next_action(world)
	decision_cooldown_left = randi_range(decision_cooldown_range_min, decision_cooldown_range_max)


func plan_next_action(world: World) -> void:
	var hour := world.time.get_hour()
	var minute := world.time.get_minute()
	var now_total := hour * 60 + minute

	var is_night := (hour >= 22 or hour < 6)
	var weekend := world.time.is_weekend()

	var has_work := (job != null and job.workplace != null) and (not weekend)

	var work_start_total := 0
	var work_end_total := 0
	var shift_total_minutes := 0
	if has_work:
		work_start_total = job.start_hour * 60 + schedule_offset
		shift_total_minutes = int(job.shift_hours * 60)
		work_end_total = work_start_total + shift_total_minutes

	var in_work_window := has_work and (now_total >= work_start_total and now_total < work_end_total)
	var is_lunch_window := (now_total >= (11 * 60 + 30) and now_total <= (13 * 60 + 30))

	var remaining_work := 0
	if has_work:
		remaining_work = max(0, shift_total_minutes - work_minutes_today)

	# 0) SUPER HUNGRY → eat has ABSOLUTE priority (even over energy=0 safety).
	# BUG FIX: Previously energy=0 check came first, so citizens waking from
	# starvation-sleep with E=0 were immediately sent back to sleep → death spiral.
	var super_hungry := needs.hunger >= 80.0
	var can_afford_meal := (favorite_restaurant != null and
		wallet.balance >= favorite_restaurant.meal_price)

	if super_hungry and can_afford_meal:
		if current_location != favorite_restaurant:
			_start_action(GoToBuildingAction.new(favorite_restaurant, 15), world)
			return
		_start_action(EatAtRestaurantAction.new(favorite_restaurant), world)
		return

	if super_hungry and not can_afford_meal:
		needs.health -= 0.5
		needs.health = clamp(needs.health, 0.0, 100.0)
		if home != null and current_location != home:
			_start_action(GoToBuildingAction.new(home, 20), world)
			return
		return

	# 1) HARD SAFETY: Energy empty → go home + sleep (only when NOT starving)
	if home != null and needs.energy <= 1.0:
		if current_location != home:
			_start_action(GoToBuildingAction.new(home, 20), world)
			return
		_start_action(SleepAction.new(), world)
		return

	# 1.5) NIGHT CURFEW
	# BUG FIX: Old threshold was H<75, leaving H=75-84 as a dead zone at night
	# (not super_hungry, but also not allowed to eat since `not is_night` blocked it).
	# Now the curfew only applies when hunger is genuinely low (< 65).
	if is_night and needs.hunger < 65.0:
		if home != null:
			if current_location != home:
				_start_action(GoToBuildingAction.new(home, 20), world)
				return
			if needs.energy < needs.TARGET_ENERGY_MIN:
				_start_action(SleepAction.new(), world)
				return
			_start_action(RelaxAtHomeAction.new(), world)
			return

	var MEAL_HUNGER_THRESHOLD := 50.0

	# 2) NEED TO EAT?
	var want_to_eat := needs.hunger >= MEAL_HUNGER_THRESHOLD and can_afford_meal
	if not want_to_eat and is_lunch_window and needs.hunger >= 30.0 and randf() < 0.5:
		want_to_eat = can_afford_meal

	# BUG FIX: Allow eating at night when genuinely hungry (>= 65).
	# Old `not is_night` completely blocked night eating for H=65-84.
	var night_eating_ok := (not is_night) or (needs.hunger >= 65.0)
	if want_to_eat and night_eating_ok:
		if current_location != favorite_restaurant:
			_start_action(GoToBuildingAction.new(favorite_restaurant, 15), world)
			return
		_start_action(EatAtRestaurantAction.new(favorite_restaurant), world)
		return

	# 3) WORK
	if in_work_window and remaining_work > 0:
		if is_lunch_window:
			if favorite_park != null and needs.energy > 35.0 and randf() < 0.45:
				if current_location != favorite_park:
					_start_action(GoToBuildingAction.new(favorite_park, 25), world)
					return
				_start_action(RelaxAtParkAction.new(45), world)
				return
			if home != null:
				if current_location != home:
					_start_action(GoToBuildingAction.new(home, 20), world)
					return
				_start_action(RelaxAtHomeAction.new(), world)
				return

		if needs.energy < low_energy_threshold:
			if home != null:
				if current_location != home:
					_start_action(GoToBuildingAction.new(home, 20), world)
					return
				_start_action(SleepAction.new(), world)
				return

		if current_location == job.workplace:
			_start_action(WorkAction.new(job), world)
			return

		var energy_factor = clamp(needs.energy / 100.0, 0.35, 1.0)
		var p_go_work = clamp(0.85 * work_motivation * energy_factor, 0.35, 0.98)

		if randf() < p_go_work:
			_start_action(GoToBuildingAction.new(job.workplace, 20), world)
			return
		else:
			if home != null:
				if current_location != home:
					_start_action(GoToBuildingAction.new(home, 20), world)
					return
				_start_action(RelaxAtHomeAction.new(), world)
				return

	# 4) SLEEP
	var should_sleep := false
	if needs.energy < needs.TARGET_ENERGY_MIN:
		if needs.energy < low_energy_threshold:
			# BUG FIX: Previously no affordability check here.
			# When broke (e.g. 2§) AND hungry AND tired, the citizen traveled to the
			# restaurant, EatAtRestaurantAction immediately aborted (can't afford),
			# plan_next_action fired again next tick → infinite restaurant loop.
			# Fix: only eat-before-sleep when we can actually afford the meal.
			if needs.hunger > 50.0 and can_afford_meal and not is_night:
				if current_location != favorite_restaurant:
					_start_action(GoToBuildingAction.new(favorite_restaurant, 15), world)
					return
				_start_action(EatAtRestaurantAction.new(favorite_restaurant), world)
				return
			should_sleep = true
		elif is_night and randf() < 0.85:
			should_sleep = true
		elif randf() < 0.12:
			should_sleep = true

	if home != null and should_sleep:
		if current_location != home:
			_start_action(GoToBuildingAction.new(home, 20), world)
			return
		_start_action(SleepAction.new(), world)
		return

	# 5) FUN
	if needs.fun < needs.TARGET_FUN_MIN and not is_night:
		var park_p := park_interest
		if weekend:
			park_p = clamp(park_p * 1.6, 0.0, 0.95)

		if favorite_park != null and needs.energy > 35.0 and randf() < park_p:
			if current_location != favorite_park:
				_start_action(GoToBuildingAction.new(favorite_park, 25), world)
				return
			_start_action(RelaxAtParkAction.new(), world)
			return

		if home != null:
			if current_location != home:
				_start_action(GoToBuildingAction.new(home, 20), world)
				return
			_start_action(RelaxAtHomeAction.new(), world)
			return

	# 6) DEFAULT
	if not is_night and weekend and favorite_park != null and needs.energy > 45.0:
		var p2 = clamp(park_interest * 0.6, 0.0, 0.6)
		if randf() < p2:
			if current_location != favorite_park:
				_start_action(GoToBuildingAction.new(favorite_park, 25), world)
				return
			_start_action(RelaxAtParkAction.new(), world)
			return

	if home != null:
		if current_location != home:
			_start_action(GoToBuildingAction.new(home, 20), world)
			return
		_start_action(RelaxAtHomeAction.new(), world)
		return


func _find_first_residential_building() -> ResidentialBuilding:
	for node in get_tree().get_nodes_in_group("buildings"):
		if node is ResidentialBuilding:
			return node
	return null


func _find_nearest_restaurant(from_pos: Vector3) -> Restaurant:
	var best: Restaurant = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("buildings"):
		if node is Restaurant:
			var r := node as Restaurant
			var d := from_pos.distance_to(r.global_position)
			if d < best_dist:
				best_dist = d
				best = r
	return best


func _find_nearest_park(from_pos: Vector3) -> Building:
	var best: Building = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("parks"):
		if node is Building:
			var b := node as Building
			var d := from_pos.distance_to(b.global_position)
			if d < best_dist:
				best_dist = d
				best = b
	return best


func _start_action(a: Action, world: World) -> void:
	current_action = a
	current_action.start(world, self)

	var h := world.time.get_hour()
	var m := world.time.get_minute()
	var w := world.time.get_weekday_name()
	var loc = current_location.name if current_location else "travelling"

	if a is GoToBuildingAction:
		var target := (a as GoToBuildingAction).target
		if target != null:
			loc = "-> " + target.name

	var health_icon := ""
	if needs.health < 50.0:    health_icon = " ☠"
	elif needs.health < 75.0:  health_icon = " 🤒"

	print("[%s] %02d:%02d (%s) | %-10s | H:%.0f E:%.0f F:%.0f HP:%.0f%s | 💰%d | at=%s" % [
		citizen_name, h, m, w,
		a.label,
		needs.hunger, needs.energy, needs.fun, needs.health, health_icon,
		wallet.balance,
		loc
	])


func pay_rent(world: World, landlord: ResidentialBuilding, amount: int) -> void:
	if landlord == null:
		return
	var before := wallet.balance
	var success := world.economy.transfer(wallet, landlord.account, amount)
	if success:
		print("[%s] 🏠 Rent paid: %d § (balance: %d → %d)" % [
			citizen_name, amount, before, wallet.balance
		])
	else:
		print("[%s] ⚠ Could not pay rent! Need %d §, have %d §" % [
			citizen_name, amount, wallet.balance
		])
