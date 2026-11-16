extends Node

func _ready() -> void:
	_run.call_deferred()


func _wait_scene(name: String, max_frames := 600) -> bool:
	for i in max_frames:
		await get_tree().process_frame
		var cs := get_tree().current_scene
		if cs and cs.name == name:
			return true
	return false


func _click(name: String) -> void:
	var b := get_tree().current_scene.find_child(name, true, false) as Control
	var p := b.get_global_rect().get_center()
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = p
		e.global_position = p
		Input.parse_input_event(e)
		await get_tree().process_frame


func _run() -> void:
	get_tree().change_scene_to_file("res://Scenes/App/Bootstrap.tscn")
	print("FLOW login shown: ", await _wait_scene("Login"))
	var t := Time.get_ticks_msec()
	await _click("OfflineButton")
	var ok: bool = await _wait_scene("Lobby")
	print("FLOW lobby shown: ", ok, " after ", Time.get_ticks_msec() - t, " ms")
	t = Time.get_ticks_msec()
	await _click("PlayButton")
	print("FLOW mode select: ", await _wait_scene("ModeSelect"), " after ", Time.get_ticks_msec() - t, " ms")
	get_tree().quit()
