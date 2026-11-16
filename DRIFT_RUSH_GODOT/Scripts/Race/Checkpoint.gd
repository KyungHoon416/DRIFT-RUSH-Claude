class_name Checkpoint
extends Area3D
## Invisible gate across the road. index 0 = start/finish line.

signal kart_passed(kart: KartController, index: int)

var index := 0


func _init(idx := 0) -> void:
	index = idx
	collision_layer = KartController.LAYER_TRIGGERS
	collision_mask = KartController.LAYER_KARTS
	monitoring = true
	monitorable = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if body is KartController:
		kart_passed.emit(body, index)
