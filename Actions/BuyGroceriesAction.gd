extends Action
class_name BuyGroceriesAction

var market: Supermarket
var purchased_units: int = 0

func _init(_market: Supermarket) -> void:
	super()
	label = "BuyGroceries"
	market = _market

func start(world, citizen) -> void:
	super.start(world, citizen)
	purchased_units = 0

	if market == null:
		finished = true
		return
	if not market.is_open(world.time.get_hour()):
		finished = true
		return
	if not market.try_add_visitor(citizen):
		finished = true
		return

	purchased_units = market.buy_groceries(world, citizen)
	if purchased_units > 0:
		citizen.home_food_stock += purchased_units

	finished = true

func finish(world, citizen) -> void:
	if market != null:
		market.remove_visitor(citizen)
