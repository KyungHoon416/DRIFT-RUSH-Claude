class_name AIDriver
extends Node
## Simple racing-line follower used by bots and by the test autopilot.
## Looks ahead along the centre line, keeps a lane offset, brakes for sharp
## corners, drifts in long bends and uses boost/items.

var kart: KartController
var track: TrackBuilder
var lane := 0.0
var skill := 0.92
var use_drift := true
var use_items := true
var rng := RandomNumberGenerator.new()
var _lane_timer := 0.0
var _item_timer := 0.0


func _ready() -> void:
	if GameFlow.test_mode and kart:
		rng.seed = hash(kart.display_name)   # reproducible test runs
	else:
		rng.randomize()
	lane = rng.randf_range(-3.0, 3.0)


func _physics_process(delta: float) -> void:
	if kart == null or track == null or kart.is_remote:
		return
	var off := track.closest_offset(kart.global_position)
	var look := 9.0 + absf(kart.speed) * 0.55
	var f := track.frame_at(off + look)
	_lane_timer -= delta
	if _lane_timer <= 0.0:
		_lane_timer = rng.randf_range(2.0, 5.0)
		lane = clampf(lane + rng.randf_range(-2.0, 2.0), -4.0, 4.0)
	var target: Vector3 = f["pos"] + f["right"] * lane
	var to := target - kart.global_position
	to.y = 0.0
	var desired := atan2(-to.x, -to.z)
	var diff := wrapf(desired - kart.heading, -PI, PI)
	var steer := -diff * 2.4
	if kart.blind_timer > 0.0:
		steer += sin(Time.get_ticks_msec() * 0.004 + lane) * 0.45   # can't see: wobbles
	kart.steer_input = clampf(steer, -1.0, 1.0)
	# Corner severity ahead
	var a: Vector3 = track.frame_at(off + 6.0)["flat"]
	var b: Vector3 = track.frame_at(off + 6.0 + 18.0 + absf(kart.speed) * 0.6)["flat"]
	var bend := a.angle_to(b)
	var limit := lerpf(1.0, 0.62, clampf((bend - 0.35) / 0.9, 0.0, 1.0)) * kart.max_speed_now()
	kart.brake_input = kart.speed > limit + 2.0 and not kart.drift.drifting
	kart.drift_input = use_drift and bend > 0.7 and kart.speed > 16.0 and absf(kart.steer_input) > 0.35
	if kart.boost_gauge >= 1.0 and bend < 0.2:
		kart.boost_request = true
	if use_items and kart.held_item != "":
		_item_timer += delta
		if _item_timer > rng.randf_range(1.5, 4.0):
			_item_timer = 0.0
			kart.item_request = true
