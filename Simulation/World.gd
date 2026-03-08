extends CSGBox3D
class_name World

@export var minutes_per_tick: int = 10
@export var tick_interval_sec: float = 0.5

var time: TimeSystem = TimeSystem.new()
var economy: EconomySystem = EconomySystem.new()

var city_account: Account = Account.new()

var citizens: Array[Citizen] = []
var buildings: Array[Building] = []

var is_paused: bool = false
var speed_multiplier: float = 1.0

signal paused_changed(paused: bool)
signal speed_changed(multiplier: float)

var _timer: Timer

func _ready() -> void:
	add_child(time)
	add_child(economy)

	city_account.owner_name = "City"
	city_account.balance = 999999

	for n in get_tree().get_nodes_in_group("buildings"):
		register_building(n as Building)
	for n in get_tree().get_nodes_in_group("citizens"):
		register_citizen(n as Citizen)

	_timer = Timer.new()
	_timer.wait_time = tick_interval_sec
	_timer.autostart = true
	_timer.timeout.connect(_on_tick)
	add_child(_timer)

	time.payday.connect(_on_payday)

func _on_tick() -> void:
	if is_paused:
		return
	time.advance(minutes_per_tick)
	for c in citizens:
		if c:
			c.sim_tick(self)

func _on_payday() -> void:
	print("\n=== PAYDAY (Day %d) ===" % world_day())
	for c in citizens:
		if c == null:
			continue

		# BUG FIX: Citizens with a Job resource but no workplace (unemployed) received
		# full wages because the old check was only `c.job == null`.
		# Now: require an actual workplace. Unemployed get a small social welfare payment
		# instead so they don't go broke and starve within days.
		if c.job == null or c.job.workplace == null:
			# Basic income / welfare: keeps unemployed alive while job-hunting.
			var welfare: int = 40
			var before := c.wallet.balance
			economy.transfer(city_account, c.wallet, welfare)
			print("  🏛 %s: welfare +%d§ | 🏦 %d → %d" % [
				c.citizen_name, welfare, before, c.wallet.balance
			])
			continue

		# BUG FIX: Pay based on actual minutes worked today, not a flat shift rate.
		var hours_worked: float = c.work_minutes_today / 60.0
		var daily_wage: int = int(c.job.wage_per_hour * hours_worked)
		if daily_wage <= 0:
			print("  ⏭ %s: worked %.1fh → no pay" % [c.citizen_name, hours_worked])
			continue

		var before := c.wallet.balance
		economy.transfer(city_account, c.wallet, daily_wage)
		print("  💵 %s: %.1fh × %d§/h = +%d§ | 🏦 %d → %d" % [
			c.citizen_name, hours_worked, c.job.wage_per_hour,
			daily_wage, before, c.wallet.balance
		])
	print("===========================\n")

func toggle_pause() -> void:
	is_paused = !is_paused
	paused_changed.emit(is_paused)
	
func set_speed(multiplier: float) -> void:
	speed_multiplier = multiplier
	_timer.wait_time = tick_interval_sec / multiplier
	speed_changed.emit(multiplier)
	
func world_day() -> int:
	return time.day

func register_citizen(c: Citizen) -> void:
	if c and not citizens.has(c):
		citizens.append(c)

func register_building(b: Building) -> void:
	if b and not buildings.has(b):
		buildings.append(b)
