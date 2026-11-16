extends BaseScreen
## G-07 Garage: 360° 3D kart view + paint presets + nickname.
## Cosmetic only (no paid parts / stat upgrades in the MVP).

var preview: KartPreview
var name_edit: LineEdit


func build() -> void:
	add_header("GARAGE")
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 20)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(h)
	preview = KartPreview.new()
	preview.auto_rotate = false
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	h.add_child(preview)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 12)
	side.custom_minimum_size = Vector2(360, 0)
	h.add_child(side)
	side.add_child(UITheme.title_label("PAINT", 26, UITheme.CYAN))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	side.add_child(grid)
	for id in GameFlow.KART_COLORS.keys():
		var b := Button.new()
		b.name = "Color_" + id
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(108, 70)
		var col: Color = GameFlow.KART_COLORS[id]
		var sel: bool = id == String(SaveSettings.get_value("kart_color"))
		b.add_theme_stylebox_override("normal", UITheme.box(col, Color.WHITE if sel else col.darkened(0.4), 12, 4 if sel else 2))
		b.add_theme_stylebox_override("hover", UITheme.box(col.lightened(0.15), Color.WHITE, 12, 3))
		b.add_theme_stylebox_override("pressed", UITheme.box(col, Color.WHITE, 12, 4))
		b.pressed.connect(_pick.bind(id))
		grid.add_child(b)
	side.add_child(UITheme.title_label("NICKNAME", 26, UITheme.CYAN))
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
	side.add_child(UITheme.label("기본 카트 1종 + 외형 색상 프리셋.\n성능에 영향을 주는 강화/유료 부품은 없습니다.", 15, UITheme.TEXT_DIM))
	add_status()


func _pick(id: String) -> void:
	preview.set_color(GameFlow.kart_color(id))
	set_meta("pending_color", id)
	set_status("미리보기: %s — 저장을 눌러 적용" % id)


func _save() -> void:
	var col: String = get_meta("pending_color", SaveSettings.get_value("kart_color"))
	SaveSettings.set_value("kart_color", col)
	var r: Dictionary = await Backend.set_nickname(name_edit.text)
	if SaveSettings.last_save_error != OK:
		set_status("저장 실패 — 기존 차량 설정을 유지합니다.", true)
	elif not r.get("ok", false):
		set_status(Backend.error_text(String(r.get("error", ""))), true)
	else:
		set_status("저장되었습니다.")
