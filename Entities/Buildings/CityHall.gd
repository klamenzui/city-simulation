extends Building
class_name CityHall

@export var business_tax_rate: float = 0.10
@export var citizen_tax_rate: float = 0.02
@export var infrastructure_cost_per_day: int = 120
@export var unemployment_support: int = 40
@export var min_operating_balance: int = 400
@export var reserve_transfer_target_balance: int = 1400
@export var reserve_transfer_daily_limit: int = 900

var tax_collected_today: int = 0
var reserve_transfers_today: int = 0
var reserve_transfer_amount_today: int = 0
var public_funding_requested_total_today: int = 0
var public_funding_total_today: int = 0
var university_funding_today: int = 0
var park_funding_today: int = 0
var public_funding_failures_today: int = 0
var infrastructure_paid_today: int = 0
var infrastructure_unpaid_today: int = 0

func _ready() -> void:
	super._ready()
	building_type = BuildingType.CITY_HALL
	apply_balance_settings("city_hall")
	business_tax_rate = BalanceConfig.get_float("economy.city_hall.business_tax_rate", business_tax_rate)
	citizen_tax_rate = BalanceConfig.get_float("economy.city_hall.citizen_tax_rate", citizen_tax_rate)
	infrastructure_cost_per_day = BalanceConfig.get_int("economy.city_hall.infrastructure_cost_per_day", infrastructure_cost_per_day)
	unemployment_support = BalanceConfig.get_int("economy.city_hall.unemployment_support", unemployment_support)
	min_operating_balance = BalanceConfig.get_int("economy.city_hall.min_operating_balance", min_operating_balance)
	reserve_transfer_target_balance = BalanceConfig.get_int("economy.city_hall.reserve_transfer_target_balance", reserve_transfer_target_balance)
	reserve_transfer_daily_limit = BalanceConfig.get_int("economy.city_hall.reserve_transfer_daily_limit", reserve_transfer_daily_limit)
	add_to_group("work")

func get_service_type() -> String:
	return "governance"

func is_city_hall() -> bool:
	return true

func begin_new_day() -> void:
	super.begin_new_day()
	tax_collected_today = 0
	reserve_transfers_today = 0
	reserve_transfer_amount_today = 0
	public_funding_requested_total_today = 0
	public_funding_total_today = 0
	university_funding_today = 0
	park_funding_today = 0
	public_funding_failures_today = 0
	infrastructure_paid_today = 0
	infrastructure_unpaid_today = 0

func ensure_operating_liquidity(world: World, reason: String = "operating") -> int:
	if world == null:
		return 0
	if account.balance >= min_operating_balance:
		return 0
	var remaining_limit := reserve_transfer_daily_limit - reserve_transfer_amount_today
	if remaining_limit <= 0:
		return 0
	var needed := reserve_transfer_target_balance - account.balance
	if needed <= 0:
		return 0
	var granted := mini(needed, mini(remaining_limit, world.city_account.balance))
	if granted <= 0:
		return 0
	if not world.economy.transfer(world.city_account, account, granted):
		return 0
	reserve_transfers_today += 1
	reserve_transfer_amount_today += granted
	SimLogger.log("[CityHall] Reserve transfer +%d EUR | reason=%s city_hall=%d reserve=%d" % [
		granted,
		reason,
		account.balance,
		world.city_account.balance
	])
	return granted

func _get_reserved_welfare_budget(world: World) -> int:
	if world == null or unemployment_support <= 0:
		return 0
	var unemployed := 0
	for citizen in world.citizens:
		if citizen == null:
			continue
		if citizen.job == null or citizen.job.workplace == null:
			unemployed += 1
	return unemployed * unemployment_support

func collect_daily_taxes(world: World) -> void:
	tax_collected_today = 0

	for building in world.buildings:
		if building == null or building == self:
			continue
		if not building.pays_business_tax():
			continue
		var tax_base: int = maxi(building.income_today, 0)
		if tax_base <= 0:
			continue
		var business_tax: int = int(round(float(tax_base) * business_tax_rate))
		if business_tax <= 0:
			continue
		var payable := mini(building.account.balance, business_tax)
		if payable > 0 and world.economy.collect_tax(building.account, account, payable):
			tax_collected_today += payable
			record_income(payable)
			building.record_tax_expense(payable)
		if payable < business_tax:
			building.record_unpaid_taxes(business_tax - payable)

	for citizen in world.citizens:
		if citizen == null:
			continue
		var citizen_tax: int = int(round(float(citizen.wallet.balance) * citizen_tax_rate))
		if citizen_tax <= 0:
			continue
		if world.economy.collect_tax(citizen.wallet, account, citizen_tax):
			tax_collected_today += citizen_tax
			record_income(citizen_tax)

func fund_public_buildings(world: World) -> void:
	if world == null:
		return

	var public_buildings: Array[Building] = []
	for building in world.buildings:
		if building == null or building == self:
			continue
		if not building.requires_public_funding():
			continue
		public_buildings.append(building)

	public_buildings.sort_custom(func(a: Building, b: Building) -> bool:
		return a.get_public_funding_priority() > b.get_public_funding_priority()
	)

	for building in public_buildings:
		var request: int = building.get_public_funding_request()
		building.record_public_funding_request(request)
		public_funding_requested_total_today += request
		if request <= 0:
			if building.account.balance >= 0 and building.is_financially_closed():
				building.reopen_after_funding()
			continue

		ensure_operating_liquidity(world, "public_funding")
		var welfare_reserve := _get_reserved_welfare_budget(world)
		var available_budget := maxi(account.balance - welfare_reserve, 0)
		var granted: int = mini(request, available_budget)
		if granted > 0 and world.economy.fund_public_building(account, building.account, granted):
			record_expense(granted)
			public_funding_total_today += granted
			building.record_public_funding(granted)
			if building.building_type == BuildingType.UNIVERSITY:
				university_funding_today += granted
			elif building.building_type == BuildingType.PARK:
				park_funding_today += granted
			if granted >= request and building.is_financially_closed():
				building.reopen_after_funding()
			else:
				granted = 0

		if granted < request:
			building.record_public_funding_shortfall(request - granted)
			public_funding_failures_today += 1
			SimLogger.log("[CityHall] Public funding shortfall for %s | requested=%d paid=%d shortfall=%d" % [
				building.get_display_name(),
				request,
				granted,
				request - granted
			])

func pay_welfare(world: World, citizen: Citizen, amount: int = -1) -> bool:
	if citizen == null:
		return false
	var payout: int = unemployment_support if amount < 0 else amount
	if payout <= 0:
		return true
	ensure_operating_liquidity(world, "welfare")
	if world.economy.pay_to_wallet(account, citizen, payout):
		record_expense(payout)
		return true
	return false

func pay_salary(world: World, citizen: Citizen, amount: int) -> bool:
	if citizen == null or amount <= 0:
		return false
	if world.economy.pay_to_wallet(account, citizen, amount):
		record_wage_expense(amount)
		return true
	return false

func pay_infrastructure(world: World) -> bool:
	if infrastructure_cost_per_day <= 0:
		return true
	ensure_operating_liquidity(world, "infrastructure")
	var payable := mini(account.balance, infrastructure_cost_per_day)
	if payable > 0 and world.economy.transfer(account, world.city_account, payable):
		record_expense(payable)
		infrastructure_paid_today = payable
	if payable < infrastructure_cost_per_day:
		infrastructure_unpaid_today = infrastructure_cost_per_day - payable
		SimLogger.log("[CityHall] Infrastructure underfunded | requested=%d paid=%d shortfall=%d" % [
			infrastructure_cost_per_day,
			payable,
			infrastructure_unpaid_today
		])
		return false
	return true

func _get_extra_info(_world = null) -> Dictionary:
	var reserve_balance: int = _world.city_account.balance if _world != null else 0
	return {
		"Tax rate (business)": "%.0f%%" % (business_tax_rate * 100.0),
		"Tax rate (citizens)": "%.0f%%" % (citizen_tax_rate * 100.0),
		"Taxes today": "%d EUR" % tax_collected_today,
		"Welfare payment": "%d EUR" % unemployment_support,
		"Reserve balance": "%d EUR" % reserve_balance,
		"Reserve transfers": "%d (%d EUR)" % [reserve_transfers_today, reserve_transfer_amount_today],
		"Min operating balance": "%d EUR" % min_operating_balance,
		"Public funding": "%d EUR" % public_funding_total_today,
		"Public funding requested": "%d EUR" % public_funding_requested_total_today,
		"University funding": "%d EUR" % university_funding_today,
		"Park funding": "%d EUR" % park_funding_today,
		"Funding failures": str(public_funding_failures_today),
		"Infrastructure paid / unpaid": "%d / %d EUR" % [infrastructure_paid_today, infrastructure_unpaid_today],
	}
