extends SceneTree

## Smoke test for the Sim-layer components.
##
## Covers (standalone, no scene bootstrap required):
##   CitizenIdentity — defaults, wallet/needs eager construction, slot writes
##   CitizenRestPose — set/clear/state lifecycle
##
## Not covered here (because they need the Main-Scene class registry):
##   CitizenSimulation wiring + apply() on a tree-attached Node3D — those
##   are exercised by the `parse` test (Main.tscn loads the full registry)
##   and by `navroute` (real CharacterBody3D in the tree).
##
## Uses preload (not class_name lookup) — `--script` headless mode does
## not populate the global class registry, so `CitizenIdentity.new()` fails.

const CitizenIdentityScript = preload("res://Entities/Citizens/New/Sim/CitizenIdentity.gd")
const CitizenRestPoseScript = preload("res://Entities/Citizens/New/Sim/CitizenRestPose.gd")
const CitizenLocationScript = preload("res://Entities/Citizens/New/Sim/CitizenLocation.gd")
const CitizenBenchReservationScript = preload("res://Entities/Citizens/New/Sim/CitizenBenchReservation.gd")
const CitizenTraceStateScript = preload("res://Entities/Citizens/New/Sim/CitizenTraceState.gd")
const CitizenDebugFacadeScript = preload("res://Entities/Citizens/New/Sim/CitizenDebugFacade.gd")
const CitizenLodComponentScript = preload("res://Entities/Citizens/New/Sim/CitizenLodComponent.gd")
const CitizenSchedulerScript = preload("res://Entities/Citizens/New/Sim/CitizenScheduler.gd")

var failures: int = 0


func _init() -> void:
	print("=== Sim components smoke test ===")
	_test_identity_defaults()
	_test_identity_writes()
	_test_rest_pose_lifecycle()
	_test_location_state()
	_test_location_lane_offset()
	_test_location_nav_points_null_building()
	_test_bench_reservation()
	_test_trace_state()
	_test_debug_facade()
	_test_lod_tier_state()
	_test_lod_tick_scheduling()
	_test_lod_commitments()
	_test_scheduler_personality()
	_test_scheduler_decision_cooldown()
	_test_scheduler_work_day()
	_test_scheduler_unreachable_cache()
	print()
	if failures == 0:
		print("RESULT: PASS")
		quit(0)
		return
	print("RESULT: FAIL (%d assertion(s))" % failures)
	quit(1)


func _test_identity_defaults() -> void:
	print("-- CitizenIdentity defaults --")
	var identity = CitizenIdentityScript.new()
	_assert_eq("citizen_name default", identity.citizen_name, "Alex")
	_assert_not_null("wallet eager-constructed", identity.wallet)
	_assert_not_null("needs eager-constructed", identity.needs)
	_assert_null("home default null", identity.home)
	_assert_null("job default null", identity.job)
	_assert_null("favorite_park default null", identity.favorite_park)
	_assert_eq("home_food_stock default", identity.home_food_stock, 2)
	_assert_eq("education_level default", identity.education_level, 0)


func _test_identity_writes() -> void:
	print("-- CitizenIdentity slot writes --")
	var identity = CitizenIdentityScript.new()
	identity.citizen_name = "Marie"
	identity.home_food_stock = 7
	identity.education_level = 3
	_assert_eq("citizen_name set", identity.citizen_name, "Marie")
	_assert_eq("home_food_stock set", identity.home_food_stock, 7)
	_assert_eq("education_level set", identity.education_level, 3)


func _test_rest_pose_lifecycle() -> void:
	print("-- CitizenRestPose lifecycle --")
	var owner_node := Node3D.new()
	var pose = CitizenRestPoseScript.new(owner_node)
	_assert_eq("inactive on construct", pose.is_active(), false)

	pose.set_pose(Vector3(1.5, 0.0, 2.0), 1.2)
	_assert_eq("active after set", pose.is_active(), true)
	_assert_eq("position stored", pose.get_position(), Vector3(1.5, 0.0, 2.0))
	_assert_eq("yaw stored", pose.get_yaw(), 1.2)

	pose.clear()
	_assert_eq("inactive after clear", pose.is_active(), false)
	# apply() while inactive must be a no-op, not a crash.
	pose.apply()

	owner_node.free()


func _test_location_state() -> void:
	print("-- CitizenLocation state --")
	var loc = CitizenLocationScript.new()
	_assert_eq("not inside on construct", loc.is_inside(), false)
	_assert_null("inside_building null", loc.get_inside_building())
	# Cannot pass a real Building (needs scene), but set/clear still trackable
	# via subsequent is_inside.
	loc.clear_inside_building()
	_assert_eq("clear is idempotent", loc.is_inside(), false)


func _test_location_lane_offset() -> void:
	print("-- CitizenLocation lane offset (deterministic) --")
	var first := CitizenLocationScript.get_lane_offset("Alex")
	var second := CitizenLocationScript.get_lane_offset("Alex")
	_assert_eq("same name -> same offset", first, second)
	var allowed: Array[float] = [-0.12, -0.04, 0.04, 0.12]
	_assert_eq("offset is in lane set",
			first in allowed, true)
	# Different names should at least cover more than one lane in a small set.
	var offsets: Array = []
	for n in ["Alex", "Marie", "Jonas", "Lara", "Ben", "Chris", "Dana", "Eli"]:
		var o := CitizenLocationScript.get_lane_offset(n)
		if not offsets.has(o):
			offsets.append(o)
	_assert_eq("8 names use at least 2 lanes", offsets.size() >= 2, true)


func _test_location_nav_points_null_building() -> void:
	print("-- CitizenLocation nav points (null building) --")
	var nav := CitizenLocationScript.resolve_navigation_points(
			null, null, "Alex", Vector3.ZERO)
	_assert_eq("null building returns empty dict", nav.is_empty(), true)


func _test_bench_reservation() -> void:
	print("-- CitizenBenchReservation --")
	var owner_node := Node.new()
	var bench = CitizenBenchReservationScript.new(owner_node)
	# release() with everything null must be a no-op, not a crash.
	bench.release(null, null, null)
	_assert_eq("null release survived", true, true)

	# Test that release() actually calls the building's release_bench_for.
	var fake_building := _MockBenchHolder.new()
	bench.release(null, fake_building, null)
	_assert_eq("building.release_bench_for called",
			fake_building.released_for == owner_node, true)
	# fallback_building used when primary is null.
	var fake_fallback := _MockBenchHolder.new()
	bench.release(null, null, fake_fallback)
	_assert_eq("fallback used when primary null",
			fake_fallback.released_for == owner_node, true)
	fake_building.free()
	fake_fallback.free()
	owner_node.free()


## Tiny mock with the two methods Bench-Reservation expects on a Building.
## Using a class instead of duck-typing so `release()` recognises has_method.
class _MockBenchHolder extends Building:
	var released_for: Node = null
	func release_bench_for(c: Node) -> void:
		released_for = c


func _test_trace_state() -> void:
	print("-- CitizenTraceState --")
	var trace = CitizenTraceStateScript.new()
	_assert_eq("default decision_reason", trace.last_decision_reason, "idle")
	_assert_eq("default desired_dir", trace.last_desired_dir, Vector3.ZERO)
	_assert_eq("default move_dir", trace.last_move_dir, Vector3.ZERO)

	trace.update_navigation("travel", Vector3(1, 0, 0), Vector3(0.7, 0, 0.7))
	_assert_eq("decision_reason after update",
			trace.last_decision_reason, "travel")
	_assert_eq("desired_dir after update",
			trace.last_desired_dir, Vector3(1, 0, 0))
	_assert_eq("move_dir after update",
			trace.last_move_dir, Vector3(0.7, 0, 0.7))

	trace.reset()
	_assert_eq("decision_reason after reset", trace.last_decision_reason, "idle")
	_assert_eq("desired_dir after reset", trace.last_desired_dir, Vector3.ZERO)

	# fmt_v3 round-trip — ensure format string is stable.
	var formatted := CitizenTraceStateScript.fmt_v3(Vector3(1.234, -2.5, 3.0))
	_assert_eq("fmt_v3 format", formatted, "(1.23, -2.50, 3.00)")

	# relative_label sanity checks (basis-inverse from identity = forward = -Z).
	var basis_inv: Basis = Basis.IDENTITY.inverse()
	_assert_eq("relative_label none",
			CitizenTraceStateScript.relative_label(Vector3.ZERO, basis_inv), "none")
	_assert_eq("relative_label forward",
			CitizenTraceStateScript.relative_label(Vector3(0, 0, -1), basis_inv), "forward")
	_assert_eq("relative_label back",
			CitizenTraceStateScript.relative_label(Vector3(0, 0, 1), basis_inv), "back")
	_assert_eq("relative_label right",
			CitizenTraceStateScript.relative_label(Vector3(1, 0, 0), basis_inv), "right")
	_assert_eq("relative_label left",
			CitizenTraceStateScript.relative_label(Vector3(-1, 0, 0), basis_inv), "left")


func _test_debug_facade() -> void:
	print("-- CitizenDebugFacade --")
	var df = CitizenDebugFacadeScript.new()
	# `emit_log` always passes through to SimLogger; we don't assert on the
	# log file here, just that the call doesn't crash with valid inputs.
	df.emit_log("Alex", "test message")
	_assert_eq("emit_log() does not crash", true, true)

	# `log_once_per_day` with null world: dedup is per-call (treated as same
	# day -1), so the second call with the same key must be filtered.
	var mock_world := _MockWorld.new()
	mock_world.day = 5
	df.reset()
	df.log_once_per_day(mock_world, "Alex", "k1", "message 1")
	df.log_once_per_day(mock_world, "Alex", "k1", "message 1 dupe")
	# Dedup state must show key was seen.
	_assert_eq("dedup key remembered", df._once_keys.has("k1"), true)
	_assert_eq("dedup day matches world", df._once_day, 5)

	# Different key on the same day passes.
	df.log_once_per_day(mock_world, "Alex", "k2", "message 2")
	_assert_eq("second key remembered", df._once_keys.has("k2"), true)
	_assert_eq("dedup tracks both keys", df._once_keys.size(), 2)

	# Day rollover clears the dedup set.
	mock_world.day = 6
	df.log_once_per_day(mock_world, "Alex", "k1", "message 1 day 6")
	_assert_eq("day rollover -> new day", df._once_day, 6)
	_assert_eq("dedup reset on rollover", df._once_keys.size(), 1)
	_assert_eq("k1 re-allowed on day 6", df._once_keys.has("k1"), true)
	mock_world.free()


class _MockWorld extends Node:
	var day: int = 0
	var minute_of_day: int = 0
	var minutes_per_tick: int = 1
	var tick_interval_sec: float = 0.5
	var time: _MockTime = null
	var due_for_simulation: bool = true
	func world_day() -> int:
		return day
	func is_citizen_due_for_simulation(_c: Node) -> bool:
		return due_for_simulation


class _MockTime:
	var hour: int = 0
	var minute: int = 0
	var day: int = 1
	var minutes_total: int = 0
	func get_hour() -> int:
		return hour
	func get_minute() -> int:
		return minute


# =================== LOD tests ===================

func _test_lod_tier_state() -> void:
	print("-- CitizenLodComponent tier state --")
	var lod = CitizenLodComponentScript.new()
	_assert_eq("default tier focus",
			lod.tier, CitizenLodComponentScript.TIER_FOCUS)
	_assert_eq("default tick interval", lod.tick_interval_minutes, 1)
	_assert_eq("default presence visible", lod.presence_hidden, false)

	lod.set_state(CitizenLodComponentScript.TIER_COARSE, false, 5)
	_assert_eq("tier coarse", lod.tier, CitizenLodComponentScript.TIER_COARSE)
	_assert_eq("tick interval 5", lod.tick_interval_minutes, 5)
	_assert_eq("hidden after rendered=false", lod.presence_hidden, true)

	# Profile application — apply_runtime_profile returns the resolved values.
	var resolved := lod.apply_runtime_profile({
		"full_navigation": false,
		"cheap_path_follow": true,
		"path_refresh_interval_sec": 1.5,
		"decision_interval_sec": 6.0,
	})
	_assert_eq("path_mode cheap",
			resolved.get("path_mode"), CitizenLodComponentScript.PATH_MODE_CHEAP)
	_assert_eq("repath override",
			resolved.get("repath_interval_sec"), 1.5)
	_assert_eq("decision interval",
			lod.decision_interval_sec, 6.0)


func _test_lod_tick_scheduling() -> void:
	print("-- CitizenLodComponent tick scheduling --")
	var lod = CitizenLodComponentScript.new()
	var world := _MockWorld.new()
	world.minutes_per_tick = 1
	world.tick_interval_sec = 0.5

	lod.set_state(CitizenLodComponentScript.TIER_FOCUS, true, 1)
	_assert_eq("interval ticks at minute=1, mpt=1",
			lod.get_tick_interval_ticks(world), 1)
	_assert_eq("slot 0 when interval==1",
			lod.get_tick_slot(world), 0)

	lod.set_state(CitizenLodComponentScript.TIER_COARSE, false, 8)
	world.minutes_per_tick = 2
	# 8 minutes / 2 minutes-per-tick = 4 ticks
	_assert_eq("interval ticks 8min/2mpt=4",
			lod.get_tick_interval_ticks(world), 4)
	# Slot is in [0, 3]
	var slot := lod.get_tick_slot(world)
	_assert_eq("slot in [0,3]", slot >= 0 and slot < 4, true)

	# Decision-cooldown range — fallback when no LOD profile.
	lod.decision_interval_sec = 0.0
	var range_no_profile := lod.get_decision_cooldown_range_minutes(world, 5, 20)
	_assert_eq("fallback range used",
			range_no_profile, Vector2i(5, 20))
	# With profile decision_interval_sec=6 → ticks_needed = ceil(6/0.5) = 12 → 24 minutes
	lod.decision_interval_sec = 6.0
	var range_with_profile := lod.get_decision_cooldown_range_minutes(world, 5, 20)
	_assert_eq("profile range >= 5 lower",
			range_with_profile.x >= 5, true)
	_assert_eq("profile range > 20 upper",
			range_with_profile.y > 20, true)
	world.free()


func _test_lod_commitments() -> void:
	print("-- CitizenLodComponent commitments --")
	var lod = CitizenLodComponentScript.new()
	var world := _MockWorld.new()
	var t := _MockTime.new()
	world.time = t
	world.day = 5
	t.hour = 10
	t.minute = 30  # = 630 minutes-of-day

	# Add two commitments with different expiries.
	lod.add_commitment("player_dialog", 5, 700, 1.0)  # expires today at 11:40
	lod.add_commitment("npc_dialog", 6, 100, 0.5)    # expires tomorrow
	_assert_eq("two commitments active",
			lod.has_active_commitment(world), true)
	_assert_eq("filter by type matches",
			lod.has_active_commitment(world, ["player_dialog"]), true)
	_assert_eq("filter by absent type",
			lod.has_active_commitment(world, ["whatever"]), false)
	_assert_eq("snapshot has 2", lod.snapshot_commitments().size(), 2)

	# Move clock past first commitment (today 12:00 = 720).
	t.hour = 12
	t.minute = 0
	lod.clear_expired_commitments(world)
	_assert_eq("first commitment expired",
			lod.snapshot_commitments().size(), 1)
	_assert_eq("only npc_dialog remains",
			str(lod.snapshot_commitments()[0].get("type", "")), "npc_dialog")

	# Upsert overrides existing entry.
	lod.upsert_commitment("npc_dialog", 7, 0, 0.9, {"reason": "extended"})
	var snap := lod.snapshot_commitments()
	_assert_eq("upsert kept count at 1", snap.size(), 1)
	_assert_eq("upsert merged metadata",
			str(snap[0].get("reason", "")), "extended")
	_assert_eq("upsert raised priority",
			float(snap[0].get("priority", 0.0)), 0.9)

	# Remove by list of types.
	lod.remove_commitments(["npc_dialog", "player_dialog"])
	_assert_eq("all removed", lod.snapshot_commitments().is_empty(), true)
	world.free()


# =================== Scheduler tests ===================

func _test_scheduler_personality() -> void:
	print("-- CitizenScheduler personality init --")
	var sched = CitizenSchedulerScript.new()
	# Defaults match legacy Citizen.gd.
	_assert_eq("hunger_threshold default", sched.hunger_threshold, 60.0)
	_assert_eq("low_energy default", sched.low_energy_threshold, 35.0)
	_assert_eq("work_motivation default", sched.work_motivation, 1.0)

	# init_personality must roll within base ± jitter, schedule_offset within range.
	sched.schedule_offset_min = -10
	sched.schedule_offset_max = 10
	sched.hunger_threshold_jitter = 5.0
	sched.init_personality()
	_assert_eq("schedule_offset in range",
			sched.schedule_offset >= -10 and sched.schedule_offset <= 10, true)
	_assert_eq("hunger_threshold near base ± 5",
			absf(sched.hunger_threshold - 60.0) <= 5.0, true)
	# park_interest is clamped to [0, 0.9].
	sched.park_interest_jitter = 1.0  # would push outside without clamp
	sched.init_personality()
	_assert_eq("park_interest clamped lower",
			sched.park_interest >= 0.0, true)
	_assert_eq("park_interest clamped upper",
			sched.park_interest <= 0.9, true)


func _test_scheduler_decision_cooldown() -> void:
	print("-- CitizenScheduler decision cooldown --")
	var sched = CitizenSchedulerScript.new()
	_assert_eq("cooldown 0 returns true at start",
			sched.tick_decision_cooldown(1), true)

	sched.decision_cooldown_left = 10
	_assert_eq("tick(3) returns false",
			sched.tick_decision_cooldown(3), false)
	_assert_eq("cooldown decremented", sched.decision_cooldown_left, 7)

	_assert_eq("tick(7) returns true",
			sched.tick_decision_cooldown(7), true)
	_assert_eq("cooldown hits zero", sched.decision_cooldown_left <= 0, true)

	sched.decision_cooldown_range_min = 8
	sched.decision_cooldown_range_max = 8
	var rolled := sched.roll_decision_cooldown()
	_assert_eq("roll uses range", rolled, 8)
	_assert_eq("decision_cooldown_left set by roll",
			sched.decision_cooldown_left, 8)


func _test_scheduler_work_day() -> void:
	print("-- CitizenScheduler work_day --")
	var sched = CitizenSchedulerScript.new()
	var world := _MockWorld.new()
	var t := _MockTime.new()
	world.time = t
	t.day = 1

	# First call syncs work_day_key from -1 to 1 (resets minutes).
	sched.update_work_day(world)
	# Now setting minutes and calling update again on the same day must preserve.
	sched.work_minutes_today = 120
	sched.update_work_day(world)
	_assert_eq("work_minutes preserved on same day",
			sched.work_minutes_today, 120)

	t.day = 2
	sched.update_work_day(world)
	_assert_eq("work_minutes reset on day rollover",
			sched.work_minutes_today, 0)

	# Null world is a no-op (headless safety).
	sched.work_minutes_today = 50
	sched.update_work_day(null)
	_assert_eq("null world preserves minutes",
			sched.work_minutes_today, 50)

	world.free()


func _test_scheduler_unreachable_cache() -> void:
	print("-- CitizenScheduler unreachable cache --")
	var sched = CitizenSchedulerScript.new()
	sched.unreachable_target_cooldown_minutes = 100
	var world := _MockWorld.new()
	var t := _MockTime.new()
	world.time = t
	t.day = 1
	t.minutes_total = 500  # day 1, minute 500

	var fake_target := Node.new()
	_assert_eq("not unreachable initially",
			sched.is_target_temporarily_unreachable(fake_target, world), false)

	var marked := sched.mark_target_unreachable(fake_target, world)
	_assert_eq("first mark returns true (new)", marked, true)
	_assert_eq("now unreachable",
			sched.is_target_temporarily_unreachable(fake_target, world), true)
	_assert_eq("remaining ~100 min",
			sched.get_target_remaining_minutes(fake_target, world), 100)

	# Re-mark with same time → no extension.
	var marked_again := sched.mark_target_unreachable(fake_target, world)
	_assert_eq("re-mark with same expiry returns false",
			marked_again, false)

	# Advance time past cooldown.
	t.minutes_total = 700  # 200 minutes later
	_assert_eq("cooldown expired",
			sched.is_target_temporarily_unreachable(fake_target, world), false)
	_assert_eq("remaining 0 after expiry",
			sched.get_target_remaining_minutes(fake_target, world), 0)

	fake_target.free()
	world.free()


# ------------------------- assertion helpers -------------------------

func _assert_eq(label: String, actual: Variant, expected: Variant) -> void:
	if actual == expected:
		print("  OK   %s: %s" % [label, str(actual)])
		return
	printerr("  FAIL %s: got %s, expected %s" % [label, str(actual), str(expected)])
	failures += 1


func _assert_null(label: String, value: Variant) -> void:
	if value == null:
		print("  OK   %s" % label)
		return
	printerr("  FAIL %s: expected null, got %s" % [label, str(value)])
	failures += 1


func _assert_not_null(label: String, value: Variant) -> void:
	if value != null:
		print("  OK   %s" % label)
		return
	printerr("  FAIL %s: expected non-null" % label)
	failures += 1
