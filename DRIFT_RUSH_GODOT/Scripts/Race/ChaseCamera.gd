class_name ChaseCamera
extends Camera3D
## Third-person chase camera behind the kart.
## - Yaw follows the kart with exponential smoothing (less motion sickness).
## - During drifts it blends toward travel direction instead of nose direction.
## - Ray-cast to walls so the camera never ends up behind/inside geometry.
## - Speed/boost FOV, tiny bounded shake on impacts (can be disabled).

var target: KartController
var distance := 5.2
var height := 2.15
var look_ahead := 5.0
var look_height := 1.1
var yaw_smooth := 5.0
var pos_smooth := 14.0
var base_fov := 70.0
var _yaw := 0.0
var _shake := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	fov = base_fov
	near = 0.1
	far = 1500.0


func snap() -> void:
	if target == null:
		return
	_yaw = target.heading
	global_position = _desired_position()
	_look()


func add_shake(amount: float) -> void:
	if bool(SaveSettings.get_value("camera_shake")):
		_shake = minf(0.35, _shake + amount)


func _desired_position() -> Vector3:
	var back := Vector3(sin(_yaw), 0.0, cos(_yaw))
	return target.global_position + back * distance + Vector3.UP * height


func _physics_process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var yaw_target := target.heading
	if target.drift.drifting:
		yaw_target = lerp_angle(target.heading, target.travel_heading, 0.6)
	_yaw = lerp_angle(_yaw, yaw_target, 1.0 - exp(-yaw_smooth * delta))
	var desired := _desired_position()
	var from := target.global_position + Vector3.UP * 1.3
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, desired, KartController.LAYER_WALLS | KartController.LAYER_WORLD)
	q.exclude = [target.get_rid()]
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		desired = hit["position"] + hit["normal"] * 0.4
	global_position = global_position.lerp(desired, 1.0 - exp(-pos_smooth * delta))
	# never go under the road surface
	if global_position.y < target.global_position.y + 0.6:
		global_position.y = target.global_position.y + 0.6
	_look()
	_hide_blocking_karts()
	var ratio := clampf(absf(target.speed) / 30.0, 0.0, 1.5)
	var target_fov := base_fov + ratio * 6.0 + (8.0 if target.boost.active else 0.0)
	fov = lerpf(fov, target_fov, 1.0 - exp(-4.0 * delta))
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 1.8)
		h_offset = _rng.randf_range(-1.0, 1.0) * _shake * 0.3
		v_offset = _rng.randf_range(-1.0, 1.0) * _shake * 0.2
	else:
		h_offset = 0.0
		v_offset = 0.0


func _look() -> void:
	var fwd := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	var tgt := target.global_position + fwd * look_ahead + Vector3.UP * look_height
	if global_position.distance_to(tgt) > 0.01:
		look_at(tgt, Vector3.UP)


## Other karts right in front of the lens would fill the screen: hide them
## while they are closer than HIDE_DIST to the camera.
const HIDE_DIST := 3.4


func _hide_blocking_karts() -> void:
	for n in get_tree().get_nodes_in_group("karts"):
		var k := n as KartController
		if k == null or k == target or k.model == null:
			continue
		k.model.visible = global_position.distance_to(k.global_position + Vector3.UP * 0.8) > HIDE_DIST
