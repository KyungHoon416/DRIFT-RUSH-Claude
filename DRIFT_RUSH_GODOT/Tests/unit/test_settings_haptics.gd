extends TestCase


func test_settings_roundtrip_and_sanitize() -> void:
	var old := SaveSettings.path
	SaveSettings.path = "user://test_roundtrip.cfg"
	SaveSettings.reset_to_defaults()
	SaveSettings.set_value("tilt_sensitivity", 1.7)
	SaveSettings.set_value("tilt_invert", true)
	SaveSettings.set_value("control_mode", "touch")
	SaveSettings.set_value("fps_target", 30)
	SaveSettings.set_value("tilt_sensitivity", 9.0)
	near(float(SaveSettings.get_value("tilt_sensitivity")), 2.0, 0.001, "sensitivity clamped to 2.0")
	SaveSettings.set_value("tilt_sensitivity", 1.7)
	SaveSettings.load_settings()
	near(float(SaveSettings.get_value("tilt_sensitivity")), 1.7, 0.001, "sensitivity persisted")
	eq(SaveSettings.get_value("tilt_invert"), true, "invert persisted")
	eq(SaveSettings.get_value("control_mode"), "touch", "control mode persisted")
	eq(Engine.max_fps, 30, "FPS cap applied")
	SaveSettings.set_value("fps_target", 60)
	SaveSettings.path = old
	SaveSettings.load_settings()


func test_corrupt_settings_fall_back_to_defaults() -> void:
	var old := SaveSettings.path
	var p := "user://test_corrupt.cfg"
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string("[settings\nthis is not = valid ][[")
	f.close()
	var err := SaveSettings.load_settings(p)
	check(err != OK, "corrupt file reported")
	eq(SaveSettings.get_value("control_mode"), "tilt", "defaults used")
	check(FileAccess.file_exists(p + ".bak"), "corrupt file backed up")
	SaveSettings.path = old
	SaveSettings.load_settings()


func test_haptics_rules() -> void:
	var clock := [1000]
	Haptics.time_source = func(): return clock[0]
	Haptics.reset_cooldown()
	SaveSettings.set_value("vibration_enabled", true, false)
	SaveSettings.set_value("vibration_strength", 1.0, false)
	check(not Haptics.impact("wall", 0.05), "tiny impact ignored")
	check(Haptics.impact("wall", 0.9), "strong wall impact vibrates")
	var strong: int = Haptics.last_event["duration_ms"]
	check(not Haptics.impact("wall", 0.9), "cooldown blocks repeats")
	clock[0] += 150
	check(not Haptics.impact("kart", 0.9), "still within 300 ms cooldown")
	clock[0] += 200
	check(Haptics.impact("wall", 0.3), "after cooldown vibrates again")
	check(int(Haptics.last_event["duration_ms"]) < strong, "weaker impact → shorter vibration")
	clock[0] += 400
	SaveSettings.set_value("vibration_strength", 0.5, false)
	Haptics.impact("wall", 0.8)
	near(float(Haptics.last_event["amplitude"]), 0.4, 0.01, "user strength scales amplitude")
	clock[0] += 400
	SaveSettings.set_value("vibration_enabled", false, false)
	check(not Haptics.impact("wall", 1.0), "disabled → no vibration")
	SaveSettings.set_value("vibration_enabled", true, false)
	SaveSettings.set_value("vibration_strength", 1.0, false)
	Haptics.time_source = Callable()
