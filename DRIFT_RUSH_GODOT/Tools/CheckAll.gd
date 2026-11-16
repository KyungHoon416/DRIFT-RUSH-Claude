extends Node
## Loads every script and scene in the project (with autoloads active) so that
## parse/compile errors are reported. Exit code = number of failures.
## Usage: godot --headless --path . res://Tools/CheckAll.tscn

func _ready() -> void:
	var failures := 0
	var files: Array[String] = []
	_collect("res://Scripts", files)
	_collect("res://Scenes", files)
	_collect("res://Tests", files)
	_collect("res://Tools", files)
	for f in files:
		var res := load(f)
		if res == null:
			failures += 1
			print("CHECK FAIL: ", f)
		elif res is GDScript and not (res as GDScript).can_instantiate():
			failures += 1
			print("CHECK FAIL (compile): ", f)
	print("CHECK DONE: %d files, %d failures" % [files.size(), failures])
	get_tree().quit(failures)


func _collect(dir: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for sub in d.get_directories():
		_collect(dir.path_join(sub), out)
	for f in d.get_files():
		if f.ends_with(".gd") or f.ends_with(".tscn"):
			out.append(dir.path_join(f))
