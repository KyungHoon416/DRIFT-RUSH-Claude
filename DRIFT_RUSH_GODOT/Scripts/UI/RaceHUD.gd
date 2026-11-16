class_name RaceHUD
extends CanvasLayer
## In-race HUD (G-09) + pause menu (G-10).
## Layout: rank (top-left, expandable standings) · LAP/time/best (top-center)
## · minimap + pause (top-right) · BRAKE/ITEM (bottom-left) · speed + boost
## gauge (bottom-center) · BOOST + big DRIFT (bottom-right).
## No blocking modals while racing; the centre stays clear for driving.

signal pause_requested(paused: bool)
signal exit_requested

var world: Node
var race: RaceManager
var kart: KartController
var online := false
var item_mode := false

var root: Control
var rank_label: Label
var rank_total: Label
var standings_box: VBoxContainer
var standings_panel: PanelContainer
var lap_label: Label
var time_label: Label
var best_label: Label
var speed_label: Label
var gauge: Control
var drift_bar: Control
var center_label: Label
var message_label: Label
var net_label: Label
var minimap: Minimap
var touch: TouchControls
var pause_layer: Control
var confirm_box: Control
var _msg_timer := 0.0
var desktop := true
var help_panel: PanelContainer
var hint_label: Label
var _help_auto_hide := -1.0
var _t := 0.0
var boost_label: Label
var _boost_label_t := 0.0
var _standings_rows: Array[Label] = []
var _gauge_value := 0.0
var _drift_value := 0.0
var _drift_col := Color.WHITE


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.name = "Root"
	root.theme = GameFlow.ui_theme
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build()


func setup(w: Node, r: RaceManager, k: KartController, is_online: bool, is_item: bool) -> void:
	world = w
	race = r
	kart = k
	online = is_online
	item_mode = is_item
	minimap.setup(r.track, r.karts, k)
	var touch_mode := String(SaveSettings.get_value("control_mode")) == "touch"
	touch.configure(touch_mode, item_mode)
	rank_total.text = "/%d" % r.karts.size()
	standings_panel.visible = r.karts.size() > 1
	rank_label.get_parent().get_parent().visible = r.karts.size() > 1
	for i in r.karts.size():
		var l := UITheme.label("", 17, UITheme.TEXT, true)
		standings_box.add_child(l)
		_standings_rows.append(l)
	r.countdown_tick.connect(_on_countdown)
	r.lap_completed.connect(_on_lap)
	r.wrong_way_changed.connect(_on_wrong_way)
	r.kart_finished.connect(_on_finished)
	r.kart_respawned.connect(_on_respawned)
	k.drift_boost.connect(_on_drift_boost)
	k.item_changed.connect(func(it: String): touch.set_item(GameFlow.item_rules.get("items", {}).get(it, {}).get("label", "")))
	touch.set_item("")
	desktop = not OS.has_feature("mobile")
	touch.set_key_hints(desktop)
	if desktop and bool(SaveSettings.get_value("controls_hint")):
		help_panel.visible = true
	r.race_started.connect(func(): _help_auto_hide = 5.0)
	_apply_safe_area()


func _apply_safe_area() -> void:
	var m := GameFlow.safe_margins(root.get_viewport())
	root.offset_left = m["left"]
	root.offset_top = m["top"]
	root.offset_right = -m["right"]
	root.offset_bottom = -m["bottom"]


func _build() -> void:
	# --- top-left: rank + standings
	var tl := VBoxContainer.new()
	tl.position = Vector2(24, 18)
	tl.add_theme_constant_override("separation", 6)
	root.add_child(tl)
	var rank_panel := PanelContainer.new()
	rank_panel.add_theme_stylebox_override("panel", UITheme.box(Color(0.05, 0.1, 0.28, 0.7), Color(0.3, 0.55, 1.0, 0.6), 14, 2, -0.15))
	tl.add_child(rank_panel)
	var rank_row := HBoxContainer.new()
	rank_row.add_theme_constant_override("separation", 2)
	rank_panel.add_child(rank_row)
	rank_label = UITheme.title_label("1st", 54, Color.WHITE)
	rank_row.add_child(rank_label)
	rank_total = UITheme.title_label("/1", 32, UITheme.TEXT_DIM)
	rank_total.size_flags_vertical = Control.SIZE_SHRINK_END
	rank_row.add_child(rank_total)
	var toggle := Button.new()
	toggle.text = "≡"
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.custom_minimum_size = Vector2(52, 48)
	toggle.pressed.connect(func(): standings_box.visible = not standings_box.visible)
	rank_row.add_child(toggle)
	standings_panel = PanelContainer.new()
	standings_panel.add_theme_stylebox_override("panel", UITheme.box(Color(0.04, 0.08, 0.22, 0.55), Color(0, 0, 0, 0), 10))
	tl.add_child(standings_panel)
	standings_box = VBoxContainer.new()
	standings_box.add_theme_constant_override("separation", 0)
	standings_panel.add_child(standings_box)

	# --- top-center: lap / time / best
	var tc := PanelContainer.new()
	tc.add_theme_stylebox_override("panel", UITheme.box(Color(0.05, 0.1, 0.28, 0.72), Color(0.3, 0.55, 1.0, 0.6), 14, 2, -0.15))
	tc.set_anchors_preset(Control.PRESET_CENTER_TOP)
	tc.grow_horizontal = Control.GROW_DIRECTION_BOTH
	tc.offset_top = 16
	root.add_child(tc)
	var tch := HBoxContainer.new()
	tch.add_theme_constant_override("separation", 22)
	tc.add_child(tch)
	lap_label = UITheme.title_label("LAP 1/3", 36, Color.WHITE)
	tch.add_child(lap_label)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", -4)
	tch.add_child(tv)
	time_label = UITheme.title_label("00:00.000", 28, Color.WHITE)
	tv.add_child(time_label)
	best_label = UITheme.title_label("BEST --:--.---", 15, UITheme.TEXT_DIM)
	tv.add_child(best_label)

	# --- top-right: minimap + pause
	var tr := HBoxContainer.new()
	tr.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tr.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	tr.offset_top = 16
	tr.offset_right = -20
	tr.alignment = BoxContainer.ALIGNMENT_END
	tr.add_theme_constant_override("separation", 8)
	root.add_child(tr)
	minimap = Minimap.new()
	minimap.custom_minimum_size = Vector2(190, 160)
	tr.add_child(minimap)
	var pause_btn := Button.new()
	pause_btn.text = "II"
	pause_btn.focus_mode = Control.FOCUS_NONE
	pause_btn.custom_minimum_size = Vector2(60, 60)
	pause_btn.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	pause_btn.add_theme_font_override("font", UITheme.display_font())
	pause_btn.pressed.connect(func(): set_paused(true))
	pause_btn.name = "PauseButton"
	tr.add_child(pause_btn)
	net_label = UITheme.label("", 16, UITheme.CYAN, true)
	net_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	net_label.offset_top = 182
	net_label.offset_right = -24
	net_label.offset_left = -360
	net_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(net_label)

	# --- bottom-center: speed + gauges
	var bc := VBoxContainer.new()
	bc.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bc.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bc.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bc.offset_bottom = -18
	bc.alignment = BoxContainer.ALIGNMENT_END
	bc.add_theme_constant_override("separation", 2)
	bc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bc)
	speed_label = UITheme.title_label("0 km/h", 44, Color.WHITE)
	speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bc.add_child(speed_label)
	gauge = Control.new()
	gauge.custom_minimum_size = Vector2(330, 22)
	gauge.draw.connect(_draw_gauge)
	bc.add_child(gauge)
	drift_bar = Control.new()
	drift_bar.custom_minimum_size = Vector2(330, 8)
	drift_bar.draw.connect(_draw_drift)
	bc.add_child(drift_bar)

	# --- centre messages
	center_label = UITheme.title_label("", 130, Color.WHITE)
	center_label.set_anchors_preset(Control.PRESET_CENTER)
	center_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	center_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_label.offset_top = -170
	center_label.offset_bottom = -20
	root.add_child(center_label)
	message_label = UITheme.title_label("", 40, UITheme.ORANGE)
	message_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	message_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.offset_top = 120
	root.add_child(message_label)

	boost_label = UITheme.title_label("", 52, UITheme.CYAN)
	boost_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	boost_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	boost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boost_label.offset_top = -230
	boost_label.offset_bottom = -160
	boost_label.pivot_offset = Vector2(200, 35)
	root.add_child(boost_label)

	hint_label = UITheme.title_label("", 24, UITheme.CYAN)
	hint_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.offset_top = -150
	hint_label.offset_bottom = -118
	root.add_child(hint_label)
	help_panel = _build_help_panel()
	help_panel.visible = false
	root.add_child(help_panel)

	# --- touch controls (bottom corners)
	touch = TouchControls.new()
	touch.name = "TouchControls"
	root.add_child(touch)

	_build_pause()


func _build_help_panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.box(Color(0.03, 0.07, 0.2, 0.82), Color(0.3, 0.6, 1.0, 0.8), 14, 2))
	# Right side under the minimap: keeps the centre (countdown, kart) clear.
	p.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	p.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	p.offset_top = 212
	p.offset_right = -20
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	p.add_child(v)
	var title := UITheme.title_label("PC 조작키  (F1)", 18, UITheme.ORANGE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var g := GridContainer.new()
	g.name = "HelpGrid"
	g.columns = 2
	g.add_theme_constant_override("h_separation", 18)
	g.add_theme_constant_override("v_separation", 2)
	v.add_child(g)
	_fill_help(g)
	return p


func _fill_help(g: GridContainer) -> void:
	for c in g.get_children():
		c.queue_free()
	for line in InputBindings.help_lines():
		var k := UITheme.label(String(line[0]), 15, UITheme.CYAN, true)
		k.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		g.add_child(k)
		g.add_child(UITheme.label(String(line[1]), 14, UITheme.TEXT))


func _build_pause() -> void:
	pause_layer = Control.new()
	pause_layer.theme = GameFlow.ui_theme
	pause_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_layer.visible = false
	add_child(pause_layer)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.02, 0.1, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_layer.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(520, 0)
	pause_layer.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)
	var title := UITheme.title_label("PAUSE", 44)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var note := UITheme.label("", 16, UITheme.TEXT_DIM)
	note.name = "PauseNote"
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(note)
	var cont := UITheme.button("계속하기  CONTINUE", Vector2(460, 66))
	UITheme.style_primary(cont, 26)
	cont.name = "ContinueButton"
	cont.pressed.connect(func(): set_paused(false))
	v.add_child(cont)
	v.add_child(_slider_row("SFX", "sfx_volume"))
	v.add_child(_slider_row("BGM", "bgm_volume"))
	var vib := CheckButton.new()
	vib.text = "진동 VIBRATION"
	vib.button_pressed = bool(SaveSettings.get_value("vibration_enabled"))
	vib.toggled.connect(func(on: bool): SaveSettings.set_value("vibration_enabled", on))
	v.add_child(vib)
	if not OS.has_feature("mobile"):
		var keys := UITheme.label("", 15, UITheme.TEXT_DIM)
		keys.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var parts: Array = []
		for line in InputBindings.help_lines().slice(0, 6):
			parts.append("%s %s" % [line[0], String(line[1]).split(" —")[0]])
		keys.text = "조작키: " + "  ·  ".join(parts) + "\n(설정에서 키를 바꿀 수 있습니다)"
		v.add_child(keys)
	var exit := UITheme.button("나가기  EXIT", Vector2(460, 58))
	exit.name = "ExitButton"
	exit.pressed.connect(func(): confirm_box.visible = true)
	v.add_child(exit)
	confirm_box = HBoxContainer.new()
	confirm_box.visible = false
	(confirm_box as HBoxContainer).alignment = BoxContainer.ALIGNMENT_CENTER
	(confirm_box as HBoxContainer).add_theme_constant_override("separation", 12)
	v.add_child(confirm_box)
	confirm_box.add_child(UITheme.label("정말 나갈까요? (기권 처리)", 18, UITheme.TEXT))
	var yes := UITheme.button("나가기", Vector2(120, 50))
	yes.name = "ConfirmExit"
	yes.pressed.connect(func(): exit_requested.emit())
	confirm_box.add_child(yes)
	var no := UITheme.button("취소", Vector2(100, 50))
	no.pressed.connect(func(): confirm_box.visible = false)
	confirm_box.add_child(no)


func _slider_row(label_text: String, key: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	var l := UITheme.label(label_text, 18, UITheme.TEXT, true)
	l.custom_minimum_size = Vector2(70, 0)
	h.add_child(l)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = float(SaveSettings.get_value(key))
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.value_changed.connect(func(val: float): SaveSettings.set_value(key, val))
	h.add_child(s)
	return h


func set_paused(p: bool) -> void:
	pause_layer.visible = p
	confirm_box.visible = false
	touch.release_all()
	var note := pause_layer.find_child("PauseNote", true, false) as Label
	note.text = "멀티플레이 중에는 경기가 계속 진행됩니다 (자동 주행 유지)." if online else "싱글 경기가 일시정지되었습니다."
	pause_requested.emit(p)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("help"):
		help_panel.visible = not help_panel.visible
		_help_auto_hide = -1.0
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause"):
		set_paused(not pause_layer.visible)
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if pause_layer and not pause_layer.visible and race and race.state == RaceManager.State.RACING:
			set_paused(true)


# ------------------------------------------------------------- updates
func _process(delta: float) -> void:
	if race == null or kart == null:
		return
	var lm: LapManager = race.lap_managers.get(kart)
	if lm:
		lap_label.text = "LAP %d/%d" % [lm.current_lap(), race.laps]
		time_label.text = GameFlow.format_time(race.race_time if not lm.finished else lm.finish_time)
		best_label.text = "BEST " + (GameFlow.format_time(lm.best_lap) if lm.best_lap < INF else "--:--.---")
	var order := race.standings()
	var r := order.find(kart) + 1
	rank_label.text = GameFlow.ordinal(r)
	for i in _standings_rows.size():
		if i < order.size():
			var k := order[i]
			var row := _standings_rows[i]
			var dnf: bool = race.lap_managers[k].dnf
			row.text = "%d  %s%s" % [i + 1, k.display_name, "  DNF" if dnf else ""]
			row.add_theme_color_override("font_color", UITheme.CYAN if k == kart else UITheme.TEXT)
	speed_label.text = "%d km/h" % int(round(kart.speed_kmh()))
	_gauge_value = kart.boost_gauge
	_drift_value = kart.drift.charge if kart.drift.drifting else 0.0
	_drift_col = Color(1.0, 0.65, 0.2)
	if _drift_value >= 0.9:
		_drift_col = UITheme.PURPLE.lightened(0.2)
	elif _drift_value >= 0.45:
		_drift_col = UITheme.CYAN
	gauge.queue_redraw()
	drift_bar.queue_redraw()
	touch.set_boost_fill(kart.boost_gauge)
	_t += delta
	if _help_auto_hide > 0.0:
		_help_auto_hide -= delta
		if _help_auto_hide <= 0.0:
			help_panel.visible = false
	# Context hints: tell the player exactly how to use what they have.
	var hint := ""
	if kart.held_item != "":
		var it: String = GameFlow.item_rules.get("items", {}).get(kart.held_item, {}).get("label", kart.held_item)
		hint = ("[%s] 아이템 사용: %s" % [InputBindings.label_for("use_item"), it]) if desktop else ("ITEM 버튼: %s" % it)
	elif kart.boost_gauge >= 1.0:
		hint = ("BOOST 준비!  [%s]" % InputBindings.label_for("boost")) if desktop else "BOOST 준비!  버튼을 누르세요"
	elif kart.drift.drifting:
		hint = ("드리프트 중… [%s] 떼면 순간 부스터" % InputBindings.primary_label("drift")) if desktop else "드리프트 중… 떼면 순간 부스터"
	hint_label.text = hint
	hint_label.modulate.a = 0.75 + 0.25 * sin(_t * 8.0) if hint.begins_with("BOOST") else 1.0
	if _boost_label_t > 0.0:
		_boost_label_t -= delta
		boost_label.modulate.a = clampf(_boost_label_t / 0.4, 0.0, 1.0)
		boost_label.scale = boost_label.scale.lerp(Vector2.ONE, minf(1.0, delta * 6.0))
	if _msg_timer > 0.0:
		_msg_timer -= delta
		if _msg_timer <= 0.0:
			message_label.text = ""
	if online:
		net_label.text = "LAN · %d명 · 수신 %d" % [Net.players.size(), int(Net.stats["states_recv"])]


func _draw_gauge() -> void:
	var s := gauge.size
	gauge.draw_rect(Rect2(Vector2.ZERO, s), Color(0.02, 0.05, 0.15, 0.75))
	var segs := 6
	var gap := 4.0
	var w := (s.x - gap * (segs + 1)) / segs
	for i in segs:
		var fill := clampf(_gauge_value * segs - i, 0.0, 1.0)
		var r := Rect2(Vector2(gap + i * (w + gap), 4), Vector2(w, s.y - 8))
		gauge.draw_rect(r, Color(0.1, 0.2, 0.4, 0.9))
		if fill > 0.0:
			var col := UITheme.CYAN if _gauge_value < 1.0 else Color(0.6, 0.95, 1.0)
			gauge.draw_rect(Rect2(r.position, Vector2(r.size.x * fill, r.size.y)), col)
	gauge.draw_rect(Rect2(Vector2.ZERO, s), Color(0.3, 0.6, 1.0, 0.8), false, 2.0)


func _draw_drift() -> void:
	var s := drift_bar.size
	if _drift_value <= 0.0:
		return
	drift_bar.draw_rect(Rect2(Vector2.ZERO, s), Color(0.02, 0.05, 0.15, 0.6))
	drift_bar.draw_rect(Rect2(Vector2.ZERO, Vector2(s.x * _drift_value, s.y)), _drift_col)


func show_message(text: String, sec := 2.0, col := UITheme.ORANGE) -> void:
	message_label.text = text
	message_label.add_theme_color_override("font_color", col)
	_msg_timer = sec


func _on_countdown(n: int) -> void:
	if n > 0:
		center_label.text = str(n)
		center_label.add_theme_color_override("font_color", Color.WHITE)
		AudioFeedback.play("beep")
	else:
		center_label.text = "GO!"
		center_label.add_theme_color_override("font_color", UITheme.ORANGE)
		AudioFeedback.play("go")
		get_tree().create_timer(0.9, true, false, true).timeout.connect(_clear_go)


func _on_drift_boost(tier: int) -> void:
	var names := ["", "BOOST!", "SUPER BOOST!", "ULTRA BOOST!"]
	var cols := [Color.WHITE, Color(1.0, 0.7, 0.25), UITheme.CYAN, UITheme.PURPLE.lightened(0.3)]
	boost_label.text = names[clampi(tier, 1, 3)]
	boost_label.add_theme_color_override("font_color", cols[clampi(tier, 1, 3)])
	boost_label.scale = Vector2.ONE * (1.0 + 0.15 * tier)
	boost_label.modulate.a = 1.0
	_boost_label_t = 0.9


func _clear_go() -> void:
	if center_label.text == "GO!":
		center_label.text = ""


func _on_respawned(k: KartController) -> void:
	if k == kart:
		show_message("복귀 중… RECOVERY", 1.5)


func _on_lap(k: KartController, lap: int, lap_time: float) -> void:
	if k != kart:
		return
	if lap == race.laps - 1:
		show_message("FINAL LAP!  " + GameFlow.format_time(lap_time), 2.5, UITheme.PINK)
		AudioFeedback.play("final_lap")
	elif lap < race.laps:
		show_message("LAP %d  %s" % [lap, GameFlow.format_time(lap_time)], 2.0)
		AudioFeedback.play("lap")


func _on_wrong_way(k: KartController, wrong: bool) -> void:
	if k != kart:
		return
	if wrong:
		show_message("역주행!  WRONG WAY", 999.0, UITheme.RED)
		AudioFeedback.play("wrong_way")
	elif message_label.text.begins_with("역주행"):
		message_label.text = ""
		_msg_timer = 0.0


func _on_finished(k: KartController, rank: int, _t: float) -> void:
	if k != kart:
		return
	center_label.text = "FINISH!"
	center_label.add_theme_color_override("font_color", UITheme.ORANGE)
	show_message("%s  —  결과 집계 중…" % GameFlow.ordinal(rank), 999.0, Color.WHITE)
	AudioFeedback.play("finish")
