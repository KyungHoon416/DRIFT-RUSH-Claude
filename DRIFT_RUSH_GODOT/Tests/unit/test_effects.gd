extends TestCase
## Race effects: skid marks, start lights, finish confetti.


func _world() -> RaceWorld:
	GameFlow.race_config = {"mode": "practice", "map": "sakura_valley", "laps": 1, "bots": 0, "online": false, "seed": 1}
	var w: RaceWorld = load("res://Scenes/Race/RaceWorld.tscn").instantiate()
	spawn(w)
	return w


func test_start_lights_follow_countdown() -> void:
	var w := _world()
	await physics_frames(2)
	eq(w.effects.start_lamps.size(), 3, "three start lamps on the gantry")
	await physics_frames(70)   # first ticks of the 3 s countdown
	check(w.effects.start_lamps[0].material_override == w.effects._red_on, "first lamp red during countdown")
	await physics_frames(150)
	check(w.effects.start_lamps[2].material_override == w.effects._green_on, "all green at GO")


func test_drifting_leaves_skid_marks() -> void:
	var w := _world()
	w.race.start_race_now()
	w.player_input.enabled = false
	await physics_frames(80)
	w.player.drift_input = true
	w.player.steer_input = 0.4
	await physics_frames(40)
	w.player.drift_input = false
	check(w.effects.marks_placed > 10, "skid marks placed while drifting (%d)" % w.effects.marks_placed)
	var before := w.effects.marks_placed
	w.player.steer_input = 0.0
	await physics_frames(30)
	eq(w.effects.marks_placed, before, "no marks when not drifting")


func test_finish_spawns_confetti() -> void:
	var w := _world()
	w.race.start_race_now()
	w.race.mark_finished(w.player, 30.0)
	await physics_frames(2)
	check(w.effects.find_child("Confetti", true, false) != null, "confetti burst at finish")
