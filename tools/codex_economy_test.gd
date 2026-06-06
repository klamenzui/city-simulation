extends SceneTree

const EconomySystemScript = preload("res://Simulation/EconomySystem.gd")
const WorldScript = preload("res://Simulation/World.gd")
const AccountScript = preload("res://Entities/Account.gd")
const JobScript = preload("res://Entities/Job.gd")
const BuildingScript = preload("res://Entities/Buildings/Building.gd")
const CityHallScript = preload("res://Entities/Buildings/CityHall.gd")
const HospitalScript = preload("res://Entities/Buildings/Hospital.gd")
const BankScript = preload("res://Entities/Buildings/Bank.gd")
const ResidentialBuildingScript = preload("res://Entities/Buildings/ResidentialBuilding.gd")
const CitizenScript = preload("res://Entities/Citizens/New/Citizen.gd")
const CitizenFactoryScript = preload("res://Simulation/Factories/CitizenFactory.gd")
const BuildingUseBinderScript = preload("res://Simulation/Bootstrap/BuildingUseBinder.gd")

var _checks_run: int = 0
var _current_error: String = ""

func _initialize() -> void:
	var failed: Array[String] = []

	for test_name in [
		"transfer",
		"market_buy_sell",
		"price_and_daily_reset",
		"open_jobs",
		"public_buildings_are_tax_exempt",
		"reserve_transfer_supports_city_hall_liquidity",
		"public_funding_covers_public_payroll",
		"hospital_treatment_uses_public_subsidy",
		"hospital_charity_care_tracks_unfunded_shortfall",
		"public_underfunding_is_soft_before_closure",
		"maintenance_shortfall_is_soft_before_closure",
		"unemployed_citizens_seek_new_jobs",
		"critical_public_staffing_retargets_unemployed",
		"economic_buildings_struggle_before_closure",
		"bank_lends_and_collects_repayment",
		"bank_binder_uses_nested_entrance",
		"extended_building_use_binder_creates_real_units",
		"teaching_jobs_require_degree",
		"tax_and_welfare",
		"citizen_pay_rent",
	]:
		var error := _run_test(test_name)
		if error != "":
			failed.append("%s: %s" % [test_name, error])

	if failed.is_empty():
		print("ECON_TEST OK checks=%d" % _checks_run)
		quit(0)
		return

	for failure in failed:
		push_error(failure)
	print("ECON_TEST FAIL count=%d" % failed.size())
	quit(1)

func _run_test(test_name: String) -> String:
	_current_error = ""
	match test_name:
		"transfer":
			return _test_transfer()
		"market_buy_sell":
			return _test_market_buy_sell()
		"price_and_daily_reset":
			return _test_price_and_daily_reset()
		"open_jobs":
			return _test_open_jobs()
		"public_buildings_are_tax_exempt":
			return _test_public_buildings_are_tax_exempt()
		"reserve_transfer_supports_city_hall_liquidity":
			return _test_reserve_transfer_supports_city_hall_liquidity()
		"public_funding_covers_public_payroll":
			return _test_public_funding_covers_public_payroll()
		"hospital_treatment_uses_public_subsidy":
			return _test_hospital_treatment_uses_public_subsidy()
		"hospital_charity_care_tracks_unfunded_shortfall":
			return _test_hospital_charity_care_tracks_unfunded_shortfall()
		"public_underfunding_is_soft_before_closure":
			return _test_public_underfunding_is_soft_before_closure()
		"maintenance_shortfall_is_soft_before_closure":
			return _test_maintenance_shortfall_is_soft_before_closure()
		"unemployed_citizens_seek_new_jobs":
			return _test_unemployed_citizens_seek_new_jobs()
		"critical_public_staffing_retargets_unemployed":
			return _test_critical_public_staffing_retargets_unemployed()
		"economic_buildings_struggle_before_closure":
			return _test_economic_buildings_struggle_before_closure()
		"bank_lends_and_collects_repayment":
			return _test_bank_lends_and_collects_repayment()
		"bank_binder_uses_nested_entrance":
			return _test_bank_binder_uses_nested_entrance()
		"extended_building_use_binder_creates_real_units":
			return _test_extended_building_use_binder_creates_real_units()
		"teaching_jobs_require_degree":
			return _test_teaching_jobs_require_degree()
		"tax_and_welfare":
			return _test_tax_and_welfare()
		"citizen_pay_rent":
			return _test_citizen_pay_rent()
		_:
			return "unknown test"

func _test_transfer() -> String:
	var economy = _new_economy()
	var alice = _new_account("Alice", 120)
	var bob = _new_account("Bob", 15)

	_expect(economy.transfer(alice, bob, 35), "transfer should succeed")
	_expect_eq(alice.balance, 85, "sender balance after transfer")
	_expect_eq(bob.balance, 50, "receiver balance after transfer")
	_expect(not economy.transfer(alice, bob, 500), "transfer should fail when sender lacks balance")
	_expect_eq(alice.balance, 85, "sender balance should stay unchanged on failed transfer")
	_expect_eq(bob.balance, 50, "receiver balance should stay unchanged on failed transfer")
	_free_node(economy)
	return _current_error

func _test_market_buy_sell() -> String:
	var economy = _new_economy()
	var buyer = _new_account("Buyer", 5000)
	var seller = _new_account("Seller", 100)
	var stock_before: int = economy.commodity_stock["food"]
	var market_before: int = economy.market_account.balance

	var purchase: Dictionary = economy.buy_wholesale(buyer, "food", 120)
	_expect_eq(purchase["qty"], 120, "buyer should receive requested quantity when stock and money allow it")
	_expect(int(purchase["unit_price"]) > 0, "wholesale unit price should be positive")
	_expect_eq(
		int(economy.commodity_stock["food"]),
		stock_before - 120,
		"market stock should shrink after wholesale buy"
	)
	_expect_eq(
		economy.market_account.balance,
		market_before + int(purchase["total_cost"]),
		"market account should receive wholesale payment"
	)

	var sale: Dictionary = economy.sell_wholesale_to_market(seller, "food", 80)
	_expect_eq(sale["qty"], 80, "market should buy offered quantity when it can afford it")
	_expect(int(sale["unit_price"]) > 0, "producer unit price should be positive")
	_expect_eq(
		int(economy.commodity_stock["food"]),
		stock_before - 40,
		"market stock should reflect buy then sell sequence"
	)
	_expect_eq(
		seller.balance,
		100 + int(sale["total_revenue"]),
		"seller should receive market payout"
	)
	_free_node(economy)
	return _current_error

func _test_price_and_daily_reset() -> String:
	var economy = _new_economy()

	var normal_price: int = economy.get_wholesale_unit_price("clothes")
	economy.commodity_stock["clothes"] = 5
	economy.commodity_demand_today["clothes"] = 700
	economy.commodity_supply_today["clothes"] = 0
	var scarcity_price: int = economy.get_wholesale_unit_price("clothes")
	_expect(scarcity_price > normal_price, "scarcity should push prices up")

	economy.commodity_stock["food"] = 10
	economy.commodity_demand_today["food"] = 55
	economy.commodity_supply_today["food"] = 33
	economy.begin_new_day()
	_expect(int(economy.commodity_stock["food"]) > 10, "daily import safety net should refill very low stock")
	_expect_eq(int(economy.commodity_demand_today["food"]), 0, "daily demand should reset")
	_expect_eq(int(economy.commodity_supply_today["food"]), 0, "daily supply should reset")
	_expect((economy.commodity_price_history["food"] as Array).size() >= 1, "price history should record a daily sample")
	_free_node(economy)
	return _current_error

func _test_open_jobs() -> String:
	var economy = _new_economy()
	var building = _new_building("Shop", BuildingScript.BuildingType.SHOP, 0, 2)
	var job = JobScript.new()
	job.workplace = building
	var allowed_types: Array[int] = [BuildingScript.BuildingType.SHOP]
	job.allowed_building_types = allowed_types

	economy.register_job(job)
	economy.register_job(job)
	_expect_eq(economy.jobs.size(), 1, "register_job should deduplicate the same job")
	_expect_eq(economy.get_open_jobs().size(), 1, "job should be open while workplace has capacity")
	economy.unregister_job(job)
	_expect_eq(economy.jobs.size(), 0, "unregister_job should remove the job from the economy registry")
	_expect_eq(economy.get_open_jobs().size(), 0, "removed jobs should no longer appear as open")
	economy.register_job(job)

	var worker_a = _new_citizen("Worker A")
	var worker_b = _new_citizen("Worker B")
	building.workers.append(worker_a)
	building.workers.append(worker_b)
	_expect_eq(economy.get_open_jobs().size(), 0, "job should close when workplace capacity is full")
	building.close_due_to_finance(null, "test")
	_expect_eq(economy.get_open_jobs().size(), 0, "closed buildings should not expose open jobs")

	_free_nodes([worker_a, worker_b, building])
	_free_node(economy)
	return _current_error

func _test_public_buildings_are_tax_exempt() -> String:
	var world = _new_world()
	var city_hall = _new_city_hall(0)
	var university = _new_building("University", BuildingScript.BuildingType.UNIVERSITY, 0)
	var park = _new_building("Park", BuildingScript.BuildingType.PARK, 0)
	var shop = _new_building("Shop", BuildingScript.BuildingType.SHOP, 1000)
	var taxpayer = _new_citizen("Taxpayer")
	taxpayer.wallet.balance = 200

	university.income_today = 600
	park.income_today = 400
	shop.income_today = 1000

	world.buildings.append(city_hall)
	world.buildings.append(university)
	world.buildings.append(park)
	world.buildings.append(shop)
	world.citizens.append(taxpayer)

	city_hall.collect_daily_taxes(world)

	_expect_eq(city_hall.tax_collected_today, 104, "city hall should only tax economic buildings plus citizens")
	_expect_eq(shop.taxes_today, 100, "economic building should pay business tax")
	_expect_eq(university.taxes_today, 0, "public university should not pay business tax")
	_expect_eq(park.taxes_today, 0, "public park should not pay business tax")
	_expect_eq(city_hall.account.balance, 104, "city hall should receive collected tax money")

	_free_nodes([taxpayer, shop, park, university, city_hall])
	_free_world(world)
	return _current_error

func _test_reserve_transfer_supports_city_hall_liquidity() -> String:
	var world = _new_world()
	var city_hall = _new_city_hall(80)
	world.city_account.balance = 700
	city_hall.min_operating_balance = 300
	city_hall.reserve_transfer_target_balance = 600
	city_hall.reserve_transfer_daily_limit = 250

	var transferred := city_hall.ensure_operating_liquidity(world, "test")
	_expect_eq(transferred, 250, "city hall should only draw up to the daily reserve transfer limit")
	_expect_eq(city_hall.account.balance, 330, "city hall balance should increase after reserve transfer")
	_expect_eq(world.city_account.balance, 450, "city reserve should shrink by the transferred amount")

	_free_nodes([city_hall])
	_free_world(world)
	return _current_error

func _test_public_funding_covers_public_payroll() -> String:
	var world = _new_world()
	var city_hall = _new_city_hall(1500)
	city_hall.business_tax_rate = 0.0
	city_hall.citizen_tax_rate = 0.0
	city_hall.infrastructure_cost_per_day = 0
	var university = _new_building("University", BuildingScript.BuildingType.UNIVERSITY, 0, 3)
	var professor = _assign_worker(university, "Professor Ada", "Professor", 28, 8.0)
	var janitor = _assign_worker(university, "Janitor Max", "Janitor", 13, 8.0)

	university.base_operating_cost = 120
	university.maintenance_cost_per_day = 30
	professor.work_minutes_today = 8 * 60
	janitor.work_minutes_today = 8 * 60

	world.buildings.append(city_hall)
	world.buildings.append(university)
	world.citizens.append(professor)
	world.citizens.append(janitor)

	var request_before := university.get_public_funding_request()
	city_hall.fund_public_buildings(world)
	var professor_wage := 28 * 8
	var janitor_wage := 13 * 8
	var expected_obligation: int = 120 + professor_wage + janitor_wage + university.maintenance_cost_per_day
	var professor_before: int = professor.wallet.balance
	var janitor_before: int = janitor.wallet.balance
	var paid_professor: String = world._pay_salary(professor, professor_wage, city_hall)
	var paid_janitor: String = world._pay_salary(janitor, janitor_wage, city_hall)
	var maintenance_ok: bool = university.pay_daily_maintenance(world)
	var operating_ok: bool = university.pay_base_operating_cost(world)

	_expect(request_before > 0, "public funding request should include public payroll and operating costs")
	_expect_eq(university.get_total_daily_obligation_estimate(), expected_obligation, "daily obligation should be computed from base cost, payroll and maintenance")
	_expect_eq(request_before, expected_obligation, "public funding request should match the computed daily obligation when no debt exists")
	_expect_eq(university.public_funding_today, request_before, "city hall should fully fund the university request when budget allows")
	_expect_eq(paid_professor, "work", "public university wage should still be paid by the university account")
	_expect_eq(paid_janitor, "work", "public university janitor wage should be paid by the university account")
	_expect(maintenance_ok, "public university should be able to pay maintenance after city hall funding")
	_expect(operating_ok, "public university should be able to pay daily operating cost after city hall funding")
	_expect_eq(professor.wallet.balance, professor_before + professor_wage, "professor should receive wage out of publicly funded university account")
	_expect_eq(janitor.wallet.balance, janitor_before + janitor_wage + university.maintenance_cost_per_day, "janitor should receive wage plus maintenance payment")
	_expect_eq(university.operating_costs_today, 120, "daily public operating cost should be tracked")
	_expect(not university.is_financially_closed(), "public building should stay open when its funding request was met")
	university.finalize_daily_financial_state(world)
	_expect_eq(university.public_funding_shortfall_today, 0, "fully paid public funding must not record a shortfall")
	_expect(not university.is_underfunded(), "fully funded public building should not remain underfunded")

	_free_nodes([janitor, professor, university, city_hall])
	_free_world(world)
	return _current_error

func _test_hospital_treatment_uses_public_subsidy() -> String:
	var world = _new_world()
	var city_hall = _new_city_hall(1000)
	var hospital = _new_hospital(0)
	var doctor = _assign_worker(hospital, "Doctor Mara", "Doctor", 30, 8.0)
	var patient = _new_citizen("Patient Robin")
	patient.wallet.balance = 40
	patient.needs.health = 10.0
	world.buildings.append(city_hall)
	world.buildings.append(hospital)
	world.citizens.append(patient)
	world._city_halls.append(city_hall)

	_expect(hospital.has_core_medical_staff(), "hospital should be operational with a Doctor")
	_expect(hospital.request_treatment(patient, world, false), "staffed hospital should accept a patient")
	_expect(hospital.can_start_treatment(patient), "queued patient should start treatment when capacity is available")
	var payment: Dictionary = hospital.begin_treatment(patient, world, false)

	_expect(bool(payment.get("started", false)), "treatment should start")
	_expect_eq(int(payment.get("paid", 0)), 5, "citizen should only pay above the configured reserve")
	_expect_eq(int(payment.get("subsidy", 0)), 20, "city hall should subsidize treatment shortfall")
	_expect_eq(int(payment.get("charity", 0)), 0, "fully subsidized care should not become charity care")
	_expect_eq(patient.wallet.balance, 35, "hospital payment should preserve the citizen reserve")
	_expect_eq(hospital.account.balance, 25, "hospital account should receive citizen payment plus public subsidy")
	_expect_eq(city_hall.hospital_funding_today, 20, "city hall should track hospital treatment subsidy")
	_expect(hospital.get_effective_healing_per_minute(false) > 0.0, "staffed hospital should provide positive healing")

	_free_nodes([patient, doctor, hospital, city_hall])
	_free_world(world)
	return _current_error

func _test_hospital_charity_care_tracks_unfunded_shortfall() -> String:
	var world = _new_world()
	var city_hall = _new_city_hall(0)
	var hospital = _new_hospital(0)
	var doctor = _assign_worker(hospital, "Doctor Lee", "Doctor", 30, 8.0)
	var patient = _new_citizen("Patient Sam")
	patient.wallet.balance = 0
	patient.needs.health = 4.0
	world.city_account.balance = 0
	world.buildings.append(city_hall)
	world.buildings.append(hospital)
	world.citizens.append(patient)
	world._city_halls.append(city_hall)

	_expect(hospital.request_treatment(patient, world, true), "emergency patient should be accepted when capacity exists")
	var payment: Dictionary = hospital.begin_treatment(patient, world, true)

	_expect(bool(payment.get("started", false)), "emergency treatment should still start without patient money")
	_expect_eq(int(payment.get("paid", 0)), 0, "cashless citizen should not pay")
	_expect_eq(int(payment.get("subsidy", 0)), 0, "empty city hall should not create subsidy money")
	_expect_eq(int(payment.get("charity", 0)), hospital.emergency_treatment_price, "unfunded emergency care should be tracked as charity care")
	_expect_eq(hospital.charity_care_today, hospital.emergency_treatment_price, "hospital should accumulate charity-care cost")
	_expect(hospital.public_funding_shortfall_today >= hospital.emergency_treatment_price, "hospital should expose public funding shortfall")

	_free_nodes([patient, doctor, hospital, city_hall])
	_free_world(world)
	return _current_error

func _test_public_underfunding_is_soft_before_closure() -> String:
	var world = _new_world()
	var city_hall = _new_city_hall(0)
	city_hall.business_tax_rate = 0.0
	city_hall.citizen_tax_rate = 0.0
	city_hall.min_operating_balance = 0
	city_hall.reserve_transfer_daily_limit = 0
	var university = _new_building("University", BuildingScript.BuildingType.UNIVERSITY, 0, 1)
	university.base_operating_cost = 120
	university.max_underfunded_days_before_closure = 3

	world.buildings.append(city_hall)
	world.buildings.append(university)

	for day_idx in range(2):
		city_hall.begin_new_day()
		university.begin_new_day()
		city_hall.fund_public_buildings(world)
		university.finalize_daily_financial_state(world)
		_expect(university.is_underfunded(), "public building should enter underfunded state on day %d" % (day_idx + 1))
		_expect(not university.is_financially_closed(), "public building should stay open before max underfunded days are reached")

	city_hall.begin_new_day()
	university.begin_new_day()
	city_hall.fund_public_buildings(world)
	university.finalize_daily_financial_state(world)
	_expect(university.is_financially_closed(), "public building should only close after repeated underfunded days")

	_free_nodes([university, city_hall])
	_free_world(world)
	return _current_error

func _test_maintenance_shortfall_is_soft_before_closure() -> String:
	var world = _new_world()
	var workshop = _new_building("Workshop", BuildingScript.BuildingType.SHOP, 10, 1)
	workshop.maintenance_cost_per_day = 30
	workshop.condition = 45.0
	workshop.repair_threshold = 60.0
	workshop.max_missed_payment_days_before_closure = 3

	var worker = _assign_worker(workshop, "Maintainer", "MaintenanceWorker", 16, 8.0)
	# One minute marks attendance without adding meaningful payroll cost; this test
	# isolates maintenance shortfall from the absence-termination rule.
	worker.work_minutes_today = 1
	worker._world_ref = world

	world.buildings.append(workshop)
	world.citizens.append(worker)

	for day_idx in range(2):
		world._on_payday()
		_expect(workshop.is_struggling(), "building should become struggling after maintenance shortfall on day %d" % (day_idx + 1))
		_expect(not workshop.is_financially_closed(), "building should not close on the first missed maintenance days")

	world._on_payday()
	_expect(workshop.is_financially_closed(), "building should close only after repeated missed maintenance days")
	_expect_eq(workshop.workers.size(), 0, "closing should fire all workers")
	_expect(worker.job != null and worker.job.workplace == null, "worker should lose workplace when the building closes")

	_free_nodes([worker, workshop])
	_free_world(world)
	return _current_error

func _test_unemployed_citizens_seek_new_jobs() -> String:
	var world = _new_world()
	var closed_shop = _new_building("Closed Shop", BuildingScript.BuildingType.SHOP, 50, 1)
	var open_shop = _new_building("Open Shop", BuildingScript.BuildingType.SHOP, 200, 1)
	closed_shop.position = Vector3.ZERO
	open_shop.position = Vector3(6.0, 0.0, 0.0)

	var citizen = _new_citizen("Applicant")
	citizen.position = Vector3.ZERO
	citizen.job = _new_job("Verkaeufer", 13, 8.0, closed_shop, [BuildingScript.BuildingType.SHOP], "")
	citizen._world_ref = world
	closed_shop.try_hire(citizen)

	world.buildings.append(closed_shop)
	world.buildings.append(open_shop)
	world.citizens.append(citizen)

	closed_shop.close_due_to_finance(world, "bankrupt")

	_expect(citizen.job != null and citizen.job.workplace == open_shop, "citizen should immediately search and find a replacement workplace")
	_expect(open_shop.workers.has(citizen), "replacement workplace should hire the citizen")

	_free_nodes([citizen, open_shop, closed_shop])
	_free_world(world)
	return _current_error

func _test_critical_public_staffing_retargets_unemployed() -> String:
	var world = _new_world()
	var university = _new_building("University", BuildingScript.BuildingType.UNIVERSITY, 120, 3)
	var shop = _new_building("Shop", BuildingScript.BuildingType.SHOP, 120, 2)
	university.position = Vector3.ZERO
	shop.position = Vector3(3.0, 0.0, 0.0)

	var citizen = _new_citizen("Retarget Applicant")
	citizen.position = Vector3.ZERO
	citizen.education_level = 0
	citizen.job = _new_job("Professor", 28, 8.0, null, [BuildingScript.BuildingType.UNIVERSITY], "")
	citizen._world_ref = world

	world.buildings.append(university)
	world.buildings.append(shop)
	world.citizens.append(citizen)

	citizen.notify_job_lost(null, "retarget")

	_expect(citizen.job != null and citizen.job.title == "Teacher", "critical public staffing should retarget the citizen to teacher first")
	_expect(citizen.job != null and citizen.job.workplace == university, "retargeted teacher should be assigned to the university")
	_expect(university.workers.has(citizen), "university should hire the retargeted citizen")

	_free_nodes([citizen, shop, university])
	_free_world(world)
	return _current_error

func _test_economic_buildings_struggle_before_closure() -> String:
	var shop = _new_building("Shop", BuildingScript.BuildingType.SHOP, 40, 0)
	shop.max_missed_payment_days_before_closure = 3

	for _day in range(2):
		shop.begin_new_day()
		shop.record_unpaid_wages(50)
		shop.finalize_daily_financial_state(null)
		_expect(shop.is_struggling(), "economic building should enter struggling state after a missed wage day")
		_expect(not shop.is_financially_closed(), "economic building should stay open during early struggling days")

	shop.begin_new_day()
	shop.record_unpaid_wages(50)
	shop.finalize_daily_financial_state(null)
	_expect(shop.is_financially_closed(), "economic building should close only after repeated missed wage days")

	_free_nodes([shop])
	return _current_error

func _test_bank_lends_and_collects_repayment() -> String:
	var world = _new_world()
	var bank: Bank = BankScript.new()
	bank.name = "Bank"
	bank.building_name = "Bank"
	bank.building_type = BuildingScript.BuildingType.BANK
	bank.account.balance = 2000
	bank.job_capacity = 1
	bank.min_operating_reserve = 1000
	bank.borrower_cash_reserve = 220
	bank.max_loan_per_building = 500
	bank.max_debt_per_building = 1000
	bank.max_daily_lending = 500
	bank.interest_rate_per_day = 0.03
	bank.repayment_rate = 0.25
	bank.service_fee_per_loan = 6
	var banker := _assign_worker(bank, "Banker", "Banker", 23, 8.0)

	var shop := _new_building("Shop", BuildingScript.BuildingType.SHOP, 10, 0)
	world.buildings.append(shop)

	_expect_eq(bank.get_service_type(), "finance", "bank should use finance service type")
	_expect_eq(bank.get_default_job_title(), "Banker", "bank should expose banker as default job")
	_expect(
		CitizenFactoryScript.get_allowed_building_types_for_job_title("Banker").has(BuildingScript.BuildingType.BANK),
		"banker job should be allowed at bank buildings"
	)

	var summary := bank.run_daily_financial_services(world)
	var loaned := int(summary.get("loaned", 0))
	_expect(loaned > 0, "bank should lend to an under-liquid economic building")
	_expect_eq(bank.get_business_debt(shop), loaned, "loan principal should become borrower debt")
	_expect_eq(shop.account.balance, 10 + loaned - bank.service_fee_per_loan, "borrower should receive loan minus service fee")
	_expect_eq(bank.service_fee_income_today, bank.service_fee_per_loan, "bank should record service fee income")

	shop.account.balance = 1000
	bank.begin_new_day()
	var repayment_summary := bank.run_daily_financial_services(world)
	_expect(int(repayment_summary.get("repaid", 0)) > 0, "borrower should repay when it has spare cash")
	_expect(int(repayment_summary.get("interest", 0)) > 0, "repayment should include interest")
	_expect(bank.get_business_debt(shop) < loaned, "borrower debt should shrink after repayment")

	_free_nodes([banker, bank, shop])
	_free_world(world)
	return _current_error

func _test_bank_binder_uses_nested_entrance() -> String:
	var source := Node3D.new()
	source.name = "BigBuilding"
	source.add_to_group("building_use_bank")
	source.set_meta("building_name", "City Bank")
	source.set_meta("building_entrance", "foundation_residential_01/Entrance")
	root.add_child(source)

	var foundation := Node3D.new()
	foundation.name = "foundation_residential_01"
	source.add_child(foundation)

	var entrance := Marker3D.new()
	entrance.name = "Entrance"
	entrance.position = Vector3(0.0, 0.0, 2.0)
	foundation.add_child(entrance)

	var created := BuildingUseBinderScript.bind_node(source)
	_expect_eq(created.size(), 1, "bank binder should create one bank unit")
	_expect(created[0] is Bank, "bank binder should create a Bank")
	var bank := created[0] as Bank
	_expect_eq(bank.building_name, "City Bank", "bank display name should avoid duplicate bank suffix")
	_expect_eq(bank.entrance, entrance, "bank binder should use nested entrance metadata")
	_expect(bank.is_in_group("buildings"), "generated bank should be in buildings group")
	_expect(bank.is_in_group("building_use_bank"), "generated bank should be in bank use group")

	_free_node(source)
	return _current_error

func _test_extended_building_use_binder_creates_real_units() -> String:
	var source := Node3D.new()
	source.name = "ConfirmedCommercialUses"
	source.add_to_group("building_use_supermarket")
	source.add_to_group("building_use_cinema")
	source.add_to_group("building_use_factory")
	source.add_to_group("building_use_gas_station")
	source.add_to_group("building_use_taxi_depot")
	source.add_to_group("building_use_logistics_depot")
	root.add_child(source)

	var entrance := Marker3D.new()
	entrance.name = "Entrance"
	source.add_child(entrance)

	var created := BuildingUseBinderScript.bind_node(source)
	_expect_eq(created.size(), 6, "binder should create one unit per supported commercial use")
	var expected_use_ids := {
		"supermarket": false,
		"cinema": false,
		"factory": false,
		"gas_station": false,
		"taxi_depot": false,
		"logistics_depot": false,
	}
	for building in created:
		for use_id in expected_use_ids.keys():
			if building.is_in_group("building_use_%s" % use_id):
				expected_use_ids[use_id] = true
	for use_id in expected_use_ids.keys():
		_expect(bool(expected_use_ids[use_id]), "binder should create %s unit" % use_id)

	_free_node(source)

	var residential_source := ResidentialBuildingScript.new()
	residential_source.name = "DepotMixedUseHome"
	residential_source.add_to_group("building_use_residential")
	residential_source.add_to_group("building_use_taxi_depot")
	residential_source.add_to_group("building_use_logistics_depot")
	root.add_child(residential_source)

	var residential_entrance := Marker3D.new()
	residential_entrance.name = "Entrance"
	residential_source.add_child(residential_entrance)
	residential_source.entrance = residential_entrance

	var depot_units := BuildingUseBinderScript.bind_node(residential_source)
	_expect_eq(depot_units.size(), 2, "residential binder should add taxi and logistics units")
	var found_taxi := false
	var found_logistics := false
	for building in depot_units:
		if building.is_in_group("building_use_taxi_depot"):
			found_taxi = true
			_expect(building is TaxiDepot, "taxi_depot use should create TaxiDepot")
			_expect(building.is_in_group("ground_floor_business"), "residential taxi depot should be marked as ground-floor business")
		elif building.is_in_group("building_use_logistics_depot"):
			found_logistics = true
			_expect(building is LogisticsDepot, "logistics_depot use should create LogisticsDepot")
			_expect(building.is_in_group("ground_floor_business"), "residential logistics depot should be marked as ground-floor business")
	_expect(found_taxi, "binder should create a taxi depot unit")
	_expect(found_logistics, "binder should create a logistics depot unit")

	_free_node(residential_source)
	return _current_error

func _test_teaching_jobs_require_degree() -> String:
	_expect_eq(
		CitizenFactoryScript.get_required_education_for_job_title("Teacher"),
		2,
		"teacher jobs should require university education"
	)
	_expect_eq(
		CitizenFactoryScript.get_required_education_for_job_title("Professor"),
		3,
		"professor jobs should require the highest education"
	)
	_expect(
		CitizenFactoryScript.get_allowed_building_types_for_job_title("Gardener").has(BuildingScript.BuildingType.PARK),
		"gardener jobs should be limited to parks"
	)
	_expect(
		CitizenFactoryScript.get_allowed_building_types_for_job_title("Professor").has(BuildingScript.BuildingType.UNIVERSITY),
		"professor jobs should be limited to universities"
	)
	_expect_eq(
		CitizenFactoryScript.get_required_education_for_job_title("Doctor"),
		3,
		"doctor jobs should require education 3"
	)
	_expect_eq(
		CitizenFactoryScript.get_required_education_for_job_title("Nurse"),
		2,
		"nurse jobs should require education 2"
	)
	_expect_eq(
		CitizenFactoryScript.get_required_education_for_job_title("Mayor"),
		3,
		"mayor jobs should require education 3"
	)
	_expect(
		CitizenFactoryScript.get_allowed_building_types_for_job_title("Doctor").has(BuildingScript.BuildingType.HOSPITAL),
		"doctor jobs should be limited to hospitals"
	)
	_expect(
		not CitizenFactoryScript.get_allowed_building_types_for_job_title("Doctor").has(BuildingScript.BuildingType.CITY_HALL),
		"doctor jobs should not be allowed in city hall"
	)
	_expect(
		CitizenFactoryScript.get_allowed_building_types_for_job_title("Pharmacist").has(BuildingScript.BuildingType.HOSPITAL),
		"pharmacist jobs should be limited to hospitals"
	)
	_expect(
		CitizenFactoryScript.get_allowed_building_types_for_job_title("Therapist").has(BuildingScript.BuildingType.HOSPITAL),
		"therapist jobs should be limited to hospitals"
	)
	_expect(
		CitizenFactoryScript.get_allowed_building_types_for_job_title("Mayor").has(BuildingScript.BuildingType.CITY_HALL),
		"mayor jobs should be limited to city hall"
	)
	_expect(
		CitizenFactoryScript.get_allowed_building_types_for_job_title("Fahrer").has(BuildingScript.BuildingType.TAXI_DEPOT),
		"driver jobs should be allowed at taxi depots"
	)
	_expect(
		CitizenFactoryScript.get_allowed_building_types_for_job_title("Fahrer").has(BuildingScript.BuildingType.LOGISTICS_DEPOT),
		"driver jobs should be allowed at logistics depots"
	)
	_expect(
		CitizenFactoryScript.get_allowed_building_types_for_job_title("Technician").has(BuildingScript.BuildingType.LOGISTICS_DEPOT),
		"technician jobs should be allowed at logistics depots"
	)

	var teacher_job = JobScript.new()
	teacher_job.title = "Teacher"
	teacher_job.required_education_level = CitizenFactoryScript.get_required_education_for_job_title("Teacher")

	# Teaching now requires a degree, but an unstaffed University may still take
	# an unqualified citizen as trainee staff (see critical_public_staffing).
	var applicant = _new_citizen("Student Worker")
	_expect(not teacher_job.meets_requirements(applicant), "citizen without education should not directly qualify for teaching jobs")
	_free_nodes([applicant])
	return _current_error

func _test_tax_and_welfare() -> String:
	var world = _new_world()
	var city_hall = _new_city_hall(0)
	city_hall.min_operating_balance = 0
	city_hall.reserve_transfer_daily_limit = 0
	var shop = _new_building("Shop", BuildingScript.BuildingType.SHOP, 500)
	var citizen = _new_citizen("Citizen")
	citizen.wallet.balance = 200

	shop.income_today = 1000
	world.buildings.append(city_hall)
	world.buildings.append(shop)
	world.citizens.append(citizen)

	city_hall.collect_daily_taxes(world)
	_expect_eq(city_hall.tax_collected_today, 104, "city hall should collect business and citizen tax")
	_expect_eq(city_hall.account.balance, 104, "city hall account after taxes")
	_expect_eq(shop.account.balance, 400, "shop account after business tax")
	_expect_eq(shop.expenses_today, 100, "shop should record tax as expense")
	_expect_eq(citizen.wallet.balance, 196, "citizen wallet after citizen tax")

	_expect(city_hall.pay_welfare(world, citizen, 40), "city hall welfare payment should succeed")
	_expect_eq(citizen.wallet.balance, 236, "citizen wallet after welfare")
	_expect_eq(city_hall.account.balance, 64, "city hall balance after welfare payment")

	city_hall.account.balance = 10
	world.city_account.balance = 70
	city_hall.min_operating_balance = 20
	city_hall.reserve_transfer_target_balance = 60
	city_hall.reserve_transfer_daily_limit = 40
	_expect(world._pay_welfare(citizen, 40, city_hall), "world welfare should use a limited reserve transfer when city hall liquidity is too low")
	_expect_eq(citizen.wallet.balance, 276, "citizen wallet should increase after reserve-backed welfare payment")
	_expect_eq(city_hall.account.balance, 10, "city hall should end near its prior post-transfer remainder after paying welfare")
	_expect_eq(world.city_account.balance, 30, "reserve balance should shrink by the transferred amount")

	_free_nodes([citizen, shop, city_hall])
	_free_world(world)
	return _current_error

func _test_citizen_pay_rent() -> String:
	var world = _new_world()
	var citizen := _new_citizen("Tenant")
	var landlord: ResidentialBuilding = ResidentialBuildingScript.new()
	landlord.name = "RentHouse"
	landlord.building_name = "RentHouse"
	landlord.account.balance = 100
	citizen.wallet.balance = 90

	_expect(citizen.pay_rent(world, landlord, 35), "rent should be paid when wallet has enough balance")
	_expect_eq(citizen.wallet.balance, 55, "citizen wallet after paid rent")
	_expect_eq(landlord.account.balance, 135, "landlord balance after paid rent")

	_expect(not citizen.pay_rent(world, landlord, 80), "rent should fail when wallet lacks balance")
	_expect_eq(citizen.wallet.balance, 55, "citizen wallet should stay unchanged after failed rent")
	_expect_eq(landlord.account.balance, 135, "landlord balance should stay unchanged after failed rent")

	_free_nodes([citizen, landlord])
	_free_world(world)
	return _current_error

func _new_economy():
	var economy = EconomySystemScript.new()
	economy._ready()
	return economy

func _new_world():
	var world = WorldScript.new()
	if world.economy != null:
		_free_node(world.economy)
	world.economy = _new_economy()
	world.city_account.owner_name = "CityReserve"
	world.city_account.balance = 180
	return world

func _new_account(owner_name: String, balance: int):
	var account = AccountScript.new()
	account.owner_name = owner_name
	account.balance = balance
	return account

func _new_building(name: String, type_id: int, balance: int = 0, worker_capacity: int = 0) -> Building:
	var building = BuildingScript.new()
	building.name = name
	building.building_name = name
	building.building_type = type_id
	building.account.balance = balance
	building.job_capacity = worker_capacity
	return building

func _new_city_hall(balance: int) -> CityHall:
	var city_hall = CityHallScript.new()
	city_hall.name = "CityHall"
	city_hall.building_name = "CityHall"
	city_hall.building_type = BuildingScript.BuildingType.CITY_HALL
	city_hall.account.balance = balance
	return city_hall

func _new_hospital(balance: int = 0):
	var hospital = HospitalScript.new()
	hospital.name = "Hospital"
	hospital.building_name = "Hospital"
	hospital.building_type = BuildingScript.BuildingType.HOSPITAL
	hospital.capacity = 20
	hospital.job_capacity = 5
	hospital.patient_capacity = 20
	hospital.treatment_capacity_per_hour = 6
	hospital.open_hour = 0
	hospital.close_hour = 24
	hospital.is_public_service = true
	hospital.service_quality = 1.0
	hospital.treatment_price = 25
	hospital.emergency_treatment_price = 60
	hospital.daily_operating_cost = 250
	hospital.base_operating_cost = 250
	hospital.account.balance = balance
	hospital._treatment_tokens = 6.0
	return hospital

func _new_citizen(citizen_name: String) -> Citizen:
	var citizen = CitizenScript.new()
	citizen.name = citizen_name
	citizen.citizen_name = citizen_name
	return citizen

func _new_job(
	title: String,
	wage_per_hour: int,
	shift_hours: float,
	workplace: Building = null,
	allowed_types: Array[int] = [],
	service_type: String = ""
) -> Job:
	var job = JobScript.new()
	job.title = title
	job.wage_per_hour = wage_per_hour
	job.shift_hours = shift_hours
	job.workplace = workplace
	job.workplace_service_type = service_type
	job.allowed_building_types = allowed_types.duplicate()
	job.required_education_level = CitizenFactoryScript.get_required_education_for_job_title(title)
	return job

func _assign_worker(building: Building, citizen_name: String, title: String, wage_per_hour: int, shift_hours: float) -> Citizen:
	var citizen = _new_citizen(citizen_name)
	var service_type := CitizenFactoryScript.get_service_type_for_job_title(title)
	var allowed_types := CitizenFactoryScript.get_allowed_building_types_for_job_title(title)
	if allowed_types.is_empty():
		allowed_types = [building.building_type]
	citizen.job = _new_job(title, wage_per_hour, shift_hours, building, allowed_types, service_type)
	building.try_hire(citizen)
	return citizen

func _free_nodes(nodes: Array) -> void:
	for node in nodes:
		if node is Node:
			_free_node(node as Node)

func _free_node(node: Node) -> void:
	if node != null:
		node.free()

func _free_world(world) -> void:
	if world == null:
		return
	if world.time != null:
		_free_node(world.time)
		world.time = null
	if world.economy != null:
		_free_node(world.economy)
		world.economy = null
	_free_node(world)

func _expect(condition: bool, message: String) -> void:
	_checks_run += 1
	if condition or _current_error != "":
		return
	_current_error = message

func _expect_eq(actual, expected, message: String) -> void:
	_checks_run += 1
	if actual == expected or _current_error != "":
		return
	_current_error = "%s | expected=%s actual=%s" % [message, str(expected), str(actual)]
