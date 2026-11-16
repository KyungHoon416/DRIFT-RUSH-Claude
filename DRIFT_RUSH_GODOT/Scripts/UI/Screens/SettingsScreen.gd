extends BaseScreen
## G-12 Settings: steering, vibration, audio, graphics, FPS. Live-applied and
## saved immediately; save failures are reported and the game keeps running.


func build() -> void:
	add_header("SETTINGS", GameFlow.previous_scene if GameFlow.previous_scene in ["lobby", "tutorial", "mode_select"] else "lobby")
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 28)
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(cols)
	var a := _section(cols, "조작 CONTROLS")
	a.add_child(SettingsWidgets.option_row("조향 방식", "control_mode", ["tilt", "touch"], ["기울기", "터치 버튼"]))
	a.add_child(SettingsWidgets.slider_row("모션 감도", "tilt_sensitivity", 0.5, 2.0, 0.05))
	a.add_child(SettingsWidgets.slider_row("데드존°", "tilt_deadzone_deg", 0.0, 10.0, 0.5))
	a.add_child(SettingsWidgets.slider_row("스무딩(s)", "tilt_smoothing", 0.0, 0.3, 0.01))
	a.add_child(SettingsWidgets.check_row("좌우 반전", "tilt_invert"))
	a.add_child(SettingsWidgets.option_row("센서 축", "tilt_axis", ["x", "y"]))
	var cal := UITheme.button("기울기 튜토리얼 / 중립 보정", Vector2(0, 54))
	cal.pressed.connect(func(): GameFlow.goto("tutorial"))
	a.add_child(cal)
	var b := _section(cols, "피드백 · 그래픽")
	b.add_child(SettingsWidgets.check_row("진동", "vibration_enabled"))
	b.add_child(SettingsWidgets.slider_row("진동 강도", "vibration_strength", 0.0, 1.0, 0.05))
	b.add_child(SettingsWidgets.check_row("화면 흔들림", "camera_shake"))
	b.add_child(SettingsWidgets.slider_row("BGM", "bgm_volume", 0.0, 1.0, 0.05))
	b.add_child(SettingsWidgets.slider_row("SFX", "sfx_volume", 0.0, 1.0, 0.05))
	b.add_child(SettingsWidgets.option_row("그래픽 품질", "graphics_quality", ["low", "medium", "high"], ["낮음", "중간", "높음"]))
	b.add_child(SettingsWidgets.option_row("FPS", "fps_target", [30, 60], ["30", "60"]))
	var test_vib := UITheme.button("진동 테스트", Vector2(0, 50))
	test_vib.pressed.connect(func():
		Haptics.reset_cooldown()
		var ok := Haptics.impact("wall", 0.8)
		set_status("진동 요청됨 (%s)" % ("모바일" if Haptics.is_supported() else "PC: 실제 진동 없음") if ok else "진동이 꺼져 있습니다."))
	b.add_child(test_vib)
	var reset := UITheme.button("기본값으로 초기화", Vector2(0, 50))
	reset.pressed.connect(func():
		SaveSettings.reset_to_defaults()
		GameFlow.goto("settings"))
	b.add_child(reset)
	_build_key_section(cols)
	add_status()
	SaveSettings.save_failed.connect(_on_save_failed)


func _on_save_failed(err: int) -> void:
	set_status("설정 저장 실패 (오류 %d). 이번 실행 동안만 적용됩니다." % err, true)


func _section(parent: Control, title: String) -> VBoxContainer:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	p.add_child(v)
	v.add_child(UITheme.title_label(title, 24, UITheme.CYAN))
	return v


# ------------------------------------------------------------- PC key bindings
var _capturing := ""
var _key_buttons: Dictionary = {}


func _build_key_section(cols: Control) -> void:
	var c := _section(cols, "PC 조작키 KEYS")
	c.add_child(UITheme.label("버튼을 누른 뒤 원하는 키를 누르세요 (Esc 취소).\n게임패드: 스틱 조향 · A 드리프트 · Y/RB 부스터 · X/LB 아이템 · B 브레이크", 15, UITheme.TEXT_DIM))
	for action in InputBindings.ACTIONS:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		var l := UITheme.label(String(InputBindings.LABELS[action]), 18, UITheme.TEXT, true)
		l.custom_minimum_size = Vector2(120, 0)
		h.add_child(l)
		var b := UITheme.button("", Vector2(170, 44))
		b.name = "Key_" + String(action)
		b.add_theme_font_size_override("font_size", 18)
		b.pressed.connect(_start_capture.bind(action))
		h.add_child(b)
		_key_buttons[action] = b
		c.add_child(h)
	c.add_child(SettingsWidgets.check_row("레이스 시작 때 조작키 안내", "controls_hint"))
	var reset := UITheme.button("조작키 기본값", Vector2(0, 46))
	reset.name = "ResetKeys"
	reset.pressed.connect(func():
		InputBindings.reset_defaults()
		_refresh_keys()
		set_status("조작키를 기본값으로 되돌렸습니다."))
	c.add_child(reset)
	_refresh_keys()


func _refresh_keys() -> void:
	for action in _key_buttons.keys():
		var b: Button = _key_buttons[action]
		b.text = InputBindings.label_for(action)


func _start_capture(action: String) -> void:
	_capturing = action
	_refresh_keys()
	(_key_buttons[action] as Button).text = "키를 누르세요…"


func _input(event: InputEvent) -> void:
	if _capturing == "" or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	get_viewport().set_input_as_handled()
	var ke := event as InputEventKey
	var action := _capturing
	_capturing = ""
	if ke.physical_keycode == KEY_ESCAPE and action != "pause":
		_refresh_keys()
		set_status("변경을 취소했습니다.")
		return
	var stolen := InputBindings.rebind(action, ke.physical_keycode)
	_refresh_keys()
	var msg := "%s → %s" % [InputBindings.LABELS[action], InputBindings.key_name(ke.physical_keycode)]
	if stolen != "":
		msg += "  (%s에서 이 키를 뺐습니다)" % InputBindings.LABELS[stolen]
	set_status(msg)
