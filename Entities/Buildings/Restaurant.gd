extends Building
class_name Restaurant

@export var meal_price: int = 15
@export var capacity: int = 8

var inside: Array[Citizen] = []

func try_enter(c: Citizen) -> bool:
	if c == null:
		return false
	if inside.size() >= capacity:
		return false
	if inside.has(c):
		return true
	inside.append(c)
	return true

func leave(c: Citizen) -> void:
	inside.erase(c)

# BUG FIX: sell_meal previously reduced hunger here AND in the action tick,
# causing double (or conflicting) hunger restoration.
# Now sell_meal ONLY handles the money transfer.
# Hunger reduction is done gradually in EatAtRestaurantAction.tick().
func sell_meal(world: World, buyer: Citizen) -> bool:
	if buyer == null:
		return false
	return world.economy.transfer(buyer.wallet, account, meal_price)
