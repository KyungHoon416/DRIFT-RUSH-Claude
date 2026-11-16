extends TestCase
## End-to-end offline race in the real RaceWorld scene (autopilot drives the
## player kart): countdown → 3 laps through all checkpoints → results.


func _run_race(mode: String, map_id: String, bots: int, laps: int, max_sec: float) -> Dictionary:
	GameFlow.autopilot = true
	GameFlow.race_config = {"mode": mode, "map": map_id, "laps": laps, "bots": bots, "online": false, "seed": 1}
	GameFlow.last_goto = ""
	var w: RaceWorld = load("res://Scenes/Race/RaceWorld.tscn").instantiate()
	var out := {"results": [], "laps": [], "world": w, "frames": 0, "wrong_way": 0, "respawns": 0, "cps": 0}
	spawn(w)
	w.race.lap_completed.connect(func(k, lap, t): if k == w.player: out["laps"].append([lap, t]))
	w.race.race_finished.connect(func(r): out["results"] = r)
	w.race.wrong_way_changed.connect(func(k, ww): if k == w.player and ww: out["wrong_way"] += 1)
	w.race.kart_respawned.connect(func(k): if k == w.player: out["respawns"] += 1)
	w.track.checkpoint_passed.connect(func(k, _i): if k == w.player: out["cps"] += 1)
	var limit := int(max_sec * 60.0)
	while out["results"].is_empty() and out["frames"] < limit:
		await tree().physics_frame
		out["frames"] += 1
	GameFlow.autopilot = false
	return out


func test_practice_three_laps_sakura() -> void:
	var o := await _run_race("practice", "sakura_valley", 0, 3, 240.0)
	var w: RaceWorld = o["world"]
	check(not o["results"].is_empty(), "race finished within time limit (%d frames)" % o["frames"])
	eq(o["laps"].size(), 3, "3 laps completed")
	eq(w.karts.size(), 1, "practice = solo")
	var lm: LapManager = w.race.lap_managers[w.player]
	check(lm.finished and lm.finish_time > 20.0, "finish time plausible (%.2f s)" % lm.finish_time)
	check(lm.best_lap > 10.0 and lm.best_lap < lm.finish_time, "best lap recorded (%.2f)" % lm.best_lap)
	check(int(o["cps"]) >= 3 * w.track.checkpoint_count, "all checkpoints passed (%d)" % int(o["cps"]))
	eq(int(o["wrong_way"]), 0, "no wrong-way warning during a clean lap")
	eq(GameFlow.last_goto, "", "result screen not opened before the delay")
	await physics_frames(170)
	eq(GameFlow.last_goto, "result", "navigates to result screen")
	check(not GameFlow.last_result.is_empty() and GameFlow.last_result["results"].size() == 1, "result stored")
	print("    practice: finish %.2f s, best lap %.2f s, respawns %d" % [lm.finish_time, lm.best_lap, o["respawns"]])


func test_speed_race_vs_7_bots_ranking() -> void:
	var o := await _run_race("speed", "sakura_valley", 7, 2, 240.0)
	var w: RaceWorld = o["world"]
	eq(w.karts.size(), 8, "8 karts on grid")
	check(not o["results"].is_empty(), "race finished")
	var res: Array = o["results"]
	eq(res.size(), 8, "8 result rows")
	var ranks := []
	var players := 0
	for r in res:
		ranks.append(r["rank"])
		if r["is_player"]:
			players += 1
		if not r["dnf"]:
			check(float(r["time"]) > 0.0, "finisher has a time")
	eq(ranks, [1, 2, 3, 4, 5, 6, 7, 8], "ranks 1..8")
	eq(players, 1, "exactly one player row")
	var finished_times := []
	for r in res:
		if not r["dnf"]:
			finished_times.append(float(r["time"]))
	var sorted := finished_times.duplicate()
	sorted.sort()
	eq(finished_times, sorted, "finishers ordered by time")


func test_item_race_neon_city_runs() -> void:
	var o := await _run_race("item", "neon_city", 3, 1, 150.0)
	var w: RaceWorld = o["world"]
	check(w.items != null, "item manager active in item mode")
	check(w.items.boxes.size() >= 4, "item boxes spawned")
	check(not o["results"].is_empty(), "item race finished")


func test_wrong_way_detection() -> void:
	GameFlow.race_config = {"mode": "practice", "map": "sakura_valley", "laps": 3, "bots": 0, "online": false, "seed": 1}
	var w: RaceWorld = load("res://Scenes/Race/RaceWorld.tscn").instantiate()
	spawn(w)
	var flagged := [false]
	w.race.wrong_way_changed.connect(func(k, ww): if ww: flagged[0] = true)
	w.race.start_race_now()
	var t := w.track.transform_at(60.0, 0.0, 0.05)
	w.player.place(Transform3D(t.basis.rotated(Vector3.UP, PI), t.origin))
	w.player_input.enabled = false
	for i in 150:
		w.player.steer_input = 0.0
		await tree().physics_frame
	check(flagged[0], "driving backwards raises WRONG WAY")


func test_camera_hides_kart_blocking_the_lens() -> void:
	GameFlow.race_config = {"mode": "speed", "map": "sakura_valley", "laps": 3, "bots": 1, "online": false, "seed": 1}
	var w: RaceWorld = load("res://Scenes/Race/RaceWorld.tscn").instantiate()
	spawn(w)
	await physics_frames(3)
	var other: KartController = w.karts[0] if w.karts[0] != w.player else w.karts[1]
	other.global_position = w.camera.global_position + Vector3.DOWN * 0.8
	await physics_frames(2)
	check(not other.model.visible, "kart inside the camera's near zone is hidden")
	other.global_position = w.player.global_position + w.player.forward() * 15.0
	await physics_frames(2)
	check(other.model.visible, "kart ahead is visible again")
