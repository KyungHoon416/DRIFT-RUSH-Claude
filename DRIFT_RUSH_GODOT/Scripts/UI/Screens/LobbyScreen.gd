extends BaseScreen
## G-02 Main lobby: real-time 3D kart in a garage, nickname, PLAY / FRIENDS,
## side menu (Lobby, Garage, Shop[준비 중], Rank, Settings).

var preview: KartPreview


func build() -> void:
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	content.add_child(top)
	var tab := PanelContainer.new()
	tab.add_theme_stylebox_override("panel", UITheme.box(UITheme.BLUE.darkened(0.2), UITheme.CYAN, 12, 2, -0.18))
	tab.add_child(UITheme.title_label("LOBBY", 30))
	top.add_child(tab)
	var prof := PanelContainer.new()
	var ph := HBoxContainer.new()
	ph.add_theme_constant_override("separation", 10)
	prof.add_child(ph)
	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(36, 36)
	dot.color = GameFlow.kart_color(String(SaveSettings.get_value("kart_color")))
	ph.add_child(dot)
	var name_l := UITheme.label(GameFlow.player_name(), 22, UITheme.TEXT, true)
	name_l.name = "Nickname"
	ph.add_child(name_l)
	top.add_child(prof)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	top.add_child(mock_badge())

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 18)
	content.add_child(body)
	var menu := VBoxContainer.new()
	menu.add_theme_constant_override("separation", 10)
	body.add_child(menu)
	for item in [["LOBBY", ""], ["GARAGE", "garage"], ["SHOP", "-"], ["RANK", "profile"], ["TUTORIAL", "tutorial"], ["SETTINGS", "settings"]]:
		var b := UITheme.button(item[0], Vector2(190, 58))
		b.add_theme_font_override("font", UITheme.display_font())
		b.name = "Menu" + String(item[0]).capitalize()
		if item[1] == "-":
			b.disabled = true
			b.text = "SHOP (준비 중)"
		elif item[1] == "":
			UITheme.style_tab(b, true)
		else:
			var key: String = item[1]
			b.pressed.connect(func(): GameFlow.goto(key))
		menu.add_child(b)
	preview = KartPreview.new()
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(preview)
	var right := VBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_END
	right.add_theme_constant_override("separation", 14)
	body.add_child(right)
	var play := UITheme.button("PLAY  »", Vector2(300, 96))
	play.name = "PlayButton"
	UITheme.style_primary(play, 44)
	play.pressed.connect(func(): GameFlow.goto("mode_select"))
	right.add_child(play)
	var friends := UITheme.button("FRIENDS", Vector2(300, 70))
	friends.name = "FriendsButton"
	UITheme.style_accent(friends, UITheme.BLUE, 30)
	friends.pressed.connect(func(): GameFlow.goto("room"))
	right.add_child(friends)
	var hint := UITheme.label("드래그해서 카트를 360° 회전", 15, UITheme.TEXT_DIM)
	right.add_child(hint)
	AudioFeedback.play_bgm(true)
