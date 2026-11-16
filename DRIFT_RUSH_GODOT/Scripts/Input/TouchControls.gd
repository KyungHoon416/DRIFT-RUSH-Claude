class_name TouchControls
extends Control
## Multi-touch virtual buttons (BRAKE / DRIFT / BOOST / ITEM / ◀ ▶).
## Godot's Button controls do not support several simultaneous touches, so
## this control tracks InputEventScreenTouch/Drag indices itself and presses
## InputMap actions. With "emulate_touch_from_mouse" the mouse works too.

signal button_pressed(action: String)

class VButton:
	extends Control
	var action := ""
	var text := ""
	var sub := ""
	var color := Color.WHITE
	var radius := 60.0
	var pressed := false
	var enabled := true
	var fill := 0.0          # 0..1 ring (boost gauge)
	var badge := ""

	func _init(a: String, t: String, c: Color, r: float) -> void:
		action = a
		text = t
		color = c
		radius = r
		custom_minimum_size = Vector2(r * 2.0, r * 2.0)
		size = custom_minimum_size
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func hit(p: Vector2) -> bool:
		return visible and enabled and (p - (global_position + size / 2.0)).length() <= radius * 1.12

	func _draw() -> void:
		var c := size / 2.0
		var col := color if enabled else Color(0.4, 0.42, 0.5)
		var a := 0.95 if pressed else 0.72
		draw_circle(c, radius, Color(0.03, 0.06, 0.16, 0.55))
		draw_circle(c, radius * (0.9 if pressed else 0.94), Color(col.r, col.g, col.b, a * 0.55))
		draw_arc(c, radius - 3.0, 0, TAU, 48, Color(col.lightened(0.4), a), 5.0, true)
		if fill > 0.0:
			draw_arc(c, radius + 6.0, -PI / 2.0, -PI / 2.0 + TAU * clampf(fill, 0.0, 1.0), 48, Color(0.35, 0.85, 1.0, 0.95), 7.0, true)
		var f := UITheme.display_font()
		var fs := int(radius * (0.42 if text.length() > 2 else 0.8))
		var ts := f.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
		draw_string_outline(f, Vector2(c.x - ts.x / 2.0, c.y + fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0.02, 0.04, 0.12))
		draw_string(f, Vector2(c.x - ts.x / 2.0, c.y + fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
		if sub != "":
			var ss := int(radius * 0.22)
			var sw := f.get_string_size(sub, HORIZONTAL_ALIGNMENT_CENTER, -1, ss)
			draw_string(f, Vector2(c.x - sw.x / 2.0, c.y + radius * 0.62), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, ss, Color(1, 1, 1, 0.85))
		if badge != "":
			draw_circle(c + Vector2(radius * 0.7, -radius * 0.7), radius * 0.28, Color(1.0, 0.75, 0.1))
			var bs := int(radius * 0.3)
			var bw := f.get_string_size(badge, HORIZONTAL_ALIGNMENT_CENTER, -1, bs)
			draw_string(f, c + Vector2(radius * 0.7 - bw.x / 2.0, -radius * 0.7 + bs * 0.35), badge, HORIZONTAL_ALIGNMENT_LEFT, -1, bs, Color(0.1, 0.05, 0.2))


var buttons: Dictionary = {}       # action -> VButton
var _touch_map: Dictionary = {}    # touch index -> action
var show_steer := false
var show_item := false
var margins := {"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add("brake", "BRAKE", Color(0.75, 0.78, 0.9), 62.0)
	_add("drift", "DRIFT", UITheme.PURPLE, 84.0)
	_add("boost", "BOOST", UITheme.BLUE, 56.0)
	_add("use_item", "ITEM", UITheme.ORANGE, 50.0)
	_add("steer_left", "◀", UITheme.CYAN, 58.0)
	_add("steer_right", "▶", UITheme.CYAN, 58.0)
	resized.connect(layout)
	layout()


func _add(action: String, text: String, col: Color, r: float) -> void:
	var b := VButton.new(action, text, col, r)
	b.name = action
	add_child(b)
	buttons[action] = b


func configure(steer_buttons: bool, item_button: bool) -> void:
	show_steer = steer_buttons
	show_item = item_button
	layout()


func layout() -> void:
	var s := size
	if s.x <= 0:
		return
	var ml := 28.0 + float(margins["left"])
	var mr := 28.0 + float(margins["right"])
	var mb := 22.0 + float(margins["bottom"])
	var drift: VButton = buttons["drift"]
	drift.position = Vector2(s.x - mr - drift.size.x, s.y - mb - drift.size.y)
	var boost: VButton = buttons["boost"]
	boost.position = Vector2(drift.position.x - boost.size.x - 26.0, s.y - mb - boost.size.y - 10.0)
	var left: VButton = buttons["steer_left"]
	var right: VButton = buttons["steer_right"]
	left.visible = show_steer
	right.visible = show_steer
	var brake: VButton = buttons["brake"]
	var item: VButton = buttons["use_item"]
	item.visible = show_item
	if show_steer:
		left.position = Vector2(ml, s.y - mb - left.size.y)
		right.position = Vector2(left.position.x + left.size.x + 22.0, s.y - mb - right.size.y)
		brake.position = Vector2(ml + 10.0, left.position.y - brake.size.y - 26.0)
		item.position = Vector2(brake.position.x + brake.size.x + 24.0, brake.position.y + 10.0)
	else:
		brake.position = Vector2(ml, s.y - mb - brake.size.y)
		item.position = Vector2(brake.position.x + brake.size.x + 24.0, s.y - mb - item.size.y - 8.0)


func set_boost_fill(v: float) -> void:
	var b: VButton = buttons["boost"]
	if absf(b.fill - v) > 0.005:
		b.fill = v
		b.enabled = true
		b.sub = "READY" if v >= 1.0 else ""
		b.queue_redraw()


func set_item(item_label: String) -> void:
	var b: VButton = buttons["use_item"]
	b.text = "ITEM" if item_label == "" else item_label.substr(0, 7)
	b.enabled = item_label != ""
	b.queue_redraw()


const MOUSE_INDEX := -100


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	# Desktop: drive the virtual buttons with the mouse directly (touch emulation
	# is off so normal UI buttons always receive plain mouse clicks).
	if event is InputEventMouseButton and not OS.has_feature("mobile"):
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				for action in buttons.keys():
					if (buttons[action] as VButton).hit(mb.position):
						_press(MOUSE_INDEX, action)
						get_viewport().set_input_as_handled()
						break
			else:
				_release(MOUSE_INDEX)
		return
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			for action in buttons.keys():
				var b: VButton = buttons[action]
				if b.hit(st.position):
					_press(st.index, action)
					get_viewport().set_input_as_handled()
					break
		else:
			_release(st.index)
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		# Allow sliding a thumb between ◀ and ▶ (and off a button = release).
		var now := ""
		for action in buttons.keys():
			if (buttons[action] as VButton).hit(sd.position):
				now = action
				break
		var prev: String = _touch_map.get(sd.index, "")
		if now != prev:
			_release(sd.index)
			if now != "":
				_press(sd.index, now)


func _press(index: int, action: String) -> void:
	_touch_map[index] = action
	Input.action_press(action)
	var b: VButton = buttons[action]
	b.pressed = true
	b.queue_redraw()
	button_pressed.emit(action)


func _release(index: int) -> void:
	if not _touch_map.has(index):
		return
	var action: String = _touch_map[index]
	_touch_map.erase(index)
	if not _touch_map.values().has(action):
		Input.action_release(action)
		var b: VButton = buttons[action]
		b.pressed = false
		b.queue_redraw()


func release_all() -> void:
	for idx in _touch_map.keys():
		_release(idx)
