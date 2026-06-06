extends Building
class_name Bank

@export var min_operating_reserve: int = 3000
@export var borrower_cash_reserve: int = 220
@export var liquidity_target_days: float = 2.0
@export var max_loan_per_building: int = 800
@export var max_debt_per_building: int = 2400
@export var max_daily_lending: int = 3200
@export_range(0.0, 1.0, 0.01) var repayment_rate: float = 0.25
@export_range(0.0, 1.0, 0.001) var interest_rate_per_day: float = 0.03
@export var service_fee_per_loan: int = 6

var loan_principal_by_borrower_id: Dictionary = {}
var loan_interest_due_by_borrower_id: Dictionary = {}
var borrower_name_by_id: Dictionary = {}

var loans_issued_today: int = 0
var principal_lent_today: int = 0
var principal_repaid_today: int = 0
var interest_income_today: int = 0
var service_fee_income_today: int = 0

func _ready() -> void:
	super._ready()
	building_type = BuildingType.BANK
	var settings := apply_balance_settings("bank")
	min_operating_reserve = int(settings.get("min_operating_reserve", min_operating_reserve))
	borrower_cash_reserve = int(settings.get("borrower_cash_reserve", borrower_cash_reserve))
	liquidity_target_days = float(settings.get("liquidity_target_days", liquidity_target_days))
	max_loan_per_building = int(settings.get("max_loan_per_building", max_loan_per_building))
	max_debt_per_building = int(settings.get("max_debt_per_building", max_debt_per_building))
	max_daily_lending = int(settings.get("max_daily_lending", max_daily_lending))
	repayment_rate = float(settings.get("repayment_rate", repayment_rate))
	interest_rate_per_day = float(settings.get("interest_rate_per_day", interest_rate_per_day))
	service_fee_per_loan = int(settings.get("service_fee_per_loan", service_fee_per_loan))
	add_to_group("work")

func get_service_type() -> String:
	return "finance"

func begin_new_day() -> void:
	super.begin_new_day()
	loans_issued_today = 0
	principal_lent_today = 0
	principal_repaid_today = 0
	interest_income_today = 0
	service_fee_income_today = 0

func run_daily_financial_services(world: World) -> Dictionary:
	var summary := _empty_summary()
	if world == null or world.economy == null:
		return summary
	if is_financially_closed() or not has_required_staff():
		return summary

	_prune_invalid_borrowers()
	_collect_daily_repayments(world, summary)
	_issue_liquidity_loans(world, summary)
	summary["outstanding_principal"] = get_outstanding_principal()
	summary["borrowers"] = get_borrower_count()
	return summary

func request_business_loan(world: World, borrower: Building, requested_amount: int, reason: String = "") -> int:
	if world == null or world.economy == null or borrower == null:
		return 0
	if not _can_lend_to(borrower):
		return 0
	var amount := _clamp_loan_amount(borrower, requested_amount, max_loan_per_building)
	if amount <= 0:
		return 0
	if not world.economy.transfer(account, borrower.account, amount):
		return 0

	var borrower_id := borrower.get_instance_id()
	loan_principal_by_borrower_id[borrower_id] = int(loan_principal_by_borrower_id.get(borrower_id, 0)) + amount
	borrower_name_by_id[borrower_id] = borrower.get_display_name()
	loans_issued_today += 1
	principal_lent_today += amount

	var fee := mini(service_fee_per_loan, borrower.account.balance)
	if fee > 0 and world.economy.transfer(borrower.account, account, fee):
		service_fee_income_today += fee
		record_income(fee)
		borrower.record_expense(fee)

	var suffix := " reason=%s" % reason if not reason.strip_edges().is_empty() else ""
	SimLogger.log("[Bank %s] Loan +%d EUR to %s debt=%d%s" % [
		get_display_name(),
		amount,
		borrower.get_display_name(),
		get_business_debt(borrower),
		suffix
	])
	return amount

func get_business_debt(borrower: Building) -> int:
	if borrower == null:
		return 0
	var borrower_id := borrower.get_instance_id()
	return int(loan_principal_by_borrower_id.get(borrower_id, 0)) \
		+ int(loan_interest_due_by_borrower_id.get(borrower_id, 0))

func get_outstanding_principal() -> int:
	var total := 0
	for value in loan_principal_by_borrower_id.values():
		total += int(value)
	return total

func get_borrower_count() -> int:
	var count := 0
	for borrower_id in loan_principal_by_borrower_id.keys():
		if int(loan_principal_by_borrower_id.get(borrower_id, 0)) > 0 \
				or int(loan_interest_due_by_borrower_id.get(borrower_id, 0)) > 0:
			count += 1
	return count

func _issue_liquidity_loans(world: World, summary: Dictionary) -> void:
	var daily_remaining := maxi(max_daily_lending - principal_lent_today, 0)
	if daily_remaining <= 0:
		return

	for candidate in world.buildings:
		if daily_remaining <= 0:
			break
		if candidate == null or candidate == self:
			continue
		if not _can_lend_to(candidate):
			continue
		var requested := _estimate_liquidity_gap(candidate, world)
		if requested <= 0:
			continue
		var lent := request_business_loan(world, candidate, mini(requested, daily_remaining), "daily_liquidity")
		if lent <= 0:
			continue
		daily_remaining -= lent
		summary["loaned"] = int(summary.get("loaned", 0)) + lent
		summary["loans"] = int(summary.get("loans", 0)) + 1

func _collect_daily_repayments(world: World, summary: Dictionary) -> void:
	for borrower_id_var in loan_principal_by_borrower_id.keys().duplicate():
		var borrower_id := int(borrower_id_var)
		var borrower := instance_from_id(borrower_id) as Building
		if borrower == null or not is_instance_valid(borrower):
			_clear_borrower(borrower_id)
			continue

		var principal := int(loan_principal_by_borrower_id.get(borrower_id, 0))
		if principal <= 0:
			_clear_borrower_if_empty(borrower_id)
			continue

		var new_interest := int(ceil(float(principal) * maxf(interest_rate_per_day, 0.0)))
		if new_interest > 0:
			loan_interest_due_by_borrower_id[borrower_id] = int(loan_interest_due_by_borrower_id.get(borrower_id, 0)) + new_interest

		var available_cash := maxi(borrower.account.balance - borrower_cash_reserve, 0)
		if available_cash <= 0:
			continue

		var interest_due := int(loan_interest_due_by_borrower_id.get(borrower_id, 0))
		var principal_due := maxi(int(ceil(float(principal) * clampf(repayment_rate, 0.0, 1.0))), 1)
		var requested_payment := mini(available_cash, interest_due + principal_due)
		if requested_payment <= 0:
			continue

		var interest_paid := mini(interest_due, requested_payment)
		var principal_paid := mini(principal, requested_payment - interest_paid)
		var paid := interest_paid + principal_paid
		if paid <= 0 or not world.economy.transfer(borrower.account, account, paid):
			continue

		if interest_paid > 0:
			loan_interest_due_by_borrower_id[borrower_id] = interest_due - interest_paid
			interest_income_today += interest_paid
			record_income(interest_paid)
			borrower.record_expense(interest_paid)
		if principal_paid > 0:
			loan_principal_by_borrower_id[borrower_id] = principal - principal_paid
			principal_repaid_today += principal_paid

		summary["repaid"] = int(summary.get("repaid", 0)) + paid
		summary["interest"] = int(summary.get("interest", 0)) + interest_paid
		_clear_borrower_if_empty(borrower_id)

func _can_lend_to(borrower: Building) -> bool:
	if borrower == null or borrower == self:
		return false
	if borrower is Bank:
		return false
	if borrower.is_financially_closed():
		return false
	if not borrower.is_economic_building():
		return false
	if not has_available_lending_cash():
		return false
	return get_business_debt(borrower) < max_debt_per_building

func has_available_lending_cash() -> bool:
	return account != null and account.balance > min_operating_reserve

func _clamp_loan_amount(borrower: Building, requested_amount: int, local_cap: int) -> int:
	var amount := maxi(requested_amount, 0)
	amount = mini(amount, maxi(local_cap, 0))
	amount = mini(amount, maxi(max_debt_per_building - get_business_debt(borrower), 0))
	amount = mini(amount, maxi(account.balance - min_operating_reserve, 0))
	return amount

func _estimate_liquidity_gap(borrower: Building, world: World) -> int:
	if borrower == null:
		return 0
	var daily_obligations := borrower.get_total_daily_obligation_estimate(world)
	var target_balance := borrower_cash_reserve + int(ceil(float(daily_obligations) * maxf(liquidity_target_days, 0.0)))
	if borrower.account.balance >= target_balance:
		return 0
	return target_balance - borrower.account.balance

func _prune_invalid_borrowers() -> void:
	for borrower_id_var in loan_principal_by_borrower_id.keys().duplicate():
		var borrower_id := int(borrower_id_var)
		var borrower := instance_from_id(borrower_id)
		if borrower == null or not is_instance_valid(borrower):
			_clear_borrower(borrower_id)

func _clear_borrower_if_empty(borrower_id: int) -> void:
	if int(loan_principal_by_borrower_id.get(borrower_id, 0)) > 0:
		return
	if int(loan_interest_due_by_borrower_id.get(borrower_id, 0)) > 0:
		return
	_clear_borrower(borrower_id)

func _clear_borrower(borrower_id: int) -> void:
	loan_principal_by_borrower_id.erase(borrower_id)
	loan_interest_due_by_borrower_id.erase(borrower_id)
	borrower_name_by_id.erase(borrower_id)

func _empty_summary() -> Dictionary:
	return {
		"loans": 0,
		"loaned": 0,
		"repaid": 0,
		"interest": 0,
		"outstanding_principal": get_outstanding_principal(),
		"borrowers": get_borrower_count(),
	}

func _get_extra_info(_world = null) -> Dictionary:
	return {
		"Outstanding loans": "%d EUR" % get_outstanding_principal(),
		"Borrowers": "%d" % get_borrower_count(),
		"Loaned today": "%d EUR" % principal_lent_today,
		"Repaid today": "%d EUR" % principal_repaid_today,
		"Interest today": "%d EUR" % interest_income_today,
		"Fees today": "%d EUR" % service_fee_income_today,
		"Reserve": "%d EUR" % min_operating_reserve,
	}
