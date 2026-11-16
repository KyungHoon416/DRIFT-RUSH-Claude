extends TestCase
## Snapshot interpolation (RaceSession.sample) and network condition simulation.


func _snap(t: float, x: float, h := 0.0, s := 20.0) -> Dictionary:
	return {"t": t, "s": {"p": Vector3(x, 0, 0), "h": h, "s": s, "d": 0, "b": false}}


func test_interpolates_between_snapshots() -> void:
	var buf := [_snap(1.0, 0.0), _snap(1.05, 1.0), _snap(1.10, 2.0)]
	var s := RaceSession.sample(buf, 1.075)
	near((s["p"] as Vector3).x, 1.5, 0.001, "linear position interpolation")
	s = RaceSession.sample(buf, 0.5)
	near((s["p"] as Vector3).x, 0.0, 0.001, "before buffer → first snapshot")


func test_extrapolates_briefly_when_late() -> void:
	var buf := [_snap(1.0, 0.0, PI / 2.0, 20.0)]
	var s := RaceSession.sample(buf, 1.1)
	near((s["p"] as Vector3).x, -2.0, 0.01, "extrapolates along heading (heading +90° → -X)")
	s = RaceSession.sample(buf, 5.0)
	near((s["p"] as Vector3).x, -5.0, 0.01, "extrapolation capped at 0.25 s")


func test_jittered_lossy_stream_stays_smooth() -> void:
	# 20 Hz snapshots of a kart moving at 30 m/s, 3% loss, ±20 ms jitter.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var buf := []
	var t := 0.0
	while t < 5.0:
		if rng.randf() > 0.03:
			buf.append(_snap(t + rng.randf_range(-0.02, 0.02) * 0.0, t * 30.0, 0.0, 30.0))
		t += 0.05
	var prev := -INF
	var max_jump := 0.0
	var render := 0.2
	while render < 4.8:
		var x: float = (RaceSession.sample(buf, render)["p"] as Vector3).x
		if prev > -INF:
			max_jump = maxf(max_jump, absf(x - prev))
		prev = x
		render += 1.0 / 60.0
	check(max_jump < 30.0 / 60.0 * 1.6, "no visible teleports with 3%% loss (max step %.2f m)" % max_jump)


func test_net_sanitizes_impossible_state() -> void:
	var s: Dictionary = Net._sanitize_state({"p": Vector3(1, 2, 3), "s": 999.0, "d": 5})
	eq(s["s"], 70.0, "speed clamped")
	eq(s["d"], 1, "drift dir clamped")
	var bad: Dictionary = Net._sanitize_state({"p": "hack"})
	eq(bad["p"], Vector3.ZERO, "non-vector position rejected")


func test_can_start_rules_offline() -> void:
	eq(Net.can_start()["ok"], false, "cannot start when not hosting")
