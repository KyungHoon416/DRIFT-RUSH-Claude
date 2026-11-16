class_name RaceWorld
extends Node3D
## Race scene root. Builds the selected track, spawns karts (player, bots or
## network peers), camera, HUD, race/item managers and wires feedback
## (haptics, sound, camera shake). Reads GameFlow.race_config.

signal race_ready

var config: Dictionary
var track: TrackBuilder
var race: RaceManager
var items: ItemManager
var session: RaceSession
var hud: RaceHUD
var camera: ChaseCamera
var player: KartController
var player_input: PlayerInput
var karts: Array[KartController] = []
var karts_by_peer: Dictionary = {}
var online := false
var _finish_timer := -1.0
var _autopilot: AIDriver


func _ready() -> void:
	config = GameFlow.race_config.duplicate()
	online = bool(config.get("online", false)) and Net.is_online()
	var map_id := String(config.get("map", "sakura_valley"))
	var map_info: Dictionary = GameFlow.maps.get(map_id, GameFlow.maps.get("sakura_valley", {}))
	var scene: PackedScene = load(String(map_info.get("scene", "res://Scenes/Tracks/SakuraValley.tscn")))
	track = scene.instantiate()
	add_child(track)
	GameFlow.apply_viewport_quality(get_viewport())

	race = RaceManager.new()
	race.name = "RaceManager"
	add_child(race)
	_spawn_karts()
	race.setup(track, karts, int(config.get("laps", 3)))
	race.authoritative = (not online) or Net.is_host()
	race.auto_finish_on_player = not online

	if player:
		camera = ChaseCamera.new()
		camera.name = "ChaseCamera"
		add_child(camera)
		camera.target = player
		camera.current = true
		camera.snap()
		_add_petals()

	if String(config.get("mode")) == "item":
		items = ItemManager.new()
		items.name = "ItemManager"
		add_child(items)
		var role := "offline"
		if online:
			role = "server" if Net.is_host() else "client"
		items.setup(track, race, role, karts_by_peer)

	if player:
		hud = preload("res://Scenes/UI/RaceHUD.tscn").instantiate()
		add_child(hud)
		hud.setup(self, race, player, online, items != null)
		hud.pause_requested.connect(_on_pause)
		hud.exit_requested.connect(_on_exit)

	race.race_started.connect(_on_race_started)
	race.kart_finished.connect(_on_kart_finished)
	race.race_finished.connect(_on_race_finished)
	if player:
		_wire_feedback(player)
		AudioFeedback.play_bgm(true)

	if online:
		session = RaceSession.new()
		session.name = "RaceSession"
		add_child(session)
		session.setup(race, player, karts_by_peer)
		if hud:
			session.corrected.connect(func(): hud.show_message("서버 위치 보정", 1.2, UITheme.CYAN))
		Net.countdown_requested.connect(_on_net_countdown)
		Net.results_received.connect(_on_net_results)
		Net.disconnected.connect(_on_net_disconnected)
		Net.peer_left.connect(_on_peer_left)
		Net.report_loaded.call_deferred()
		if Net.is_host():
			get_tree().create_timer(10.0).timeout.connect(_host_load_timeout)
	else:
		race.start_countdown(3.0)
	race_ready.emit()


func _spawn_karts() -> void:
	var kart_scene: PackedScene = preload("res://Scenes/Vehicles/KartBase.tscn")
	var my_color := GameFlow.kart_color(String(SaveSettings.get_value("kart_color")))
	if online:
		var ids: Array = Net.players.keys()
		ids.sort()
		for i in ids.size():
			var id: int = ids[i]
			var info: Dictionary = Net.players[id]
			var k: KartController = kart_scene.instantiate()
			k.peer_id = id
			var mine := id == Net.my_id() and Net.has_local_player()
			k.is_remote = not mine
			k.setup(String(info["name"]), GameFlow.kart_color(String(info["color"])), mine)
			add_child(k)
			k.place(track.grid_transform(i))
			karts.append(k)
			karts_by_peer[id] = k
			if k.is_player:
				player = k
			else:
				k.model.set_name_tag(k.display_name, Color.WHITE)
	else:
		var bots := int(config.get("bots", 0))
		if String(config.get("mode")) == "practice":
			bots = 0
		var total := bots + 1
		var player_slot := total - 1   # player starts at the back of the grid
		var colors := GameFlow.KART_COLORS.keys()
		var bot_i := 0
		for slot in total:
			var k: KartController = kart_scene.instantiate()
			if slot == player_slot:
				k.setup(GameFlow.player_name(), my_color, true)
			else:
				var cid: String = colors[(bot_i + 1) % colors.size()]
				var col := GameFlow.kart_color(cid)
				if col.is_equal_approx(my_color):
					col = GameFlow.kart_color(colors[(bot_i + 2) % colors.size()])
				k.setup(GameFlow.BOT_NAMES[bot_i % GameFlow.BOT_NAMES.size()], col, false)
				k.speed_multiplier = randf_range(0.9, 0.97)
				bot_i += 1
			add_child(k)
			k.place(track.grid_transform(slot))
			karts.append(k)
			if slot == player_slot:
				player = k
			else:
				var ai := AIDriver.new()
				ai.kart = k
				ai.track = track
				ai.use_items = String(config.get("mode")) == "item"
				k.add_child(ai)
				k.model.set_name_tag(k.display_name, Color.WHITE)
	if player == null:
		return   # dedicated server: every kart is a network ghost
	if GameFlow.autopilot:
		_autopilot = AIDriver.new()
		_autopilot.kart = player
		_autopilot.track = track
		_autopilot.use_items = true
		player.add_child(_autopilot)
	else:
		player_input = PlayerInput.new()
		player_input.kart = player
		player.add_child(player_input)


func _add_petals() -> void:
	if not bool(track.theme.get("petals", false)) or not bool(GameFlow.quality_profile().get("petals", true)):
		return
	var p := CPUParticles3D.new()
	p.name = "Petals"
	p.amount = 90
	p.lifetime = 5.0
	p.preprocess = 4.0
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(22, 2, 22)
	p.direction = Vector3(0.3, -1, 0.2)
	p.spread = 30.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.6
	p.gravity = Vector3(0.4, -0.6, 0.2)
	p.angular_velocity_min = -90
	p.angular_velocity_max = 90
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.3
	var q := QuadMesh.new()
	q.size = Vector2(0.16, 0.11)
	p.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_color = Color(1.0, 0.75, 0.86)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	p.material_override = m
	p.position = Vector3(0, 8, -10)
	camera.add_child(p)


func _wire_feedback(k: KartController) -> void:
	k.impact.connect(func(kind: String, strength: float):
		Haptics.impact(kind, strength)
		AudioFeedback.play_impact(kind, strength)
		camera.add_shake(strength * (0.25 if kind == "kart" else 0.35)))
	k.boost_started.connect(func(kind: String):
		AudioFeedback.play("boost" if kind != "mini" else "mini_boost")
		Haptics.impact("boost", 0.6))
	k.drift_started.connect(func(_d: int): AudioFeedback.set_drift(true))
	k.drift_ended.connect(func(_c: float, _t: int): AudioFeedback.set_drift(false))


func _process(_delta: float) -> void:
	if player:
		AudioFeedback.set_engine(race.state == RaceManager.State.RACING or race.state == RaceManager.State.COUNTDOWN,
			absf(player.speed) / maxf(1.0, player.max_speed_now()))
	if _finish_timer > 0.0:
		_finish_timer -= _delta
		if _finish_timer <= 0.0:
			if online and not Net.has_local_player():
				Net.back_to_room()
				GameFlow.goto("bootstrap")   # dedicated server: back to waiting room
			else:
				GameFlow.goto("result")


func _on_race_started() -> void:
	pass


func _on_kart_finished(k: KartController, _rank: int, _t: float) -> void:
	if k == player and _autopilot == null:
		# Cool-down lap on autopilot while others finish.
		if player_input:
			player_input.enabled = false
		_autopilot = AIDriver.new()
		_autopilot.kart = player
		_autopilot.track = track
		_autopilot.use_items = false
		player.add_child(_autopilot)


func _on_race_finished(results: Array) -> void:
	if online and not Net.is_host():
		return   # clients wait for host results
	_store_results(results)


func _store_results(results: Array) -> void:
	if _finish_timer > 0.0 or GameFlow.last_result.get("_token") == get_instance_id():
		return   # host receives its own broadcast too
	var best := -1.0
	var total := -1.0
	for r in results:
		var mine: bool = (int(r.get("peer_id", 0)) == Net.my_id()) if online else bool(r.get("is_player", false))
		r["is_player"] = mine   # host-built results are re-labelled from this client's view
		if mine:
			best = float(r["best_lap"])
			total = float(r["time"])
	GameFlow.last_result = {
		"results": results, "map": config.get("map"), "mode": config.get("mode"), "online": online,
		"laps": config.get("laps"), "verified": false, "_token": get_instance_id(),
	}
	if online and not Net.has_local_player():
		print("[Server] race finished: ", JSON.stringify(results))
	if not online and total > 0.0:
		SaveSettings.record_local_best(String(config.get("map")), best, total)
	Backend.submit_race_result(GameFlow.last_result)
	AudioFeedback.stop_race_loops()
	_finish_timer = 2.5


func _on_pause(p: bool) -> void:
	if online:
		# Server simulation continues: hand the wheel to the autopilot.
		if player_input:
			player_input.enabled = not p
			if p:
				player_input.release_all()
		if p and _autopilot == null:
			_autopilot = AIDriver.new()
			_autopilot.kart = player
			_autopilot.track = track
			_autopilot.use_items = false
			player.add_child(_autopilot)
		elif not p and _autopilot and not race.lap_managers[player].finished:
			_autopilot.queue_free()
			_autopilot = null
	else:
		get_tree().paused = p
		AudioFeedback.set_engine(false)


func _on_exit() -> void:
	get_tree().paused = false
	AudioFeedback.stop_race_loops()
	if online:
		Net.leave()
	GameFlow.goto("lobby")


func _on_net_countdown(delay: float) -> void:
	get_tree().create_timer(delay).timeout.connect(func(): race.start_countdown(3.0))


func _host_load_timeout() -> void:
	if race.state == RaceManager.State.IDLE:
		Net.force_countdown()


func _on_net_results(results: Array) -> void:
	_store_results(results)


func _on_net_disconnected(reason: String) -> void:
	if hud:
		hud.show_message(reason, 4.0, UITheme.RED)
	AudioFeedback.stop_race_loops()
	get_tree().create_timer(3.0).timeout.connect(func(): GameFlow.goto("lobby"))


func _on_peer_left(id: int) -> void:
	if karts_by_peer.has(id):
		var k: KartController = karts_by_peer[id]
		if hud:
			hud.show_message("%s 연결 끊김 (DNF)" % k.display_name, 2.5, UITheme.RED)
		if Net.is_host() and race.lap_managers.has(k):
			race.lap_managers[k].dnf = true
