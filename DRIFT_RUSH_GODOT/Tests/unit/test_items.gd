extends TestCase
## Item effects (offline item race on the real track with bots).

var w: RaceWorld


func _world(bots := 3) -> void:
	GameFlow.race_config = {"mode": "item", "map": "sakura_valley", "laps": 3, "bots": bots, "online": false, "seed": 1}
	w = load("res://Scenes/Race/RaceWorld.tscn").instantiate()
	spawn(w)
	await physics_frames(3)
	w.race.start_race_now()
	w.player_input.enabled = false
	for k in w.karts:
		for n in k.get_children():
			if n is AIDriver:
				n.use_items = false


func _bot(i := 0) -> KartController:
	var bots: Array = w.karts.filter(func(k): return k != w.player)
	return bots[i]


func _use(k: KartController, item: String) -> void:
	k.item_cooldown = 0.0
	k.give_item(item)
	w.items.use_item(k)


func test_all_nine_items_can_be_rolled() -> void:
	await _world(1)
	var items: Dictionary = GameFlow.item_rules["items"]
	eq(items.size(), 9, "9 item types defined")
	var seen := {}
	for i in 3000:
		seen[w.items.roll_item(1 + i % 8, 8)] = true
	for id in items.keys():
		check(seen.has(id), "%s appears in rolls" % id)


func test_water_bomb_puddle_slows_karts() -> void:
	await _world(1)
	_use(w.player, "bomb")
	await physics_frames(50)
	eq(w.items.bombs.size(), 1, "bomb exists")
	check(w.items.bombs[0]["landed"], "bomb landed")
	var b := _bot()
	b.place(Transform3D(Basis(), w.items.bombs[0]["to"]))
	await physics_frames(3)
	check(b.slow_timer > 0.0, "kart in the puddle is slowed")
	check(b.max_speed_now() < float(b.stats["max_speed"]) * b.speed_multiplier * 0.7, "top speed reduced while slowed")


func test_emp_spins_nearby_only_and_shield_blocks() -> void:
	await _world(3)
	var near := _bot(0)
	var shielded := _bot(1)
	var far := _bot(2)
	var t := w.track.transform_at(w.track.closest_offset(w.player.global_position) + 8.0, 0.0, 0.05)
	near.place(t)
	shielded.place(w.track.transform_at(w.track.closest_offset(w.player.global_position) + 12.0, 3.0, 0.05))
	shielded.shield_timer = 5.0
	far.place(w.track.transform_at(w.track.closest_offset(w.player.global_position) + 120.0, 0.0, 0.05))
	await physics_frames(2)
	_use(w.player, "emp")
	await physics_frames(2)
	check(near.spin_timer > 0.0, "kart within 25 m spins")
	eq(shielded.spin_timer, 0.0, "shield blocks the EMP")
	eq(far.spin_timer, 0.0, "kart 120 m away unaffected")
	eq(w.player.spin_timer, 0.0, "user unaffected")


func test_magnet_pulls_towards_kart_ahead() -> void:
	await _world(1)
	var ahead := _bot()
	ahead.place(w.track.transform_at(w.track.closest_offset(w.player.global_position) + 40.0, 0.0, 0.05))
	await physics_frames(3)
	_use(w.player, "magnet")
	await physics_frames(1)
	check(w.player.boost.active and w.player.boost.kind == "turbo", "magnet gives a pull boost")
	eq(w.items.beams.size(), 1, "magnet beam drawn")
	check(w.items.beams[0]["b"] == ahead, "beam locks onto the kart ahead")


func test_storm_blinds_only_karts_ahead() -> void:
	await _world(3)
	var ahead := _bot(0)
	var behind := _bot(1)
	var off := w.track.closest_offset(w.player.global_position)
	ahead.place(w.track.transform_at(off + 30.0, 0.0, 0.05))
	behind.place(w.track.transform_at(off - 20.0, 0.0, 0.05))
	_bot(2).place(w.track.transform_at(off - 40.0, 3.0, 0.05))
	await physics_frames(10)
	_use(w.player, "storm")
	await physics_frames(1)
	check(ahead.blind_timer > 0.0, "kart ahead is blinded")
	eq(behind.blind_timer, 0.0, "kart behind is not")
	w.player.blind_timer = 2.0
	await physics_frames(2)
	check(w.hud.blind_fx.visible, "player's screen shows the petal storm when blinded")


func test_ghost_passes_through_karts_and_ignores_items() -> void:
	await _world(1)
	var front := _bot()
	for n in front.get_children():
		if n is AIDriver:
			n.queue_free()
	var off := w.track.closest_offset(w.player.global_position)
	front.place(w.track.transform_at(off + 15.0, 0.0, 0.05))
	front.control_enabled = false
	w.player.place(w.track.transform_at(off, 0.0, 0.05))
	await physics_frames(2)
	_use(w.player, "ghost")
	check(w.player.ghost_timer > 0.0, "ghost active")
	check(not w.player.apply_item_hit(1.0), "items cannot hit a ghost")
	w.player.speed = 25.0
	w.player.steer_input = 0.0
	for i in 60:
		await tree().physics_frame
	var ahead_of_front := (w.player.global_position - front.global_position).dot(front.forward())
	check(ahead_of_front > 2.0, "ghost drove straight through the stopped kart (%.1f m past)" % ahead_of_front)
	await physics_frames(int(3.6 * 60))
	eq(w.player.ghost_timer, 0.0, "ghost wears off")
