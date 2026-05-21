class_name CitizenIdentity
extends RefCounted

## Pure-data slots that the simulation layer + actions read from / write to.
## Extracted from old `Citizen.gd` lines 11-32.
##
## RefCounted, no behaviour beyond construction defaults. Anything that needs
## logic (validation, NodePath resolution, persistence) lives in `Citizen.gd`;
## Identity is just the bag.
##
## Slot ownership convention:
##   - `wallet`, `needs` are constructed eagerly so callers never see null.
##   - All building/job slots default to null and are filled by the
##     CitizenFactory or by user assignment via NodePath in the Facade.

var citizen_name: String = "Alex"

# Buildings/job — set by Factory or NodePath resolution.
var home: ResidentialBuilding = null
var job: Job = null
var current_location: Building = null

# Behavioural favorites (used by GOAP planner).
var favorite_restaurant: Restaurant = null
var favorite_supermarket: Supermarket = null
var favorite_shop: Shop = null
var favorite_cinema: Cinema = null
var favorite_park: Building = null

# Inventory + progression.
var home_food_stock: int = 2
var clothing_items: int = 0
var education_level: int = 0
# Consecutive days employed at the current workplace. Shown in the UI as
# tenure; reset to 0 on hire/fire so it tracks the current job, not lifetime.
var job_tenure_days: int = 0
# Consecutive days with zero work minutes at the current workplace. Reaches the
# configured limit -> automatic termination.
var job_absence_days: int = 0
# Accumulated experience wage bonus (fraction, e.g. 0.05 = +5%). Grows or shrinks
# daily depending on the workplace profit tier; reset to 0 on hire/fire.
var experience_wage_bonus: float = 0.0

# Always present: economy + needs models.
var wallet: Account = null
var needs: Needs = null


func _init() -> void:
	wallet = Account.new()
	needs = Needs.new()
