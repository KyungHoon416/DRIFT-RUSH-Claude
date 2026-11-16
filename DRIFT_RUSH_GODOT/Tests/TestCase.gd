class_name TestCase
extends RefCounted
## Minimal test base. Methods named test_* are run by Tests/TestRunner.gd
## (they may await frames). Use check/eq/near; failures are collected.

var runner: Node
var failures: Array[String] = []
var current := ""
var checks := 0
var _spawned: Array[Node] = []


func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures.append("%s: %s" % [current, msg])


func eq(a: Variant, b: Variant, msg := "") -> void:
	check(a == b, "%s (expected %s, got %s)" % [msg, str(b), str(a)])


func near(a: float, b: float, eps: float, msg := "") -> void:
	check(absf(a - b) <= eps, "%s (expected %.4f ± %.4f, got %.4f)" % [msg, b, eps, a])


func tree() -> SceneTree:
	return runner.get_tree()


func physics_frames(n: int) -> void:
	for i in n:
		await tree().physics_frame


func frames(n: int) -> void:
	for i in n:
		await tree().process_frame


func spawn(node: Node) -> Node:
	runner.add_child(node)
	_spawned.append(node)
	return node


func cleanup() -> void:
	for n in _spawned:
		if is_instance_valid(n):
			n.queue_free()
	_spawned.clear()


func before_each() -> void:
	pass
