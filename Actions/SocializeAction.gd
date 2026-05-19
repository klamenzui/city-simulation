extends Action
class_name SocializeAction

## Lean social-visit activity (Step 3b). The citizen has already been moved
## to its favorite park by the GOAP go_park step (GoToBuildingAction), so this
## action just spends time "socializing" there and restores the `social` need
## directly. It deliberately does NOT touch the central needs-modifier
## pipeline (which has no social channel) and adds no bench/park-internal
## routing — that keeps `social` fully decoupled, consistent with Step 3a.

const BalanceConfig = preload("res://Simulation/Config/BalanceConfig.gd")

var _social_add_per_min: float = 1.5
var _default_minutes: int = 30
var _min_minutes: int = 20
var _max_minutes: int = 40
var _stop_hunger_threshold: float = 70.0
var _stop_health_threshold: float = 35.0
var _minutes_target: int = 0
var _minutes_elapsed: int = 0

func _init(max_minutes: int = -1) -> void:
	var config: Dictionary = BalanceConfig.get_section("actions.socialize")
	super(0)
	label = "Socialize"
	_social_add_per_min = float(config.get("social_add_per_min", _social_add_per_min))
	_default_minutes = int(config.get("default_minutes", _default_minutes))
	_min_minutes = int(config.get("min_minutes", _min_minutes))
	_max_minutes = int(config.get("max_minutes", _max_minutes))
	if _max_minutes < _min_minutes:
		_max_minutes = _min_minutes
	_stop_hunger_threshold = float(config.get("stop_hunger_threshold", _stop_hunger_threshold))
	_stop_health_threshold = float(config.get("stop_health_threshold", _stop_health_threshold))
	_minutes_target = maxi(max_minutes, 0) if max_minutes >= 0 else randi_range(_min_minutes, _max_minutes)

func start(world, citizen) -> void:
	super.start(world, citizen)
	_minutes_elapsed = 0
	if citizen == null or not (citizen.current_location is Park):
		finished = true

func tick(world, citizen, dt: int) -> void:
	super.tick(world, citizen, dt)
	if citizen == null:
		finished = true
		return
	_minutes_elapsed += dt
	citizen.needs.social = clamp(
		citizen.needs.social + _social_add_per_min * float(dt), 0.0, 100.0)
	if citizen.needs.social >= citizen.needs.TARGET_SOCIAL_MIN \
		or citizen.needs.hunger >= _stop_hunger_threshold \
		or citizen.needs.health <= _stop_health_threshold \
		or _minutes_elapsed >= _minutes_target:
		finished = true

func finish(world, citizen) -> void:
	if citizen == null:
		return
	if citizen.is_travelling():
		citizen.stop_travel()
	if citizen.current_location is Park:
		citizen.leave_current_location(world, false)
	citizen.decision_cooldown_left = 0
