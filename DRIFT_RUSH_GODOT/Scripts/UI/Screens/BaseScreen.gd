class_name BaseScreen
extends Control
## Common menu screen scaffolding: gradient background, safe-area margins,
## header with back button, a content root, status/error line.

var content: VBoxContainer
var safe: MarginContainer
var status_label: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = GameFlow.ui_theme
	add_child(UITheme.background())
	safe = MarginContainer.new()
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var m := GameFlow.safe_margins(get_viewport())
	safe.add_theme_constant_override("margin_left", int(28 + m["left"]))
	safe.add_theme_constant_override("margin_right", int(28 + m["right"]))
	safe.add_theme_constant_override("margin_top", int(20 + m["top"]))
	safe.add_theme_constant_override("margin_bottom", int(18 + m["bottom"]))
	add_child(safe)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	safe.add_child(content)
	build()


## Override.
func build() -> void:
	pass


func add_header(title: String, back_to := "lobby") -> HBoxContainer:
	var cb := Callable()
	if back_to != "":
		cb = func(): go_back(back_to)
	var h := UITheme.header(title, cb)
	content.add_child(h)
	return h


func go_back(key: String) -> void:
	GameFlow.goto(key)


func add_status() -> Label:
	status_label = UITheme.label("", 18, UITheme.TEXT_DIM)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.name = "Status"
	content.add_child(status_label)
	return status_label


func set_status(text: String, error := false) -> void:
	if status_label:
		status_label.text = text
		status_label.add_theme_color_override("font_color", UITheme.RED if error else UITheme.TEXT_DIM)


func mock_badge() -> Label:
	var l := UITheme.label("", 15, UITheme.ORANGE, true)
	if Backend.mode == "mock":
		l.text = "MOCK 백엔드 · Firebase 미연결"
	else:
		l.text = "Firebase 연결 설정됨"
		l.add_theme_color_override("font_color", UITheme.GREEN)
	return l


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		var back := find_child("BackButton", true, false) as Button
		if back:
			back.pressed.emit()
