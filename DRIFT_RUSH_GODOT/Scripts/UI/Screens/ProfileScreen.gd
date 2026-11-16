extends BaseScreen
## G-13 Profile / friends / ranking. Friend list and global ranking need the
## Firebase backend + server-verified results; local personal bests are shown
## and labelled as unverified. Clients never upload records themselves.


func build() -> void:
	add_header("PROFILE · RANK")
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 20)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(h)
	var a := PanelContainer.new()
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(a)
	var av := VBoxContainer.new()
	av.add_theme_constant_override("separation", 10)
	a.add_child(av)
	av.add_child(UITheme.title_label(GameFlow.player_name(), 34))
	var fc: String = Backend.user.get("friend_code", "")
	av.add_child(UITheme.label("친구 코드: %s" % (fc if fc != "" else "—"), 20, UITheme.TEXT, true))
	av.add_child(UITheme.label("계정: %s" % String(Backend.user.get("provider", "로그인 안 됨")), 18, UITheme.TEXT_DIM))
	av.add_child(mock_badge())
	av.add_child(UITheme.title_label("내 스피드전 기록 (로컬 · 서버 미검증)", 22, UITheme.CYAN))
	var laps: Dictionary = SaveSettings.get_value("best_laps")
	var races: Dictionary = SaveSettings.get_value("best_races")
	if laps.is_empty():
		av.add_child(UITheme.label("아직 기록이 없습니다. 연습 주행을 완주해 보세요!", 18, UITheme.TEXT_DIM))
	for id in laps.keys():
		var nm: String = GameFlow.maps.get(id, {}).get("name", id)
		av.add_child(UITheme.label("%s  ·  베스트 랩 %s  ·  3랩 %s" % [nm, GameFlow.format_time(float(laps[id])), GameFlow.format_time(float(races.get(id, -1)))], 19))
	var b := PanelContainer.new()
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(b)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 10)
	b.add_child(bv)
	bv.add_child(UITheme.title_label("친구", 24, UITheme.PINK))
	var friends_label := UITheme.label("불러오는 중…", 18, UITheme.TEXT_DIM)
	friends_label.name = "FriendsLabel"
	friends_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bv.add_child(friends_label)
	bv.add_child(UITheme.title_label("랭킹", 24, UITheme.ORANGE))
	var rank := UITheme.label("글로벌 랭킹은 게임 서버가 검증한 결과만 집계합니다. Firebase/게임 서버 연결 전에는 표시하지 않습니다.", 18, UITheme.TEXT_DIM)
	rank.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bv.add_child(rank)
	_load_friends(friends_label)


func _load_friends(l: Label) -> void:
	var r: Dictionary = await Backend.get_friends()
	if not is_instance_valid(l):
		return
	var arr: Array = r.get("friends", [])
	if not r.get("ok", false):
		l.text = Backend.error_text(String(r.get("error", "")))
	elif arr.is_empty():
		l.text = "친구가 없습니다." + (" (MOCK 백엔드: 친구 기능은 Firebase 연결 후 사용 가능)" if Backend.mode == "mock" else "")
	else:
		l.text = "\n".join(arr.map(func(f): return str(f.get("nickname", "?"))))
