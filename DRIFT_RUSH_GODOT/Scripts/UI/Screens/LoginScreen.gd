extends BaseScreen
## G-01 Start / login: guest sign-in, (later) Apple/Google linking,
## offline practice fallback, retry with distinct error messages.

var guest_btn: Button
var offline_btn: Button
var busy := false


func build() -> void:
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(center)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	v.custom_minimum_size = Vector2(520, 0)
	center.add_child(v)
	var logo := UITheme.title_label("DRIFT RUSH", 92, UITheme.ORANGE)
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(logo)
	var sub := UITheme.title_label("3D MOBILE KART RACING", 24, UITheme.CYAN)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	guest_btn = UITheme.button("게스트로 시작  START AS GUEST", Vector2(520, 72))
	guest_btn.name = "GuestButton"
	UITheme.style_primary(guest_btn, 26)
	guest_btn.pressed.connect(_on_guest)
	v.add_child(guest_btn)
	var google := UITheme.button("Google 계정 연결 (준비 중)", Vector2(520, 56))
	google.disabled = true
	google.tooltip_text = "Firebase + Google Sign-In 네이티브 플러그인 연동 후 제공"
	v.add_child(google)
	var apple := UITheme.button("Apple로 계속하기 (iOS · 준비 중)", Vector2(520, 56))
	apple.disabled = true
	apple.visible = OS.has_feature("ios") or not OS.has_feature("mobile")
	v.add_child(apple)
	offline_btn = UITheme.button("오프라인 연습  OFFLINE PRACTICE", Vector2(520, 56))
	offline_btn.name = "OfflineButton"
	offline_btn.pressed.connect(_on_offline)
	v.add_child(offline_btn)
	var badge := mock_badge()
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(badge)
	status_label = UITheme.label("", 18, UITheme.TEXT_DIM)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(status_label)


func _on_guest() -> void:
	if busy:
		return
	busy = true
	guest_btn.disabled = true
	set_status("로그인 중…")
	var r: Dictionary = await Backend.sign_in_guest()
	busy = false
	guest_btn.disabled = false
	if r.get("ok", false):
		GameFlow.goto("lobby" if bool(SaveSettings.get_value("tutorial_done")) else "tutorial")
	else:
		set_status(Backend.error_text(String(r.get("error", ""))) + "  다시 시도하거나 오프라인 연습을 이용하세요.", true)
		guest_btn.text = "다시 시도  RETRY"


func _on_offline() -> void:
	Backend.start_offline()
	GameFlow.goto("lobby")
