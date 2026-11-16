extends TestCase
## Kart physics on the real Sakura Valley track (CharacterBody3D + trimesh).

var track: TrackBuilder


func _setup() -> KartController:
	track = load("res://Scenes/Tracks/SakuraValley.tscn").instantiate()
	spawn(track)
	var k: KartController = load("res://Scenes/Vehicles/KartBase.tscn").instantiate()
	k.setup("TEST", Color.ORANGE, true)
	spawn(k)
	k.place(track.grid_transform(0))
	return k


func test_auto_acceleration_reaches_top_speed() -> void:
	var k := _setup()
	await physics_frames(10)
	eq(k.speed, 0.0, "no movement before control is enabled (countdown)")
	k.control_enabled = true
	var start := k.global_position
	await physics_frames(60)
	check(k.speed > 8.0, "accelerates without throttle input (speed after 1 s = %.1f)" % k.speed)
	# keep it on the road through the first corner with the line-follower
	var ai := AIDriver.new()
	ai.kart = k
	ai.track = track
	ai.use_drift = false
	k.add_child(ai)
	var peak := 0.0
	for i in 240:
		await tree().physics_frame
		peak = maxf(peak, k.speed)
	check(peak > float(k.stats["max_speed"]) * 0.9, "reaches ~top speed (peak %.1f)" % peak)
	check(k.speed <= float(k.stats["max_speed"]) + 0.01, "does not exceed top speed without boost")
	var moved := k.global_position - start
	check(moved.length() > 40.0, "kart actually moved along the track (%.1f m)" % moved.length())
	check(k.is_on_floor(), "kart stays on the road surface")


func test_steering_left_right() -> void:
	var k := _setup()
	k.control_enabled = true
	await physics_frames(45)
	var h0 := k.heading
	k.steer_input = 1.0
	await physics_frames(20)
	var dr := wrapf(k.heading - h0, -PI, PI)
	check(dr < -0.1, "steer right turns clockwise (heading delta %.2f)" % dr)
	k.steer_input = -1.0
	await physics_frames(40)
	var dl := wrapf(k.heading - h0, -PI, PI)
	check(dl > dr + 0.2, "steer left turns back counter-clockwise")
	# visual body faces the same way as the collision body
	near(k.rotation.y, k.heading, 0.001, "body rotation follows heading")


func test_brake_and_release_resumes() -> void:
	var k := _setup()
	k.control_enabled = true
	await physics_frames(120)
	var v := k.speed
	k.brake_input = true
	await physics_frames(30)
	check(k.speed < v - 8.0, "brake decelerates (%.1f → %.1f)" % [v, k.speed])
	k.brake_input = false
	var v2 := k.speed
	await physics_frames(30)
	check(k.speed > v2 + 3.0, "auto acceleration resumes after brake release")


func test_wall_collision_slows_and_emits_impact() -> void:
	var k := _setup()
	var events: Array = []
	k.impact.connect(func(kind, s): events.append([kind, s]))
	Haptics.reset_cooldown()
	var before_haptics := Haptics.events_fired
	k.impact.connect(func(kind, s): Haptics.impact(kind, s))
	# Aim at the right wall at ~60° and drive.
	var t := track.transform_at(40.0, 0.0, 0.05)
	k.place(t)
	k.heading -= deg_to_rad(60)
	k.travel_heading = k.heading
	k.control_enabled = true
	k.speed = 25.0
	var max_before := 0.0
	for i in 90:
		await tree().physics_frame
		if events.is_empty():
			max_before = k.speed
		else:
			break
	check(not events.is_empty(), "impact signal emitted on wall hit")
	if not events.is_empty():
		eq(events[0][0], "wall", "impact kind is wall")
		check(float(events[0][1]) > 0.2, "impact strength reflects speed (%.2f)" % float(events[0][1]))
		check(k.speed < max_before * 0.85, "speed reduced by wall (%.1f → %.1f)" % [max_before, k.speed])
		check(Haptics.events_fired > before_haptics, "haptics requested for wall impact")
	# kart must still be inside the track (not through the wall)
	await physics_frames(30)
	var lat := absf(track.lateral_distance(k.global_position, track.closest_offset(k.global_position)))
	check(lat < track.half_width() + TrackBuilder.KERB_W + 0.6, "kart did not pass through wall (lateral %.1f)" % lat)


func test_boost_increases_speed_then_expires() -> void:
	var k := _setup()
	k.control_enabled = true
	await physics_frames(300)
	var top := k.speed
	k.boost_gauge = 1.0
	k.boost_request = true
	await physics_frames(2)
	check(k.boost.active, "boost active after BOOST with full gauge")
	eq(k.boost_gauge, 0.0, "gauge consumed")
	await physics_frames(60)
	check(k.speed > top + 4.0, "boost raises speed above normal top speed (%.1f → %.1f)" % [top, k.speed])
	await physics_frames(int(float(k.stats["boost_duration"]) * 60.0) + 5)
	check(not k.boost.active, "boost expired after its duration")
	await physics_frames(120)
	check(k.speed <= float(k.stats["max_speed"]) + 0.5, "speed returns to normal after boost")
	k.boost_request = true
	await physics_frames(2)
	check(not k.boost.active, "no boost with empty gauge")


func test_drift_engages_charges_and_rewards() -> void:
	var k := _setup()
	k.control_enabled = true
	await physics_frames(90)
	k.drift_input = true
	k.steer_input = 0.8
	await physics_frames(3)
	check(k.drift.drifting, "drift starts with DRIFT held + steer + speed")
	await physics_frames(70)
	check(k.boost_gauge > 0.2, "drifting fills the boost gauge (%.2f)" % k.boost_gauge)
	var slip := absf(wrapf(k.heading - k.travel_heading, -PI, PI))
	check(slip > 0.05, "kart slides (heading/travel slip %.2f rad)" % slip)
	var charge := k.drift.charge
	k.drift_input = false
	await physics_frames(2)
	check(not k.drift.drifting, "drift ends on release")
	if charge >= 0.45:
		check(k.boost.active and k.boost.kind == "mini", "mini-boost reward after a charged drift")


func test_respawn_after_falling() -> void:
	var k := _setup()
	var rm := RaceManager.new()
	spawn(rm)
	var arr: Array[KartController] = [k]
	rm.setup(track, arr, 3)
	rm.start_race_now()
	await physics_frames(60)
	k.global_position = Vector3(500, -30, 500)
	await physics_frames(3)
	check(k.global_position.y > -1.0, "kart respawned on track after falling (y=%.1f)" % k.global_position.y)
	var lat := absf(track.lateral_distance(k.global_position, track.closest_offset(k.global_position)))
	check(lat < 2.0, "respawn point on centre line")
