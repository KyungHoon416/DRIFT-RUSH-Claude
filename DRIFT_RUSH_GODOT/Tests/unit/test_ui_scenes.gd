extends TestCase
## Every UI scene loads, builds and survives a few frames; key buttons exist
## and are wired (pressing them changes GameFlow.last_goto).

const SCENES := ["App/Bootstrap", "UI/Login", "UI/Lobby", "UI/ModeSelect", "UI/RoomLobby", "UI/MapSelect",
	"UI/Garage", "UI/TiltTutorial", "UI/Settings", "UI/Profile", "UI/RaceResult"]


func _open(name: String) -> Control:
	var c: Control = load("res://Scenes/%s.tscn" % name).instantiate()
	spawn(c)
	return c


func test_all_screens_instantiate() -> void:
	GameFlow.last_result = {"results": [{"rank": 1, "name": "A", "time": 60.0, "best_lap": 19.0, "dnf": false, "is_player": true},
		{"rank": 2, "name": "B", "time": -1.0, "best_lap": -1.0, "dnf": true, "is_player": false}], "map": "sakura_valley", "mode": "speed", "laps": 3}
	for s in SCENES:
		var c := _open(s)
		await frames(3)
		check(c.get_child_count() > 0, "%s built UI" % s)
		c.queue_free()
		await frames(1)


func _press(root: Node, button_name: String) -> void:
	var b := root.find_child(button_name, true, false) as BaseButton
	check(b != null, "button %s exists" % button_name)
	if b:
		check(not b.disabled, "button %s enabled" % button_name)
		b.pressed.emit()


func test_navigation_buttons() -> void:
	var lobby := _open("UI/Lobby")
	await frames(2)
	_press(lobby, "PlayButton")
	eq(GameFlow.last_goto, "mode_select", "PLAY → mode select")
	_press(lobby, "FriendsButton")
	eq(GameFlow.last_goto, "room", "FRIENDS → room")
	_press(lobby, "MenuGarage")
	eq(GameFlow.last_goto, "garage", "GARAGE menu")
	_press(lobby, "MenuSettings")
	eq(GameFlow.last_goto, "settings", "SETTINGS menu")
	var mode := _open("UI/ModeSelect")
	await frames(2)
	_press(mode, "Tab_practice")
	_press(mode, "StartOffline")
	eq(GameFlow.last_goto, "race", "practice start → race")
	eq(GameFlow.race_config["mode"], "practice", "practice config")
	eq(GameFlow.race_config["online"], false, "offline race")


func test_room_lobby_error_states() -> void:
	var room := _open("UI/RoomLobby")
	await frames(2)
	await Backend.sign_in_guest()
	var code_in := room.find_child("CodeInput", true, false) as LineEdit
	code_in.text = "QQQQQQ"
	_press(room, "JoinOnline")
	await tree().create_timer(3.6).timeout   # LAN discovery (2.5 s) then backend
	var status := room.find_child("Status", true, false) as Label
	check(status.text.contains("존재하지 않는"), "unknown room code message shown (%s)" % status.text)


func test_map_select_applies_choice() -> void:
	var m := _open("UI/MapSelect")
	await frames(2)
	_press(m, "Card_neon_city")
	eq(SaveSettings.get_value("selected_map"), "neon_city", "map selection saved")
	_press(m, "Card_coral_coast")
	eq(SaveSettings.get_value("selected_map"), "coral_coast", "third map selectable")
	_press(m, "Card_sakura_valley")
	eq(SaveSettings.get_value("selected_map"), "sakura_valley", "map selection restored")


func test_race_hud_layout_and_pause() -> void:
	GameFlow.race_config = {"mode": "speed", "map": "sakura_valley", "laps": 3, "bots": 3, "online": false, "seed": 1}
	var w: RaceWorld = load("res://Scenes/Race/RaceWorld.tscn").instantiate()
	spawn(w)
	await frames(3)
	var hud := w.hud
	var vp := hud.root.get_viewport_rect().size
	var drift := hud.touch.buttons["drift"] as Control
	var brake := hud.touch.buttons["brake"] as Control
	check(drift.global_position.x > vp.x * 0.6 and drift.global_position.y > vp.y * 0.5, "DRIFT bottom-right")
	check(brake.global_position.x < vp.x * 0.4 and brake.global_position.y > vp.y * 0.5, "BRAKE bottom-left")
	check(hud.minimap.global_position.x > vp.x * 0.6 and hud.minimap.global_position.y < vp.y * 0.4, "minimap top-right")
	check(hud.lap_label.text.begins_with("LAP 1/3"), "lap label")
	hud.set_paused(true)
	check(tree().paused, "single player pause pauses the tree")
	hud.set_paused(false)
	check(not tree().paused, "continue unpauses")
	# simulated touch on DRIFT presses the action
	var ev := InputEventScreenTouch.new()
	ev.index = 0
	ev.pressed = true
	ev.position = drift.global_position + drift.size / 2.0
	hud.touch._input(ev)
	check(Input.is_action_pressed("drift"), "touch on DRIFT presses drift action")
	ev.pressed = false
	hud.touch._input(ev)
	check(not Input.is_action_pressed("drift"), "release lifts the action")
