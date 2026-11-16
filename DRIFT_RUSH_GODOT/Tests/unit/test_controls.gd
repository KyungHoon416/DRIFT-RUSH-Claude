extends TestCase
## PC key bindings, re-binding, gamepad mapping, smoothed keyboard steering.


func before_each() -> void:
	InputBindings.reset_defaults()


func _has_key(action: String, key: int) -> bool:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey and (ev as InputEventKey).physical_keycode == key:
			return true
	return false


func test_default_layout() -> void:
	check(_has_key("steer_left", KEY_LEFT) and _has_key("steer_left", KEY_A), "steer left ← / A")
	check(_has_key("drift", KEY_SHIFT) and _has_key("drift", KEY_SPACE), "drift Shift / Space")
	check(_has_key("boost", KEY_UP) and _has_key("boost", KEY_W), "boost ↑ / W")
	check(_has_key("use_item", KEY_CTRL) and _has_key("use_item", KEY_E), "item Ctrl / E")
	check(_has_key("respawn", KEY_R), "respawn R")
	check(_has_key("help", KEY_F1), "help F1")
	var pad := false
	for ev in InputMap.action_get_events("drift"):
		if ev is InputEventJoypadButton:
			pad = true
	check(pad, "gamepad button mapped for drift")
	eq(InputBindings.label_for("boost"), "↑ / W", "HUD label for boost")


func test_rebind_moves_key_and_persists() -> void:
	var stolen := InputBindings.rebind("boost", KEY_E)   # E was the item key
	eq(stolen, "use_item", "key taken from the item action")
	check(_has_key("boost", KEY_E), "boost now on E")
	check(not _has_key("use_item", KEY_E), "item no longer on E")
	check(_has_key("use_item", KEY_CTRL), "item keeps Ctrl")
	SaveSettings.load_settings()
	InputBindings.apply()
	check(_has_key("boost", KEY_E), "binding survives reload")
	InputBindings.reset_defaults()
	check(_has_key("use_item", KEY_E), "reset restores defaults")


func test_keyboard_steering_is_smoothed() -> void:
	var track: TrackBuilder = load("res://Scenes/Tracks/SakuraValley.tscn").instantiate()
	spawn(track)
	var k: KartController = load("res://Scenes/Vehicles/KartBase.tscn").instantiate()
	spawn(k)
	k.place(track.grid_transform(0))
	var pi := PlayerInput.new()
	pi.kart = k
	k.add_child(pi)
	Input.action_press("steer_right")
	await physics_frames(2)
	var early := k.steer_input
	await physics_frames(12)
	var later := k.steer_input
	Input.action_release("steer_right")
	await physics_frames(12)
	check(early > 0.0 and early < 0.5, "tap gives a partial turn first (%.2f)" % early)
	near(later, 1.0, 0.01, "holding reaches full lock")
	near(k.steer_input, 0.0, 0.01, "returns to centre after release")
