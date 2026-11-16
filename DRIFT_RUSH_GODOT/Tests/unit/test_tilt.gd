extends TestCase
## TiltSteering math (sensor values are simulated; real devices unverified).


func _t() -> TiltSteering:
	var t := TiltSteering.new()
	t.sensitivity = 1.0
	t.deadzone_deg = 3.0
	t.max_angle_deg = 28.0
	t.smoothing = 0.0
	t.invert = false
	t.axis = "x"
	t.neutral_deg = 0.0
	return t


func _g(roll_deg: float, pitch_back_deg := 35.0) -> Vector3:
	# Gravity for a landscape phone rolled by roll_deg and tipped back by pitch.
	var r := deg_to_rad(roll_deg)
	var p := deg_to_rad(pitch_back_deg)
	return Vector3(sin(r), -cos(r) * cos(p), -cos(r) * sin(p)) * 9.81


func test_roll_angle_independent_of_pitch() -> void:
	near(TiltSteering.roll_deg(_g(15, 10)), 15.0, 0.2, "roll at pitch 10")
	near(TiltSteering.roll_deg(_g(15, 60)), 15.0, 0.2, "roll at pitch 60")
	near(TiltSteering.roll_deg(_g(-20, 35)), -20.0, 0.2, "negative roll")


func test_deadzone_sensitivity_clamp_invert() -> void:
	var t := _t()
	eq(t.map_angle(2.0), 0.0, "inside deadzone → 0")
	near(t.map_angle(28.0), 1.0, 0.001, "max angle → full lock")
	near(t.map_angle(-15.5), -0.5, 0.001, "half way (left)")
	eq(t.map_angle(80.0), 1.0, "clamped to 1")
	t.sensitivity = 2.0
	near(t.map_angle(15.5), 1.0, 0.001, "sensitivity 2 doubles response")
	t.sensitivity = 0.5
	near(t.map_angle(28.0), 0.5, 0.001, "sensitivity 0.5 halves response")
	t.sensitivity = 1.0
	t.invert = true
	near(t.map_angle(15.5), -0.5, 0.001, "invert flips sign")


func test_calibration_sets_neutral() -> void:
	var t := _t()
	t.calibrate(_g(12.0))
	near(t.neutral_deg, 12.0, 0.2, "neutral from current pose")
	eq(t.update(_g(12.0), 0.016), 0.0, "neutral pose steers straight")
	check(t.update(_g(30.0), 0.016) > 0.5, "tilt relative to neutral steers right")


func test_no_sensor_returns_zero() -> void:
	var t := _t()
	check(not TiltSteering.has_sensor(Vector3.ZERO), "zero vector = no sensor (desktop)")
	eq(t.update(Vector3.ZERO, 0.016), 0.0, "no steering without sensor")


func test_smoothing_and_resume_suppression() -> void:
	var t := _t()
	t.smoothing = 0.1
	var v1 := t.update(_g(28.0), 0.016)
	check(v1 > 0.0 and v1 < 0.5, "smoothing ramps gradually (%.2f)" % v1)
	for i in 60:
		t.update(_g(28.0), 0.016)
	check(t.value > 0.95, "converges to target")
	t.reset_smoothing(0.3)
	eq(t.value, 0.0, "resume resets output")
	t.update(_g(28.0), 0.1)
	near(t.value, 0.0, 0.001, "suppressed right after resume")
