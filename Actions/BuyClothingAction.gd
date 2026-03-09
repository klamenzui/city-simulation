extends Action
class_name BuyClothingAction

var shop: Shop
var _purchased := false

func _init(_shop: Shop) -> void:
	super()
	label = "BuyClothes"
	shop = _shop

func start(world, citizen) -> void:
	super.start(world, citizen)
	_purchased = false

	if shop == null:
		finished = true
		return
	if not shop.is_open(world.time.get_hour()):
		finished = true
		return
	if not shop.try_add_visitor(citizen):
		finished = true
		return

	_purchased = shop.buy_item(world, citizen, 1.2)
	finished = true

func finish(world, citizen) -> void:
	if shop != null:
		shop.remove_visitor(citizen)
