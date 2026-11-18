extends BaseScreen
## G-07 Garage: choose a kart type (4 bodies with balanced trade-offs), paint
## preset and nickname, with a 360° 3D preview. All karts are free; no paid
## parts or upgrades (stats only trade one strength for another).

var preview: KartPreview
var name_edit: LineEdit
var type_buttons: Dictionary = {}
var stats_box: VBoxContainer
var desc_label: Label
var pending_type := ""
var pending_color := ""


func build() -> void:
	add_header("GARAGE")
	pending_type = String(SaveSettings.get_value("kart_type"))
	pending_color = String(SaveSettings.get_value("kart_color"))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 20)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(h)
	preview = KartPreview.new()
	preview.auto_rotate = true
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	h.add_child(preview)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(430, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	h.add_child(scroll)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 10)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(side)

	side.add_child(UITheme.title_label("KART", 24, UITheme.CYAN))
	var tg := GridContainer.new()
	tg.columns = 2
	tg.add_theme_constant_override("h_separation", 10)
	tg.add_theme_constant_override("v_separation", 10)
	side.add_child(tg)
	for id in GameFlow.KART_TYPES:
		var b := UITheme.button(String(GameFlow.kart_stats.get(id, {}).get("_label", id.to_upper())), Vector2(200, 56))
		b.name = "Kart_" + id
		b.add_theme_font_override("font", UITheme.display_font())
		b.pressed.connect(_pick_type.bind(id))
		tg.add_child(b)
		type_buttons[id] = b
	desc_label = UITheme.label("", 16, UITheme.TEXT_DIM)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(desc_label)
	stats_box = VBoxContainer.new()
	stats_box.add_theme_constant_override("separation", 4)
	side.add_child(stats_box)

	side.add_child(UITheme.title_label("PAINT", 24, UITheme.CYAN))
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 8)
	side.add_child(grid)
	for id in GameFlow.KART_COLORS.keys():
		var b := Button.new()
		b.name = "Color_" + id
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(60, 50)
		var col: Color = GameFlow.KART_COLORS[id]
		b.add_theme_stylebox_override("normal", UITheme.box(col, col.darkened(0.4), 10, 2))
		b.add_theme_stylebox_override("hover", UITheme.box(col.lightened(0.15), Color.WHITE, 10, 3))
		b.add_theme_stylebox_override("pressed", UITheme.box(col, Color.WHITE, 10, 4))
		b.pressed.connect(_pick_color.bind(id))
		grid.add_child(b)

	side.add_child(UITheme.title_label("NICKNAME", 24, UITheme.CYAN))
	name_edit = LineEdit.new()
	name_edit.name = "NicknameEdit"
	name_edit.max_length = 12
	name_edit.text = GameFlow.player_name()
	side.add_child(name_edit)
	var save := UITheme.button("저장  SAVE", Vector2(0, 62))
	save.name = "SaveButton"
	UITheme.style_primary(save, 26)
	save.pressed.connect(_save)
	side.add_child(save)
	side.add_child(UITheme.label("모든 카트는 무료입니다. 능력치는 장단점만 다르고 유료 강화는 없습니다.", 14, UITheme.TEXT_DIM))
	add_status()
	_refresh()


func _pick_type(id: String) -> void:
	pending_type = id
	preview.set_kart_type(id, GameFlow.kart_color(pending_color))
	_refresh()
	set_status("미리보기: %s — 저장을 눌러 적용" % String(GameFlow.kart_stats.get(id, {}).get("_label", id)))


func _pick_color(id: String) -> void:
	pending_color = id
	preview.set_color(GameFlow.kart_color(id))
	set_status("미리보기: %s — 저장을 눌러 적용" % id)


func _refresh() -> void:
	for id in type_buttons.keys():
		UITheme.style_tab(type_buttons[id], id == pending_type)
	desc_label.text = String(GameFlow.kart_stats.get(pending_type, {}).get("_desc", ""))
	for c in stats_box.get_children():
		c.queue_free()
	var r := GameFlow.kart_ratings(pending_type)
	for k in r.keys():
		var row := HBoxContainer.new()
		var l := UITheme.label(String(k), 16, UITheme.TEXT, true)
		l.custom_minimum_size = Vector2(80, 0)
		row.add_child(l)
		var bar := ProgressBar.new()
		bar.name = "Stat_" + String(k)
		bar.min_value = 0.0
		bar.max_value = 1.0
		bar.value = clampf(0.15 + 0.85 * float(r[k]), 0.0, 1.0)
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(250, 16)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.add_theme_stylebox_override("background", UITheme.box(Color(0.06, 0.1, 0.25), Color(0, 0, 0, 0), 6))
		bar.add_theme_stylebox_override("fill", UITheme.box(UITheme.ORANGE, Color(0, 0, 0, 0), 6))
		row.add_child(bar)
		stats_box.add_child(row)


func _save() -> void:
	SaveSettings.set_value("kart_type", pending_type)
	SaveSettings.set_value("kart_color", pending_color)
	var r: Dictionary = await Backend.set_nickname(name_edit.text)
	if SaveSettings.last_save_error != OK:
		set_status("저장 실패 — 기존 차량 설정을 유지합니다.", true)
	elif not r.get("ok", false):
		set_status(Backend.error_text(String(r.get("error", ""))), true)
	else:
		set_status("저장되었습니다.")
