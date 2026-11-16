extends BaseScreen
## App entry: shows the logo, restores a saved session (auto-login) and routes
## to the lobby or the login screen.

func build() -> void:
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(center)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(v)
	var logo := UITheme.title_label("DRIFT RUSH", 96, UITheme.ORANGE)
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(logo)
	var sub := UITheme.title_label("3D MOBILE KART RACING", 26, UITheme.CYAN)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	var l := UITheme.label("불러오는 중…", 20, UITheme.TEXT_DIM)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	_route.call_deferred()


func _route() -> void:
	if GameFlow.test_mode:
		return
	var r: Dictionary = await Backend.restore_session()
	GameFlow.goto("lobby" if r.get("ok", false) else "login")
