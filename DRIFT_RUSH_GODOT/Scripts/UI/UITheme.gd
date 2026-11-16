class_name UITheme
extends RefCounted
## Navy + electric-blue UI theme with orange primary buttons (see UI concept).

const NAVY := Color("0b1736")
const NAVY_2 := Color("13285e")
const PANEL := Color(0.07, 0.13, 0.31, 0.88)
const BLUE := Color("2f8cff")
const CYAN := Color("39d3ff")
const ORANGE := Color("ffb21c")
const ORANGE_2 := Color("ff7a00")
const PURPLE := Color("8b3dff")
const PINK := Color("ff6fae")
const GREEN := Color("39d98a")
const RED := Color("ff4d5e")
const TEXT := Color("f4f7ff")
const TEXT_DIM := Color("9fb0d8")

static var _display_font: Font
static var _bold_font: Font


static func display_font() -> Font:
	if _display_font == null:
		var f: FontFile = load("res://Assets/Fonts/RussoOne-Regular.ttf")
		# Korean text / symbols (◀ ▶) fall back to Noto Sans KR.
		f.fallbacks = [load("res://Assets/Fonts/NotoSansKR.ttf")]
		_display_font = f
	return _display_font


static func bold_font() -> Font:
	if _bold_font == null:
		var v := FontVariation.new()
		v.base_font = load("res://Assets/Fonts/NotoSansKR.ttf")
		v.variation_opentype = {"wght": 800}
		_bold_font = v
	return _bold_font


static func box(bg: Color, border := Color(0, 0, 0, 0), radius := 14, border_w := 0, skew := 0.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	sb.anti_aliasing = true
	if skew != 0.0:
		sb.skew = Vector2(skew, 0)
	return sb


static func build() -> Theme:
	var t := Theme.new()
	t.default_font_size = 20
	# Buttons (secondary style: navy with blue border)
	t.set_stylebox("normal", "Button", box(NAVY_2, BLUE, 12, 2))
	t.set_stylebox("hover", "Button", box(NAVY_2.lightened(0.12), CYAN, 12, 2))
	t.set_stylebox("pressed", "Button", box(BLUE.darkened(0.3), CYAN, 12, 3))
	t.set_stylebox("disabled", "Button", box(Color(0.15, 0.18, 0.28, 0.8), Color(0.3, 0.33, 0.45), 12, 2))
	t.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), CYAN, 12, 2))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(0.55, 0.6, 0.72))
	t.set_font("font", "Button", bold_font())
	t.set_font_size("font_size", "Button", 22)
	# Panels
	t.set_stylebox("panel", "PanelContainer", box(PANEL, Color(0.2, 0.45, 1.0, 0.55), 16, 2))
	t.set_stylebox("panel", "Panel", box(PANEL, Color(0.2, 0.45, 1.0, 0.55), 16, 2))
	# Labels
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", Color(0.02, 0.05, 0.15))
	# LineEdit
	t.set_stylebox("normal", "LineEdit", box(Color(0.04, 0.08, 0.2, 0.95), BLUE, 10, 2))
	t.set_stylebox("focus", "LineEdit", box(Color(0.04, 0.08, 0.2, 0.95), CYAN, 10, 2))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_font_size("font_size", "LineEdit", 24)
	# Sliders
	var track := box(Color(0.1, 0.16, 0.36), Color(0, 0, 0, 0), 6)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	t.set_stylebox("slider", "HSlider", track)
	var fill := box(BLUE, Color(0, 0, 0, 0), 6)
	fill.content_margin_top = 4
	fill.content_margin_bottom = 4
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	t.set_icon("grabber", "HSlider", _circle_icon(26, CYAN))
	t.set_icon("grabber_highlight", "HSlider", _circle_icon(28, Color.WHITE))
	# CheckButton / OptionButton use Button styles; tweak option popup
	t.set_stylebox("panel", "PopupMenu", box(NAVY, BLUE, 10, 2))
	t.set_font_size("font_size", "PopupMenu", 22)
	t.set_stylebox("normal", "OptionButton", box(NAVY_2, BLUE, 12, 2))
	t.set_stylebox("hover", "OptionButton", box(NAVY_2.lightened(0.1), CYAN, 12, 2))
	t.set_stylebox("pressed", "OptionButton", box(NAVY_2, CYAN, 12, 2))
	# Scroll
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	# Tooltips etc.
	t.set_stylebox("panel", "TooltipPanel", box(NAVY, BLUE, 8, 1))
	return t


static func _circle_icon(size: int, col: Color) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) / 2.0
	for y in size:
		for x in size:
			var d := Vector2(x - c, y - c).length()
			var a := clampf(c - d + 0.5, 0.0, 1.0)
			img.set_pixel(x, y, Color(col.r, col.g, col.b, a))
	return ImageTexture.create_from_image(img)


## Primary call-to-action style (orange/amber, skewed like the concept art).
static func style_primary(b: Button, font_size := 34) -> void:
	b.add_theme_stylebox_override("normal", box(ORANGE, Color("fff0a8"), 14, 3, -0.12))
	b.add_theme_stylebox_override("hover", box(ORANGE.lightened(0.12), Color.WHITE, 14, 3, -0.12))
	b.add_theme_stylebox_override("pressed", box(ORANGE_2, Color.WHITE, 14, 3, -0.12))
	b.add_theme_stylebox_override("disabled", box(Color(0.45, 0.4, 0.3), Color(0.6, 0.55, 0.4), 14, 2, -0.12))
	b.add_theme_color_override("font_color", Color("1b1530"))
	b.add_theme_color_override("font_hover_color", Color("1b1530"))
	b.add_theme_color_override("font_pressed_color", Color("1b1530"))
	b.add_theme_font_override("font", display_font())
	b.add_theme_font_size_override("font_size", font_size)


static func style_accent(b: Button, col: Color, font_size := 26) -> void:
	b.add_theme_stylebox_override("normal", box(col.darkened(0.15), col.lightened(0.35), 14, 3, -0.12))
	b.add_theme_stylebox_override("hover", box(col, Color.WHITE, 14, 3, -0.12))
	b.add_theme_stylebox_override("pressed", box(col.darkened(0.35), Color.WHITE, 14, 3, -0.12))
	b.add_theme_font_override("font", display_font())
	b.add_theme_font_size_override("font_size", font_size)


static func style_tab(b: Button, active: bool) -> void:
	if active:
		b.add_theme_stylebox_override("normal", box(BLUE, CYAN, 12, 3, -0.12))
		b.add_theme_stylebox_override("hover", box(BLUE.lightened(0.1), Color.WHITE, 12, 3, -0.12))
	else:
		b.add_theme_stylebox_override("normal", box(NAVY_2, Color(0.25, 0.35, 0.6), 12, 2, -0.12))
		b.add_theme_stylebox_override("hover", box(NAVY_2.lightened(0.1), CYAN, 12, 2, -0.12))


static func title_label(text: String, size := 40, col := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", display_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_constant_override("outline_size", 8)
	l.add_theme_color_override("font_outline_color", Color(0.02, 0.05, 0.15))
	return l


static func label(text: String, size := 20, col := TEXT, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if bold:
		l.add_theme_font_override("font", bold_font())
	return l


static func button(text: String, min_size := Vector2(200, 64)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func(): AudioFeedback.play("ui_click"))
	return b


static func panel() -> PanelContainer:
	return PanelContainer.new()


## Full-screen gradient background used by menu screens.
static func background(top := Color("0e2257"), bottom := Color("070d24")) -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, top)
	g.set_color(1, bottom)
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 64
	gt.height = 256
	var tr := TextureRect.new()
	tr.texture = gt
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


## Screen header: back button + skewed title tab.
static func header(title: String, on_back: Callable) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	if on_back.is_valid():
		var back := button("◀", Vector2(72, 60))
		back.add_theme_font_size_override("font_size", 26)
		back.pressed.connect(on_back)
		back.name = "BackButton"
		h.add_child(back)
	var tab := PanelContainer.new()
	tab.add_theme_stylebox_override("panel", box(BLUE.darkened(0.2), CYAN, 12, 2, -0.18))
	var t := title_label(title, 30)
	tab.add_child(t)
	h.add_child(tab)
	return h
