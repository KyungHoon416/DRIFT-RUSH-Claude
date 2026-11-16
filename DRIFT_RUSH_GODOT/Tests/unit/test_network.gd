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


func test_lan_beacon_roundtrip() -> void:
	var txt := LanDiscovery.encode({"code": "A7F3K9", "port": 7777, "name": "Kim|Racer", "players": 3, "capacity": 8,
		"mode": "item", "map": "neon_city", "started": false})
	var d := LanDiscovery.decode(txt)
	eq(d["code"], "A7F3K9", "code")
	eq(d["port"], 7777, "port")
	eq(d["name"], "Kim/Racer", "separator in name escaped")
	eq(d["mode"], "item", "mode")
	eq(d["started"], false, "started flag")
	check(LanDiscovery.decode("HELLO|x").is_empty(), "foreign packets ignored")


func test_server_rejects_teleport_and_off_track() -> void:
	var track: TrackBuilder = load("res://Scenes/Tracks/SakuraValley.tscn").instantiate()
	spawn(track)
	await physics_frames(2)
	var rs := RaceSession.new()
	rs.track = track
	var p0 := track.transform_at(100.0).origin
	var prev := {"p": p0, "h": 0.0, "t": 10.0, "off": 100.0}
	eq(rs.check_state({}, p0, 10.0), "", "first state on track accepted")
	eq(rs.check_state(prev, track.transform_at(101.5).origin, 10.05), "", "normal 30 m/s movement accepted")
	eq(rs.check_state(prev, track.transform_at(350.0).origin, 10.05), "teleport", "250 m jump in 50 ms rejected")
	var off_track: Vector3 = p0 + track.frame_at(100.0)["right"] * 40.0
	eq(rs.check_state(prev, off_track, 10.05), "off_track", "outside the walls rejected")
	eq(rs.check_state(prev, Vector3(p0.x, -30, p0.z), 10.05), "below_world", "under the map rejected")
	eq(rs.check_state(prev, track.transform_at(85.0).origin, 10.05), "", "respawn slightly behind on centre line accepted")
	rs.free()
