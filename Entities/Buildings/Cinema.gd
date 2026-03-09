extends Building
class_name Cinema

@export var ticket_price: int = 14

func _ready() -> void:
	super._ready()
	building_type = BuildingType.CINEMA
	open_hour = 12
	close_hour = 23
	capacity = max(capacity, 35)
	if job_capacity <= 0:
		job_capacity = 5
	add_to_group("work")

func get_service_type() -> String:
	return "fun"

func try_enter(citizen: Citizen) -> bool:
	return try_add_visitor(citizen)

func leave(citizen: Citizen) -> void:
	remove_visitor(citizen)

func buy_ticket(world: World, citizen: Citizen) -> bool:
	if citizen == null:
		return false
	if not world.economy.transfer(citizen.wallet, account, ticket_price):
		return false
	record_income(ticket_price)
	return true

func _get_extra_info(_world = null) -> Dictionary:
	return {
		"Ticket": "%d €" % ticket_price,
	}
