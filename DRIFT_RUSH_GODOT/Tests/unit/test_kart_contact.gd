extends TestCase
## Karts must never drive through each other (rear-end and side-by-side).

var track: TrackBuilder


func _kart(slot_d: float, lateral: float) -> KartController:
	var k: KartController = load("res://Scenes/Vehicles/KartBase.tscn").instantiate()
	k.setup("K", Color.ORANGE, false)
	spawn(k)
	k.place(track.transform_at(slot_d, lateral, 0.05))
	return k


func _setup() -> void:
	track = load("res://Scenes/Tracks/SakuraValley.tscn").instantiate()
	spawn(track)


## Separation in the front kart's frame: (lateral, longitudinal) distance.
func _gap(a: KartController, b: KartController) -> Vector2:
	var d := b.global_position - a.global_position
	var fwd := a.forward()
	var right := fwd.cross(Vector3.UP)
	return Vector2(absf(d.dot(right)), d.dot(fwd))


func test_rear_end_does_not_pass_through() -> void:
	_setup()
	await physics_frames(2)
	var front := _kart(40.0, 0.0)
	var back := _kart(25.0, 0.0)
	await physics_frames(3)
	back.control_enabled = true
	back.speed = 28.0
	var min_long := INF
	for i in 120:
		await tree().physics_frame
		var g := _gap(front, back)
		if g.x < 1.5:
			min_long = minf(min_long, -g.y)   # back kart is behind → negative y
	check(_gap(front, back).y < -2.4, "rear kart stays behind the front kart (gap %.2f m)" % -_gap(front, back).y)
	check(min_long > 2.4, "never overlaps lengthwise (closest %.2f m)" % min_long)


func test_side_by_side_karts_do_not_overlap() -> void:
	_setup()
	await physics_frames(2)
	var a := _kart(30.0, -1.2)
	var b := _kart(30.0, 1.2)
	await physics_frames(3)
	a.control_enabled = true
	b.control_enabled = true
	var min_lat := INF
	for i in 150:
		a.steer_input = 0.6     # steer into each other
		b.steer_input = -0.6
		await tree().physics_frame
		var g := _gap(a, b)
		if absf(g.y) < 2.0:
			min_lat = minf(min_lat, g.x)
	check(min_lat > 1.55, "side-by-side karts keep their bodies apart (closest lateral %.2f m)" % min_lat)
