extends Node

func _ready() -> void:
	var d: Node = load("res://Tools/NetTestDriver.gd").new()
	d.name = "NetTestDriver"
	get_tree().root.add_child.call_deferred(d)
