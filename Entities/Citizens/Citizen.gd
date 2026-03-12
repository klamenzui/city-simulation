extends Node3D
class_name Citizen

const CitizenAgentScript = preload("res://Simulation/Citizens/CitizenAgent.gd")

# Emittiert wenn der Spieler auf diesen Citizen klickt
signal clicked

@export var citizen_name: String = "Alex"
@export var home_path: NodePath
@export var restaurant_path: NodePath
@export var supermarket_path: NodePath
@export var shop_path: NodePath
@export var cinema_path: NodePath
@export var park_path: NodePath
@export var job: Job
@export var debug_panel: DebugPanel

var home: ResidentialBuilding
var favorite_restaurant: Restaurant
var favorite_supermarket: Supermarket
var favorite_shop: Shop
var favorite_cinema: Cinema
var favorite_park: Building

var needs := Needs.new()
var wallet := Account.new()
var home_food_stock: int = 2
var education_level: int = 0

var current_location: Building = null
var current_action: Action = null

var _world_ref: World = null
var _agent = CitizenAgentScript.new()

# --- Movement / Navigation ---
@export var move_speed_min: float = 1.6
@export var move_speed_max: float = 2.4
@export var move_acceleration: float = 5.5
@export var move_deceleration: float = 7.0
@export var turn_speed: float = 8.0
@export var waypoint_reach_distance: float = 0.35
@export var arrival_distance: float = 0.65
@export var ground_probe_up: float = 4.0
@export var ground_probe_down: float = 12.0
@export var repath_interval_sec: float = 0.6
@export var gravity_strength: float = 28.0
@export var max_fall_speed: float = 35.0
@export var ground_snap_rate: float = 18.0

var _nav_agent: NavigationAgent3D = null
var _is_travelling: bool = false
var _travel_target: Vector3 = Vector3.ZERO
var _travel_route: PackedVector3Array = PackedVector3Array()
var _travel_route_index: int = -1
var _repath_time_left: float = 0.0
var _walk_speed: float = 2.0
var _current_speed: float = 0.0
var _vertical_speed: float = 0.0
var _ground_fallback_y: float = 0.0
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
	_walk_speed = randf_range(move_speed_min, move_speed_max)

	decision_cooldown_left = randi_range(0, 10)

	_setup_clickable()
	_setup_highlight()
	_agent.setup(self)
	call_deferred("_auto_resolve_refs")

func _physics_process(delta: float) -> void:
	_agent.physics_step(self, delta, _world_ref)

# Click detection via Area3D
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


# Highlight selection material
func _setup_highlight() -> void:
	_mesh_instance = get_node_or_null("MeshInstance3D") as MeshInstance3D
	if _mesh_instance == null:
		return
	_original_material = _mesh_instance.get_surface_override_material(0)

	_highlight_material = StandardMaterial3D.new()
	_highlight_material.albedo_color = Color(1.0, 0.85, 0.1)  # Gelb
	_highlight_material.emission_enabled = true
	_highlight_material.emission = Color(0.6, 0.4, 0.0)

func _setup_navigation() -> void:
	_nav_agent = get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	if _nav_agent == null:
		_nav_agent = NavigationAgent3D.new()
		_nav_agent.name = "NavigationAgent3D"
		add_child(_nav_agent)

	_nav_agent.path_desired_distance = waypoint_reach_distance
	_nav_agent.target_desired_distance = arrival_distance
	_nav_agent.path_max_distance = 2.0
	_nav_agent.radius = 0.35
	_nav_agent.height = 1.8
	_nav_agent.avoidance_enabled = false

func _probe_ground_hit(pos: Vector3) -> Dictionary:
	if not is_inside_tree():
		return {}

	var from := pos + Vector3.UP * ground_probe_up
	var to := pos + Vector3.DOWN * ground_probe_down
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	return get_world_3d().direct_space_state.intersect_ray(query)

func _project_to_ground(pos: Vector3) -> Vector3:
	var hit := _probe_ground_hit(pos)
	if hit.is_empty():
		var fallback := pos
		fallback.y = _ground_fallback_y
		return fallback

	var grounded := pos
	grounded.y = (hit["position"] as Vector3).y
	return grounded

func _apply_grounding(pos: Vector3, delta: float) -> Vector3:
	var grounded := pos
	var hit := _probe_ground_hit(pos)
	if hit.is_empty():
		_vertical_speed = max(_vertical_speed - gravity_strength * delta, -max_fall_speed)
		grounded.y += _vertical_speed * delta
		if grounded.y < _ground_fallback_y:
			grounded.y = _ground_fallback_y
			_vertical_speed = 0.0
		return grounded

	_vertical_speed = 0.0
	var floor_y := (hit["position"] as Vector3).y
	grounded.y = lerp(grounded.y, floor_y, clamp(ground_snap_rate * delta, 0.0, 1.0))
	return grounded

func set_position_grounded(pos: Vector3) -> void:
	_agent.locomotion.set_position_grounded(self, pos, _world_ref)

func begin_travel_to(target_pos: Vector3) -> void:
	_agent.locomotion.begin_travel_to(self, target_pos, _world_ref)

func has_reached_travel_target() -> bool:
	return _agent.locomotion.has_reached_travel_target(self)

func stop_travel() -> void:
	_agent.locomotion.stop_travel(self)

func _advance_travel_route() -> bool:
	if _travel_route.is_empty():
		return false

	var next_index := _travel_route_index + 1
	if next_index >= _travel_route.size():
		return false

	_travel_route_index = next_index
	_travel_target = _project_to_ground(_travel_route[_travel_route_index])
	if _nav_agent != null:
		_nav_agent.target_position = _travel_target
	_repath_time_left = repath_interval_sec
	return true

func _move_along_path(delta: float) -> void:
	if _nav_agent == null:
		return

	_repath_time_left -= delta
	if _repath_time_left <= 0.0:
		_repath_time_left = repath_interval_sec
		_nav_agent.target_position = _travel_target

	if _nav_agent.is_navigation_finished() or has_reached_travel_target():
		if _advance_travel_route():
			set_position_grounded(_travel_target)
			return
		stop_travel()
		set_position_grounded(_travel_target)
		return

	var next_path_point := _nav_agent.get_next_path_position()
	var to_next := next_path_point - global_position
	to_next.y = 0.0
	var distance_to_next := to_next.length()
	if distance_to_next <= 0.001:
		_current_speed = move_toward(_current_speed, 0.0, move_deceleration * delta)
		return

	var desired_speed: float = _walk_speed
	if distance_to_next < 1.2:
		desired_speed *= clamp(distance_to_next / 1.2, 0.25, 1.0)

	if _current_speed < desired_speed:
		_current_speed = move_toward(_current_speed, desired_speed, move_acceleration * delta)
	else:
		_current_speed = move_toward(_current_speed, desired_speed, move_deceleration * delta)

	var dir: Vector3 = to_next / distance_to_next
	var step: float = minf(_current_speed * delta, distance_to_next)
	var next_pos: Vector3 = global_position + dir * step
	global_position = _apply_grounding(next_pos, delta)
	_update_facing(dir, delta)

func _update_facing(move_dir: Vector3, delta: float) -> void:
	if move_dir.length_squared() <= 0.0001:
		return

	var target_yaw := atan2(move_dir.x, move_dir.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, clamp(turn_speed * delta, 0.0, 1.0))
# Called from main.gd when selection/debug panel changes.
func set_selected(selected: bool) -> void:
	if _mesh_instance == null:
		return
	if selected:
		_mesh_instance.set_surface_override_material(0, _highlight_material)
	else:
		_mesh_instance.set_surface_override_material(0, _original_material)


# Selection entrypoint called from main.gd
# NOTE: _set() is not called for exported vars in this case.
# Variable ist schon definiert, daher greift der _set-Fallback nie.
# Solution: main.gd calls select(panel) directly.
func select(panel) -> void:
	debug_panel = panel
	set_selected(panel != null)


# Auto-resolve optional node references
func _auto_resolve_refs() -> void:
	if home_path != NodePath():
		home = get_node_or_null(home_path) as ResidentialBuilding
	if restaurant_path != NodePath():
		favorite_restaurant = get_node_or_null(restaurant_path) as Restaurant
	if supermarket_path != NodePath():
		favorite_supermarket = get_node_or_null(supermarket_path) as Supermarket
	if shop_path != NodePath():
		favorite_shop = get_node_or_null(shop_path) as Shop
	if cinema_path != NodePath():
		favorite_cinema = get_node_or_null(cinema_path) as Cinema
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

	var origin := home.get_entrance_pos() if home else global_position

	if favorite_restaurant == null:
		favorite_restaurant = _find_nearest_restaurant(origin, false)
		if favorite_restaurant:
			print("[Citizen %s] Auto-found restaurant: %s" % [citizen_name, favorite_restaurant.name])

	if favorite_supermarket == null:
		favorite_supermarket = _find_nearest_supermarket(origin, false)
		if favorite_supermarket:
			print("[Citizen %s] Auto-found supermarket: %s" % [citizen_name, favorite_supermarket.name])

	if favorite_shop == null:
		favorite_shop = _find_nearest_shop(origin, false)
		if favorite_shop:
			print("[Citizen %s] Auto-found shop: %s" % [citizen_name, favorite_shop.name])

	if favorite_cinema == null:
		favorite_cinema = _find_nearest_cinema(origin, false)
		if favorite_cinema:
			print("[Citizen %s] Auto-found cinema: %s" % [citizen_name, favorite_cinema.name])

	if favorite_park == null:
		favorite_park = _find_nearest_park(origin)
		if favorite_park:
			print("[Citizen %s] Auto-found park: %s" % [citizen_name, favorite_park.name])

	_try_find_job_once()

	if home:
		current_location = home
		set_position_grounded(home.get_entrance_pos())

func _try_find_job_once() -> void:
	if job == null:
		return
	if job.workplace != null:
		return

	var from_pos := home.get_entrance_pos() if home else global_position
	if _world_ref != null:
		job.workplace = _world_ref.find_nearest_open_workplace(from_pos, job.workplace_name)

	if job.workplace == null:
		var root := get_tree().current_scene
		job.resolve_nearest(root, from_pos)

	if job.workplace == null:
		return

	if not job.meets_requirements(self):
		print("[Citizen %s] Needs education level %d for job %s (current %d)." % [
			citizen_name,
			job.required_education_level,
			job.title,
			education_level
		])
		job.workplace = null
		return

	var hired := job.try_get_employed(self)
	if hired:
		print("[Citizen %s] Employed at: %s" % [citizen_name, job.workplace.name])
	else:
		job.workplace = null
		print("[Citizen %s] Workplace full, will retry later." % citizen_name)

func set_world_ref(world: World) -> void:
	if world == null:
		return
	_world_ref = world
	_ground_fallback_y = world.get_ground_fallback_y()
	_connect_time_signals(world)

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
		print("[%s] Health %s%.1f -> %.1f%s" % [
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
		"----------": "",
		"Hunger"   : "%.1f / 100  (eat@50)" % needs.hunger,
		"Energy"   : "%.1f / 100  (sleep@80)" % needs.energy,
		"Fun"      : "%.1f / 100  (relax@30)" % needs.fun,
		"Health"   : "%.1f / 100" % needs.health,
		"----------2": "",
		"Money"    : "%d EUR" % wallet.balance,
		"Groceries": str(home_food_stock),
		"Education": "%d" % education_level,
		"Workplace": job.workplace.name if (job and job.workplace) else "unemployed",
		"WorkToday": "%d / %d min" % [
			work_minutes_today,
			int(job.shift_hours * 60) if job else 0
		],
		"JobReqEdu": "%d" % (job.required_education_level if job else 0),
		"Motivation": "%.2f" % work_motivation,
		"ParkInterest": "%.2f" % park_interest,
	})

func _update_work_day(world: World) -> void:
	var today: int = world.time.day
	if _work_day_key != today:
		_work_day_key = today
		work_minutes_today = 0


func sim_tick(world: World) -> void:
	_agent.sim_tick(self, world)

func plan_next_action(world: World) -> void:
	_agent.planner.plan_next_action(world, self)

func can_afford_restaurant(world: World) -> bool:
	if favorite_restaurant == null:
		return false
	var price: int = favorite_restaurant.meal_price
	if favorite_restaurant.has_method("get_meal_price"):
		price = int(favorite_restaurant.get_meal_price(world))
	return wallet.balance >= price

func can_afford_groceries(world: World) -> bool:
	if favorite_supermarket == null:
		return false
	var price: int = favorite_supermarket.grocery_price
	if favorite_supermarket.has_method("get_grocery_price"):
		price = int(favorite_supermarket.get_grocery_price(world))
	return wallet.balance >= price

func can_afford_shop_item(_world: World) -> bool:
	if favorite_shop == null:
		return false
	var price: int = favorite_shop.item_price
	if favorite_shop.has_method("get_item_price_quote"):
		price = int(favorite_shop.get_item_price_quote(1.0))
	return wallet.balance >= price

func can_afford_cinema(_world: World) -> bool:
	if favorite_cinema == null:
		return false
	return wallet.balance >= favorite_cinema.ticket_price
func _find_first_residential_building() -> ResidentialBuilding:
	if _world_ref != null:
		return _world_ref.find_first_residential_building()

	for node in get_tree().get_nodes_in_group("buildings"):
		if node is ResidentialBuilding:
			return node
	return null


func _find_nearest_restaurant(from_pos: Vector3, require_open: bool = true) -> Restaurant:
	if _world_ref != null:
		return _world_ref.find_nearest_restaurant(from_pos, require_open)

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


func _find_nearest_supermarket(from_pos: Vector3, require_open: bool = true) -> Supermarket:
	if _world_ref != null:
		return _world_ref.find_nearest_supermarket(from_pos, require_open)

	var best: Supermarket = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("buildings"):
		if node is Supermarket:
			var market := node as Supermarket
			var d := from_pos.distance_to(market.global_position)
			if d < best_dist:
				best_dist = d
				best = market
	return best


func _find_nearest_shop(from_pos: Vector3, require_open: bool = true) -> Shop:
	if _world_ref != null:
		return _world_ref.find_nearest_shop(from_pos, require_open)

	var best: Shop = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("buildings"):
		if node is Shop and node is not Supermarket:
			var shop := node as Shop
			var d := from_pos.distance_to(shop.global_position)
			if d < best_dist:
				best_dist = d
				best = shop
	return best


func _find_nearest_cinema(from_pos: Vector3, require_open: bool = true) -> Cinema:
	if _world_ref != null:
		return _world_ref.find_nearest_cinema(from_pos, require_open)

	var best: Cinema = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("buildings"):
		if node is Cinema:
			var cinema := node as Cinema
			var d := from_pos.distance_to(cinema.global_position)
			if d < best_dist:
				best_dist = d
				best = cinema
	return best

func _find_nearest_university(from_pos: Vector3, require_open: bool = true) -> University:
	if _world_ref != null:
		return _world_ref.find_nearest_university(from_pos, require_open)

	var best: University = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("buildings"):
		if node is University:
			var uni := node as University
			var d := from_pos.distance_to(uni.global_position)
			if d < best_dist:
				best_dist = d
				best = uni
	return best

func _find_nearest_park(from_pos: Vector3) -> Building:
	if _world_ref != null:
		return _world_ref.find_nearest_park(from_pos)

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


func start_action(a: Action, world: World) -> void:
	_start_action(a, world)

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
	if needs.health < 50.0:    health_icon = " [LOW]"
	elif needs.health < 75.0:  health_icon = " [WARN]"

	print("[%s] %02d:%02d (%s) | %-10s | H:%.0f E:%.0f F:%.0f HP:%.0f%s | $%d | at=%s" % [
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
		print("[%s] Rent paid: %d EUR (balance: %d -> %d)" % [
			citizen_name, amount, before, wallet.balance
		])
	else:
		print("[%s] Could not pay rent! Need %d EUR, have %d EUR" % [
			citizen_name, amount, wallet.balance
		])
