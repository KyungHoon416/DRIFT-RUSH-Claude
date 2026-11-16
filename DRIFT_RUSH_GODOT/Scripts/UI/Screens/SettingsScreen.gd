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
