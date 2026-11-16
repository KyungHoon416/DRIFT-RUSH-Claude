extends Node
## Renders real screenshots of UI screens and races into Docs/screenshots/.
## Needs a display (e.g. xvfb-run) — NOT headless:
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-method gl_compatibility \
##       --fixed-fps 30 --path . res://Tools/Capture.tscn -- --autopilot

var out_dir := ""


func _ready() -> void:
	GameFlow.test_mode = true
	out_dir = ProjectSettings.globalize_path("res://Docs/screenshots")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("SHOT ", name, " ", img.get_size())


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _screen(path: String, name: String, frames := 20) -> Node:
	var c: Node = load(path).instantiate()
	add_child(c)
	await _wait(frames)
	await _shot(name)
	return c


func _run() -> void:
	var only: String = GameFlow.cmdline.get("only", "")
	if only == "" or only == "ui":
		for s in [["res://Scenes/UI/Login.tscn", "01_login"], ["res://Scenes/UI/Lobby.tscn", "02_lobby"],
				["res://Scenes/UI/ModeSelect.tscn", "03_mode_select"], ["res://Scenes/UI/MapSelect.tscn", "06_map_select"],
				["res://Scenes/UI/Garage.tscn", "07_garage"], ["res://Scenes/UI/TiltTutorial.tscn", "08_tilt_tutorial"],
				["res://Scenes/UI/Settings.tscn", "12_settings"]]:
			var c := await _screen(s[0], s[1], 30)
			c.queue_free()
			await _wait(2)
		# LAN room with host
		Net.host_lan("DRIFT_RUSH", "orange", 7790, 8)
		var room := await _screen("res://Scenes/UI/RoomLobby.tscn", "05_friend_lobby", 20)
		room.queue_free()
		Net.leave()
		await _wait(2)
	if only == "" or only == "race":
		GameFlow.race_config = {"mode": "speed", "map": "sakura_valley", "laps": 3, "bots": 7, "online": false, "seed": 3}
		var w: RaceWorld = load("res://Scenes/Race/RaceWorld.tscn").instantiate()
		add_child(w)
		await _wait(40)
		await _shot("09a_race_countdown")
		await _wait(170)
		await _shot("09b_race_start")
		await _wait(300)
		await _shot("09c_race_hud")
		await _wait(400)
		await _shot("09d_race_sakura")
		w.player.drift_input = true
		await _wait(200)
		await _shot("09e_race_later")
		w.race.force_finish()
		await _wait(5)
		w.queue_free()
		await _wait(3)
		var res := await _screen("res://Scenes/UI/RaceResult.tscn", "11_result", 15)
		res.queue_free()
		await _wait(2)
	if only == "" or only == "neon":
		GameFlow.race_config = {"mode": "item", "map": "neon_city", "laps": 3, "bots": 5, "online": false, "seed": 4}
		var n: RaceWorld = load("res://Scenes/Race/RaceWorld.tscn").instantiate()
		add_child(n)
		await _wait(420)
		await _shot("10_neon_city_item_race")
		n.queue_free()
		await _wait(3)
	print("CAPTURE DONE")
	get_tree().quit()
