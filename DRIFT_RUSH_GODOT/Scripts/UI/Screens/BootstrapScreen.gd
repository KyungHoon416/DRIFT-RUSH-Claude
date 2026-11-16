extends BaseScreen
## App entry: shows the logo, restores a saved session (auto-login) and routes
## to the lobby or the login screen.
## Dedicated server: `godot --headless --path . -- --server [--port=7777]
## [--map=sakura_valley] [--mode=speed|item] [--laps=3] [--capacity=8]
## [--min-players=2]` hosts a room and waits here between races.

var server_label: Label


func build() -> void:
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(center)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(v)
	var logo := UITheme.title_label("DRIFT RUSH", 96, UITheme.ORANGE)
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(logo)
	var sub := UITheme.title_label("3D MOBILE KART RACING", 26, UITheme.CYAN)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	server_label = UITheme.label("불러오는 중…", 20, UITheme.TEXT_DIM)
	server_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(server_label)
	_route.call_deferred()


func _route() -> void:
	if GameFlow.test_mode:
		return
	if GameFlow.cmdline.has("server"):
		_run_dedicated()
		return
	var r: Dictionary = await Backend.restore_session()
	GameFlow.goto("lobby" if r.get("ok", false) else "login")


func _run_dedicated() -> void:
	var a: Dictionary = GameFlow.cmdline
	if not (Net.is_host() and Net.dedicated):
		var settings := {
			"map": a.get("map", "sakura_valley"), "mode": a.get("mode", "speed"),
			"laps": int(a.get("laps", "3")), "capacity": int(a.get("capacity", "8")),
		}
		Net.auto_start_min_players = maxi(2, int(a.get("min-players", "2")))
		if Net.host_dedicated(int(a.get("port", str(Net.DEFAULT_PORT))), settings) != OK:
			server_label.text = "서버 포트를 열 수 없습니다."
			get_tree().quit(1)
			return
	server_label.text = "DEDICATED SERVER · UDP %d · ROOM %s\n%d명 접속 · 전원 READY 시 자동 시작" % [Net.server_port, Net.room_code, Net.players.size()]
	print("[Server] waiting for players (room %s)" % Net.room_code)
