extends Building
class_name CityHall

@export var business_tax_rate: float = 0.10
@export var citizen_tax_rate: float = 0.02
@export var infrastructure_cost_per_day: int = 120
@export var unemployment_support: int = 40

var tax_collected_today: int = 0

func _ready() -> void:
	super._ready()
	building_type = BuildingType.CITY_HALL
	open_hour = 6
	close_hour = 19
	capacity = max(capacity, 15)
	if job_capacity <= 0:
		job_capacity = 5
	add_to_group("work")

func get_service_type() -> String:
	return "governance"

func is_city_hall() -> bool:
	return true

func collect_daily_taxes(world: World) -> void:
	tax_collected_today = 0

	for building in world.buildings:
		if building == null or building == self:
			continue
		var tax_base: int = maxi(building.income_today, 0)
		if tax_base <= 0:
			continue
		var business_tax: int = int(round(float(tax_base) * business_tax_rate))
		if business_tax <= 0:
			continue
		if world.economy.transfer(building.account, account, business_tax):
			tax_collected_today += business_tax
			record_income(business_tax)
			building.record_expense(business_tax)

	for citizen in world.citizens:
		if citizen == null:
			continue
		var citizen_tax: int = int(round(float(citizen.wallet.balance) * citizen_tax_rate))
		if citizen_tax <= 0:
			continue
		if world.economy.transfer(citizen.wallet, account, citizen_tax):
			tax_collected_today += citizen_tax
			record_income(citizen_tax)

func pay_welfare(world: World, citizen: Citizen, amount: int = -1) -> bool:
	if citizen == null:
		return false
	var payout: int = unemployment_support if amount < 0 else amount
	if payout <= 0:
		return true
	if world.economy.transfer(account, citizen.wallet, payout):
		record_expense(payout)
		return true
	return false

func pay_salary(world: World, citizen: Citizen, amount: int) -> bool:
	if citizen == null or amount <= 0:
		return false
	if world.economy.transfer(account, citizen.wallet, amount):
		record_expense(amount)
		return true
	return false

func pay_infrastructure(world: World) -> bool:
	if infrastructure_cost_per_day <= 0:
		return true
	if world.economy.transfer(account, world.city_account, infrastructure_cost_per_day):
		record_expense(infrastructure_cost_per_day)
		return true
	return false

func _get_extra_info(_world = null) -> Dictionary:
	return {
		"Tax rate (business)": "%.0f%%" % (business_tax_rate * 100.0),
		"Tax rate (citizens)": "%.0f%%" % (citizen_tax_rate * 100.0),
		"Taxes today": "%d €" % tax_collected_today,
		"Welfare payment": "%d €" % unemployment_support,
	}
