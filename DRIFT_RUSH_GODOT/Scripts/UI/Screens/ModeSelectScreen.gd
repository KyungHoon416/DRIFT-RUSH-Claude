extends BaseScreen
## G-03 Mode select: Speed / Item / Practice tabs with rules and entry points.

var mode := "speed"
var tabs: Dictionary = {}
var desc: Label
var actions: VBoxContainer
var bots_spin: SpinBox
var laps_spin: SpinBox

const INFO := {
	"speed": ["SPEED RACE · 스피드전", "공격 아이템 없이 드리프트와 부스터로만 승부합니다. 드리프트로 부스터 게이지를 채우고 BOOST로 가속하세요. 기본 3랩, 2~8명."],
	"item": ["ITEM RACE · 아이템전", "트랙의 ? 상자에서 아이템(미사일·실드·터보·벚꽃 함정)을 얻습니다. 뒤처질수록 역전 아이템 확률이 높습니다. 오프라인 봇전과 LAN/전용 서버 친구방 모두 지원 (아이템 판정은 서버)."],
	"practice": ["PRACTICE · 연습하기", "혼자 달리며 랩 타임을 기록합니다(로컬 기록, 서버 미검증). 기울기 조향 연습에 추천."],
}


func build() -> void:
	add_header("MODE SELECT")
	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 12)
	content.add_child(tab_row)
	for m in ["speed", "item", "practice"]:
		var b := UITheme.button(String(INFO[m][0]).split(" · ")[0], Vector2(250, 64))
		b.add_theme_font_override("font", UITheme.display_font())
		b.name = "Tab_" + m
		b.pressed.connect(_select.bind(m))
		tab_row.add_child(b)
		tabs[m] = b
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(panel)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 30)
	panel.add_child(h)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(left)
	desc = UITheme.label("", 22, UITheme.TEXT)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(desc)
	var map_l := UITheme.label("", 20, UITheme.CYAN, true)
	map_l.name = "MapLabel"
	left.add_child(map_l)
	var opts := HBoxContainer.new()
	opts.add_theme_constant_override("separation", 14)
	left.add_child(opts)
	opts.add_child(UITheme.label("봇 수", 20))
	bots_spin = SpinBox.new()
	bots_spin.min_value = 1
	bots_spin.max_value = 7
	bots_spin.value = 7
	opts.add_child(bots_spin)
	opts.add_child(UITheme.label("랩", 20))
	laps_spin = SpinBox.new()
	laps_spin.min_value = 1
	laps_spin.max_value = 5
	laps_spin.value = 3
	opts.add_child(laps_spin)
	actions = VBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	h.add_child(actions)
	add_status()
	_select("speed")


func _select(m: String) -> void:
	mode = m
	for k in tabs.keys():
		UITheme.style_tab(tabs[k], k == m)
	desc.text = "%s\n\n%s" % [INFO[m][0], INFO[m][1]]
	var map_id := String(SaveSettings.get_value("selected_map"))
	(find_child("MapLabel", true, false) as Label).text = "맵: %s" % GameFlow.maps.get(map_id, {}).get("name", map_id)
	bots_spin.get_parent().visible = m != "practice"
	for c in actions.get_children():
		c.queue_free()
	var start_label := "혼자 달리기" if m == "practice" else "봇과 레이스 (오프라인)"
	var start := UITheme.button(start_label, Vector2(330, 76))
	start.name = "StartOffline"
	UITheme.style_primary(start, 26)
	start.pressed.connect(_start_offline)
	actions.add_child(start)
	var map_b := UITheme.button("맵 선택  MAP", Vector2(330, 58))
	map_b.pressed.connect(func(): GameFlow.goto("map_select"))
	actions.add_child(map_b)
	if m != "practice":
		var room := UITheme.button("친구방 만들기 / 참가", Vector2(330, 58))
		room.name = "RoomButton"
		room.pressed.connect(func():
			GameFlow.set_meta("room_mode", m)
			GameFlow.goto("room"))
		actions.add_child(room)
		if m == "item":
			var note := UITheme.label("친구방 아이템전: 서버(방장/전용 서버)가\n획득·명중을 판정합니다", 16, UITheme.CYAN)
			actions.add_child(note)
	var tut := UITheme.button("기울기 튜토리얼", Vector2(330, 54))
	tut.pressed.connect(func(): GameFlow.goto("tutorial"))
	actions.add_child(tut)


func _start_offline() -> void:
	GameFlow.start_offline_race(mode, String(SaveSettings.get_value("selected_map")), int(bots_spin.value), int(laps_spin.value))
