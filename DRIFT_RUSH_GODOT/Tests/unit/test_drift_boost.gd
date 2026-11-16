extends TestCase


func test_drift_start_conditions() -> void:
	var d := DriftSystem.new()
	eq(d.update(0.016, true, 0.8, 5.0, true), "", "too slow: no drift")
	eq(d.update(0.016, true, 0.1, 20.0, true), "", "too little steer: no drift")
	eq(d.update(0.016, true, 0.8, 20.0, false), "", "airborne: no drift")
	eq(d.update(0.016, false, 0.8, 20.0, true), "", "button not held: no drift")
	eq(d.update(0.016, true, -0.8, 20.0, true), "start", "valid → start")
	eq(d.direction, -1, "direction from steer sign")


func test_drift_charge_tiers() -> void:
	var d := DriftSystem.new()
	d.update(0.016, true, 0.8, 20.0, true)
	for i in 30:
		d.update(0.016, true, 0.8, 20.0, true)
	eq(d.update(0.016, false, 0.8, 20.0, true), "end", "release ends")
	eq(d.reward_tier(), 0, "short drift: no reward")
	d.update(0.016, true, 0.8, 20.0, true)
	for i in 200:
		d.update(0.016, true, 0.8, 20.0, true)
	d.update(0.016, false, 0.8, 20.0, true)
	eq(d.reward_tier(), 2, "long drift: big mini-boost")


func test_boost_timer_and_expiry() -> void:
	var b := BoostSystem.new()
	eq(b.update(0.1), 0.0, "inactive → no bonus")
	b.start(1.0, 12.0, "boost")
	near(b.update(0.5), 12.0, 0.001, "bonus while active")
	b.start(0.2, 5.0, "mini")
	near(b.remaining, 0.5, 0.001, "shorter boost does not cut remaining time")
	b.update(0.6)
	check(not b.active and b.just_ended, "expires and reports just_ended")
	eq(b.update(0.1), 0.0, "no bonus after expiry")
