extends BaseScreen
## G-11 Race result: 1~8 rows (rank, name, time, best lap, DNF), retry / same
## room / lobby. Rewards are shown only for server-verified results (none yet).


func build() -> void:
	var res: Dictionary = GameFlow.last_result
	var rows: Array = res.get("results", [])
	var h := UITheme.header("RACE RESULT", Callable())
	content.add_child(h)
	var map_name: String = GameFlow.maps.get(res.get("map", ""), {}).get("name", "")
	h.add_child(UITheme.label("  %s · %s · %s LAP" % [map_name, String(res.get("mode", "")).to_upper(), str(res.get("laps", ""))], 20, UITheme.TEXT_DIM))
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(panel)
	var list := VBoxContainer.new()
	list.name = "ResultList"
	list.add_theme_constant_override("separation", 4)
	panel.add_child(list)
	list.add_child(_row(["#", "PLAYER", "TIME", "BEST LAP"], true, false))
	if rows.is_empty():
		list.add_child(UITheme.label("결과가 없습니다.", 20, UITheme.TEXT_DIM))
	for r in rows:
		var t: String = "DNF" if r.get("dnf", false) else GameFlow.format_time(float(r.get("time", -1)))
		list.add_child(_row([GameFlow.ordinal(int(r["rank"])), String(r["name"]), t, GameFlow.format_time(float(r.get("best_lap", -1)))], false, bool(r.get("is_player", false))))
	var note := "보상: 서버 검증 결과에만 지급 — 현재 결과는 미검증(로컬/LAN)이므로 보상 없음."
	if not res.get("online", false):
		note += "  개인 최고 기록은 이 기기에만 저장됩니다."
	content.add_child(UITheme.label(note, 15, UITheme.TEXT_DIM))
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_END
	btns.add_theme_constant_override("separation", 14)
	content.add_child(btns)
	if res.get("online", false):
		var room := UITheme.button("같은 방으로", Vector2(240, 66))
		room.name = "SameRoomButton"
		room.disabled = not Net.is_online()
		room.pressed.connect(func():
			Net.back_to_room()
			GameFlow.goto("room"))
		btns.add_child(room)
	else:
		var again := UITheme.button("다시 하기  RETRY", Vector2(260, 66))
		again.name = "RetryButton"
		UITheme.style_primary(again, 26)
		again.pressed.connect(func():
			var c := GameFlow.race_config
			GameFlow.start_offline_race(String(c["mode"]), String(c["map"]), int(c["bots"]), int(c["laps"])))
		btns.add_child(again)
	var lobby := UITheme.button("로비로  LOBBY", Vector2(240, 66))
	lobby.name = "LobbyButton"
	lobby.pressed.connect(func():
		if Net.is_online():
			Net.leave()
		GameFlow.goto("lobby"))
	btns.add_child(lobby)
	AudioFeedback.stop_race_loops()


func _row(cells: Array, header: bool, me: bool) -> PanelContainer:
	var p := PanelContainer.new()
	var bg := Color(0.2, 0.45, 1.0, 0.45) if me else Color(0.05, 0.1, 0.25, 0.5 if header else 0.8)
	p.add_theme_stylebox_override("panel", UITheme.box(bg, UITheme.CYAN if me else Color(0, 0, 0, 0), 10, 2 if me else 0))
	var h := HBoxContainer.new()
	p.add_child(h)
	var widths := [110, 420, 230, 230]
	for i in cells.size():
		var l := UITheme.label(String(cells[i]), 18 if header else 24, UITheme.TEXT_DIM if header else Color.WHITE, true)
		if i == 0 and not header:
			l.add_theme_font_override("font", UITheme.display_font())
		l.custom_minimum_size = Vector2(widths[i], 0)
		h.add_child(l)
	return p
