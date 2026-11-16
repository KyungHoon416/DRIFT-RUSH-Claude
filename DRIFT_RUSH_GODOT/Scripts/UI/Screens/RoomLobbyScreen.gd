extends BaseScreen
## G-04 Create/join room + G-05 friend waiting room.
## Two paths:
##  · LAN room (works now): ENet host/join on the same Wi-Fi, up to 8 players,
##    ready states, host badge, host-only settings & start.
##  · Online friend room (Firebase): 6-char invite code via Cloud Functions.
##    With the MOCK backend the code flow and error states work locally but no
##    other device can join (clearly labelled).

var view := "menu"
var body: Control
var slots: GridContainer
var start_btn: Button
var ready_btn: Button
var info_label: Label
var online_code := ""
var my_ready := false


func build() -> void:
	add_header("FRIEND LOBBY", "")
	var back := find_child("BackButton", true, false) as Button
	if back == null:
		var h: HBoxContainer = content.get_child(0)
		back = UITheme.button("◀", Vector2(72, 60))
		back.name = "BackButton"
		h.add_child(back)
		h.move_child(back, 0)
	back.pressed.connect(_on_back)
	content.get_child(0).add_child(mock_badge())
	body = VBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(body)
	add_status()
	Net.lobby_updated.connect(_on_lobby_updated)
	Net.connection_failed.connect(_on_net_error)
	Net.disconnected.connect(_on_net_error)
	Net.connected.connect(_on_net_connected)
	if Net.is_online():
		_show_lan_room()
	else:
		_show_menu()


func _on_net_error(reason: String) -> void:
	set_status(reason, true)
	_show_menu()


func _on_net_connected() -> void:
	set_status("연결됨. 대기실 동기화 중…")


func _clear() -> void:
	for c in body.get_children():
		c.queue_free()


func _show_menu() -> void:
	view = "menu"
	_clear()
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 20)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(h)
	# --- LAN
	var lan := PanelContainer.new()
	lan.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(lan)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 10)
	lan.add_child(lv)
	lv.add_child(UITheme.title_label("LAN 방 (같은 Wi-Fi)", 26, UITheme.CYAN))
	lv.add_child(UITheme.label("실제 동작 · ENet P2P(방장 호스트) · 2~8명", 16, UITheme.TEXT_DIM))
	var cap_row := HBoxContainer.new()
	cap_row.add_child(UITheme.label("정원", 20))
	var cap := SpinBox.new()
	cap.name = "Capacity"
	cap.min_value = 2
	cap.max_value = 8
	cap.value = 8
	cap_row.add_child(cap)
	lv.add_child(cap_row)
	var host := UITheme.button("방 만들기 (호스트)", Vector2(0, 62))
	host.name = "HostLan"
	UITheme.style_primary(host, 24)
	host.pressed.connect(func(): _host_lan(int(cap.value)))
	lv.add_child(host)
	var ip := LineEdit.new()
	ip.name = "IpInput"
	ip.placeholder_text = "호스트 IP (예: 192.168.0.12)"
	ip.text = "127.0.0.1" if not OS.has_feature("mobile") else ""
	lv.add_child(ip)
	var join := UITheme.button("IP로 참가", Vector2(0, 56))
	join.name = "JoinLan"
	join.pressed.connect(func(): _join_lan(ip.text.strip_edges()))
	lv.add_child(join)
	var ips := Net.local_ip_addresses()
	lv.add_child(UITheme.label("내 IP: %s" % (", ".join(ips) if ips.size() > 0 else "확인 불가"), 16, UITheme.TEXT_DIM))
	# --- Online
	var on := PanelContainer.new()
	on.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(on)
	var ov := VBoxContainer.new()
	ov.add_theme_constant_override("separation", 10)
	on.add_child(ov)
	ov.add_child(UITheme.title_label("온라인 친구방", 26, UITheme.PINK))
	ov.add_child(UITheme.label("초대 코드 6자리 · Firebase 필요" + (" (현재 MOCK: 로컬 검증만)" if Backend.mode == "mock" else ""), 16, UITheme.ORANGE if Backend.mode == "mock" else UITheme.TEXT_DIM))
	var priv := CheckButton.new()
	priv.name = "Private"
	priv.text = "비공개 방 (코드로만 입장)"
	priv.button_pressed = true
	ov.add_child(priv)
	var create := UITheme.button("코드 방 만들기", Vector2(0, 58))
	create.name = "CreateOnline"
	create.pressed.connect(func(): _create_online(not priv.button_pressed, int(cap.value)))
	ov.add_child(create)
	var code := LineEdit.new()
	code.name = "CodeInput"
	code.placeholder_text = "초대 코드 (예: A7F3K9)"
	code.max_length = 6
	ov.add_child(code)
	var join_c := UITheme.button("코드로 참가", Vector2(0, 56))
	join_c.name = "JoinOnline"
	join_c.pressed.connect(func(): _join_online(code.text))
	ov.add_child(join_c)


# ------------------------------------------------------------- LAN
func _host_lan(capacity: int) -> void:
	var err := Net.host_lan(GameFlow.player_name(), String(SaveSettings.get_value("kart_color")), Net.DEFAULT_PORT, capacity)
	if err == OK:
		var mode: String = GameFlow.get_meta("room_mode", "speed")
		Net.update_room_settings({"mode": "speed" if mode == "item" else mode, "map": SaveSettings.get_value("selected_map")})
		_show_lan_room()


func _join_lan(ip: String) -> void:
	if not ip.is_valid_ip_address():
		set_status("올바른 IP 주소를 입력하세요.", true)
		return
	set_status("%s 에 연결 중…" % ip)
	if Net.join_lan(ip, GameFlow.player_name(), String(SaveSettings.get_value("kart_color"))) == OK:
		_show_lan_room()


func _show_lan_room() -> void:
	view = "lan_room"
	_clear()
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(h)
	slots = GridContainer.new()
	slots.columns = 4
	slots.add_theme_constant_override("h_separation", 12)
	slots.add_theme_constant_override("v_separation", 12)
	slots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(slots)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 10)
	side.custom_minimum_size = Vector2(300, 0)
	h.add_child(side)
	info_label = UITheme.label("", 18, UITheme.TEXT)
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(info_label)
	var map_opt := OptionButton.new()
	map_opt.name = "MapOption"
	for id in GameFlow.maps.keys():
		map_opt.add_item(String(GameFlow.maps[id]["name"]))
		map_opt.set_item_metadata(map_opt.item_count - 1, id)
	map_opt.item_selected.connect(func(i): Net.update_room_settings({"map": map_opt.get_item_metadata(i)}))
	side.add_child(map_opt)
	var laps := SpinBox.new()
	laps.name = "LapsSpin"
	laps.min_value = 1
	laps.max_value = 5
	laps.value = int(Net.room_settings.get("laps", 3))
	laps.prefix = "LAP"
	laps.value_changed.connect(func(v): Net.update_room_settings({"laps": int(v)}))
	side.add_child(laps)
	var copy := UITheme.button("호스트 IP 복사", Vector2(0, 50))
	copy.pressed.connect(func():
		DisplayServer.clipboard_set(", ".join(Net.local_ip_addresses()))
		set_status("복사했습니다. 친구에게 공유하세요."))
	side.add_child(copy)
	ready_btn = UITheme.button("READY", Vector2(0, 64))
	ready_btn.name = "ReadyButton"
	ready_btn.pressed.connect(_toggle_ready)
	side.add_child(ready_btn)
	start_btn = UITheme.button("START  »", Vector2(0, 76))
	start_btn.name = "StartButton"
	UITheme.style_primary(start_btn, 32)
	start_btn.pressed.connect(_on_start)
	side.add_child(start_btn)
	var leave := UITheme.button("방 나가기", Vector2(0, 50))
	leave.pressed.connect(func():
		Net.leave()
		_show_menu())
	side.add_child(leave)
	_on_lobby_updated(Net.players)


func _toggle_ready() -> void:
	my_ready = not my_ready
	Net.set_ready(my_ready)


func _on_start() -> void:
	var c := Net.can_start()
	if not c["ok"]:
		set_status(String(c["reason"]), true)
		return
	Net.host_start_race()


func _on_lobby_updated(players: Dictionary) -> void:
	if view != "lan_room" or slots == null:
		return
	for c in slots.get_children():
		c.queue_free()
	var ids := players.keys()
	ids.sort()
	var cap := int(Net.room_settings.get("capacity", 8))
	for i in 8:
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(150, 130)
		var v := VBoxContainer.new()
		card.add_child(v)
		if i < ids.size():
			var p: Dictionary = players[ids[i]]
			var col := GameFlow.kart_color(String(p["color"]))
			card.add_theme_stylebox_override("panel", UITheme.box(Color(0.08, 0.15, 0.36, 0.9), col, 14, 3 if ids[i] == Net.my_id() else 1))
			v.add_child(UITheme.label("%d%s" % [i + 1, "  ★HOST" if p["host"] else ""], 16, UITheme.ORANGE if p["host"] else UITheme.TEXT_DIM, true))
			var sw := ColorRect.new()
			sw.color = col
			sw.custom_minimum_size = Vector2(0, 26)
			v.add_child(sw)
			v.add_child(UITheme.label(String(p["name"]), 20, UITheme.TEXT, true))
			var st := "연결 끊김" if not p["connected"] else ("HOST" if p["host"] else ("✔ READY" if p["ready"] else "미준비"))
			var stc := UITheme.RED if not p["connected"] else (UITheme.GREEN if p["ready"] or p["host"] else UITheme.TEXT_DIM)
			v.add_child(UITheme.label(st, 18, stc, true))
		elif i < cap:
			card.add_theme_stylebox_override("panel", UITheme.box(Color(0.05, 0.09, 0.22, 0.6), Color(0.2, 0.3, 0.5), 14, 1))
			v.add_child(UITheme.label("%d  빈 자리" % (i + 1), 16, UITheme.TEXT_DIM))
		else:
			card.modulate = Color(1, 1, 1, 0.25)
		slots.add_child(card)
	var host := Net.is_host()
	var map_name: String = GameFlow.maps.get(Net.room_settings.get("map", ""), {}).get("name", "?")
	info_label.text = "%s · %s · %d LAP\n%d/%d명" % [map_name, "SPEED RACE", int(Net.room_settings.get("laps", 3)), ids.size(), cap]
	(find_child("MapOption", true, false) as OptionButton).disabled = not host
	(find_child("LapsSpin", true, false) as SpinBox).editable = host
	start_btn.visible = host
	ready_btn.visible = not host
	if not host and players.has(Net.my_id()):
		my_ready = bool(players[Net.my_id()]["ready"])
		ready_btn.text = "준비 취소" if my_ready else "READY"
	if host:
		var c := Net.can_start()
		start_btn.disabled = not c["ok"]
		set_status("" if c["ok"] else String(c["reason"]))


# ------------------------------------------------------------- Online (Firebase / mock)
func _create_online(public: bool, capacity: int) -> void:
	set_status("방 만드는 중…")
	var r: Dictionary = await Backend.create_room({"public": public, "capacity": capacity, "mode": "speed",
		"map": SaveSettings.get_value("selected_map"), "laps": 3})
	if not r.get("ok", false):
		set_status(Backend.error_text(String(r.get("error", ""))), true)
		return
	online_code = String(r["code"])
	_show_online_room(r.get("room", {}))


func _join_online(code: String) -> void:
	set_status("참가 중…")
	var r: Dictionary = await Backend.join_room(code)
	if not r.get("ok", false):
		set_status(Backend.error_text(String(r.get("error", ""))), true)
		return
	online_code = String(r["code"])
	_show_online_room(r.get("room", {}))


func _show_online_room(room: Dictionary) -> void:
	view = "online_room"
	_clear()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	body.add_child(v)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	v.add_child(row)
	row.add_child(UITheme.label("ROOM CODE", 18, UITheme.TEXT_DIM))
	var cl := UITheme.title_label(online_code, 48, Color.WHITE)
	cl.name = "RoomCode"
	row.add_child(cl)
	var copy := UITheme.button("복사", Vector2(100, 54))
	copy.pressed.connect(func():
		DisplayServer.clipboard_set(online_code)
		set_status("초대 코드를 복사했습니다."))
	row.add_child(copy)
	v.add_child(UITheme.label("%s · 정원 %d · %s" % ["공개" if room.get("public", false) else "비공개", int(room.get("capacity", 8)), GameFlow.maps.get(room.get("map", ""), {}).get("name", "")], 20))
	if Backend.mode == "mock":
		v.add_child(UITheme.label("MOCK 백엔드: 코드 생성/검증 흐름만 로컬에서 동작합니다. 다른 기기의 실제 참가와 실시간 경기는 Firebase + 게임 서버 연결 후 가능합니다. 지금 친구와 달리려면 LAN 방을 사용하세요.", 17, UITheme.ORANGE))
	var leave := UITheme.button("방 나가기", Vector2(240, 54))
	leave.pressed.connect(func():
		await Backend.leave_room()
		_show_menu())
	v.add_child(leave)
	set_status("")


func _on_back() -> void:
	if view == "lan_room":
		Net.leave()
	elif view == "online_room":
		await Backend.leave_room()
	GameFlow.goto("lobby")
