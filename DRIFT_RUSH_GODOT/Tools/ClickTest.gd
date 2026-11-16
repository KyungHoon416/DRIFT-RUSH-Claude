extends Node
## Full real flow: Bootstrap → Login → click → measure time until the next scene shows.

var log_t := 0


func _ready() -> void:
	var d := Node.new()
	d.set_script(load("res://Tools/ClickDriver.gd"))
	get_tree().root.add_child.call_deferred(d)
