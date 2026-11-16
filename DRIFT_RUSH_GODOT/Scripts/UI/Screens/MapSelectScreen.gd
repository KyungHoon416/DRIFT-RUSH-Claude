extends BaseScreen
## G-06 Map select: Sakura Valley / Neon City cards with a preview drawn from
## the real track curve, difficulty, curvature and measured length.

var cards: Dictionary = {}


class TrackOutline:
	extends Control
	var pts := PackedVector2Array()
	var col := Color.WHITE
	var bg_top := Color.BLACK
	var bg_bottom := Color.BLACK

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, bg_bottom)
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, size.y * 0.5)), bg_top)
		if pts.size() < 2:
			return
		var mn := Vector2(INF, INF)
		var mx := Vector2(-INF, -INF)
		for p in pts:
			mn = mn.min(p)
			mx = mx.max(p)
		var span := mx - mn
		var s := minf((size.x - 40) / span.x, (size.y - 40) / span.y)
		var off := (size - span * s) / 2.0
		var poly := PackedVector2Array()
		for p in pts:
			poly.append((p - mn) * s + off)
		draw_polyline(poly, Color(0, 0, 0, 0.6), 14.0, true)
		draw_polyline(poly, col, 8.0, true)
		draw_circle(poly[0], 8.0, Color.WHITE)


func build() -> void:
	add_header("MAP SELECT", "mode_select")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(row)
	for id in GameFlow.maps.keys():
		row.add_child(_card(id))
	add_status()
	_refresh()


func _card(id: String) -> Control:
	var info: Dictionary = GameFlow.maps[id]
	var b := Button.new()
	b.name = "Card_" + id
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(500, 420)
	b.toggle_mode = true
	b.pressed.connect(_choose.bind(id))
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 14
	v.offset_right = -14
	v.offset_top = 14
	v.offset_bottom = -14
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var outline := TrackOutline.new()
	outline.custom_minimum_size = Vector2(0, 250)
	outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var neon := id == "neon_city"
	outline.col = Color(0.3, 0.9, 1.0) if neon else Color(1.0, 0.6, 0.8)
	outline.bg_top = Color(0.12, 0.05, 0.3) if neon else Color(0.55, 0.78, 1.0)
	outline.bg_bottom = Color(0.08, 0.06, 0.18) if neon else Color(0.6, 0.85, 0.5)
	# Measure the real track by instancing its definition (no rendering).
	var length := 0.0
	var track: TrackBuilder = load(String(info["scene"])).instantiate()
	track._define_track()
	var pts := PackedVector3Array()
	for p in track.control_points:
		pts.append(Vector3(p.x * track.xz_scale, p.y, p.z * track.xz_scale))
	var curve := TrackBuilder.make_closed_curve(pts)
	length = curve.get_baked_length()
	var d := 0.0
	while d <= length:
		var p := curve.sample_baked(d)
		outline.pts.append(Vector2(p.x, p.z))
		d += 8.0
	track.free()
	v.add_child(outline)
	v.add_child(UITheme.title_label(String(info["name"]), 32, Color.WHITE))
	var dots := ""
	for i in 5:
		dots += "●" if i < int(info.get("difficulty", 1)) else "○"
	v.add_child(UITheme.label("난이도 %s   곡률 %s" % [dots, info.get("curvature", "")], 18, UITheme.TEXT, true))
	v.add_child(UITheme.label("트랙 길이 %.2f km (실측) · 3 LAP" % (length / 1000.0), 18, UITheme.TEXT_DIM))
	var status_text := "완성" if info.get("status") == "complete" else "플레이 가능 (프로토타입)"
	v.add_child(UITheme.label(status_text, 16, UITheme.GREEN if info.get("status") == "complete" else UITheme.ORANGE, true))
	cards[id] = b
	return b


func _choose(id: String) -> void:
	SaveSettings.set_value("selected_map", id)
	if Net.is_host():
		Net.update_room_settings({"map": id})
	_refresh()
	set_status("%s 선택됨" % GameFlow.maps[id]["name"])


func _refresh() -> void:
	var sel := String(SaveSettings.get_value("selected_map"))
	for id in cards.keys():
		var b: Button = cards[id]
		b.button_pressed = id == sel
		b.add_theme_stylebox_override("normal", UITheme.box(UITheme.NAVY_2, UITheme.CYAN if id == sel else Color(0.25, 0.35, 0.6), 18, 5 if id == sel else 2))
		b.add_theme_stylebox_override("pressed", UITheme.box(UITheme.NAVY_2, UITheme.CYAN, 18, 5))
		b.add_theme_stylebox_override("hover", UITheme.box(UITheme.NAVY_2.lightened(0.08), UITheme.CYAN, 18, 3))
