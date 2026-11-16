extends BaseScreen
## G-08 Tilt tutorial: live tilt angle + steering preview, neutral calibration,
## sensitivity, invert, axis, touch fallback, sensor availability notice.

var tilt := TiltSteering.new()
var angle_label: Label
var sensor_label: Label
var meter: Control
var wheel: Control
var _steer := 0.0


func build() -> void:
	add_header("TILT TUTORIAL", "lobby")
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 24)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(h)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 10)
	h.add_child(left)
	left.add_child(UITheme.label("휴대폰을 핸들처럼 좌우로 기울이면 카트가 회전합니다.\n편하게 쥔 자세에서 [중립 보정]을 눌러 주세요.", 20))
	wheel = Control.new()
	wheel.custom_minimum_size = Vector2(0, 230)
	wheel.draw.connect(_draw_wheel)
	left.add_child(wheel)
	angle_label = UITheme.title_label("0.0°", 30)
	angle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(angle_label)
	meter = Control.new()
	meter.custom_minimum_size = Vector2(0, 36)
	meter.draw.connect(_draw_meter)
	left.add_child(meter)
	sensor_label = UITheme.label("", 17, UITheme.ORANGE, true)
	sensor_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(sensor_label)
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(400, 0)
	right.add_theme_constant_override("separation", 10)
	h.add_child(right)
	var cal := UITheme.button("중립 보정  CALIBRATE", Vector2(0, 66))
	cal.name = "CalibrateButton"
	UITheme.style_accent(cal, UITheme.BLUE, 24)
	cal.pressed.connect(_calibrate)
	right.add_child(cal)
	right.add_child(SettingsWidgets.slider_row("감도", "tilt_sensitivity", 0.5, 2.0, 0.05))
	right.add_child(SettingsWidgets.slider_row("데드존°", "tilt_deadzone_deg", 0.0, 10.0, 0.5))
	right.add_child(SettingsWidgets.check_row("좌우 반전", "tilt_invert"))
	right.add_child(SettingsWidgets.option_row("센서 축", "tilt_axis", ["x", "y"]))
	right.add_child(SettingsWidgets.option_row("조향 방식", "control_mode", ["tilt", "touch"], ["기울기", "터치 버튼"]))
	var go := UITheme.button("연습 주행  PRACTICE »", Vector2(0, 76))
	go.name = "PracticeButton"
	UITheme.style_primary(go, 28)
	go.pressed.connect(func():
		SaveSettings.set_value("tutorial_done", true)
		GameFlow.start_offline_race("practice", String(SaveSettings.get_value("selected_map")), 0, 3))
	right.add_child(go)
	SaveSettings.changed.connect(_on_setting)
	tilt.load_from_settings()


func _on_setting(_k: String, _v: Variant) -> void:
	tilt.load_from_settings()


func _calibrate() -> void:
	var g := Input.get_gravity()
	if not TiltSteering.has_sensor(g):
		sensor_label.text = "센서 값이 없어 보정할 수 없습니다. 터치 조향을 사용하세요."
		return
	tilt.calibrate(g)
	SaveSettings.set_value("tilt_neutral_deg", tilt.neutral_deg)
	sensor_label.text = "중립 보정 완료 (%.1f°)" % tilt.neutral_deg


func _process(delta: float) -> void:
	var g := Input.get_gravity()
	var has := TiltSteering.has_sensor(g)
	if has:
		_steer = tilt.update(g, delta)
		angle_label.text = "%.1f°  →  조향 %+.2f" % [tilt.raw_deg - tilt.neutral_deg, _steer]
		if not sensor_label.text.begins_with("중립"):
			sensor_label.text = ""
	else:
		_steer = Input.get_axis("steer_left", "steer_right")
		angle_label.text = "센서 없음 · 키보드 %+.2f" % _steer
		sensor_label.text = "이 기기에서 기울기 센서를 찾지 못했습니다 (PC/에디터는 정상). 조향 방식을 '터치 버튼'으로 바꾸거나 A/D·←/→ 키를 사용하세요."
	wheel.queue_redraw()
	meter.queue_redraw()


func _draw_wheel() -> void:
	var c := wheel.size / 2.0
	var r := minf(c.x, c.y) - 10.0
	wheel.draw_circle(c, r, Color(0.05, 0.1, 0.25, 0.8))
	wheel.draw_arc(c, r, 0, TAU, 64, UITheme.CYAN, 6.0, true)
	var ang := _steer * deg_to_rad(90.0)
	var dir := Vector2(sin(ang), -cos(ang))
	wheel.draw_line(c, c + dir * r, Color.WHITE, 8.0, true)
	wheel.draw_line(c - dir.orthogonal() * r, c + dir.orthogonal() * r, Color(1, 1, 1, 0.6), 6.0, true)
	wheel.draw_circle(c, 18.0, UITheme.ORANGE)


func _draw_meter() -> void:
	var s := meter.size
	meter.draw_rect(Rect2(Vector2.ZERO, s), Color(0.04, 0.08, 0.2))
	var mid := s.x / 2.0
	var w := _steer * mid
	meter.draw_rect(Rect2(Vector2(mid + minf(0.0, w), 4), Vector2(absf(w), s.y - 8)), UITheme.CYAN)
	meter.draw_line(Vector2(mid, 0), Vector2(mid, s.y), Color.WHITE, 2.0)
