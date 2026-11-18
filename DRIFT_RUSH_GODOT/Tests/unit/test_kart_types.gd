extends TestCase
## Four kart bodies: build, distinct stats, fair balance, garage + race wiring.


func test_every_type_builds_its_own_body() -> void:
	var counts := {}
	for id in GameFlow.KART_TYPES:
		var m := KartModel.new()
		spawn(m)
		m.build(Color.ORANGE, false, 0.0, id)
		eq(m.kart_type, id, "%s model type" % id)
		eq(m.wheels.size(), 4, "%s has 4 wheels" % id)
		check(m.flame_emitters.size() >= 1, "%s has boost flames" % id)
		check(m.number_label != null, "%s has a number roundel" % id)
		counts[id] = m.body.get_child_count()
	var uniq := {}
	for v in counts.values():
		uniq[v] = true
	check(uniq.size() >= 3, "bodies differ in construction (%s)" % str(counts))


func test_stats_trade_offs() -> void:
	var r := GameFlow.get_kart_stats("rocket")
	var b := GameFlow.get_kart_stats("bolt")
	var u := GameFlow.get_kart_stats("bubble")
	var d := GameFlow.get_kart_stats("drifter")
	check(float(b["max_speed"]) > float(r["max_speed"]) and float(b["turn_speed"]) < float(r["turn_speed"]), "BOLT: faster but turns less")
	check(float(u["acceleration"]) > float(r["acceleration"]) and float(u["max_speed"]) < float(r["max_speed"]), "BUBBLE: quicker off the line, lower top speed")
	check(float(d["drift_charge_rate"]) > float(r["drift_charge_rate"]) and float(d["grip"]) < float(r["grip"]), "DRIFTER: charges drifts faster, less grip")
	check(not b.has("_label"), "label metadata not merged into physics stats")


func test_types_are_balanced_on_a_lap() -> void:
	var times := {}
	for id in GameFlow.KART_TYPES:
		SaveSettings.set_value("kart_type", id, false)
		GameFlow.autopilot = true
		GameFlow.race_config = {"mode": "practice", "map": "sakura_valley", "laps": 1, "bots": 0, "online": false, "seed": 1}
		var w: RaceWorld = load("res://Scenes/Race/RaceWorld.tscn").instantiate()
		spawn(w)
		var done := [false]
		w.race.race_finished.connect(func(_r): done[0] = true)
		var f := 0
		while not done[0] and f < 4000:
			await tree().physics_frame
			f += 1
		eq(w.player.stats_id, id, "player drives the selected type")
		times[id] = w.race.lap_managers[w.player].finish_time
		w.queue_free()
		await physics_frames(2)
	GameFlow.autopilot = false
	SaveSettings.set_value("kart_type", "rocket", false)
	var lo := INF
	var hi := 0.0
	for v in times.values():
		lo = minf(lo, float(v))
		hi = maxf(hi, float(v))
	print("    lap times by type: ", times)
	check(lo > 0.0, "all types finished")
	check(hi / lo < 1.05, "lap times within 5%% of each other (%.2f – %.2f s)" % [lo, hi])


func test_garage_type_selection_saves() -> void:
	var g: Control = load("res://Scenes/UI/Garage.tscn").instantiate()
	spawn(g)
	await frames(3)
	(g.find_child("Kart_bolt", true, false) as Button).pressed.emit()
	(g.find_child("SaveButton", true, false) as Button).pressed.emit()
	await frames(2)
	eq(SaveSettings.get_value("kart_type"), "bolt", "garage saves kart type")
	check(g.find_child("Stat_속도", true, false) != null, "stat bars shown")
	SaveSettings.set_value("kart_type", "rocket", false)
